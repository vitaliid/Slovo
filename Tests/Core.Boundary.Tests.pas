unit Core.Boundary.Tests;

{ Hexagonal boundary (A-01, Slovo_03 Part C): no unit in Core\ may use the VCL,
  Windows API, SQLite, Infrastructure or Presentation.

  The test project compiles Infrastructure too, and Vcl.*/Winapi.* are always on
  the library path, so the compiler cannot catch this - the test reads the uses
  clauses of Core\*.pas instead. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCoreBoundaryTests = class
  public
    [Test] procedure CoreUnits_UseNoForbiddenUnits;
    [Test] procedure ViewModel_UsesNoVclOrInfrastructure;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.RegularExpressions;

const
  ForbiddenPrefixes: array[0..8] of string = (
    'vcl.', 'winapi.', 'fmx.', 'data.', 'firedac.',
    'infrastructure.', 'infra.', 'presentation.', 'app.');

// The test EXE lives in Tests\<Platform>\<Config>; walk up until a Core folder appears.
function FindCoreDir: string;
var
  Dir: string;
begin
  Dir := TPath.GetDirectoryName(ParamStr(0));
  while Dir <> '' do
  begin
    if TDirectory.Exists(TPath.Combine(Dir, 'Core')) then
      Exit(TPath.Combine(Dir, 'Core'));
    if TPath.GetDirectoryName(Dir) = Dir then
      Break;
    Dir := TPath.GetDirectoryName(Dir);
  end;
  Result := '';
end;

// Folder of the repository (the one that holds Core\).
function RepoDir: string;
begin
  Result := FindCoreDir;
  if Result <> '' then
    Result := TPath.GetDirectoryName(Result);
end;

function StripComments(const Source: string): string;
begin
  Result := TRegEx.Replace(Source, '\{[^}]*\}', ' ');
  Result := TRegEx.Replace(Result, '\(\*.*?\*\)', ' ', [roSingleLine]);
  Result := TRegEx.Replace(Result, '//[^\r\n]*', ' ');
end;

// Uses-clause entries of the given files that start with a forbidden prefix.
function FindViolations(const Files: TArray<string>; const Forbidden: array of string): string;
var
  FileName, Source, UnitName, Lower: string;
  Clause: TMatch;
  I: Integer;
begin
  Result := '';
  for FileName in Files do
  begin
    Source := StripComments(TFile.ReadAllText(FileName));
    for Clause in TRegEx.Matches(Source, '\buses\b([^;]*);', [roIgnoreCase]) do
      for UnitName in Clause.Groups[1].Value.Split([',']) do
      begin
        Lower := UnitName.Trim.ToLower;
        // 'Foo in ''path''' -> 'foo'
        if Lower.Contains(' in ') then
          Lower := Lower.Substring(0, Lower.IndexOf(' in ')).Trim;
        for I := Low(Forbidden) to High(Forbidden) do
          if Lower.StartsWith(Forbidden[I]) or Lower.Contains('sqlite') then
          begin
            Result := Result + sLineBreak + TPath.GetFileName(FileName) + ': ' + UnitName.Trim;
            Break;
          end;
      end;
  end;
end;

procedure TCoreBoundaryTests.CoreUnits_UseNoForbiddenUnits;
var
  CoreDir, Violations: string;
  Files: TArray<string>;
begin
  CoreDir := FindCoreDir;
  Assert.IsNotEmpty(CoreDir, 'Core folder not found above ' + ParamStr(0));
  Files := TDirectory.GetFiles(CoreDir, '*.pas', TSearchOption.soAllDirectories);
  Assert.IsTrue(Length(Files) > 0, 'No .pas files found in ' + CoreDir);
  Violations := FindViolations(Files, ForbiddenPrefixes);
  Assert.IsEmpty(Violations, 'Core uses forbidden units:' + Violations);
end;

// Slovo_04 C.1: the ViewModel compiles without Vcl.* and knows only Core.
procedure TCoreBoundaryTests.ViewModel_UsesNoVclOrInfrastructure;
var
  FileName, Violations: string;
begin
  FileName := TPath.Combine(TPath.Combine(RepoDir, 'Presentation'), 'Presentation.MainViewModel.pas');
  Assert.IsTrue(TFile.Exists(FileName), FileName);
  Violations := FindViolations([FileName],
    ['vcl.', 'winapi.', 'fmx.', 'data.', 'firedac.', 'infrastructure.', 'infra.', 'app.']);
  Assert.IsEmpty(Violations, 'ViewModel uses forbidden units:' + Violations);
end;

initialization
  TDUnitX.RegisterTestFixture(TCoreBoundaryTests);

end.
