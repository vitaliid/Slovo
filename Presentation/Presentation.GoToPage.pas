unit Presentation.GoToPage;

{ The text of the "go to" field (Slovo_04 A.7, E-24) - what was typed, before
  anything is looked up. No VCL, no database: the ViewModel decides what the
  numbers mean (a page of a book, a chapter and a verse of the Bible).

  Accepted: a number ('71'), a number with a separator still without its
  second number ('3:' - the reader is typing), two numbers ('3:4', '3.4', '3,4',
  '3 4'; spaces around the separator do not matter). A letter anywhere is
  another book ('ПП 71') - the field does not take it (variant A of the mockup).
  Everything else, and a number longer than 5 digits, is giBad.
  ('goto' is a reserved word, hence the unit's name.) }

interface

type
  TGoToInputKind = (giEmpty, giNumber, giPair, giLetters, giBad);

  TGoToInput = record
    Kind: TGoToInputKind;
    First: Integer;                   // giNumber, giPair
    Second: Integer;                  // giPair
  end;

function ParseGoTo(const Text: string): TGoToInput;

implementation

uses
  System.SysUtils,
  System.Character;

const
  MaxDigits = 5;

function IsNumber(const S: string): Boolean;
var
  C: Char;
begin
  Result := (S <> '') and (Length(S) <= MaxDigits);
  for C in S do
    if not CharInSet(C, ['0'..'9']) then
      Exit(False);
end;

function ParseGoTo(const Text: string): TGoToInput;
var
  S, Head, Tail: string;
  C: Char;
  P: Integer;
begin
  Result := Default(TGoToInput);
  S := Trim(Text);
  if S = '' then
    Exit;                             // giEmpty
  for C in S do
    if C.IsLetter then
    begin
      Result.Kind := giLetters;
      Exit;
    end;

  Result.Kind := giBad;
  // One separator ':' between the numbers; spaces around it are dropped, a
  // space alone between two numbers is the separator itself.
  S := StringReplace(S, '.', ':', [rfReplaceAll]);
  S := StringReplace(S, ',', ':', [rfReplaceAll]);
  for C in S do
    if not CharInSet(C, ['0'..'9', ':', ' ']) then
      Exit;
  while Pos('  ', S) > 0 do
    S := StringReplace(S, '  ', ' ', [rfReplaceAll]);
  S := StringReplace(S, ' :', ':', [rfReplaceAll]);
  S := StringReplace(S, ': ', ':', [rfReplaceAll]);
  S := StringReplace(S, ' ', ':', [rfReplaceAll]);

  P := Pos(':', S);
  if P = 0 then
  begin
    Head := S;
    Tail := '';
  end
  else
  begin
    Head := Copy(S, 1, P - 1);
    Tail := Copy(S, P + 1, MaxInt);
  end;
  if not IsNumber(Head) or (Pos(':', Tail) > 0) then
    Exit;
  Result.First := StrToInt(Head);
  if Tail = '' then
    Result.Kind := giNumber
  else if IsNumber(Tail) then
  begin
    Result.Kind := giPair;
    Result.Second := StrToInt(Tail);
  end;
end;

end.
