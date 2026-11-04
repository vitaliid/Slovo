unit Presentation.Fonts;

{ The reading font ships with the program (E-04, D-09): fonts\EBGaramond-
  Regular/Italic/Bold.ttf, loaded with AddFontResourceEx(FR_PRIVATE) - visible
  to this process only, nothing is written into the system. One family, so
  \b, \i and fsBold work as usual.

  RemoveFontResourceEx is deliberately NOT called: Windows drops private fonts
  when the process ends, and this way there is no rule about destroying the
  form first (💡-13). A missing or broken file -> Georgia, a line in the log,
  no banner. }

interface

uses
  Core.Contracts,
  Presentation.Theme;

type
  TPrivateFonts = class
  private
    FLoadedAll: Boolean;
  public
    constructor Create(const AFontsDir: string; const ALogger: ILogger);
    function ResolveTheme: TReaderTheme;
    property LoadedAll: Boolean read FLoadedAll;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows;

const
  FR_PRIVATE = $10;
  FontFiles: array[0..2] of string = (
    'EBGaramond-Regular.ttf', 'EBGaramond-Italic.ttf', 'EBGaramond-Bold.ttf');

function AddFontResourceExW(Name: PWideChar; Flags: DWORD; Reserved: Pointer): Integer; stdcall;
  external gdi32 name 'AddFontResourceExW';

constructor TPrivateFonts.Create(const AFontsDir: string; const ALogger: ILogger);
var
  FileName, Path: string;
  Missing: string;
begin
  inherited Create;
  Missing := '';
  for FileName in FontFiles do
  begin
    Path := TPath.Combine(AFontsDir, FileName);
    if not TFile.Exists(Path) or (AddFontResourceExW(PWideChar(Path), FR_PRIVATE, nil) = 0) then
      Missing := Missing + ' ' + FileName;
  end;
  FLoadedAll := Missing = '';
  if not FLoadedAll then
    ALogger.LogError('Fonts', Format('Not loaded from %s:%s - text uses %s',
      [AFontsDir, Missing, TextFontFallback]));
end;

function TPrivateFonts.ResolveTheme: TReaderTheme;
begin
  if FLoadedAll then
    Result := NewReaderTheme(TextFontName)
  else
    Result := NewReaderTheme(TextFontFallback);
end;

end.
