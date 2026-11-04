unit Presentation.Localization;

{ Interface text from lang\<code>.lang next to the EXE (Slovo_04 C.3; E-05, R3-25).

  ILocalizer + TFileLocalizer + the global accessor L(). Zero dependencies on
  other project units: problems are reported through a plain log procedure,
  not ILogger. Localization is Presentation-only - Core returns TResultError
  codes and never text.

  File format: UTF-8 (BOM optional), "key = value" split at the FIRST '=',
  '#' starts a comment, escapes \n \t \\. Placeholders are Format patterns
  (%d, %s, %0:s) - the translator decides the word order (R4-40).

  A missing key shows the key itself and is logged once per key, in Release as
  well; a missing language FILE shows keys everywhere and is logged once.
  Technical text (errors, diagnostics, exceptions) is English and stays in code. }

interface

uses
  System.SysUtils,
  System.Generics.Collections;

const
  DefaultUILanguage = 'uk';
  LanguageFileExt = '.lang';
  // The language menu has three fixed items (R3-25).
  UILanguageCodes: array[0..2] of string = ('uk', 'ru', 'en');
  // Endonyms: the same whatever the interface language is, so not in the files.
  UILanguageNames: array[0..2] of string = ('Українська', 'Русский', 'English');

type
  TLocalizerLogProc = reference to procedure(const AMessage: string);

  ILocalizer = interface
    ['{6B0F3C2E-8A41-4D7B-9E15-3C8A2F6D4B90}']
    function GetLanguage: string;
    procedure SetLanguage(const ACode: string);
    function Text(const AKey: string): string;
    function TextFmt(const AKey: string; const AArgs: array of const): string;
    property Language: string read GetLanguage;
  end;

  TFileLocalizer = class(TInterfacedObject, ILocalizer)
  private
    FFolder: string;
    FLanguage: string;
    FLog: TLocalizerLogProc;
    FStrings: TDictionary<string, string>;
    FMissing: TDictionary<string, Byte>;
    procedure Log(const AMessage: string);
    procedure LoadFile(const AFileName: string);
  public
    constructor Create(const AFolder, ALanguage: string; const ALog: TLocalizerLogProc);
    destructor Destroy; override;
    function GetLanguage: string;
    procedure SetLanguage(const ACode: string);
    function Text(const AKey: string): string;
    function TextFmt(const AKey: string; const AArgs: array of const): string;
  end;

// Creates the global localizer. Call once, before the first text (composition root).
procedure InitLocalization(const AFolder, ALanguageCode: string;
  const ALogProc: TLocalizerLogProc = nil);
function Localizer: ILocalizer;

// The accessor every form uses: L('menu.file'), L('search.hits', [172]).
function L(const AKey: string): string; overload;
function L(const AKey: string; const AArgs: array of const): string; overload;

function LanguageName(const ACode: string): string;

implementation

uses
  System.Classes,
  System.IOUtils;

var
  GLocalizer: ILocalizer;

// Only what a translator plausibly needs on one line; an unknown escape is kept.
function Unescape(const AValue: string): string;
var
  I: Integer;
  SB: TStringBuilder;
begin
  if AValue.IndexOf('\') < 0 then
    Exit(AValue);
  SB := TStringBuilder.Create(Length(AValue));
  try
    I := 1;
    while I <= Length(AValue) do
    begin
      if (AValue[I] = '\') and (I < Length(AValue)) then
      begin
        case AValue[I + 1] of
          'n': SB.Append(sLineBreak);
          't': SB.Append(#9);
          '\': SB.Append('\');
        else
          SB.Append(AValue[I]).Append(AValue[I + 1]);
        end;
        Inc(I, 2);
      end
      else
      begin
        SB.Append(AValue[I]);
        Inc(I);
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TFileLocalizer }

constructor TFileLocalizer.Create(const AFolder, ALanguage: string; const ALog: TLocalizerLogProc);
begin
  inherited Create;
  FFolder := AFolder;
  FLog := ALog;
  FStrings := TDictionary<string, string>.Create;
  FMissing := TDictionary<string, Byte>.Create;
  SetLanguage(ALanguage);
end;

destructor TFileLocalizer.Destroy;
begin
  FMissing.Free;
  FStrings.Free;
  inherited;
end;

procedure TFileLocalizer.Log(const AMessage: string);
begin
  if Assigned(FLog) then
    FLog(AMessage);
end;

procedure TFileLocalizer.LoadFile(const AFileName: string);
var
  Lines: TStringList;
  Line: string;
  Separator: Integer;
begin
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(AFileName, TEncoding.UTF8);   // with or without BOM
    except
      on E: Exception do
      begin
        Log(Format('Cannot read %s: %s', [AFileName, E.Message]));
        Exit;
      end;
    end;
    for Line in Lines do
    begin
      if (Line.Trim = '') or Line.Trim.StartsWith('#') then
        Continue;
      Separator := Line.IndexOf('=');
      if Separator <= 0 then
        Continue;
      FStrings.AddOrSetValue(Line.Substring(0, Separator).Trim,
        Unescape(Line.Substring(Separator + 1).Trim));
    end;
  finally
    Lines.Free;
  end;
end;

function TFileLocalizer.GetLanguage: string;
begin
  Result := FLanguage;
end;

procedure TFileLocalizer.SetLanguage(const ACode: string);
var
  FileName: string;
begin
  FLanguage := ACode.Trim.ToLower;
  FStrings.Clear;
  FMissing.Clear;                    // a new language - a new set of misses
  if (FFolder = '') or (FLanguage = '') then
    Exit;
  FileName := TPath.Combine(FFolder, FLanguage + LanguageFileExt);
  if TFile.Exists(FileName) then
    LoadFile(FileName)
  else
    Log('Language file not found: ' + FileName);
end;

function TFileLocalizer.Text(const AKey: string): string;
begin
  if FStrings.TryGetValue(AKey, Result) then
    Exit;
  // Once per key: a miss inside OnPaint would otherwise flood the log.
  if not FMissing.ContainsKey(AKey) then
  begin
    FMissing.Add(AKey, 0);
    Log(Format('Missing key %s (%s)', [AKey, FLanguage]));
  end;
  Result := AKey;
end;

function TFileLocalizer.TextFmt(const AKey: string; const AArgs: array of const): string;
var
  Pattern: string;
begin
  Pattern := Text(AKey);
  try
    Result := Format(Pattern, AArgs);
  except
    on E: Exception do
    begin
      Log(Format('Bad format pattern for key %s: %s', [AKey, E.Message]));
      Result := Pattern;
    end;
  end;
end;

{ globals }

procedure InitLocalization(const AFolder, ALanguageCode: string; const ALogProc: TLocalizerLogProc);
begin
  GLocalizer := TFileLocalizer.Create(AFolder, ALanguageCode, ALogProc);
end;

function Localizer: ILocalizer;
begin
  Result := GLocalizer;
end;

function L(const AKey: string): string;
begin
  if GLocalizer = nil then
    Exit(AKey);
  Result := GLocalizer.Text(AKey);
end;

function L(const AKey: string; const AArgs: array of const): string;
begin
  if GLocalizer = nil then
    Exit(AKey);
  Result := GLocalizer.TextFmt(AKey, AArgs);
end;

function LanguageName(const ACode: string): string;
var
  I: Integer;
begin
  for I := Low(UILanguageCodes) to High(UILanguageCodes) do
    if UILanguageCodes[I] = ACode then
      Exit(UILanguageNames[I]);
  Result := ACode;
end;

initialization

finalization
  GLocalizer := nil;

end.
