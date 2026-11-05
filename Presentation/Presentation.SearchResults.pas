unit Presentation.SearchResults;

(* What the search panel shows, without VCL (Slovo_04 A.4, C.5; B-27, B-31).

  BuildResultSections turns a TSearchReply into the rows of the result list:
  two sections, "Книги" and "Біблія", never merged by rank (B-27); the Bible
  section is grouped by translation (B-31) - SearchBible returns the groups one
  after another, so a group starts wherever ModuleId changes. Empty sections
  are left out. Each row carries its reference line and the snippet cut into
  runs, the matched ones bold (TSearchHighlight).

  Reference line (A.4): "Патріархи і пророки · Розділ 3 · 71.2" - the page
  part only when the book has a page system; Bible: "Буття 22:8". "Розділ N"
  is a localized string, so the form passes it in as ChapterLabel - this unit
  knows neither the localizer nor the form. *)

interface

uses
  System.SysUtils,
  Core.Domain,
  Core.Catalog,
  Presentation.MainViewModel;

type
  TTextRun = record
    Text: string;
    Bold: Boolean;
  end;

  TResultSectionKind = (rsBooks, rsBible);

  TResultRow = record
    RefText: string;
    Runs: TArray<TTextRun>;
    Index: Integer;                     // into Reply.Books.Items or Reply.Bible.Items
  end;

  // Books: one group with Caption = ''; Bible: one group per translation.
  TResultGroup = record
    Caption: string;
    Rows: TArray<TResultRow>;
  end;

  TResultSection = record
    Kind: TResultSectionKind;
    Groups: TArray<TResultGroup>;
  end;

  TChapterLabelFunc = reference to function(ChapterOrder: Integer): string;

// Snippet -> runs between the highlights. Highlights may come unsorted,
// overlapping or partly outside the text: they are sorted, merged and clipped.
function SplitRuns(const Snippet: string; const Highlights: TArray<TSearchHighlight>): TArray<TTextRun>;

function BookResultRef(Catalog: TLibraryCatalog; const Item: TBookSearchResult;
  const ChapterLabel: TChapterLabelFunc): string;
function BibleResultRef(Catalog: TLibraryCatalog; const Item: TBibleSearchResult): string;

function BuildResultSections(const Reply: TSearchReply; Catalog: TLibraryCatalog;
  const ChapterLabel: TChapterLabelFunc): TArray<TResultSection>;

// Number for the status line (E-12) and whether it is "the first N" (any page Truncated).
function ResultCount(const Reply: TSearchReply): Integer;
function ResultTruncated(const Reply: TSearchReply): Boolean;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Math;

function SplitRuns(const Snippet: string; const Highlights: TArray<TSearchHighlight>): TArray<TTextRun>;
var
  Spans: TArray<TSearchHighlight>;
  H: TSearchHighlight;
  Merged: TList<TSearchHighlight>;
  Last: TSearchHighlight;
  Pos, I: Integer;

  procedure Add(const Text: string; Bold: Boolean);
  var
    Run: TTextRun;
  begin
    if Text = '' then
      Exit;
    Run.Text := Text;
    Run.Bold := Bold;
    Result := Result + [Run];
  end;

begin
  Result := nil;
  // Clip to the text; offsets are 0-based UTF-16 units (B-24), Delphi strings 1-based.
  Spans := nil;
  for H in Highlights do
  begin
    Last.StartOffset := Max(H.StartOffset, 0);
    Last.Len := Min(H.StartOffset + H.Len, Length(Snippet)) - Last.StartOffset;
    if Last.Len > 0 then
      Spans := Spans + [Last];
  end;
  TArray.Sort<TSearchHighlight>(Spans, TComparer<TSearchHighlight>.Construct(
    function(const A, B: TSearchHighlight): Integer
    begin
      Result := A.StartOffset - B.StartOffset;
    end));

  Merged := TList<TSearchHighlight>.Create;
  try
    for H in Spans do
      if (Merged.Count > 0) and (H.StartOffset <= Merged.Last.StartOffset + Merged.Last.Len) then
      begin
        Last := Merged.Last;
        Last.Len := Max(Last.StartOffset + Last.Len, H.StartOffset + H.Len) - Last.StartOffset;
        Merged[Merged.Count - 1] := Last;
      end
      else
        Merged.Add(H);

    Pos := 0;
    for I := 0 to Merged.Count - 1 do
    begin
      Add(Copy(Snippet, Pos + 1, Merged[I].StartOffset - Pos), False);
      Add(Copy(Snippet, Merged[I].StartOffset + 1, Merged[I].Len), True);
      Pos := Merged[I].StartOffset + Merged[I].Len;
    end;
    Add(Copy(Snippet, Pos + 1, MaxInt), False);
  finally
    Merged.Free;
  end;
end;

function BookResultRef(Catalog: TLibraryCatalog; const Item: TBookSearchResult;
  const ChapterLabel: TChapterLabelFunc): string;
var
  M: TModule;
begin
  if Catalog.FindModule(Item.Ref.Chapter.ModuleId, M) then
    Result := M.Title
  else
    Result := string(Item.Ref.Chapter.ModuleId);
  Result := Result + ' · ' + ChapterLabel(Item.Ref.Chapter.ChapterOrder);
  if Item.PageNumber > 0 then
    Result := Result + Format(' · %d.%d', [Item.PageNumber, Item.ParagraphOnPage]);
end;

function BibleResultRef(Catalog: TLibraryCatalog; const Item: TBibleSearchResult): string;
begin
  Result := Catalog.BookTitle(Item.Ref.Chapter.Book);
  if Result = '' then
    Result := string(Item.Ref.Chapter.Book.BookCode);
  Result := Format('%s %d:%d', [Result, Item.Ref.Chapter.ChapterNumber, Item.Ref.VerseNumber]);
end;

function BuildResultSections(const Reply: TSearchReply; Catalog: TLibraryCatalog;
  const ChapterLabel: TChapterLabelFunc): TArray<TResultSection>;
var
  Section: TResultSection;
  Group: TResultGroup;
  Row: TResultRow;
  M: TModule;
  Current: TModuleId;
  I: Integer;
begin
  Result := nil;

  if Length(Reply.Books.Items) > 0 then
  begin
    Section := Default(TResultSection);
    Section.Kind := rsBooks;
    Group := Default(TResultGroup);
    for I := 0 to High(Reply.Books.Items) do
    begin
      Row.RefText := BookResultRef(Catalog, Reply.Books.Items[I], ChapterLabel);
      Row.Runs := SplitRuns(Reply.Books.Items[I].Snippet, Reply.Books.Items[I].Highlights);
      Row.Index := I;
      Group.Rows := Group.Rows + [Row];
    end;
    Section.Groups := [Group];
    Result := Result + [Section];
  end;

  if Length(Reply.Bible.Items) > 0 then
  begin
    Section := Default(TResultSection);
    Section.Kind := rsBible;
    Current := '';
    Group := Default(TResultGroup);
    for I := 0 to High(Reply.Bible.Items) do
    begin
      if (I = 0) or (Reply.Bible.Items[I].Ref.Chapter.Book.ModuleId <> Current) then
      begin
        if I > 0 then
          Section.Groups := Section.Groups + [Group];
        Current := Reply.Bible.Items[I].Ref.Chapter.Book.ModuleId;
        Group := Default(TResultGroup);
        if Catalog.FindModule(Current, M) then
          Group.Caption := M.Title
        else
          Group.Caption := string(Current);
      end;
      Row.RefText := BibleResultRef(Catalog, Reply.Bible.Items[I]);
      Row.Runs := SplitRuns(Reply.Bible.Items[I].Snippet, Reply.Bible.Items[I].Highlights);
      Row.Index := I;
      Group.Rows := Group.Rows + [Row];
    end;
    Section.Groups := Section.Groups + [Group];
    Result := Result + [Section];
  end;
end;

function ResultCount(const Reply: TSearchReply): Integer;
begin
  Result := Length(Reply.Books.Items) + Length(Reply.Bible.Items);
end;

function ResultTruncated(const Reply: TSearchReply): Boolean;
begin
  Result := Reply.Books.Truncated or Reply.Bible.Truncated;
end;

end.
