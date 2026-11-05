unit Shell.LibraryTree;

(* The library tree of the left panel (Slovo_04 A.3, C.5, E-02).

  A thin owner of one TVirtualStringTree. The tree is built ONCE from the flat
  TLibraryNode array of OnLibraryChanged (B-29): nodes are added in array order,
  the parent of each is an already added node. A VST node holds only the index
  into that array (NodeDataSize = SizeOf(Integer)) - no strings in the tree, so
  a language change is an Invalidate, never a rebuild (R4-12).

  Drawn as the mockup "Читання v2" (A.3): OnGetText returns '' and every row is
  painted in OnAfterCellPaint, so the tree never measures a row wider than the
  panel - long titles end with "…", no horizontal scrolling.
    - category: 10.5 px caps, semi-bold, muted, a hairline to the right;
      series - the same without the line;
    - book / translation: the square box "Шукати в цій книзі" (R4-41: only
      here, no cascade, no tri-state), the title 13.5 px (the book being read -
      bold), the dot "читаю" when collapsed, the counter 10.5 px muted (E-09);
    - Bible book: the title, the dot, the counter;
    - chapter: its number in a muted column, the title 12.5 px, the dot at the
      end of the active one (a Bible chapter - only its number).
  The check boxes are ours, not VST's (toCheckSupport is off): the state lives
  in FChecked, a click inside the box zone or Space toggles it.

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
    FTreeNodes: TArray<PVirtualNode>;          // index in FNodes -> VST node
    FChecked: TArray<Boolean>;                 // lnModule / lnBibleTranslation
    FActive: Integer;                          // the chapter being read; -1 = none
    FOnActivate: TLibraryNodeEvent;
    FOnCheck: TLibraryCheckEvent;

    function Px(Value: Integer): Integer;
    function IndexOf(Node: PVirtualNode): Integer;
    function IsAncestorOfActive(Index: Integer): Boolean;
    function ContentLeft(Node: PVirtualNode): Integer;
    function HasCheckBox(Index: Integer): Boolean;
    function InCheckZone(Node: PVirtualNode; X: Integer): Boolean;
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
    // After a chapter is loaded: the dot "читаю" moves, the path opens (R4-43).
    procedure SetActive(const Position: TReadingPosition);
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
  Presentation.Localization,
  Presentation.Theme;

const
  // Row heights and sizes, 96-DPI pixels (mockup "Читання v2", left aside).
  CategoryHeight = 34;
  SeriesHeight   = 28;
  BookHeight     = 30;
  ChapterHeight  = 28;
  IndentPx       = 16;
  CheckZone      = 24;      // the button around the 14 px box
  CheckBoxPx     = 14;
  CheckInnerPx   = 8;
  DotPx          = 5;
  GroupPx        = 11;      // mockup 10.5
  BookPx         = 14;      // mockup 13.5
  ChapterPx      = 13;      // mockup 12.5
  CounterPx      = 11;      // mockup 10.5
  NumberColumn   = 22;      // up to three digits at CounterPx
  NumberGap      = 9;
  RowPadRight    = 8;

  ColorRowHover    = TColor($00F1F1F1);   // rgba(0,0,0,.045) on #fcfcfc
  ColorGroupLine   = TColor($00EDEDED);   // rgba(0,0,0,.07)
  ColorBookText    = TColor($003D3D3D);   // #3d3d3d
  ColorCurrentText = TColor($001F1F1F);   // #1f1f1f
  ColorChapterText = TColor($005F5F5F);   // #5f5f5f

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
  FTree.DefaultNodeHeight := Px(ChapterHeight);
  FTree.Indent := Px(IndentPx);
  FTree.Margin := 0;
  FTree.TextMargin := 0;
  FTree.ButtonStyle := bsTriangle;
  FTree.Colors.TreeLineColor := ColorMarker;
  FTree.ScrollBarOptions.ScrollBars := System.UITypes.TScrollStyle.ssVertical;   // scoped enum
  FTree.TreeOptions.MiscOptions := FTree.TreeOptions.MiscOptions - [toCheckSupport, toEditable];
  FTree.TreeOptions.PaintOptions := FTree.TreeOptions.PaintOptions
    - [toShowTreeLines, toUseExplorerTheme]
    + [toShowRoot, toShowButtons, toHideFocusRect, toHotTrack, toAlwaysHideSelection];
  FTree.TreeOptions.SelectionOptions := FTree.TreeOptions.SelectionOptions + [toFullRowSelect];
  FTree.OnGetText := TreeGetText;
  FTree.OnAfterCellPaint := TreeAfterCellPaint;
  FTree.OnNodeClick := TreeNodeClick;
  FTree.OnKeyDown := TreeKeyDown;
  FTree.OnExpanded := TreeCollapsedOrExpanded;
  FTree.OnCollapsed := TreeCollapsedOrExpanded;
end;

destructor TLibraryTree.Destroy;
begin
  FTree.OnGetText := nil;
  FTree.OnAfterCellPaint := nil;
  FTree.OnNodeClick := nil;
  FTree.OnKeyDown := nil;
  FTree.OnExpanded := nil;
  FTree.OnCollapsed := nil;
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

function TLibraryTree.HasCheckBox(Index: Integer): Boolean;
begin
  Result := FNodes[Index].Kind in [lnModule, lnBibleTranslation];
end;

procedure TLibraryTree.Build(const Nodes: TArray<TLibraryNode>);
var
  I, H: Integer;
  Parent, Node: PVirtualNode;
begin
  FNodes := Nodes;
  SetLength(FTreeNodes, Length(Nodes));
  SetLength(FChecked, Length(Nodes));
  FActive := -1;
  FTree.BeginUpdate;
  try
    FTree.Clear;
    for I := 0 to High(Nodes) do
    begin
      if Nodes[I].Parent < 0 then
        Parent := nil
      else
        Parent := FTreeNodes[Nodes[I].Parent];
      Node := FTree.AddChild(Parent);
      PInteger(FTree.GetNodeData(Node))^ := I;
      FTreeNodes[I] := Node;
      FChecked[I] := HasCheckBox(I) and Nodes[I].Checked;
      case Nodes[I].Kind of
        lnCategory:                           H := CategoryHeight;
        lnSeries:                             H := SeriesHeight;
        lnModule, lnBibleTranslation, lnBibleBook: H := BookHeight;
      else
        H := ChapterHeight;
      end;
      FTree.NodeHeight[Node] := Px(H);
    end;
    for I := 0 to High(Nodes) do
      if Nodes[I].Kind = lnCategory then
        FTree.Expanded[FTreeNodes[I]] := True;
  finally
    FTree.EndUpdate;
  end;
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
    FTree.InvalidateNode(FTreeNodes[Index]);
    Index := FNodes[Index].Parent;
  end;
end;

procedure TLibraryTree.SetActive(const Position: TReadingPosition);
var
  I, Found: Integer;
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
  FTree.FullyVisible[FTreeNodes[Found]] := True;
  FTree.ScrollIntoView(FTreeNodes[Found], False);
  FTree.ClearSelection;
  FTree.FocusedNode := FTreeNodes[Found];
  FTree.Selected[FTreeNodes[Found]] := True;
end;

{ painting }

// The row content starts after the indent of its level, where VST draws the
// expand button (toShowRoot: level 0 has one too).
function TLibraryTree.ContentLeft(Node: PVirtualNode): Integer;
begin
  Result := Integer(FTree.GetNodeLevel(Node) + 1) * Integer(FTree.Indent) - FTree.OffsetX;
end;

function TLibraryTree.CounterText(Index: Integer): string;
var
  N: TLibraryNode;
begin
  N := FNodes[Index];
  if N.Count <= 0 then
    Exit('');
  case N.Kind of
    lnModule:           Result := L('library.chapters', [N.Count]);
    lnBibleTranslation: Result := L('library.bibleBooks', [N.Count]);
    lnBibleBook:        Result := L('library.bibleChapters', [N.Count]);
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
  R: TRect;
begin
  Index := IndexOf(Node);
  if (Index < 0) or (Index > High(FNodes)) then
    Exit;
  // CellRect includes the indent with the expand button - not painted over.
  R := Rect(ContentLeft(Node), CellRect.Top, Sender.ClientWidth, CellRect.Bottom);
  PaintRow(TargetCanvas, Node, Index, R);
end;

procedure TLibraryTree.PaintRow(Canvas: TCanvas; Node: PVirtualNode; Index: Integer; const R: TRect);
var
  N: TLibraryNode;
  Hot, Current, Dot: Boolean;
  X, Right, CenterY, W: Integer;
  TextR, Box: TRect;
  Text, Counter: string;

  procedure UseFont(SizePx: Integer; Style: TFontStyles; Color: TColor);
  begin
    Canvas.Font.Name := FFontName;
    Canvas.Font.Height := -Px(SizePx);
    Canvas.Font.Style := Style;
    Canvas.Font.Color := Color;
  end;

  procedure DrawLine(const S: string; Left, Right: Integer; Flags: Cardinal);
  begin
    TextR := Rect(Left, R.Top, Right, R.Bottom);
    Winapi.Windows.DrawText(Canvas.Handle, PChar(S), Length(S), TextR,
      DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS or Flags);
  end;

begin
  N := FNodes[Index];
  Hot := (Node = FTree.HotNode) or ((Node = FTree.FocusedNode) and FTree.Focused);
  CenterY := (R.Top + R.Bottom) div 2;
  Right := R.Right - Px(RowPadRight);

  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ColorBackground;
  Canvas.FillRect(R);
  if Hot and not (N.Kind in [lnCategory, lnSeries]) then
    PaintRoundRect(Canvas, Rect(R.Left, R.Top + 1, R.Right - Px(2), R.Bottom - 1),
      Px(6), ColorRowHover, clNone);
  Canvas.Brush.Style := bsClear;

  case N.Kind of
    lnCategory, lnSeries:
      begin
        if N.Kind = lnCategory then
          Text := L(N.CaptionKey).ToUpper
        else
          Text := N.Caption.ToUpper;
        UseFont(GroupPx, [fsBold], ColorMuted);
        X := R.Left + Px(2);
        DrawLine(Text, X, Right, DT_LEFT);
        if N.Kind = lnCategory then
        begin
          W := X + Canvas.TextWidth(Text) + Px(8);
          if W < Right then
          begin
            Canvas.Brush.Style := bsSolid;
            Canvas.Brush.Color := ColorGroupLine;
            Canvas.FillRect(Rect(W, CenterY, Right, CenterY + 1));
          end;
        end;
      end;

    lnModule, lnBibleTranslation, lnBibleBook:
      begin
        X := R.Left;
        if HasCheckBox(Index) then
        begin
          Box.Left := X + (Px(CheckZone) - Px(CheckBoxPx)) div 2;
          Box.Top := CenterY - Px(CheckBoxPx) div 2;
          Box.Right := Box.Left + Px(CheckBoxPx);
          Box.Bottom := Box.Top + Px(CheckBoxPx);
          PaintCheckBox(Canvas, Box, FChecked[Index], Px(CheckInnerPx));
          X := X + Px(CheckZone) + Px(4);
        end
        else
          X := X + Px(4);

        Current := IsAncestorOfActive(Index);
        Dot := Current and not FTree.Expanded[Node];

        // The counter and the dot from the right; the title takes the rest.
        Counter := CounterText(Index);
        if Counter <> '' then
        begin
          UseFont(CounterPx, [], ColorMarker);
          W := Canvas.TextWidth(Counter);
          DrawLine(Counter, Right - W, Right, DT_RIGHT);
          Right := Right - W - Px(6);
        end;
        if Dot then
        begin
          PaintDot(Canvas, Right - Px(DotPx) div 2 - Px(1), CenterY, Px(DotPx), ColorAccent);
          Right := Right - Px(DotPx) - Px(8);
        end;

        if Current then
          UseFont(BookPx, [fsBold], ColorCurrentText)
        else if Hot then
          UseFont(BookPx, [], ColorAccent)
        else
          UseFont(BookPx, [], ColorBookText);
        Canvas.Brush.Style := bsClear;
        DrawLine(N.Caption, X, Right, DT_LEFT);
      end;

    lnChapter:
      begin
        X := R.Left + Px(4);
        if Index = FActive then
        begin
          PaintDot(Canvas, Right - Px(DotPx) div 2 - Px(1), CenterY, Px(DotPx), ColorAccent);
          Right := Right - Px(DotPx) - Px(8);
        end;
        Canvas.Brush.Style := bsClear;
        if N.BookCode <> '' then
        begin
          // A Bible chapter: only its number.
          if Index = FActive then
            UseFont(ChapterPx, [], ColorCurrentText)
          else
            UseFont(ChapterPx, [], ColorChapterText);
          DrawLine(N.Caption, X, Right, DT_LEFT);
        end
        else
        begin
          UseFont(CounterPx, [], ColorMarker);
          DrawLine(IntToStr(N.ChapterOrder), X, X + Px(NumberColumn), DT_RIGHT);
          X := X + Px(NumberColumn) + Px(NumberGap);
          if Index = FActive then
            UseFont(ChapterPx, [], ColorCurrentText)
          else if Hot then
            UseFont(ChapterPx, [], ColorCurrentText)
          else
            UseFont(ChapterPx, [], ColorChapterText);
          DrawLine(N.Caption, X, Right, DT_LEFT);
        end;
      end;
  end;
end;

{ input }

function TLibraryTree.InCheckZone(Node: PVirtualNode; X: Integer): Boolean;
var
  Index, Left: Integer;
begin
  Index := IndexOf(Node);
  Result := (Index >= 0) and HasCheckBox(Index);
  if not Result then
    Exit;
  Left := ContentLeft(Node);
  Result := (X >= Left) and (X < Left + Px(CheckZone));
end;

procedure TLibraryTree.ToggleCheck(Index: Integer);
begin
  FChecked[Index] := not FChecked[Index];
  FTree.InvalidateNode(FTreeNodes[Index]);
  if Assigned(FOnCheck) then
    FOnCheck(FNodes[Index], FChecked[Index]);
end;

procedure TLibraryTree.Activate(Node: PVirtualNode);
var
  Index: Integer;
begin
  Index := IndexOf(Node);
  if Index < 0 then
    Exit;
  case FNodes[Index].Kind of
    lnCategory, lnSeries:
      FTree.Expanded[Node] := not FTree.Expanded[Node];
    lnModule, lnBibleTranslation, lnBibleBook:
      FTree.Expanded[Node] := True;            // A.3: the book opens in the tree and as Toc
  end;
  if Assigned(FOnActivate) then
    FOnActivate(FNodes[Index]);
end;

procedure TLibraryTree.TreeNodeClick(Sender: TBaseVirtualTree; const HitInfo: THitInfo);
var
  P: TPoint;
begin
  // The expand button does its own job, nothing else.
  if (HitInfo.HitNode = nil) or (hiOnItemButton in HitInfo.HitPositions) then
    Exit;
  P := FTree.ScreenToClient(Mouse.CursorPos);
  if InCheckZone(HitInfo.HitNode, P.X) then
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
        if (Index >= 0) and HasCheckBox(Index) then
        begin
          ToggleCheck(Index);
          Key := 0;
        end;
      end;
  end;
end;

// The dot moves between a collapsed book and its open chapter.
procedure TLibraryTree.TreeCollapsedOrExpanded(Sender: TBaseVirtualTree; Node: PVirtualNode);
begin
  Sender.InvalidateNode(Node);
end;

end.
