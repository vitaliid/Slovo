unit Presentation.Views;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.Menus;

type
  TMainForm = class(TForm)
    mmMain: TMainMenu;
    miFile: TMenuItem;
    miExit: TMenuItem;
    miView: TMenuItem;
    miLanguage: TMenuItem;
    miLanguageUkrainian: TMenuItem;
    miLanguageRussian: TMenuItem;
    miLanguageEnglish: TMenuItem;
    miHelp: TMenuItem;
    miSQLiteDiagnostics: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure miExitClick(Sender: TObject);
    procedure miLanguageItemClick(Sender: TObject);
    procedure miSQLiteDiagnosticsClick(Sender: TObject);
  private
    procedure ApplyStrings;
  public
    { Public declarations }
  end;

var
  MainForm: TMainForm;

implementation

uses
  System.UITypes,
  Vcl.Dialogs,
  Presentation.Strings,
  Infrastructure.SQLite3.Database;

{$R *.dfm}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  ApplyStrings;
end;

{ The captions stored in the .dfm are English placeholders for the designer's
  benefit only; the real interface text comes from the current lang\*.lang file
  through UI(). Called once at startup and again on every language change, so it
  must be safe to run repeatedly. Every control that shows text to the user must
  be listed here - a control missing from this method keeps its placeholder and
  ships untranslated. A key missing from the file shows as the key itself and is
  logged once, so the gap is visible rather than silent. }
procedure TMainForm.ApplyStrings;
begin
  miFile.Caption := UI('menu.file');
  miExit.Caption := UI('menu.file.exit');
  miView.Caption := UI('menu.view');
  miLanguage.Caption := UI('menu.view.language');
  miHelp.Caption := UI('menu.help');
  miSQLiteDiagnostics.Caption := UI('menu.help.sqliteDiagnostics');

  { Language names are endonyms and stay the same whatever the interface
    language is, so they do not come from the translation files. }
  miLanguageUkrainian.Caption := LanguageName(UILanguageCodes[0]);
  miLanguageRussian.Caption := LanguageName(UILanguageCodes[1]);
  miLanguageEnglish.Caption := LanguageName(UILanguageCodes[2]);

  miLanguageUkrainian.Checked := CurrentLanguage = UILanguageCodes[0];
  miLanguageRussian.Checked := CurrentLanguage = UILanguageCodes[1];
  miLanguageEnglish.Checked := CurrentLanguage = UILanguageCodes[2];
end;

procedure TMainForm.miExitClick(Sender: TObject);
begin
  Close;
end;

{ Shared by the three language items; each carries the index of its language
  code in Tag. Switching re-reads that language's file, so a correction made in
  lang\*.lang shows up by switching away and back - no rebuild. }
procedure TMainForm.miLanguageItemClick(Sender: TObject);
var
  LTag: Integer;
begin
  LTag := (Sender as TMenuItem).Tag;
  if (LTag < Low(UILanguageCodes)) or (LTag > High(UILanguageCodes)) then
    Exit;
  SetCurrentLanguage(UILanguageCodes[LTag]);
  ApplyStrings;
end;

{ Loads sqlite3.dll if it is not loaded yet and reports what the binding sees:
  library path, version, threading mode, FTS5 and the unicode61 tokenizer.
  This is the quickest way to tell a deployment problem (missing or wrong DLL)
  from a query problem. The report itself is technical and stays English. }
procedure TMainForm.miSQLiteDiagnosticsClick(Sender: TObject);
begin
  TaskMessageDlg(UI('dialog.sqliteDiagnostics.title'), SQLiteSelfTest,
    mtInformation, [mbOK], 0);
end;

end.
