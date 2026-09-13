unit Presentation.Strings;

{
  Every piece of user-facing interface text, loaded at run time from
  lang\<code>.lang next to the executable. One file per language, one
  "key = value" pair per line.

  Why files and not a table compiled into the EXE: adding or correcting a
  translation should not require Delphi, and adding a language should not
  require a rebuild. The program already ships a modules folder, so a second
  data folder next to it costs nothing in deployment.

  A key with no value in the current file is NOT an error that stops anything:
  the key itself is displayed and the miss is logged once. That is deliberate -
  a half-translated interface stays usable, and the log says exactly what to
  add.

  The forms themselves stay neutral: the captions in the .dfm files are English
  placeholders that exist only so the form designer stays readable, and they are
  overwritten from this unit whenever the language changes. Adding a caption to
  a form therefore means adding a key to the three .lang files and a line to
  TMainForm.ApplyStrings - never a translated literal in a .dfm.

  Technical text does NOT belong here. Error messages, diagnostics and exception
  text are English, are not translated, and live as resourcestrings next to the
  code that produces them (Infrastructure.SQLite3.Api,
  Infrastructure.SQLite3.Database, Slovo.dpr).

  If the interface text ever turns out to be small enough to keep inside the
  EXE after all, only LoadLanguageFile below changes - a TResourceStream
  instead of a file. Nothing outside this unit notices.
}

interface

type
  { Where to report missing keys and unreadable files. nil = nowhere.
    Slovo.dpr passes OutputDebugString for now; this becomes ILogger once
    there is one. }
  TLocalizerLogProc = reference to procedure(const AMessage: string);
  { Note: messages below use [brackets] rather than "quotes" - the IDE's Event
    Log truncates an OutputDebugString message at the first double quote. }

const
  { The languages offered in View -> Language. The index of a code is the Tag
    of its menu item, which is the only place the order matters. }
  UILanguageCodes: array[0..2] of string = ('uk', 'ru', 'en');
  DefaultUILanguage = 'uk';
  LanguageFileExt = '.lang';

{ Reads AFolder\<ALanguageCode>.lang. Called once from the composition root;
  a missing folder or file is logged, never fatal. }
procedure InitLocalization(const AFolder: string;
  const ALanguageCode: string = DefaultUILanguage;
  const ALogProc: TLocalizerLogProc = nil);

function CurrentLanguage: string;

{ Re-reads the file for ACode. The caller refreshes its captions afterwards. }
procedure SetCurrentLanguage(const ACode: string);

{ The interface text for AKey in the language currently selected,
  or AKey itself if the current file has no such key. }
function UI(const AKey: string): string;

{ UI + Format. A placeholder broken by a translator is logged and the
  unformatted text is returned, rather than an exception reaching a window. }
function UIFmt(const AKey: string; const AArgs: array of const): string;

{ The name of a language in that language - never translated. }
function LanguageName(const ACode: string): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections;

const
  { Endonyms stay in code on purpose: they are the same whatever the interface
    language is, so they are not translations and do not belong in a file that
    translators edit. Same order as UILanguageCodes. }
  UILanguageNames: array[0..2] of string = (
    'Українська',
    'Русский',
    'English'
  );

var
  GFolder: string;
  GLanguage: string;
  GLog: TLocalizerLogProc;
  GStrings: TDictionary<string, string>;
  GMissing: TDictionary<string, Byte>;

procedure Log(const AMessage: string);
begin
  if Assigned(GLog) then
    GLog(AMessage);
end;

{ Only what a translator plausibly needs on a single line. An unknown escape is
  left alone - it is far more likely to be a backslash in the text than a typo. }
function Unescape(const AValue: string): string;
var
  LIndex: Integer;
  LBuilder: TStringBuilder;
begin
  if AValue.IndexOf('\') < 0 then
    Exit(AValue);

  LBuilder := TStringBuilder.Create(Length(AValue));
  try
    LIndex := 1;
    while LIndex <= Length(AValue) do
    begin
      if (AValue[LIndex] = '\') and (LIndex < Length(AValue)) then
      begin
        case AValue[LIndex + 1] of
          'n': LBuilder.Append(sLineBreak);
          't': LBuilder.Append(#9);
          '\': LBuilder.Append('\');
        else
          LBuilder.Append(AValue[LIndex]).Append(AValue[LIndex + 1]);
        end;
        Inc(LIndex, 2);
      end
      else
      begin
        LBuilder.Append(AValue[LIndex]);
        Inc(LIndex);
      end;
    end;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

procedure LoadLanguageFile(const AFileName: string);
var
  LLines: TStringList;
  LLine: string;
  LSeparator: Integer;
begin
  LLines := TStringList.Create;
  try
    try
      { TEncoding.UTF8 handles the file with or without a BOM. }
      LLines.LoadFromFile(AFileName, TEncoding.UTF8);
    except
      on E: Exception do
      begin
        Log(Format('Localization: cannot read [%s]: %s', [AFileName, E.Message]));
        Exit;
      end;
    end;

    for LLine in LLines do
    begin
      if (LLine.Trim = '') or LLine.Trim.StartsWith('#') then
        Continue;
      { Split at the FIRST '=' so a value may contain one. }
      LSeparator := LLine.IndexOf('=');
      if LSeparator <= 0 then
        Continue;
      GStrings.AddOrSetValue(
        LLine.Substring(0, LSeparator).Trim,
        Unescape(LLine.Substring(LSeparator + 1).Trim));
    end;
  finally
    LLines.Free;
  end;
end;

procedure SetCurrentLanguage(const ACode: string);
var
  LFileName: string;
begin
  GLanguage := LowerCase(ACode.Trim);
  GStrings.Clear;
  GMissing.Clear;   { a new language means a new set of misses }

  if (GFolder = '') or (GLanguage = '') then
    Exit;

  LFileName := TPath.Combine(GFolder, GLanguage + LanguageFileExt);
  if TFile.Exists(LFileName) then
  begin
    LoadLanguageFile(LFileName);
    Log(Format('Localization: [%s], %d keys', [GLanguage, GStrings.Count]));
  end
  else
    { No file: the interface shows keys. Ugly, but it runs and it says why. }
    Log(Format('Localization: file not found: [%s]', [LFileName]));
end;

procedure InitLocalization(const AFolder: string; const ALanguageCode: string;
  const ALogProc: TLocalizerLogProc);
begin
  GFolder := AFolder;
  GLog := ALogProc;
  SetCurrentLanguage(ALanguageCode);
end;

function CurrentLanguage: string;
begin
  Result := GLanguage;
end;

function UI(const AKey: string): string;
begin
  if GStrings.TryGetValue(AKey, Result) then
    Exit;

  { Logged once per key: the first miss inside OnPaint or a list renderer would
    otherwise write megabytes a second. }
  if not GMissing.ContainsKey(AKey) then
  begin
    GMissing.Add(AKey, 0);
    Log(Format('Localization: missing key [%s] (%s)', [AKey, GLanguage]));
  end;

  Result := AKey;
end;

function UIFmt(const AKey: string; const AArgs: array of const): string;
var
  LPattern: string;
begin
  LPattern := UI(AKey);
  try
    Result := Format(LPattern, AArgs);
  except
    on E: Exception do
    begin
      Log(Format('Localization: bad format pattern for key [%s]: %s',
        [AKey, E.Message]));
      Result := LPattern;
    end;
  end;
end;

function LanguageName(const ACode: string): string;
var
  LIndex: Integer;
begin
  for LIndex := Low(UILanguageCodes) to High(UILanguageCodes) do
    if UILanguageCodes[LIndex] = ACode then
      Exit(UILanguageNames[LIndex]);
  Result := ACode;
end;

initialization
  GStrings := TDictionary<string, string>.Create;
  GMissing := TDictionary<string, Byte>.Create;
  GLanguage := DefaultUILanguage;

finalization
  GMissing.Free;
  GStrings.Free;

end.
