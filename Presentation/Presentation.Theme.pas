unit Presentation.Theme;

{ Design tokens of the mockup "Slovo - Читання v2" (Slovo_04 A.1, E-14).
  The ONE place for colours and sizes; sizes are 96-DPI pixels, scaled with
  ScaleValue by the form. TColor is $00BBGGRR. }

interface

uses
  System.UITypes;

type
  // What becomes known only at startup (E-04): the real text font after loading.
  TReaderTheme = record
    TextFont: string;           // 'EB Garamond' or the fallback 'Georgia'
    UiFont: string;             // UiFontName: 'IBM Plex Sans' or 'Segoe UI'
  end;

const
  TextFontName = 'EB Garamond';
  TextFontFallback = 'Georgia';
  UiFontPlex = 'IBM Plex Sans';
  UiFontFallback = 'Segoe UI';

  // Colours (A.1)
  ColorBackground  = TColor($00FCFCFC);   // #fcfcfc
  ColorText        = TColor($002F2F2F);   // #2f2f2f
  ColorHeading     = TColor($00242424);   // #242424
  ColorMuted       = TColor($00767676);   // #767676
  ColorMarker      = TColor($008A8A8A);   // #8a8a8a
  ColorAccent      = TColor($00A86E3C);   // #3c6ea8
  ColorAccentHover = TColor($00955F2F);   // #2f5f95
  ColorHitCurrent  = TColor($00E6D7CA);   // #CAD7E6
  ColorHitOther    = TColor($00F4EBE4);   // #E4EBF4
  ColorBannerBack  = TColor($00E5F4FF);   // #fff4e5
  ColorBannerText  = TColor($001E4B5C);   // #5c4b1e

  // Layout (A, in 96-DPI pixels)
  HeaderHeight     = 57;
  LeftPanelWidth   = 272;
  RightPanelWidth  = 320;
  TextColumnMax    = 724;
  // The text column of the mockup "Читання v2" (A.5): <main> has side padding
  // clamp(16px, 4vw, 56px); inside it the column is max-width 724px (border-box:
  // the left padding below is inside the 724, the text is 724 - padding), centred,
  // with left padding clamp(48px, 6vw, 64px) - the margin for page markers -
  // and 44px above the breadcrumbs, 44px between them and the title.
  TextColumnSideMin     = 16;
  TextColumnSideMax     = 56;
  TextColumnSidePercent = 4;   // of the window width
  TextColumnLeftMin     = 48;
  TextColumnLeftMax     = 64;
  TextColumnLeftPercent = 6;
  TextColumnTop         = 44;
  CrumbsBottom          = 44;
  BannerHeight     = 36;
  NarrowWidth      = 1180;     // below: one side panel at a time (A.5)
  VeryNarrowWidth  = 780;      // below: the left panel hides
  SilencePeekStrip = 28;       // «Тиша»: the mouse in this top strip brings the header back

  // Text size (E-11): px = 20.5 + 1.5 * Step, Step -4..+6
  BaseTextPx       = 20.5;
  ZoomStepPx       = 1.5;

var
  // The interface font, as the mockup: IBM Plex Sans ships in fonts\ (R4-17
  // revised by Vitalii, 2026-11-06). TPrivateFonts sets these at start; until
  // then, or when the files are missing - Segoe UI. GDI sees every weight as
  // its own family: 500 - 'IBM Plex Sans Medm', 600 - 'IBM Plex Sans SmBld'.
  UiFontName: string = UiFontFallback;
  UiFontMediumName: string = UiFontFallback;
  UiFontSemiBoldName: string = 'Segoe UI Semibold';

function NewReaderTheme(const TextFont: string): TReaderTheme;

implementation

function NewReaderTheme(const TextFont: string): TReaderTheme;
begin
  Result.TextFont := TextFont;
  Result.UiFont := UiFontName;
end;

end.
