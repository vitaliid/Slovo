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

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  Winapi.Windows,
  Winapi.Messages,
  Winapi.RichEdit,
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

end.
