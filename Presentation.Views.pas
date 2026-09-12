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
    procedure miExitClick(Sender: TObject);
    procedure miSQLiteDiagnosticsClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  MainForm: TMainForm;

implementation

uses
  System.UITypes,
  Vcl.Dialogs,
  Infrastructure.SQLite3.Database;

{$R *.dfm}

resourcestring
  SSQLiteDiagnosticsCaption = 'SQLite diagnostics';

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
