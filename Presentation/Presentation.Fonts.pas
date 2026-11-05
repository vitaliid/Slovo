unit Presentation.Fonts;

{ The fonts ship with the program (E-04, D-09), loaded with
  AddFontResourceEx(FR_PRIVATE) - visible to this process only, nothing is
  written into the system:
    - the reading font fonts\EBGaramond-Regular/Italic/Bold.ttf - one family,
      so \b, \i and fsBold work as usual; missing -> Georgia;
    - the interface font fonts\IBMPlexSans-Regular/Medium/SemiBold.ttf (the
      mockup's, R4-17 revised 2026-11-06) - sets Presentation.Theme.UiFont*Name;
      missing -> Segoe UI.

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
  UiFontFiles: array[0..2] of string = (
    'IBMPlexSans-Regular.ttf', 'IBMPlexSans-Medium.ttf', 'IBMPlexSans-SemiBold.ttf');

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

  Missing := '';
  for FileName in UiFontFiles do
  begin
    Path := TPath.Combine(AFontsDir, FileName);
    if not TFile.Exists(Path) or (AddFontResourceExW(PWideChar(Path), FR_PRIVATE, nil) = 0) then
      Missing := Missing + ' ' + FileName;
  end;
  if Missing = '' then
  begin
    UiFontName := UiFontPlex;
    UiFontMediumName := UiFontPlex + ' Medm';
    UiFontSemiBoldName := UiFontPlex + ' SmBld';
  end
  else
    ALogger.LogError('Fonts', Format('Not loaded from %s:%s - interface uses %s',
      [AFontsDir, Missing, UiFontFallback]));
end;

function TPrivateFonts.ResolveTheme: TReaderTheme;
begin
  if FLoadedAll then
    Result := NewReaderTheme(TextFontName)
  else
    Result := NewReaderTheme(TextFontFallback);
end;

end.
