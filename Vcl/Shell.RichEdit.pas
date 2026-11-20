unit Shell.RichEdit;

(* The few RichEdit messages the reader needs (Slovo_04 C.4, E-01, E-11).

  Everything goes through messages on the window handle, not through
  TRichEdit.Lines: Lines would convert the text, hide the stream error and
  count characters differently from the map TChapterRtfBuilder produces.
  Positions here are in the same units as that map - EM_GETTEXTLENGTHEX
  without GTL_USECRLF, 1 per paragraph mark. *)

interface

uses
  Vcl.ComCtrls;

// Once per handle, and again before every load - a recreated window loses them:
// no 32K text limit (EM_STREAMIN would silently cut the chapter), no undo
// buffer (read-only), no automatic font substitution for Cyrillic (R4-18).
procedure PrepareReader(Reader: TRichEdit);

// EM_STREAMIN with SF_RTF. The builder escapes everything outside ASCII, so the
// string goes in as ASCII bytes. StreamError = EDITSTREAM.dwError (0 = fine).
procedure StreamInRtf(Reader: TRichEdit; const Rtf: string; out StreamError: Integer);

// EM_GETTEXTLENGTHEX, GTL_PRECISE or GTL_NUMCHARS, UTF-16 - compare with ExpectedChars.
function PreciseLength(Reader: TRichEdit): Integer;

// E-11: text size in 96-DPI pixels over the base RTF size of BaseTextPx.
procedure SetZoomPx(Reader: TRichEdit; Px: Double);

// Caret to CharPos and the line with it a little below the top of the view.
procedure ScrollToChar(Reader: TRichEdit; CharPos: Integer);

// The boxes of the matches, painted over the text RichEdit has just painted
// (call after its WM_PAINT). RichEdit's own \highlight fills the whole line,
// whose extra height is above the letters; these boxes stand around the
// letters. Starts / Lens - positions in the control; Focus - the match being
// looked at (-1 = none); EmPx - the text size on screen, in device pixels.
// The fill is "screen AND colour": the page darkens to the colour, the letters
// stay dark - and painting the same box twice changes nothing, so every paint
// may repeat all the visible ones.
procedure PaintMatchBoxes(Reader: TRichEdit; const Starts, Lens: TArray<Integer>; Focus, EmPx: Integer);

// E-24: the amber strip at the left edge of the reader beside the paragraph a
// page leads to - from its first line to its last. StartChar / Len - the
// paragraph in the control (its text, after the marker). Call after WM_PAINT.
procedure PaintParagraphMark(Reader: TRichEdit; StartChar, Len, EmPx: Integer);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  Winapi.Windows,
  Winapi.Messages,
  Winapi.RichEdit,
  System.Types,
  Vcl.Graphics,
  Presentation.Theme;

const
  LinesAboveTarget = 2;

function StreamInCallback(dwCookie: DWORD_PTR; pbBuff: PByte; cb: Longint;
  var pcb: Longint): Longint; stdcall;
begin
  pcb := TStream(dwCookie).Read(pbBuff^, cb);
  Result := 0;
end;

procedure PrepareReader(Reader: TRichEdit);
var
  Options: LRESULT;
begin
  SendMessage(Reader.Handle, EM_EXLIMITTEXT, 0, $7FFFFFFE);
  SendMessage(Reader.Handle, EM_SETUNDOLIMIT, 0, 0);
  Options := SendMessage(Reader.Handle, EM_GETLANGOPTIONS, 0, 0);
  SendMessage(Reader.Handle, EM_SETLANGOPTIONS, 0, Options and not IMF_AUTOFONT);
end;

procedure StreamInRtf(Reader: TRichEdit; const Rtf: string; out StreamError: Integer);
var
  Stream: TBytesStream;
  ES: TEditStream;
begin
  PrepareReader(Reader);
  Stream := TBytesStream.Create(TEncoding.ASCII.GetBytes(Rtf));
  try
    ES.dwCookie := DWORD_PTR(Stream);
    ES.dwError := 0;
    ES.pfnCallback := @StreamInCallback;
    SendMessage(Reader.Handle, EM_STREAMIN, SF_RTF, LPARAM(@ES));
    StreamError := ES.dwError;
  finally
    Stream.Free;
  end;
end;

function PreciseLength(Reader: TRichEdit): Integer;
var
  GTL: TGetTextLengthEx;
begin
  GTL.flags := GTL_PRECISE or GTL_NUMCHARS;
  GTL.codepage := 1200;                       // UTF-16
  Result := Integer(SendMessage(Reader.Handle, EM_GETTEXTLENGTHEX, WPARAM(@GTL), 0));
end;

procedure SetZoomPx(Reader: TRichEdit; Px: Double);
begin
  // EM_SETZOOM takes a ratio; Px / BaseTextPx in tenths of a pixel.
  SendMessage(Reader.Handle, EM_SETZOOM, Round(Px * 10), Round(BaseTextPx * 10));
end;

procedure ScrollToChar(Reader: TRichEdit; CharPos: Integer);
var
  Range: TCharRange;
  TargetLine, FirstLine: Integer;
begin
  Range.cpMin := CharPos;
  Range.cpMax := CharPos;
  SendMessage(Reader.Handle, EM_EXSETSEL, 0, LPARAM(@Range));
  SendMessage(Reader.Handle, EM_SCROLLCARET, 0, 0);
  TargetLine := Integer(SendMessage(Reader.Handle, EM_EXLINEFROMCHAR, 0, CharPos));
  FirstLine := Integer(SendMessage(Reader.Handle, EM_GETFIRSTVISIBLELINE, 0, 0));
  SendMessage(Reader.Handle, EM_LINESCROLL, 0, Max(TargetLine - LinesAboveTarget, 0) - FirstLine);
end;

procedure PaintMatchBoxes(Reader: TRichEdit; const Starts, Lens: TArray<Integer>; Focus, EmPx: Integer);
const
  DestAndPattern = $00A000C9;                 // ternary raster op DPa

var
  DC: HDC;
  Client: TRect;

  function PosOf(CharPos: Integer): TPoint;
  var
    P: TPointL;
  begin
    P.x := 0;
    P.y := 0;
    SendMessage(Reader.Handle, EM_POSFROMCHAR, WPARAM(@P), CharPos);
    Result := Point(P.x, P.y);
  end;

  procedure Fill(const R: TRect; Color: TColor);
  var
    Brush, Old: HGDIOBJ;
  begin
    if (R.Right <= R.Left) or (R.Bottom <= R.Top) then
      Exit;
    Brush := CreateSolidBrush(ColorToRGB(Color));
    Old := SelectObject(DC, Brush);
    PatBlt(DC, R.Left, R.Top, R.Width, R.Height, DestAndPattern);
    SelectObject(DC, Old);
    DeleteObject(Brush);
  end;

  // One match, line by line: a phrase may wrap.
  procedure PaintOne(Start, Len: Integer; Color: TColor);
  var
    C, Stop, SegEnd, Line, NextStart, Left, Right, Bottom, LineHeight, Font, Baseline, PadX: Integer;
    P: TPoint;
  begin
    C := Start;
    Stop := Start + Len;
    PadX := Max(EmPx div 8, 2);
    while C < Stop do
    begin
      Line := Integer(SendMessage(Reader.Handle, EM_EXLINEFROMCHAR, 0, C));
      NextStart := Integer(SendMessage(Reader.Handle, EM_LINEINDEX, Line + 1, 0));
      P := PosOf(C);
      Left := P.X;
      if (NextStart > C) and (NextStart < Stop) then
      begin
        // The match goes on to the next line: this piece ends with the line's
        // last character (the space the line was broken at).
        SegEnd := NextStart;
        Right := PosOf(NextStart - 1).X;
      end
      else
      begin
        SegEnd := Stop;
        Right := PosOf(Stop).X;
        if Right < Left then                 // the match ends the line exactly
          Right := PosOf(Stop - 1).X + EmPx div 2;
      end;
      // The line's bottom is the top of the next one.
      if NextStart > C then
        Bottom := PosOf(NextStart).Y
      else
        Bottom := P.Y + Round(EmPx * 1.72);  // the last line of the document
      LineHeight := Bottom - P.Y;
      // Where the letters stand in the line (seen on Windows 11, 2026-11-16):
      //   text and epigraph (exact line height, 1.5 - 1.8 em): the BASELINE is
      //     almost on the line's bottom - all the extra height is above the
      //     letters and the descenders hang into the next line;
      //   titles (the font's own line height, about 1.3 of its size): the
      //     descenders are inside the line.
      // The box: from a little over the tall letters to under the descenders.
      if (LineHeight >= Round(EmPx * 1.4)) and (LineHeight <= Round(EmPx * 1.8)) then
      begin
        Font := EmPx;
        Baseline := Bottom - Round(Font * 0.08);
      end
      else
      begin
        Font := Round(LineHeight / 1.3);
        Baseline := Bottom - Round(Font * 0.3);
      end;
      if (Baseline + Font > Client.Top) and (Baseline - Font < Client.Bottom) then
        Fill(Rect(Left - PadX, Baseline - Round(Font * 0.8), Right + PadX, Baseline + Round(Font * 0.3)), Color);
      C := SegEnd;
    end;
  end;

var
  I, FirstChar, LastChar: Integer;
  Corner: TPointL;
begin
  if (Length(Starts) = 0) or (Length(Lens) <> Length(Starts)) or not Reader.HandleAllocated then
    Exit;
  Winapi.Windows.GetClientRect(Reader.Handle, Client);
  // Only the matches on screen: the characters at the corners of the view.
  Corner.x := 0;
  Corner.y := 0;
  FirstChar := Integer(SendMessage(Reader.Handle, EM_CHARFROMPOS, 0, LPARAM(@Corner)));
  Corner.x := Client.Right - 1;
  Corner.y := Client.Bottom - 1;
  LastChar := Integer(SendMessage(Reader.Handle, EM_CHARFROMPOS, 0, LPARAM(@Corner)));
  DC := GetDC(Reader.Handle);
  try
    for I := 0 to High(Starts) do
      if (Lens[I] > 0) and (Starts[I] + Lens[I] >= FirstChar) and (Starts[I] <= LastChar) then
        if I = Focus then
          PaintOne(Starts[I], Lens[I], ColorHitCurrent)
        else
          PaintOne(Starts[I], Lens[I], ColorHitOther);
  finally
    ReleaseDC(Reader.Handle, DC);
  end;
end;

procedure PaintParagraphMark(Reader: TRichEdit; StartChar, Len, EmPx: Integer);
var
  DC: HDC;
  Client, Bar: TRect;
  P: TPointL;
  FirstTop, LastTop, LastLine, LineHeight, Above: Integer;
  Brush: HBRUSH;

  function TopOf(CharPos: Integer): Integer;
  begin
    P.x := 0;
    P.y := 0;
    SendMessage(Reader.Handle, EM_POSFROMCHAR, WPARAM(@P), CharPos);
    Result := P.y;
  end;

begin
  if (Len <= 0) or not Reader.HandleAllocated then
    Exit;
  Winapi.Windows.GetClientRect(Reader.Handle, Client);
  // The text's lines are 1.72 em with the extra height above the letters (see
  // PaintMatchBoxes): the strip starts at the letters of the first line and
  // ends under the descenders of the last.
  LineHeight := Round(EmPx * 1.72);
  Above := LineHeight - Round(EmPx * 1.1);
  FirstTop := TopOf(StartChar);
  LastLine := Integer(SendMessage(Reader.Handle, EM_EXLINEFROMCHAR, 0, StartChar + Len - 1));
  LastTop := TopOf(Integer(SendMessage(Reader.Handle, EM_LINEINDEX, LastLine, 0)));
  Bar := Rect(Client.Left, FirstTop + Above, Client.Left + Max(EmPx div 7, 3),
    LastTop + LineHeight + Round(EmPx * 0.25));
  if (Bar.Bottom <= Client.Top) or (Bar.Top >= Client.Bottom) then
    Exit;
  DC := GetDC(Reader.Handle);
  try
    Brush := CreateSolidBrush(ColorToRGB(ColorGoToMark));
    FillRect(DC, Bar, Brush);
    DeleteObject(Brush);
  finally
    ReleaseDC(Reader.Handle, DC);
  end;
end;

end.
