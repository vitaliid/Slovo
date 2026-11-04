unit Slovo.TestSupport;

{ Shared helpers for the tests:
  - TTestLogger: an ILogger that remembers what it was told;
  - BuildTestLibrary: creates library.db from Tests\fixtures\schema.sql + data.sql
    with the same sqlite3.dll the application uses, then switches the file to
    journal_mode=DELETE and VACUUMs it, like the producer does (Slovo_02). }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Core.Contracts;

type
  TTestLogger = class(TInterfacedObject, ILogger)
  private
    FMessages: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure LogError(const Source, Msg: string);
    function Contains(const Fragment: string): Boolean;
    function Count: Integer;
  end;

// Tests\fixtures, found by walking up from the test EXE.
function FixturesDir: string;

// A fresh temporary folder; Suffix lets a test put e.g. Cyrillic into the path.
function NewTempDir(const Suffix: string = ''): string;

// Builds a test library at FileName (overwrites) and returns FileName.
function BuildTestLibrary(const FileName: string): string;

// Runs SQL against an existing library through a read-write connection.
procedure ExecOnLibrary(const FileName, SQL: string);

implementation

uses
  System.IOUtils,
  Infrastructure.SQLite3.Database;

{ TTestLogger }

constructor TTestLogger.Create;
begin
  inherited Create;
  FMessages := TList<string>.Create;
end;

destructor TTestLogger.Destroy;
begin
  FMessages.Free;
  inherited;
end;

procedure TTestLogger.LogError(const Source, Msg: string);
begin
  FMessages.Add('[' + Source + '] ' + Msg);
end;

function TTestLogger.Contains(const Fragment: string): Boolean;
var
  Msg: string;
begin
  for Msg in FMessages do
    if Msg.Contains(Fragment) then
      Exit(True);
  Result := False;
end;

function TTestLogger.Count: Integer;
begin
  Result := FMessages.Count;
end;

{ helpers }

function FixturesDir: string;
var
  Dir: string;
begin
  Dir := TPath.GetDirectoryName(ParamStr(0));
  while Dir <> '' do
  begin
    Result := TPath.Combine(Dir, 'fixtures');
    if TFile.Exists(TPath.Combine(Result, 'schema.sql')) then
      Exit;
    Result := TPath.Combine(TPath.Combine(Dir, 'Tests'), 'fixtures');
    if TFile.Exists(TPath.Combine(Result, 'schema.sql')) then
      Exit;
    if TPath.GetDirectoryName(Dir) = Dir then
      Break;
    Dir := TPath.GetDirectoryName(Dir);
  end;
  raise Exception.Create('Tests\fixtures\schema.sql not found above ' + ParamStr(0));
end;

function NewTempDir(const Suffix: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath,
    'Slovo.Tests-' + TGUID.NewGuid.ToString.Substring(1, 8));
  if Suffix <> '' then
    Result := TPath.Combine(Result, Suffix);
  TDirectory.CreateDirectory(Result);
end;

function BuildTestLibrary(const FileName: string): string;
var
  Db: TSQLiteDatabase;
begin
  if TFile.Exists(FileName) then
    TFile.Delete(FileName);
  Db := TSQLiteDatabase.Create(FileName, omCreate, 0);
  try
    Db.Execute(TFile.ReadAllText(TPath.Combine(FixturesDir, 'schema.sql'), TEncoding.UTF8));
    Db.Execute(TFile.ReadAllText(TPath.Combine(FixturesDir, 'data.sql'), TEncoding.UTF8));
    Db.Execute('PRAGMA journal_mode = DELETE;');
    Db.Execute('VACUUM;');
  finally
    Db.Free;
  end;
  Result := FileName;
end;

procedure ExecOnLibrary(const FileName, SQL: string);
var
  Db: TSQLiteDatabase;
begin
  Db := TSQLiteDatabase.Create(FileName, omReadWrite, 0);
  try
    Db.Execute(SQL);
  finally
    Db.Free;
  end;
end;

end.
