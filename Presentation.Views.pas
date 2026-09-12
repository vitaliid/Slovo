unit Presentation.Views;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.Menus;

type
  TMainForm = class(TForm)
    mmMain: TMainMenu;
    miFile: TMenuItem;
    miExit: TMenuItem;
    miHelp: TMenuItem;
    miSQLiteDiagnostics: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure miExitClick(Sender: TObject);
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
  benefit only; the real interface text comes from Presentation.Strings. Every
  control that shows text to the user must be listed here - a control missing
  from this method keeps its placeholder and ships untranslated. }
procedure TMainForm.ApplyStrings;
begin
  miFile.Caption := SMenuFile;
  miExit.Caption := SMenuFileExit;
  miHelp.Caption := SMenuHelp;
  miSQLiteDiagnostics.Caption := SMenuHelpSQLiteDiagnostics;
end;

procedure TMainForm.miExitClick(Sender: TObject);
begin
  Close;
end;

{ Loads sqlite3.dll if it is not loaded yet and reports what the binding sees:
  library path, version, threading mode, FTS5 and the unicode61 tokenizer.
  This is the quickest way to tell a deployment problem (missing or wrong DLL)
  from a query problem. }
procedure TMainForm.miSQLiteDiagnosticsClick(Sender: TObject);
begin
  TaskMessageDlg(SSQLiteDiagnosticsCaption, SQLiteSelfTest, mtInformation, [mbOK], 0);
end;

end.
