unit Shell.LibraryTree;

(* The library tree of the left panel (Slovo_04 A.3, C.5, E-02).

  A thin owner of one TVirtualStringTree. The tree is built ONCE from the flat
  TLibraryNode array of OnLibraryChanged (B-29): nodes are added in array order,
  the parent of each is an already added node. A VST node holds only the index
  into that array (NodeDataSize = SizeOf(Integer)) - no strings in the tree, so
  a language change is an Invalidate, never a rebuild (R4-12).

  This step draws with the standard VST look: standard check boxes on books and
  translations (R4-41: no cascade, no tri-state), the counter as VST static text.
  The mockup drawing (A.3) replaces the painting later; this API stays.

  The form decides what a click means (ViewModel calls); the tree only reports
  which node was activated or checked. *)

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Graphics,
  VirtualTrees,
  VirtualTrees.Types,
  VirtualTrees.BaseTree,
  Core.Domain,
  Presentation.MainViewModel;

type
  TLibraryNodeEvent = reference to procedure(const Node: TLibraryNode);
  TLibraryCheckEvent = reference to procedure(const Node: TLibraryNode; Checked: Boolean);

  TLibraryTree = class
  private
    FTree: TVirtualStringTree;
    FNodes: TArray<TLibraryNode>;
    FTreeNodes: TArray<PVirtualNode>;          // index in FNodes -> VST node
    FActive: Integer;                          // the chapter being read; -1 = none
    FBuilding: Boolean;
    FOnActivate: TLibraryNodeEvent;
    FOnCheck: TLibraryCheckEvent;

    function IndexOf(Node: PVirtualNode): Integer;
    function IsAncestorOfActive(Index: Integer): Boolean;
    procedure InvalidatePath(Index: Integer);
    procedure Activate(Node: PVirtualNode);

    procedure TreeGetText(Sender: TBaseVirtualTree; Node: PVirtualNode; Column: TColumnIndex;
      TextType: TVSTTextType; var CellText: string);
    procedure TreePaintText(Sender: TBaseVirtualTree; const TargetCanvas: TCanvas;
      Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType);
    procedure TreeNodeClick(Sender: TBaseVirtualTree; const HitInfo: THitInfo);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeChecked(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure TreeCollapsedOrExpanded(Sender: TBaseVirtualTree; Node: PVirtualNode);
  public
    constructor Create(AOwner: TComponent; AParent: TWinControl);
    // The VST belongs to AOwner and outlives this object while the form is
    // destroyed: its events are detached here so none reaches freed code.
    destructor Destroy; override;

    // OnLibraryChanged: the whole tree, once. Categories start expanded.
    procedure Build(const Nodes: TArray<TLibraryNode>);
    // After a chapter is loaded: the dot "читаю" moves, the path opens (R4-43).
    procedure SetActive(const Position: TReadingPosition);
    // The language changed: texts come from L() in OnGetText.
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
  ActiveMark = '•';

{ TLibraryTree }

constructor TLibraryTree.Create(AOwner: TComponent; AParent: TWinControl);
begin
  inherited Create;
  FActive := -1;
  FTree := TVirtualStringTree.Create(AOwner);
  FTree.Parent := AParent;
  FTree.Align := alClient;
  FTree.BorderStyle := bsNone;
  FTree.NodeDataSize := SizeOf(Integer);
  FTree.DefaultNodeHeight := 26;           // 96-DPI pixels; VST scales it itself (E-14)
  FTree.Color := ColorBackground;
  FTree.TreeOptions.MiscOptions := FTree.TreeOptions.MiscOptions + [toCheckSupport] - [toEditable];
  FTree.TreeOptions.PaintOptions := FTree.TreeOptions.PaintOptions - [toShowTreeLines]
    + [toHideFocusRect];
  FTree.TreeOptions.SelectionOptions := FTree.TreeOptions.SelectionOptions + [toFullRowSelect];
  FTree.TreeOptions.StringOptions := FTree.TreeOptions.StringOptions + [toShowStaticText];
  FTree.OnGetText := TreeGetText;
  FTree.OnPaintText := TreePaintText;
  FTree.OnNodeClick := TreeNodeClick;
  FTree.OnKeyDown := TreeKeyDown;
  FTree.OnChecked := TreeChecked;
  FTree.OnExpanded := TreeCollapsedOrExpanded;
  FTree.OnCollapsed := TreeCollapsedOrExpanded;
end;

destructor TLibraryTree.Destroy;
begin
  FTree.OnGetText := nil;
  FTree.OnPaintText := nil;
  FTree.OnNodeClick := nil;
  FTree.OnKeyDown := nil;
  FTree.OnChecked := nil;
  FTree.OnExpanded := nil;
  FTree.OnCollapsed := nil;
  inherited;
end;

procedure TLibraryTree.ApplyFont(const FontName: string);
begin
  FTree.Font.Name := FontName;
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

procedure TLibraryTree.Build(const Nodes: TArray<TLibraryNode>);
var
  I: Integer;
  Parent, Node: PVirtualNode;
begin
  FNodes := Nodes;
  SetLength(FTreeNodes, Length(Nodes));
  FActive := -1;
  FBuilding := True;                       // setting CheckState fires OnChecked
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
      if Nodes[I].Kind in [lnModule, lnBibleTranslation] then
      begin
        FTree.CheckType[Node] := ctCheckBox;
        if Nodes[I].Checked then
          FTree.CheckState[Node] := csCheckedNormal;
      end;
    end;
    for I := 0 to High(Nodes) do
      if Nodes[I].Kind = lnCategory then
        FTree.Expanded[FTreeNodes[I]] := True;
  finally
    FTree.EndUpdate;
    FBuilding := False;
  end;
end;

function TLibraryTree.CheckedCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FTreeNodes) do
    if FTree.CheckState[FTreeNodes[I]] = csCheckedNormal then
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

{ events }

procedure TLibraryTree.TreeGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
  Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
var
  Index: Integer;
  N: TLibraryNode;
  Counter: string;
begin
  Index := IndexOf(Node);
  if Index < 0 then
    Exit;
  N := FNodes[Index];

  if TextType = ttNormal then
  begin
    case N.Kind of
      lnCategory: CellText := L(N.CaptionKey);
      lnChapter:
        if N.BookCode = '' then
          CellText := Format('%d · %s', [N.ChapterOrder, N.Caption])
        else
          CellText := N.Caption;              // a Bible chapter: its number
    else
      CellText := N.Caption;
    end;
    Exit;
  end;

  // ttStatic: the counter (E-09) and the dot "читаю" - on the chapter itself, or
  // on a collapsed node that hides it (A.3).
  case N.Kind of
    lnModule:           Counter := L('library.chapters', [N.Count]);
    lnBibleTranslation: Counter := L('library.bibleBooks', [N.Count]);
    lnBibleBook:        Counter := L('library.bibleChapters', [N.Count]);
  else
    Counter := '';
  end;
  if (Index = FActive) or (not Sender.Expanded[Node] and IsAncestorOfActive(Index)) then
    if Counter = '' then
      Counter := ActiveMark
    else
      Counter := ActiveMark + '  ' + Counter;
  CellText := Counter;
end;

procedure TLibraryTree.TreePaintText(Sender: TBaseVirtualTree; const TargetCanvas: TCanvas;
  Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType);
var
  Index: Integer;
begin
  Index := IndexOf(Node);
  if Index < 0 then
    Exit;
  if TextType = ttStatic then
  begin
    TargetCanvas.Font.Color := ColorMuted;
    Exit;
  end;
  if FNodes[Index].Kind = lnCategory then
    TargetCanvas.Font.Style := [fsBold];
  if Index = FActive then
    TargetCanvas.Font.Color := ColorAccent;
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
begin
  // The expand button and the check box do their own job, nothing else.
  if (HitInfo.HitNode = nil) or (hiOnItemButton in HitInfo.HitPositions) or
    (hiOnItemCheckbox in HitInfo.HitPositions) then
    Exit;
  Activate(HitInfo.HitNode);
end;

procedure TLibraryTree.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = vkReturn) and (FTree.FocusedNode <> nil) then
  begin
    Activate(FTree.FocusedNode);
    Key := 0;
  end;
end;

procedure TLibraryTree.TreeChecked(Sender: TBaseVirtualTree; Node: PVirtualNode);
var
  Index: Integer;
begin
  if FBuilding then
    Exit;
  Index := IndexOf(Node);
  if (Index >= 0) and Assigned(FOnCheck) then
    FOnCheck(FNodes[Index], Sender.CheckState[Node] = csCheckedNormal);
end;

// The dot moves between a collapsed book and its open chapter.
procedure TLibraryTree.TreeCollapsedOrExpanded(Sender: TBaseVirtualTree; Node: PVirtualNode);
begin
  Sender.InvalidateNode(Node);
end;

end.
