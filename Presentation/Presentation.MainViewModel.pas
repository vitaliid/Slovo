unit Presentation.MainViewModel;

{ TMainViewModel (Slovo_04 C.1; MVVM-light, A-02).

  Knows the domain and the ports only: no Vcl, no RTF, no VirtualTreeView, no
  localizer - it compiles without Vcl.* and is tested without a form.
  Everything runs on the UI thread and events fire directly (C-21).

  What the form does itself (not here): panels, "Тиша", zoom, hot keys, RTF,
  context menu, the wait cursor, the checked counter, the empty-query and
  empty-scope status lines (Slovo_04 A.3, A.4). }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Core.Domain,
  Core.Catalog,
  Core.Contracts,
  Core.Events;

type
  // State of the text column (Slovo_04 A.2).
  TReaderView = (rvShelf, rvToc, rvRead);

  TLibraryNodeKind = (lnCategory, lnSeries, lnBibleTranslation, lnModule, lnBibleBook, lnChapter);

  // Library tree node. The tree is built ONCE from the catalog (B-29) and handed
  // over as a flat array in display order; a parent always precedes its children
  // and Parent is its index in the same array. Language-dependent captions are
  // composed by the form from CaptionKey/Count (R4-12).
  TLibraryNode = record
    Kind: TLibraryNodeKind;
    Parent: Integer;              // -1 = root
    CaptionKey: string;           // lnCategory: 'category.spiritOfProphecy', 'category.bible'...
    Caption: string;              // series/translation/book/chapter - from the database (B-25)
    Series: string;               // lnSeries: its code (TModule.Series) - the series' shelf
    ModuleId: TModuleId;
    BookCode: TBookCode;          // lnBibleBook and Bible chapters
    ChapterOrder: Integer;        // lnChapter: book ChapterOrder or Bible ChapterNumber
    Count: Integer;               // E-09: ChildCount or TBookInfo.ChapterCount; 0 = no counter
    Checked: Boolean;             // lnModule / lnBibleTranslation only (R4-41)
  end;

  // One search run returns two pages (B-27); an empty section has empty Items.
  TSearchReply = record
    Books: TSearchPage<TBookSearchResult>;
    Bible: TSearchPage<TBibleSearchResult>;
    Query: TSearchQuery;
  end;

  // A chapter was opened (E-08): Hits of the active search in this chapter;
  // Focus = index in Hits of the current paragraph, -1 = none.
  TChapterLoadedArgs = record
    Content: TChapterContent;
    Hits: TArray<TParagraphHit>;
    Focus: Integer;
  end;

  TBibleChapterLoadedArgs = record
    Content: TBibleChapterContent;
    BookTitle: string;
    Hits: TArray<TVerseHit>;
    Focus: Integer;
  end;

  TMainViewModel = class
  private
    FLibrary: ILibrary;
    FCatalog: TLibraryCatalog;          // owned by the composition root
    FSearchIndex: ISearchIndex;
    FSettings: ISettings;
    FLogger: ILogger;

    FView: TReaderView;
    FShelfCategory: TBookCategory;
    FShelfTranslation: TModuleId;       // '' = the shelf shows a book category
    FShelfSeries: string;               // <> '' = the shelf shows that series of FShelfCategory
    FTocModule: TModuleId;
    FTocBook: TBookRef;                 // Bible table of contents; BookCode '' = a book's TOC
    FPosition: TReadingPosition;
    FHasPosition: Boolean;
    FChecked: TList<TModuleId>;
    FActiveQuery: TSearchQuery;
    FHasActiveQuery: Boolean;
    FPendingFocus: Integer;             // LogicalIndex / VerseNumber to focus; -1 = none
    FStarting: Boolean;                 // phase 1: failures go to the log, not the banner (E-16)

    FOnLibraryChanged: TEvent<TArray<TLibraryNode>>;
    FOnViewChanged: TEvent<TReaderView>;
    FOnChapterLoaded: TEvent<TChapterLoadedArgs>;
    FOnBibleChapterLoaded: TEvent<TBibleChapterLoadedArgs>;
    FOnSearchCompleted: TEvent<TSearchReply>;
    FOnErrorOccurred: TEvent<TResultError>;

    function BuildNodes: TArray<TLibraryNode>;
    procedure SetView(Value: TReaderView);
    procedure ReportError(Error: TResultError; const Where: string);
    procedure RememberPosition(const Position: TReadingPosition);
    function IsChecked(const Id: TModuleId): Boolean;
  public
    constructor Create(const ALibrary: ILibrary; ACatalog: TLibraryCatalog;
      const ASearchIndex: ISearchIndex; const ASettings: ISettings; const ALogger: ILogger);
    destructor Destroy; override;

    // ---- Phase 1 of startup (C-22, E-16)
    procedure Start;

    // ---- Navigation
    procedure ShowShelf(Category: TBookCategory); overload;
    procedure ShowShelf(const TranslationId: TModuleId); overload;
    // The books of one series as the shelf (Vitalii, 2026-11-06).
    procedure ShowSeriesShelf(Category: TBookCategory; const Series: string);
    procedure ShowToc(const ModuleId: TModuleId); overload;
    procedure ShowToc(const Book: TBookRef); overload;
    procedure OpenChapter(const Ref: TChapterRef); overload;
    procedure OpenChapter(const Ref: TBibleChapterRef); overload;
    procedure NextChapter;
    procedure PreviousChapter;
    function CanGoNext: Boolean;
    function CanGoPrevious: Boolean;

    // ---- Search (B-27, B-28, B-31)
    procedure SetChecked(const ModuleId: TModuleId; Value: Boolean);
    procedure Search(const Text: string; WholeLibrary, ExactPhrase, WordForms: Boolean);
    procedure OpenSearchResult(const Ref: TParagraphRef); overload;
    procedure OpenSearchResult(const Ref: TVerseRef); overload;

    // ---- Lookups for the form - all from the catalog
    function ModuleTitle(const ModuleId: TModuleId): string;
    function ChapterTitle(const Ref: TChapterRef): string;
    function BookTitle(const Ref: TBookRef): string;

    // ---- Diagnostics (Slovo_03 A.6/A.7)
    procedure ReportRenderProblem(const Msg: string);
    procedure ReportUnexpected(const Msg: string);

    property View: TReaderView read FView;
    property ShelfCategory: TBookCategory read FShelfCategory;
    property ShelfTranslation: TModuleId read FShelfTranslation;
    property ShelfSeries: string read FShelfSeries;
    property TocModule: TModuleId read FTocModule;
    property TocBook: TBookRef read FTocBook;
    property Position: TReadingPosition read FPosition;
    property HasPosition: Boolean read FHasPosition;
    property ActiveQuery: TSearchQuery read FActiveQuery;
    property HasActiveQuery: Boolean read FHasActiveQuery;
    property Catalog: TLibraryCatalog read FCatalog;

    property OnLibraryChanged: TEvent<TArray<TLibraryNode>> read FOnLibraryChanged;
    property OnViewChanged: TEvent<TReaderView> read FOnViewChanged;
    property OnChapterLoaded: TEvent<TChapterLoadedArgs> read FOnChapterLoaded;
    property OnBibleChapterLoaded: TEvent<TBibleChapterLoadedArgs> read FOnBibleChapterLoaded;
    property OnSearchCompleted: TEvent<TSearchReply> read FOnSearchCompleted;
    property OnErrorOccurred: TEvent<TResultError> read FOnErrorOccurred;
  end;

const
  CategoryKeys: array[TBookCategory] of string = (
    'category.spiritOfProphecy', 'category.history', 'category.spiritualLife',
    'category.prophecyStudy', 'category.dailyReadings');
  BibleCategoryKey = 'category.bible';

implementation

uses
  System.Generics.Defaults;

{ TMainViewModel }

constructor TMainViewModel.Create(const ALibrary: ILibrary; ACatalog: TLibraryCatalog;
  const ASearchIndex: ISearchIndex; const ASettings: ISettings; const ALogger: ILogger);
begin
  inherited Create;
  FLibrary := ALibrary;
  FCatalog := ACatalog;
  FSearchIndex := ASearchIndex;
  FSettings := ASettings;
  FLogger := ALogger;
  FChecked := TList<TModuleId>.Create;
  FPendingFocus := -1;
  FView := rvShelf;
  FShelfCategory := bcSpiritOfProphecy;

  FOnLibraryChanged := TEvent<TArray<TLibraryNode>>.Create;
  FOnViewChanged := TEvent<TReaderView>.Create;
  FOnChapterLoaded := TEvent<TChapterLoadedArgs>.Create;
  FOnBibleChapterLoaded := TEvent<TBibleChapterLoadedArgs>.Create;
  FOnSearchCompleted := TEvent<TSearchReply>.Create;
  FOnErrorOccurred := TEvent<TResultError>.Create;
end;

destructor TMainViewModel.Destroy;
begin
  FOnErrorOccurred.Free;
  FOnSearchCompleted.Free;
  FOnBibleChapterLoaded.Free;
  FOnChapterLoaded.Free;
  FOnViewChanged.Free;
  FOnLibraryChanged.Free;
  FChecked.Free;
  inherited;
end;

// ---------------------------------------------------------------- tree (B-25)

function TMainViewModel.IsChecked(const Id: TModuleId): Boolean;
begin
  Result := FChecked.Contains(Id);
end;

function TMainViewModel.BuildNodes: TArray<TLibraryNode>;
var
  Nodes: TList<TLibraryNode>;

  function AddNode(Kind: TLibraryNodeKind; Parent: Integer): Integer;
  var
    N: TLibraryNode;
  begin
    N := Default(TLibraryNode);
    N.Kind := Kind;
    N.Parent := Parent;
    Result := Nodes.Count;
    Nodes.Add(N);
  end;

  procedure AddBook(const M: TModule; Parent: Integer);
  var
    Index: Integer;
    N: TLibraryNode;
    C: TChapterInfo;
  begin
    Index := AddNode(lnModule, Parent);
    N := Nodes[Index];
    N.Caption := M.Title;
    N.ModuleId := M.Id;
    N.Count := M.ChildCount;
    N.Checked := IsChecked(M.Id);
    Nodes[Index] := N;
    for C in FCatalog.Chapters(M.Id) do
    begin
      N := Default(TLibraryNode);
      N.Kind := lnChapter;
      N.Parent := Index;
      N.Caption := C.Title;
      N.ModuleId := M.Id;
      N.ChapterOrder := C.Ref.ChapterOrder;
      Nodes.Add(N);
    end;
  end;

  procedure AddTranslation(const M: TModule; Parent: Integer);
  var
    Index, BookIndex, Chapter: Integer;
    N: TLibraryNode;
    B: TBookInfo;
  begin
    Index := AddNode(lnBibleTranslation, Parent);
    N := Nodes[Index];
    N.Caption := M.Title;
    N.ModuleId := M.Id;
    N.Count := M.ChildCount;
    N.Checked := IsChecked(M.Id);
    Nodes[Index] := N;
    for B in FCatalog.Books(M.Id) do
    begin
      BookIndex := AddNode(lnBibleBook, Index);
      N := Nodes[BookIndex];
      N.Caption := B.DisplayTitle;
      N.ModuleId := M.Id;
      N.BookCode := B.Ref.BookCode;
      N.Count := B.ChapterCount;
      Nodes[BookIndex] := N;
      for Chapter := 1 to B.ChapterCount do
      begin
        N := Default(TLibraryNode);
        N.Kind := lnChapter;
        N.Parent := BookIndex;
        N.Caption := IntToStr(Chapter);
        N.ModuleId := M.Id;
        N.BookCode := B.Ref.BookCode;
        N.ChapterOrder := Chapter;
        Nodes.Add(N);
      end;
    end;
  end;

var
  Category: TBookCategory;
  Books, Translations: TList<TModule>;
  M: TModule;
  CategoryIndex, SeriesIndex, I: Integer;
  N: TLibraryNode;
  LastSeries: string;
begin
  Nodes := TList<TLibraryNode>.Create;
  Books := TList<TModule>.Create;
  Translations := TList<TModule>.Create;
  try
    for Category := Low(TBookCategory) to High(TBookCategory) do
    begin
      Books.Clear;
      for M in FCatalog.Modules do
        if (M.Kind = ckBook) and (M.Category = Category) then
          Books.Add(M);
      if Books.Count = 0 then
        Continue;

      // Series first (by SeriesOrder, then SortOrder), then the rest by Title.
      Books.Sort(TComparer<TModule>.Construct(
        function(const L, R: TModule): Integer
        begin
          if (L.Series <> '') <> (R.Series <> '') then
            Exit(Ord(L.Series = '') - Ord(R.Series = ''));
          if L.Series <> '' then
          begin
            Result := L.SeriesOrder - R.SeriesOrder;
            if Result = 0 then
              Result := CompareStr(L.Series, R.Series);
            if Result = 0 then
              Result := L.SortOrder - R.SortOrder;
          end
          else
            Result := AnsiCompareText(L.Title, R.Title);
        end));

      CategoryIndex := AddNode(lnCategory, -1);
      N := Nodes[CategoryIndex];
      N.CaptionKey := CategoryKeys[Category];
      Nodes[CategoryIndex] := N;

      LastSeries := '';
      SeriesIndex := -1;
      for I := 0 to Books.Count - 1 do
      begin
        M := Books[I];
        if M.Series = '' then
          AddBook(M, CategoryIndex)
        else
        begin
          if M.Series <> LastSeries then
          begin
            SeriesIndex := AddNode(lnSeries, CategoryIndex);
            N := Nodes[SeriesIndex];
            N.Caption := M.SeriesTitle;
            N.Series := M.Series;
            Nodes[SeriesIndex] := N;
            LastSeries := M.Series;
          end;
          AddBook(M, SeriesIndex);
        end;
      end;
    end;

    for M in FCatalog.Modules do
      if M.Kind = ckBibleTranslation then
        Translations.Add(M);
    if Translations.Count > 0 then
    begin
      Translations.Sort(TComparer<TModule>.Construct(
        function(const L, R: TModule): Integer
        begin
          Result := AnsiCompareText(L.Title, R.Title);
        end));
      CategoryIndex := AddNode(lnCategory, -1);
      N := Nodes[CategoryIndex];
      N.CaptionKey := BibleCategoryKey;
      Nodes[CategoryIndex] := N;
      for M in Translations do
        AddTranslation(M, CategoryIndex);
    end;

    Result := Nodes.ToArray;
  finally
    Translations.Free;
    Books.Free;
    Nodes.Free;
  end;
end;

// ---------------------------------------------------------------- startup

procedure TMainViewModel.Start;
var
  Id: TModuleId;
  M: TModule;
  Last: TReadingPosition;
  Valid: Boolean;
begin
  // Checked modules that are no longer in the library are dropped (R4-29).
  FChecked.Clear;
  for Id in FSettings.GetCheckedModules do
    if FCatalog.FindModule(Id, M) and not FChecked.Contains(Id) then
      FChecked.Add(Id);

  FOnLibraryChanged.Fire(BuildNodes);

  FStarting := True;
  try
    if FSettings.GetLastPosition(Last) then
    begin
      if Last.Kind = ckBibleTranslation then
        Valid := FCatalog.IsValid(Last.BibleChapter)
      else
        Valid := FCatalog.IsValid(Last.Chapter);
      if Valid then
      begin
        if Last.Kind = ckBibleTranslation then
          OpenChapter(Last.BibleChapter)
        else
          OpenChapter(Last.Chapter);
      end
      else
        FLogger.LogError('Start', 'Saved position is not in the library: ' + string(Last.ModuleId));
    end;
    if FView <> rvRead then
      ShowShelf(bcSpiritOfProphecy);
  finally
    FStarting := False;
  end;
end;

// ---------------------------------------------------------------- navigation

procedure TMainViewModel.SetView(Value: TReaderView);
begin
  FView := Value;
  FOnViewChanged.Fire(Value);
end;

procedure TMainViewModel.ReportError(Error: TResultError; const Where: string);
begin
  if FStarting then
    // E-16: a broken position at startup -> Shelf silently, a line in the log.
    FLogger.LogError('Start', Format('%s failed at startup (error %d)', [Where, Ord(Error)]))
  else
    FOnErrorOccurred.Fire(Error);
end;

procedure TMainViewModel.ShowShelf(Category: TBookCategory);
begin
  FShelfCategory := Category;
  FShelfTranslation := '';
  FShelfSeries := '';
  SetView(rvShelf);
end;

procedure TMainViewModel.ShowShelf(const TranslationId: TModuleId);
begin
  FShelfTranslation := TranslationId;
  FShelfSeries := '';
  SetView(rvShelf);
end;

procedure TMainViewModel.ShowSeriesShelf(Category: TBookCategory; const Series: string);
begin
  FShelfCategory := Category;
  FShelfTranslation := '';
  FShelfSeries := Series;
  SetView(rvShelf);
end;

procedure TMainViewModel.ShowToc(const ModuleId: TModuleId);
begin
  FTocModule := ModuleId;
  FTocBook := Default(TBookRef);
  SetView(rvToc);
end;

procedure TMainViewModel.ShowToc(const Book: TBookRef);
begin
  FTocModule := Book.ModuleId;
  FTocBook := Book;
  SetView(rvToc);
end;

procedure TMainViewModel.RememberPosition(const Position: TReadingPosition);
begin
  FPosition := Position;
  FHasPosition := True;
  FSettings.SetLastPosition(Position);
  FSettings.Save;                       // R4-27: the position must survive a crash
end;

procedure TMainViewModel.OpenChapter(const Ref: TChapterRef);
var
  Content: TResult<TChapterContent>;
  Hits: TResult<TArray<TParagraphHit>>;
  Args: TChapterLoadedArgs;
  P: TReadingPosition;
  Focus, I: Integer;
begin
  Focus := FPendingFocus;
  FPendingFocus := -1;
  if not FCatalog.IsValid(Ref) then
  begin
    ReportError(reNotFound, Format('OpenChapter %s:%d', [string(Ref.ModuleId), Ref.ChapterOrder]));
    Exit;
  end;

  Content := FLibrary.GetChapterContent(Ref);
  if not Content.IsSuccess then
  begin
    ReportError(Content.Error, Format('OpenChapter %s:%d', [string(Ref.ModuleId), Ref.ChapterOrder]));
    Exit;
  end;

  Args := Default(TChapterLoadedArgs);
  Args.Content := Content.Value;
  Args.Focus := -1;
  if FHasActiveQuery then
  begin
    Hits := FSearchIndex.FindInChapter(FActiveQuery, Ref);
    if Hits.IsSuccess then
    begin
      Args.Hits := Hits.Value;
      for I := 0 to High(Args.Hits) do
        if Args.Hits[I].LogicalIndex = Focus then
          Args.Focus := I;
    end
    else
      // E-08: the chapter is shown without highlighting, only the log knows.
      FLogger.LogError('Search', Format('FindInChapter failed (error %d)', [Ord(Hits.Error)]));
  end;

  P := Default(TReadingPosition);
  P.Kind := ckBook;
  P.Chapter := Ref;
  RememberPosition(P);
  FTocModule := Ref.ModuleId;
  SetView(rvRead);
  FOnChapterLoaded.Fire(Args);
end;

procedure TMainViewModel.OpenChapter(const Ref: TBibleChapterRef);
var
  Content: TResult<TBibleChapterContent>;
  Hits: TResult<TArray<TVerseHit>>;
  Args: TBibleChapterLoadedArgs;
  P: TReadingPosition;
  Focus, I: Integer;
begin
  Focus := FPendingFocus;
  FPendingFocus := -1;
  if not FCatalog.IsValid(Ref) then
  begin
    ReportError(reNotFound, Format('OpenChapter %s:%s:%d',
      [string(Ref.Book.ModuleId), string(Ref.Book.BookCode), Ref.ChapterNumber]));
    Exit;
  end;

  Content := FLibrary.GetBibleChapter(Ref);
  if not Content.IsSuccess then
  begin
    ReportError(Content.Error, Format('OpenChapter %s:%s:%d',
      [string(Ref.Book.ModuleId), string(Ref.Book.BookCode), Ref.ChapterNumber]));
    Exit;
  end;

  Args := Default(TBibleChapterLoadedArgs);
  Args.Content := Content.Value;
  Args.BookTitle := FCatalog.BookTitle(Ref.Book);
  Args.Focus := -1;
  if FHasActiveQuery then
  begin
    Hits := FSearchIndex.FindInBibleChapter(FActiveQuery, Ref);
    if Hits.IsSuccess then
    begin
      Args.Hits := Hits.Value;
      for I := 0 to High(Args.Hits) do
        if Args.Hits[I].VerseNumber = Focus then
          Args.Focus := I;
    end
    else
      FLogger.LogError('Search', Format('FindInBibleChapter failed (error %d)', [Ord(Hits.Error)]));
  end;

  P := Default(TReadingPosition);
  P.Kind := ckBibleTranslation;
  P.BibleChapter := Ref;
  RememberPosition(P);
  FTocModule := Ref.Book.ModuleId;
  FTocBook := Ref.Book;
  SetView(rvRead);
  FOnBibleChapterLoaded.Fire(Args);
end;

function TMainViewModel.CanGoNext: Boolean;
var
  T: TChapterRef;
  TB: TBibleChapterRef;
begin
  if not FHasPosition then
    Exit(False);
  if FPosition.Kind = ckBibleTranslation then
    Result := FCatalog.Neighbour(FPosition.BibleChapter, +1, TB)
  else
    Result := FCatalog.Neighbour(FPosition.Chapter, +1, T);
end;

function TMainViewModel.CanGoPrevious: Boolean;
var
  T: TChapterRef;
  TB: TBibleChapterRef;
begin
  if not FHasPosition then
    Exit(False);
  if FPosition.Kind = ckBibleTranslation then
    Result := FCatalog.Neighbour(FPosition.BibleChapter, -1, TB)
  else
    Result := FCatalog.Neighbour(FPosition.Chapter, -1, T);
end;

procedure TMainViewModel.NextChapter;
var
  T: TChapterRef;
  TB: TBibleChapterRef;
begin
  if not FHasPosition then
    Exit;
  if FPosition.Kind = ckBibleTranslation then
  begin
    if FCatalog.Neighbour(FPosition.BibleChapter, +1, TB) then
      OpenChapter(TB);
  end
  else if FCatalog.Neighbour(FPosition.Chapter, +1, T) then
    OpenChapter(T);
end;

procedure TMainViewModel.PreviousChapter;
var
  T: TChapterRef;
  TB: TBibleChapterRef;
begin
  if not FHasPosition then
    Exit;
  if FPosition.Kind = ckBibleTranslation then
  begin
    if FCatalog.Neighbour(FPosition.BibleChapter, -1, TB) then
      OpenChapter(TB);
  end
  else if FCatalog.Neighbour(FPosition.Chapter, -1, T) then
    OpenChapter(T);
end;

// ---------------------------------------------------------------- search

procedure TMainViewModel.SetChecked(const ModuleId: TModuleId; Value: Boolean);
begin
  if Value then
  begin
    if not FChecked.Contains(ModuleId) then
      FChecked.Add(ModuleId);
  end
  else
    FChecked.Remove(ModuleId);
  FSettings.SetCheckedModules(FChecked.ToArray);
end;

procedure TMainViewModel.Search(const Text: string; WholeLibrary, ExactPhrase, WordForms: Boolean);
var
  Query, BookQuery, BibleQuery: TSearchQuery;
  BookIds, BibleIds: TArray<TModuleId>;
  Id: TModuleId;
  M: TModule;
  Reply: TSearchReply;
  Books: TResult<TSearchPage<TBookSearchResult>>;
  Bible: TResult<TSearchPage<TBibleSearchResult>>;
begin
  // The form already shows a status line for these (R4-24); this is a guard for tests.
  if Text.Replace(#$00A0, ' ').Trim.IsEmpty then
    Exit;
  if not WholeLibrary and (FChecked.Count = 0) then
    Exit;

  FSettings.SetSearchWholeLibrary(WholeLibrary);
  FSettings.SetExactPhrase(ExactPhrase);
  FSettings.SetWordForms(WordForms);

  Query := Default(TSearchQuery);
  Query.Text := Text;
  Query.ExactPhrase := ExactPhrase;
  Query.WordForms := WordForms;

  // Split the scope by kind through the catalog (B-27).
  if not WholeLibrary then
    for Id in FChecked do
      if FCatalog.FindModule(Id, M) then
        if M.Kind = ckBook then
          BookIds := BookIds + [Id]
        else
          BibleIds := BibleIds + [Id];

  Reply := Default(TSearchReply);
  Reply.Query := Query;

  // R4-01: an empty list of one kind means NO call, not "the whole library".
  if WholeLibrary or (Length(BookIds) > 0) then
  begin
    BookQuery := Query;
    BookQuery.ModuleIds := BookIds;
    Books := FSearchIndex.SearchBook(BookQuery);
    if not Books.IsSuccess then
    begin
      FOnErrorOccurred.Fire(Books.Error);
      Exit;
    end;
    Reply.Books := Books.Value;
  end;

  if WholeLibrary or (Length(BibleIds) > 0) then
  begin
    BibleQuery := Query;
    BibleQuery.ModuleIds := BibleIds;
    Bible := FSearchIndex.SearchBible(BibleQuery);
    if not Bible.IsSuccess then
    begin
      FOnErrorOccurred.Fire(Bible.Error);
      Exit;
    end;
    Reply.Bible := Bible.Value;
  end;

  // FindInChapter ignores ModuleIds (the chapter names its module), so the plain
  // query is the active one for highlighting.
  FActiveQuery := Query;
  FHasActiveQuery := True;
  FOnSearchCompleted.Fire(Reply);
end;

procedure TMainViewModel.OpenSearchResult(const Ref: TParagraphRef);
begin
  FPendingFocus := Ref.LogicalIndex;
  OpenChapter(Ref.Chapter);
end;

procedure TMainViewModel.OpenSearchResult(const Ref: TVerseRef);
begin
  FPendingFocus := Ref.VerseNumber;
  OpenChapter(Ref.Chapter);
end;

// ---------------------------------------------------------------- lookups

function TMainViewModel.ModuleTitle(const ModuleId: TModuleId): string;
var
  M: TModule;
begin
  if FCatalog.FindModule(ModuleId, M) then
    Result := M.Title
  else
    Result := '';
end;

function TMainViewModel.ChapterTitle(const Ref: TChapterRef): string;
begin
  Result := FCatalog.ChapterTitle(Ref);
end;

function TMainViewModel.BookTitle(const Ref: TBookRef): string;
begin
  Result := FCatalog.BookTitle(Ref);
end;

// ---------------------------------------------------------------- diagnostics

procedure TMainViewModel.ReportRenderProblem(const Msg: string);
begin
  FLogger.LogError('Render', Msg);       // E-01: log only, no banner
end;

procedure TMainViewModel.ReportUnexpected(const Msg: string);
begin
  FLogger.LogError('Unexpected', Msg);
  FOnErrorOccurred.Fire(reUnexpected);
end;

end.
