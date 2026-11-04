program Slovo.Tests;

{ DUnitX console runner for Slovo (Slovo_03, Part C).
  Presentation\ is not listed, so Core or Infrastructure using it stops this
  project from compiling. Core's own boundary (no Vcl, Winapi, SQLite,
  Infrastructure) is checked by Core.Boundary.Tests (A-01).

  Needs sqlite3.dll next to the EXE - the post-build event copies the custom
  build from tools\sqlite\out. Fixtures are read from Tests\fixtures.

  Run:  Slovo.Tests.exe --exitbehavior:Continue   (no "press Enter" at the end) }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.TestFramework,
  Core.Domain in '..\Core\Core.Domain.pas',
  Core.Catalog in '..\Core\Core.Catalog.pas',
  Core.Contracts in '..\Core\Core.Contracts.pas',
  Infrastructure.SQLite3.Api in '..\Infrastructure\Infrastructure.SQLite3.Api.pas',
  Infrastructure.SQLite3.Database in '..\Infrastructure\Infrastructure.SQLite3.Database.pas',
  Infra.SQLite.LibraryDatabase in '..\Infrastructure\Infra.SQLite.LibraryDatabase.pas',
  Infra.SQLite.LibraryReader in '..\Infrastructure\Infra.SQLite.LibraryReader.pas',
  Infra.Search.Fts5SearchIndex in '..\Infrastructure\Infra.Search.Fts5SearchIndex.pas',
  Infra.Logging.FileLogger in '..\Infrastructure\Infra.Logging.FileLogger.pas',
  Infra.Settings.IniSettings in '..\Infrastructure\Infra.Settings.IniSettings.pas',
  Slovo.TestSupport in 'Slovo.TestSupport.pas',
  Core.Domain.Tests in 'Core.Domain.Tests.pas',
  Core.Catalog.Tests in 'Core.Catalog.Tests.pas',
  Core.Boundary.Tests in 'Core.Boundary.Tests.pas',
  Infra.LibraryDatabase.Tests in 'Infra.LibraryDatabase.Tests.pas',
  Infra.LibraryReader.Tests in 'Infra.LibraryReader.Tests.pas',
  Infra.Fts5SearchIndex.Tests in 'Infra.Fts5SearchIndex.Tests.pas',
  Infra.LoggerAndSettings.Tests in 'Infra.LoggerAndSettings.Tests.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
begin
  try
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.FailsOnNoAsserts := True;
    Runner.AddLogger(TDUnitXConsoleLogger.Create(True));

    Results := Runner.Execute;
    if not Results.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Done. Press <Enter> to quit.');
      System.Readln;
    end;
  except
    on E: Exception do
    begin
      System.Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := EXIT_ERRORS;
    end;
  end;
end.
