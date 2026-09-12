program Slovo;

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  Presentation.Views in 'Presentation.Views.pas' {MainForm},
  Infrastructure.SQLite3.Api in 'Infrastructure.SQLite3.Api.pas',
  Infrastructure.SQLite3.Database in 'Infrastructure.SQLite3.Database.pas';

{$R *.res}

resourcestring
  SStartupFailureCaption = 'Slovo - startup failed';
  SStartupFailureHint = sLineBreak + sLineBreak +
    'Check that sqlite3.dll sits next to Slovo.exe.';

{ Loads SQLite before the main window is created. Without the library the
  application can neither open a book nor search, so failing here - loudly and
  in one readable sentence - beats letting the window appear and die on the
  first query. The lazy load inside TSQLiteDatabase.Create stays in place; it
  simply never has anything left to do. }
function TryLoadSQLite: Boolean;
begin
  Result := True;
  try
    LoadSQLite3;
  except
    on E: Exception do
    begin
      Result := False;
      Application.MessageBox(PChar(E.Message + SStartupFailureHint),
        PChar(SStartupFailureCaption), MB_OK or MB_ICONERROR);
    end;
  end;
end;

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Slovo';

  if TryLoadSQLite then
  begin
    Application.CreateForm(TMainForm, MainForm);
    Application.Run;
  end
  else
    ExitCode := 1;
end.
