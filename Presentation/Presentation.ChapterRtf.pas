unit Presentation.ChapterRtf;

(* TChapterRtfBuilder - one chapter as one RTF document (Slovo_04 C.4, E-01).

  Stateless and window-free: uses System.* and Core.Domain only, so it is tested
  without a form. The form streams Rtf into the RichEdit (EM_STREAMIN), compares
  the control's length with ExpectedChars and scrolls to HitStarts.

  Character map (R6, R4-11). Positions are in the units of EM_GETTEXTLENGTHEX
  without GTL_USECRLF: every UTF-16 code unit of text is 1, every \par is 1.
  Paragraphs are SEPARATED by \par; the document ends with one more \par that
  is NOT counted: RichEdit folds it into its own final paragraph mark (which it
  does not count), and without it RichEdit dropped the paragraph formatting of
  the last paragraph - its \li and tabs (seen on Windows, 2026-11-06).

  Spacing between paragraphs is an EMPTY spacer paragraph of exact height
  (\sl-N\slmult0), never \sa/\sb: RichEdit counts the space after a paragraph
  into the height of its last line and paints \highlight over the whole line,
  so a match at the end of a paragraph got a box reaching into the gap (seen on
  Windows 11). A spacer has no text and so nothing to highlight; it costs one
  more \par (1 character) per gap, which the writer counts like any other.
  Markers stand in the left margin, as the mockup (R4-07 recipe, Vitalii,
  2026-11-06): every paragraph is indented by the margin (\li960 = 64 px); a
  paragraph with a marker hangs its first line back to 0 and tabs twice -
  "\tab[71]\tab text", the marker right-aligned at 44 px (\tqr\tx660), the
  text at 64 px (\tx960). \tx counts from the formatting rectangle's edge.
  The two tabs and the marker stand before StartChar (MarkerLen), so a match
  position is StartChar + Offset with no correction.

  Text goes through one replacement that keeps its length: CR, LF, TAB and other
  control characters become a space; '\', '{', '}' are escaped; everything
  outside ASCII is \uN? (\uc1; N > 32767 is written negative). *)

interface

uses
  Core.Domain,
  Presentation.Theme;

type
  // The map for "Copy with reference" (E-13).
  TParagraphRange = record
    LogicalIndex: Integer;       // for the Bible - VerseNumber
    StartChar, Len: Integer;     // the text in RichEdit coordinates, AFTER the marker; Len = Length(Text)
    MarkerLen: Integer;          // length of "\t[71]\t" / "\t8\t" before StartChar; 0 - no marker
    PageNumber, ParagraphOnPage: Integer;
  end;

  // What to highlight (E-08): ready matches from FTS. Every highlighted word is
  // a match of its own, numbered in document order (the title first); Focus -
  // the number of the current match, -1 - none. The current word gets
  // \highlight5, all the others \highlight6.
  THighlightRequest = record
    Hits: TArray<TParagraphHit>;
    Focus: Integer;
    class function None: THighlightRequest; static;
  end;

  TVerseHighlightRequest = record
    Hits: TArray<TVerseHit>;
    Focus: Integer;
    class function None: TVerseHighlightRequest; static;
  end;

  TChapterRtf = record
    Rtf: string;
    ExpectedChars: Integer;      // visible characters: text, markers, 1 per \par
    Paragraphs: TArray<TParagraphRange>;
    HitStarts: TArray<Integer>;  // per Hits[i]: StartChar of its first match; -1 - not in this chapter
    MatchStarts: TArray<Integer>;   // per match (word), document order: its position in RichEdit
    HitFirstMatch: TArray<Integer>; // per Hits[i]: index in MatchStarts of its first match; -1 - none
    Where: string;               // 'PP:3' / 'ohienko-uk:GEN:3' - for the log line
    TitleLen: Integer;           // the title's characters from 0: the form sizes them (A.2)
  end;

  TChapterRtfBuilder = class
  public
    // ChapterLabel - the localized "Розділ N" under the title; the form passes
    // L('read.chapter', [N]) so the builder stays free of global state.
    class function Build(const Chapter: TChapterContent; const ChapterLabel: string;
      const Theme: TReaderTheme; const Highlight: THighlightRequest): TChapterRtf; overload;
    class function Build(const Chapter: TBibleChapterContent; const BookTitle, ChapterLabel: string;
      const Theme: TReaderTheme; const Highlight: TVerseHighlightRequest): TChapterRtf; overload;

    // The length-preserving replacement, exposed for tests.
    class function EscapeText(const S: string): string; static;
  end;

const
  // Paragraph styles by Kind (B-04) - the ONLY place with RTF font sizes.
  // \fs is half-points: px * 0.75 * 2. Spacing in twips: 1 px = 15 twips.
  // Line spacing as the mockup (R4-08 recipe, Vitalii 2026-11-06; R6 had the
  // font's own): EXACT heights - text 1.72 x 20.5 px = 529 twips, epigraph
  // 1.6 x 19 px = 456. RichEdit paints \highlight over the whole line, so a
  // match gets a box of the full line height (tried first; own painting next
  // if it looks bad).
  // Space before / after a paragraph is NOT in the style: see the Space* pairs
  // below and the spacer paragraphs (unit header).
  RtfChapterTitle    = '\f0\fs69\cf7';                      // 46 px
  RtfChapterLabel    = '\f0\fs26\i\cf3';                    // 17 px
  RtfSubChapterTitle = '\f0\fs42\cf1';                      // 28 px
  RtfEpigraph        = '\li1560\ri600\sl-456\slmult0\f0\fs29\i\cf4';   // 19 px / 1.6, padding 0 40 after the margin; E-10: one block
  RtfSectionHeading  = '\f0\fs31\b\cf1';                    // real Bold file (E-04)
  RtfSourceCitation  = '\qr\f0\fs22\i\cf3';                 // 15 px
  RtfText            = '\sl-529\slmult0\f0\fs31\cf1';       // 20.5 px / 1.72; no first-line indent (mockup)
  RtfVerse           = '\sl-529\slmult0\f0\fs31\cf1';       // as text: 1.72

  // Space before / after, twips. The gap between two paragraphs is the
  // previous After plus the next Before - what \sa + \sb gave in RichEdit.
  SpaceTitleAfter           = 120;
  SpaceLabelAfter           = 240;
  SpaceRuleAfter            = 600;
  SpaceSubChapterBefore     = 480;
  SpaceSubChapterAfter      = 240;
  SpaceEpigraphAfter        = 660;
  SpaceSectionBefore        = 480;
  SpaceSectionAfter         = 240;
  SpaceSourceCitationAfter  = 360;
  SpaceTextAfter            = 360;       // 24 px
  SpaceVerseAfter           = 180;

  // Start of a spacer paragraph; \fs2 keeps the empty line from growing past \sl.
  RtfSpacerStart     = '\pard\plain\sl-';
  // The left margin of every paragraph (64 px): the markers' zone, A.5.
  RtfMargin          = '\li960';
  // A paragraph with a marker: the first line hangs to 0, the marker
  // right-aligned at 44 px, the text at 64 px.
  RtfMarkerTabs      = '\fi-960\tqr\tx660\tx960';
  RtfPageMarker      = '\f1\fs16\cf2';                       // "[71]", 10.5 px #8a8a8a
  RtfVerseNumber     = '\fs19\cf3';                          // "8", .62em #767676
  RtfHitCurrent      = '\highlight5';
  RtfHitOther        = '\highlight6';

  // The short rule under the title (A.1), muted, aligned with the title and
  // "Розділ N" on the left. ONE glyph: consecutive dashes leave gaps (side
  // bearings). EB Garamond has the three-em dash U+2E3B; Georgia does not, so
  // the fallback font gets em dashes, which Georgia draws joined.
  RtfRule            = '\f0\fs34\cf3';           // U+2E3B at 17 pt ~ 56 px: the mockup's 58 px line
  RuleTextGaramond   = #$2E3B;
  RuleTextFallback   = #$2014#$2014;

function RuleTextFor(const Theme: TReaderTheme): string;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults;

const
  // Fixed colour table (R6, R4-09): \cf1 text, \cf2 marker, \cf3 muted,
  // \cf4 epigraph, \cf5/\cf6 hit backgrounds (\highlight5/6), \cf7 heading.
  RtfColorTable =
    '{\colortbl;' +
    '\red47\green47\blue47;' +      // 1 #2f2f2f
    '\red138\green138\blue138;' +   // 2 #8a8a8a
    '\red118\green118\blue118;' +   // 3 #767676
    '\red74\green74\blue74;' +      // 4 #4a4a4a
    '\red202\green215\blue230;' +   // 5 #CAD7E6
    '\red228\green235\blue244;' +   // 6 #E4EBF4
    '\red36\green36\blue36;}';      // 7 #242424

type
  // Accumulates the document and counts visible characters as it goes, so the
  // map and ExpectedChars cannot drift from the RTF that was written.
  TRtfWriter = class
  private
    FOut: TStringBuilder;
    FChars: Integer;
    FParagraphs: Integer;
    FPendingAfter: Integer;                          // After of the previous paragraph, twips
  public
    constructor Create;
    destructor Destroy; override;
    procedure Raw(const S: string);
    procedure Text(const S: string);                 // escaped; counts Length(S)
    procedure Tab;                                   // \tab - 1 character
    // \par before every paragraph but the first, and a spacer of After of the
    // previous + Before of this one when that is more than 0.
    procedure BeginParagraph(const Style: string; Before, After: Integer);
    function ToRtf: string;
    property Chars: Integer read FChars;
  end;

constructor TRtfWriter.Create;
begin
  inherited;
  FOut := TStringBuilder.Create(16 * 1024);
end;

destructor TRtfWriter.Destroy;
begin
  FOut.Free;
  inherited;
end;

procedure TRtfWriter.Raw(const S: string);
begin
  FOut.Append(S);
end;

procedure TRtfWriter.Text(const S: string);
begin
  FOut.Append(TChapterRtfBuilder.EscapeText(S));
  Inc(FChars, Length(S));
end;

procedure TRtfWriter.Tab;
begin
  FOut.Append('\tab ');
  Inc(FChars);
end;

procedure TRtfWriter.BeginParagraph(const Style: string; Before, After: Integer);
var
  Gap: Integer;
begin
  if FParagraphs > 0 then
  begin
    FOut.Append('\par'#13#10);
    Inc(FChars);
    Gap := FPendingAfter + Before;
    if Gap > 0 then
    begin
      FOut.Append(RtfSpacerStart).Append(Gap).Append('\slmult0\fs2 \par'#13#10);
      Inc(FChars);
    end;
  end;
  Inc(FParagraphs);
  FPendingAfter := After;
  // \plain resets the character formatting: italic of an epigraph must not
  // leak into the next paragraph. The trailing space ends the control word.
  FOut.Append('\pard\plain').Append(RtfMargin).Append(Style).Append(' ');
end;

function TRtfWriter.ToRtf: string;
begin
  Result := FOut.ToString;
end;

{ THighlightRequest }

class function THighlightRequest.None: THighlightRequest;
begin
  Result.Hits := nil;
  Result.Focus := -1;
end;

class function TVerseHighlightRequest.None: TVerseHighlightRequest;
begin
  Result.Hits := nil;
  Result.Focus := -1;
end;

{ helpers }

function FontTable(const Theme: TReaderTheme): string;
begin
  // Font names are ASCII; \fcharset204 keeps older RichEdit from guessing.
  Result := '{\fonttbl{\f0\fnil\fcharset204 ' + Theme.TextFont + ';}' +
    '{\f1\fnil\fcharset204 ' + Theme.UiFont + ';}}';
end;

procedure WriteHeader(W: TRtfWriter; const Theme: TReaderTheme);
begin
  W.Raw('{\rtf1\ansi\deff0\uc1'#13#10);
  W.Raw(FontTable(Theme) + #13#10);
  W.Raw(RtfColorTable + #13#10);
end;

// Under the title: "Розділ N" and the rule.
function RuleTextFor(const Theme: TReaderTheme): string;
begin
  if SameText(Theme.TextFont, TextFontName) then
    Result := RuleTextGaramond
  else
    Result := RuleTextFallback;
end;

procedure WriteLabelAndRule(W: TRtfWriter; const ChapterLabel: string; const Theme: TReaderTheme);
begin
  W.BeginParagraph(RtfChapterLabel, 0, SpaceLabelAfter);
  W.Text(ChapterLabel);
  // RichEdit keeps paragraph borders but does not draw them, so the rule is
  // text. It is never empty: an empty last paragraph would be swallowed into
  // RichEdit's own final mark and the count would be one short.
  W.BeginParagraph(RtfRule, 0, SpaceRuleAfter);
  W.Text(RuleTextFor(Theme));
end;

// Normalised highlights: inside the text, sorted, without overlaps.
function CleanHighlights(const Highlights: TArray<TSearchHighlight>; TextLen: Integer): TArray<TSearchHighlight>;
var
  List: TList<TSearchHighlight>;
  H: TSearchHighlight;
  LastEnd: Integer;
begin
  List := TList<TSearchHighlight>.Create;
  try
    for H in Highlights do
      if (H.Len > 0) and (H.StartOffset >= 0) and (H.StartOffset < TextLen) then
      begin
        var C := H;
        if C.StartOffset + C.Len > TextLen then
          C.Len := TextLen - C.StartOffset;
        List.Add(C);
      end;
    List.Sort(TComparer<TSearchHighlight>.Construct(
      function(const A, B: TSearchHighlight): Integer
      begin
        Result := CompareValue(A.StartOffset, B.StartOffset);
      end));
    Result := nil;
    LastEnd := 0;
    for H in List do
      if H.StartOffset >= LastEnd then
      begin
        Result := Result + [H];
        LastEnd := H.StartOffset + H.Len;
      end;
  finally
    List.Free;
  end;
end;

// The paragraph text with the matches baked in as {\highlightN ...} groups.
// Every match is numbered in document order; Starts gets its position.
// Result - the number of the paragraph's first match; -1 when cleaning left none.
function WriteHighlightedText(W: TRtfWriter; const Text: string;
  const Highlights: TArray<TSearchHighlight>; Focus: Integer; Starts: TList<Integer>): Integer;
var
  H: TSearchHighlight;
  Pos: Integer;
  Group: string;
begin
  Result := Starts.Count;
  Pos := 0;
  for H in CleanHighlights(Highlights, Length(Text)) do
  begin
    W.Text(Copy(Text, Pos + 1, H.StartOffset - Pos));
    if Starts.Count = Focus then
      Group := RtfHitCurrent
    else
      Group := RtfHitOther;
    Starts.Add(W.Chars);
    W.Raw('{' + Group + ' ');
    W.Text(Copy(Text, H.StartOffset + 1, H.Len));
    W.Raw('}');
    Pos := H.StartOffset + H.Len;
  end;
  W.Text(Copy(Text, Pos + 1, MaxInt));
  if Starts.Count = Result then
    Result := -1;
end;

function StyleFor(Kind: TParagraphKind): string;
begin
  case Kind of
    pkChapterTitle:    Result := RtfChapterTitle;
    pkSubChapterTitle: Result := RtfSubChapterTitle;
    pkEpigraph:        Result := RtfEpigraph;
    pkSectionHeading:  Result := RtfSectionHeading;
    pkSourceCitation:  Result := RtfSourceCitation;
  else
    Result := RtfText;
  end;
end;

function SpaceBeforeFor(Kind: TParagraphKind): Integer;
begin
  case Kind of
    pkSubChapterTitle: Result := SpaceSubChapterBefore;
    pkSectionHeading:  Result := SpaceSectionBefore;
  else
    Result := 0;
  end;
end;

function SpaceAfterFor(Kind: TParagraphKind): Integer;
begin
  case Kind of
    pkChapterTitle:    Result := SpaceTitleAfter;
    pkSubChapterTitle: Result := SpaceSubChapterAfter;
    pkEpigraph:        Result := SpaceEpigraphAfter;
    pkSectionHeading:  Result := SpaceSectionAfter;
    pkSourceCitation:  Result := SpaceSourceCitationAfter;
  else
    Result := SpaceTextAfter;
  end;
end;

function FirstMatchStart(const Highlights: TArray<TSearchHighlight>; StartChar, TextLen: Integer): Integer;
var
  Clean: TArray<TSearchHighlight>;
begin
  Clean := CleanHighlights(Highlights, TextLen);
  if Length(Clean) = 0 then
    Result := StartChar
  else
    Result := StartChar + Clean[0].StartOffset;
end;

{ TChapterRtfBuilder }

class function TChapterRtfBuilder.EscapeText(const S: string): string;
var
  B: TStringBuilder;
  C: Char;
  Code: Integer;
begin
  B := TStringBuilder.Create(Length(S) + 16);
  try
    for C in S do
    begin
      Code := Ord(C);
      if Code < 32 then
        B.Append(' ')                                   // CR, LF, TAB, other controls
      else if (C = '\') or (C = '{') or (C = '}') then
        B.Append('\').Append(C)
      else if Code < 128 then
        B.Append(C)
      else
      begin
        if Code > 32767 then
          Code := Code - 65536;                         // RTF \u is a signed 16-bit value
        B.Append('\u').Append(Code).Append('?');        // each UTF-16 unit, surrogates too
      end;
    end;
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

class function TChapterRtfBuilder.Build(const Chapter: TChapterContent;
  const ChapterLabel: string; const Theme: TReaderTheme;
  const Highlight: THighlightRequest): TChapterRtf;
var
  W: TRtfWriter;
  HitIndex: TDictionary<Integer, Integer>;     // LogicalIndex -> index in Highlight.Hits
  Ranges: TList<TParagraphRange>;
  Starts: TList<Integer>;
  P: TParagraphContent;
  R: TParagraphRange;
  Marker, Title: string;
  HasMarker: Boolean;
  I, First, HitAt: Integer;
begin
  Result.Where := Format('%s:%d', [string(Chapter.Ref.ModuleId), Chapter.Ref.ChapterOrder]);
  SetLength(Result.HitStarts, Length(Highlight.Hits));
  SetLength(Result.HitFirstMatch, Length(Highlight.Hits));
  for I := 0 to High(Result.HitStarts) do
  begin
    Result.HitStarts[I] := -1;
    Result.HitFirstMatch[I] := -1;
  end;

  W := TRtfWriter.Create;
  HitIndex := TDictionary<Integer, Integer>.Create;
  Ranges := TList<TParagraphRange>.Create;
  Starts := TList<Integer>.Create;
  try
    for I := 0 to High(Highlight.Hits) do
      HitIndex.AddOrSetValue(Highlight.Hits[I].LogicalIndex, I);

    WriteHeader(W, Theme);

    // The first block is the title, "Розділ N" and the rule. The title comes from
    // a leading pkChapterTitle paragraph when there is one, else from the chapter.
    First := 0;
    if (Length(Chapter.Paragraphs) > 0) and (Chapter.Paragraphs[0].Kind = pkChapterTitle) then
    begin
      Title := Chapter.Paragraphs[0].Text;
      First := 1;
    end
    else
      Title := Chapter.Title;
    W.BeginParagraph(RtfChapterTitle, 0, SpaceTitleAfter);
    if First = 1 then
    begin
      // The title is a paragraph of the chapter too: it can be quoted and matched.
      R := Default(TParagraphRange);
      R.LogicalIndex := Chapter.Paragraphs[0].Ref.LogicalIndex;
      R.StartChar := W.Chars;
      R.Len := Length(Title);
      if HitIndex.TryGetValue(R.LogicalIndex, HitAt) then
      begin
        Result.HitFirstMatch[HitAt] :=
          WriteHighlightedText(W, Title, Highlight.Hits[HitAt].Highlights, Highlight.Focus, Starts);
        Result.HitStarts[HitAt] := FirstMatchStart(Highlight.Hits[HitAt].Highlights, R.StartChar, R.Len);
      end
      else
        W.Text(Title);
      Ranges.Add(R);
    end
    else
      W.Text(Title);
    Result.TitleLen := W.Chars;
    WriteLabelAndRule(W, ChapterLabel, Theme);

    for I := First to High(Chapter.Paragraphs) do
    begin
      P := Chapter.Paragraphs[I];
      if P.Kind = pkPageMarker then
        Continue;                               // never stored; ignore if it ever comes
      // Marker only where a text paragraph starts a page (R6, R4-07).
      HasMarker := (P.Kind = pkText) and (P.StartPageNumber > 0) and (P.ParagraphOnPage = 1);
      if HasMarker then
        W.BeginParagraph(StyleFor(P.Kind) + RtfMarkerTabs, SpaceBeforeFor(P.Kind), SpaceAfterFor(P.Kind))
      else
        W.BeginParagraph(StyleFor(P.Kind), SpaceBeforeFor(P.Kind), SpaceAfterFor(P.Kind));

      R := Default(TParagraphRange);
      R.LogicalIndex := P.Ref.LogicalIndex;
      R.PageNumber := P.StartPageNumber;
      R.ParagraphOnPage := P.ParagraphOnPage;
      if HasMarker then
      begin
        Marker := Format('[%d]', [P.StartPageNumber]);
        W.Tab;
        W.Raw('{' + RtfPageMarker + ' ');
        W.Text(Marker);
        W.Raw('}');
        W.Tab;
        R.MarkerLen := Length(Marker) + 2;
      end;
      R.StartChar := W.Chars;
      R.Len := Length(P.Text);

      if HitIndex.TryGetValue(R.LogicalIndex, HitAt) then
      begin
        Result.HitFirstMatch[HitAt] :=
          WriteHighlightedText(W, P.Text, Highlight.Hits[HitAt].Highlights, Highlight.Focus, Starts);
        Result.HitStarts[HitAt] := FirstMatchStart(Highlight.Hits[HitAt].Highlights, R.StartChar, R.Len);
      end
      else
        W.Text(P.Text);
      Ranges.Add(R);
    end;

    W.Raw('\par}');                            // uncounted: see the unit header
    Result.Rtf := W.ToRtf;
    Result.ExpectedChars := W.Chars;
    Result.Paragraphs := Ranges.ToArray;
    Result.MatchStarts := Starts.ToArray;
  finally
    Starts.Free;
    Ranges.Free;
    HitIndex.Free;
    W.Free;
  end;
end;

class function TChapterRtfBuilder.Build(const Chapter: TBibleChapterContent;
  const BookTitle, ChapterLabel: string; const Theme: TReaderTheme;
  const Highlight: TVerseHighlightRequest): TChapterRtf;
var
  W: TRtfWriter;
  HitIndex: TDictionary<Integer, Integer>;     // VerseNumber -> index in Highlight.Hits
  Ranges: TList<TParagraphRange>;
  Starts: TList<Integer>;
  V: TVerseContent;
  R: TParagraphRange;
  Marker: string;
  I, HitAt: Integer;
begin
  Result.Where := Format('%s:%s:%d', [string(Chapter.Ref.Book.ModuleId),
    string(Chapter.Ref.Book.BookCode), Chapter.Ref.ChapterNumber]);
  SetLength(Result.HitStarts, Length(Highlight.Hits));
  SetLength(Result.HitFirstMatch, Length(Highlight.Hits));
  for I := 0 to High(Result.HitStarts) do
  begin
    Result.HitStarts[I] := -1;
    Result.HitFirstMatch[I] := -1;
  end;

  W := TRtfWriter.Create;
  HitIndex := TDictionary<Integer, Integer>.Create;
  Ranges := TList<TParagraphRange>.Create;
  Starts := TList<Integer>.Create;
  try
    for I := 0 to High(Highlight.Hits) do
      HitIndex.AddOrSetValue(Highlight.Hits[I].VerseNumber, I);

    WriteHeader(W, Theme);
    W.BeginParagraph(RtfChapterTitle, 0, SpaceTitleAfter);
    W.Text(BookTitle);
    Result.TitleLen := W.Chars;
    WriteLabelAndRule(W, ChapterLabel, Theme);

    for V in Chapter.Verses do
    begin
      W.BeginParagraph(RtfVerse + RtfMarkerTabs, 0, SpaceVerseAfter);
      R := Default(TParagraphRange);
      R.LogicalIndex := V.Ref.VerseNumber;
      Marker := IntToStr(V.Ref.VerseNumber);
      W.Tab;
      W.Raw('{' + RtfVerseNumber + ' ');
      W.Text(Marker);
      W.Raw('}');
      W.Tab;
      R.MarkerLen := Length(Marker) + 2;
      R.StartChar := W.Chars;
      R.Len := Length(V.Text);

      if HitIndex.TryGetValue(R.LogicalIndex, HitAt) then
      begin
        Result.HitFirstMatch[HitAt] :=
          WriteHighlightedText(W, V.Text, Highlight.Hits[HitAt].Highlights, Highlight.Focus, Starts);
        Result.HitStarts[HitAt] := FirstMatchStart(Highlight.Hits[HitAt].Highlights, R.StartChar, R.Len);
      end
      else
        W.Text(V.Text);
      Ranges.Add(R);
    end;

    W.Raw('\par}');                            // uncounted: see the unit header
    Result.Rtf := W.ToRtf;
    Result.ExpectedChars := W.Chars;
    Result.Paragraphs := Ranges.ToArray;
    Result.MatchStarts := Starts.ToArray;
  finally
    Starts.Free;
    Ranges.Free;
    HitIndex.Free;
    W.Free;
  end;
end;

end.
