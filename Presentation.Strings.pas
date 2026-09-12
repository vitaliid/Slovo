unit Presentation.Strings;

{
  Every piece of user-facing interface text, in every language the interface
  offers. Ukrainian is the default; Russian and English can be chosen from
  View -> Language while the program is running.

  The forms themselves stay neutral: the captions in the .dfm files are English
  placeholders that exist only so the form designer stays readable, and they are
  overwritten from this unit whenever the language changes. Adding a caption to
  a form therefore means adding a row to UITexts below and a line to
  TMainForm.ApplyStrings - never a translated literal in a .dfm.

  Technical text does NOT belong here. Error messages, diagnostics and exception
  text are English, are not translated, and live as resourcestrings next to the
  code that produces them (Infrastructure.SQLite3.Api,
  Infrastructure.SQLite3.Database, Slovo.dpr).
}

interface

type
  { The order of this type is the column order of UITexts. }
  TUILanguage = (ulUkrainian, ulRussian, ulEnglish);

  TUIString = (
    uiMenuFile,
    uiMenuFileExit,
    uiMenuView,
    uiMenuViewLanguage,
    uiMenuHelp,
    uiMenuHelpSQLiteDiagnostics,
    uiSQLiteDiagnosticsCaption
  );

const
  DefaultUILanguage = ulUkrainian;

function CurrentLanguage: TUILanguage;
procedure SetCurrentLanguage(AValue: TUILanguage);

{ The interface text for AString in the language currently selected. }
function UI(AString: TUIString): string;

{ The name of a language in that language - never translated. }
function LanguageName(ALanguage: TUILanguage): string;

implementation

const
  { One row per string, one column per language, in the order of TUILanguage.
    Adding a language means adding a value to TUILanguage and a column to every
    row here; the compiler then refuses to build until all rows are complete,
    which is exactly the point - a forgotten translation cannot ship silently. }
  UITexts: array[TUIString, TUILanguage] of string = (
    { uiMenuFile                  } ('&Файл',
                                     '&Файл',
                                     '&File'),
    { uiMenuFileExit              } ('&Вихід',
                                     '&Выход',
                                     'E&xit'),
    { uiMenuView                  } ('&Вигляд',
                                     '&Вид',
                                     '&View'),
    { uiMenuViewLanguage          } ('&Мова',
                                     '&Язык',
                                     '&Language'),
    { uiMenuHelp                  } ('&Довідка',
                                     '&Справка',
                                     '&Help'),
    { uiMenuHelpSQLiteDiagnostics } ('Д&іагностика SQLite...',
                                     'Д&иагностика SQLite...',
                                     'SQLite &diagnostics...'),
    { uiSQLiteDiagnosticsCaption  } ('Діагностика SQLite',
                                     'Диагностика SQLite',
                                     'SQLite diagnostics')
  );

  LanguageNames: array[TUILanguage] of string = (
    'Українська',
    'Русский',
    'English'
  );

var
  GCurrentLanguage: TUILanguage = DefaultUILanguage;

function CurrentLanguage: TUILanguage;
begin
  Result := GCurrentLanguage;
end;

procedure SetCurrentLanguage(AValue: TUILanguage);
begin
  GCurrentLanguage := AValue;
end;

function UI(AString: TUIString): string;
begin
  Result := UITexts[AString, GCurrentLanguage];
end;

function LanguageName(ALanguage: TUILanguage): string;
begin
  Result := LanguageNames[ALanguage];
end;

end.
