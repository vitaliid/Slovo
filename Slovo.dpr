program Slovo;

{ Program entry (Slovo_03 A.2). Phase 0 - OpenLibrary - checks everything the
  program depends on before any window exists; phase 1 - BindMainForm - fills
  the standard Application.CreateForm form through IMainView (C-14, C-22). }

uses
  System.SysUtils,
  Vcl.Forms,
  Core.Domain in 'Core\Core.Domain.pas',
  Core.Catalog in 'Core\Core.Catalog.pas',
  Core.Contracts in 'Core\Core.Contracts.pas',
  Core.Events in 'Core\Core.Events.pas',
  Infrastructure.SQLite3.Api in 'Infrastructure\Infrastructure.SQLite3.Api.pas',
  Infrastructure.SQLite3.Database in 'Infrastructure\Infrastructure.SQLite3.Database.pas',
  Infra.SQLite.LibraryDatabase in 'Infrastructure\Infra.SQLite.LibraryDatabase.pas',
  Infra.SQLite.LibraryReader in 'Infrastructure\Infra.SQLite.LibraryReader.pas',
  Infra.Search.Fts5SearchIndex in 'Infrastructure\Infra.Search.Fts5SearchIndex.pas',
  Infra.Logging.FileLogger in 'Infrastructure\Infra.Logging.FileLogger.pas',
  Infra.Settings.IniSettings in 'Infrastructure\Infra.Settings.IniSettings.pas',
  Presentation.Localization in 'Presentation\Presentation.Localization.pas',
  Presentation.Theme in 'Presentation\Presentation.Theme.pas',
  Presentation.Fonts in 'Presentation\Presentation.Fonts.pas',
  Presentation.MainViewModel in 'Presentation\Presentation.MainViewModel.pas',
  Presentation.Views in 'Presentation\Presentation.Views.pas',
  Shell.MainForm in 'Vcl\Shell.MainForm.pas' {MainForm},
  App.CompositionRoot in 'App.CompositionRoot.pas';

{$R *.res}

var
  Root: TCompositionRoot;

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;

  Root := TCompositionRoot.Create;          // nothing fatal here (C-22)
  try
    try
      if Root.OpenLibrary then              // phase 0; False = the message was shown
      begin
        Application.Title := L('app.title');
        Application.CreateForm(TMainForm, MainForm);
        Root.BindMainForm(MainForm);        // phase 1: the window appears already filled
        Application.Run;
      end
      else
        ExitCode := 1;
    except
      on E: Exception do
      begin
        Root.ReportFatal(E);
        ExitCode := 1;
      end;
    end;
  finally
    // ORDER MATTERS. Application owns the form, which would otherwise die during
    // VCL finalization - AFTER the ViewModel it is subscribed to. So: unbind,
    // free the form explicitly, then the root. CreateForm may not have run.
    if Assigned(MainForm) then
      Root.UnbindMainForm(MainForm);
    FreeAndNil(MainForm);
    Root.Free;
  end;
end.
