unit Infra.Search.Fts5SearchIndex;

{ ISearchIndex over the FTS5 tables of library.db (Slovo_02 "Пошукові запити").

  Table choice (B-28/B-31):
    WordForms = False -> ParagraphsFTS / VersesFTS, one query;
    WordForms = True  -> ParagraphsStem_<lang> / VersesStem_<lang>, one query per
                         language among the modules in scope. A language without
                         a stemmed table silently falls back to the exact table
                         (logged once per session).
  Two steps, no limit (B-34):
    Count*  - COUNT(*) GROUP BY chapter / Bible book over all matches, one query
              per table (language group), the rows of all groups in one array;
    Search* - one window LIMIT / OFFSET in text order or by bm25. Its modules
              must belong to one table: ranks of different tables are not
              comparable and an offset has no meaning across them.

  Matches are marked with char(2)/char(3) by snippet()/highlight() and cut out
  here, so offsets are UTF-16 code units of the clean text (B-24). Synchronous,
  stateless between calls (C-08, C-21). }

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
  private
    FDatabase: TLibraryDatabase;      // not owned
    FCatalog: TLibraryCatalog;        // not owned
    FLogger: ILogger;
    FTables: TDictionary<string, Boolean>;
    FWarnedLanguages: TList<string>;

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
end;

destructor TFts5SearchIndex.Destroy;
begin
  FWarnedLanguages.Free;
  FTables.Free;
  inherited;
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
  MatchExpr, SQL: string;
  Counts: TArray<TBookHitCount>;
  I: Integer;
  G: TSearchGroup;
  Stmt: TSQLiteStatement;
  Item: TBookHitCount;
begin
  Counts := nil;
  if not TryBuildMatchQuery(Query.Text, MatchModeOf(Query), MatchExpr) then
    Exit(TResult<TArray<TBookHitCount>>.Success(Counts));
  try
    for G in PlanGroups(ckBook, Query) do
    begin
      // G.Table is one of our own fixed names (TableFor), never user input.
      SQL := Format(
        'SELECT p.ModuleId, p.ChapterOrder, COUNT(*) ' +
        'FROM %0:s JOIN Paragraphs p ON p.Id = %0:s.rowid ' +
        'WHERE %0:s MATCH ?1', [G.Table]);
      if Length(G.ModuleIds) > 0 then
        SQL := SQL + ' AND p.ModuleId ' + InClause(Length(G.ModuleIds), 2);
      SQL := SQL + ' GROUP BY p.ModuleId, p.ChapterOrder ORDER BY p.ModuleId, p.ChapterOrder;';

      Stmt := FDatabase.Connection.Prepare(SQL);
      try
        Stmt.BindText(1, MatchExpr);
        for I := 0 to High(G.ModuleIds) do
          Stmt.BindText(I + 2, G.ModuleIds[I]);
        while Stmt.Step do
        begin
          Item.ModuleId := Stmt.ColumnText(0);
          Item.ChapterOrder := Stmt.ColumnInt(1);
          Item.Count := Stmt.ColumnInt(2);
          Counts := Counts + [Item];
        end;
      finally
        Stmt.Free;
      end;
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
  MatchExpr, SQL: string;
  Counts: TArray<TBibleHitCount>;
  I: Integer;
  G: TSearchGroup;
  Stmt: TSQLiteStatement;
  Item: TBibleHitCount;
begin
  Counts := nil;
  if not TryBuildMatchQuery(Query.Text, MatchModeOf(Query), MatchExpr) then
    Exit(TResult<TArray<TBibleHitCount>>.Success(Counts));
  try
    for G in PlanGroups(ckBibleTranslation, Query) do
    begin
      SQL := Format(
        'SELECT v.ModuleId, v.BookCode, COUNT(*) ' +
        'FROM %0:s JOIN Verses v ON v.Id = %0:s.rowid ' +
        'JOIN Books b ON b.ModuleId = v.ModuleId AND b.BookCode = v.BookCode ' +
        'WHERE %0:s MATCH ?1', [G.Table]);
      if Length(G.ModuleIds) > 0 then
        SQL := SQL + ' AND v.ModuleId ' + InClause(Length(G.ModuleIds), 2);
      SQL := SQL + ' GROUP BY v.ModuleId, v.BookCode ORDER BY v.ModuleId, b.OrderInModule;';

      Stmt := FDatabase.Connection.Prepare(SQL);
      try
        Stmt.BindText(1, MatchExpr);
        for I := 0 to High(G.ModuleIds) do
          Stmt.BindText(I + 2, G.ModuleIds[I]);
        while Stmt.Step do
        begin
          Item.ModuleId := Stmt.ColumnText(0);
          Item.BookCode := Stmt.ColumnText(1);
          Item.Count := Stmt.ColumnInt(2);
          Counts := Counts + [Item];
        end;
      finally
        Stmt.Free;
      end;
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
    N := Length(G.ModuleIds);
    // G.Table is one of our own fixed names (TableFor), never user input.
    SQL := Format(
      'SELECT p.ModuleId, p.ChapterOrder, p.LogicalIndex, p.StartPageNumber, p.ParagraphOnPage, ' +
      'snippet(%0:s, 0, char(2), char(3), ''…'', %1:d) ' +
      'FROM %0:s JOIN Paragraphs p ON p.Id = %0:s.rowid ' +
      'WHERE %0:s MATCH ?1 AND p.ModuleId ', [G.Table, SnippetTokens]) + InClause(N, 2);
    // The rowid breaks ties of equal ranks: windows must not overlap or skip rows.
    if Window.Order = soRelevance then
      SQL := SQL + Format(' ORDER BY rank, %s.rowid', [G.Table])
    else
      SQL := SQL + ' ORDER BY p.ModuleId, p.ChapterOrder, p.LogicalIndex';
    SQL := SQL + Format(' LIMIT ?%d OFFSET ?%d;', [N + 2, N + 3]);

    Stmt := FDatabase.Connection.Prepare(SQL);
    try
      Stmt.BindText(1, MatchExpr);
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
    N := Length(G.ModuleIds);
    SQL := Format(
      'SELECT v.ModuleId, v.BookCode, v.ChapterNumber, v.VerseNumber, ' +
      'snippet(%0:s, 0, char(2), char(3), ''…'', %1:d) ' +
      'FROM %0:s JOIN Verses v ON v.Id = %0:s.rowid ' +
      'JOIN Books b ON b.ModuleId = v.ModuleId AND b.BookCode = v.BookCode ' +
      'WHERE %0:s MATCH ?1 AND v.ModuleId ', [G.Table, SnippetTokens]) + InClause(N, 2);
    if Window.Order = soRelevance then
      SQL := SQL + Format(' ORDER BY rank, %s.rowid', [G.Table])
    else
      SQL := SQL + ' ORDER BY v.ModuleId, b.OrderInModule, v.ChapterNumber, v.VerseNumber';
    SQL := SQL + Format(' LIMIT ?%d OFFSET ?%d;', [N + 2, N + 3]);

    Stmt := FDatabase.Connection.Prepare(SQL);
    try
      Stmt.BindText(1, MatchExpr);
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
begin
  Hits := nil;
  if not TryBuildMatchQuery(Query.Text, MatchModeOf(Query), MatchExpr) then
    Exit(TResult<TArray<TParagraphHit>>.Success(Hits));
  if not ModuleLanguage(Ref.ModuleId, M) or (M.Kind <> ckBook) then
    Exit(TResult<TArray<TParagraphHit>>.Failure(reNotFound));
  try
    Table := TableFor(ckBook, Query.WordForms, M.Language);
    Stmt := FDatabase.Connection.Prepare(Format(
      'SELECT p.LogicalIndex, highlight(%0:s, 0, char(2), char(3)) ' +
      'FROM %0:s JOIN Paragraphs p ON p.Id = %0:s.rowid ' +
      'WHERE %0:s MATCH ?1 AND p.ModuleId = ?2 AND p.ChapterOrder = ?3 ' +
      'ORDER BY p.LogicalIndex;', [Table]));
    try
      Stmt.BindText(1, MatchExpr).BindText(2, Ref.ModuleId).BindInt(3, Ref.ChapterOrder);
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
begin
  Hits := nil;
  if not TryBuildMatchQuery(Query.Text, MatchModeOf(Query), MatchExpr) then
    Exit(TResult<TArray<TVerseHit>>.Success(Hits));
  if not ModuleLanguage(Ref.Book.ModuleId, M) or (M.Kind <> ckBibleTranslation) then
    Exit(TResult<TArray<TVerseHit>>.Failure(reNotFound));
  try
    Table := TableFor(ckBibleTranslation, Query.WordForms, M.Language);
    Stmt := FDatabase.Connection.Prepare(Format(
      'SELECT v.VerseNumber, highlight(%0:s, 0, char(2), char(3)) ' +
      'FROM %0:s JOIN Verses v ON v.Id = %0:s.rowid ' +
      'WHERE %0:s MATCH ?1 AND v.ModuleId = ?2 AND v.BookCode = ?3 AND v.ChapterNumber = ?4 ' +
      'ORDER BY v.VerseNumber;', [Table]));
    try
      Stmt.BindText(1, MatchExpr).BindText(2, Ref.Book.ModuleId)
        .BindText(3, Ref.Book.BookCode).BindInt(4, Ref.ChapterNumber);
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
