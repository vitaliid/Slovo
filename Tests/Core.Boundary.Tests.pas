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

function StripComments(const Source: string): string;
begin
  Result := TRegEx.Replace(Source, '\{[^}]*\}', ' ');
  Result := TRegEx.Replace(Result, '\(\*.*?\*\)', ' ', [roSingleLine]);
  Result := TRegEx.Replace(Result, '//[^\r\n]*', ' ');
end;

procedure TCoreBoundaryTests.CoreUnits_UseNoForbiddenUnits;
var
  CoreDir, FileName, Source, UnitName, Lower, Violations: string;
  Clause: TMatch;
  Checked: Integer;
begin
  CoreDir := FindCoreDir;
  Assert.IsNotEmpty(CoreDir, 'Core folder not found above ' + ParamStr(0));

  Violations := '';
  Checked := 0;
  for FileName in TDirectory.GetFiles(CoreDir, '*.pas', TSearchOption.soAllDirectories) do
  begin
    Inc(Checked);
    Source := StripComments(TFile.ReadAllText(FileName));
    for Clause in TRegEx.Matches(Source, '\buses\b([^;]*);', [roIgnoreCase]) do
      for UnitName in Clause.Groups[1].Value.Split([',']) do
      begin
        Lower := UnitName.Trim.ToLower;
        // 'Foo in ''path''' -> 'foo'
        if Lower.Contains(' in ') then
          Lower := Lower.Substring(0, Lower.IndexOf(' in ')).Trim;
        for var Prefix in ForbiddenPrefixes do
          if Lower.StartsWith(Prefix) or Lower.Contains('sqlite') then
          begin
            Violations := Violations + sLineBreak + TPath.GetFileName(FileName) + ': ' + UnitName.Trim;
            Break;
          end;
      end;
  end;

  Assert.IsTrue(Checked > 0, 'No .pas files found in ' + CoreDir);
  Assert.IsEmpty(Violations, 'Core uses forbidden units:' + Violations);
end;

initialization
  TDUnitX.RegisterTestFixture(TCoreBoundaryTests);

end.
