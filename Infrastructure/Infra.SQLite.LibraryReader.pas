unit Infra.SQLite.LibraryReader;

{ ILibrary over library.db (B-29, Slovo_02 "Запити каталогу й вмісту").

  LoadCatalog - three queries, once, in phase 0; any failure raises (A-07) and
  the composition root shows startup.libraryCorrupted.
  GetChapterContent / GetBibleChapter - one chapter at a time; failures come
  back as TResultError (A-06) and the technical detail goes to the log. }

interface

uses
  System.SysUtils,
  Core.Domain,
  Core.Catalog,
  Core.Contracts,
  Infra.SQLite.LibraryDatabase;

type
  TLibrary = class(TInterfacedObject, ILibrary)
  private
    FDatabase: TLibraryDatabase;      // not owned
    FLogger: ILogger;
  public
    constructor Create(ADatabase: TLibraryDatabase; const ALogger: ILogger);

    function LoadCatalog: TLibraryCatalog;
    function GetChapterContent(const Ref: TChapterRef): TResult<TChapterContent>;
    function GetBibleChapter(const Ref: TBibleChapterRef): TResult<TBibleChapterContent>;
  end;

implementation

uses
  System.Generics.Collections,
  Infrastructure.SQLite3.Database;

// Enums are stored as INTEGER (B-16); an unknown value means a newer or broken file.
function ToContentKind(Value: Integer; const ModuleId: string): TContentKind;
begin
  if (Value < Ord(Low(TContentKind))) or (Value > Ord(High(TContentKind))) then
    raise EArgumentOutOfRangeException.CreateFmt('Module %s: unknown Kind %d', [ModuleId, Value]);
  Result := TContentKind(Value);
end;

function ToCategory(Value: Integer; const ModuleId: string): TBookCategory;
begin
  if (Value < Ord(Low(TBookCategory))) or (Value > Ord(High(TBookCategory))) then
    raise EArgumentOutOfRangeException.CreateFmt('Module %s: unknown Category %d', [ModuleId, Value]);
  Result := TBookCategory(Value);
end;

function ToParagraphKind(Value: Integer): TParagraphKind;
begin
  if (Value < Ord(Low(TParagraphKind))) or (Value > Ord(High(TParagraphKind))) or
     (Value = Ord(pkPageMarker)) then
    raise EArgumentOutOfRangeException.CreateFmt('Unknown paragraph Kind %d', [Value]);
  Result := TParagraphKind(Value);
end;

function ToSpanKind(Value: Integer): TInlineSpanKind;
begin
  if (Value < Ord(Low(TInlineSpanKind))) or (Value > Ord(High(TInlineSpanKind))) then
    raise EArgumentOutOfRangeException.CreateFmt('Unknown span Kind %d', [Value]);
  Result := TInlineSpanKind(Value);
end;

{ TLibrary }

constructor TLibrary.Create(ADatabase: TLibraryDatabase; const ALogger: ILogger);
begin
  inherited Create;
  FDatabase := ADatabase;
  FLogger := ALogger;
end;

function TLibrary.LoadCatalog: TLibraryCatalog;
var
  Db: TSQLiteDatabase;
  Stmt: TSQLiteStatement;
  Modules: TList<TModule>;
  Chapters: TList<TChapterInfo>;
  Books: TList<TBookInfo>;
  M: TModule;
  C: TChapterInfo;
  B: TBookInfo;
begin
  Db := FDatabase.Connection;
  Modules := TList<TModule>.Create;
  Chapters := TList<TChapterInfo>.Create;
  Books := TList<TBookInfo>.Create;
  try
    Stmt := Db.Prepare(
      'SELECT ModuleId, Kind, Category, Language, Title, Author, ' +
      'Series, SeriesTitle, SeriesOrder, SortOrder FROM Modules;');
    try
      while Stmt.Step do
      begin
        M := Default(TModule);
        M.Id := Stmt.ColumnText(0);
        M.Kind := ToContentKind(Stmt.ColumnInt(1), M.Id);
        M.Category := ToCategory(Stmt.ColumnInt(2), M.Id);
        M.Language := Stmt.ColumnText(3);
        M.Title := Stmt.ColumnText(4);
        M.Author := Stmt.ColumnText(5);
        M.Series := Stmt.ColumnText(6);
        M.SeriesTitle := Stmt.ColumnText(7);
        M.SeriesOrder := Stmt.ColumnInt(8);
        M.SortOrder := Stmt.ColumnInt(9);
        Modules.Add(M);
      end;
    finally
      Stmt.Free;
    end;

    Stmt := Db.Prepare(
      'SELECT ModuleId, ChapterOrder, ChapterTitle FROM Chapters ' +
      'ORDER BY ModuleId, ChapterOrder;');
    try
      while Stmt.Step do
      begin
        C.Ref.ModuleId := Stmt.ColumnText(0);
        C.Ref.ChapterOrder := Stmt.ColumnInt(1);
        C.Title := Stmt.ColumnText(2);
        Chapters.Add(C);
      end;
    finally
      Stmt.Free;
    end;

    Stmt := Db.Prepare(
      'SELECT ModuleId, BookCode, OrderInModule, DisplayTitle, ChapterCount FROM Books ' +
      'ORDER BY ModuleId, OrderInModule;');
    try
      while Stmt.Step do
      begin
        B.Ref.ModuleId := Stmt.ColumnText(0);
        B.Ref.BookCode := Stmt.ColumnText(1);
        B.OrderInModule := Stmt.ColumnInt(2);
        B.DisplayTitle := Stmt.ColumnText(3);
        B.ChapterCount := Stmt.ColumnInt(4);
        Books.Add(B);
      end;
    finally
      Stmt.Free;
    end;

    Result := TLibraryCatalog.Create(Modules.ToArray, Chapters.ToArray, Books.ToArray);
  finally
    Books.Free;
    Chapters.Free;
    Modules.Free;
  end;
end;

function TLibrary.GetChapterContent(const Ref: TChapterRef): TResult<TChapterContent>;
var
  Db: TSQLiteDatabase;
  Stmt: TSQLiteStatement;
  Content: TChapterContent;
  P: TParagraphContent;
  Paragraphs: TList<TParagraphContent>;
  IndexById: TDictionary<Int64, Integer>;
  Index: Integer;
  Span: TInlineSpan;
begin
  try
    Db := FDatabase.Connection;
    Content := Default(TChapterContent);
    Content.Ref := Ref;

    Stmt := Db.Prepare(
      'SELECT ChapterTitle FROM Chapters WHERE ModuleId = ?1 AND ChapterOrder = ?2;');
    try
      Stmt.BindText(1, Ref.ModuleId).BindInt(2, Ref.ChapterOrder);
      if not Stmt.Step then
        Exit(TResult<TChapterContent>.Failure(reNotFound));
      Content.Title := Stmt.ColumnText(0);
    finally
      Stmt.Free;
    end;

    Paragraphs := TList<TParagraphContent>.Create;
    IndexById := TDictionary<Int64, Integer>.Create;
    try
      Stmt := Db.Prepare(
        'SELECT Id, LogicalIndex, Kind, Text, StartPageNumber, PageBreakOffset, ParagraphOnPage ' +
        'FROM Paragraphs WHERE ModuleId = ?1 AND ChapterOrder = ?2 ORDER BY LogicalIndex;');
      try
        Stmt.BindText(1, Ref.ModuleId).BindInt(2, Ref.ChapterOrder);
        while Stmt.Step do
        begin
          P := Default(TParagraphContent);
          P.Ref.Chapter := Ref;
          P.Ref.LogicalIndex := Stmt.ColumnInt(1);
          P.Kind := ToParagraphKind(Stmt.ColumnInt(2));
          P.Text := Stmt.ColumnText(3);
          P.StartPageNumber := Stmt.ColumnInt(4);
          P.PageBreakOffset := Stmt.ColumnInt(5);
          P.ParagraphOnPage := Stmt.ColumnInt(6);
          IndexById.Add(Stmt.ColumnInt64(0), Paragraphs.Count);
          Paragraphs.Add(P);
        end;
      finally
        Stmt.Free;
      end;

      // Paragraphs.Id is internal (B-21): used here to attach spans, never returned.
      Content.Paragraphs := Paragraphs.ToArray;
      Stmt := Db.Prepare(
        'SELECT s.ParagraphId, s.StartOffset, s.Length, s.Kind FROM Spans s ' +
        'JOIN Paragraphs p ON p.Id = s.ParagraphId ' +
        'WHERE p.ModuleId = ?1 AND p.ChapterOrder = ?2 ' +
        'ORDER BY s.ParagraphId, s.StartOffset;');
      try
        Stmt.BindText(1, Ref.ModuleId).BindInt(2, Ref.ChapterOrder);
        while Stmt.Step do
          if IndexById.TryGetValue(Stmt.ColumnInt64(0), Index) then
          begin
            Span.StartOffset := Stmt.ColumnInt(1);
            Span.Len := Stmt.ColumnInt(2);
            Span.Kind := ToSpanKind(Stmt.ColumnInt(3));
            Content.Paragraphs[Index].InlineSpans := Content.Paragraphs[Index].InlineSpans + [Span];
          end;
      finally
        Stmt.Free;
      end;
    finally
      IndexById.Free;
      Paragraphs.Free;
    end;

    Result := TResult<TChapterContent>.Success(Content);
  except
    on E: Exception do
    begin
      FLogger.LogError('Library', Format('GetChapterContent %s:%d: %s: %s',
        [string(Ref.ModuleId), Ref.ChapterOrder, E.ClassName, E.Message]));
      Result := TResult<TChapterContent>.Failure(SQLiteErrorToResult(E));
    end;
  end;
end;

function TLibrary.GetBibleChapter(const Ref: TBibleChapterRef): TResult<TBibleChapterContent>;
var
  Stmt: TSQLiteStatement;
  Content: TBibleChapterContent;
  Verses: TList<TVerseContent>;
  V: TVerseContent;
begin
  try
    Content := Default(TBibleChapterContent);
    Content.Ref := Ref;
    Verses := TList<TVerseContent>.Create;
    try
      Stmt := FDatabase.Connection.Prepare(
        'SELECT VerseNumber, Text FROM Verses ' +
        'WHERE ModuleId = ?1 AND BookCode = ?2 AND ChapterNumber = ?3 ORDER BY VerseNumber;');
      try
        Stmt.BindText(1, Ref.Book.ModuleId).BindText(2, Ref.Book.BookCode)
          .BindInt(3, Ref.ChapterNumber);
        while Stmt.Step do
        begin
          V.Ref.Chapter := Ref;
          V.Ref.VerseNumber := Stmt.ColumnInt(0);
          V.Text := Stmt.ColumnText(1);
          Verses.Add(V);
        end;
      finally
        Stmt.Free;
      end;
      if Verses.Count = 0 then
        Exit(TResult<TBibleChapterContent>.Failure(reNotFound));
      Content.Verses := Verses.ToArray;
    finally
      Verses.Free;
    end;
    Result := TResult<TBibleChapterContent>.Success(Content);
  except
    on E: Exception do
    begin
      FLogger.LogError('Library', Format('GetBibleChapter %s:%s:%d: %s: %s',
        [string(Ref.Book.ModuleId), string(Ref.Book.BookCode), Ref.ChapterNumber,
         E.ClassName, E.Message]));
      Result := TResult<TBibleChapterContent>.Failure(SQLiteErrorToResult(E));
    end;
  end;
end;

end.
