unit Shell.RichEdit.Tests;

(* TChapterRtfBuilder against the REAL RichEdit (msftedit.dll), through the
  same Shell.RichEdit calls the form uses (Slovo_04 C.4).

  Presentation.ChapterRtf.Tests reads the RTF back with its own small reader;
  that reader is only as right as our idea of RichEdit. Two differences were
  found on Windows by hand (an empty last paragraph is swallowed, paragraph
  borders are not drawn); this fixture is where the next one shows up
  automatically. A hidden form hosts the control - nothing is ever shown.

  Checked: no stream error, EM_GETTEXTLENGTHEX = ExpectedChars, and the text at
  every StartChar / marker / HitStart read back with EM_GETTEXTRANGE. *)

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Vcl.ComCtrls,
  Core.Domain,
  Core.Contracts,
  Infra.SQLite.LibraryDatabase,
  Presentation.ChapterRtf;

type
  [TestFixture]
  TRichEditRenderTests = class
  private
    FHost: TForm;
    FReader: TRichEdit;
    FDir: string;
    FDatabase: TLibraryDatabase;
    FLibrary: ILibrary;
    function Load(const Doc: TChapterRtf): Integer;
    function TextAt(StartChar, Len: Integer): string;
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure Book_CountAndMapMatchRichEdit;
    [Test] procedure Book_TitleOnlyChapterCountMatches;
    [Test] procedure Book_HitStartsPointAtTheMatchInRichEdit;
    [Test] procedure Bible_CountAndMapMatchRichEdit;
    [Test] procedure TestLibrary_EveryChapterRendersCompletely;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  Winapi.Messages,
  Winapi.RichEdit,
  Core.Catalog,
  Infra.SQLite.LibraryReader,
  Presentation.Theme,
  Presentation.ChapterRtf.Tests,
  Shell.RichEdit,
  Slovo.TestSupport;

type
  // TEXTRANGEW; Winapi.RichEdit has no Unicode alias for it under this name.
  TTextRangeW = record
    chrg: TCharRange;
    lpstrText: PWideChar;
  end;

{ TRichEditRenderTests }

procedure TRichEditRenderTests.SetupFixture;
var
  Error: TResultError;
  Logger: ILogger;
begin
  FHost := TForm.CreateNew(nil);
  FReader := TRichEdit.Create(FHost);
  FReader.Parent := FHost;
  FReader.ReadOnly := True;
  FReader.HandleNeeded;                       // creates the hidden host window too

  FDir := NewTempDir;
  Logger := TTestLogger.Create;
  FDatabase := TLibraryDatabase.Create(Logger);
  if not FDatabase.Open(BuildTestLibrary(TPath.Combine(FDir, 'library.db')), Error) then
    raise Exception.Create('Test library did not open');
  FLibrary := TLibrary.Create(FDatabase, Logger);
end;

procedure TRichEditRenderTests.TearDownFixture;
begin
  FLibrary := nil;
  FDatabase.Free;
  FHost.Free;
  try
    TDirectory.Delete(FDir, True);
  except
  end;
end;

// Streams the document in and returns what the control counts.
function TRichEditRenderTests.Load(const Doc: TChapterRtf): Integer;
var
  StreamError: Integer;
begin
  StreamInRtf(FReader, Doc.Rtf, StreamError);
  Assert.AreEqual(0, StreamError, 'stream error in ' + Doc.Where);
  Result := PreciseLength(FReader);
end;

function TRichEditRenderTests.TextAt(StartChar, Len: Integer): string;
var
  Range: TTextRangeW;
  Got: Integer;
begin
  if Len <= 0 then
    Exit('');
  SetLength(Result, Len + 1);                 // room for the terminating #0
  Range.chrg.cpMin := StartChar;
  Range.chrg.cpMax := StartChar + Len;
  Range.lpstrText := PChar(Result);
  Got := Integer(SendMessage(FReader.Handle, EM_GETTEXTRANGE, 0, LPARAM(@Range)));
  SetLength(Result, Got);
end;

procedure TRichEditRenderTests.Book_CountAndMapMatchRichEdit;
var
  Chapter: TChapterContent;
  Doc: TChapterRtf;
  R: TParagraphRange;
  I: Integer;
begin
  Chapter := SampleChapter;                   // title, epigraph, markers, \ { }, tab, CR LF, emoji
  Doc := TChapterRtfBuilder.Build(Chapter, 'Розділ 3', Theme, THighlightRequest.None);
  Assert.AreEqual(Doc.ExpectedChars, Load(Doc), 'ExpectedChars');
  for I := 0 to High(Doc.Paragraphs) do
  begin
    R := Doc.Paragraphs[I];
    Assert.AreEqual(Visible(Chapter.Paragraphs[I].Text), TextAt(R.StartChar, R.Len),
      'paragraph ' + IntToStr(R.LogicalIndex));
    if R.MarkerLen > 0 then
      Assert.AreEqual(#9 + Format('[%d]', [R.PageNumber]) + #9, TextAt(R.StartChar - R.MarkerLen, R.MarkerLen));
  end;
end;

procedure TRichEditRenderTests.Book_TitleOnlyChapterCountMatches;
var
  Chapter: TChapterContent;
  Doc: TChapterRtf;
begin
  // The case found by hand: DA:2 counted 24 against 25 while the rule paragraph was empty.
  Chapter := SampleChapter;
  Chapter.Paragraphs := Copy(Chapter.Paragraphs, 0, 1);
  Doc := TChapterRtfBuilder.Build(Chapter, 'Розділ 2', Theme, THighlightRequest.None);
  Assert.AreEqual(Doc.ExpectedChars, Load(Doc));
end;

procedure TRichEditRenderTests.Book_HitStartsPointAtTheMatchInRichEdit;
var
  Request: THighlightRequest;
  Doc: TChapterRtf;
begin
  Request.Hits := [Hit(3, [Hl(35, 6)]), Hit(4, [Hl(30, 6), Hl(39, 6)])];
  Request.Focus := 1;
  Doc := TChapterRtfBuilder.Build(SampleChapter, 'Розділ 3', Theme, Request);
  Assert.AreEqual(Doc.ExpectedChars, Load(Doc), 'highlight groups add no characters');
  Assert.AreEqual('жертва', TextAt(Doc.HitStarts[0], 6));
  Assert.AreEqual('жертва', TextAt(Doc.HitStarts[1], 6));
end;

procedure TRichEditRenderTests.Bible_CountAndMapMatchRichEdit;
var
  Chapter: TBibleChapterContent;
  Doc: TChapterRtf;
  R: TParagraphRange;
  I: Integer;
begin
  Chapter := SampleBibleChapter;
  Doc := TChapterRtfBuilder.Build(Chapter, 'Буття', 'Розділ 3', Theme, TVerseHighlightRequest.None);
  Assert.AreEqual(Doc.ExpectedChars, Load(Doc), 'ExpectedChars');
  for I := 0 to High(Doc.Paragraphs) do
  begin
    R := Doc.Paragraphs[I];
    Assert.AreEqual(Chapter.Verses[I].Text, TextAt(R.StartChar, R.Len));
    Assert.AreEqual(#9 + IntToStr(R.LogicalIndex) + #9, TextAt(R.StartChar - R.MarkerLen, R.MarkerLen));
  end;
end;

// Every chapter the fixtures contain, in both themes' rule variants.
procedure TRichEditRenderTests.TestLibrary_EveryChapterRendersCompletely;
var
  Catalog: TLibraryCatalog;
  M: TModule;
  C: TChapterInfo;
  B: TBookInfo;
  BookContent: TResult<TChapterContent>;
  BibleContent: TResult<TBibleChapterContent>;
  BibleRef: TBibleChapterRef;
  Doc: TChapterRtf;
  Themes: TArray<TReaderTheme>;
  T: TReaderTheme;
  N, Rendered: Integer;
begin
  Rendered := 0;
  Themes := [NewReaderTheme(TextFontName), NewReaderTheme(TextFontFallback)];
  Catalog := FLibrary.LoadCatalog;
  try
    for T in Themes do
      for M in Catalog.Modules do
        if M.Kind = ckBook then
          for C in Catalog.Chapters(M.Id) do
          begin
            BookContent := FLibrary.GetChapterContent(C.Ref);
            if not BookContent.IsSuccess then
              Continue;
            Doc := TChapterRtfBuilder.Build(BookContent.Value, 'Розділ', T, THighlightRequest.None);
            Assert.AreEqual(Doc.ExpectedChars, Load(Doc), Doc.Where);
            Inc(Rendered);
          end
        else
          for B in Catalog.Books(M.Id) do
            for N := 1 to B.ChapterCount do
            begin
              BibleRef.Book := B.Ref;
              BibleRef.ChapterNumber := N;
              BibleContent := FLibrary.GetBibleChapter(BibleRef);
              if not BibleContent.IsSuccess then
                Continue;                     // the fixtures hold only a few chapters
              Doc := TChapterRtfBuilder.Build(BibleContent.Value, B.DisplayTitle, 'Розділ', T,
                TVerseHighlightRequest.None);
              Assert.AreEqual(Doc.ExpectedChars, Load(Doc), Doc.Where);
              Inc(Rendered);
            end;
  finally
    Catalog.Free;
  end;
  // 9 book chapters and 7 Bible chapters with verses, in two themes.
  Assert.AreEqual(2 * 16, Rendered, 'chapters rendered');
end;

initialization
  TDUnitX.RegisterTestFixture(TRichEditRenderTests);

end.
