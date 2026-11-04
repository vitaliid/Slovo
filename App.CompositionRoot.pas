unit App.CompositionRoot;

{ Composition root (Slovo_03 A.2; C-13, C-22): manual constructor injection in
  two phases.

  Create      - nothing that can fail fatally: paths, data\ + write probe, logger,
                settings, interface language, reading font.
  OpenLibrary - phase 0: sqlite3.dll (with FTS5), library.db (read-only, UTF-8
                path, SchemaVersion), the snowball tokenizer, the catalog; every
                failure -> MessageBox in the user's language -> False -> exit.
  BindMainForm / UnbindMainForm - phase 1, through IMainView only (C-14). }

interface

uses
  System.SysUtils,
  Winapi.Windows,
  Core.Domain,
  Core.Catalog,
  Core.Contracts,
  Infra.SQLite.LibraryDatabase,
  Presentation.Theme,
  Presentation.Fonts,
  Presentation.MainViewModel,
  Presentation.Views;

type
  TCompositionRoot = class
  private
    FExeDir, FDataDir: string;
    FDataWritable: Boolean;

    FLogger: ILogger;
    FSettings: ISettings;
    FFonts: TPrivateFonts;
    FTheme: TReaderTheme;

    FDatabase: TLibraryDatabase;        // ONE connection for the session (C-02, C-21)
    FLibrary: ILibrary;
    FCatalog: TLibraryCatalog;          // immutable after phase 0; owned here
    FSearchIndex: ISearchIndex;
    FMainViewModel: TMainViewModel;

    function Fail(const MessageKey: string): Boolean;
    procedure ShowStartupMessage(const MessageKey: string; Flags: UINT);
  public
    constructor Create;
    destructor Destroy; override;

    function OpenLibrary: Boolean;
    procedure BindMainForm(const View: IMainView);
    procedure UnbindMainForm(const View: IMainView);
    procedure ReportFatal(E: Exception);
  end;

implementation

uses
  System.IOUtils,
  Infrastructure.SQLite3.Api,
  Infrastructure.SQLite3.Database,
  Infra.Logging.FileLogger,
  Infra.Settings.IniSettings,
  Infra.SQLite.LibraryReader,
  Infra.Search.Fts5SearchIndex,
  Presentation.Localization;

// ForceDirectories + a probe file written and deleted. Decides only one thing:
// whether to warn the user that settings and log will not be kept (D-04).
function EnsureWritableDir(const Dir: string): Boolean;
var
  Probe: string;
begin
  try
    TDirectory.CreateDirectory(Dir);
    Probe := TPath.Combine(Dir, '.write-probe');
    TFile.WriteAllText(Probe, 'x');
    TFile.Delete(Probe);
    Result := True;
  except
    Result := False;
  end;
end;

{ TCompositionRoot }

constructor TCompositionRoot.Create;
var
  Logger: ILogger;
begin
  inherited;
  // Paths from ParamStr(0), never from the current directory: a shortcut with
  // "Start in" filled in must not break the start (portable layout, D-02).
  FExeDir := TPath.GetDirectoryName(ParamStr(0));
  FDataDir := TPath.Combine(FExeDir, 'data');

  FDataWritable := EnsureWritableDir(FDataDir);
  FLogger := TFileLogger.Create(TPath.Combine(FDataDir, 'slovo.log'));
  FSettings := TIniSettings.Create(TPath.Combine(FDataDir, 'settings.ini'), FLogger);

  // Language before the first text, including the phase-0 MessageBox (R3-25).
  Logger := FLogger;
  InitLocalization(TPath.Combine(FExeDir, 'lang'), FSettings.GetLanguage,
    procedure(const Msg: string)
    begin
      Logger.LogError('Localization', Msg);
    end);

  FFonts := TPrivateFonts.Create(TPath.Combine(FExeDir, 'fonts'), FLogger);
  FTheme := FFonts.ResolveTheme;
end;

destructor TCompositionRoot.Destroy;
begin
  // Reverse order. No tasks in flight (C-21) - nothing to wait for.
  FMainViewModel.Free;          // holds subscriptions and the catalog reference
  FSearchIndex := nil;          // refers to the catalog - before it goes
  FLibrary := nil;
  FCatalog.Free;
  FDatabase.Free;               // after everyone working on its connection
  FFonts.Free;                  // no RemoveFontResourceEx (E-04)
  FSettings := nil;             // Save was already called from Unbind
  FLogger := nil;               // last - the others log until they are gone
  inherited;
end;

procedure TCompositionRoot.ShowStartupMessage(const MessageKey: string; Flags: UINT);
begin
  MessageBox(0, PChar(L(MessageKey)), PChar(L('app.title')), MB_OK or MB_TASKMODAL or Flags);
end;

function TCompositionRoot.Fail(const MessageKey: string): Boolean;
begin
  ShowStartupMessage(MessageKey, MB_ICONERROR);
  Result := False;
end;

function TCompositionRoot.OpenLibrary: Boolean;
var
  OpenError: TResultError;
  Probe: TSQLiteDatabase;
  HasFts5: Boolean;
begin
  // 6. sqlite3.dll - only from here, by full path (D-08).
  try
    LoadSQLite3(TPath.Combine(FExeDir, 'sqlite3.dll'));
  except
    on E: Exception do
    begin
      FLogger.LogError('Startup', E.ClassName + ': ' + E.Message);
      Exit(Fail('startup.noSqlite'));
    end;
  end;
  try
    Probe := TSQLiteDatabase.Create(':memory:', omCreate, 0);
    try
      HasFts5 := Probe.SupportsFTS5;
    finally
      Probe.Free;
    end;
  except
    HasFts5 := False;
  end;
  if not HasFts5 then
  begin
    FLogger.LogError('Startup', 'sqlite3.dll without FTS5: ' + SQLite3LibraryPath);
    Exit(Fail('startup.wrongSqlite'));
  end;

  // 7. library.db: read-only, UTF-8 path, Meta.SchemaVersion (B-16).
  FDatabase := TLibraryDatabase.Create(FLogger);
  if not FDatabase.Open(TPath.Combine(FExeDir, 'library.db'), OpenError) then
    case OpenError of
      reUnsupportedSchema: Exit(Fail('startup.unsupportedSchema'));
      reModuleCorrupted:   Exit(Fail('startup.libraryCorrupted'));
    else
      Exit(Fail('startup.noLibrary'));     // most often: started straight from the ZIP
    end;

  // 7a. B-31: stemmed tables open only with a DLL that has snowball.
  if not FDatabase.CheckStemTokenizer then
    Exit(Fail('startup.wrongSqlite'));

  // 8. The catalog - once per session (B-29).
  FLibrary := TLibrary.Create(FDatabase, FLogger);
  try
    FCatalog := FLibrary.LoadCatalog;
  except
    on E: Exception do
    begin
      FLogger.LogError('Startup', E.ClassName + ': ' + E.Message);
      Exit(Fail('startup.libraryCorrupted'));
    end;
  end;
  if Length(FCatalog.Modules) = 0 then
    Exit(Fail('startup.noLibrary'));

  // 9. Search on the same connection (C-21); the catalog gives module languages (B-31).
  FSearchIndex := TFts5SearchIndex.Create(FDatabase, FCatalog, FLogger);

  // 10. A read-only folder is not an exit, just one warning (D-04).
  if not FDataWritable then
    ShowStartupMessage('startup.readOnlyFolder', MB_ICONWARNING);

  // 11. The ViewModel gets only ports and the catalog.
  FMainViewModel := TMainViewModel.Create(FLibrary, FCatalog, FSearchIndex, FSettings, FLogger);
  Result := True;
end;

procedure TCompositionRoot.BindMainForm(const View: IMainView);
begin
  View.Bind(FMainViewModel, FSettings, FTheme);
end;

procedure TCompositionRoot.UnbindMainForm(const View: IMainView);
begin
  View.Unbind;
end;

procedure TCompositionRoot.ReportFatal(E: Exception);
begin
  // Before Application.Run there is no VCL handler: without this an exception
  // from phase 1 would close the program without a word.
  FLogger.LogError('Startup', E.ClassName + ': ' + E.Message);
  ShowStartupMessage('startup.unexpected', MB_ICONERROR);
end;

end.
