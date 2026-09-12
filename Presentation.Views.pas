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
  benefit only; the real interface text comes from Presentation.Strings. Called
  once at startup and again on every language change, so it must be safe to run
  repeatedly. Every control that shows text to the user must be listed here - a
  control missing from this method keeps its placeholder and ships
  untranslated. }
procedure TMainForm.ApplyStrings;
begin
  miFile.Caption := UI(uiMenuFile);
  miExit.Caption := UI(uiMenuFileExit);
  miView.Caption := UI(uiMenuView);
  miLanguage.Caption := UI(uiMenuViewLanguage);
  miHelp.Caption := UI(uiMenuHelp);
  miSQLiteDiagnostics.Caption := UI(uiMenuHelpSQLiteDiagnostics);

  { Language names are endonyms and stay the same whatever the interface
    language is, so they do not come from the string table. }
  miLanguageUkrainian.Caption := LanguageName(ulUkrainian);
  miLanguageRussian.Caption := LanguageName(ulRussian);
  miLanguageEnglish.Caption := LanguageName(ulEnglish);

  miLanguageUkrainian.Checked := CurrentLanguage = ulUkrainian;
  miLanguageRussian.Checked := CurrentLanguage = ulRussian;
  miLanguageEnglish.Checked := CurrentLanguage = ulEnglish;
end;

procedure TMainForm.miExitClick(Sender: TObject);
begin
  Close;
end;

{ Shared by the three language items; each carries its TUILanguage in Tag. }
procedure TMainForm.miLanguageItemClick(Sender: TObject);
var
  LTag: Integer;
begin
  LTag := (Sender as TMenuItem).Tag;
  if (LTag < Ord(Low(TUILanguage))) or (LTag > Ord(High(TUILanguage))) then
    Exit;
  SetCurrentLanguage(TUILanguage(LTag));
  ApplyStrings;
end;

{ Loads sqlite3.dll if it is not loaded yet and reports what the binding sees:
  library path, version, threading mode, FTS5 and the unicode61 tokenizer.
  This is the quickest way to tell a deployment problem (missing or wrong DLL)
  from a query problem. The report itself is technical and stays English. }
procedure TMainForm.miSQLiteDiagnosticsClick(Sender: TObject);
begin
  TaskMessageDlg(UI(uiSQLiteDiagnosticsCaption), SQLiteSelfTest,
    mtInformation, [mbOK], 0);
end;

end.
