unit Shell.LibraryTree;

(* The library tree of the left panel (Slovo_04 A.3, C.5, E-02).

  A thin owner of one TVirtualStringTree. The tree is built ONCE from the flat
  TLibraryNode array of OnLibraryChanged (B-29): nodes are added in array order,
  the parent of each is an already added node. A VST node holds only the index
  into that array (NodeDataSize = SizeOf(Integer)) - no strings in the tree, so
  a language change is an Invalidate, never a rebuild (R4-12).

  The tree ends at the book (Vitalii, 2026-11-09): category - series - book,
  the Bible - at the translation. Chapters and Bible books stay in the array
  (the toc and the shelf read them) but get no row here: a chapter is picked
  in the toc, a Bible book on the translation's shelf.

  Drawn as the mockup "Читання v2" (A.3): OnGetText returns '' and every row is
  painted in OnAfterCellPaint, so the tree never measures a row wider than the
  panel - long titles end with "…", no horizontal scrolling. VST's own indent
  and buttons are off (Indent 0): the geometry is the mockup's - a book row with
  the box at 2 (a book has nothing to unfold, so the box stands where the
  caret was) and the title at 34. Row heights carry the mockup's margins.
  A series (not in the mockup) is the mockup's book row - the caret at 2, the
  box at 30, the title at 62, "5 кн." - and its books nest under it 26 px in
  with a hairline on the left, so a book outside the series does not look
  like one of it (Vitalii, 2026-11-06).
  A group - a category or a series - has a box too (Vitalii, 2026-11-14): one
  click checks all its books, or unchecks them when all are checked. The
  group keeps no state of its own: its box shows its books - all (the
  square), some (a dash), none.
    - category: 10.5 px caps, semi-bold, muted, a hairline to the right;
      series - the same without the line;
    - book / translation: the square box "Шукати в цій книзі" (R4-41: only
      here, no cascade, no tri-state), the title 13.5 px (the book being read -
      bold), the dot "читаю", the counter 10.5 px muted (E-09).
  The check boxes are ours, not VST's (toCheckSupport is off): the state lives
  in FChecked, a click inside the box zone or Space toggles it.

  The filter (Slovo_04 A.3, E-25): SetFilter hides the rows FilterLibrary
  leaves out (VST IsVisible), opens the series that keep books and paints the
  match under the letters. The series' own folding is kept aside while the
  filter is on and comes back when it is cleared. Row heights follow the
  VISIBLE neighbours - the margins of a nested list, the first category.
  The check boxes do not care about the filter (Vitalii, 2026-11-20).

  The form decides what a click means (ViewModel calls); the tree only reports
  which node was activated or checked. *)

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Graphics,
  VirtualTrees,
  VirtualTrees.Types,
  VirtualTrees.BaseTree,
  Core.Domain,
  Presentation.MainViewModel,
  Presentation.LibraryFilter,
  Shell.FlatControls;

type
  TLibraryNodeEvent = reference to procedure(const Node: TLibraryNode);
  TLibraryCheckEvent = reference to procedure(const Node: TLibraryNode; Checked: Boolean);

  TLibraryTree = class
  private
    FTree: TVirtualStringTree;
    FScale: TFlatScaleFunc;
    FFontName: string;
    FNodes: TArray<TLibraryNode>;
    FTreeNodes: TArray<PVirtualNode>;          // index in FNodes -> VST node; nil = no row
    FChecked: TArray<Boolean>;                 // lnModule / lnBibleTranslation
    FActive: Integer;                          // the chapter being read; -1 = none
    FFilter: TLibraryFilterResult;             // E-25; not Active - no filter
    FSavedExpanded: TArray<Boolean>;           // the series' folding before the filter
    FOnActivate: TLibraryNodeEvent;
    FOnCheck: TLibraryCheckEvent;

    function Px(Value: Integer): Integer;
    function IndexOf(Node: PVirtualNode): Integer;
    function HasRow(Index: Integer): Boolean;
    function PrevShown(Node: PVirtualNode): PVirtualNode;
    function NextShown(Node: PVirtualNode): PVirtualNode;
    function ShownChildren(Node: PVirtualNode): Integer;
    procedure UpdateHeights;
    procedure ScrollToActive;
    function IsAncestorOfActive(Index: Integer): Boolean;
    function IsBookLike(Index: Integer): Boolean;
    function BookDepth(Node: PVirtualNode): Integer;
    function RowLeft(Node: PVirtualNode): Integer;
    function RowBox(Node: PVirtualNode; Index: Integer; const R: TRect): TRect;
    function HasCheckBox(Index: Integer): Boolean;
    function IsGroup(Index: Integer): Boolean;
    function IsUnder(Index, Group: Integer): Boolean;
    function GroupState(Group: Integer): Integer;
    function CheckLeft(Index: Integer): Integer;
    procedure ToggleGroup(Group: Integer);
    function InCheckZone(Node: PVirtualNode; X: Integer): Boolean;
    function InCaretZone(Node: PVirtualNode; X: Integer): Boolean;
    procedure TreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure TreeCollapsing(Sender: TBaseVirtualTree; Node: PVirtualNode; var Allowed: Boolean);
    function CounterText(Index: Integer): string;
    procedure InvalidatePath(Index: Integer);
    procedure Activate(Node: PVirtualNode);
    procedure ToggleCheck(Index: Integer);

    procedure PaintRow(Canvas: TCanvas; Node: PVirtualNode; Index: Integer; const R: TRect);
    procedure TreeGetText(Sender: TBaseVirtualTree; Node: PVirtualNode; Column: TColumnIndex;
      TextType: TVSTTextType; var CellText: string);
    procedure TreeAfterCellPaint(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
      Node: PVirtualNode; Column: TColumnIndex; CellRect: TRect);
    procedure TreeNodeClick(Sender: TBaseVirtualTree; const HitInfo: THitInfo);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeCollapsedOrExpanded(Sender: TBaseVirtualTree; Node: PVirtualNode);
  public
    // Scale: 96-DPI pixels to the form's (E-14) - the form's own ScaleValue.
    constructor Create(AOwner: TComponent; AParent: TWinControl; const Scale: TFlatScaleFunc);
    // The VST belongs to AOwner and outlives this object while the form is
    // destroyed: its events are detached here so none reaches freed code.
    destructor Destroy; override;

    // OnLibraryChanged: the whole tree, once. Categories start expanded.
    procedure Build(const Nodes: TArray<TLibraryNode>);
    // After a chapter is loaded: the dot "читаю" moves to its book, the path opens (R4-43).
    procedure SetActive(const Position: TReadingPosition);
    // E-25: the rows whose captions match Text (and their parents) stay; '' -
    // the whole tree as it was. The result: the counts and the first book.
    function SetFilter(const Text: string): TLibraryFilterResult;
    // As a click on the row of node Index (Enter in the filter).
    procedure ActivateIndex(Index: Integer);
    // The language changed: texts come from L() while painting.
    procedure Invalidate;
    function CheckedCount: Integer;
    procedure ApplyFont(const FontName: string);

    property Control: TVirtualStringTree read FTree;
    property OnActivate: TLibraryNodeEvent read FOnActivate write FOnActivate;
    property OnCheck: TLibraryCheckEvent read FOnCheck write FOnCheck;
  end;

implementation

uses
  System.UITypes,
  System.Math,
  Presentation.Localization,
  Presentation.Theme;

const
  // Geometry of the mockup "Читання v2", left aside, 96-DPI pixels. The host
  // gives the aside's padding (18 left, 10 right); x is from the row's left.
  CategoryHeight      = 48;     // the previous group's margin 26 + caption 14 + 8 below
  FirstCategoryHeight = 22;     // no group above
  CategoryBelow       = 8;
  CaptionLine         = 14;
  SeriesHeight        = 28;
  SeriesBelow         = 6;
  BookHeight          = 32;     // the 30 px row + margin-bottom 2
  BookRow             = 30;
  NestTop             = 2;      // the nested list: margin 2 0 8 26
  NestBottom          = 8;
  NestLine            = 26;     // its border-left, from the parent row's left
  NestStep            = 37;     // 26 + border 1 + padding 10: where nested rows start
  CaretX              = 2;      // row padding-left 2: the caret of a series
  ButtonPx            = 24;     // the caret and the box buttons
  CheckX              = 2;      // the box of a book or a category, in the caret's place
  LabelX              = 34;     // 2 + 24 + gap 4 + label padding 4
  SeriesCheckX        = 30;     // a series: after its caret, 2 + 24 + gap 4
  SeriesLabelX        = 62;     // 30 + 24 + gap 4 + label padding 4
  PartBarPx           = 2;      // the dash of a partly checked group
  RowPadRight         = 8;
  CaretPx             = 7;
  CheckBoxPx          = 14;
  CheckInnerPx        = 8;
  DotPx               = 5;
  GroupPx             = 11;     // mockup 10.5
  BookPx              = 14;     // mockup 13.5
  CounterPx           = 11;     // mockup 10.5
  BottomPadding       = 40;     // aside padding-bottom

  ColorRowHover    = TColor($00F1F1F1);   // rgba(0,0,0,.045) on #fcfcfc
  ColorCaretHover  = TColor($00EDEDED);   // rgba(0,0,0,.06)
  ColorGroupLine   = TColor($00EDEDED);   // rgba(0,0,0,.07)
  ColorNestLine    = TColor($00E8E8E8);   // rgba(0,0,0,.08)
  ColorCaret       = TColor($008A8A8A);   // #8a8a8a
  ColorCaretHot    = TColor($002F2F2F);   // #2f2f2f
  ColorBookText    = TColor($003D3D3D);   // #3d3d3d
  ColorCurrentText = TColor($001F1F1F);   // #1f1f1f

{ TLibraryTree }

constructor TLibraryTree.Create(AOwner: TComponent; AParent: TWinControl;
  const Scale: TFlatScaleFunc);
begin
  inherited Create;
  FScale := Scale;
  FFontName := UiFontName;
  FActive := -1;
  FTree := TVirtualStringTree.Create(AOwner);
  FTree.Parent := AParent;
  FTree.Align := alClient;
  FTree.BorderStyle := bsNone;
  FTree.NodeDataSize := SizeOf(Integer);
  FTree.Color := ColorBackground;
  // toAutoChangeScale would reset row heights to the font height (see Shell.ChapterList).
  FTree.TreeOptions.AutoOptions := FTree.TreeOptions.AutoOptions - [toAutoChangeScale];
  FTree.DefaultNodeHeight := Px(BookHeight);
  FTree.Indent := 0;                         // the geometry is ours (RowLeft)
  FTree.Margin := 0;
  FTree.TextMargin := 0;
  FTree.ScrollBarOptions.ScrollBars := System.UITypes.TScrollStyle.ssVertical;   // scoped enum
  FTree.TreeOptions.MiscOptions := FTree.TreeOptions.MiscOptions
    - [toCheckSupport, toEditable, toToggleOnDblClick];
  FTree.TreeOptions.PaintOptions := FTree.TreeOptions.PaintOptions
    - [toShowTreeLines, toUseExplorerTheme, toShowRoot, toShowButtons]
    + [toHideFocusRect, toHotTrack, toAlwaysHideSelection];
  FTree.TreeOptions.SelectionOptions := FTree.TreeOptions.SelectionOptions + [toFullRowSelect];
  FTree.OnGetText := TreeGetText;
  FTree.OnAfterCellPaint := TreeAfterCellPaint;
  FTree.OnNodeClick := TreeNodeClick;
  FTree.OnKeyDown := TreeKeyDown;
  FTree.OnExpanded := TreeCollapsedOrExpanded;
  FTree.OnCollapsed := TreeCollapsedOrExpanded;
  FTree.OnMouseMove := TreeMouseMove;
  FTree.OnCollapsing := TreeCollapsing;
end;

destructor TLibraryTree.Destroy;
begin
  FTree.OnGetText := nil;
  FTree.OnAfterCellPaint := nil;
  FTree.OnNodeClick := nil;
  FTree.OnKeyDown := nil;
  FTree.OnExpanded := nil;
  FTree.OnCollapsed := nil;
  FTree.OnMouseMove := nil;
  FTree.OnCollapsing := nil;
  inherited;
end;

function TLibraryTree.Px(Value: Integer): Integer;
begin
  Result := FScale(Value);
end;

procedure TLibraryTree.ApplyFont(const FontName: string);
begin
  FFontName := FontName;
  FTree.Font.Name := FontName;
  FTree.Invalidate;
end;

function TLibraryTree.IndexOf(Node: PVirtualNode): Integer;
var
  Data: PInteger;
begin
  Result := -1;
  if Node = nil then
    Exit;
  Data := FTree.GetNodeData(Node);
  if Data <> nil then
    Result := Data^;
end;

// Chapters and Bible books have no row: the tree ends at the book.
function TLibraryTree.HasRow(Index: Integer): Boolean;
begin
  Result := FNodes[Index].Kind in [lnCategory, lnSeries, lnModule, lnBibleTranslation];
end;

function TLibraryTree.HasCheckBox(Index: Integer): Boolean;
begin
  Result := FNodes[Index].Kind in [lnModule, lnBibleTranslation];
end;

function TLibraryTree.IsGroup(Index: Integer): Boolean;
begin
  Result := FNodes[Index].Kind in [lnCategory, lnSeries];
end;

function TLibraryTree.IsUnder(Index, Group: Integer): Boolean;
var
  P: Integer;
begin
  P := FNodes[Index].Parent;
  while (P >= 0) and (P <> Group) do
    P := FNodes[P].Parent;
  Result := P = Group;
end;

// The box of a group shows its books: 0 - none checked, 1 - some, 2 - all.
function TLibraryTree.GroupState(Group: Integer): Integer;
var
  I, Total, Checked: Integer;
begin
  Total := 0;
  Checked := 0;
  for I := Group + 1 to High(FNodes) do
    if HasCheckBox(I) and IsUnder(I, Group) then
    begin
      Inc(Total);
      if FChecked[I] then
        Inc(Checked);
    end;
  if Checked = 0 then
    Result := 0
  else if Checked = Total then
    Result := 2
  else
    Result := 1;
end;

// Where the box button starts, from the row's left.
function TLibraryTree.CheckLeft(Index: Integer): Integer;
begin
  if FNodes[Index].Kind = lnSeries then
    Result := Px(SeriesCheckX)
  else
    Result := Px(CheckX);
end;

procedure TLibraryTree.Build(const Nodes: TArray<TLibraryNode>);
var
  I: Integer;
  Parent, Node: PVirtualNode;
begin
  FNodes := Nodes;
  FFilter := Default(TLibraryFilterResult);
  FSavedExpanded := nil;
  SetLength(FTreeNodes, Length(Nodes));
  SetLength(FChecked, Length(Nodes));
  FActive := -1;
  FTree.BeginUpdate;
  try
    FTree.Clear;
    // Not in the constructor: setting it makes VST look for its bottom node
    // before the window exists (an access violation in FormCreate).
    FTree.BottomSpace := Px(BottomPadding);
    for I := 0 to High(Nodes) do
    begin
      FTreeNodes[I] := nil;
      FChecked[I] := False;
      if not HasRow(I) then
        Continue;
      if Nodes[I].Parent < 0 then
        Parent := nil
      else
        Parent := FTreeNodes[Nodes[I].Parent];
      Node := FTree.AddChild(Parent);
      PInteger(FTree.GetNodeData(Node))^ := I;
      FTreeNodes[I] := Node;
      FChecked[I] := HasCheckBox(I) and Nodes[I].Checked;
    end;
    UpdateHeights;
    for I := 0 to High(Nodes) do
      if Nodes[I].Kind in [lnCategory, lnSeries] then
        FTree.Expanded[FTreeNodes[I]] := True;
  finally
    FTree.EndUpdate;
  end;
end;

// The visible neighbours of a row: the filter hides some of its siblings (E-25).
function TLibraryTree.PrevShown(Node: PVirtualNode): PVirtualNode;
begin
  Result := Node.PrevSibling;
  while (Result <> nil) and not FTree.IsVisible[Result] do
    Result := Result.PrevSibling;
end;

function TLibraryTree.NextShown(Node: PVirtualNode): PVirtualNode;
begin
  Result := Node.NextSibling;
  while (Result <> nil) and not FTree.IsVisible[Result] do
    Result := Result.NextSibling;
end;

function TLibraryTree.ShownChildren(Node: PVirtualNode): Integer;
var
  Child: PVirtualNode;
begin
  Result := 0;
  Child := Node.FirstChild;
  while Child <> nil do
  begin
    if FTree.IsVisible[Child] then
      Inc(Result);
    Child := Child.NextSibling;
  end;
end;

// Heights by the visible rows: a nested list adds its margins to its first and
// last row; the first category has no group above it.
procedure TLibraryTree.UpdateHeights;
var
  I, H: Integer;
  Node: PVirtualNode;
  FirstCategory: Boolean;
begin
  FirstCategory := True;
  for I := 0 to High(FNodes) do
  begin
    Node := FTreeNodes[I];
    if (Node = nil) or not FTree.IsVisible[Node] then
      Continue;
    H := BookHeight;
    if FNodes[I].Kind = lnCategory then
    begin
      if FirstCategory then
        H := FirstCategoryHeight
      else
        H := CategoryHeight;
      FirstCategory := False;
    end;
    H := Px(H);
    if BookDepth(Node) > 0 then
    begin
      if PrevShown(Node) = nil then
        Inc(H, Px(NestTop));
      if NextShown(Node) = nil then
        Inc(H, Px(NestBottom));
    end;
    FTree.NodeHeight[Node] := H;
  end;
end;

function TLibraryTree.SetFilter(const Text: string): TLibraryFilterResult;
var
  Captions: TArray<string>;
  I: Integer;
  WasActive: Boolean;
  Node: PVirtualNode;
begin
  SetLength(Captions, Length(FNodes));
  for I := 0 to High(FNodes) do
    if FNodes[I].Kind = lnCategory then
      Captions[I] := L(FNodes[I].CaptionKey)
    else
      Captions[I] := FNodes[I].Caption;
  WasActive := FFilter.Active;
  FFilter := FilterLibrary(FNodes, Captions, Text);
  FTree.BeginUpdate;
  try
    if FFilter.Active and not WasActive then
    begin
      SetLength(FSavedExpanded, Length(FNodes));
      for I := 0 to High(FNodes) do
        FSavedExpanded[I] := (FTreeNodes[I] <> nil) and FTree.Expanded[FTreeNodes[I]];
    end;
    for I := 0 to High(FNodes) do
    begin
      Node := FTreeNodes[I];
      if Node = nil then
        Continue;
      FTree.IsVisible[Node] := FFilter.Visible[I];
      if FNodes[I].Kind = lnSeries then
      begin
        if FFilter.Active then
          FTree.Expanded[Node] := FFilter.Visible[I]
        else if WasActive then
          FTree.Expanded[Node] := FSavedExpanded[I];
      end;
    end;
    UpdateHeights;
  finally
    FTree.EndUpdate;
  end;
  if FFilter.Active then
    FTree.OffsetY := 0
  else if WasActive then
    ScrollToActive;                          // back to the book being read
  FTree.Invalidate;
  Result := FFilter;
end;

procedure TLibraryTree.ActivateIndex(Index: Integer);
begin
  if (Index < 0) or (Index > High(FTreeNodes)) or (FTreeNodes[Index] = nil) then
    Exit;
  FTree.ClearSelection;
  FTree.FocusedNode := FTreeNodes[Index];
  FTree.Selected[FTreeNodes[Index]] := True;
  Activate(FTreeNodes[Index]);
end;

procedure TLibraryTree.ScrollToActive;
var
  Row: Integer;
begin
  Row := FActive;
  while (Row >= 0) and (FTreeNodes[Row] = nil) do
    Row := FNodes[Row].Parent;
  if Row >= 0 then
    FTree.ScrollIntoView(FTreeNodes[Row], False);
end;

function TLibraryTree.CheckedCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FChecked) do
    if FChecked[I] then
      Inc(Result);
end;

procedure TLibraryTree.Invalidate;
begin
  FTree.Invalidate;
end;

function TLibraryTree.IsAncestorOfActive(Index: Integer): Boolean;
var
  P: Integer;
begin
  Result := False;
  if FActive < 0 then
    Exit;
  P := FNodes[FActive].Parent;
  while P >= 0 do
  begin
    if P = Index then
      Exit(True);
    P := FNodes[P].Parent;
  end;
end;

procedure TLibraryTree.InvalidatePath(Index: Integer);
begin
  while Index >= 0 do
  begin
    if FTreeNodes[Index] <> nil then
      FTree.InvalidateNode(FTreeNodes[Index]);
    Index := FNodes[Index].Parent;
  end;
end;

procedure TLibraryTree.SetActive(const Position: TReadingPosition);
var
  I, Found, Row: Integer;
  N: TLibraryNode;
begin
  Found := -1;
  for I := 0 to High(FNodes) do
  begin
    N := FNodes[I];
    if N.Kind <> lnChapter then
      Continue;
    if Position.Kind = ckBibleTranslation then
    begin
      if (N.ModuleId = Position.BibleChapter.Book.ModuleId) and
        (N.BookCode = Position.BibleChapter.Book.BookCode) and
        (N.ChapterOrder = Position.BibleChapter.ChapterNumber) then
        Found := I;
    end
    else if (N.BookCode = '') and (N.ModuleId = Position.Chapter.ModuleId) and
      (N.ChapterOrder = Position.Chapter.ChapterOrder) then
      Found := I;
    if Found >= 0 then
      Break;
  end;

  InvalidatePath(FActive);
  FActive := Found;
  if Found < 0 then
    Exit;
  InvalidatePath(Found);
  // The chapter has no row: the row to show is its book (the translation).
  Row := Found;
  while (Row >= 0) and (FTreeNodes[Row] = nil) do
    Row := FNodes[Row].Parent;
  if Row < 0 then
    Exit;
  // A row the filter hides stays hidden (FullyVisible would show it, E-25).
  if FFilter.Active and not FTree.IsVisible[FTreeNodes[Row]] then
    Exit;
  FTree.FullyVisible[FTreeNodes[Row]] := True;
  FTree.ScrollIntoView(FTreeNodes[Row], False);
  FTree.ClearSelection;
  FTree.FocusedNode := FTreeNodes[Row];
  FTree.Selected[FTreeNodes[Row]] := True;
end;

{ painting }

function TLibraryTree.IsBookLike(Index: Integer): Boolean;
begin
  Result := FNodes[Index].Kind in [lnSeries, lnModule, lnBibleTranslation];
end;

// How many book-like rows this row is nested in: a book of a series - in one.
function TLibraryTree.BookDepth(Node: PVirtualNode): Integer;
var
  P: PVirtualNode;
  I: Integer;
begin
  Result := 0;
  P := Node.Parent;
  while (P <> nil) and (P <> FTree.RootNode) do
  begin
    I := IndexOf(P);
    if (I >= 0) and IsBookLike(I) then
      Inc(Result);
    P := P.Parent;
  end;
end;

function TLibraryTree.RowLeft(Node: PVirtualNode): Integer;
begin
  Result := BookDepth(Node) * Px(NestStep) - FTree.OffsetX;
end;

// The row's own box inside its cell: without the margins around it.
function TLibraryTree.RowBox(Node: PVirtualNode; Index: Integer; const R: TRect): TRect;
begin
  Result := R;
  Result.Left := RowLeft(Node);
  if (BookDepth(Node) > 0) and (PrevShown(Node) = nil) then
    Inc(Result.Top, Px(NestTop));
  if IsBookLike(Index) then
    Result.Bottom := Result.Top + Px(BookRow);
end;

function TLibraryTree.CounterText(Index: Integer): string;
var
  N: TLibraryNode;
begin
  N := FNodes[Index];
  if (N.Kind = lnSeries) and (N.Count <= 0) then
    N.Count := FTreeNodes[Index].ChildCount;  // the catalog gives no count for a series
  if N.Count <= 0 then
    Exit('');
  case N.Kind of
    lnModule:           Result := L('library.chapters', [N.Count]);
    lnBibleTranslation: Result := L('library.bibleBooks', [N.Count]);
    lnSeries:
      if FFilter.Active and (ShownChildren(FTreeNodes[Index]) < N.Count) then
        Result := L('library.filter.shownOf', [ShownChildren(FTreeNodes[Index]), N.Count])
      else
        Result := L('library.bibleBooks', [N.Count]);   // "5 кн."
  else
    Result := '';
  end;
end;

procedure TLibraryTree.TreeGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
  Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
begin
  CellText := '';                            // everything is painted (A.3, C.5)
end;

procedure TLibraryTree.TreeAfterCellPaint(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
  Node: PVirtualNode; Column: TColumnIndex; CellRect: TRect);
var
  Index: Integer;
begin
  Index := IndexOf(Node);
  if (Index < 0) or (Index > High(FNodes)) then
    Exit;
  PaintRow(TargetCanvas, Node, Index, Rect(0, CellRect.Top, Sender.ClientWidth, CellRect.Bottom));
end;

procedure TLibraryTree.PaintRow(Canvas: TCanvas; Node: PVirtualNode; Index: Integer; const R: TRect);
var
  N: TLibraryNode;
  Hot, CaretHot, Current, Dot: Boolean;
  Box, B, TextR: TRect;
  X, Right, CenterY, W, Depth, K, LineX, Y1, Y2: Integer;
  P: TPoint;
  Text, Counter: string;

  // The 14 px box in its 24 px button, centred on Y; a group shows its books.
  procedure DrawBox(Y: Integer);
  var
    State: Integer;
  begin
    B.Left := Box.Left + CheckLeft(Index) + (Px(ButtonPx) - Px(CheckBoxPx)) div 2;
    B.Top := Y - Px(CheckBoxPx) div 2;
    B.Right := B.Left + Px(CheckBoxPx);
    B.Bottom := B.Top + Px(CheckBoxPx);
    if IsGroup(Index) then
      State := GroupState(Index)
    else if FChecked[Index] then
      State := 2
    else
      State := 0;
    PaintCheckBox(Canvas, B, State = 2, Px(CheckInnerPx));
    if State = 1 then
    begin
      B.Left := B.Left + (B.Width - Px(CheckInnerPx)) div 2;
      B.Top := B.Top + (B.Height - Px(PartBarPx)) div 2;
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ColorAccent;
      Canvas.FillRect(Rect(B.Left, B.Top, B.Left + Px(CheckInnerPx), B.Top + Px(PartBarPx)));
    end;
  end;

  procedure UseFont(const Name: string; SizePx: Integer; Color: TColor);
  begin
    Canvas.Font.Name := Name;
    Canvas.Font.Height := -Px(SizePx);
    Canvas.Font.Style := [];
    Canvas.Font.Color := Color;
    SetTextCharacterExtra(Canvas.Handle, 0);
  end;

  // E-25: the filter's match under the letters - with the font already chosen.
  procedure DrawHit(const S: string; Left, Top, Right, Bottom: Integer);
  var
    M: TFilterMatch;
    A, Z, H, Y: Integer;
  begin
    if not FFilter.Active or (Index > High(FFilter.Matches)) then
      Exit;
    M := FFilter.Matches[Index];
    if (M.Length = 0) or (M.Start + M.Length > Length(S)) then
      Exit;
    A := Left + Canvas.TextWidth(Copy(S, 1, M.Start));
    Z := Min(Left + Canvas.TextWidth(Copy(S, 1, M.Start + M.Length)), Right);
    if Z <= A then
      Exit;
    H := Canvas.TextHeight('Ag');
    Y := (Top + Bottom - H) div 2;
    PaintRoundRect(Canvas, Rect(A - 1, Y, Z + 1, Y + H), Px(2), ColorFilterHit, clNone);
    Canvas.Brush.Style := bsClear;
  end;

  procedure DrawIn(const S: string; Left, Top, Right, Bottom: Integer; Flags: Cardinal);
  begin
    TextR := Rect(Left, Top, Right, Bottom);
    Winapi.Windows.DrawText(Canvas.Handle, PChar(S), Length(S), TextR,
      DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS or Flags);
  end;

begin
  N := FNodes[Index];
  Hot := (Node = FTree.HotNode) or ((Node = FTree.FocusedNode) and FTree.Focused);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ColorBackground;
  Canvas.FillRect(R);

  // The nested lists' left hairlines (mockup border-left), the innermost one
  // without the list's own margins.
  Depth := BookDepth(Node);
  for K := 1 to Depth do
  begin
    LineX := (K - 1) * Px(NestStep) + Px(NestLine) - FTree.OffsetX;
    Y1 := R.Top;
    Y2 := R.Bottom;
    if K = Depth then
    begin
      if PrevShown(Node) = nil then
        Inc(Y1, Px(NestTop));
      if NextShown(Node) = nil then
        Dec(Y2, Px(NestBottom));
    end;
    Canvas.Brush.Color := ColorNestLine;
    Canvas.FillRect(Rect(LineX, Y1, LineX + 1, Y2));
  end;

  Box := RowBox(Node, Index, R);
  CenterY := (Box.Top + Box.Bottom) div 2;
  Right := R.Right - Px(RowPadRight);

  case N.Kind of
    lnCategory:
      begin
        Text := L(N.CaptionKey).ToUpper;
        // Mockup: 10.5 px, weight 600, letter-spacing .12em, 8 px above the
        // group's first row; a category has a hairline to the right.
        // The box of the whole category, in the books' box column; the caption
        // starts where the book titles do.
        DrawBox(R.Bottom - Px(CategoryBelow) - Px(CaptionLine) div 2);
        UseFont(UiFontSemiBoldName, GroupPx, ColorMuted);
        SetTracking(Canvas, 0.12);
        X := Box.Left + Px(LabelX);
        B := Rect(X, R.Bottom - Px(CategoryBelow) - Px(CaptionLine), Right, R.Bottom - Px(CategoryBelow));
        DrawHit(Text, B.Left, B.Top, B.Right, B.Bottom);
        Canvas.Brush.Style := bsClear;
        DrawIn(Text, B.Left, B.Top, B.Right, B.Bottom, DT_VCENTER or DT_LEFT);
        W := X + Canvas.TextWidth(Text) + Px(8);
        if W < Right then
        begin
          Y1 := (B.Top + B.Bottom) div 2;
          Canvas.Brush.Style := bsSolid;
          Canvas.Brush.Color := ColorGroupLine;
          Canvas.FillRect(Rect(W, Y1, Right, Y1 + 1));
        end;
        SetTextCharacterExtra(Canvas.Handle, 0);
      end;

    lnSeries, lnModule, lnBibleTranslation:
      begin
        if Hot then
          PaintRoundRect(Canvas, Rect(Box.Left, Box.Top, R.Right, Box.Bottom), Px(6), ColorRowHover, clNone);
        // The caret button 24 x 24 of a series: ▸ / ▾ #8a8a8a, its own hover.
        if Node.ChildCount > 0 then
        begin
          B.Left := Box.Left + Px(CaretX);
          B.Top := CenterY - Px(ButtonPx) div 2;
          B.Right := B.Left + Px(ButtonPx);
          B.Bottom := B.Top + Px(ButtonPx);
          P := FTree.ScreenToClient(Mouse.CursorPos);
          CaretHot := (Node = FTree.HotNode) and PtInRect(B, P);
          if CaretHot then
          begin
            PaintRoundRect(Canvas, B, Px(5), ColorCaretHover, clNone);
            PaintTriangle(Canvas, B, FTree.Expanded[Node], Px(CaretPx), ColorCaretHot);
          end
          else
            PaintTriangle(Canvas, B, FTree.Expanded[Node], Px(CaretPx), ColorCaret);
        end;
        // The box "Шукати в цій книзі", in its 24 px button; of a series - all its books.
        DrawBox(CenterY);
        if N.Kind = lnSeries then
          X := Box.Left + Px(SeriesLabelX)
        else
          X := Box.Left + Px(LabelX);

        // The book being read; a series shows the dot only while it hides it.
        Current := IsAncestorOfActive(Index);
        Dot := Current and not FTree.Expanded[Node];
        Canvas.Brush.Style := bsClear;
        // From the right: the counter, gap 4, the dot (margin-right 4), gap 4.
        Counter := CounterText(Index);
        if Counter <> '' then
        begin
          UseFont(FFontName, CounterPx, ColorMarker);
          W := Canvas.TextWidth(Counter);
          DrawIn(Counter, Right - W, Box.Top, Right, Box.Bottom, DT_VCENTER or DT_RIGHT);
          Right := Right - W - Px(4);
        end;
        if Dot then
        begin
          Right := Right - Px(4);
          PaintDot(Canvas, Right - Px(DotPx) div 2, CenterY, Px(DotPx), ColorAccent);
          Right := Right - Px(DotPx) - Px(4);
        end;
        Right := Right - Px(4);                // the label's padding-right
        // Mockup: weight 500, the book being read - 600; hover - the accent.
        if Current then
          UseFont(UiFontSemiBoldName, BookPx, ColorCurrentText)
        else if Hot then
          UseFont(UiFontMediumName, BookPx, ColorAccent)
        else
          UseFont(UiFontMediumName, BookPx, ColorBookText);
        DrawHit(N.Caption, X, Box.Top, Right, Box.Bottom);
        Canvas.Brush.Style := bsClear;
        DrawIn(N.Caption, X, Box.Top, Right, Box.Bottom, DT_VCENTER or DT_LEFT);
      end;
  end;
end;

{ input }

function TLibraryTree.InCheckZone(Node: PVirtualNode; X: Integer): Boolean;
var
  Index, Left: Integer;
begin
  Index := IndexOf(Node);
  Result := (Index >= 0) and (HasCheckBox(Index) or IsGroup(Index));
  if not Result then
    Exit;
  Left := RowLeft(Node) + CheckLeft(Index);
  Result := (X >= Left) and (X < Left + Px(ButtonPx));
end;

function TLibraryTree.InCaretZone(Node: PVirtualNode; X: Integer): Boolean;
var
  Index, Left: Integer;
begin
  Index := IndexOf(Node);
  Result := (Index >= 0) and IsBookLike(Index) and (Node.ChildCount > 0);
  if not Result then
    Exit;
  Left := RowLeft(Node) + Px(CaretX);
  Result := (X >= Left) and (X < Left + Px(ButtonPx));
end;

// A category never folds - not by a click, not by ← (Vitalii, 2026-11-06).
procedure TLibraryTree.TreeCollapsing(Sender: TBaseVirtualTree; Node: PVirtualNode;
  var Allowed: Boolean);
var
  Index: Integer;
begin
  Index := IndexOf(Node);
  Allowed := (Index < 0) or (FNodes[Index].Kind <> lnCategory);
end;

// The caret has its own hover inside the hot row: repaint it as the mouse moves.
procedure TLibraryTree.TreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if FTree.HotNode <> nil then
    FTree.InvalidateNode(FTree.HotNode);
end;

procedure TLibraryTree.ToggleCheck(Index: Integer);
begin
  if IsGroup(Index) then
  begin
    ToggleGroup(Index);
    Exit;
  end;
  FChecked[Index] := not FChecked[Index];
  InvalidatePath(Index);                     // its groups' boxes show it too
  if Assigned(FOnCheck) then
    FOnCheck(FNodes[Index], FChecked[Index]);
end;

// One click for the whole group: all its books checked, or - when all already
// are - unchecked. The form hears of each book that changed, as of a click on it.
procedure TLibraryTree.ToggleGroup(Group: Integer);
var
  I: Integer;
  Value: Boolean;
begin
  Value := GroupState(Group) <> 2;
  for I := Group + 1 to High(FNodes) do
    if HasCheckBox(I) and IsUnder(I, Group) and (FChecked[I] <> Value) then
    begin
      FChecked[I] := Value;
      if Assigned(FOnCheck) then
        FOnCheck(FNodes[I], Value);
    end;
  FTree.Invalidate;
end;

procedure TLibraryTree.Activate(Node: PVirtualNode);
var
  Index: Integer;
begin
  Index := IndexOf(Node);
  if Index < 0 then
    Exit;
  // A category never folds (no caret: folded or not would not show); a
  // series opens in the tree and as its shelf; a book only as its toc.
  if FNodes[Index].Kind = lnSeries then
    FTree.Expanded[Node] := True;
  if Assigned(FOnActivate) then
    FOnActivate(FNodes[Index]);
end;

procedure TLibraryTree.TreeNodeClick(Sender: TBaseVirtualTree; const HitInfo: THitInfo);
var
  P: TPoint;
begin
  if HitInfo.HitNode = nil then
    Exit;
  P := FTree.ScreenToClient(Mouse.CursorPos);
  // The caret only opens / closes; the box only checks; the rest activates.
  if InCaretZone(HitInfo.HitNode, P.X) then
    FTree.ToggleNode(HitInfo.HitNode)
  else if InCheckZone(HitInfo.HitNode, P.X) then
    ToggleCheck(IndexOf(HitInfo.HitNode))
  else
    Activate(HitInfo.HitNode);
end;

procedure TLibraryTree.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Index: Integer;
begin
  if FTree.FocusedNode = nil then
    Exit;
  case Key of
    vkReturn:
      begin
        Activate(FTree.FocusedNode);
        Key := 0;
      end;
    vkSpace:
      begin
        Index := IndexOf(FTree.FocusedNode);
        if (Index >= 0) and (HasCheckBox(Index) or IsGroup(Index)) then
        begin
          ToggleCheck(Index);
          Key := 0;
        end;
      end;
  end;
end;

// The dot moves between a collapsed series and its book.
procedure TLibraryTree.TreeCollapsedOrExpanded(Sender: TBaseVirtualTree; Node: PVirtualNode);
begin
  Sender.InvalidateNode(Node);
end;

end.
