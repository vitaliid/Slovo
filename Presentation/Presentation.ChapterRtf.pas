unit Presentation.ChapterRtf;

(* TChapterRtfBuilder - one chapter as one RTF document (Slovo_04 C.4, E-01).

  Stateless and window-free: uses System.* and Core.Domain only, so it is tested
  without a form. The form streams Rtf into the RichEdit (EM_STREAMIN), compares
  the control's length with ExpectedChars and scrolls to HitStarts.

  Character map (R6, R4-11). Positions are in the units of EM_GETTEXTLENGTHEX
  without GTL_USECRLF: every UTF-16 code unit of text is 1, every \par is 1.
  Paragraphs are SEPARATED by \par - there is none after the last one, because
  RichEdit keeps its own final paragraph mark, which it does not count.
  A marker ("[71] ", "8 ") stands before StartChar, so a match position is
  StartChar + Offset with no correction.

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
    MarkerLen: Integer;          // length of "[71] " / "8 " before StartChar; 0 - no marker
    PageNumber, ParagraphOnPage: Integer;
  end;

  // What to highlight (E-08): ready matches from FTS. Focus - index in Hits of the
  // current paragraph (or verse); -1 - none.
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
    Where: string;               // 'PP:3' / 'ohienko-uk:GEN:3' - for the log line
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
  // Line spacing is the font's own; \sl is never set (R6, R4-08).
  RtfChapterTitle    = '\f0\fs69\cf7\sa120';                 // 46 px
  RtfChapterLabel    = '\f0\fs26\i\cf3\sa240';               // 17 px
  RtfSubChapterTitle = '\sb480\sa240\f0\fs42\cf1';           // 28 px
  RtfEpigraph        = '\li600\ri600\sa660\f0\fs29\i\cf4';   // 19 px, E-10: one block
  RtfSectionHeading  = '\sb480\sa240\f0\fs31\b\cf1';         // real Bold file (E-04)
  RtfSourceCitation  = '\qr\sa360\f0\fs22\i\cf3';            // 15 px
  RtfText            = '\fi360\sa360\f0\fs31\cf1';           // 20.5 px; 24 px indent and after
  RtfVerse           = '\sa180\f0\fs31\cf1';
  RtfPageMarker      = '\f1\fs16\cf2';                       // "[71] "
  RtfVerseNumber     = '\fs19\cf2';                          // "8 "
  RtfHitCurrent      = '\highlight5';
  RtfHitOther        = '\highlight6';

  // The short rule under the title (A.1), muted, aligned with the title and
  // "Розділ N" on the left. ONE glyph: consecutive dashes leave gaps (side
  // bearings). EB Garamond has the three-em dash U+2E3B; Georgia does not, so
  // the fallback font gets em dashes, which Georgia draws joined.
  RtfRule            = '\sa600\f0\fs22\cf3';
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
  public
    constructor Create;
    destructor Destroy; override;
    procedure Raw(const S: string);
    procedure Text(const S: string);                 // escaped; counts Length(S)
    procedure BeginParagraph(const Style: string);   // \par before every paragraph but the first
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

procedure TRtfWriter.BeginParagraph(const Style: string);
begin
  if FParagraphs > 0 then
  begin
    FOut.Append('\par'#13#10);
    Inc(FChars);
  end;
  Inc(FParagraphs);
  // \plain resets the character formatting: italic of an epigraph must not
  // leak into the next paragraph. The trailing space ends the control word.
  FOut.Append('\pard\plain').Append(Style).Append(' ');
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
  W.BeginParagraph(RtfChapterLabel);
  W.Text(ChapterLabel);
  // RichEdit keeps paragraph borders but does not draw them, so the rule is
  // text. It is never empty: an empty last paragraph would be swallowed into
  // RichEdit's own final mark and the count would be one short.
  W.BeginParagraph(RtfRule);
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
procedure WriteHighlightedText(W: TRtfWriter; const Text: string;
  const Highlights: TArray<TSearchHighlight>; IsFocus: Boolean);
var
  H: TSearchHighlight;
  Pos: Integer;
  Group: string;
begin
  if IsFocus then
    Group := RtfHitCurrent
  else
    Group := RtfHitOther;
  Pos := 0;
  for H in CleanHighlights(Highlights, Length(Text)) do
  begin
    W.Text(Copy(Text, Pos + 1, H.StartOffset - Pos));
    W.Raw('{' + Group + ' ');
    W.Text(Copy(Text, H.StartOffset + 1, H.Len));
    W.Raw('}');
    Pos := H.StartOffset + H.Len;
  end;
  W.Text(Copy(Text, Pos + 1, MaxInt));
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
  P: TParagraphContent;
  R: TParagraphRange;
  Marker, Title: string;
  I, First, HitAt: Integer;
begin
  Result.Where := Format('%s:%d', [string(Chapter.Ref.ModuleId), Chapter.Ref.ChapterOrder]);
  SetLength(Result.HitStarts, Length(Highlight.Hits));
  for I := 0 to High(Result.HitStarts) do
    Result.HitStarts[I] := -1;

  W := TRtfWriter.Create;
  HitIndex := TDictionary<Integer, Integer>.Create;
  Ranges := TList<TParagraphRange>.Create;
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
    W.BeginParagraph(RtfChapterTitle);
    if First = 1 then
    begin
      // The title is a paragraph of the chapter too: it can be quoted and matched.
      R := Default(TParagraphRange);
      R.LogicalIndex := Chapter.Paragraphs[0].Ref.LogicalIndex;
      R.StartChar := W.Chars;
      R.Len := Length(Title);
      if HitIndex.TryGetValue(R.LogicalIndex, HitAt) then
      begin
        WriteHighlightedText(W, Title, Highlight.Hits[HitAt].Highlights, HitAt = Highlight.Focus);
        Result.HitStarts[HitAt] := FirstMatchStart(Highlight.Hits[HitAt].Highlights, R.StartChar, R.Len);
      end
      else
        W.Text(Title);
      Ranges.Add(R);
    end
    else
      W.Text(Title);
    WriteLabelAndRule(W, ChapterLabel, Theme);

    for I := First to High(Chapter.Paragraphs) do
    begin
      P := Chapter.Paragraphs[I];
      if P.Kind = pkPageMarker then
        Continue;                               // never stored; ignore if it ever comes
      W.BeginParagraph(StyleFor(P.Kind));

      R := Default(TParagraphRange);
      R.LogicalIndex := P.Ref.LogicalIndex;
      R.PageNumber := P.StartPageNumber;
      R.ParagraphOnPage := P.ParagraphOnPage;
      // Marker only where a text paragraph starts a page (R6, R4-07).
      if (P.Kind = pkText) and (P.StartPageNumber > 0) and (P.ParagraphOnPage = 1) then
      begin
        Marker := Format('[%d] ', [P.StartPageNumber]);
        W.Raw('{' + RtfPageMarker + ' ');
        W.Text(Marker);
        W.Raw('}');
        R.MarkerLen := Length(Marker);
      end;
      R.StartChar := W.Chars;
      R.Len := Length(P.Text);

      if HitIndex.TryGetValue(R.LogicalIndex, HitAt) then
      begin
        WriteHighlightedText(W, P.Text, Highlight.Hits[HitAt].Highlights, HitAt = Highlight.Focus);
        Result.HitStarts[HitAt] := FirstMatchStart(Highlight.Hits[HitAt].Highlights, R.StartChar, R.Len);
      end
      else
        W.Text(P.Text);
      Ranges.Add(R);
    end;

    W.Raw('}');
    Result.Rtf := W.ToRtf;
    Result.ExpectedChars := W.Chars;
    Result.Paragraphs := Ranges.ToArray;
  finally
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
  V: TVerseContent;
  R: TParagraphRange;
  Marker: string;
  I, HitAt: Integer;
begin
  Result.Where := Format('%s:%s:%d', [string(Chapter.Ref.Book.ModuleId),
    string(Chapter.Ref.Book.BookCode), Chapter.Ref.ChapterNumber]);
  SetLength(Result.HitStarts, Length(Highlight.Hits));
  for I := 0 to High(Result.HitStarts) do
    Result.HitStarts[I] := -1;

  W := TRtfWriter.Create;
  HitIndex := TDictionary<Integer, Integer>.Create;
  Ranges := TList<TParagraphRange>.Create;
  try
    for I := 0 to High(Highlight.Hits) do
      HitIndex.AddOrSetValue(Highlight.Hits[I].VerseNumber, I);

    WriteHeader(W, Theme);
    W.BeginParagraph(RtfChapterTitle);
    W.Text(BookTitle);
    WriteLabelAndRule(W, ChapterLabel, Theme);

    for V in Chapter.Verses do
    begin
      W.BeginParagraph(RtfVerse);
      R := Default(TParagraphRange);
      R.LogicalIndex := V.Ref.VerseNumber;
      Marker := IntToStr(V.Ref.VerseNumber) + ' ';
      W.Raw('{' + RtfVerseNumber + ' ');
      W.Text(Marker);
      W.Raw('}');
      R.MarkerLen := Length(Marker);
      R.StartChar := W.Chars;
      R.Len := Length(V.Text);

      if HitIndex.TryGetValue(R.LogicalIndex, HitAt) then
      begin
        WriteHighlightedText(W, V.Text, Highlight.Hits[HitAt].Highlights, HitAt = Highlight.Focus);
        Result.HitStarts[HitAt] := FirstMatchStart(Highlight.Hits[HitAt].Highlights, R.StartChar, R.Len);
      end
      else
        W.Text(V.Text);
      Ranges.Add(R);
    end;

    W.Raw('}');
    Result.Rtf := W.ToRtf;
    Result.ExpectedChars := W.Chars;
    Result.Paragraphs := Ranges.ToArray;
  finally
    Ranges.Free;
    HitIndex.Free;
    W.Free;
  end;
end;

end.
