unit Infrastructure.SQLite3.Api;

{
  Raw 1:1 bindings to the SQLite3 C API.

  The library is bound at run time (LoadLibraryEx with a full, explicit path)
  instead of being statically imported, because:

    * a missing DLL, or one of the wrong bitness, produces a readable message
      instead of a Windows loader failure that kills the process before any of
      our code runs;
    * the DLL is never searched for in the current directory or along PATH,
      which closes the classic DLL pre-loading / hijacking hole;
    * the exact library version in use can be asserted and logged.

  FireDAC is deliberately not used: the search layer needs sqlite3_interrupt()
  to cancel a running query from another thread, and direct access to the FTS5
  auxiliary functions (bm25, snippet, highlight).

  This unit performs no error handling and no string conversion - it is the bare
  C surface. Use Infrastructure.SQLite3.Database for everyday work.
}

interface

uses
  Winapi.Windows,
  System.SysUtils;

type
  { Opaque handles. Declared as distinct types so that a sqlite3* cannot be
    passed where a sqlite3_stmt* is expected. }
  PSQLite3 = type Pointer;
  PSQLite3Stmt = type Pointer;
  PPAnsiCharArray = ^PAnsiChar;

  { Callback used by sqlite3_exec. Returning non-zero aborts the run. }
  TSQLiteExecCallback = function(UserData: Pointer; ColumnCount: Integer;
    ColumnValues: PPAnsiCharArray; ColumnNames: PPAnsiCharArray): Integer; cdecl;

const
  { ---- Primary result codes ---- }
  SQLITE_OK         = 0;
  SQLITE_ERROR      = 1;
  SQLITE_INTERNAL   = 2;
  SQLITE_PERM       = 3;
  SQLITE_ABORT      = 4;
  SQLITE_BUSY       = 5;
  SQLITE_LOCKED     = 6;
  SQLITE_NOMEM      = 7;
  SQLITE_READONLY   = 8;
  SQLITE_INTERRUPT  = 9;
  SQLITE_IOERR      = 10;
  SQLITE_CORRUPT    = 11;
  SQLITE_NOTFOUND   = 12;
  SQLITE_FULL       = 13;
  SQLITE_CANTOPEN   = 14;
  SQLITE_PROTOCOL   = 15;
  SQLITE_EMPTY      = 16;
  SQLITE_SCHEMA     = 17;
  SQLITE_TOOBIG     = 18;
  SQLITE_CONSTRAINT = 19;
  SQLITE_MISMATCH   = 20;
  SQLITE_MISUSE     = 21;
  SQLITE_NOLFS      = 22;
  SQLITE_AUTH       = 23;
  SQLITE_FORMAT     = 24;
  SQLITE_RANGE      = 25;
  SQLITE_NOTADB     = 26;
  SQLITE_NOTICE     = 27;
  SQLITE_WARNING    = 28;
  SQLITE_ROW        = 100;
  SQLITE_DONE       = 101;

  { ---- sqlite3_open_v2 flags ---- }
  SQLITE_OPEN_READONLY     = $00000001;
  SQLITE_OPEN_READWRITE    = $00000002;
  SQLITE_OPEN_CREATE       = $00000004;
  SQLITE_OPEN_URI          = $00000040;
  SQLITE_OPEN_MEMORY       = $00000080;
  SQLITE_OPEN_NOMUTEX      = $00008000;
  SQLITE_OPEN_FULLMUTEX    = $00010000;
  SQLITE_OPEN_SHAREDCACHE  = $00020000;
  SQLITE_OPEN_PRIVATECACHE = $00040000;
  SQLITE_OPEN_NOFOLLOW     = $01000000;
  SQLITE_OPEN_EXRESCODE    = $02000000;

  { ---- Column data types ---- }
  SQLITE_INTEGER = 1;
  SQLITE_FLOAT   = 2;
  SQLITE_TEXT    = 3;
  SQLITE_BLOB    = 4;
  SQLITE_NULL    = 5;

  { ---- Text encodings ---- }
  SQLITE_UTF8 = 1;

  { ---- sqlite3_config verbs (the ones we may ever need) ---- }
  SQLITE_CONFIG_SINGLETHREAD = 1;
  SQLITE_CONFIG_MULTITHREAD  = 2;
  SQLITE_CONFIG_SERIALIZED   = 3;

  { The earliest release we are willing to run against.
    FTS5 arrived in 3.9.0, UPSERT (which the annotation store will want) in
    3.24.0, and "remove_diacritics 2" - the unicode61 setting the index uses -
    in 3.27.0. Anything older is rejected at load time with a clear message. }
  SQLITE_MIN_VERSION_NUMBER = 3027000;

  SQLITE3_LIBRARY_NAME = 'sqlite3.dll';

{ Destructor sentinels for the bind_* family.
  Declared as functions rather than typed constants so that no assumption is
  made about how the compiler folds Pointer(-1) in a constant expression. }
function SQLITE_STATIC: Pointer; inline;
function SQLITE_TRANSIENT: Pointer; inline;

var
  { ---- Library information ---- }
  sqlite3_libversion: function: PAnsiChar; cdecl;
  sqlite3_libversion_number: function: Integer; cdecl;
  sqlite3_sourceid: function: PAnsiChar; cdecl;
  sqlite3_threadsafe: function: Integer; cdecl;

  { ---- Global lifecycle ---- }
  sqlite3_initialize: function: Integer; cdecl;
  sqlite3_shutdown: function: Integer; cdecl;
  { Only the zero-extra-argument verbs (SQLITE_CONFIG_MULTITHREAD and friends).
    sqlite3_config is variadic; cdecl lets us call it with fewer arguments. }
  sqlite3_config: function(Op: Integer): Integer; cdecl;

  { ---- Connections ---- }
  sqlite3_open_v2: function(FileName: PAnsiChar; out DB: PSQLite3;
    Flags: Integer; VfsName: PAnsiChar): Integer; cdecl;
  sqlite3_close_v2: function(DB: PSQLite3): Integer; cdecl;
  sqlite3_busy_timeout: function(DB: PSQLite3; MilliSeconds: Integer): Integer; cdecl;
  sqlite3_extended_result_codes: function(DB: PSQLite3; OnOff: Integer): Integer; cdecl;
  sqlite3_db_readonly: function(DB: PSQLite3; SchemaName: PAnsiChar): Integer; cdecl;

  { ---- Errors ---- }
  sqlite3_errcode: function(DB: PSQLite3): Integer; cdecl;
  sqlite3_extended_errcode: function(DB: PSQLite3): Integer; cdecl;
  sqlite3_errmsg: function(DB: PSQLite3): PAnsiChar; cdecl;
  sqlite3_errstr: function(ResultCode: Integer): PAnsiChar; cdecl;
  sqlite3_free: procedure(P: Pointer); cdecl;

  { ---- One-shot execution ---- }
  sqlite3_exec: function(DB: PSQLite3; SQL: PAnsiChar;
    Callback: TSQLiteExecCallback; UserData: Pointer;
    ErrMsg: PPAnsiCharArray): Integer; cdecl;

  { ---- Prepared statements ---- }
  sqlite3_prepare_v2: function(DB: PSQLite3; SQL: PAnsiChar; ByteCount: Integer;
    out Stmt: PSQLite3Stmt; Tail: PPAnsiCharArray): Integer; cdecl;
  sqlite3_step: function(Stmt: PSQLite3Stmt): Integer; cdecl;
  sqlite3_reset: function(Stmt: PSQLite3Stmt): Integer; cdecl;
  sqlite3_finalize: function(Stmt: PSQLite3Stmt): Integer; cdecl;
  sqlite3_clear_bindings: function(Stmt: PSQLite3Stmt): Integer; cdecl;
  sqlite3_stmt_readonly: function(Stmt: PSQLite3Stmt): Integer; cdecl;
  sqlite3_db_handle: function(Stmt: PSQLite3Stmt): PSQLite3; cdecl;

  { ---- Binding ---- }
  sqlite3_bind_parameter_index: function(Stmt: PSQLite3Stmt; Name: PAnsiChar): Integer; cdecl;
  sqlite3_bind_null: function(Stmt: PSQLite3Stmt; Index: Integer): Integer; cdecl;
  sqlite3_bind_int: function(Stmt: PSQLite3Stmt; Index: Integer; Value: Integer): Integer; cdecl;
  sqlite3_bind_int64: function(Stmt: PSQLite3Stmt; Index: Integer; Value: Int64): Integer; cdecl;
  sqlite3_bind_double: function(Stmt: PSQLite3Stmt; Index: Integer; Value: Double): Integer; cdecl;
  sqlite3_bind_text: function(Stmt: PSQLite3Stmt; Index: Integer; Value: PAnsiChar;
    ByteCount: Integer; Destructor_: Pointer): Integer; cdecl;
  sqlite3_bind_blob: function(Stmt: PSQLite3Stmt; Index: Integer; Value: Pointer;
    ByteCount: Integer; Destructor_: Pointer): Integer; cdecl;

  { ---- Reading results ---- }
  sqlite3_column_count: function(Stmt: PSQLite3Stmt): Integer; cdecl;
  sqlite3_column_name: function(Stmt: PSQLite3Stmt; Col: Integer): PAnsiChar; cdecl;
  sqlite3_column_type: function(Stmt: PSQLite3Stmt; Col: Integer): Integer; cdecl;
  sqlite3_column_bytes: function(Stmt: PSQLite3Stmt; Col: Integer): Integer; cdecl;
  sqlite3_column_text: function(Stmt: PSQLite3Stmt; Col: Integer): PAnsiChar; cdecl;
  sqlite3_column_blob: function(Stmt: PSQLite3Stmt; Col: Integer): Pointer; cdecl;
  sqlite3_column_int: function(Stmt: PSQLite3Stmt; Col: Integer): Integer; cdecl;
  sqlite3_column_int64: function(Stmt: PSQLite3Stmt; Col: Integer): Int64; cdecl;
  sqlite3_column_double: function(Stmt: PSQLite3Stmt; Col: Integer): Double; cdecl;

  { ---- Mutation bookkeeping ---- }
  sqlite3_changes: function(DB: PSQLite3): Integer; cdecl;
  sqlite3_total_changes: function(DB: PSQLite3): Integer; cdecl;
  sqlite3_last_insert_rowid: function(DB: PSQLite3): Int64; cdecl;

  { ---- Cancellation ----
    sqlite3_interrupt may be called from a thread other than the one running
    the statement; that is the whole reason this project talks to sqlite3.dll
    directly. The connection must not be closed concurrently with the call. }
  sqlite3_interrupt: procedure(DB: PSQLite3); cdecl;
  { Present since 3.41.0; nil on older libraries - always test before calling. }
  sqlite3_is_interrupted: function(DB: PSQLite3): Integer; cdecl;

type
  ESQLite3LoadError = class(Exception);

{ Loads sqlite3.dll and binds every entry point above.
  AFileName defaults to sqlite3.dll sitting next to the executable.
  Safe to call repeatedly and from several threads; only the first call works. }
procedure LoadSQLite3(const AFileName: string = '');

{ Releases the library. Every connection must be closed first. }
procedure UnloadSQLite3;

function SQLite3IsLoaded: Boolean;

{ Full path of the library that is actually loaded; empty when not loaded. }
function SQLite3LibraryPath: string;

{ <exe directory>\sqlite3.dll }
function DefaultSQLite3Path: string;

implementation

uses
  System.SyncObjs,
  System.IOUtils;

resourcestring
  SSQLiteDllNotFound =
    'Could not load the SQLite library:' + sLineBreak + '%s' + sLineBreak +
    sLineBreak + 'The file is missing or damaged (Windows error code: %d).';
  SSQLiteDllBadBitness =
    'The SQLite library has the wrong bitness:' + sLineBreak + '%s' + sLineBreak +
    sLineBreak + 'The application is 64-bit and requires a 64-bit sqlite3.dll.';
  SSQLiteEntryPointMissing =
    'The SQLite library (%s) has no entry point "%s".' + sLineBreak +
    'It is probably not sqlite3.dll, or a version that is too old.';
  SSQLiteVersionTooOld =
    'SQLite %s is too old. Version %s or newer is required.' + sLineBreak +
    'File: %s';
  SSQLiteInitFailed =
    'Could not initialize SQLite (%s): error code %d.';

var
  GLock: TCriticalSection = nil;
  GHandle: HMODULE = 0;
  GPath: string = '';

function SQLITE_STATIC: Pointer; inline;
begin
  Result := nil;
end;

function SQLITE_TRANSIENT: Pointer; inline;
begin
  Result := Pointer(NativeInt(-1));
end;

function DefaultSQLite3Path: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), SQLITE3_LIBRARY_NAME);
end;

function SQLite3IsLoaded: Boolean;
begin
  Result := GHandle <> 0;
end;

function SQLite3LibraryPath: string;
begin
  Result := GPath;
end;

function VersionNumberToString(AVersion: Integer): string;
begin
  Result := Format('%d.%d.%d', [AVersion div 1000000,
    (AVersion div 1000) mod 1000, AVersion mod 1000]);
end;

{ Resolves one entry point. Raises when a required export is missing, which is
  far more useful than an access violation on the first call. }
function Entry(const AName: string; ARequired: Boolean = True): Pointer;
var
  LName: AnsiString;
begin
  { GetProcAddress is ANSI-only - there is no GetProcAddressW - so PChar
    (PWideChar under Unicode Delphi) would not even compile here. }
  LName := AnsiString(AName);
  Result := GetProcAddress(GHandle, PAnsiChar(LName));
  if (Result = nil) and ARequired then
    raise ESQLite3LoadError.CreateResFmt(@SSQLiteEntryPointMissing, [GPath, AName]);
end;

procedure BindAll;
begin
  @sqlite3_libversion := Entry('sqlite3_libversion');
  @sqlite3_libversion_number := Entry('sqlite3_libversion_number');
  @sqlite3_sourceid := Entry('sqlite3_sourceid');
  @sqlite3_threadsafe := Entry('sqlite3_threadsafe');

  @sqlite3_initialize := Entry('sqlite3_initialize');
  @sqlite3_shutdown := Entry('sqlite3_shutdown');
  @sqlite3_config := Entry('sqlite3_config');

  @sqlite3_open_v2 := Entry('sqlite3_open_v2');
  @sqlite3_close_v2 := Entry('sqlite3_close_v2');
  @sqlite3_busy_timeout := Entry('sqlite3_busy_timeout');
  @sqlite3_extended_result_codes := Entry('sqlite3_extended_result_codes');
  @sqlite3_db_readonly := Entry('sqlite3_db_readonly');

  @sqlite3_errcode := Entry('sqlite3_errcode');
  @sqlite3_extended_errcode := Entry('sqlite3_extended_errcode');
  @sqlite3_errmsg := Entry('sqlite3_errmsg');
  @sqlite3_errstr := Entry('sqlite3_errstr');
  @sqlite3_free := Entry('sqlite3_free');

  @sqlite3_exec := Entry('sqlite3_exec');

  @sqlite3_prepare_v2 := Entry('sqlite3_prepare_v2');
  @sqlite3_step := Entry('sqlite3_step');
  @sqlite3_reset := Entry('sqlite3_reset');
  @sqlite3_finalize := Entry('sqlite3_finalize');
  @sqlite3_clear_bindings := Entry('sqlite3_clear_bindings');
  @sqlite3_stmt_readonly := Entry('sqlite3_stmt_readonly');
  @sqlite3_db_handle := Entry('sqlite3_db_handle');

  @sqlite3_bind_parameter_index := Entry('sqlite3_bind_parameter_index');
  @sqlite3_bind_null := Entry('sqlite3_bind_null');
  @sqlite3_bind_int := Entry('sqlite3_bind_int');
  @sqlite3_bind_int64 := Entry('sqlite3_bind_int64');
  @sqlite3_bind_double := Entry('sqlite3_bind_double');
  @sqlite3_bind_text := Entry('sqlite3_bind_text');
  @sqlite3_bind_blob := Entry('sqlite3_bind_blob');

  @sqlite3_column_count := Entry('sqlite3_column_count');
  @sqlite3_column_name := Entry('sqlite3_column_name');
  @sqlite3_column_type := Entry('sqlite3_column_type');
  @sqlite3_column_bytes := Entry('sqlite3_column_bytes');
  @sqlite3_column_text := Entry('sqlite3_column_text');
  @sqlite3_column_blob := Entry('sqlite3_column_blob');
  @sqlite3_column_int := Entry('sqlite3_column_int');
  @sqlite3_column_int64 := Entry('sqlite3_column_int64');
  @sqlite3_column_double := Entry('sqlite3_column_double');

  @sqlite3_changes := Entry('sqlite3_changes');
  @sqlite3_total_changes := Entry('sqlite3_total_changes');
  @sqlite3_last_insert_rowid := Entry('sqlite3_last_insert_rowid');

  @sqlite3_interrupt := Entry('sqlite3_interrupt');
  @sqlite3_is_interrupted := Entry('sqlite3_is_interrupted', False);
end;

procedure UnbindAll;
begin
  sqlite3_libversion := nil;
  sqlite3_libversion_number := nil;
  sqlite3_sourceid := nil;
  sqlite3_threadsafe := nil;
  sqlite3_initialize := nil;
  sqlite3_shutdown := nil;
  sqlite3_config := nil;
  sqlite3_open_v2 := nil;
  sqlite3_close_v2 := nil;
  sqlite3_busy_timeout := nil;
  sqlite3_extended_result_codes := nil;
  sqlite3_db_readonly := nil;
  sqlite3_errcode := nil;
  sqlite3_extended_errcode := nil;
  sqlite3_errmsg := nil;
  sqlite3_errstr := nil;
  sqlite3_free := nil;
  sqlite3_exec := nil;
  sqlite3_prepare_v2 := nil;
  sqlite3_step := nil;
  sqlite3_reset := nil;
  sqlite3_finalize := nil;
  sqlite3_clear_bindings := nil;
  sqlite3_stmt_readonly := nil;
  sqlite3_db_handle := nil;
  sqlite3_bind_parameter_index := nil;
  sqlite3_bind_null := nil;
  sqlite3_bind_int := nil;
  sqlite3_bind_int64 := nil;
  sqlite3_bind_double := nil;
  sqlite3_bind_text := nil;
  sqlite3_bind_blob := nil;
  sqlite3_column_count := nil;
  sqlite3_column_name := nil;
  sqlite3_column_type := nil;
  sqlite3_column_bytes := nil;
  sqlite3_column_text := nil;
  sqlite3_column_blob := nil;
  sqlite3_column_int := nil;
  sqlite3_column_int64 := nil;
  sqlite3_column_double := nil;
  sqlite3_changes := nil;
  sqlite3_total_changes := nil;
  sqlite3_last_insert_rowid := nil;
  sqlite3_interrupt := nil;
  sqlite3_is_interrupted := nil;
end;

procedure LoadSQLite3(const AFileName: string {= ''});
var
  LPath: string;
  LError: Cardinal;
  LVersion: Integer;
  LResult: Integer;
begin
  GLock.Enter;
  try
    if GHandle <> 0 then
      Exit;

    if AFileName <> '' then
      LPath := AFileName
    else
      LPath := DefaultSQLite3Path;
    GPath := LPath;

    { LOAD_WITH_ALTERED_SEARCH_PATH together with a full path pins the load to
      exactly this file - no current-directory or PATH lookup. }
    GHandle := LoadLibraryEx(PChar(LPath), 0, LOAD_WITH_ALTERED_SEARCH_PATH);
    if GHandle = 0 then
    begin
      LError := GetLastError;
      GPath := '';
      if LError = ERROR_BAD_EXE_FORMAT then
        raise ESQLite3LoadError.CreateResFmt(@SSQLiteDllBadBitness, [LPath])
      else
        raise ESQLite3LoadError.CreateResFmt(@SSQLiteDllNotFound, [LPath, LError]);
    end;

    try
      BindAll;

      LVersion := sqlite3_libversion_number;
      if LVersion < SQLITE_MIN_VERSION_NUMBER then
        raise ESQLite3LoadError.CreateResFmt(@SSQLiteVersionTooOld,
          [VersionNumberToString(LVersion),
           VersionNumberToString(SQLITE_MIN_VERSION_NUMBER), LPath]);

      { Every connection is opened with SQLITE_OPEN_NOMUTEX and is used by a
        single thread at a time, so multi-thread mode is enough and skips the
        per-connection mutex. Must happen before sqlite3_initialize; returns
        SQLITE_MISUSE if something already initialised the library, in which
        case the (safer) serialized default simply stays in force. }
      sqlite3_config(SQLITE_CONFIG_MULTITHREAD);

      LResult := sqlite3_initialize;
      if LResult <> SQLITE_OK then
        raise ESQLite3LoadError.CreateResFmt(@SSQLiteInitFailed, [LPath, LResult]);
    except
      UnbindAll;
      FreeLibrary(GHandle);
      GHandle := 0;
      GPath := '';
      raise;
    end;
  finally
    GLock.Leave;
  end;
end;

procedure UnloadSQLite3;
begin
  GLock.Enter;
  try
    if GHandle = 0 then
      Exit;
    if Assigned(sqlite3_shutdown) then
      sqlite3_shutdown;
    UnbindAll;
    FreeLibrary(GHandle);
    GHandle := 0;
    GPath := '';
  finally
    GLock.Leave;
  end;
end;

initialization
  GLock := TCriticalSection.Create;

finalization
  UnloadSQLite3;
  GLock.Free;

end.
