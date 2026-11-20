unit Infra.Search.Fts5SearchIndex;

{ ISearchIndex over the FTS5 tables of library.db (Slovo_02 "Пошукові запити").

  Table choice (B-28/B-31):
    WordForms = False -> ParagraphsFTS / VersesFTS, one query;
    WordForms = True  -> ParagraphsStem_<lang> / VersesStem_<lang>, one query per
                         language among the modules in scope. A language without
                         a stemmed table silently falls back to the exact table
                         (logged once per session).
  Two steps, no limit (B-34):
    Count*  - the rowids of all matches, one query per table (language group),
              counted per chapter / Bible book here; the rows of all groups in
              one array;
    Search* - one window LIMIT / OFFSET in text order or by bm25. Its modules
              must belong to one table: ranks of different tables are not
              comparable and an offset has no meaning across them.

  The rowid is the address (R8-03). The producer numbers Paragraphs.Id and
  Verses.Id in text order: a module is one run of ids, inside it the chapters
  (Bible books) follow in their order, inside them the paragraphs (verses).
  So a chapter, a Bible book and a module are ranges of rowids, and a match is
  placed by its rowid alone - no JOIN for every match, and text order is the
  order FTS5 gives the rows in. The ranges are read once, before the first
  search, and the numbering is checked there: a library that breaks it answers
  every search with reModuleCorrupted (the reason is in the log). The Id itself
  still never leaves this unit (B-21).

  Matches are marked with char(2)/char(3) by snippet()/highlight() and cut out
  here, so offsets are UTF-16 code units of the clean text (B-24). Synchronous;
  between calls it keeps only the ranges and the table names (C-08, C-21). }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Core.Domain,
  Core.Catalog,
  Core.Contracts,
  Infra.SQLite.LibraryDatabase;

type
  TMatchMode = (
    mmAllWords,       // every word somewhere in the text, any order
    mmExactPhrase,    // words in this exact order (in a stemmed table: a phrase of stems)
    mmPrefix          // RESERVED for CountPrefix (Sprint 3): '*' on the last term
  );

// Every term in double quotes, inner quotes doubled (B-12).
function SanitizeFtsTerm(const Term: string): string;

// False = nothing to search for (empty or whitespace only): the caller does NOT
// query the database and answers with an empty page.
function TryBuildMatchQuery(const RawText: string; Mode: TMatchMode;
  out MatchExpr: string): Boolean;

// Removes the char(2)/char(3) markers; returns the match ranges in Clean.
function ExtractHighlights(const Marked: string; out Clean: string): TArray<TSearchHighlight>;

type
  TFts5SearchIndex = class(TInterfacedObject, ISearchIndex)
  private type
    TSearchGroup = record
      Table: string;
      Language: string;
      ModuleIds: TArray<TModuleId>;   // empty = no IN filter (whole table)
    end;
    // R8-03: the rows of a chapter (books) or of a Bible book - one range of rowids.
    TUnitRange = record
      ModuleId: TModuleId;
      ChapterOrder: Integer;          // books
      BookCode: TBookCode;            // Bible
      Place: Integer;                 // ChapterOrder / OrderInModule: its place in the module
      FirstId, LastId: Int64;
    end;
    TIdRange = record
      FirstId, LastId: Int64;
    end;
  private
    FDatabase: TLibraryDatabase;      // not owned
    FCatalog: TLibraryCatalog;        // not owned
    FLogger: ILogger;
    FTables: TDictionary<string, Boolean>;
    FWarnedLanguages: TList<string>;
    // R8-03, read by NeedRanges: units by FirstId, their keys, the range of every module.
    FRangesLoaded: Boolean;
    FRangesProblem: string;           // <> '' - the library breaks the numbering
    FBookUnits, FBibleUnits: TArray<TUnitRange>;
    FBookKeys, FBibleKeys: TDictionary<string, Integer>;
    FModuleRanges: TDictionary<TModuleId, TIdRange>;

    procedure NeedRanges;
    function LoadUnits(Kind: TContentKind): TArray<TUnitRange>;
    procedure IndexUnits(const Units: TArray<TUnitRange>; Keys: TDictionary<string, Integer>);
    class function UnitKey(const ModuleId: TModuleId; const Part: string): string; static;
    // Matches per unit of Units (same indexes), over the tables of the query's scope.
    function CountPerUnit(Kind: TContentKind; const Units: TArray<TUnitRange>;
      const Query: TSearchQuery; const MatchExpr: string): TArray<Integer>;
    // The units with matches, by module and then by their place in it.
    function UnitsWithMatches(const Units: TArray<TUnitRange>; const Totals: TArray<Integer>): TArray<Integer>;

    procedure LoadTableNames;
    function TableFor(Kind: TContentKind; WordForms: Boolean; const Language: string): string;
    function PlanGroups(Kind: TContentKind; const Query: TSearchQuery): TArray<TSearchGroup>;
    function ModuleLanguage(const Id: TModuleId; out Module: TModule): Boolean;
    class function LanguageRank(const Language: string): Integer; static;
    class function InClause(Count, FirstParam: Integer): string; static;
    // The one table of a window; False = Error (reNone: nothing to search in).
    function PlanWindow(Kind: TContentKind; const Query: TSearchQuery; const Window: TSearchWindow;
      out Group: TSearchGroup; out Error: TResultError): Boolean;
  public
    constructor Create(ADatabase: TLibraryDatabase; ACatalog: TLibraryCatalog; const ALogger: ILogger);
    destructor Destroy; override;

    function CountBook(const Query: TSearchQuery): TResult<TArray<TBookHitCount>>;
    function CountBible(const Query: TSearchQuery): TResult<TArray<TBibleHitCount>>;
    function SearchBook(const Query: TSearchQuery; const Window: TSearchWindow): TResult<TArray<TBookSearchResult>>;
    function SearchBible(const Query: TSearchQuery; const Window: TSearchWindow): TResult<TArray<TBibleSearchResult>>;
    function FindInChapter(const Query: TSearchQuery; const Ref: TChapterRef): TResult<TArray<TParagraphHit>>;
    function FindInBibleChapter(const Query: TSearchQuery; const Ref: TBibleChapterRef): TResult<TArray<TVerseHit>>;
  end;

implementation

uses
  System.Generics.Defaults,
  Infrastructure.SQLite3.Api,
  Infrastructure.SQLite3.Database;

const
  MarkOpen = #2;
  MarkClose = #3;
  // As many words as a wide search panel can show (E-22); the list cuts what
  // does not fit. 64 is the limit of FTS5.
  SnippetTokens = 32;

  // Word separators in a query: pasted text brings non-breaking spaces,
  // a multi-line field brings tabs and line breaks (R4-52).
  WordSeparators: array[0..4] of Char = (' ', #9, #10, #13, #$00A0);

function SanitizeFtsTerm(const Term: string): string;
begin
  Result := '"' + StringReplace(Term, '"', '""', [rfReplaceAll]) + '"';
end;

function TryBuildMatchQuery(const RawText: string; Mode: TMatchMode;
  out MatchExpr: string): Boolean;
var
  Normalized: string;
  Words, Sanitized: TArray<string>;
  I: Integer;
begin
  MatchExpr := '';
  // Trim does not remove #$00A0 - every separator becomes a plain space first.
  Normalized := RawText;
  for var C in WordSeparators do
    Normalized := Normalized.Replace(C, ' ');
  Normalized := Normalized.Trim;
  if Normalized.IsEmpty then
    Exit(False);

  if Mode = mmExactPhrase then
  begin
    Words := Normalized.Split([' '], TStringSplitOptions.ExcludeEmpty);
    MatchExpr := SanitizeFtsTerm(string.Join(' ', Words));
    Exit(True);
  end;

  Words := Normalized.Split([' '], TStringSplitOptions.ExcludeEmpty);
  SetLength(Sanitized, Length(Words));
  for I := 0 to High(Words) do
    Sanitized[I] := SanitizeFtsTerm(Words[I]);
  if Mode = mmPrefix then
    Sanitized[High(Sanitized)] := Sanitized[High(Sanitized)] + '*';
  MatchExpr := string.Join(' ', Sanitized);
  Result := True;
end;

function ExtractHighlights(const Marked: string; out Clean: string): TArray<TSearchHighlight>;
var
  SB: TStringBuilder;
  Start: Integer;
  H: TSearchHighlight;
  C: Char;
begin
  Result := nil;
  Start := -1;
  SB := TStringBuilder.Create(Length(Marked));
  try
    for C in Marked do
      case C of
        MarkOpen:
          Start := SB.Length;                 // 0-based UTF-16 offset in the clean text
        MarkClose:
          if Start >= 0 then
          begin
            H.StartOffset := Start;
            H.Len := SB.Length - Start;
            Result := Result + [H];
            Start := -1;
          end;
      else
        SB.Append(C);
      end;
    Clean := SB.ToString;
  finally
    SB.Free;
  end;
end;

function MatchModeOf(const Query: TSearchQuery): TMatchMode;
begin
  if Query.ExactPhrase then
    Result := mmExactPhrase
  else
    Result := mmAllWords;
end;

{ TFts5SearchIndex }

constructor TFts5SearchIndex.Create(ADatabase: TLibraryDatabase;
  ACatalog: TLibraryCatalog; const ALogger: ILogger);
begin
  inherited Create;
  FDatabase := ADatabase;
  FCatalog := ACatalog;
  FLogger := ALogger;
  FWarnedLanguages := TList<string>.Create;
  FBookKeys := TDictionary<string, Integer>.Create;
  FBibleKeys := TDictionary<string, Integer>.Create;
  FModuleRanges := TDictionary<TModuleId, TIdRange>.Create;
end;

destructor TFts5SearchIndex.Destroy;
begin
  FModuleRanges.Free;
  FBibleKeys.Free;
  FBookKeys.Free;
  FWarnedLanguages.Free;
  FTables.Free;
  inherited;
end;

// ---------------------------------------------------------------- ranges (R8-03)

class function TFts5SearchIndex.UnitKey(const ModuleId: TModuleId; const Part: string): string;
begin
  Result := string(ModuleId) + #1 + Part;
end;

// The units of one kind, sorted by FirstId. Raises when the numbering is not
// the text order (see the unit header).
function TFts5SearchIndex.LoadUnits(Kind: TContentKind): TArray<TUnitRange>;
const
  RangesSQL: array[TContentKind] of string = (
    'SELECT ModuleId, ChapterOrder, MIN(Id), MAX(Id) FROM Paragraphs GROUP BY ModuleId, ChapterOrder;',
    'SELECT ModuleId, BookCode, MIN(Id), MAX(Id) FROM Verses GROUP BY ModuleId, BookCode;');
  // Rows whose Id is not above the Id of the row before them in the text.
  DisorderSQL: array[TContentKind] of string = (
    'SELECT COUNT(*) FROM (SELECT Id, LAG(Id) OVER ' +
    '(PARTITION BY ModuleId, ChapterOrder ORDER BY LogicalIndex) AS Prev FROM Paragraphs) ' +
    'WHERE Id <= Prev;',
    'SELECT COUNT(*) FROM (SELECT Id, LAG(Id) OVER ' +
    '(PARTITION BY ModuleId, BookCode ORDER BY ChapterNumber, VerseNumber) AS Prev FROM Verses) ' +
    'WHERE Id <= Prev;');
  TableName: array[TContentKind] of string = ('Paragraphs', 'Verses');
var
  Stmt: TSQLiteStatement;
  List: TList<TUnitRange>;
  U: TUnitRange;
  Book: TBookInfo;
  Seen: TDictionary<TModuleId, Boolean>;
  Range: TIdRange;
  Disorder: Int64;
  I: Integer;
begin
  List := TList<TUnitRange>.Create;
  try
    Stmt := FDatabase.Connection.Prepare(RangesSQL[Kind]);
    try
      while Stmt.Step do
      begin
        U := Default(TUnitRange);
        U.ModuleId := Stmt.ColumnText(0);
        if Kind = ckBook then
        begin
          U.ChapterOrder := Stmt.ColumnInt(1);
          U.Place := U.ChapterOrder;
        end
        else
        begin
          U.BookCode := Stmt.ColumnText(1);
          U.Place := -1;
          for Book in FCatalog.Books(U.ModuleId) do
            if Book.Ref.BookCode = U.BookCode then
              U.Place := Book.OrderInModule;
          if U.Place < 0 then
            raise ESQLiteError.Create(Format('Verses of %s:%s have no row in Books',
              [string(U.ModuleId), string(U.BookCode)]), SQLITE_CORRUPT, SQLITE_CORRUPT);
        end;
        U.FirstId := Stmt.ColumnInt64(2);
        U.LastId := Stmt.ColumnInt64(3);
        List.Add(U);
      end;
    finally
      Stmt.Free;
    end;

    List.Sort(TComparer<TUnitRange>.Construct(
      function(const L, R: TUnitRange): Integer
      begin
        if L.FirstId < R.FirstId then
          Result := -1
        else if L.FirstId > R.FirstId then
          Result := 1
        else
          Result := 0;
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;

  // A module is one run of ids, and its units follow in their order.
  Seen := TDictionary<TModuleId, Boolean>.Create;
  try
    for I := 0 to High(Result) do
    begin
      U := Result[I];
      if (I > 0) and (Result[I - 1].LastId >= U.FirstId) then
        raise ESQLiteError.Create(Format('%s.Id is not in text order: the ids of %s and %s overlap',
          [TableName[Kind], string(Result[I - 1].ModuleId), string(U.ModuleId)]),
          SQLITE_CORRUPT, SQLITE_CORRUPT);
      if (I > 0) and (Result[I - 1].ModuleId = U.ModuleId) then
      begin
        if Result[I - 1].Place >= U.Place then
          raise ESQLiteError.Create(Format('%s.Id is not in text order: module %s, unit %d after %d',
            [TableName[Kind], string(U.ModuleId), U.Place, Result[I - 1].Place]),
            SQLITE_CORRUPT, SQLITE_CORRUPT);
        Range := FModuleRanges[U.ModuleId];
        Range.LastId := U.LastId;
        FModuleRanges[U.ModuleId] := Range;
      end
      else
      begin
        if Seen.ContainsKey(U.ModuleId) or FModuleRanges.ContainsKey(U.ModuleId) then
          raise ESQLiteError.Create(Format('%s.Id is not in text order: module %s is not one run of ids',
            [TableName[Kind], string(U.ModuleId)]), SQLITE_CORRUPT, SQLITE_CORRUPT);
        Seen.Add(U.ModuleId, True);
        Range.FirstId := U.FirstId;
        Range.LastId := U.LastId;
        FModuleRanges.Add(U.ModuleId, Range);
      end;
    end;
  finally
    Seen.Free;
  end;

  // Inside a unit: paragraphs by LogicalIndex, verses by chapter and number.
  Disorder := FDatabase.Connection.QueryInt64(DisorderSQL[Kind], 0);
  if Disorder > 0 then
    raise ESQLiteError.Create(Format('%s.Id is not in text order: %d rows inside their chapters',
      [TableName[Kind], Disorder]), SQLITE_CORRUPT, SQLITE_CORRUPT);
end;

procedure TFts5SearchIndex.IndexUnits(const Units: TArray<TUnitRange>;
  Keys: TDictionary<string, Integer>);
var
  I: Integer;
begin
  Keys.Clear;
  for I := 0 to High(Units) do
    if Units[I].BookCode <> '' then
      Keys.AddOrSetValue(UnitKey(Units[I].ModuleId, string(Units[I].BookCode)), I)
    else
      Keys.AddOrSetValue(UnitKey(Units[I].ModuleId, IntToStr(Units[I].ChapterOrder)), I);
end;

// Once, before the first search. A library that breaks the numbering is
// remembered as such: every later call raises the same error without reading again.
procedure TFts5SearchIndex.NeedRanges;
begin
  if FRangesProblem <> '' then
    raise ESQLiteError.Create(FRangesProblem, SQLITE_CORRUPT, SQLITE_CORRUPT);
  if FRangesLoaded then
    Exit;
  try
    FModuleRanges.Clear;
    FBookUnits := LoadUnits(ckBook);
    FBibleUnits := LoadUnits(ckBibleTranslation);
    IndexUnits(FBookUnits, FBookKeys);
    IndexUnits(FBibleUnits, FBibleKeys);
    FRangesLoaded := True;
  except
    on E: ESQLiteError do
    begin
      if E.ErrorCode = SQLITE_CORRUPT then
        FRangesProblem := E.Message;
      raise;
    end;
  end;
end;

function TFts5SearchIndex.CountPerUnit(Kind: TContentKind; const Units: TArray<TUnitRange>;
  const Query: TSearchQuery; const MatchExpr: string): TArray<Integer>;
var
  G: TSearchGroup;
  Stmt: TSQLiteStatement;
  Scope: TDictionary<TModuleId, Boolean>;
  InScope: TArray<Boolean>;
  Id: Int64;
  ModuleId: TModuleId;
  I, U: Integer;
begin
  SetLength(Result, Length(Units));
  SetLength(InScope, Length(Units));
  for G in PlanGroups(Kind, Query) do
  begin
    // Which units this table answers for: all, or those of the group's modules.
    Scope := TDictionary<TModuleId, Boolean>.Create;
    try
      for ModuleId in G.ModuleIds do
        Scope.AddOrSetValue(ModuleId, True);
      for I := 0 to High(Units) do
        InScope[I] := (Length(G.ModuleIds) = 0) or Scope.ContainsKey(Units[I].ModuleId);
    finally
      Scope.Free;
    end;

    // G.Table is one of our own fixed names (TableFor), never user input.
    // The rowids come ascending, as the units are sorted: one pass over both.
    Stmt := FDatabase.Connection.Prepare(Format(
      'SELECT rowid FROM %0:s WHERE %0:s MATCH ?1 ORDER BY rowid;', [G.Table]));
    try
      Stmt.BindText(1, MatchExpr);
      U := 0;
      while Stmt.Step do
      begin
        Id := Stmt.ColumnInt64(0);
        while (U <= High(Units)) and (Units[U].LastId < Id) do
          Inc(U);
        if U > High(Units) then
          Break;
        if (Id >= Units[U].FirstId) and InScope[U] then
          Inc(Result[U]);
      end;
    finally
      Stmt.Free;
    end;
  end;
end;

function TFts5SearchIndex.UnitsWithMatches(const Units: TArray<TUnitRange>;
  const Totals: TArray<Integer>): TArray<Integer>;
var
  Sorted: TArray<TUnitRange>;
  List: TList<Integer>;
  I: Integer;
begin
  Sorted := Units;                    // a local for the comparer to capture
  List := TList<Integer>.Create;
  try
    for I := 0 to High(Totals) do
      if Totals[I] > 0 then
        List.Add(I);
    List.Sort(TComparer<Integer>.Construct(
      function(const L, R: Integer): Integer
      begin
        Result := CompareStr(string(Sorted[L].ModuleId), string(Sorted[R].ModuleId));
        if Result = 0 then
          Result := Sorted[L].Place - Sorted[R].Place;
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

procedure TFts5SearchIndex.LoadTableNames;
var
  Stmt: TSQLiteStatement;
begin
  if FTables <> nil then
    Exit;
  FTables := TDictionary<string, Boolean>.Create;
  Stmt := FDatabase.Connection.Prepare(
    'SELECT name FROM sqlite_master WHERE type = ''table'' AND name GLOB ''*Stem_*'';');
  try
    while Stmt.Step do
      FTables.AddOrSetValue(Stmt.ColumnText(0), True);
  finally
    Stmt.Free;
  end;
end;

function TFts5SearchIndex.TableFor(Kind: TContentKind; WordForms: Boolean;
  const Language: string): string;
var
  Base: string;
begin
  if Kind = ckBook then
    Base := 'Paragraphs'
  else
    Base := 'Verses';
  if WordForms then
  begin
    LoadTableNames;
    Result := Base + 'Stem_' + Language;
    if FTables.ContainsKey(Result) then
      Exit;
    // Language without a stemmer: exact table, logged once per session.
    if not FWarnedLanguages.Contains(Base + ':' + Language) then
    begin
      FWarnedLanguages.Add(Base + ':' + Language);
      FLogger.LogError('Search', Format(
        'No %s table for language "%s": word forms fall back to exact search', [Result, Language]));
    end;
  end;
  Result := Base + 'FTS';
end;

function TFts5SearchIndex.ModuleLanguage(const Id: TModuleId; out Module: TModule): Boolean;
begin
  Result := FCatalog.FindModule(Id, Module);
end;

class function TFts5SearchIndex.LanguageRank(const Language: string): Integer;
begin
  if Language = 'uk' then
    Result := 0
  else if Language = 'ru' then
    Result := 1
  else if Language = 'en' then
    Result := 2
  else
    Result := 3;
end;

class function TFts5SearchIndex.InClause(Count, FirstParam: Integer): string;
var
  Params: TArray<string>;
  I: Integer;
begin
  SetLength(Params, Count);
  for I := 0 to Count - 1 do
    Params[I] := '?' + IntToStr(FirstParam + I);
  Result := 'IN (' + string.Join(', ', Params) + ')';
end;

function TFts5SearchIndex.PlanGroups(Kind: TContentKind;
  const Query: TSearchQuery): TArray<TSearchGroup>;
var
  WholeLibrary: Boolean;
  Scope: TList<TModule>;
  ByTable: TDictionary<string, Integer>;
  Groups: TList<TSearchGroup>;
  M: TModule;
  Id: TModuleId;
  Table: string;
  G: TSearchGroup;
  Index: Integer;
begin
  WholeLibrary := Length(Query.ModuleIds) = 0;
  Scope := TList<TModule>.Create;
  ByTable := TDictionary<string, Integer>.Create;
  Groups := TList<TSearchGroup>.Create;
  try
    // Modules of this kind in scope. Unknown ids and the other kind are skipped:
    // they have no rows in this table anyway (R4-23).
    if WholeLibrary then
    begin
      for M in FCatalog.Modules do
        if M.Kind = Kind then
          Scope.Add(M);
    end
    else
      for Id in Query.ModuleIds do
        if ModuleLanguage(Id, M) and (M.Kind = Kind) then
          Scope.Add(M);

    for M in Scope do
    begin
      Table := TableFor(Kind, Query.WordForms, M.Language);
      if not ByTable.TryGetValue(Table, Index) then
      begin
        G := Default(TSearchGroup);
        G.Table := Table;
        G.Language := M.Language;
        Index := Groups.Count;
        Groups.Add(G);
        ByTable.Add(Table, Index);
      end;
      G := Groups[Index];
      G.ModuleIds := G.ModuleIds + [M.Id];
      Groups[Index] := G;
    end;

    // A whole-library search needs no IN filter when the table holds nothing but
    // this kind and (for stemmed tables) this language. A fallback to the exact
    // table mixes languages, so it keeps its IN list.
    if WholeLibrary then
      for Index := 0 to Groups.Count - 1 do
      begin
        G := Groups[Index];
        if G.Table.Contains('Stem_') or (Groups.Count = 1) then
        begin
          G.ModuleIds := nil;
          Groups[Index] := G;
        end;
      end;

    Groups.Sort(TComparer<TSearchGroup>.Construct(
      function(const L, R: TSearchGroup): Integer
      begin
        Result := LanguageRank(L.Language) - LanguageRank(R.Language);
        if Result = 0 then
          Result := CompareStr(L.Language, R.Language);
      end));
    Result := Groups.ToArray;
  finally
    Groups.Free;
    ByTable.Free;
    Scope.Free;
  end;
end;

function TFts5SearchIndex.CountBook(const Query: TSearchQuery): TResult<TArray<TBookHitCount>>;
var
  MatchExpr: string;
  Counts: TArray<TBookHitCount>;
  Totals: TArray<Integer>;
  Item: TBookHitCount;
  U: Integer;
begin
  Counts := nil;
  if not TryBuildMatchQuery(Query.Text, MatchModeOf(Query), MatchExpr) then
    Exit(TResult<TArray<TBookHitCount>>.Success(Counts));
  try
    NeedRanges;
    Totals := CountPerUnit(ckBook, FBookUnits, Query, MatchExpr);
    for U in UnitsWithMatches(FBookUnits, Totals) do
    begin
      Item.ModuleId := FBookUnits[U].ModuleId;
      Item.ChapterOrder := FBookUnits[U].ChapterOrder;
      Item.Count := Totals[U];
      Counts := Counts + [Item];
    end;
    Result := TResult<TArray<TBookHitCount>>.Success(Counts);
  except
    on E: Exception do
    begin
      FLogger.LogError('Search', Format('CountBook "%s": %s: %s', [Query.Text, E.ClassName, E.Message]));
      Result := TResult<TArray<TBookHitCount>>.Failure(SQLiteErrorToResult(E));
    end;
  end;
end;

function TFts5SearchIndex.CountBible(const Query: TSearchQuery): TResult<TArray<TBibleHitCount>>;
var
  MatchExpr: string;
  Counts: TArray<TBibleHitCount>;
  Totals: TArray<Integer>;
  Item: TBibleHitCount;
  U: Integer;
begin
  Counts := nil;
  if not TryBuildMatchQuery(Query.Text, MatchModeOf(Query), MatchExpr) then
    Exit(TResult<TArray<TBibleHitCount>>.Success(Counts));
  try
    NeedRanges;
    Totals := CountPerUnit(ckBibleTranslation, FBibleUnits, Query, MatchExpr);
    for U in UnitsWithMatches(FBibleUnits, Totals) do
    begin
      Item.ModuleId := FBibleUnits[U].ModuleId;
      Item.BookCode := FBibleUnits[U].BookCode;
      Item.Count := Totals[U];
      Counts := Counts + [Item];
    end;
    Result := TResult<TArray<TBibleHitCount>>.Success(Counts);
  except
    on E: Exception do
    begin
      FLogger.LogError('Search', Format('CountBible "%s": %s: %s', [Query.Text, E.ClassName, E.Message]));
      Result := TResult<TArray<TBibleHitCount>>.Failure(SQLiteErrorToResult(E));
    end;
  end;
end;

// A window is one query on one table. No modules of this kind in the scope is
// not an error - there is nothing to search in (Error = reNone).
function TFts5SearchIndex.PlanWindow(Kind: TContentKind; const Query: TSearchQuery;
  const Window: TSearchWindow; out Group: TSearchGroup; out Error: TResultError): Boolean;
var
  Groups: TArray<TSearchGroup>;
begin
  Group := Default(TSearchGroup);
  Error := reNone;
  Result := False;
  if (Length(Query.ModuleIds) = 0) or (Window.Offset < 0) then
  begin
    Error := reInvalidQuery;
    FLogger.LogError('Search', 'A window of results needs its modules and a non-negative offset');
    Exit;
  end;
  Groups := PlanGroups(Kind, Query);
  if Length(Groups) = 0 then
    Exit;
  if Length(Groups) > 1 then
  begin
    Error := reInvalidQuery;
    FLogger.LogError('Search', Format(
      'A window of results over %d tables (%s, %s, ...): its modules must share one',
      [Length(Groups), Groups[0].Table, Groups[1].Table]));
    Exit;
  end;
  Group := Groups[0];
  Result := True;
end;

function TFts5SearchIndex.SearchBook(const Query: TSearchQuery;
  const Window: TSearchWindow): TResult<TArray<TBookSearchResult>>;
var
  MatchExpr, SQL: string;
  Items: TArray<TBookSearchResult>;
  I, N: Integer;
  G: TSearchGroup;
  Error: TResultError;
  Stmt: TSQLiteStatement;
  Item: TBookSearchResult;
  Range: TIdRange;
  ByRange: Boolean;
begin
  Items := nil;
  if (Window.Count <= 0) or not TryBuildMatchQuery(Query.Text, MatchModeOf(Query), MatchExpr) then
    Exit(TResult<TArray<TBookSearchResult>>.Success(Items));
  try
    if not PlanWindow(ckBook, Query, Window, G, Error) then
    begin
      if Error = reNone then
        Exit(TResult<TArray<TBookSearchResult>>.Success(Items));
      Exit(TResult<TArray<TBookSearchResult>>.Failure(Error));
    end;
    NeedRanges;
    N := Length(G.ModuleIds);
    // R8-03: one book in text order is its range of rowids, in the order FTS5
    // gives them - no filter after the match and nothing to sort.
    ByRange := (Window.Order = soText) and (N = 1);
    if ByRange and not FModuleRanges.TryGetValue(G.ModuleIds[0], Range) then
      Exit(TResult<TArray<TBookSearchResult>>.Success(Items));   // a book without paragraphs
    // G.Table is one of our own fixed names (TableFor), never user input.
    SQL := Format(
      'SELECT p.ModuleId, p.ChapterOrder, p.LogicalIndex, p.StartPageNumber, p.ParagraphOnPage, ' +
      'snippet(%0:s, 0, char(2), char(3), ''…'', %1:d) ' +
      'FROM %0:s JOIN Paragraphs p ON p.Id = %0:s.rowid ' +
      'WHERE %0:s MATCH ?1', [G.Table, SnippetTokens]);
    if ByRange then
    begin
      N := 2;                                // ?2, ?3 - the range
      SQL := SQL + Format(' AND %0:s.rowid BETWEEN ?2 AND ?3 ORDER BY %0:s.rowid', [G.Table]);
    end
    else
    begin
      SQL := SQL + ' AND p.ModuleId ' + InClause(N, 2);
      // The rowid breaks ties of equal ranks: windows must not overlap or skip rows.
      if Window.Order = soRelevance then
        SQL := SQL + Format(' ORDER BY rank, %s.rowid', [G.Table])
      else
        SQL := SQL + ' ORDER BY p.ModuleId, p.ChapterOrder, p.LogicalIndex';
    end;
    SQL := SQL + Format(' LIMIT ?%d OFFSET ?%d;', [N + 2, N + 3]);

    Stmt := FDatabase.Connection.Prepare(SQL);
    try
      Stmt.BindText(1, MatchExpr);
      if ByRange then
        Stmt.BindInt64(2, Range.FirstId).BindInt64(3, Range.LastId)
      else
        for I := 0 to N - 1 do
          Stmt.BindText(I + 2, G.ModuleIds[I]);
      Stmt.BindInt(N + 2, Window.Count);
      Stmt.BindInt(N + 3, Window.Offset);
      while Stmt.Step do
      begin
        Item := Default(TBookSearchResult);
        Item.Ref.Chapter.ModuleId := Stmt.ColumnText(0);
        Item.Ref.Chapter.ChapterOrder := Stmt.ColumnInt(1);
        Item.Ref.LogicalIndex := Stmt.ColumnInt(2);
        Item.PageNumber := Stmt.ColumnInt(3);
        Item.ParagraphOnPage := Stmt.ColumnInt(4);
        Item.Highlights := ExtractHighlights(Stmt.ColumnText(5), Item.Snippet);
        Items := Items + [Item];
      end;
    finally
      Stmt.Free;
    end;
    Result := TResult<TArray<TBookSearchResult>>.Success(Items);
  except
    on E: Exception do
    begin
      FLogger.LogError('Search', Format('SearchBook "%s": %s: %s', [Query.Text, E.ClassName, E.Message]));
      Result := TResult<TArray<TBookSearchResult>>.Failure(SQLiteErrorToResult(E));
    end;
  end;
end;

function TFts5SearchIndex.SearchBible(const Query: TSearchQuery;
  const Window: TSearchWindow): TResult<TArray<TBibleSearchResult>>;
var
  MatchExpr, SQL: string;
  Items: TArray<TBibleSearchResult>;
  I, N: Integer;
  G: TSearchGroup;
  Error: TResultError;
  Stmt: TSQLiteStatement;
  Item: TBibleSearchResult;
  Range: TIdRange;
  ByRange: Boolean;
begin
  Items := nil;
  if (Window.Count <= 0) or not TryBuildMatchQuery(Query.Text, MatchModeOf(Query), MatchExpr) then
    Exit(TResult<TArray<TBibleSearchResult>>.Success(Items));
  try
    if not PlanWindow(ckBibleTranslation, Query, Window, G, Error) then
    begin
      if Error = reNone then
        Exit(TResult<TArray<TBibleSearchResult>>.Success(Items));
      Exit(TResult<TArray<TBibleSearchResult>>.Failure(Error));
    end;
    NeedRanges;
    N := Length(G.ModuleIds);
    // R8-03: one translation in text order is its range of rowids - the books
    // stand there by OrderInModule (checked by NeedRanges).
    ByRange := (Window.Order = soText) and (N = 1);
    if ByRange and not FModuleRanges.TryGetValue(G.ModuleIds[0], Range) then
      Exit(TResult<TArray<TBibleSearchResult>>.Success(Items));  // a translation without verses
    SQL := Format(
      'SELECT v.ModuleId, v.BookCode, v.ChapterNumber, v.VerseNumber, ' +
      'snippet(%0:s, 0, char(2), char(3), ''…'', %1:d) ' +
      'FROM %0:s JOIN Verses v ON v.Id = %0:s.rowid ', [G.Table, SnippetTokens]);
    if ByRange then
    begin
      N := 2;                                // ?2, ?3 - the range
      SQL := SQL + Format('WHERE %0:s MATCH ?1 AND %0:s.rowid BETWEEN ?2 AND ?3 ORDER BY %0:s.rowid',
        [G.Table]);
    end
    else
    begin
      SQL := SQL + Format(
        'JOIN Books b ON b.ModuleId = v.ModuleId AND b.BookCode = v.BookCode ' +
        'WHERE %0:s MATCH ?1 AND v.ModuleId ', [G.Table]) + InClause(N, 2);
      if Window.Order = soRelevance then
        SQL := SQL + Format(' ORDER BY rank, %s.rowid', [G.Table])
      else
        SQL := SQL + ' ORDER BY v.ModuleId, b.OrderInModule, v.ChapterNumber, v.VerseNumber';
    end;
    SQL := SQL + Format(' LIMIT ?%d OFFSET ?%d;', [N + 2, N + 3]);

    Stmt := FDatabase.Connection.Prepare(SQL);
    try
      Stmt.BindText(1, MatchExpr);
      if ByRange then
        Stmt.BindInt64(2, Range.FirstId).BindInt64(3, Range.LastId)
      else
        for I := 0 to N - 1 do
          Stmt.BindText(I + 2, G.ModuleIds[I]);
      Stmt.BindInt(N + 2, Window.Count);
      Stmt.BindInt(N + 3, Window.Offset);
      while Stmt.Step do
      begin
        Item := Default(TBibleSearchResult);
        Item.Ref.Chapter.Book.ModuleId := Stmt.ColumnText(0);
        Item.Ref.Chapter.Book.BookCode := Stmt.ColumnText(1);
        Item.Ref.Chapter.ChapterNumber := Stmt.ColumnInt(2);
        Item.Ref.VerseNumber := Stmt.ColumnInt(3);
        Item.Highlights := ExtractHighlights(Stmt.ColumnText(4), Item.Snippet);
        Items := Items + [Item];
      end;
    finally
      Stmt.Free;
    end;
    Result := TResult<TArray<TBibleSearchResult>>.Success(Items);
  except
    on E: Exception do
    begin
      FLogger.LogError('Search', Format('SearchBible "%s": %s: %s', [Query.Text, E.ClassName, E.Message]));
      Result := TResult<TArray<TBibleSearchResult>>.Failure(SQLiteErrorToResult(E));
    end;
  end;
end;

function TFts5SearchIndex.FindInChapter(const Query: TSearchQuery;
  const Ref: TChapterRef): TResult<TArray<TParagraphHit>>;
var
  MatchExpr, Table, Clean: string;
  M: TModule;
  Stmt: TSQLiteStatement;
  Hits: TArray<TParagraphHit>;
  Hit: TParagraphHit;
  U: Integer;
begin
  Hits := nil;
  if not TryBuildMatchQuery(Query.Text, MatchModeOf(Query), MatchExpr) then
    Exit(TResult<TArray<TParagraphHit>>.Success(Hits));
  if not ModuleLanguage(Ref.ModuleId, M) or (M.Kind <> ckBook) then
    Exit(TResult<TArray<TParagraphHit>>.Failure(reNotFound));
  try
    NeedRanges;
    // R8-03: the chapter is a range of rowids; a chapter without paragraphs has none.
    if not FBookKeys.TryGetValue(UnitKey(Ref.ModuleId, IntToStr(Ref.ChapterOrder)), U) then
      Exit(TResult<TArray<TParagraphHit>>.Success(Hits));
    Table := TableFor(ckBook, Query.WordForms, M.Language);
    Stmt := FDatabase.Connection.Prepare(Format(
      'SELECT p.LogicalIndex, highlight(%0:s, 0, char(2), char(3)) ' +
      'FROM %0:s JOIN Paragraphs p ON p.Id = %0:s.rowid ' +
      'WHERE %0:s MATCH ?1 AND %0:s.rowid BETWEEN ?2 AND ?3 ' +
      'ORDER BY %0:s.rowid;', [Table]));
    try
      Stmt.BindText(1, MatchExpr).BindInt64(2, FBookUnits[U].FirstId).BindInt64(3, FBookUnits[U].LastId);
      while Stmt.Step do
      begin
        Hit.LogicalIndex := Stmt.ColumnInt(0);
        Hit.Highlights := ExtractHighlights(Stmt.ColumnText(1), Clean);
        Hits := Hits + [Hit];
      end;
    finally
      Stmt.Free;
    end;
    Result := TResult<TArray<TParagraphHit>>.Success(Hits);
  except
    on E: Exception do
    begin
      FLogger.LogError('Search', Format('FindInChapter %s:%d "%s": %s: %s',
        [string(Ref.ModuleId), Ref.ChapterOrder, Query.Text, E.ClassName, E.Message]));
      Result := TResult<TArray<TParagraphHit>>.Failure(SQLiteErrorToResult(E));
    end;
  end;
end;

function TFts5SearchIndex.FindInBibleChapter(const Query: TSearchQuery;
  const Ref: TBibleChapterRef): TResult<TArray<TVerseHit>>;
var
  MatchExpr, Table, Clean: string;
  M: TModule;
  Stmt: TSQLiteStatement;
  Hits: TArray<TVerseHit>;
  Hit: TVerseHit;
  U: Integer;
begin
  Hits := nil;
  if not TryBuildMatchQuery(Query.Text, MatchModeOf(Query), MatchExpr) then
    Exit(TResult<TArray<TVerseHit>>.Success(Hits));
  if not ModuleLanguage(Ref.Book.ModuleId, M) or (M.Kind <> ckBibleTranslation) then
    Exit(TResult<TArray<TVerseHit>>.Failure(reNotFound));
  try
    NeedRanges;
    // R8-03: the range is the Bible book; the chapter is picked among its matches.
    if not FBibleKeys.TryGetValue(UnitKey(Ref.Book.ModuleId, string(Ref.Book.BookCode)), U) then
      Exit(TResult<TArray<TVerseHit>>.Success(Hits));
    Table := TableFor(ckBibleTranslation, Query.WordForms, M.Language);
    Stmt := FDatabase.Connection.Prepare(Format(
      'SELECT v.VerseNumber, highlight(%0:s, 0, char(2), char(3)) ' +
      'FROM %0:s JOIN Verses v ON v.Id = %0:s.rowid ' +
      'WHERE %0:s MATCH ?1 AND %0:s.rowid BETWEEN ?2 AND ?3 AND v.ChapterNumber = ?4 ' +
      'ORDER BY %0:s.rowid;', [Table]));
    try
      Stmt.BindText(1, MatchExpr).BindInt64(2, FBibleUnits[U].FirstId)
        .BindInt64(3, FBibleUnits[U].LastId).BindInt(4, Ref.ChapterNumber);
      while Stmt.Step do
      begin
        Hit.VerseNumber := Stmt.ColumnInt(0);
        Hit.Highlights := ExtractHighlights(Stmt.ColumnText(1), Clean);
        Hits := Hits + [Hit];
      end;
    finally
      Stmt.Free;
    end;
    Result := TResult<TArray<TVerseHit>>.Success(Hits);
  except
    on E: Exception do
    begin
      FLogger.LogError('Search', Format('FindInBibleChapter %s:%s:%d "%s": %s: %s',
        [string(Ref.Book.ModuleId), string(Ref.Book.BookCode), Ref.ChapterNumber,
         Query.Text, E.ClassName, E.Message]));
      Result := TResult<TArray<TVerseHit>>.Failure(SQLiteErrorToResult(E));
    end;
  end;
end;

end.
