program Slovo;

uses
  Vcl.Forms,
  Presentation.Views in 'Presentation.Views.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Slovo';
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
