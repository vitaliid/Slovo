unit Core.Catalog.Tests;

{ TLibraryCatalog (B-29): grouping, ChildCount (E-09), titles, IsValid,
  Neighbour inside a book, across Bible book boundaries (B-22) and never
  across the module edge. Pure in-memory fixtures, no database. }

interface

uses
  DUnitX.TestFramework,
  Core.Domain,
  Core.Catalog;

type
  [TestFixture]
  TLibraryCatalogTests = class
  private
    FCatalog: TLibraryCatalog;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test] procedure ChildCount_CountsChaptersForBooksAndBooksForTranslations;
    [Test] procedure Chapters_AreSortedByChapterOrder;
    [Test] procedure Chapters_UnknownModule_IsEmpty;
    [Test] procedure Books_AreSortedByOrderInModule;
    [Test] procedure FindModule_KnownAndUnknown;
    [Test] procedure ChapterTitle_KnownAndUnknown;
    [Test] procedure BookTitle_KnownAndUnknown;
    [Test] procedure IsValid_BookChapter;
    [Test] procedure IsValid_BibleChapter;
    [Test] procedure Neighbour_Book_InsideModule;
    [Test] procedure Neighbour_Book_StopsAtModuleEdges;
    [Test] procedure Neighbour_Book_InvalidRefOrZeroDelta;
    [Test] procedure Neighbour_Bible_InsideBook;
    [Test] procedure Neighbour_Bible_CrossesBookBoundary;
    [Test] procedure Neighbour_Bible_StopsAtTranslationEdges;
    [Test] procedure Neighbour_Bible_SeveralSteps;
    [Test] procedure Neighbour_Bible_InvalidRef;
  end;

implementation

function Module(const Id: string; Kind: TContentKind): TModule;
begin
  Result := Default(TModule);
  Result.Id := Id;
  Result.Kind := Kind;
  Result.Title := Id;
end;

function ChapterRef(const ModuleId: string; Order: Integer): TChapterRef;
begin
  Result.ModuleId := ModuleId;
  Result.ChapterOrder := Order;
end;

function Chapter(const ModuleId: string; Order: Integer; const Title: string): TChapterInfo;
begin
  Result.Ref := ChapterRef(ModuleId, Order);
  Result.Title := Title;
end;

function BookRef(const ModuleId, Code: string): TBookRef;
begin
  Result.ModuleId := ModuleId;
  Result.BookCode := Code;
end;

function Book(const ModuleId, Code: string; Order: Integer; const Title: string;
  ChapterCount: Integer): TBookInfo;
begin
  Result.Ref := BookRef(ModuleId, Code);
  Result.OrderInModule := Order;
  Result.DisplayTitle := Title;
  Result.ChapterCount := ChapterCount;
end;

function BibleRef(const ModuleId, Code: string; Chapter: Integer): TBibleChapterRef;
begin
  Result.Book := BookRef(ModuleId, Code);
  Result.ChapterNumber := Chapter;
end;

{ TLibraryCatalogTests }

procedure TLibraryCatalogTests.Setup;
begin
  // Input deliberately out of order: the catalog must sort it.
  FCatalog := TLibraryCatalog.Create(
    [Module('PP', ckBook), Module('GC', ckBook), Module('EMPTY', ckBook),
     Module('ohienko-uk', ckBibleTranslation), Module('kjv-en', ckBibleTranslation)],
    [Chapter('PP', 3, 'Третя'), Chapter('GC', 1, 'Єдина'),
     Chapter('PP', 1, 'Перша'), Chapter('PP', 2, 'Друга')],
    [Book('ohienko-uk', 'EXO', 2, 'Вихід', 40),
     Book('ohienko-uk', 'REV', 3, 'Об''явлення', 22),
     Book('kjv-en', 'GEN', 1, 'Genesis', 50),
     Book('ohienko-uk', 'GEN', 1, 'Буття', 50)]);
end;

procedure TLibraryCatalogTests.TearDown;
begin
  FCatalog.Free;
end;

procedure TLibraryCatalogTests.ChildCount_CountsChaptersForBooksAndBooksForTranslations;
var
  M: TModule;
begin
  Assert.IsTrue(FCatalog.FindModule('PP', M));
  Assert.AreEqual(3, M.ChildCount);
  Assert.IsTrue(FCatalog.FindModule('GC', M));
  Assert.AreEqual(1, M.ChildCount);
  Assert.IsTrue(FCatalog.FindModule('EMPTY', M));
  Assert.AreEqual(0, M.ChildCount);
  Assert.IsTrue(FCatalog.FindModule('ohienko-uk', M));
  Assert.AreEqual(3, M.ChildCount);
  Assert.IsTrue(FCatalog.FindModule('kjv-en', M));
  Assert.AreEqual(1, M.ChildCount);
  // The Modules property carries the same counts, in input order.
  Assert.AreEqual(5, Integer(Length(FCatalog.Modules)));
  Assert.AreEqual(3, FCatalog.Modules[0].ChildCount);
end;

procedure TLibraryCatalogTests.Chapters_AreSortedByChapterOrder;
var
  Items: TArray<TChapterInfo>;
begin
  Items := FCatalog.Chapters('PP');
  Assert.AreEqual(3, Integer(Length(Items)));
  Assert.AreEqual(1, Items[0].Ref.ChapterOrder);
  Assert.AreEqual(2, Items[1].Ref.ChapterOrder);
  Assert.AreEqual(3, Items[2].Ref.ChapterOrder);
  Assert.AreEqual('Перша', Items[0].Title);
end;

procedure TLibraryCatalogTests.Chapters_UnknownModule_IsEmpty;
begin
  Assert.AreEqual(0, Integer(Length(FCatalog.Chapters('NOPE'))));
  Assert.AreEqual(0, Integer(Length(FCatalog.Chapters('ohienko-uk'))));   // translation has books, not chapters
  Assert.AreEqual(0, Integer(Length(FCatalog.Books('PP'))));
end;

procedure TLibraryCatalogTests.Books_AreSortedByOrderInModule;
var
  Items: TArray<TBookInfo>;
begin
  Items := FCatalog.Books('ohienko-uk');
  Assert.AreEqual(3, Integer(Length(Items)));
  Assert.AreEqual('GEN', string(Items[0].Ref.BookCode));
  Assert.AreEqual('EXO', string(Items[1].Ref.BookCode));
  Assert.AreEqual('REV', string(Items[2].Ref.BookCode));
end;

procedure TLibraryCatalogTests.FindModule_KnownAndUnknown;
var
  M: TModule;
begin
  Assert.IsTrue(FCatalog.FindModule('ohienko-uk', M));
  Assert.IsTrue(M.Kind = ckBibleTranslation);
  Assert.IsFalse(FCatalog.FindModule('NOPE', M));
  Assert.AreEqual('', string(M.Id));
end;

procedure TLibraryCatalogTests.ChapterTitle_KnownAndUnknown;
begin
  Assert.AreEqual('Друга', FCatalog.ChapterTitle(ChapterRef('PP', 2)));
  Assert.AreEqual('', FCatalog.ChapterTitle(ChapterRef('PP', 9)));
  Assert.AreEqual('', FCatalog.ChapterTitle(ChapterRef('NOPE', 1)));
end;

procedure TLibraryCatalogTests.BookTitle_KnownAndUnknown;
begin
  Assert.AreEqual('Буття', FCatalog.BookTitle(BookRef('ohienko-uk', 'GEN')));
  Assert.AreEqual('Genesis', FCatalog.BookTitle(BookRef('kjv-en', 'GEN')));
  Assert.AreEqual('', FCatalog.BookTitle(BookRef('ohienko-uk', 'MAT')));
end;

procedure TLibraryCatalogTests.IsValid_BookChapter;
begin
  Assert.IsTrue(FCatalog.IsValid(ChapterRef('PP', 1)));
  Assert.IsTrue(FCatalog.IsValid(ChapterRef('PP', 3)));
  Assert.IsFalse(FCatalog.IsValid(ChapterRef('PP', 0)));
  Assert.IsFalse(FCatalog.IsValid(ChapterRef('PP', 4)));
  Assert.IsFalse(FCatalog.IsValid(ChapterRef('EMPTY', 1)));
  Assert.IsFalse(FCatalog.IsValid(ChapterRef('NOPE', 1)));
end;

procedure TLibraryCatalogTests.IsValid_BibleChapter;
begin
  Assert.IsTrue(FCatalog.IsValid(BibleRef('ohienko-uk', 'GEN', 1)));
  Assert.IsTrue(FCatalog.IsValid(BibleRef('ohienko-uk', 'GEN', 50)));
  Assert.IsFalse(FCatalog.IsValid(BibleRef('ohienko-uk', 'GEN', 0)));
  Assert.IsFalse(FCatalog.IsValid(BibleRef('ohienko-uk', 'GEN', 51)));
  Assert.IsFalse(FCatalog.IsValid(BibleRef('ohienko-uk', 'MAT', 1)));
  Assert.IsFalse(FCatalog.IsValid(BibleRef('NOPE', 'GEN', 1)));
end;

procedure TLibraryCatalogTests.Neighbour_Book_InsideModule;
var
  T: TChapterRef;
begin
  Assert.IsTrue(FCatalog.Neighbour(ChapterRef('PP', 2), +1, T));
  Assert.AreEqual(3, T.ChapterOrder);
  Assert.AreEqual('PP', string(T.ModuleId));
  Assert.IsTrue(FCatalog.Neighbour(ChapterRef('PP', 2), -1, T));
  Assert.AreEqual(1, T.ChapterOrder);
end;

procedure TLibraryCatalogTests.Neighbour_Book_StopsAtModuleEdges;
var
  T: TChapterRef;
begin
  Assert.IsFalse(FCatalog.Neighbour(ChapterRef('PP', 3), +1, T));
  Assert.IsFalse(FCatalog.Neighbour(ChapterRef('PP', 1), -1, T));
  Assert.IsFalse(FCatalog.Neighbour(ChapterRef('GC', 1), +1, T));
end;

procedure TLibraryCatalogTests.Neighbour_Book_InvalidRefOrZeroDelta;
var
  T: TChapterRef;
begin
  Assert.IsFalse(FCatalog.Neighbour(ChapterRef('PP', 9), +1, T));
  Assert.IsFalse(FCatalog.Neighbour(ChapterRef('NOPE', 1), +1, T));
  Assert.IsFalse(FCatalog.Neighbour(ChapterRef('PP', 2), 0, T));
end;

procedure TLibraryCatalogTests.Neighbour_Bible_InsideBook;
var
  T: TBibleChapterRef;
begin
  Assert.IsTrue(FCatalog.Neighbour(BibleRef('ohienko-uk', 'GEN', 49), +1, T));
  Assert.AreEqual('GEN', string(T.Book.BookCode));
  Assert.AreEqual(50, T.ChapterNumber);
  Assert.IsTrue(FCatalog.Neighbour(BibleRef('ohienko-uk', 'EXO', 5), -1, T));
  Assert.AreEqual('EXO', string(T.Book.BookCode));
  Assert.AreEqual(4, T.ChapterNumber);
end;

procedure TLibraryCatalogTests.Neighbour_Bible_CrossesBookBoundary;
var
  T: TBibleChapterRef;
begin
  // B-22: after GEN 50 comes EXO 1, and back.
  Assert.IsTrue(FCatalog.Neighbour(BibleRef('ohienko-uk', 'GEN', 50), +1, T));
  Assert.AreEqual('EXO', string(T.Book.BookCode));
  Assert.AreEqual(1, T.ChapterNumber);
  Assert.AreEqual('ohienko-uk', string(T.Book.ModuleId));

  Assert.IsTrue(FCatalog.Neighbour(BibleRef('ohienko-uk', 'EXO', 1), -1, T));
  Assert.AreEqual('GEN', string(T.Book.BookCode));
  Assert.AreEqual(50, T.ChapterNumber);
end;

procedure TLibraryCatalogTests.Neighbour_Bible_StopsAtTranslationEdges;
var
  T: TBibleChapterRef;
begin
  Assert.IsFalse(FCatalog.Neighbour(BibleRef('ohienko-uk', 'GEN', 1), -1, T));
  Assert.IsFalse(FCatalog.Neighbour(BibleRef('ohienko-uk', 'REV', 22), +1, T));
  // Never into another translation.
  Assert.IsFalse(FCatalog.Neighbour(BibleRef('kjv-en', 'GEN', 50), +1, T));
end;

procedure TLibraryCatalogTests.Neighbour_Bible_SeveralSteps;
var
  T: TBibleChapterRef;
begin
  Assert.IsTrue(FCatalog.Neighbour(BibleRef('ohienko-uk', 'GEN', 50), +2, T));
  Assert.AreEqual('EXO', string(T.Book.BookCode));
  Assert.AreEqual(2, T.ChapterNumber);
  Assert.IsFalse(FCatalog.Neighbour(BibleRef('ohienko-uk', 'REV', 21), +2, T));
end;

procedure TLibraryCatalogTests.Neighbour_Bible_InvalidRef;
var
  T: TBibleChapterRef;
begin
  Assert.IsFalse(FCatalog.Neighbour(BibleRef('ohienko-uk', 'GEN', 51), +1, T));
  Assert.IsFalse(FCatalog.Neighbour(BibleRef('ohienko-uk', 'MAT', 1), +1, T));
  Assert.IsFalse(FCatalog.Neighbour(BibleRef('ohienko-uk', 'GEN', 10), 0, T));
end;

initialization
  TDUnitX.RegisterTestFixture(TLibraryCatalogTests);

end.
