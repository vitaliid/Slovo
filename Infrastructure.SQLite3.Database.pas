unit Infrastructure.SQLite3.Database;

{
  A thin object wrapper over Infrastructure.SQLite3.Api.

  Deliberately small: open a connection, prepare a statement, bind, step, read.
  No dataset, no component, no ORM - the search and repository layers sit on
  top of this and own their own SQL.

  Conventions:
    * every string crossing the boundary is converted to / from UTF-8 here and
      nowhere else;
    * every non-OK result code raises ESQLiteError carrying the SQLite message;
    * one connection belongs to one thread (connections are opened with
      SQLITE_OPEN_NOMUTEX). Interrupt is the single exception: it is designed
      to be called from another thread while Step is running.
}

interface

uses
  System.SysUtils,
  Infrastructure.SQLite3.Api;

type
  ESQLiteError = class(Exception)
  private
    FErrorCode: Integer;
    FExtendedCode: Integer;
    FSQL: string;
  public
    constructor Create(const AMessage: string; AErrorCode, AExtendedCode: Integer;
      const ASQL: string = '');
    { Primary result code, e.g. SQLITE_CONSTRAINT. }
    property ErrorCode: Integer read FErrorCode;
    { Extended result code, e.g. SQLITE_CONSTRAINT_UNIQUE. }
    property ExtendedCode: Integer read FExtendedCode;
    { The statement that failed, when the failure came from one. }
    property SQL: string read FSQL;
  end;

  { Raised specifically when a statement was cancelled through Interrupt, so the
    ViewModel can tell "user cancelled" from "query failed". }
  ESQLiteInterrupted = class(ESQLiteError);

  TSQLiteDatabase = class;

  TSQLiteStatement = class
  private
    FDatabase: TSQLiteDatabase;
    FHandle: PSQLite3Stmt;
    FSQL: string;
    function GetColumnCount: Integer;
  public
    constructor Create(ADatabase: TSQLiteDatabase; const ASQL: string);
    destructor Destroy; override;

    { Bind* return Self so that calls can be chained:
        Stmt.BindText(1, Term).BindInt64(2, BookId); }
    function BindText(AIndex: Integer; const AValue: string): TSQLiteStatement;
    function BindInt(AIndex: Integer; AValue: Integer): TSQLiteStatement;
    function BindInt64(AIndex: Integer; const AValue: Int64): TSQLiteStatement;
    function BindDouble(AIndex: Integer; const AValue: Double): TSQLiteStatement;
    function BindNull(AIndex: Integer): TSQLiteStatement;
    function ParameterIndex(const AName: string): Integer;

    { True while a row is available, False once the statement is done. }
    function Step: Boolean;
    { Runs a statement that returns no rows. }
    procedure Execute;
    procedure Reset;
    procedure ClearBindings;

    function IsNull(AColumn: Integer): Boolean;
    function ColumnText(AColumn: Integer): string;
    function ColumnInt(AColumn: Integer): Integer;
    function ColumnInt64(AColumn: Integer): Int64;
    function ColumnDouble(AColumn: Integer): Double;
    function ColumnName(AColumn: Integer): string;

    property ColumnCount: Integer read GetColumnCount;
    property Handle: PSQLite3Stmt read FHandle;
    property SQL: string read FSQL;
  end;

  TSQLiteOpenMode = (
    omReadOnly,   { fails if the file is missing - used for *.book content }
    omReadWrite,  { fails if the file is missing }
    omCreate      { creates the file when absent - used for the user's data }
  );

  TSQLiteDatabase = class
  private
    FHandle: PSQLite3;
    FFileName: string;
    FMode: TSQLiteOpenMode;
    function GetReadOnly: Boolean;
  public
    { Opens the database. ':memory:' is accepted with omCreate.
      LoadSQLite3 is called implicitly if the library is not loaded yet. }
    constructor Create(const AFileName: string; AMode: TSQLiteOpenMode = omReadOnly;
      ABusyTimeoutMs: Integer = 5000);
    destructor Destroy; override;

    procedure Execute(const ASQL: string);
    function Prepare(const ASQL: string): TSQLiteStatement;

    { Convenience readers for single-value queries (PRAGMA, COUNT(*), ...). }
    function QueryText(const ASQL: string; const ADefault: string = ''): string;
    function QueryInt64(const ASQL: string; const ADefault: Int64 = 0): Int64;

    { Cancels whatever statement is currently running on this connection.
      Safe to call from another thread; the running Step raises
      ESQLiteInterrupted. The connection must stay alive for the call. }
    procedure Interrupt;

    { Probes the loaded library for FTS5 by creating a temporary virtual table.
      More reliable than sqlite_compileoption_used(), which itself can be
      compiled out. }
    function SupportsFTS5: Boolean;

    { Raises ESQLiteError when AResultCode is not OK / ROW / DONE. }
    procedure Check(AResultCode: Integer; const ASQL: string = '');

    property Handle: PSQLite3 read FHandle;
    property FileName: string read FFileName;
    property Mode: TSQLiteOpenMode read FMode;
    property IsReadOnly: Boolean read GetReadOnly;
  end;

{ UTF-8 boundary helpers. The only place in the codebase that should touch
  PAnsiChar coming from SQLite. }
function SQLiteToUtf8(const AValue: string): UTF8String; inline;
function SQLiteFromUtf8(AValue: PAnsiChar): string; overload;
function SQLiteFromUtf8(AValue: PAnsiChar; AByteCount: Integer): string; overload;

{ Human-readable report: library path, version, threading mode, FTS5 support.
  Used by the diagnostics menu item and worth writing to the log at startup. }
function SQLiteSelfTest: string;

implementation

uses
  System.IOUtils,
  System.StrUtils;

resourcestring
  SSQLiteErrorFmt = 'SQLite: %s (code %d)';
  SSQLiteErrorWithSqlFmt = 'SQLite: %s (code %d)' + sLineBreak + 'SQL: %s';
  SSQLiteInterrupted = 'The operation was cancelled.';
  SSQLiteFileNotFound = 'Database file not found:' + sLineBreak + '%s';
  SSQLiteColumnRange = 'Column index %d is out of range (columns: %d).';

  SDiagLibrary    = 'Library:         %s';
  SDiagVersion    = 'Version:         %s';
  SDiagSourceId   = 'Source ID:       %s';
  SDiagThreadsafe = 'Threading mode:  %s';
  SDiagFts5       = 'FTS5:            %s';
  SDiagFts5Ok     = 'available';
  SDiagFts5Absent = 'MISSING - search will not work';
  SDiagUnicode61  = 'unicode61:       %s';
  SDiagOk         = 'works (verified with Cyrillic text)';
  SDiagFailed     = 'failed';
  SDiagFailure    = 'SQLite self-test failed:' + sLineBreak + '%s';

{ ---------------------------------------------------------------------------
  UTF-8 helpers
  --------------------------------------------------------------------------- }

function SQLiteToUtf8(const AValue: string): UTF8String; inline;
begin
  Result := UTF8String(AValue);
end;

function SQLiteFromUtf8(AValue: PAnsiChar; AByteCount: Integer): string;
var
  LUtf8: UTF8String;
begin
  if (AValue = nil) or (AByteCount <= 0) then
    Exit('');
  SetString(LUtf8, AValue, AByteCount);
  Result := string(LUtf8);
end;

function SQLiteFromUtf8(AValue: PAnsiChar): string;
var
  LLength: Integer;
begin
  if AValue = nil then
    Exit('');
  LLength := 0;
  while AValue[LLength] <> #0 do
    Inc(LLength);
  Result := SQLiteFromUtf8(AValue, LLength);
end;

{ ---------------------------------------------------------------------------
  ESQLiteError
  --------------------------------------------------------------------------- }

constructor ESQLiteError.Create(const AMessage: string; AErrorCode,
  AExtendedCode: Integer; const ASQL: string);
begin
  if ASQL <> '' then
    inherited CreateFmt(SSQLiteErrorWithSqlFmt, [AMessage, AErrorCode, ASQL])
  else
    inherited CreateFmt(SSQLiteErrorFmt, [AMessage, AErrorCode]);
  FErrorCode := AErrorCode;
  FExtendedCode := AExtendedCode;
  FSQL := ASQL;
end;

{ ---------------------------------------------------------------------------
  TSQLiteDatabase
  --------------------------------------------------------------------------- }

constructor TSQLiteDatabase.Create(const AFileName: string;
  AMode: TSQLiteOpenMode; ABusyTimeoutMs: Integer);
const
  { NOMUTEX: one connection per thread, so SQLite's own per-connection mutex
    would only cost time. See the "one active search slot" rule. }
  CBaseFlags = SQLITE_OPEN_NOMUTEX;
var
  LFileName: UTF8String;
  LFlags: Integer;
  LResult: Integer;
begin
  inherited Create;
  FFileName := AFileName;
  FMode := AMode;

  if not SQLite3IsLoaded then
    LoadSQLite3;

  case AMode of
    omReadOnly:  LFlags := CBaseFlags or SQLITE_OPEN_READONLY;
    omReadWrite: LFlags := CBaseFlags or SQLITE_OPEN_READWRITE;
  else
    LFlags := CBaseFlags or SQLITE_OPEN_READWRITE or SQLITE_OPEN_CREATE;
  end;

  { sqlite3_open_v2 reports a missing file as SQLITE_CANTOPEN, which reads the
    same as a dozen other I/O problems. Check first and say what is wrong. }
  if (AMode <> omCreate) and not SameText(AFileName, ':memory:') and
     not TFile.Exists(AFileName) then
    raise ESQLiteError.Create(Format(SSQLiteFileNotFound, [AFileName]),
      SQLITE_CANTOPEN, SQLITE_CANTOPEN);

  LFileName := SQLiteToUtf8(AFileName);
  LResult := sqlite3_open_v2(PAnsiChar(LFileName), FHandle, LFlags, nil);
  if LResult <> SQLITE_OK then
  begin
    { open_v2 hands back a handle even on failure, precisely so that the error
      message can be read from it. It still has to be closed. }
    if FHandle <> nil then
    begin
      Check(LResult);
    end
    else
      raise ESQLiteError.Create(SQLiteFromUtf8(sqlite3_errstr(LResult)),
        LResult, LResult);
  end;

  sqlite3_extended_result_codes(FHandle, 1);
  if ABusyTimeoutMs > 0 then
    sqlite3_busy_timeout(FHandle, ABusyTimeoutMs);
end;

destructor TSQLiteDatabase.Destroy;
begin
  if FHandle <> nil then
  begin
    { close_v2 tolerates statements that are still alive - it defers the actual
      close until the last one is finalized. }
    sqlite3_close_v2(FHandle);
    FHandle := nil;
  end;
  inherited;
end;

procedure TSQLiteDatabase.Check(AResultCode: Integer; const ASQL: string);
var
  LMessage: string;
  LExtended: Integer;
begin
  if (AResultCode = SQLITE_OK) or (AResultCode = SQLITE_ROW) or
     (AResultCode = SQLITE_DONE) then
    Exit;

  if FHandle <> nil then
  begin
    LMessage := SQLiteFromUtf8(sqlite3_errmsg(FHandle));
    LExtended := sqlite3_extended_errcode(FHandle);
  end
  else
  begin
    LMessage := SQLiteFromUtf8(sqlite3_errstr(AResultCode));
    LExtended := AResultCode;
  end;

  { The low byte carries the primary code once extended codes are enabled. }
  if (AResultCode and $FF) = SQLITE_INTERRUPT then
    raise ESQLiteInterrupted.Create(SSQLiteInterrupted, SQLITE_INTERRUPT,
      LExtended, ASQL);

  raise ESQLiteError.Create(LMessage, AResultCode and $FF, LExtended, ASQL);
end;

procedure TSQLiteDatabase.Execute(const ASQL: string);
var
  LSQL: UTF8String;
begin
  LSQL := SQLiteToUtf8(ASQL);
  Check(sqlite3_exec(FHandle, PAnsiChar(LSQL), nil, nil, nil), ASQL);
end;

function TSQLiteDatabase.Prepare(const ASQL: string): TSQLiteStatement;
begin
  Result := TSQLiteStatement.Create(Self, ASQL);
end;

function TSQLiteDatabase.QueryText(const ASQL, ADefault: string): string;
var
  LStatement: TSQLiteStatement;
begin
  LStatement := Prepare(ASQL);
  try
    if LStatement.Step then
      Result := LStatement.ColumnText(0)
    else
      Result := ADefault;
  finally
    LStatement.Free;
  end;
end;

function TSQLiteDatabase.QueryInt64(const ASQL: string; const ADefault: Int64): Int64;
var
  LStatement: TSQLiteStatement;
begin
  LStatement := Prepare(ASQL);
  try
    if LStatement.Step then
      Result := LStatement.ColumnInt64(0)
    else
      Result := ADefault;
  finally
    LStatement.Free;
  end;
end;

procedure TSQLiteDatabase.Interrupt;
begin
  if FHandle <> nil then
    sqlite3_interrupt(FHandle);
end;

function TSQLiteDatabase.GetReadOnly: Boolean;
begin
  Result := sqlite3_db_readonly(FHandle, 'main') = 1;
end;

function TSQLiteDatabase.SupportsFTS5: Boolean;
var
  LProbe, LDrop: UTF8String;
begin
  LProbe := SQLiteToUtf8('CREATE VIRTUAL TABLE temp.slovo_fts5_probe USING fts5(x);');
  LDrop := SQLiteToUtf8('DROP TABLE temp.slovo_fts5_probe;');
  Result := sqlite3_exec(FHandle, PAnsiChar(LProbe), nil, nil, nil) = SQLITE_OK;
  if Result then
    sqlite3_exec(FHandle, PAnsiChar(LDrop), nil, nil, nil);
end;

{ ---------------------------------------------------------------------------
  TSQLiteStatement
  --------------------------------------------------------------------------- }

constructor TSQLiteStatement.Create(ADatabase: TSQLiteDatabase; const ASQL: string);
var
  LSQL: UTF8String;
begin
  inherited Create;
  FDatabase := ADatabase;
  FSQL := ASQL;
  LSQL := SQLiteToUtf8(ASQL);
  FDatabase.Check(sqlite3_prepare_v2(FDatabase.Handle, PAnsiChar(LSQL),
    Length(LSQL), FHandle, nil), ASQL);
end;

destructor TSQLiteStatement.Destroy;
begin
  if FHandle <> nil then
  begin
    { The result of finalize repeats the last step error; it is not a new
      failure and must not raise out of a destructor. }
    sqlite3_finalize(FHandle);
    FHandle := nil;
  end;
  inherited;
end;

function TSQLiteStatement.GetColumnCount: Integer;
begin
  Result := sqlite3_column_count(FHandle);
end;

function TSQLiteStatement.ParameterIndex(const AName: string): Integer;
var
  LName: UTF8String;
begin
  LName := SQLiteToUtf8(AName);
  Result := sqlite3_bind_parameter_index(FHandle, PAnsiChar(LName));
end;

function TSQLiteStatement.BindText(AIndex: Integer; const AValue: string): TSQLiteStatement;
var
  LValue: UTF8String;
begin
  LValue := SQLiteToUtf8(AValue);
  { SQLITE_TRANSIENT: SQLite copies the bytes, so LValue may die right here. }
  FDatabase.Check(sqlite3_bind_text(FHandle, AIndex, PAnsiChar(LValue),
    Length(LValue), SQLITE_TRANSIENT), FSQL);
  Result := Self;
end;

function TSQLiteStatement.BindInt(AIndex, AValue: Integer): TSQLiteStatement;
begin
  FDatabase.Check(sqlite3_bind_int(FHandle, AIndex, AValue), FSQL);
  Result := Self;
end;

function TSQLiteStatement.BindInt64(AIndex: Integer; const AValue: Int64): TSQLiteStatement;
begin
  FDatabase.Check(sqlite3_bind_int64(FHandle, AIndex, AValue), FSQL);
  Result := Self;
end;

function TSQLiteStatement.BindDouble(AIndex: Integer; const AValue: Double): TSQLiteStatement;
begin
  FDatabase.Check(sqlite3_bind_double(FHandle, AIndex, AValue), FSQL);
  Result := Self;
end;

function TSQLiteStatement.BindNull(AIndex: Integer): TSQLiteStatement;
begin
  FDatabase.Check(sqlite3_bind_null(FHandle, AIndex), FSQL);
  Result := Self;
end;

function TSQLiteStatement.Step: Boolean;
var
  LResult: Integer;
begin
  LResult := sqlite3_step(FHandle);
  case LResult of
    SQLITE_ROW: Result := True;
    SQLITE_DONE: Result := False;
  else
    FDatabase.Check(LResult, FSQL);
    Result := False;
  end;
end;

procedure TSQLiteStatement.Execute;
begin
  while Step do
    ;
end;

procedure TSQLiteStatement.Reset;
begin
  { reset returns the error of the previous step, which the caller has already
    seen; only a genuinely broken statement matters here. }
  sqlite3_reset(FHandle);
end;

procedure TSQLiteStatement.ClearBindings;
begin
  FDatabase.Check(sqlite3_clear_bindings(FHandle), FSQL);
end;

function TSQLiteStatement.IsNull(AColumn: Integer): Boolean;
begin
  Result := sqlite3_column_type(FHandle, AColumn) = SQLITE_NULL;
end;

function TSQLiteStatement.ColumnText(AColumn: Integer): string;
var
  LText: PAnsiChar;
  LByteCount: Integer;
begin
  { Order matters and Delphi does not define argument evaluation order, so the
    two calls are sequenced by hand: column_text first, to force the value to
    UTF-8, and only then column_bytes to measure it. }
  LText := sqlite3_column_text(FHandle, AColumn);
  LByteCount := sqlite3_column_bytes(FHandle, AColumn);
  Result := SQLiteFromUtf8(LText, LByteCount);
end;

function TSQLiteStatement.ColumnInt(AColumn: Integer): Integer;
begin
  Result := sqlite3_column_int(FHandle, AColumn);
end;

function TSQLiteStatement.ColumnInt64(AColumn: Integer): Int64;
begin
  Result := sqlite3_column_int64(FHandle, AColumn);
end;

function TSQLiteStatement.ColumnDouble(AColumn: Integer): Double;
begin
  Result := sqlite3_column_double(FHandle, AColumn);
end;

function TSQLiteStatement.ColumnName(AColumn: Integer): string;
begin
  Result := SQLiteFromUtf8(sqlite3_column_name(FHandle, AColumn));
end;

{ ---------------------------------------------------------------------------
  Self test
  --------------------------------------------------------------------------- }

function ThreadSafeModeName(AValue: Integer): string;
begin
  case AValue of
    0: Result := 'single-thread';
    1: Result := 'serialized (compiled THREADSAFE=1)';
    2: Result := 'multi-thread';
  else
    Result := IntToStr(AValue);
  end;
end;

function SQLiteSelfTest: string;
var
  LDatabase: TSQLiteDatabase;
  LStatement: TSQLiteStatement;
  LFts5: Boolean;
  LTokenizerOk: Boolean;
  LLines: TArray<string>;
begin
  try
    if not SQLite3IsLoaded then
      LoadSQLite3;

    LDatabase := TSQLiteDatabase.Create(':memory:', omCreate);
    try
      LFts5 := LDatabase.SupportsFTS5;
      LTokenizerOk := False;

      if LFts5 then
      try
        { Round-trips Cyrillic through the tokenizer the index will use: an
          upper-case query has to match lower-case content. Guarded on its own,
          so that a library missing this tokenizer option still produces the
          rest of the report instead of one blanket failure. }
        LDatabase.Execute('CREATE VIRTUAL TABLE temp.probe USING ' +
          'fts5(body, tokenize=''unicode61 remove_diacritics 2'');');
        LDatabase.Execute('INSERT INTO temp.probe(body) VALUES (''Бог є любов'');');
        { The MATCH operand must be the bare table name - "temp.probe MATCH"
          is rejected with "no such column". }
        LStatement := LDatabase.Prepare(
          'SELECT count(*) FROM temp.probe WHERE probe MATCH ''БОГ'';');
        try
          LTokenizerOk := LStatement.Step and (LStatement.ColumnInt64(0) = 1);
        finally
          LStatement.Free;
        end;
        LDatabase.Execute('DROP TABLE temp.probe;');
      except
        LTokenizerOk := False;
      end;

      LLines := [
        Format(SDiagLibrary, [SQLite3LibraryPath]),
        Format(SDiagVersion, [SQLiteFromUtf8(sqlite3_libversion)]),
        Format(SDiagSourceId, [SQLiteFromUtf8(sqlite3_sourceid)]),
        Format(SDiagThreadsafe, [ThreadSafeModeName(sqlite3_threadsafe)]),
        '',
        Format(SDiagFts5, [IfThen(LFts5, SDiagFts5Ok, SDiagFts5Absent)]),
        Format(SDiagUnicode61, [IfThen(LTokenizerOk, SDiagOk, SDiagFailed)])
      ];
      Result := string.Join(sLineBreak, LLines);
    finally
      LDatabase.Free;
    end;
  except
    on E: Exception do
      Result := Format(SDiagFailure, [E.Message]);
  end;
end;

end.
