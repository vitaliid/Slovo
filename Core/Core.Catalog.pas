unit Core.Catalog;

{ TLibraryCatalog (B-29): everything the tree, shelf, table of contents,
  breadcrumbs, chapter navigation and search-result captions need, held in
  memory. Built once in phase 0 from three queries (ILibrary.LoadCatalog);
  immutable afterwards. Chapter/verse text is NOT part of the catalog.

  Owned by the composition root; the ViewModel and the search index only read it. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Core.Domain;

type
  TLibraryCatalog = class
  private
    FModules: TArray<TModule>;
    FModuleIndex: TDictionary<TModuleId, Integer>;
    FChapters: TDictionary<TModuleId, TArray<TChapterInfo>>;
    FBooks: TDictionary<TModuleId, TArray<TBookInfo>>;

    function ChapterIndex(const Ref: TChapterRef; out Items: TArray<TChapterInfo>): Integer;
    function BookIndex(const Ref: TBookRef; out Items: TArray<TBookInfo>): Integer;
    function StepBible(var Ref: TBibleChapterRef; Forward: Boolean): Boolean;
  public
    // Groups chapters and books by ModuleId, sorts them (ChapterOrder,
    // OrderInModule) and fills TModule.ChildCount (E-09). Input order is irrelevant.
    constructor Create(const AModules: TArray<TModule>; const AChapters: TArray<TChapterInfo>;
      const ABooks: TArray<TBookInfo>);
    destructor Destroy; override;

    property Modules: TArray<TModule> read FModules;     // tree order is the ViewModel's job (B-25)
    function FindModule(const Id: TModuleId; out Module: TModule): Boolean;
    function Chapters(const Id: TModuleId): TArray<TChapterInfo>;   // ckBook, by ChapterOrder
    function Books(const Id: TModuleId): TArray<TBookInfo>;         // ckBibleTranslation, by OrderInModule

    function ChapterTitle(const Ref: TChapterRef): string;          // '' when unknown
    function BookTitle(const Ref: TBookRef): string;                // '' when unknown

    function IsValid(const Ref: TChapterRef): Boolean; overload;
    function IsValid(const Ref: TBibleChapterRef): Boolean; overload;

    // Neighbouring chapter, Delta = +1 / -1 (any non-zero value walks that many steps).
    // Bible: crosses book boundaries (B-22). False at the edge of the MODULE or for
    // an invalid Ref - navigation never leaves the module.
    function Neighbour(const Ref: TChapterRef; Delta: Integer; out Target: TChapterRef): Boolean; overload;
    function Neighbour(const Ref: TBibleChapterRef; Delta: Integer; out Target: TBibleChapterRef): Boolean; overload;
  end;

implementation

uses
  System.Generics.Defaults;

{ TLibraryCatalog }

constructor TLibraryCatalog.Create(const AModules: TArray<TModule>;
  const AChapters: TArray<TChapterInfo>; const ABooks: TArray<TBookInfo>);
var
  ChapterLists: TObjectDictionary<TModuleId, TList<TChapterInfo>>;
  BookLists: TObjectDictionary<TModuleId, TList<TBookInfo>>;
  ChapterList: TList<TChapterInfo>;
  BookList: TList<TBookInfo>;
  Chapter: TChapterInfo;
  Book: TBookInfo;
  ChapterArray: TArray<TChapterInfo>;
  BookArray: TArray<TBookInfo>;
  I: Integer;
begin
  inherited Create;
  FModuleIndex := TDictionary<TModuleId, Integer>.Create;
  FChapters := TDictionary<TModuleId, TArray<TChapterInfo>>.Create;
  FBooks := TDictionary<TModuleId, TArray<TBookInfo>>.Create;

  ChapterLists := TObjectDictionary<TModuleId, TList<TChapterInfo>>.Create([doOwnsValues]);
  BookLists := TObjectDictionary<TModuleId, TList<TBookInfo>>.Create([doOwnsValues]);
  try
    for Chapter in AChapters do
    begin
      if not ChapterLists.TryGetValue(Chapter.Ref.ModuleId, ChapterList) then
      begin
        ChapterList := TList<TChapterInfo>.Create;
        ChapterLists.Add(Chapter.Ref.ModuleId, ChapterList);
      end;
      ChapterList.Add(Chapter);
    end;

    for Book in ABooks do
    begin
      if not BookLists.TryGetValue(Book.Ref.ModuleId, BookList) then
      begin
        BookList := TList<TBookInfo>.Create;
        BookLists.Add(Book.Ref.ModuleId, BookList);
      end;
      BookList.Add(Book);
    end;

    for var Pair in ChapterLists do
    begin
      Pair.Value.Sort(TComparer<TChapterInfo>.Construct(
        function(const L, R: TChapterInfo): Integer
        begin
          Result := L.Ref.ChapterOrder - R.Ref.ChapterOrder;
        end));
      FChapters.Add(Pair.Key, Pair.Value.ToArray);
    end;

    for var Pair in BookLists do
    begin
      Pair.Value.Sort(TComparer<TBookInfo>.Construct(
        function(const L, R: TBookInfo): Integer
        begin
          Result := L.OrderInModule - R.OrderInModule;
        end));
      FBooks.Add(Pair.Key, Pair.Value.ToArray);
    end;
  finally
    BookLists.Free;
    ChapterLists.Free;
  end;

  FModules := Copy(AModules);
  for I := 0 to High(FModules) do
  begin
    FModuleIndex.AddOrSetValue(FModules[I].Id, I);
    case FModules[I].Kind of
      ckBook:
        if FChapters.TryGetValue(FModules[I].Id, ChapterArray) then
          FModules[I].ChildCount := Length(ChapterArray)
        else
          FModules[I].ChildCount := 0;
      ckBibleTranslation:
        if FBooks.TryGetValue(FModules[I].Id, BookArray) then
          FModules[I].ChildCount := Length(BookArray)
        else
          FModules[I].ChildCount := 0;
    end;
  end;
end;

destructor TLibraryCatalog.Destroy;
begin
  FBooks.Free;
  FChapters.Free;
  FModuleIndex.Free;
  inherited;
end;

function TLibraryCatalog.FindModule(const Id: TModuleId; out Module: TModule): Boolean;
var
  Index: Integer;
begin
  Result := FModuleIndex.TryGetValue(Id, Index);
  if Result then
    Module := FModules[Index]
  else
    Module := Default(TModule);
end;

function TLibraryCatalog.Chapters(const Id: TModuleId): TArray<TChapterInfo>;
begin
  if not FChapters.TryGetValue(Id, Result) then
    Result := nil;
end;

function TLibraryCatalog.Books(const Id: TModuleId): TArray<TBookInfo>;
begin
  if not FBooks.TryGetValue(Id, Result) then
    Result := nil;
end;

function TLibraryCatalog.ChapterIndex(const Ref: TChapterRef; out Items: TArray<TChapterInfo>): Integer;
var
  I: Integer;
begin
  Items := Chapters(Ref.ModuleId);
  for I := 0 to High(Items) do
    if Items[I].Ref.ChapterOrder = Ref.ChapterOrder then
      Exit(I);
  Result := -1;
end;

function TLibraryCatalog.BookIndex(const Ref: TBookRef; out Items: TArray<TBookInfo>): Integer;
var
  I: Integer;
begin
  Items := Books(Ref.ModuleId);
  for I := 0 to High(Items) do
    if Items[I].Ref.BookCode = Ref.BookCode then
      Exit(I);
  Result := -1;
end;

function TLibraryCatalog.ChapterTitle(const Ref: TChapterRef): string;
var
  Items: TArray<TChapterInfo>;
  Index: Integer;
begin
  Index := ChapterIndex(Ref, Items);
  if Index >= 0 then
    Result := Items[Index].Title
  else
    Result := '';
end;

function TLibraryCatalog.BookTitle(const Ref: TBookRef): string;
var
  Items: TArray<TBookInfo>;
  Index: Integer;
begin
  Index := BookIndex(Ref, Items);
  if Index >= 0 then
    Result := Items[Index].DisplayTitle
  else
    Result := '';
end;

function TLibraryCatalog.IsValid(const Ref: TChapterRef): Boolean;
var
  Items: TArray<TChapterInfo>;
begin
  Result := ChapterIndex(Ref, Items) >= 0;
end;

function TLibraryCatalog.IsValid(const Ref: TBibleChapterRef): Boolean;
var
  Items: TArray<TBookInfo>;
  Index: Integer;
begin
  Index := BookIndex(Ref.Book, Items);
  Result := (Index >= 0) and (Ref.ChapterNumber >= 1) and
    (Ref.ChapterNumber <= Items[Index].ChapterCount);
end;

function TLibraryCatalog.Neighbour(const Ref: TChapterRef; Delta: Integer;
  out Target: TChapterRef): Boolean;
var
  Items: TArray<TChapterInfo>;
  Index: Integer;
begin
  Target := Ref;
  Index := ChapterIndex(Ref, Items);
  Result := (Delta <> 0) and (Index >= 0) and
    (Index + Delta >= 0) and (Index + Delta <= High(Items));
  if Result then
    Target := Items[Index + Delta].Ref;
end;

// One step inside the translation; False at its first/last chapter.
function TLibraryCatalog.StepBible(var Ref: TBibleChapterRef; Forward: Boolean): Boolean;
var
  Items: TArray<TBookInfo>;
  Index: Integer;
begin
  Index := BookIndex(Ref.Book, Items);
  if Index < 0 then
    Exit(False);
  Result := True;
  if Forward then
  begin
    if Ref.ChapterNumber < Items[Index].ChapterCount then
      Inc(Ref.ChapterNumber)
    else if Index < High(Items) then
    begin
      Ref.Book := Items[Index + 1].Ref;
      Ref.ChapterNumber := 1;
    end
    else
      Result := False;
  end
  else
  begin
    if Ref.ChapterNumber > 1 then
      Dec(Ref.ChapterNumber)
    else if Index > 0 then
    begin
      Ref.Book := Items[Index - 1].Ref;
      Ref.ChapterNumber := Items[Index - 1].ChapterCount;
    end
    else
      Result := False;
  end;
end;

function TLibraryCatalog.Neighbour(const Ref: TBibleChapterRef; Delta: Integer;
  out Target: TBibleChapterRef): Boolean;
var
  Current: TBibleChapterRef;
  Step: Integer;
begin
  Target := Ref;
  if (Delta = 0) or not IsValid(Ref) then
    Exit(False);
  Current := Ref;
  for Step := 1 to Abs(Delta) do
    if not StepBible(Current, Delta > 0) then
      Exit(False);
  Target := Current;
  Result := True;
end;

end.
