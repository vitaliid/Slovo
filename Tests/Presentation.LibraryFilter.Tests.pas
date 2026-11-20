unit Presentation.LibraryFilter.Tests;

{ Presentation.LibraryFilter (Slovo_04 A.3, E-25) without a form: the words
  and their folding, a caption's match, which rows of the tree stay. }

interface

uses
  DUnitX.TestFramework,
  Presentation.MainViewModel,
  Presentation.LibraryFilter;

type
  [TestFixture]
  TLibraryFilterTests = class
  private
    FNodes: TArray<TLibraryNode>;
    FCaptions: TArray<string>;
    procedure Add(Kind: TLibraryNodeKind; Parent: Integer; const Caption: string);
    function Filter(const Text: string): TLibraryFilterResult;
  public
    [Setup] procedure Setup;

    [Test] procedure Words_SplitAndFolded;
    [Test] procedure Match_AllWordsAnywhere_FirstWordHighlighted;
    [Test] procedure Match_AWordMissing_NoMatch;
    [Test] procedure Match_PrefersTheStartOfAWord;
    [Test] procedure Match_UkrainianAndRussianLetters;
    [Test] procedure Match_ApostropheSkipped_HighlightSpansIt;
    [Test] procedure Match_NoWords_NoMatch;

    [Test] procedure Library_NoText_EveryRowVisible;
    [Test] procedure Library_Book_WithItsParentsOnly;
    [Test] procedure Library_Series_AllItsBooks;
    [Test] procedure Library_Category_AllItsBooks;
    [Test] procedure Library_NothingFound;
    [Test] procedure Library_ChaptersNeverStay;
    [Test] procedure Library_First_InTreeOrder;
  end;

implementation

uses
  System.SysUtils;

{ Nodes, in the array's order (B-25):
    0 Біблія (category)
    1   Огієнко (translation)
    2     Буття (Bible book - no row)
    3 Праці Е. Ґ. Вайт (category)
    4   Конфлікт віків (series)
    5     Патріархи і пророки
    6       Створення (chapter - no row)
    7     Велика боротьба
    8   Шлях до Христа }

procedure TLibraryFilterTests.Add(Kind: TLibraryNodeKind; Parent: Integer; const Caption: string);
var
  N: TLibraryNode;
begin
  N := Default(TLibraryNode);
  N.Kind := Kind;
  N.Parent := Parent;
  N.Caption := Caption;
  FNodes := FNodes + [N];
  FCaptions := FCaptions + [Caption];
end;

procedure TLibraryFilterTests.Setup;
begin
  FNodes := nil;
  FCaptions := nil;
  Add(lnCategory, -1, 'Біблія');
  Add(lnBibleTranslation, 0, 'Огієнко');
  Add(lnBibleBook, 1, 'Буття');
  Add(lnCategory, -1, 'Праці Е. Ґ. Вайт');
  Add(lnSeries, 3, 'Конфлікт віків');
  Add(lnModule, 4, 'Патріархи і пророки');
  Add(lnChapter, 5, 'Створення');
  Add(lnModule, 4, 'Велика боротьба');
  Add(lnModule, 3, 'Шлях до Христа');
end;

function TLibraryFilterTests.Filter(const Text: string): TLibraryFilterResult;
begin
  Result := FilterLibrary(FNodes, FCaptions, Text);
end;

procedure TLibraryFilterTests.Words_SplitAndFolded;
var
  W: TArray<string>;
begin
  W := FilterWords('  Велика  БОРОТЬБА '#9'Їжа ґанок Ёлка є');
  Assert.AreEqual(6, Integer(Length(W)));
  Assert.AreEqual('велика', W[0]);
  Assert.AreEqual('боротьба', W[1]);
  Assert.AreEqual('ижа', W[2]);
  Assert.AreEqual('ганок', W[3]);
  Assert.AreEqual('елка', W[4]);
  Assert.AreEqual('е', W[5]);
end;

procedure TLibraryFilterTests.Match_AllWordsAnywhere_FirstWordHighlighted;
var
  M: TFilterMatch;
begin
  Assert.IsTrue(MatchCaption('Велика боротьба', FilterWords('бор вел'), M));
  Assert.AreEqual(7, M.Start);
  Assert.AreEqual(3, M.Length);
end;

procedure TLibraryFilterTests.Match_AWordMissing_NoMatch;
var
  M: TFilterMatch;
begin
  Assert.IsFalse(MatchCaption('Велика боротьба', FilterWords('вел христ'), M));
  Assert.AreEqual(0, M.Length);
end;

procedure TLibraryFilterTests.Match_PrefersTheStartOfAWord;
var
  M: TFilterMatch;
begin
  // "бо" is inside "Робота" first, but starts "Божа".
  Assert.IsTrue(MatchCaption('Робота Божа', FilterWords('бо'), M));
  Assert.AreEqual(7, M.Start);
  Assert.AreEqual(2, M.Length);
  // Inside a word only - still found, where it occurs first.
  Assert.IsTrue(MatchCaption('Пророки і царі', FilterWords('рок'), M));
  Assert.AreEqual(3, M.Start);
end;

procedure TLibraryFilterTests.Match_UkrainianAndRussianLetters;
var
  M: TFilterMatch;
begin
  Assert.IsFalse(MatchCaption('Свідчення для Церкви', FilterWords('свидет'), M));
  Assert.IsTrue(MatchCaption('Свідчення для Церкви', FilterWords('свидч'), M));
  Assert.IsTrue(MatchCaption('Свидетельства для Церкви', FilterWords('свід'), M));
  Assert.IsTrue(MatchCaption('Её жизнь', FilterWords('ее'), M));
  Assert.IsTrue(MatchCaption('Євангелізм', FilterWords('евангел'), M));
  Assert.IsTrue(MatchCaption('Ґедеон', FilterWords('гед'), M));
  Assert.IsTrue(MatchCaption('Steps to Christ', FilterWords('CHRIST'), M));
end;

procedure TLibraryFilterTests.Match_ApostropheSkipped_HighlightSpansIt;
var
  M: TFilterMatch;
begin
  Assert.IsTrue(MatchCaption('Об’явлення', FilterWords('обявл'), M));
  Assert.AreEqual(0, M.Start);
  Assert.AreEqual(6, M.Length);                 // "Об’явл"
  Assert.IsTrue(MatchCaption('Обявлення', FilterWords('об''явл'), M));
end;

procedure TLibraryFilterTests.Match_NoWords_NoMatch;
var
  M: TFilterMatch;
begin
  Assert.IsFalse(MatchCaption('Велика боротьба', FilterWords('   '), M));
end;

procedure TLibraryFilterTests.Library_NoText_EveryRowVisible;
var
  R: TLibraryFilterResult;
begin
  R := Filter('  ');
  Assert.IsFalse(R.Active);
  Assert.IsTrue(R.Visible[0] and R.Visible[1] and R.Visible[3] and R.Visible[4]
    and R.Visible[5] and R.Visible[7] and R.Visible[8]);
  Assert.IsFalse(R.Visible[2] or R.Visible[6]);
  Assert.AreEqual(4, R.Shown);
  Assert.AreEqual(4, R.Total);
  Assert.AreEqual(0, R.Matches[5].Length);
end;

procedure TLibraryFilterTests.Library_Book_WithItsParentsOnly;
var
  R: TLibraryFilterResult;
begin
  R := Filter('вел бор');
  Assert.IsTrue(R.Active);
  Assert.IsTrue(R.Visible[3] and R.Visible[4] and R.Visible[7]);
  Assert.IsFalse(R.Visible[0] or R.Visible[1] or R.Visible[5] or R.Visible[8]);
  Assert.AreEqual(1, R.Shown);
  Assert.AreEqual(4, R.Total);
  Assert.AreEqual(0, R.Matches[7].Start);
  Assert.AreEqual(3, R.Matches[7].Length);
  Assert.AreEqual(0, R.Matches[4].Length);      // the series only holds it
end;

procedure TLibraryFilterTests.Library_Series_AllItsBooks;
var
  R: TLibraryFilterResult;
begin
  R := Filter('конфлікт');
  Assert.IsTrue(R.Visible[3] and R.Visible[4] and R.Visible[5] and R.Visible[7]);
  Assert.IsFalse(R.Visible[8] or R.Visible[0]);
  Assert.AreEqual(8, R.Matches[4].Length);
  Assert.AreEqual(0, R.Matches[5].Length);
  Assert.AreEqual(2, R.Shown);
end;

procedure TLibraryFilterTests.Library_Category_AllItsBooks;
var
  R: TLibraryFilterResult;
begin
  R := Filter('вайт');
  Assert.IsTrue(R.Visible[3] and R.Visible[4] and R.Visible[5] and R.Visible[7] and R.Visible[8]);
  Assert.IsFalse(R.Visible[0] or R.Visible[1]);
  Assert.AreEqual(3, R.Shown);
end;

procedure TLibraryFilterTests.Library_NothingFound;
var
  R: TLibraryFilterResult;
  I: Integer;
begin
  R := Filter('зелень');
  for I := 0 to High(FNodes) do
    Assert.IsFalse(R.Visible[I], 'node ' + I.ToString);
  Assert.AreEqual(0, R.Shown);
  Assert.AreEqual(-1, R.First);
end;

procedure TLibraryFilterTests.Library_ChaptersNeverStay;
var
  R: TLibraryFilterResult;
begin
  R := Filter('створення');                      // only a chapter is called so
  Assert.AreEqual(0, R.Shown);
  Assert.IsFalse(R.Visible[6] or R.Visible[5]);
  R := Filter('буття');                          // only a Bible book
  Assert.AreEqual(0, R.Shown);
  Assert.IsFalse(R.Visible[1] or R.Visible[0]);
end;

procedure TLibraryFilterTests.Library_First_InTreeOrder;
begin
  Assert.AreEqual(7, Filter('бор').First);
  Assert.AreEqual(8, Filter('христ').First);
  Assert.AreEqual(1, Filter('о').First);
  Assert.AreEqual(1, Filter('').First);
end;

initialization
  TDUnitX.RegisterTestFixture(TLibraryFilterTests);

end.
