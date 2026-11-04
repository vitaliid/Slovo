unit Infra.SQLite.LibraryDatabase;

{ The one read-only connection to library.db for the whole session
  (Slovo_02 "Як застосунок відкриває базу"; C-02, C-21).

  Opened in phase 0 of startup (C-22). Open never raises: it answers with a
  TResultError that the composition root turns into a startup message
  (reNotFound -> noLibrary, reModuleCorrupted -> libraryCorrupted,
  reUnsupportedSchema -> unsupportedSchema). The technical detail goes to the log.

  TLibrary and TFts5SearchIndex work on Connection, one after another, on the
  UI thread; this class owns the handle. }

interface

uses
  System.SysUtils,
  Core.Domain,
  Core.Contracts,
  Infrastructure.SQLite3.Database;

const
  // Format version this build of the application understands (B-16).
  SupportedSchemaVersion = 1;

type
  TLibraryDatabase = class
  private
    FConnection: TSQLiteDatabase;
    FLogger: ILogger;
    FFileName: string;
  public
    constructor Create(const ALogger: ILogger);
    destructor Destroy; override;

    // SQLITE_OPEN_READONLY, path as UTF-8, pragmas, Meta.SchemaVersion check.
    // False -> Error says why; the connection is closed again.
    function Open(const AFileName: string; out Error: TResultError): Boolean;

    // R6 (B-31): one probe MATCH per *Stem_* table. False means a sqlite3.dll
    // without the snowball tokenizer ("no such tokenizer") -> startup.wrongSqlite.
    function CheckStemTokenizer: Boolean;

    property Connection: TSQLiteDatabase read FConnection;
    property FileName: string read FFileName;
  end;

// Maps an exception from the SQLite layer to a TResultError (R3-10, Slovo_03 A.5).
function SQLiteErrorToResult(E: Exception): TResultError;

implementation

uses
  System.IOUtils,
  Infrastructure.SQLite3.Api;

const
  // mmap covers the whole read-only file; pages are read on demand (Slovo_02).
  MmapSizeBytes = 512 * 1024 * 1024;
  // Negative = KiB. One connection, so a moderate cache is enough.
  CacheSizeKiB = 16 * 1024;

function SQLiteErrorToResult(E: Exception): TResultError;
begin
  if E is ESQLiteError then
    case ESQLiteError(E).ErrorCode of
      SQLITE_CORRUPT, SQLITE_NOTADB:
        Result := reModuleCorrupted;
      SQLITE_IOERR, SQLITE_CANTOPEN:
        Result := reIOFailure;
      SQLITE_ERROR:
        if E.Message.Contains('fts5:') then
          Result := reInvalidQuery
        else
          Result := reModuleCorrupted;
    else
      Result := reModuleCorrupted;
    end
  else
    Result := reUnexpected;
end;

{ TLibraryDatabase }

constructor TLibraryDatabase.Create(const ALogger: ILogger);
begin
  inherited Create;
  FLogger := ALogger;
end;

destructor TLibraryDatabase.Destroy;
begin
  FConnection.Free;
  inherited;
end;

function TLibraryDatabase.Open(const AFileName: string; out Error: TResultError): Boolean;
var
  Version: Int64;
begin
  FreeAndNil(FConnection);
  FFileName := AFileName;
  Error := reNone;

  if not TFile.Exists(AFileName) then
  begin
    FLogger.LogError('LibraryDatabase', 'Library not found: ' + AFileName);
    Error := reNotFound;
    Exit(False);
  end;

  try
    // Busy timeout 0: a read-only file with journal_mode=DELETE is never locked by us.
    FConnection := TSQLiteDatabase.Create(AFileName, omReadOnly, 0);
    FConnection.Execute(Format('PRAGMA mmap_size = %d;', [MmapSizeBytes]));
    FConnection.Execute(Format('PRAGMA cache_size = -%d;', [CacheSizeKiB]));

    // The first real read: a file that is not a database fails right here (NOTADB).
    Version := FConnection.QueryInt64('SELECT SchemaVersion FROM Meta LIMIT 1;', -1);
    if Version <> SupportedSchemaVersion then
    begin
      FLogger.LogError('LibraryDatabase', Format(
        'Unsupported SchemaVersion %d in %s (supported: %d)',
        [Version, AFileName, SupportedSchemaVersion]));
      if Version > SupportedSchemaVersion then
        Error := reUnsupportedSchema
      else
        Error := reModuleCorrupted;
      FreeAndNil(FConnection);
      Exit(False);
    end;
  except
    on E: Exception do
    begin
      FLogger.LogError('LibraryDatabase', Format('Cannot open %s: %s: %s',
        [AFileName, E.ClassName, E.Message]));
      Error := SQLiteErrorToResult(E);
      if Error = reUnexpected then
        Error := reModuleCorrupted;
      FreeAndNil(FConnection);
      Exit(False);
    end;
  end;

  Result := True;
end;

function TLibraryDatabase.CheckStemTokenizer: Boolean;
var
  Tables: TSQLiteStatement;
  Names: TArray<string>;
  Name: string;
begin
  Result := False;
  if FConnection = nil then
    Exit;
  try
    // Listing sqlite_master does not touch the tokenizer; the probe below does.
    Tables := FConnection.Prepare(
      'SELECT name FROM sqlite_master ' +
      'WHERE type = ''table'' AND name GLOB ''*Stem_*'' AND sql LIKE ''CREATE VIRTUAL TABLE%'' ' +
      'ORDER BY name;');
    try
      while Tables.Step do
        Names := Names + [Tables.ColumnText(0)];
    finally
      Tables.Free;
    end;

    for Name in Names do
      // Table names come from sqlite_master, never from the user.
      FConnection.QueryInt64(Format(
        'SELECT rowid FROM "%0:s" WHERE "%0:s" MATCH ''a'' LIMIT 1;', [Name]), 0);
    Result := True;
  except
    on E: Exception do
      FLogger.LogError('LibraryDatabase', 'Stemmed tables unusable (wrong sqlite3.dll?): ' +
        E.ClassName + ': ' + E.Message);
  end;
end;

end.
