unit Presentation.Strings;

{
  Every piece of user-facing interface text lives here.

  The forms themselves stay neutral: the captions in the .dfm files are English
  placeholders that exist only so the form designer stays readable, and they are
  overwritten at run time from the resourcestrings below. Translating the
  interface therefore means translating one unit - or shipping a resource DLL
  built from it - and never editing a form.

  Technical text does NOT belong here. Error messages, diagnostics and exception
  text are English and live next to the code that produces them
  (Infrastructure.SQLite3.Api, Infrastructure.SQLite3.Database, Slovo.dpr).
}

interface

resourcestring
  { Main menu }
  SMenuFile = '&Файл';
  SMenuFileExit = '&Вихід';
  SMenuHelp = '&Довідка';
  SMenuHelpSQLiteDiagnostics = 'Д&іагностика SQLite...';

  { Dialog captions }
  SSQLiteDiagnosticsCaption = 'Діагностика SQLite';

implementation

end.
