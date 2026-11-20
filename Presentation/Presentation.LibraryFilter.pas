unit Presentation.LibraryFilter;

{ The library tree filter (Slovo_04 A.3, E-25): which rows of the tree stay and
  where each caption matched, from the same TLibraryNode array the tree is
  built of. No VCL - the tree applies the result (Shell.LibraryTree.SetFilter).

  Matching: case does not matter; ё and є are е, і and ї are и, ґ is г (one
  book comes in Ukrainian and in Russian); apostrophes are skipped. The text
  is split into words and every word must occur in the caption, anywhere
  ("вел бор" - "Велика боротьба"). The highlight is the first word: where it
  starts a word of the caption, else where it occurs first.

  What stays: a book or a translation whose caption matched, with its parents;
  a category or a series whose caption matched - with all its books. Chapters
  and Bible books have no row and never stay. The filter has nothing to do
  with the check boxes (Vitalii, 2026-11-20). }

interface

uses
  Presentation.MainViewModel;

type
  TFilterMatch = record
    Start: Integer;                     // 0-based, UTF-16 code units of the caption
    Length: Integer;                    // 0 - nothing to highlight
  end;

  TLibraryFilterResult = record
    Active: Boolean;                    // the text had words
    Visible: TArray<Boolean>;           // per node of the array
    Matches: TArray<TFilterMatch>;      // per node: its own caption's match
    Shown: Integer;                     // books and translations left visible
    Total: Integer;                     // books and translations in all
    First: Integer;                     // the first visible book or translation; -1 - none
  end;

// The words of the field's text, folded as the captions are.
function FilterWords(const Text: string): TArray<string>;
// True when every word occurs in Caption; Match - where the first one is.
function MatchCaption(const Caption: string; const Words: TArray<string>;
  out Match: TFilterMatch): Boolean;
// Captions[I] - the text of node I's row (a category - from lang\, the rest - Caption).
function FilterLibrary(const Nodes: TArray<TLibraryNode>; const Captions: TArray<string>;
  const Text: string): TLibraryFilterResult;

implementation

uses
  System.SysUtils,
  System.Character;

function IsApostrophe(C: Char): Boolean;
begin
  Result := (C = '''') or (C = '`') or (C = #$2019) or (C = #$02BC);
end;

function Fold(C: Char): Char;
begin
  Result := C.ToLower;
  case Result of
    #$0451, #$0454: Result := #$0435;   // ё, є - е
    #$0456, #$0457: Result := #$0438;   // і, ї - и
    #$0491:         Result := #$0433;   // ґ - г
  end;
end;

// The folded text and, for each of its characters, where it stood in S (0-based).
procedure Normalize(const S: string; out Text: string; out Map: TArray<Integer>);
var
  I, N: Integer;
begin
  SetLength(Text, Length(S));
  SetLength(Map, Length(S));
  N := 0;
  for I := 1 to Length(S) do
    if not IsApostrophe(S[I]) then
    begin
      Inc(N);
      Text[N] := Fold(S[I]);
      Map[N - 1] := I - 1;
    end;
  SetLength(Text, N);
  SetLength(Map, N);
end;

function FilterWords(const Text: string): TArray<string>;
var
  Folded: string;
  Map: TArray<Integer>;
begin
  Normalize(Text, Folded, Map);
  Result := Folded.Split([' ', #9, #$00A0], TStringSplitOptions.ExcludeEmpty);
end;

// 1-based; at the start of a word if it is there, else the first place; 0 - nowhere.
function FindWord(const Text, Word: string): Integer;
var
  At: Integer;
begin
  Result := 0;
  At := Pos(Word, Text);
  while At > 0 do
  begin
    if Result = 0 then
      Result := At;
    if (At = 1) or not Text[At - 1].IsLetterOrDigit then
      Exit(At);
    At := Pos(Word, Text, At + 1);
  end;
end;

function MatchCaption(const Caption: string; const Words: TArray<string>;
  out Match: TFilterMatch): Boolean;
var
  Text: string;
  Map: TArray<Integer>;
  I, At, Start: Integer;
begin
  Match := Default(TFilterMatch);
  if Length(Words) = 0 then
    Exit(False);
  Normalize(Caption, Text, Map);
  Start := 0;
  for I := 0 to High(Words) do
  begin
    At := FindWord(Text, Words[I]);
    if At = 0 then
      Exit(False);
    if I = 0 then
      Start := At;
  end;
  Match.Start := Map[Start - 1];
  Match.Length := Map[Start - 1 + Length(Words[0]) - 1] + 1 - Match.Start;
  Result := True;
end;

function HasRow(Kind: TLibraryNodeKind): Boolean;
begin
  Result := Kind in [lnCategory, lnSeries, lnModule, lnBibleTranslation];
end;

function FilterLibrary(const Nodes: TArray<TLibraryNode>; const Captions: TArray<string>;
  const Text: string): TLibraryFilterResult;
var
  Words: TArray<string>;
  Hit, FromParent: TArray<Boolean>;
  I, P: Integer;
begin
  Result := Default(TLibraryFilterResult);
  SetLength(Result.Visible, Length(Nodes));
  SetLength(Result.Matches, Length(Nodes));
  SetLength(Hit, Length(Nodes));
  SetLength(FromParent, Length(Nodes));
  Words := FilterWords(Text);
  Result.Active := Length(Words) > 0;
  Result.First := -1;

  // A parent comes before its children in the array (B-29): its own match is
  // known when a child asks whether one of its parents matched.
  for I := 0 to High(Nodes) do
  begin
    if not HasRow(Nodes[I].Kind) then
      Continue;
    P := Nodes[I].Parent;
    if P >= 0 then
      FromParent[I] := Hit[P] or FromParent[P];
    if Result.Active and (I <= High(Captions)) then
      Hit[I] := MatchCaption(Captions[I], Words, Result.Matches[I]);
    Result.Visible[I] := not Result.Active or Hit[I] or FromParent[I];
  end;
  // A row that stays keeps its parents.
  for I := High(Nodes) downto 0 do
    if Result.Visible[I] and (Nodes[I].Parent >= 0) then
      Result.Visible[Nodes[I].Parent] := True;

  for I := 0 to High(Nodes) do
    if Nodes[I].Kind in [lnModule, lnBibleTranslation] then
    begin
      Inc(Result.Total);
      if Result.Visible[I] then
      begin
        Inc(Result.Shown);
        if Result.First < 0 then
          Result.First := I;
      end;
    end;
end;

end.
