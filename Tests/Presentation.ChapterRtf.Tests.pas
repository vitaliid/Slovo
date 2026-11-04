unit Presentation.ChapterRtf.Tests;

(* TChapterRtfBuilder (Slovo_04 C.4) without a window.

  The tests read the produced RTF back with a small reader that does what the
  RichEdit does with the characters: \par -> 1 character, \uN? -> 1 code unit,
  escapes -> the character, the font and colour tables skipped. The plain text it
  returns is what EM_GETTEXTRANGE would give, so the map (StartChar, MarkerLen),
  ExpectedChars and HitStarts are checked against real positions, not against
  the builder's own counting. *)

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Core.Domain,
  Presentation.Theme,
  Presentation.ChapterRtf;

type
  [TestFixture]
  TChapterRtfBuilderTests = class
  public
    [Test] procedure EscapeText_KeepsVisibleLength;
    [Test] procedure Book_PlainTextMatchesMap;
    [Test] procedure Book_ExpectedCharsIsTheVisibleLength;
    [Test] procedure Book_PageMarkerOnlyWhereTextStartsAPage;
    [Test] procedure Book_TitleFromLeadingTitleParagraph;
    [Test] procedure Book_TitleFallsBackToChapterTitle;
    [Test] procedure Book_EveryParagraphResetsCharacterFormatting;
    [Test] procedure Book_FocusAndOtherHitsAreBakedIn;
    [Test] procedure Book_HitStartsPointAtTheFirstMatch;
    [Test] procedure Book_HitOutsideTheChapterIsMinusOne;
    [Test] procedure Book_BadHighlightsAreClampedAndOverlapsDropped;
    [Test] procedure Book_FontsComeFromTheTheme;
    [Test] procedure Bible_VerseNumbersAreMarkersBeforeStartChar;
    [Test] procedure Bible_HitStartsAndFocus;
    [Test] procedure Where_IdentifiesTheChapter;
  end;

implementation

type
  TRtfReadBack = record
    Text: string;                    // what the control shows; #13 per \par
    Highlight: TArray<Integer>;      // \highlightN in effect for each character
    function UnderHighlight(Level: Integer): string;
  end;

function TRtfReadBack.UnderHighlight(Level: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Highlight) do
    if Highlight[I] = Level then
      Result := Result + Text[I + 1];
end;

// Just enough of RTF for what the builder writes (\uc1, no other destinations).
function ReadBack(const Rtf: string): TRtfReadBack;
type
  TState = record
    Skip: Boolean;
    Highlight: Integer;
  end;
var
  Stack: TArray<TState>;
  State: TState;
  I, N, Sign: Integer;
  Ctl, Digits: string;
  Text: TStringBuilder;
  Levels: TArray<Integer>;

  procedure Emit(C: Char);
  begin
    if State.Skip then
      Exit;
    Text.Append(C);
    Levels := Levels + [State.Highlight];
  end;

begin
  Text := TStringBuilder.Create;
  try
    State.Skip := False;
    State.Highlight := 0;
    I := 1;
    while I <= Length(Rtf) do
    begin
      case Rtf[I] of
        '{':
          begin
            Stack := Stack + [State];
            Inc(I);
          end;
        '}':
          begin
            State := Stack[High(Stack)];
            SetLength(Stack, Length(Stack) - 1);
            Inc(I);
          end;
        #13, #10:
          Inc(I);
        '\':
          begin
            Inc(I);
            if CharInSet(Rtf[I], ['\', '{', '}']) then
            begin
              Emit(Rtf[I]);
              Inc(I);
              Continue;
            end;
            Ctl := '';
            while (I <= Length(Rtf)) and CharInSet(Rtf[I], ['a'..'z']) do
            begin
              Ctl := Ctl + Rtf[I];
              Inc(I);
            end;
            Sign := 1;
            if (I <= Length(Rtf)) and (Rtf[I] = '-') then
            begin
              Sign := -1;
              Inc(I);
            end;
            Digits := '';
            while (I <= Length(Rtf)) and CharInSet(Rtf[I], ['0'..'9']) do
            begin
              Digits := Digits + Rtf[I];
              Inc(I);
            end;
            N := Sign * StrToIntDef(Digits, 0);
            if (I <= Length(Rtf)) and (Rtf[I] = ' ') then
              Inc(I);                                    // the delimiter is not text
            if Ctl = 'par' then
              Emit(#13)
            else if Ctl = 'u' then
            begin
              Emit(Char(System.Word(N)));
              Inc(I);                                    // \uc1: skip the '?'
            end
            else if (Ctl = 'fonttbl') or (Ctl = 'colortbl') then
              State.Skip := True
            else if Ctl = 'highlight' then
              State.Highlight := N
            else if Ctl = 'plain' then
              State.Highlight := 0;
          end;
      else
        Emit(Rtf[I]);
        Inc(I);
      end;
    end;
    Result.Text := Text.ToString;
    Result.Highlight := Levels;
  finally
    Text.Free;
  end;
end;

{ fixtures }

function Para(Index: Integer; Kind: TParagraphKind; const Text: string;
  Page: Integer = 0; OnPage: Integer = 0): TParagraphContent;
begin
  Result := Default(TParagraphContent);
  Result.Ref.Chapter.ModuleId := 'PP';
  Result.Ref.Chapter.ChapterOrder := 3;
  Result.Ref.LogicalIndex := Index;
  Result.Kind := Kind;
  Result.Text := Text;
  Result.StartPageNumber := Page;
  Result.ParagraphOnPage := OnPage;
  Result.PageBreakOffset := -1;
end;

function Hl(Start, Len: Integer): TSearchHighlight;
begin
  Result.StartOffset := Start;
  Result.Len := Len;
end;

function Hit(Index: Integer; const Highlights: TArray<TSearchHighlight>): TParagraphHit;
begin
  Result.LogicalIndex := Index;
  Result.Highlights := Highlights;
end;

function SampleChapter: TChapterContent;
begin
  Result.Ref.ModuleId := 'PP';
  Result.Ref.ChapterOrder := 3;
  Result.Title := 'Спокуса і гріхопадіння';
  Result.Paragraphs := [
    Para(1, pkChapterTitle, 'Спокуса і гріхопадіння'),
    Para(2, pkEpigraph, 'Епіграф {курсивом}'),
    Para(3, pkText, 'Перший абзац сторінки 52 зі словом жертва.', 52, 1),
    Para(4, pkText, 'Другий абзац тієї ж сторінки, жертва і жертви.', 52, 2),
    Para(5, pkSectionHeading, 'Розділ\Підрозділ'),
    Para(6, pkText, 'Табуляція'#9'і рядок'#13#10'посередині 😀.', 53, 1),
    Para(7, pkSourceCitation, '— Патріархи і пророки, с. 53')];
end;

function Theme: TReaderTheme;
begin
  Result := NewReaderTheme(TextFontName);
end;

// The length-preserving replacement as the reader sees it.
function Visible(const S: string): string;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if Ord(Result[I]) < 32 then
      Result[I] := ' ';
end;

function TextAt(const Back: TRtfReadBack; StartChar, Len: Integer): string;
begin
  Result := Copy(Back.Text, StartChar + 1, Len);
end;

{ TChapterRtfBuilderTests }

procedure TChapterRtfBuilderTests.EscapeText_KeepsVisibleLength;
const
  Sample = 'a\b{c}d'#9'ї'#$FB01'😀';
var
  Back: TRtfReadBack;
begin
  Back := ReadBack('{\rtf1\uc1 ' + TChapterRtfBuilder.EscapeText(Sample) + '}');
  Assert.AreEqual(Visible(Sample), Back.Text);
  Assert.AreEqual('\u-1279?', TChapterRtfBuilder.EscapeText(#$FB01), 'above 32767 - negative');
  Assert.AreEqual('\\\{\}', TChapterRtfBuilder.EscapeText('\{}'));
end;

procedure TChapterRtfBuilderTests.Book_PlainTextMatchesMap;
var
  Chapter: TChapterContent;
  Doc: TChapterRtf;
  Back: TRtfReadBack;
  I: Integer;
begin
  Chapter := SampleChapter;
  Doc := TChapterRtfBuilder.Build(Chapter, 'Розділ 3', Theme, THighlightRequest.None);
  Back := ReadBack(Doc.Rtf);

  Assert.AreEqual(Integer(Length(Chapter.Paragraphs)), Integer(Length(Doc.Paragraphs)));
  for I := 0 to High(Doc.Paragraphs) do
  begin
    Assert.AreEqual(Chapter.Paragraphs[I].Ref.LogicalIndex, Doc.Paragraphs[I].LogicalIndex);
    Assert.AreEqual(Visible(Chapter.Paragraphs[I].Text),
      TextAt(Back, Doc.Paragraphs[I].StartChar, Doc.Paragraphs[I].Len),
      'paragraph ' + IntToStr(Doc.Paragraphs[I].LogicalIndex));
  end;
end;

procedure TChapterRtfBuilderTests.Book_ExpectedCharsIsTheVisibleLength;
var
  Doc: TChapterRtf;
  Back: TRtfReadBack;
begin
  Doc := TChapterRtfBuilder.Build(SampleChapter, 'Розділ 3', Theme, THighlightRequest.None);
  Back := ReadBack(Doc.Rtf);
  Assert.AreEqual(Length(Back.Text), Doc.ExpectedChars);
  Assert.IsFalse(Back.Text.EndsWith(#13), 'no \par after the last paragraph');
end;

procedure TChapterRtfBuilderTests.Book_PageMarkerOnlyWhereTextStartsAPage;
var
  Doc: TChapterRtf;
  Back: TRtfReadBack;
  R: TParagraphRange;
begin
  Doc := TChapterRtfBuilder.Build(SampleChapter, 'Розділ 3', Theme, THighlightRequest.None);
  Back := ReadBack(Doc.Rtf);

  R := Doc.Paragraphs[2];                                  // LogicalIndex 3, page 52.1
  Assert.AreEqual(5, R.MarkerLen);
  Assert.AreEqual('[52] ', TextAt(Back, R.StartChar - R.MarkerLen, R.MarkerLen));
  Assert.AreEqual(52, R.PageNumber);
  Assert.AreEqual(1, R.ParagraphOnPage);

  R := Doc.Paragraphs[3];                                  // 52.2 - no marker
  Assert.AreEqual(0, R.MarkerLen);
  Assert.AreEqual(string(#13), TextAt(Back, R.StartChar - 1, 1));
  Assert.AreEqual(2, R.ParagraphOnPage);

  Assert.AreEqual(0, Doc.Paragraphs[1].MarkerLen, 'epigraph never gets a marker');
  Assert.AreEqual('[53] ', TextAt(Back, Doc.Paragraphs[5].StartChar - 5, 5));
end;

procedure TChapterRtfBuilderTests.Book_TitleFromLeadingTitleParagraph;
var
  Doc: TChapterRtf;
  Back: TRtfReadBack;
begin
  Doc := TChapterRtfBuilder.Build(SampleChapter, 'Розділ 3', Theme, THighlightRequest.None);
  Back := ReadBack(Doc.Rtf);
  // Title, label, the empty rule paragraph, then the epigraph.
  Assert.IsTrue(Back.Text.StartsWith('Спокуса і гріхопадіння'#13'Розділ 3'#13#13'Епіграф'), Back.Text);
  Assert.AreEqual(0, Doc.Paragraphs[0].StartChar);
  Assert.Contains(Doc.Rtf, RtfChapterTitle);
  Assert.Contains(Doc.Rtf, RtfChapterLabel);
  Assert.Contains(Doc.Rtf, '\brdrb\brdrs');
end;

procedure TChapterRtfBuilderTests.Book_TitleFallsBackToChapterTitle;
var
  Chapter: TChapterContent;
  Doc: TChapterRtf;
  Back: TRtfReadBack;
begin
  Chapter := SampleChapter;
  Chapter.Paragraphs := Copy(Chapter.Paragraphs, 1, MaxInt);     // no pkChapterTitle
  Chapter.Title := 'Назва з каталогу';
  Doc := TChapterRtfBuilder.Build(Chapter, 'Розділ 3', Theme, THighlightRequest.None);
  Back := ReadBack(Doc.Rtf);
  Assert.IsTrue(Back.Text.StartsWith('Назва з каталогу'#13'Розділ 3'#13#13), Back.Text);
  Assert.AreEqual(Integer(Length(Chapter.Paragraphs)), Integer(Length(Doc.Paragraphs)),
    'the title from the catalog is not a paragraph of the map');
  Assert.AreEqual(2, Doc.Paragraphs[0].LogicalIndex);
end;

procedure TChapterRtfBuilderTests.Book_EveryParagraphResetsCharacterFormatting;
var
  Doc: TChapterRtf;
  Count, P: Integer;
begin
  Doc := TChapterRtfBuilder.Build(SampleChapter, 'Розділ 3', Theme, THighlightRequest.None);
  Count := 0;
  P := Pos('\pard\plain', Doc.Rtf);
  while P > 0 do
  begin
    Inc(Count);
    P := Pos('\pard\plain', Doc.Rtf, P + 1);
  end;
  // 7 paragraphs + label + rule; the title paragraph is one of the 7.
  Assert.AreEqual(9, Count);
  Assert.Contains(Doc.Rtf, RtfEpigraph);
  Assert.Contains(Doc.Rtf, RtfSectionHeading);
  Assert.Contains(Doc.Rtf, RtfSourceCitation);
  Assert.IsFalse(Doc.Rtf.Contains('\sl'), 'line spacing is the font''s own (R4-08)');
end;

procedure TChapterRtfBuilderTests.Book_FocusAndOtherHitsAreBakedIn;
var
  Request: THighlightRequest;
  Doc: TChapterRtf;
  Back: TRtfReadBack;
begin
  // "жертва" in paragraph 3 (offset 35) - focus; "жертва", "жертви" in 4.
  Request.Hits := [Hit(3, [Hl(35, 6)]), Hit(4, [Hl(30, 6), Hl(39, 6)])];
  Request.Focus := 0;
  Doc := TChapterRtfBuilder.Build(SampleChapter, 'Розділ 3', Theme, Request);
  Back := ReadBack(Doc.Rtf);

  Assert.AreEqual('жертва', Back.UnderHighlight(5));
  Assert.AreEqual('жертважертви', Back.UnderHighlight(6));
  Assert.AreEqual(Length(Back.Text), Doc.ExpectedChars, 'highlight groups add no characters');
end;

procedure TChapterRtfBuilderTests.Book_HitStartsPointAtTheFirstMatch;
var
  Request: THighlightRequest;
  Doc: TChapterRtf;
  Back: TRtfReadBack;
begin
  Request.Hits := [Hit(4, [Hl(39, 6), Hl(30, 6)]), Hit(1, [Hl(8, 1)])];   // unsorted on purpose
  Request.Focus := 1;
  Doc := TChapterRtfBuilder.Build(SampleChapter, 'Розділ 3', Theme, Request);
  Back := ReadBack(Doc.Rtf);

  Assert.AreEqual(2, Integer(Length(Doc.HitStarts)));
  Assert.AreEqual('жертва', TextAt(Back, Doc.HitStarts[0], 6));
  Assert.AreEqual(8, Doc.HitStarts[1], 'a match in the title');
  Assert.AreEqual('і', Back.UnderHighlight(5));
end;

procedure TChapterRtfBuilderTests.Book_HitOutsideTheChapterIsMinusOne;
var
  Request: THighlightRequest;
  Doc: TChapterRtf;
begin
  Request.Hits := [Hit(99, [Hl(0, 3)])];
  Request.Focus := 0;
  Doc := TChapterRtfBuilder.Build(SampleChapter, 'Розділ 3', Theme, Request);
  Assert.AreEqual(-1, Doc.HitStarts[0]);
  Assert.IsFalse(Doc.Rtf.Contains(RtfHitCurrent));
end;

procedure TChapterRtfBuilderTests.Book_BadHighlightsAreClampedAndOverlapsDropped;
var
  Request: THighlightRequest;
  Doc: TChapterRtf;
  Back: TRtfReadBack;
  Text: string;
begin
  Text := SampleChapter.Paragraphs[3].Text;                // LogicalIndex 4
  Request.Hits := [Hit(4, [Hl(-1, 3), Hl(0, 0), Hl(0, 6), Hl(3, 5), Hl(Length(Text) - 2, 50),
    Hl(Length(Text) + 5, 2)])];
  Request.Focus := -1;
  Doc := TChapterRtfBuilder.Build(SampleChapter, 'Розділ 3', Theme, Request);
  Back := ReadBack(Doc.Rtf);

  Assert.AreEqual(Copy(Text, 1, 6) + Copy(Text, Length(Text) - 1, 2), Back.UnderHighlight(6));
  Assert.AreEqual(Length(Back.Text), Doc.ExpectedChars);
end;

procedure TChapterRtfBuilderTests.Book_FontsComeFromTheTheme;
var
  Doc: TChapterRtf;
begin
  Doc := TChapterRtfBuilder.Build(SampleChapter, 'Розділ 3', NewReaderTheme(TextFontFallback),
    THighlightRequest.None);
  Assert.IsTrue(Doc.Rtf.StartsWith('{\rtf1\ansi\deff0\uc1'));
  Assert.Contains(Doc.Rtf, '{\f0\fnil\fcharset204 Georgia;}');
  Assert.Contains(Doc.Rtf, '{\f1\fnil\fcharset204 Segoe UI;}');
end;

function SampleBibleChapter: TBibleChapterContent;

  function Verse(N: Integer; const Text: string): TVerseContent;
  begin
    Result.Ref.Chapter.Book.ModuleId := 'ohienko-uk';
    Result.Ref.Chapter.Book.BookCode := 'GEN';
    Result.Ref.Chapter.ChapterNumber := 3;
    Result.Ref.VerseNumber := N;
    Result.Text := Text;
  end;

begin
  Result.Ref.Book.ModuleId := 'ohienko-uk';
  Result.Ref.Book.BookCode := 'GEN';
  Result.Ref.ChapterNumber := 3;
  Result.Verses := [Verse(1, 'А змій був хитріший від усієї польової звірини.'),
    Verse(2, 'І сказала жінка до змія.'),
    Verse(10, 'А той відказав: Я почув Твій голос.')];
end;

procedure TChapterRtfBuilderTests.Bible_VerseNumbersAreMarkersBeforeStartChar;
var
  Chapter: TBibleChapterContent;
  Doc: TChapterRtf;
  Back: TRtfReadBack;
  I: Integer;
  R: TParagraphRange;
begin
  Chapter := SampleBibleChapter;
  Doc := TChapterRtfBuilder.Build(Chapter, 'Буття', 'Розділ 3', Theme, TVerseHighlightRequest.None);
  Back := ReadBack(Doc.Rtf);

  Assert.IsTrue(Back.Text.StartsWith('Буття'#13'Розділ 3'#13#13'1 А змій'), Back.Text);
  Assert.AreEqual(Length(Back.Text), Doc.ExpectedChars);
  Assert.AreEqual(3, Integer(Length(Doc.Paragraphs)));
  for I := 0 to High(Doc.Paragraphs) do
  begin
    R := Doc.Paragraphs[I];
    Assert.AreEqual(Chapter.Verses[I].Ref.VerseNumber, R.LogicalIndex);
    Assert.AreEqual(IntToStr(R.LogicalIndex) + ' ', TextAt(Back, R.StartChar - R.MarkerLen, R.MarkerLen));
    Assert.AreEqual(Chapter.Verses[I].Text, TextAt(Back, R.StartChar, R.Len));
  end;
  Assert.AreEqual(3, Doc.Paragraphs[2].MarkerLen, '"10 "');
  Assert.Contains(Doc.Rtf, RtfVerse);
end;

procedure TChapterRtfBuilderTests.Bible_HitStartsAndFocus;
var
  Request: TVerseHighlightRequest;
  Doc: TChapterRtf;
  Back: TRtfReadBack;
  V: TVerseHit;
begin
  V.VerseNumber := 2;
  V.Highlights := [Hl(10, 5)];                             // "жінка"
  Request.Hits := [V];
  Request.Focus := 0;
  Doc := TChapterRtfBuilder.Build(SampleBibleChapter, 'Буття', 'Розділ 3', Theme, Request);
  Back := ReadBack(Doc.Rtf);

  Assert.AreEqual('жінка', Back.UnderHighlight(5));
  Assert.AreEqual('жінка', TextAt(Back, Doc.HitStarts[0], 5));
end;

procedure TChapterRtfBuilderTests.Where_IdentifiesTheChapter;
begin
  Assert.AreEqual('PP:3', TChapterRtfBuilder.Build(SampleChapter, '', Theme,
    THighlightRequest.None).Where);
  Assert.AreEqual('ohienko-uk:GEN:3', TChapterRtfBuilder.Build(SampleBibleChapter, 'Буття', '',
    Theme, TVerseHighlightRequest.None).Where);
end;

initialization
  TDUnitX.RegisterTestFixture(TChapterRtfBuilderTests);

end.
