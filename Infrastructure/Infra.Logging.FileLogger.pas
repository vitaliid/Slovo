unit Infra.Logging.FileLogger;

{ ILogger over data\slovo.log (Slovo_03 A.7; C-11, C-18).

  Errors only, no levels, no rotation. Open-append-close on every call: errors
  are rare, the file can be read while the program runs, and several instances
  may write to it (C-23). Called from the UI thread only (C-21), so no lock.

  LogError NEVER raises: it is called from except blocks, and an exception
  from the logger would replace the original error. }

interface

uses
  Core.Contracts;

type
  TFileLogger = class(TInterfacedObject, ILogger)
  private
    FLogFilePath: string;
  public
    constructor Create(const ALogFilePath: string);
    procedure LogError(const Source, Msg: string);
    property LogFilePath: string read FLogFilePath;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils;

constructor TFileLogger.Create(const ALogFilePath: string);
begin
  inherited Create;
  FLogFilePath := ALogFilePath;
end;

procedure TFileLogger.LogError(const Source, Msg: string);
var
  Dir: string;
  Line: TBytes;
  Stream: TFileStream;
begin
  try
    Dir := TPath.GetDirectoryName(FLogFilePath);
    if (Dir <> '') and not TDirectory.Exists(Dir) then
      TDirectory.CreateDirectory(Dir);
    Line := TEncoding.UTF8.GetBytes(
      Format('[%s] [%s] %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), Source, Msg]) + sLineBreak);
    // UTF-8 without BOM, appended byte-exact - no preamble in the middle of the file.
    if TFile.Exists(FLogFilePath) then
      Stream := TFileStream.Create(FLogFilePath, fmOpenWrite or fmShareDenyWrite)
    else
      Stream := TFileStream.Create(FLogFilePath, fmCreate or fmShareDenyWrite);
    try
      Stream.Seek(0, soEnd);
      Stream.WriteBuffer(Line, Length(Line));
    finally
      Stream.Free;
    end;
  except
    // Deliberately swallowed (C-18): losing a log line is unfortunate,
    // replacing the application's own error is not acceptable.
  end;
end;

end.
