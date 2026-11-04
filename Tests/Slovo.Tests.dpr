program Slovo.Tests;

{ DUnitX console runner for Slovo (Slovo_03, Part C).
  Lists Core units by path and nothing from Infrastructure\ or Presentation\:
  if Core ever uses one of those, this project stops compiling (A-01).

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
  Core.Domain.Tests in 'Core.Domain.Tests.pas',
  Core.Catalog.Tests in 'Core.Catalog.Tests.pas',
  Core.Boundary.Tests in 'Core.Boundary.Tests.pas';

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
