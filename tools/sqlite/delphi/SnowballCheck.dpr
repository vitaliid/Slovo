program SnowballCheck;

{ Slovo — Sprint 1, step 1: checks the custom sqlite3.dll from Delphi.

  Repeats the check from Slovo_02 («Перевірено 2026-11-01»):
    VersesStem_uk  "жертва"          → жертву, Жертви, жертву
    VersesStem_uk  "жертва Богові"   → Жертви Богові
    VersesStem_ru  "жертва"          → Жертва, жертвы
    VersesStem_en  "sacrifice"/"saving" → sacrifices / saved, save
    VersesFTS      "жертва"          → Жертва   (exact table: no word forms)
  plus the phase-0 startup probe (C-22) and the highlight() → UTF-16 offset
  path that Fts5SearchIndex will use (char(2)/char(3) markers, B-24).

  Build: Delphi 13, Win64, console. Put sqlite3.dll next to the EXE.
  Exit code: 0 = all PASS, 1 = at least one FAIL, 2 = DLL could not be used. }

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  System.StrUtils;

const
  SQLITE_OK   = 0;
  SQLITE_ROW  = 100;
  SQLITE_DONE = 101;
  SQLITE_OPEN_READWRITE = $00000002;
  SQLITE_OPEN_CREATE    = $00000004;
  SQLITE_OPEN_MEMORY    = $00000080;
  SQLITE_OPEN_NOMUTEX   = $00008000;
  SQLITE_TRANSIENT      = Pointer(-1);

  HitOpen  = #2;   // highlight(T, 0, char(2), char(3)) — as in Slovo_02
  HitClose = #3;

type
  PSqlite3 = Pointer;
  PSqlite3Stmt = Pointer;

  // Subset of the C API, bound at run time (D-08). Win64 has one calling
  // convention; cdecl keeps the declarations correct for Win32 as well.
  TSqlite3Api = record
    libversion: function: PAnsiChar; cdecl;
    compileoption_used: function(zOptName: PAnsiChar): Integer; cdecl;
    open_v2: function(filename: PAnsiChar; out db: PSqlite3; flags: Integer; zVfs: PAnsiChar): Integer; cdecl;
    close_v2: function(db: PSqlite3): Integer; cdecl;
    exec: function(db: PSqlite3; sql: PAnsiChar; callback, arg: Pointer; errmsg: PPAnsiChar): Integer; cdecl;
    free: procedure(p: Pointer); cdecl;
    errmsg: function(db: PSqlite3): PAnsiChar; cdecl;
    prepare_v2: function(db: PSqlite3; sql: PAnsiChar; nByte: Integer; out stmt: PSqlite3Stmt; pzTail: PPAnsiChar): Integer; cdecl;
    bind_text: function(stmt: PSqlite3Stmt; idx: Integer; value: PAnsiChar; n: Integer; destructor_: Pointer): Integer; cdecl;
    step: function(stmt: PSqlite3Stmt): Integer; cdecl;
    column_int64: function(stmt: PSqlite3Stmt; iCol: Integer): Int64; cdecl;
    column_text: function(stmt: PSqlite3Stmt; iCol: Integer): PAnsiChar; cdecl;
    column_bytes: function(stmt: PSqlite3Stmt; iCol: Integer): Integer; cdecl;
    finalize: function(stmt: PSqlite3Stmt): Integer; cdecl;
  end;

  TCheckCase = record
    Table, Query, Expected: string;
  end;

const
  Cases: array[0..5] of TCheckCase = (
    (Table: 'VersesStem_uk'; Query: 'жертва';        Expected: 'жертву|Жертви|жертву'),
    (Table: 'VersesStem_uk'; Query: 'жертва Богові'; Expected: 'Жертви Богові'),
    (Table: 'VersesStem_ru'; Query: 'жертва';        Expected: 'Жертва|жертвы'),
    (Table: 'VersesStem_en'; Query: 'sacrifice';     Expected: 'sacrifices'),
    (Table: 'VersesStem_en'; Query: 'saving';        Expected: 'saved|save'),
    (Table: 'VersesFTS';     Query: 'жертва';        Expected: 'Жертва'));

  StemTables: array[0..2] of string = ('VersesStem_uk', 'VersesStem_ru', 'VersesStem_en');

  // The Bible part of library.db (Slovo_02) + the same verses as test.sql.
  SchemaSql =
    'CREATE TABLE Modules (ModuleId TEXT PRIMARY KEY, Kind INTEGER NOT NULL, Language TEXT NOT NULL);' +
    'CREATE TABLE Verses (Id INTEGER PRIMARY KEY, ModuleId TEXT NOT NULL, BookCode TEXT NOT NULL,' +
    '  ChapterNumber INTEGER NOT NULL, VerseNumber INTEGER NOT NULL, Text TEXT NOT NULL);' +
    'CREATE VIRTUAL TABLE VersesFTS USING fts5(Text, content=''Verses'', content_rowid=''Id'',' +
    '  tokenize=''unicode61 remove_diacritics 0'');' +
    'CREATE VIEW Verses_uk AS SELECT v.Id, v.Text FROM Verses v JOIN Modules m ON m.ModuleId = v.ModuleId WHERE m.Language = ''uk'';' +
    'CREATE VIEW Verses_ru AS SELECT v.Id, v.Text FROM Verses v JOIN Modules m ON m.ModuleId = v.ModuleId WHERE m.Language = ''ru'';' +
    'CREATE VIEW Verses_en AS SELECT v.Id, v.Text FROM Verses v JOIN Modules m ON m.ModuleId = v.ModuleId WHERE m.Language = ''en'';' +
    'CREATE VIRTUAL TABLE VersesStem_uk USING fts5(Text, content=''Verses_uk'', content_rowid=''Id'',' +
    '  tokenize=''snowball ukrainian unicode61 remove_diacritics 0'');' +
    'CREATE VIRTUAL TABLE VersesStem_ru USING fts5(Text, content=''Verses_ru'', content_rowid=''Id'',' +
    '  tokenize=''snowball russian unicode61 remove_diacritics 0'');' +
    'CREATE VIRTUAL TABLE VersesStem_en USING fts5(Text, content=''Verses_en'', content_rowid=''Id'',' +
    '  tokenize=''snowball english unicode61 remove_diacritics 0'');' +
    'INSERT INTO Modules VALUES (''test-uk'', 1, ''uk''), (''test-ru'', 1, ''ru''), (''test-en'', 1, ''en'');' +
    'INSERT INTO Verses (ModuleId, BookCode, ChapterNumber, VerseNumber, Text) VALUES' +
    '  (''test-uk'', ''LEV'', 1, 1, ''І приніс він жертву Господеві.''),' +
    '  (''test-uk'', ''PSA'', 51, 19, ''Жертви Богові — дух зламаний.''),' +
    '  (''test-uk'', ''HEB'', 10, 12, ''Він приніс одну жертву за гріхи.''),' +
    '  (''test-uk'', ''GEN'', 1, 1, ''На початку Бог створив небо й землю.''),' +
    '  (''test-ru'', ''PSA'', 50, 19, ''Жертва Богу — дух сокрушенный.''),' +
    '  (''test-ru'', ''HEB'', 10, 11, ''Каждый священник приносит одни и те же жертвы.''),' +
    '  (''test-ru'', ''GEN'', 1, 1, ''В начале сотворил Бог небо и землю.''),' +
    '  (''test-en'', ''PSA'', 51, 17, ''The sacrifices of God are a broken spirit.''),' +
    '  (''test-en'', ''MAT'', 27, 42, ''He saved others; himself he cannot save.''),' +
    '  (''test-en'', ''GEN'', 1, 1, ''In the beginning God created the heaven and the earth.'');' +
    'INSERT INTO VersesFTS(VersesFTS) VALUES(''rebuild'');' +
    'INSERT INTO VersesStem_uk(VersesStem_uk) VALUES(''rebuild'');' +
    'INSERT INTO VersesStem_ru(VersesStem_ru) VALUES(''rebuild'');' +
    'INSERT INTO VersesStem_en(VersesStem_en) VALUES(''rebuild'');';

var
  Api: TSqlite3Api;
  Db: PSqlite3;
  Failures: Integer = 0;

procedure Report(Ok: Boolean; const What: string);
begin
  if Ok then
    Writeln('PASS  ', What)
  else
  begin
    Writeln('FAIL  ', What);
    Inc(Failures);
  end;
end;

function FromUtf8(P: PAnsiChar; Len: Integer): string;
var
  Bytes: TBytes;
begin
  if (P = nil) or (Len <= 0) then
    Exit('');
  SetLength(Bytes, Len);
  Move(P^, Bytes[0], Len);
  Result := TEncoding.UTF8.GetString(Bytes);
end;

function ToUtf8(const S: string): UTF8String;
begin
  Result := UTF8Encode(S);
end;

function LastError: string;
var
  P: PAnsiChar;
begin
  P := Api.errmsg(Db);
  Result := FromUtf8(P, Length(P));
end;

function LoadSqlite(const DllPath: string; out Error: string): Boolean;
var
  H: HMODULE;

  function Bind(var Proc; const Name: string): Boolean;
  begin
    Pointer(Proc) := GetProcAddress(H, PChar(Name));
    Result := Pointer(Proc) <> nil;
    if not Result then
      Error := 'Missing export ' + Name;
  end;

begin
  Result := False;
  // Full path: never pick up a sqlite3.dll from System32 or PATH (D-08).
  H := LoadLibraryEx(PChar(DllPath), 0, LOAD_WITH_ALTERED_SEARCH_PATH);
  if H = 0 then
  begin
    Error := 'Cannot load ' + DllPath + ' (error ' + IntToStr(GetLastError) + ')';
    Exit;
  end;
  Result :=
    Bind(Api.libversion, 'sqlite3_libversion') and
    Bind(Api.compileoption_used, 'sqlite3_compileoption_used') and
    Bind(Api.open_v2, 'sqlite3_open_v2') and
    Bind(Api.close_v2, 'sqlite3_close_v2') and
    Bind(Api.exec, 'sqlite3_exec') and
    Bind(Api.free, 'sqlite3_free') and
    Bind(Api.errmsg, 'sqlite3_errmsg') and
    Bind(Api.prepare_v2, 'sqlite3_prepare_v2') and
    Bind(Api.bind_text, 'sqlite3_bind_text') and
    Bind(Api.step, 'sqlite3_step') and
    Bind(Api.column_int64, 'sqlite3_column_int64') and
    Bind(Api.column_text, 'sqlite3_column_text') and
    Bind(Api.column_bytes, 'sqlite3_column_bytes') and
    Bind(Api.finalize, 'sqlite3_finalize');
end;

function ExecSql(const Sql: string; out Error: string): Boolean;
var
  ErrMsg: PAnsiChar;
begin
  ErrMsg := nil;
  Result := Api.exec(Db, PAnsiChar(ToUtf8(Sql)), nil, nil, @ErrMsg) = SQLITE_OK;
  if not Result then
  begin
    Error := FromUtf8(ErrMsg, Length(ErrMsg));
    Api.free(ErrMsg);
  end;
end;

// Same rule as TryBuildMatchQuery in Slovo_02: every term in double quotes.
function QuoteTerm(const Term: string): string;
begin
  Result := '"' + StringReplace(Term, '"', '""', [rfReplaceAll]) + '"';
end;

// Strips the char(2)/char(3) markers and returns the hit words, cut out of the
// CLEAN text by UTF-16 offsets — exactly what Fts5SearchIndex will do (B-24).
function ExtractHits(const Marked: string; out Clean: string): TArray<string>;
var
  I, Start: Integer;
  Starts, Lens: TArray<Integer>;
begin
  Clean := '';
  Start := -1;
  for I := 1 to Length(Marked) do
    case Marked[I] of
      HitOpen:
        Start := Length(Clean);                // 0-based UTF-16 offset
      HitClose:
        begin
          Starts := Starts + [Start];
          Lens := Lens + [Length(Clean) - Start];
        end;
    else
      Clean := Clean + Marked[I];
    end;
  SetLength(Result, Length(Starts));
  for I := 0 to High(Starts) do
    Result[I] := Copy(Clean, Starts[I] + 1, Lens[I]);
end;

procedure RunCase(const C: TCheckCase);
var
  Stmt: PSqlite3Stmt;
  Sql, Clean, Original, Actual, What: string;
  Match: UTF8String;
  Rc: Integer;
  Hits: TArray<string>;
  OffsetsOk: Boolean;
begin
  What := Format('%s MATCH %s', [C.Table, QuoteTerm(C.Query)]);
  // Table name is from the constant list above, never from user input.
  Sql := Format('SELECT highlight(%0:s, 0, char(2), char(3)), v.Text ' +
                'FROM %0:s JOIN Verses v ON v.Id = %0:s.rowid ' +
                'WHERE %0:s MATCH ?1 ORDER BY v.Id', [C.Table]);
  if Api.prepare_v2(Db, PAnsiChar(ToUtf8(Sql)), -1, Stmt, nil) <> SQLITE_OK then
  begin
    Report(False, What + '  →  ' + LastError);
    Exit;
  end;
  try
    Match := ToUtf8(QuoteTerm(C.Query));
    Api.bind_text(Stmt, 1, PAnsiChar(Match), Length(Match), SQLITE_TRANSIENT);
    Actual := '';
    OffsetsOk := True;
    repeat
      Rc := Api.step(Stmt);
      if Rc = SQLITE_ROW then
      begin
        Hits := ExtractHits(FromUtf8(Api.column_text(Stmt, 0), Api.column_bytes(Stmt, 0)), Clean);
        Original := FromUtf8(Api.column_text(Stmt, 1), Api.column_bytes(Stmt, 1));
        OffsetsOk := OffsetsOk and (Clean = Original);  // offsets valid in Verses.Text
        for var Hit in Hits do
          if Actual = '' then Actual := Hit else Actual := Actual + '|' + Hit;
      end;
    until Rc <> SQLITE_ROW;
    if Rc <> SQLITE_DONE then
    begin
      Report(False, What + '  →  ' + LastError);
      Exit;
    end;
    if Actual = '' then
      Actual := '(нічого)';
    if (Actual = C.Expected) and OffsetsOk then
      Report(True, What + '  →  ' + Actual)
    else if not OffsetsOk then
      Report(False, What + '  →  text without markers differs from Verses.Text')
    else
      Report(False, What + '  →  ' + Actual + '   очікувалось: ' + C.Expected);
  finally
    Api.finalize(Stmt);
  end;
end;

// Phase-0 startup probe from Slovo_02 (C-22): fails with "no such tokenizer"
// when a foreign sqlite3.dll without Snowball was loaded.
procedure ProbeStemTable(const Table: string);
var
  Stmt: PSqlite3Stmt;
  Rc: Integer;
  Sql: string;
begin
  Sql := Format('SELECT rowid FROM %0:s WHERE %0:s MATCH ''a'' LIMIT 1', [Table]);
  Rc := Api.prepare_v2(Db, PAnsiChar(ToUtf8(Sql)), -1, Stmt, nil);
  if Rc = SQLITE_OK then
  begin
    Rc := Api.step(Stmt);
    Api.finalize(Stmt);
  end;
  if (Rc = SQLITE_ROW) or (Rc = SQLITE_DONE) then
    Report(True, 'probe ' + Table)
  else
    Report(False, 'probe ' + Table + '  →  ' + LastError);
end;

var
  DllPath, Error: string;
  Ok: Boolean;
  C: TCheckCase;
  T: string;
begin
  SetConsoleOutputCP(CP_UTF8);    // the console shows UTF-8 ...
  SetTextCodePage(Output, CP_UTF8); // ... and Writeln sends UTF-8
  DllPath := ExtractFilePath(ParamStr(0)) + 'sqlite3.dll';
  if ParamCount > 0 then
    DllPath := ParamStr(1);

  if not LoadSqlite(DllPath, Error) then
  begin
    Writeln('FAIL  ', Error);
    Halt(2);
  end;
  Writeln('DLL   ', DllPath);
  Writeln('SQLite ', string(AnsiString(Api.libversion)));

  Report(Api.compileoption_used('ENABLE_FTS5') = 1, 'compile option ENABLE_FTS5');

  if Api.open_v2(':memory:', Db,
       SQLITE_OPEN_READWRITE or SQLITE_OPEN_CREATE or SQLITE_OPEN_MEMORY or SQLITE_OPEN_NOMUTEX,
       nil) <> SQLITE_OK then
  begin
    Writeln('FAIL  sqlite3_open_v2');
    Halt(2);
  end;
  try
    Ok := ExecSql(SchemaSql, Error);
    Report(Ok, 'schema + tokenize=''snowball ...''' + IfThen(Ok, '', '  →  ' + Error));
    if Ok then
    begin
      for C in Cases do
        RunCase(C);
      for T in StemTables do
        ProbeStemTable(T);
    end;
  finally
    Api.close_v2(Db);
  end;

  Writeln;
  if Failures = 0 then
    Writeln('ALL PASS')
  else
    Writeln(Failures, ' FAIL');
  if Failures > 0 then
    ExitCode := 1;
end.
