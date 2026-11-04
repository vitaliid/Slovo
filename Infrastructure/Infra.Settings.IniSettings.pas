unit Infra.Settings.IniSettings;

{ ISettings over data\settings.ini (Slovo_04 C.2; E-06, E-07).

  Read once in the constructor (TMemIniFile, UTF-8), changed in memory by Set*,
  written only by Save - called on chapter change and on exit (R4-27).
  A missing file means defaults. Values are trimmed. Save never raises: a
  read-only folder is logged once (D-04).

  [Positions]: the key is the ModuleId; a colon in the value means a Bible
  position "BookCode:ChapterNumber", otherwise it is a book ChapterOrder (R4-28). }

interface

uses
  System.Types,
  System.IniFiles,
  Core.Domain,
  Core.Contracts;

const
  MinZoomStep = -4;
  MaxZoomStep = 6;
  DefaultLanguage = 'uk';

type
  TIniSettings = class(TInterfacedObject, ISettings)
  private
    FIni: TMemIniFile;
    FLogger: ILogger;
    FSaveFailureLogged: Boolean;
    function ReadText(const Section, Key, Default: string): string;
    function ReadInt(const Section, Key: string; Default: Integer): Integer;
    function ReadBool(const Section, Key: string; Default: Boolean): Boolean;
    procedure WriteBool(const Section, Key: string; Value: Boolean);
  public
    constructor Create(const AFileName: string; const ALogger: ILogger);
    destructor Destroy; override;

    function GetLanguage: string;
    procedure SetLanguage(const Value: string);
    function GetZoomStep: Integer;
    procedure SetZoomStep(Value: Integer);
    function GetLeftPanelVisible: Boolean;
    procedure SetLeftPanelVisible(Value: Boolean);
    function GetRightPanelVisible: Boolean;
    procedure SetRightPanelVisible(Value: Boolean);
    function GetWindowBounds(out Bounds: TRect; out Maximized: Boolean): Boolean;
    procedure SetWindowBounds(const Bounds: TRect; Maximized: Boolean);
    function GetLastPosition(out Position: TReadingPosition): Boolean;
    procedure SetLastPosition(const Position: TReadingPosition);
    function GetPosition(const ModuleId: TModuleId; out Position: TReadingPosition): Boolean;
    procedure SetPosition(const Position: TReadingPosition);
    function GetCheckedModules: TArray<TModuleId>;
    procedure SetCheckedModules(const Value: TArray<TModuleId>);
    function GetSearchWholeLibrary: Boolean;
    procedure SetSearchWholeLibrary(Value: Boolean);
    function GetExactPhrase: Boolean;
    procedure SetExactPhrase(Value: Boolean);
    function GetWordForms: Boolean;
    procedure SetWordForms(Value: Boolean);
    procedure Save;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math;

const
  SUi = 'Ui';
  SWindow = 'Window';
  SReading = 'Reading';
  SPositions = 'Positions';
  SSearch = 'Search';

{ TIniSettings }

constructor TIniSettings.Create(const AFileName: string; const ALogger: ILogger);
begin
  inherited Create;
  FLogger := ALogger;
  try
    FIni := TMemIniFile.Create(AFileName, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      // Unreadable file: start from defaults; Save will try to write it again.
      FLogger.LogError('Settings', Format('Cannot read %s: %s: %s', [AFileName, E.ClassName, E.Message]));
      FIni := TMemIniFile.Create('', TEncoding.UTF8);
      FIni.Rename(AFileName, False);
    end;
  end;
end;

destructor TIniSettings.Destroy;
begin
  FIni.Free;
  inherited;
end;

function TIniSettings.ReadText(const Section, Key, Default: string): string;
begin
  Result := FIni.ReadString(Section, Key, Default).Trim;
end;

function TIniSettings.ReadInt(const Section, Key: string; Default: Integer): Integer;
begin
  Result := StrToIntDef(ReadText(Section, Key, ''), Default);
end;

function TIniSettings.ReadBool(const Section, Key: string; Default: Boolean): Boolean;
var
  S: string;
begin
  S := ReadText(Section, Key, '');
  if S = '1' then
    Result := True
  else if S = '0' then
    Result := False
  else
    Result := Default;
end;

procedure TIniSettings.WriteBool(const Section, Key: string; Value: Boolean);
begin
  FIni.WriteString(Section, Key, IfThen(Value, '1', '0'));
end;

// ---- [Ui]

function TIniSettings.GetLanguage: string;
begin
  Result := ReadText(SUi, 'Language', DefaultLanguage).ToLower;
  if (Result <> 'uk') and (Result <> 'ru') and (Result <> 'en') then
    Result := DefaultLanguage;
end;

procedure TIniSettings.SetLanguage(const Value: string);
begin
  FIni.WriteString(SUi, 'Language', Value);
end;

function TIniSettings.GetZoomStep: Integer;
begin
  Result := EnsureRange(ReadInt(SUi, 'ZoomStep', 0), MinZoomStep, MaxZoomStep);
end;

procedure TIniSettings.SetZoomStep(Value: Integer);
begin
  FIni.WriteInteger(SUi, 'ZoomStep', EnsureRange(Value, MinZoomStep, MaxZoomStep));
end;

function TIniSettings.GetLeftPanelVisible: Boolean;
begin
  Result := ReadBool(SUi, 'LeftPanel', True);
end;

procedure TIniSettings.SetLeftPanelVisible(Value: Boolean);
begin
  WriteBool(SUi, 'LeftPanel', Value);
end;

function TIniSettings.GetRightPanelVisible: Boolean;
begin
  Result := ReadBool(SUi, 'RightPanel', True);
end;

procedure TIniSettings.SetRightPanelVisible(Value: Boolean);
begin
  WriteBool(SUi, 'RightPanel', Value);
end;

// ---- [Window]

function TIniSettings.GetWindowBounds(out Bounds: TRect; out Maximized: Boolean): Boolean;
var
  Width, Height: Integer;
begin
  Bounds := TRect.Empty;
  Maximized := ReadBool(SWindow, 'Maximized', False);
  Width := ReadInt(SWindow, 'Width', 0);
  Height := ReadInt(SWindow, 'Height', 0);
  Result := (Width > 0) and (Height > 0) and FIni.ValueExists(SWindow, 'Left') and
    FIni.ValueExists(SWindow, 'Top');
  if Result then
    Bounds := TRect.Create(TPoint.Create(ReadInt(SWindow, 'Left', 0), ReadInt(SWindow, 'Top', 0)),
      Width, Height);
end;

procedure TIniSettings.SetWindowBounds(const Bounds: TRect; Maximized: Boolean);
begin
  FIni.WriteInteger(SWindow, 'Left', Bounds.Left);
  FIni.WriteInteger(SWindow, 'Top', Bounds.Top);
  FIni.WriteInteger(SWindow, 'Width', Bounds.Width);
  FIni.WriteInteger(SWindow, 'Height', Bounds.Height);
  WriteBool(SWindow, 'Maximized', Maximized);
end;

// ---- [Reading] + [Positions]

function TIniSettings.GetLastPosition(out Position: TReadingPosition): Boolean;
var
  ModuleId: string;
begin
  Position := Default(TReadingPosition);
  ModuleId := ReadText(SReading, 'Last', '');
  Result := (ModuleId <> '') and GetPosition(ModuleId, Position);
end;

procedure TIniSettings.SetLastPosition(const Position: TReadingPosition);
begin
  FIni.WriteString(SReading, 'Last', Position.ModuleId);
  SetPosition(Position);
end;

function TIniSettings.GetPosition(const ModuleId: TModuleId; out Position: TReadingPosition): Boolean;
var
  Value: string;
  Colon, Number: Integer;
begin
  Position := Default(TReadingPosition);
  Value := ReadText(SPositions, ModuleId, '');
  if Value = '' then
    Exit(False);

  Colon := Value.IndexOf(':');
  if Colon >= 0 then
  begin
    // Bible: BookCode:ChapterNumber
    Number := StrToIntDef(Value.Substring(Colon + 1).Trim, 0);
    Result := (Colon > 0) and (Number > 0);
    if Result then
    begin
      Position.Kind := ckBibleTranslation;
      Position.BibleChapter.Book.ModuleId := ModuleId;
      Position.BibleChapter.Book.BookCode := Value.Substring(0, Colon).Trim;
      Position.BibleChapter.ChapterNumber := Number;
    end;
  end
  else
  begin
    // Book: ChapterOrder
    Number := StrToIntDef(Value, 0);
    Result := Number > 0;
    if Result then
    begin
      Position.Kind := ckBook;
      Position.Chapter.ModuleId := ModuleId;
      Position.Chapter.ChapterOrder := Number;
    end;
  end;
  if not Result then
    Position := Default(TReadingPosition);
end;

procedure TIniSettings.SetPosition(const Position: TReadingPosition);
begin
  if Position.ModuleId = '' then
    Exit;
  if Position.Kind = ckBibleTranslation then
    FIni.WriteString(SPositions, Position.ModuleId,
      Format('%s:%d', [string(Position.BibleChapter.Book.BookCode), Position.BibleChapter.ChapterNumber]))
  else
    FIni.WriteInteger(SPositions, Position.ModuleId, Position.Chapter.ChapterOrder);
end;

// ---- [Search]

function TIniSettings.GetCheckedModules: TArray<TModuleId>;
var
  Part: string;
begin
  Result := nil;
  for Part in ReadText(SSearch, 'Checked', '').Split([','], TStringSplitOptions.ExcludeEmpty) do
    if Part.Trim <> '' then
      Result := Result + [TModuleId(Part.Trim)];
end;

procedure TIniSettings.SetCheckedModules(const Value: TArray<TModuleId>);
var
  Parts: TArray<string>;
  I: Integer;
begin
  SetLength(Parts, Length(Value));
  for I := 0 to High(Value) do
    Parts[I] := Value[I];
  FIni.WriteString(SSearch, 'Checked', string.Join(',', Parts));
end;

function TIniSettings.GetSearchWholeLibrary: Boolean;
begin
  Result := ReadBool(SSearch, 'WholeLibrary', True);
end;

procedure TIniSettings.SetSearchWholeLibrary(Value: Boolean);
begin
  WriteBool(SSearch, 'WholeLibrary', Value);
end;

function TIniSettings.GetExactPhrase: Boolean;
begin
  Result := ReadBool(SSearch, 'ExactPhrase', False);
end;

procedure TIniSettings.SetExactPhrase(Value: Boolean);
begin
  WriteBool(SSearch, 'ExactPhrase', Value);
end;

function TIniSettings.GetWordForms: Boolean;
begin
  Result := ReadBool(SSearch, 'WordForms', False);
end;

procedure TIniSettings.SetWordForms(Value: Boolean);
begin
  WriteBool(SSearch, 'WordForms', Value);
end;

// ---- Save

procedure TIniSettings.Save;
begin
  try
    FIni.UpdateFile;
  except
    on E: Exception do
      if not FSaveFailureLogged then
      begin
        FSaveFailureLogged := True;
        FLogger.LogError('Settings', Format('Cannot save %s: %s: %s',
          [FIni.FileName, E.ClassName, E.Message]));
      end;
  end;
end;

end.
