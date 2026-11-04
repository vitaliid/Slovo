unit Core.Events;

{ TEvent<T> - a minimal multicast event (A-03), so Core needs no Spring4D.

  A CLASS, not a record: the ViewModel exposes it as
    property OnErrorOccurred: TEvent<TResultError> read FOnErrorOccurred;
  and a record property would hand out a copy, on which Add() would silently
  vanish. The owner (the ViewModel) creates and frees the instances.

  Fire runs on the caller's thread. In the MVP everything is on the UI thread
  (C-21); when background search returns, the ViewModel marshals Fire with
  TThread.Queue (A-04). }

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TEvent<T> = class
  private
    FHandlers: TList<TProc<T>>;
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const Handler: TProc<T>);
    // Removes the same method reference that was added (identity, not equality).
    procedure Remove(const Handler: TProc<T>);
    procedure Clear;
    // Iterates over a snapshot: a handler may add or remove handlers safely.
    procedure Fire(const Value: T);
    property Count: Integer read GetCount;
  end;

implementation

constructor TEvent<T>.Create;
begin
  inherited Create;
  FHandlers := TList<TProc<T>>.Create;
end;

destructor TEvent<T>.Destroy;
begin
  FHandlers.Free;
  inherited;
end;

procedure TEvent<T>.Add(const Handler: TProc<T>);
begin
  if Assigned(Handler) then
    FHandlers.Add(Handler);
end;

procedure TEvent<T>.Remove(const Handler: TProc<T>);
var
  I: Integer;
  Item: TProc<T>;
begin
  // A method reference is an interface: compare the interface pointers.
  for I := FHandlers.Count - 1 downto 0 do
  begin
    Item := FHandlers[I];
    if PPointer(@Item)^ = PPointer(@Handler)^ then
    begin
      FHandlers.Delete(I);
      Exit;
    end;
  end;
end;

procedure TEvent<T>.Clear;
begin
  FHandlers.Clear;
end;

procedure TEvent<T>.Fire(const Value: T);
var
  Handler: TProc<T>;
begin
  for Handler in FHandlers.ToArray do
    Handler(Value);
end;

function TEvent<T>.GetCount: Integer;
begin
  Result := FHandlers.Count;
end;

end.
