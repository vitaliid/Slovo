unit Shell.LibraryTree;

(* The library tree of the left panel (Slovo_04 A.3, C.5, E-02).

  A thin owner of one TVirtualStringTree. The tree is built ONCE from the flat
  TLibraryNode array of OnLibraryChanged (B-29): nodes are added in array order,
  the parent of each is an already added node. A VST node holds only the index
  into that array (NodeDataSize = SizeOf(Integer)) - no strings in the tree, so
  a language change is an Invalidate, never a rebuild (R4-12).

  Drawn as the mockup "Читання v2" (A.3): OnGetText returns '' and every row is
  painted in OnAfterCellPaint, so the tree never measures a row wider than the
  panel - long titles end with "…", no horizontal scrolling. VST's own indent
  and buttons are off (Indent 0): the geometry is the mockup's - a book row with
  the caret button at 2, the box at 30, the title at 62; its chapters a nested
  list 26 px in with a hairline on the left, the number in a 12 px column, the
  title 9 px after it, number and title on one baseline; a Bible book nests in
  its translation the same way. Row heights carry the mockup's margins.
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
    function IsBookLike(Index: Integer): Boolean;
    function BookDepth(Node: PVirtualNode): Integer;
    function RowLeft(Node: PVirtualNode): Integer;
    function RowBox(Node: PVirtualNode; Index: Integer; const R: TRect): TRect;
    function HasCheckBox(Index: Integer): Boolean;
    function InCheckZone(Node: PVirtualNode; X: Integer): Boolean;
    function InCaretZone(Node: PVirtualNode; X: Integer): Boolean;
    procedure TreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
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
  ChapterHeight       = 30;     // the 29 px row + gap 1
  ChapterRow          = 29;
  NestTop             = 2;      // the nested list: margin 2 0 8 26
  NestBottom          = 8;
  NestLine            = 26;     // its border-left, from the parent row's left
  NestStep            = 37;     // 26 + border 1 + padding 10: where nested rows start
  GroupX              = 8;      // caption padding 0 8
  CaretX              = 2;      // row padding-left 2
  ButtonPx            = 24;     // the caret and the box buttons
  CheckX              = 30;     // 2 + 24 + gap 4
  LabelX              = 62;     // 30 + 24 + gap 4 + label padding 4
  LabelNoCheckX       = 34;     // a Bible book has no box
  RowPadRight         = 8;
  ChapterPadX         = 9;
  NumberColumn        = 12;
  NumberGap           = 9;
  CaretPx             = 7;
  CheckBoxPx          = 14;
  CheckInnerPx        = 8;
  DotPx               = 5;
  GroupPx             = 11;     // mockup 10.5
  BookPx              = 14;     // mockup 13.5
  ChapterPx           = 13;     // mockup 12.5
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
  FirstCategory: Boolean;
begin
  FirstCategory := True;
  FNodes := Nodes;
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
      if Nodes[I].Parent < 0 then
        Parent := nil
      else
        Parent := FTreeNodes[Nodes[I].Parent];
      Node := FTree.AddChild(Parent);
      PInteger(FTree.GetNodeData(Node))^ := I;
      FTreeNodes[I] := Node;
      FChecked[I] := HasCheckBox(I) and Nodes[I].Checked;
    end;
    // Heights once all siblings are known: a nested list adds its margins to
    // its first and last row.
    for I := 0 to High(Nodes) do
    begin
      Node := FTreeNodes[I];
      case Nodes[I].Kind of
        lnCategory:
          begin
            if FirstCategory then
              H := FirstCategoryHeight
            else
              H := CategoryHeight;
            FirstCategory := False;
          end;
        lnSeries:                             H := SeriesHeight;
        lnModule, lnBibleTranslation, lnBibleBook: H := BookHeight;
      else
        H := ChapterHeight;
      end;
      H := Px(H);
      if BookDepth(Node) > 0 then
      begin
        if Node.PrevSibling = nil then
          Inc(H, Px(NestTop));
        if Node.NextSibling = nil then
          Inc(H, Px(NestBottom));
      end;
      FTree.NodeHeight[Node] := H;
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

function TLibraryTree.IsBookLike(Index: Integer): Boolean;
begin
  Result := FNodes[Index].Kind in [lnModule, lnBibleTranslation, lnBibleBook];
end;

// How many book-like rows (book, translation, Bible book) this row is nested in.
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
  if (BookDepth(Node) > 0) and (Node.PrevSibling = nil) then
    Inc(Result.Top, Px(NestTop));
  case FNodes[Index].Kind of
    lnModule, lnBibleTranslation, lnBibleBook: Result.Bottom := Result.Top + Px(BookRow);
    lnChapter:                                 Result.Bottom := Result.Top + Px(ChapterRow);
  end;
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
  X, Right, CenterY, W, Depth, K, LineX, Y1, Y2, Baseline: Integer;
  P: TPoint;
  Text, Counter: string;
  TM: TTextMetric;

  procedure UseFont(const Name: string; SizePx: Integer; Color: TColor);
  begin
    Canvas.Font.Name := Name;
    Canvas.Font.Height := -Px(SizePx);
    Canvas.Font.Style := [];
    Canvas.Font.Color := Color;
    SetTextCharacterExtra(Canvas.Handle, 0);
  end;

  procedure DrawIn(const S: string; Left, Top, Right, Bottom: Integer; Flags: Cardinal);
  begin
    TextR := Rect(Left, Top, Right, Bottom);
    Winapi.Windows.DrawText(Canvas.Handle, PChar(S), Length(S), TextR,
      DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS or Flags);
  end;

  // Mockup align-items: baseline - the text's baseline on Baseline.
  procedure DrawOnBaseline(const S: string; Left, Right: Integer; Flags: Cardinal);
  var
    M: TTextMetric;
  begin
    GetTextMetrics(Canvas.Handle, M);
    DrawIn(S, Left, Baseline - M.tmAscent, Right, Baseline - M.tmAscent + M.tmHeight, DT_TOP or Flags);
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
      if Node.PrevSibling = nil then
        Inc(Y1, Px(NestTop));
      if Node.NextSibling = nil then
        Dec(Y2, Px(NestBottom));
    end;
    Canvas.Brush.Color := ColorNestLine;
    Canvas.FillRect(Rect(LineX, Y1, LineX + 1, Y2));
  end;

  Box := RowBox(Node, Index, R);
  CenterY := (Box.Top + Box.Bottom) div 2;
  Right := R.Right - Px(RowPadRight);

  case N.Kind of
    lnCategory, lnSeries:
      begin
        if N.Kind = lnCategory then
          Text := L(N.CaptionKey).ToUpper
        else
          Text := N.Caption.ToUpper;
        // Mockup: 10.5 px, weight 600, letter-spacing .12em, 8 px above the
        // group's first row; a category has a hairline to the right.
        UseFont(UiFontSemiBoldName, GroupPx, ColorMuted);
        SetTracking(Canvas, 0.12);
        X := Box.Left + Px(GroupX);
        if N.Kind = lnCategory then
          B := Rect(X, R.Bottom - Px(CategoryBelow) - Px(CaptionLine), Right, R.Bottom - Px(CategoryBelow))
        else
          B := Rect(X, R.Bottom - Px(SeriesBelow) - Px(CaptionLine), Right, R.Bottom - Px(SeriesBelow));
        Canvas.Brush.Style := bsClear;
        DrawIn(Text, B.Left, B.Top, B.Right, B.Bottom, DT_VCENTER or DT_LEFT);
        if N.Kind = lnCategory then
        begin
          W := X + Canvas.TextWidth(Text) + Px(8);
          if W < Right then
          begin
            Y1 := (B.Top + B.Bottom) div 2;
            Canvas.Brush.Style := bsSolid;
            Canvas.Brush.Color := ColorGroupLine;
            Canvas.FillRect(Rect(W, Y1, Right, Y1 + 1));
          end;
        end;
        SetTextCharacterExtra(Canvas.Handle, 0);
      end;

    lnModule, lnBibleTranslation, lnBibleBook:
      begin
        if Hot then
          PaintRoundRect(Canvas, Rect(Box.Left, Box.Top, R.Right, Box.Bottom), Px(6), ColorRowHover, clNone);
        // The caret button 24 x 24: ▸ / ▾ #8a8a8a, its own hover.
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
        // The box "Шукати в цій книзі" (R4-41), in its 24 px button.
        if HasCheckBox(Index) then
        begin
          B.Left := Box.Left + Px(CheckX) + (Px(ButtonPx) - Px(CheckBoxPx)) div 2;
          B.Top := CenterY - Px(CheckBoxPx) div 2;
          B.Right := B.Left + Px(CheckBoxPx);
          B.Bottom := B.Top + Px(CheckBoxPx);
          PaintCheckBox(Canvas, B, FChecked[Index], Px(CheckInnerPx));
          X := Box.Left + Px(LabelX);
        end
        else
          X := Box.Left + Px(LabelNoCheckX);

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
        Canvas.Brush.Style := bsClear;
        DrawIn(N.Caption, X, Box.Top, Right, Box.Bottom, DT_VCENTER or DT_LEFT);
      end;

    lnChapter:
      begin
        if Hot then
          PaintRoundRect(Canvas, Rect(Box.Left, Box.Top, R.Right, Box.Bottom), Px(5), ColorRowHover, clNone);
        Right := R.Right - Px(ChapterPadX);
        X := Box.Left + Px(ChapterPadX);
        // One baseline for the number and the title: the title's, centred.
        UseFont(FFontName, ChapterPx, ColorChapterText);
        GetTextMetrics(Canvas.Handle, TM);
        Baseline := CenterY - TM.tmHeight div 2 + TM.tmAscent;
        if Index = FActive then
        begin
          // Mockup: the dot at the end, margin-bottom 3 over the baseline.
          PaintDot(Canvas, Right - Px(DotPx) div 2, Baseline - Px(3) - Px(DotPx) div 2,
            Px(DotPx), ColorAccent);
          Right := Right - Px(DotPx) - Px(NumberGap);
        end;
        Canvas.Brush.Style := bsClear;
        if N.BookCode = '' then
        begin
          UseFont(FFontName, CounterPx, ColorMarker);
          // Right-aligned in the 12 px column; wider numbers grow to the left.
          DrawOnBaseline(IntToStr(N.ChapterOrder), X + Px(NumberColumn) - Px(32), X + Px(NumberColumn), DT_RIGHT);
          X := X + Px(NumberColumn) + Px(NumberGap);
        end;
        // A Bible chapter has only its number as the title.
        if (Index = FActive) or Hot then
          UseFont(FFontName, ChapterPx, ColorCurrentText)
        else
          UseFont(FFontName, ChapterPx, ColorChapterText);
        DrawOnBaseline(N.Caption, X, Right, DT_LEFT);
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
  Left := RowLeft(Node) + Px(CheckX);
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

// The caret has its own hover inside the hot row: repaint it as the mouse moves.
procedure TLibraryTree.TreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if FTree.HotNode <> nil then
    FTree.InvalidateNode(FTree.HotNode);
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
