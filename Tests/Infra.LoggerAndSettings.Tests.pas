unit Infra.LoggerAndSettings.Tests;

{ TFileLogger (C-11, C-18) and TIniSettings (E-06, E-07, Slovo_04 C.2),
  in temporary folders (Slovo_03 Part C). }

interface

uses
  DUnitX.TestFramework,
  Core.Domain,
  Core.Contracts,
  Slovo.TestSupport;

type
  [TestFixture]
  TFileLoggerTests = class
  private
    FDir: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test] procedure CreatesMissingFolderAndAppends;
    [Test] procedure WritesUtf8WithoutBom;
    [Test] procedure NeverRaises_WhenPathIsUnusable;
  end;

  [TestFixture]
  TIniSettingsTests = class
  private
    FDir: string;
    FFile: string;
    FLogger: TTestLogger;
    FLoggerRef: IInterface;
    function NewSettings: ISettings;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test] procedure MissingFile_GivesDefaults;
    [Test] procedure RoundTrip_AllKeys;
    [Test] procedure Positions_BookAndBible;
    [Test] procedure LastPosition_WritesLastAndPositionsRow;
    [Test] procedure ValuesWithSpaces_AreTrimmed;
    [Test] procedure InvalidValues_FallBackToDefaults;
    [Test] procedure ZoomStep_IsClamped;
    [Test] procedure Save_IntoUnwritablePath_DoesNotRaise_LogsOnce;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  System.IOUtils,
  Infra.Logging.FileLogger,
  Infra.Settings.IniSettings;

{ TFileLoggerTests }

procedure TFileLoggerTests.Setup;
begin
  FDir := NewTempDir;
end;

procedure TFileLoggerTests.TearDown;
begin
  try
    TDirectory.Delete(FDir, True);
  except
  end;
end;

procedure TFileLoggerTests.CreatesMissingFolderAndAppends;
var
  Logger: ILogger;
  FileName: string;
  Lines: TArray<string>;
begin
  FileName := TPath.Combine(TPath.Combine(FDir, 'data'), 'slovo.log');
  Logger := TFileLogger.Create(FileName);
  Logger.LogError('Test', 'first');
  Logger.LogError('Test', 'second');
  Assert.IsTrue(TFile.Exists(FileName));
  Lines := TFile.ReadAllLines(FileName, TEncoding.UTF8);
  Assert.AreEqual(2, Integer(Length(Lines)));
  Assert.IsTrue(Lines[0].EndsWith('[Test] first'), Lines[0]);
  Assert.IsTrue(Lines[1].EndsWith('[Test] second'), Lines[1]);
end;

procedure TFileLoggerTests.WritesUtf8WithoutBom;
var
  Logger: ILogger;
  FileName: string;
  Bytes: TBytes;
begin
  FileName := TPath.Combine(FDir, 'slovo.log');
  Logger := TFileLogger.Create(FileName);
  Logger.LogError('Пошук', 'жертва');
  Logger.LogError('Пошук', 'ще раз');
  Bytes := TFile.ReadAllBytes(FileName);
  Assert.IsFalse((Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB), 'no BOM expected');
  Assert.IsTrue(TEncoding.UTF8.GetString(Bytes).Contains('[Пошук] жертва'));
  Assert.IsFalse(TEncoding.UTF8.GetString(Bytes).Contains(#$FEFF), 'no BOM in the middle');
end;

procedure TFileLoggerTests.NeverRaises_WhenPathIsUnusable;
var
  Logger: ILogger;
  AFile: string;
begin
  // A "folder" that is actually a file: neither the folder nor the log can be created.
  AFile := TPath.Combine(FDir, 'not-a-folder');
  TFile.WriteAllText(AFile, 'x');
  Logger := TFileLogger.Create(TPath.Combine(AFile, 'slovo.log'));
  Assert.WillNotRaiseAny(
    procedure
    begin
      Logger.LogError('Test', 'lost, and that is fine');
    end);
end;

{ TIniSettingsTests }

procedure TIniSettingsTests.Setup;
begin
  FDir := NewTempDir;
  FFile := TPath.Combine(FDir, 'settings.ini');
  FLogger := TTestLogger.Create;
  FLoggerRef := FLogger;
end;

procedure TIniSettingsTests.TearDown;
begin
  try
    TDirectory.Delete(FDir, True);
  except
  end;
end;

function TIniSettingsTests.NewSettings: ISettings;
begin
  Result := TIniSettings.Create(FFile, FLogger);
end;

procedure TIniSettingsTests.MissingFile_GivesDefaults;
var
  S: ISettings;
  R: TRect;
  Maximized: Boolean;
  P: TReadingPosition;
begin
  S := NewSettings;
  Assert.AreEqual('uk', S.GetLanguage);
  Assert.AreEqual(0, S.GetZoomStep);
  Assert.IsTrue(S.GetLeftPanelVisible);
  Assert.IsTrue(S.GetRightPanelVisible);
  Assert.IsFalse(S.GetWindowBounds(R, Maximized));
  Assert.IsFalse(S.GetLastPosition(P));
  Assert.AreEqual(0, Integer(Length(S.GetCheckedModules)));
  Assert.IsTrue(S.GetSearchWholeLibrary);       // default WholeLibrary=1
  Assert.IsFalse(S.GetExactPhrase);
  Assert.IsFalse(S.GetWordForms);
  Assert.IsFalse(TFile.Exists(FFile), 'nothing is written before Save');
end;

procedure TIniSettingsTests.RoundTrip_AllKeys;
var
  S: ISettings;
  R: TRect;
  Maximized: Boolean;
  Checked: TArray<TModuleId>;
begin
  S := NewSettings;
  S.SetLanguage('ru');
  S.SetZoomStep(3);
  S.SetLeftPanelVisible(False);
  S.SetRightPanelVisible(True);
  S.SetWindowBounds(TRect.Create(TPoint.Create(120, 80), 1280, 800), True);
  S.SetCheckedModules(['PP', 'GC', 'ohienko-uk']);
  S.SetSearchWholeLibrary(False);
  S.SetExactPhrase(True);
  S.SetWordForms(True);
  S.Save;

  S := NewSettings;
  Assert.AreEqual('ru', S.GetLanguage);
  Assert.AreEqual(3, S.GetZoomStep);
  Assert.IsFalse(S.GetLeftPanelVisible);
  Assert.IsTrue(S.GetRightPanelVisible);
  Assert.IsTrue(S.GetWindowBounds(R, Maximized));
  Assert.AreEqual(120, R.Left);
  Assert.AreEqual(80, R.Top);
  Assert.AreEqual(1280, R.Width);
  Assert.AreEqual(800, R.Height);
  Assert.IsTrue(Maximized);
  Checked := S.GetCheckedModules;
  Assert.AreEqual(3, Integer(Length(Checked)));
  Assert.AreEqual('ohienko-uk', string(Checked[2]));
  Assert.IsFalse(S.GetSearchWholeLibrary);
  Assert.IsTrue(S.GetExactPhrase);
  Assert.IsTrue(S.GetWordForms);
  Assert.AreEqual(0, FLogger.Count);
end;

procedure TIniSettingsTests.Positions_BookAndBible;
var
  S: ISettings;
  P, Got: TReadingPosition;
begin
  S := NewSettings;
  P := Default(TReadingPosition);
  P.Kind := ckBook;
  P.Chapter.ModuleId := 'PP';
  P.Chapter.ChapterOrder := 3;
  S.SetPosition(P);
  P := Default(TReadingPosition);
  P.Kind := ckBibleTranslation;
  P.BibleChapter.Book.ModuleId := 'ohienko-uk';
  P.BibleChapter.Book.BookCode := 'GEN';
  P.BibleChapter.ChapterNumber := 22;
  S.SetPosition(P);
  S.Save;

  // Format on disk (Slovo_04 C.2): colon means Bible.
  Assert.IsTrue(TFile.ReadAllText(FFile).Contains('ohienko-uk=GEN:22'));
  Assert.IsTrue(TFile.ReadAllText(FFile).Contains('PP=3'));

  S := NewSettings;
  Assert.IsTrue(S.GetPosition('PP', Got));
  Assert.IsTrue(Got.Kind = ckBook);
  Assert.AreEqual(3, Got.Chapter.ChapterOrder);
  Assert.IsTrue(S.GetPosition('ohienko-uk', Got));
  Assert.IsTrue(Got.Kind = ckBibleTranslation);
  Assert.AreEqual('GEN', string(Got.BibleChapter.Book.BookCode));
  Assert.AreEqual(22, Got.BibleChapter.ChapterNumber);
  Assert.AreEqual('ohienko-uk', string(Got.ModuleId));
  Assert.IsFalse(S.GetPosition('GC', Got));
end;

procedure TIniSettingsTests.LastPosition_WritesLastAndPositionsRow;
var
  S: ISettings;
  P, Got: TReadingPosition;
begin
  S := NewSettings;
  P := Default(TReadingPosition);
  P.Kind := ckBook;
  P.Chapter.ModuleId := 'DA';
  P.Chapter.ChapterOrder := 2;
  S.SetLastPosition(P);
  S.Save;

  S := NewSettings;
  Assert.IsTrue(S.GetLastPosition(Got));
  Assert.AreEqual('DA', string(Got.ModuleId));
  Assert.AreEqual(2, Got.Chapter.ChapterOrder);
  Assert.IsTrue(S.GetPosition('DA', Got), 'SetLastPosition also writes [Positions]');
end;

procedure TIniSettingsTests.ValuesWithSpaces_AreTrimmed;
var
  S: ISettings;
  P: TReadingPosition;
begin
  TFile.WriteAllText(FFile,
    '[Ui]' + sLineBreak + 'Language = en ' + sLineBreak + 'ZoomStep = 2 ' + sLineBreak +
    '[Reading]' + sLineBreak + 'Last = ohienko-uk ' + sLineBreak +
    '[Positions]' + sLineBreak + 'ohienko-uk = PSA : 51 ' + sLineBreak +
    '[Search]' + sLineBreak + 'Checked = PP , GC ,, ' + sLineBreak, TEncoding.UTF8);
  S := NewSettings;
  Assert.AreEqual('en', S.GetLanguage);
  Assert.AreEqual(2, S.GetZoomStep);
  Assert.IsTrue(S.GetLastPosition(P));
  Assert.AreEqual('PSA', string(P.BibleChapter.Book.BookCode));
  Assert.AreEqual(51, P.BibleChapter.ChapterNumber);
  Assert.AreEqual(2, Integer(Length(S.GetCheckedModules)));
  Assert.AreEqual('GC', string(S.GetCheckedModules[1]));
end;

procedure TIniSettingsTests.InvalidValues_FallBackToDefaults;
var
  S: ISettings;
  P: TReadingPosition;
begin
  TFile.WriteAllText(FFile,
    '[Ui]' + sLineBreak + 'Language=de' + sLineBreak + 'ZoomStep=abc' + sLineBreak +
    'LeftPanel=maybe' + sLineBreak +
    '[Reading]' + sLineBreak + 'Last=PP' + sLineBreak +
    '[Positions]' + sLineBreak + 'PP=x' + sLineBreak + 'GC=:5' + sLineBreak + 'DA=GEN:0' + sLineBreak,
    TEncoding.UTF8);
  S := NewSettings;
  Assert.AreEqual('uk', S.GetLanguage);
  Assert.AreEqual(0, S.GetZoomStep);
  Assert.IsTrue(S.GetLeftPanelVisible);
  Assert.IsFalse(S.GetLastPosition(P));
  Assert.IsFalse(S.GetPosition('GC', P));
  Assert.IsFalse(S.GetPosition('DA', P));
end;

procedure TIniSettingsTests.ZoomStep_IsClamped;
var
  S: ISettings;
begin
  S := NewSettings;
  S.SetZoomStep(99);
  Assert.AreEqual(MaxZoomStep, S.GetZoomStep);
  S.SetZoomStep(-99);
  Assert.AreEqual(MinZoomStep, S.GetZoomStep);
end;

procedure TIniSettingsTests.Save_IntoUnwritablePath_DoesNotRaise_LogsOnce;
var
  S: ISettings;
  AFile: string;
begin
  AFile := TPath.Combine(FDir, 'not-a-folder');
  TFile.WriteAllText(AFile, 'x');
  S := TIniSettings.Create(TPath.Combine(AFile, 'settings.ini'), FLogger);
  S.SetLanguage('en');
  Assert.WillNotRaiseAny(
    procedure
    begin
      S.Save;
      S.Save;
    end);
  Assert.AreEqual(1, FLogger.Count);
  Assert.IsTrue(FLogger.Contains('Cannot save'));
end;

initialization
  TDUnitX.RegisterTestFixture(TFileLoggerTests);
  TDUnitX.RegisterTestFixture(TIniSettingsTests);

end.
