unit Presentation.SearchResults;

(* What the search panel shows, without VCL (Slovo_04 A.4, C.5; B-27, B-31).

  BuildResultSections turns a TSearchReply into the rows of the result list:
  two sections, "Книги" and "Біблія", never merged by rank (B-27); the Bible
  section is grouped by translation (B-31) - SearchBible returns the groups one
  after another, so a group starts wherever ModuleId changes. Empty sections
  are left out. Each row carries its reference line and the snippet cut into
  runs, the matched ones bold (TSearchHighlight).

  Reference line (A.4): "Патріархи і пророки · Розділ 3 · 71.2" - the page
  part only when the book has a page system; Bible: "Буття 22:8". "Розділ N"
  is a localized string, so the form passes it in as ChapterLabel - this unit
  knows neither the localizer nor the form.

  TSearchResultsModel (E-19, E-20; B-34) is the list that replaces the flat
  page: built from the COUNTS of a search, it knows every row of the list
  before a single snippet is read, and reads the rows in windows of PageSize
  when the list asks for them.
    soText ("за книгами"): a block per book in library order - a heading per
      chapter with matches, the matches under it in text order, the reference
      of a row only its page "71.2"; the Bible: a block per translation,
      headings - its books, the reference "22:8".
    soRelevance: the books - one block per language without a caption (ranks
      of different tables are not comparable, B-31), the full reference in
      every row; the Bible - a block per translation.
  A block is what folds in the list; headings do not fold. *)

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Core.Domain,
  Core.Catalog,
  Presentation.MainViewModel;

type
  TTextRun = record
    Text: string;
    Bold: Boolean;
  end;

  TResultSectionKind = (rsBooks, rsBible);

  TResultRow = record
    RefText: string;
    Runs: TArray<TTextRun>;
    Index: Integer;                     // into Reply.Books.Items or Reply.Bible.Items
  end;

  // Books: one group with Caption = ''; Bible: one group per translation.
  TResultGroup = record
    Caption: string;
    Rows: TArray<TResultRow>;
  end;

  TResultSection = record
    Kind: TResultSectionKind;
    Groups: TArray<TResultGroup>;
  end;

  TChapterLabelFunc = reference to function(ChapterOrder: Integer): string;

// Snippet -> runs between the highlights. Highlights may come unsorted,
// overlapping or partly outside the text: they are sorted, merged and clipped.
function SplitRuns(const Snippet: string; const Highlights: TArray<TSearchHighlight>): TArray<TTextRun>;

function BookResultRef(Catalog: TLibraryCatalog; const Item: TBookSearchResult;
  const ChapterLabel: TChapterLabelFunc): string;
function BibleResultRef(Catalog: TLibraryCatalog; const Item: TBibleSearchResult): string;

function BuildResultSections(const Reply: TSearchReply; Catalog: TLibraryCatalog;
  const ChapterLabel: TChapterLabelFunc): TArray<TResultSection>;

// Number for the status line (E-12) and whether it is "the first N" (any page Truncated).
function ResultCount(const Reply: TSearchReply): Integer;
function ResultTruncated(const Reply: TSearchReply): Boolean;

// ---------------------------------------------------------------------------
// The grouped list (E-19, E-20; B-34)

type
  TResultLineKind = (rlHeading, rlHit);

  // One row of a block.
  TResultLine = record
    Kind: TResultLineKind;
    Loaded: Boolean;                    // rlHit: False = its window gave no such row
    RefText: string;                    // rlHeading: the caption; rlHit: the reference
    Runs: TArray<TTextRun>;
    BookRef: TParagraphRef;             // rlHit of rsBooks
    BibleRef: TVerseRef;                // rlHit of rsBible
  end;

  TResultHeading = record
    Caption: string;                    // "3 · Спокуса і падіння" / "Буття"
    Row: Integer;                       // its row in the block
    FirstHit: Integer;                  // matches of the block before it
  end;

  // What folds: a book, a translation; in the relevance view of the books -
  // one language group (Caption = '': it has no row of its own).
  TResultBlock = record
    Caption: string;
    ModuleIds: TArray<TModuleId>;
    HitCount: Integer;
    RowCount: Integer;                  // HitCount + Length(Headings)
    Headings: TArray<TResultHeading>;   // soText only
  end;

  TResultPart = record
    Kind: TResultSectionKind;
    Blocks: TArray<TResultBlock>;
  end;

  TFetchBookRowsFunc = reference to function(const ModuleIds: TArray<TModuleId>;
    Order: TSearchOrder; Offset, Count: Integer): TArray<TBookSearchResult>;
  TFetchBibleRowsFunc = reference to function(const ModuleIds: TArray<TModuleId>;
    Order: TSearchOrder; Offset, Count: Integer): TArray<TBibleSearchResult>;

  TSearchResultsModel = class
  private
    FCatalog: TLibraryCatalog;          // not owned
    FOrder: TSearchOrder;
    FChapterLabel: TChapterLabelFunc;
    FFetchBooks: TFetchBookRowsFunc;
    FFetchBible: TFetchBibleRowsFunc;
    FParts: TArray<TResultPart>;
    FTotalHits: Integer;
    FBookPages: TDictionary<string, TArray<TBookSearchResult>>;
    FBiblePages: TDictionary<string, TArray<TBibleSearchResult>>;

    function ModuleTitle(const Id: TModuleId): string;
    function InLibraryOrder(const Ids, ModuleOrder: TArray<TModuleId>): TArray<TModuleId>;
    function LanguageGroups(const Ids: TArray<TModuleId>): TArray<TArray<TModuleId>>;
    procedure BuildBooks(const Counts: TArray<TBookHitCount>; const ModuleOrder: TArray<TModuleId>);
    procedure BuildBible(const Counts: TArray<TBibleHitCount>; const ModuleOrder: TArray<TModuleId>);
    function HeadingAt(const Block: TResultBlock; Row: Integer): Integer;
    procedure FillBookHit(Part, Block, Hit: Integer; var Line: TResultLine);
    procedure FillBibleHit(Part, Block, Hit: Integer; var Line: TResultLine);
  public
    const PageSize = 50;                // rows in one window (B-34)

    // ModuleOrder: the modules as the library tree lists them (B-25); a module
    // missing there goes after the listed ones.
    constructor Create(const BookCounts: TArray<TBookHitCount>; const BibleCounts: TArray<TBibleHitCount>;
      Catalog: TLibraryCatalog; const ModuleOrder: TArray<TModuleId>; Order: TSearchOrder;
      const ChapterLabel: TChapterLabelFunc; const FetchBooks: TFetchBookRowsFunc;
      const FetchBible: TFetchBibleRowsFunc);
    destructor Destroy; override;

    // Row of a block; reads its window on first use. Out of range - a hit not Loaded.
    function Line(Part, Block, Row: Integer): TResultLine;
    // The pinned line over the list (E-19): the block and the heading of the row -
    // "Патріархи і пророки · 3 · Спокуса і падіння", "Огієнко · Буття".
    function PinnedText(Part, Block, Row: Integer): string;

    property Parts: TArray<TResultPart> read FParts;   // empty parts are left out
    property Order: TSearchOrder read FOrder;
    property TotalHits: Integer read FTotalHits;       // the status line "Збіги: N"
  end;

implementation

uses
  System.Generics.Defaults,
  System.Math;

function SplitRuns(const Snippet: string; const Highlights: TArray<TSearchHighlight>): TArray<TTextRun>;
var
  Spans: TArray<TSearchHighlight>;
  H: TSearchHighlight;
  Merged: TList<TSearchHighlight>;
  Last: TSearchHighlight;
  Pos, I: Integer;

  procedure Add(const Text: string; Bold: Boolean);
  var
    Run: TTextRun;
  begin
    if Text = '' then
      Exit;
    Run.Text := Text;
    Run.Bold := Bold;
    Result := Result + [Run];
  end;

begin
  Result := nil;
  // Clip to the text; offsets are 0-based UTF-16 units (B-24), Delphi strings 1-based.
  Spans := nil;
  for H in Highlights do
  begin
    Last.StartOffset := Max(H.StartOffset, 0);
    Last.Len := Min(H.StartOffset + H.Len, Length(Snippet)) - Last.StartOffset;
    if Last.Len > 0 then
      Spans := Spans + [Last];
  end;
  TArray.Sort<TSearchHighlight>(Spans, TComparer<TSearchHighlight>.Construct(
    function(const A, B: TSearchHighlight): Integer
    begin
      Result := A.StartOffset - B.StartOffset;
    end));

  Merged := TList<TSearchHighlight>.Create;
  try
    for H in Spans do
      if (Merged.Count > 0) and (H.StartOffset <= Merged.Last.StartOffset + Merged.Last.Len) then
      begin
        Last := Merged.Last;
        Last.Len := Max(Last.StartOffset + Last.Len, H.StartOffset + H.Len) - Last.StartOffset;
        Merged[Merged.Count - 1] := Last;
      end
      else
        Merged.Add(H);

    Pos := 0;
    for I := 0 to Merged.Count - 1 do
    begin
      Add(Copy(Snippet, Pos + 1, Merged[I].StartOffset - Pos), False);
      Add(Copy(Snippet, Merged[I].StartOffset + 1, Merged[I].Len), True);
      Pos := Merged[I].StartOffset + Merged[I].Len;
    end;
    Add(Copy(Snippet, Pos + 1, MaxInt), False);
  finally
    Merged.Free;
  end;
end;

function BookResultRef(Catalog: TLibraryCatalog; const Item: TBookSearchResult;
  const ChapterLabel: TChapterLabelFunc): string;
var
  M: TModule;
begin
  if Catalog.FindModule(Item.Ref.Chapter.ModuleId, M) then
    Result := M.Title
  else
    Result := string(Item.Ref.Chapter.ModuleId);
  Result := Result + ' · ' + ChapterLabel(Item.Ref.Chapter.ChapterOrder);
  if Item.PageNumber > 0 then
    Result := Result + Format(' · %d.%d', [Item.PageNumber, Item.ParagraphOnPage]);
end;

function BibleResultRef(Catalog: TLibraryCatalog; const Item: TBibleSearchResult): string;
begin
  Result := Catalog.BookTitle(Item.Ref.Chapter.Book);
  if Result = '' then
    Result := string(Item.Ref.Chapter.Book.BookCode);
  Result := Format('%s %d:%d', [Result, Item.Ref.Chapter.ChapterNumber, Item.Ref.VerseNumber]);
end;

function BuildResultSections(const Reply: TSearchReply; Catalog: TLibraryCatalog;
  const ChapterLabel: TChapterLabelFunc): TArray<TResultSection>;
var
  Section: TResultSection;
  Group: TResultGroup;
  Row: TResultRow;
  M: TModule;
  Current: TModuleId;
  I: Integer;
begin
  Result := nil;

  if Length(Reply.Books.Items) > 0 then
  begin
    Section := Default(TResultSection);
    Section.Kind := rsBooks;
    Group := Default(TResultGroup);
    for I := 0 to High(Reply.Books.Items) do
    begin
      Row.RefText := BookResultRef(Catalog, Reply.Books.Items[I], ChapterLabel);
      Row.Runs := SplitRuns(Reply.Books.Items[I].Snippet, Reply.Books.Items[I].Highlights);
      Row.Index := I;
      Group.Rows := Group.Rows + [Row];
    end;
    Section.Groups := [Group];
    Result := Result + [Section];
  end;

  if Length(Reply.Bible.Items) > 0 then
  begin
    Section := Default(TResultSection);
    Section.Kind := rsBible;
    Current := '';
    Group := Default(TResultGroup);
    for I := 0 to High(Reply.Bible.Items) do
    begin
      if (I = 0) or (Reply.Bible.Items[I].Ref.Chapter.Book.ModuleId <> Current) then
      begin
        if I > 0 then
          Section.Groups := Section.Groups + [Group];
        Current := Reply.Bible.Items[I].Ref.Chapter.Book.ModuleId;
        Group := Default(TResultGroup);
        if Catalog.FindModule(Current, M) then
          Group.Caption := M.Title
        else
          Group.Caption := string(Current);
      end;
      Row.RefText := BibleResultRef(Catalog, Reply.Bible.Items[I]);
      Row.Runs := SplitRuns(Reply.Bible.Items[I].Snippet, Reply.Bible.Items[I].Highlights);
      Row.Index := I;
      Group.Rows := Group.Rows + [Row];
    end;
    Section.Groups := Section.Groups + [Group];
    Result := Result + [Section];
  end;
end;

function ResultCount(const Reply: TSearchReply): Integer;
begin
  Result := Length(Reply.Books.Items) + Length(Reply.Bible.Items);
end;

function ResultTruncated(const Reply: TSearchReply): Boolean;
begin
  Result := Reply.Books.Truncated or Reply.Bible.Truncated;
end;

{ TSearchResultsModel }

procedure AddOnce(var Ids: TArray<TModuleId>; const Id: TModuleId);
var
  Known: TModuleId;
begin
  for Known in Ids do
    if Known = Id then
      Exit;
  Ids := Ids + [Id];
end;

function HasId(const Ids: TArray<TModuleId>; const Id: TModuleId): Boolean;
var
  Known: TModuleId;
begin
  Result := False;
  for Known in Ids do
    if Known = Id then
      Exit(True);
end;

constructor TSearchResultsModel.Create(const BookCounts: TArray<TBookHitCount>;
  const BibleCounts: TArray<TBibleHitCount>; Catalog: TLibraryCatalog;
  const ModuleOrder: TArray<TModuleId>; Order: TSearchOrder; const ChapterLabel: TChapterLabelFunc;
  const FetchBooks: TFetchBookRowsFunc; const FetchBible: TFetchBibleRowsFunc);
begin
  inherited Create;
  FCatalog := Catalog;
  FOrder := Order;
  FChapterLabel := ChapterLabel;
  FFetchBooks := FetchBooks;
  FFetchBible := FetchBible;
  FBookPages := TDictionary<string, TArray<TBookSearchResult>>.Create;
  FBiblePages := TDictionary<string, TArray<TBibleSearchResult>>.Create;
  BuildBooks(BookCounts, ModuleOrder);
  BuildBible(BibleCounts, ModuleOrder);
end;

destructor TSearchResultsModel.Destroy;
begin
  FBiblePages.Free;
  FBookPages.Free;
  inherited;
end;

function TSearchResultsModel.ModuleTitle(const Id: TModuleId): string;
var
  M: TModule;
begin
  if FCatalog.FindModule(Id, M) then
    Result := M.Title
  else
    Result := string(Id);
end;

function TSearchResultsModel.InLibraryOrder(const Ids, ModuleOrder: TArray<TModuleId>): TArray<TModuleId>;
var
  Id: TModuleId;
begin
  Result := nil;
  for Id in ModuleOrder do
    if HasId(Ids, Id) then
      AddOnce(Result, Id);
  for Id in Ids do
    AddOnce(Result, Id);
end;

// Groups in the order uk, ru, en, then the rest by code (B-31); inside a group
// the modules keep the order of Ids.
function TSearchResultsModel.LanguageGroups(const Ids: TArray<TModuleId>): TArray<TArray<TModuleId>>;

  function Rank(const Language: string): Integer;
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

  function Before(const L, R: string): Boolean;
  begin
    if Rank(L) <> Rank(R) then
      Result := Rank(L) < Rank(R)
    else
      Result := CompareStr(L, R) < 0;
  end;

var
  Languages: TArray<string>;
  Id: TModuleId;
  M: TModule;
  Language: string;
  I, J: Integer;
begin
  Result := nil;
  Languages := nil;
  for Id in Ids do
  begin
    if FCatalog.FindModule(Id, M) then
      Language := M.Language
    else
      Language := '';
    J := -1;
    for I := 0 to High(Languages) do
      if Languages[I] = Language then
        J := I;
    if J < 0 then
    begin
      J := Length(Languages);
      SetLength(Languages, J + 1);
      SetLength(Result, J + 1);
      while (J > 0) and Before(Language, Languages[J - 1]) do
      begin
        Languages[J] := Languages[J - 1];
        Result[J] := Result[J - 1];
        Dec(J);
      end;
      Languages[J] := Language;
      Result[J] := nil;
    end;
    Result[J] := Result[J] + [Id];
  end;
end;

procedure TSearchResultsModel.BuildBooks(const Counts: TArray<TBookHitCount>;
  const ModuleOrder: TArray<TModuleId>);
var
  Part: TResultPart;
  Ids, Group: TArray<TModuleId>;
  C: TBookHitCount;
  Id: TModuleId;
  Block: TResultBlock;
  H: TResultHeading;
  Ref: TChapterRef;
  Title: string;
begin
  Ids := nil;
  for C in Counts do
    if C.Count > 0 then
    begin
      AddOnce(Ids, C.ModuleId);
      Inc(FTotalHits, C.Count);
    end;
  if Length(Ids) = 0 then
    Exit;
  Ids := InLibraryOrder(Ids, ModuleOrder);

  Part := Default(TResultPart);
  Part.Kind := rsBooks;
  if FOrder = soText then
    for Id in Ids do
    begin
      Block := Default(TResultBlock);
      Block.Caption := ModuleTitle(Id);
      Block.ModuleIds := [Id];
      // The counts of a module come by ChapterOrder - the order of its window (B-34).
      for C in Counts do
        if (C.ModuleId = Id) and (C.Count > 0) then
        begin
          Ref.ModuleId := Id;
          Ref.ChapterOrder := C.ChapterOrder;
          Title := FCatalog.ChapterTitle(Ref);
          if Title = '' then
            H.Caption := FChapterLabel(C.ChapterOrder)
          else
            H.Caption := Format('%d · %s', [C.ChapterOrder, Title]);
          H.Row := Block.RowCount;
          H.FirstHit := Block.HitCount;
          Block.Headings := Block.Headings + [H];
          Inc(Block.HitCount, C.Count);
          Inc(Block.RowCount, C.Count + 1);
        end;
      Part.Blocks := Part.Blocks + [Block];
    end
  else
    for Group in LanguageGroups(Ids) do
    begin
      Block := Default(TResultBlock);
      Block.ModuleIds := Group;
      for C in Counts do
        if (C.Count > 0) and HasId(Group, C.ModuleId) then
          Inc(Block.HitCount, C.Count);
      Block.RowCount := Block.HitCount;
      Part.Blocks := Part.Blocks + [Block];
    end;
  FParts := FParts + [Part];
end;

procedure TSearchResultsModel.BuildBible(const Counts: TArray<TBibleHitCount>;
  const ModuleOrder: TArray<TModuleId>);
var
  Part: TResultPart;
  Ids: TArray<TModuleId>;
  C: TBibleHitCount;
  Id: TModuleId;
  Block: TResultBlock;
  H: TResultHeading;
  Book: TBookRef;
begin
  Ids := nil;
  for C in Counts do
    if C.Count > 0 then
    begin
      AddOnce(Ids, C.ModuleId);
      Inc(FTotalHits, C.Count);
    end;
  if Length(Ids) = 0 then
    Exit;
  Ids := InLibraryOrder(Ids, ModuleOrder);

  Part := Default(TResultPart);
  Part.Kind := rsBible;
  for Id in Ids do
  begin
    Block := Default(TResultBlock);
    Block.Caption := ModuleTitle(Id);
    Block.ModuleIds := [Id];
    // The counts of a translation come by OrderInModule - the order of its window.
    for C in Counts do
      if (C.ModuleId = Id) and (C.Count > 0) then
      begin
        if FOrder = soText then
        begin
          Book.ModuleId := Id;
          Book.BookCode := C.BookCode;
          H.Caption := FCatalog.BookTitle(Book);
          if H.Caption = '' then
            H.Caption := string(C.BookCode);
          H.Row := Block.RowCount;
          H.FirstHit := Block.HitCount;
          Block.Headings := Block.Headings + [H];
          Inc(Block.RowCount);
        end;
        Inc(Block.HitCount, C.Count);
        Inc(Block.RowCount, C.Count);
      end;
    Part.Blocks := Part.Blocks + [Block];
  end;
  FParts := FParts + [Part];
end;

// The last heading at or above Row; the first row of a block with headings is one.
function TSearchResultsModel.HeadingAt(const Block: TResultBlock; Row: Integer): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  Lo := 0;
  Hi := High(Block.Headings);
  while Lo < Hi do
  begin
    Mid := (Lo + Hi + 1) div 2;
    if Block.Headings[Mid].Row <= Row then
      Lo := Mid
    else
      Hi := Mid - 1;
  end;
  Result := Lo;
end;

function TSearchResultsModel.Line(Part, Block, Row: Integer): TResultLine;
var
  B: TResultBlock;
  H, Hit: Integer;
begin
  Result := Default(TResultLine);
  Result.Kind := rlHit;
  if (Part < 0) or (Part > High(FParts)) or (Block < 0) or (Block > High(FParts[Part].Blocks)) then
    Exit;
  B := FParts[Part].Blocks[Block];
  if (Row < 0) or (Row >= B.RowCount) then
    Exit;
  Hit := Row;
  if Length(B.Headings) > 0 then
  begin
    H := HeadingAt(B, Row);
    if B.Headings[H].Row = Row then
    begin
      Result.Kind := rlHeading;
      Result.Loaded := True;
      Result.RefText := B.Headings[H].Caption;
      Exit;
    end;
    Hit := B.Headings[H].FirstHit + (Row - B.Headings[H].Row - 1);
  end;
  if FParts[Part].Kind = rsBooks then
    FillBookHit(Part, Block, Hit, Result)
  else
    FillBibleHit(Part, Block, Hit, Result);
end;

procedure TSearchResultsModel.FillBookHit(Part, Block, Hit: Integer; var Line: TResultLine);
var
  Key: string;
  Items: TArray<TBookSearchResult>;
  Item: TBookSearchResult;
  Page: Integer;
begin
  Page := Hit div PageSize;
  Key := Format('%d:%d:%d', [Part, Block, Page]);
  if not FBookPages.TryGetValue(Key, Items) then
  begin
    Items := nil;
    if Assigned(FFetchBooks) then
      Items := FFetchBooks(FParts[Part].Blocks[Block].ModuleIds, FOrder, Page * PageSize, PageSize);
    // Kept even when empty: a failed window is not asked for on every repaint.
    FBookPages.Add(Key, Items);
  end;
  if Hit mod PageSize > High(Items) then
    Exit;
  Item := Items[Hit mod PageSize];
  Line.Loaded := True;
  Line.BookRef := Item.Ref;
  Line.Runs := SplitRuns(Item.Snippet, Item.Highlights);
  if FOrder = soRelevance then
    Line.RefText := BookResultRef(FCatalog, Item, FChapterLabel)
  else if Item.PageNumber > 0 then
    Line.RefText := Format('%d.%d', [Item.PageNumber, Item.ParagraphOnPage])
  else
    Line.RefText := '';                      // the book and the chapter stand above
end;

procedure TSearchResultsModel.FillBibleHit(Part, Block, Hit: Integer; var Line: TResultLine);
var
  Key: string;
  Items: TArray<TBibleSearchResult>;
  Item: TBibleSearchResult;
  Page: Integer;
begin
  Page := Hit div PageSize;
  Key := Format('%d:%d:%d', [Part, Block, Page]);
  if not FBiblePages.TryGetValue(Key, Items) then
  begin
    Items := nil;
    if Assigned(FFetchBible) then
      Items := FFetchBible(FParts[Part].Blocks[Block].ModuleIds, FOrder, Page * PageSize, PageSize);
    FBiblePages.Add(Key, Items);
  end;
  if Hit mod PageSize > High(Items) then
    Exit;
  Item := Items[Hit mod PageSize];
  Line.Loaded := True;
  Line.BibleRef := Item.Ref;
  Line.Runs := SplitRuns(Item.Snippet, Item.Highlights);
  if FOrder = soRelevance then
    Line.RefText := BibleResultRef(FCatalog, Item)
  else
    Line.RefText := Format('%d:%d', [Item.Ref.Chapter.ChapterNumber, Item.Ref.VerseNumber]);
end;

function TSearchResultsModel.PinnedText(Part, Block, Row: Integer): string;
var
  B: TResultBlock;
begin
  Result := '';
  if (Part < 0) or (Part > High(FParts)) or (Block < 0) or (Block > High(FParts[Part].Blocks)) then
    Exit;
  B := FParts[Part].Blocks[Block];
  Result := B.Caption;
  if (Length(B.Headings) > 0) and (Row >= 0) and (Row < B.RowCount) then
    Result := Result + ' · ' + B.Headings[HeadingAt(B, Row)].Caption;
end;

end.
