program Slovo;

uses
  Vcl.Forms,
  Presentation.Views in 'Presentation.Views.pas' {MainForm},
  Infrastructure.SQLite3.Api in 'Infrastructure.SQLite3.Api.pas',
  Infrastructure.SQLite3.Database in 'Infrastructure.SQLite3.Database.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Slovo';
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
