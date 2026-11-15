unit Shell.SearchResults;

(* The search result list of the right panel (Slovo_04 A.4, C.5; R4-37; E-18,
  E-19, E-20; B-34).

  One VirtualStringTree over a TSearchResultsModel (Presentation.SearchResults):
    section "Книги" / "Біблія"        - a root node with the expand button;
    block (a book, a translation)     - a node with the button, its caption and
                                        the number of its matches;
    heading (a chapter, a Bible book) - a row that does not fold;
    match                             - the reference line (10.5 px, muted) and
                                        the snippet in two lines of EB Garamond
                                        15.5 px, the matches bold #2f5f95.
  By books (soText) a match is one line, as in a concordance (Vitalii,
  2026-11-16): the book and the chapter stand above, so there is no reference
  line; the page "71.2" / the verse "22:8" stands small on the right. When the
  match itself would not fit on the line, the words before it give way.

  The rows of a block stand in line with its caption, the rows of a flat
  section - with the section's caption: nothing is left of its parent.
  A block without a caption (the books by relevance) has no node: its rows
  stand right under the section.

  The tree knows the number of rows of every block from the model; the text of
  a match is asked for only when its row is painted - the model reads it in
  windows (B-34). Everything is painted in OnAfterCellPaint (OnGetText = '').

  The result that was opened stays marked (E-18) wherever the focus goes: the
  accent bar on the left and a tint of the accent. The results opened before
  it are dimmed, as visited links. Both live until the list is shown again.

  The pinned line (E-19): the block and the heading of the topmost row, for the
  form to show over the list - found again after every paint.

  SaveState / RestoreState (Vitalii, 2026-11-15): what the reader did to the
  list - folded blocks, the scroll position, the opened results - so that a
  switch of the view and back finds the list as it was left. *)

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
  Presentation.SearchResults;

type
  TResultOpenEvent = reference to procedure(Section: TResultSectionKind; const Line: TResultLine);
  TSectionCaptionFunc = reference to function(Section: TResultSectionKind): string;
  TResultScaleFunc = reference to function(Value: Integer): Integer;

  // A node of the list by its place in the model; Block = -1 - the section
  // itself, Row = -1 - the block itself.
  TResultRowKey = record
    Part, Block, Row: Integer;
  end;

  // What the reader did to a shown list. Good only for a list of the same
  // search in the same view.
  TResultListState = record
    Valid: Boolean;
    OffsetY: Integer;
    Folded: TArray<TResultRowKey>;             // sections and blocks
    Visited: TArray<TResultRowKey>;
    HasCurrent: Boolean;
    Current: TResultRowKey;
  end;

  TSearchResultList = class
  private
    FTree: TVirtualStringTree;
    FModel: TSearchResultsModel;               // not owned; nil = nothing to show
    FTextFont: string;
    FUiFont: string;
    FScale: TResultScaleFunc;
    FSectionCaption: TSectionCaptionFunc;
    FOnOpen: TResultOpenEvent;
    FOnPinnedChanged: TProc;
    FOnFoldChanged: TProc;
    FCurrent: PVirtualNode;                    // the open result; nil = none
    FVisited: TArray<TResultRowKey>;           // in the order they were opened
    FBulk: Boolean;                            // folding many nodes: no OnFoldChanged
    FPinned: string;

    function Px(Value: Integer): Integer;
    function IsFlat(Part: Integer): Boolean;
    function Compact: Boolean;
    function RowLeft(Node: PVirtualNode): Integer;
    function HitHeight: Integer;
    procedure Locate(Part, Index: Integer; out Block, Row: Integer);
    function KeyOf(Node: PVirtualNode): TResultRowKey;
    function NodeOf(const Key: TResultRowKey): PVirtualNode;
    procedure TreeFoldChanged(Sender: TBaseVirtualTree; Node: PVirtualNode);
    function TopPinnedText: string;
    procedure UpdatePinned;
    procedure Open(Node: PVirtualNode);
    procedure TreeInitNode(Sender: TBaseVirtualTree; ParentNode, Node: PVirtualNode;
      var InitialStates: TVirtualNodeInitStates);
    procedure TreeInitChildren(Sender: TBaseVirtualTree; Node: PVirtualNode; var ChildCount: Cardinal);
    procedure TreeGetText(Sender: TBaseVirtualTree; Node: PVirtualNode; Column: TColumnIndex;
      TextType: TVSTTextType; var CellText: string);
    procedure TreeAfterCellPaint(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
      Node: PVirtualNode; Column: TColumnIndex; CellRect: TRect);
    procedure TreeAfterPaint(Sender: TBaseVirtualTree; TargetCanvas: TCanvas);
    procedure TreeNodeClick(Sender: TBaseVirtualTree; const HitInfo: THitInfo);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure PaintRow(Canvas: TCanvas; const Row: TResultLine; const R: TRect; Visited: Boolean);
  public
    constructor Create(AOwner: TComponent; AParent: TWinControl; const Scale: TResultScaleFunc);
    destructor Destroy; override;

    // The model belongs to the caller and must outlive the list's use of it:
    // Show(another) or Clear before it is freed.
    procedure Show(Model: TSearchResultsModel);
    procedure Clear;
    // The blocks (books, translations) folded to their captions, or all open again.
    procedure CollapseAll;
    procedure ExpandAll;
    function HasBlocks: Boolean;
    function AllCollapsed: Boolean;            // there are blocks and every one is folded
    function SaveState: TResultListState;
    procedure RestoreState(const State: TResultListState);
    procedure ApplyFonts(const TextFont, UiFont: string);
    procedure Invalidate;

    property Control: TVirtualStringTree read FTree;
    property PinnedText: string read FPinned;
    property SectionCaption: TSectionCaptionFunc read FSectionCaption write FSectionCaption;
    property OnOpen: TResultOpenEvent read FOnOpen write FOnOpen;
    property OnPinnedChanged: TProc read FOnPinnedChanged write FOnPinnedChanged;
    // The reader folded or unfolded a section or a block by its button.
    property OnFoldChanged: TProc read FOnFoldChanged write FOnFoldChanged;
  end;

implementation

uses
  System.UITypes,
  System.Math,
  Presentation.Theme,
  Shell.FlatControls;

type
  TNodeKind = (nkSection, nkBlock, nkHeading, nkHit);
  // Block = -1 / Row = -1 for the upper levels.
  TNodeData = record
    Kind: TNodeKind;
    Part, Block, Row: Integer;
    Visited: Boolean;                          // nkHit: was opened since the list was shown
  end;
  PNodeData = ^TNodeData;

const
  RowHeight     = 74;     // 6 + ref 14 + 2 + 2 x 23 + 6: tighter than the mockup's 88 (Vitalii, 2026-11-15)
  CompactHeight = 33;     // by books: 5 + one line 23 + 5, no reference line
  CompactPadY   = 5;
  RefGap        = 10;     // between the first line of the snippet and the page on its right
  RowGap        = 2;      // the list's gap
  RowRadius     = 8;
  AccentWidth   = 2;      // border-left 2px, transparent until hover
  BottomPadding = 60;     // aside padding-bottom
  HeaderHeight  = 30;
  HeadingHeight = 30;     // a chapter / a Bible book over its matches
  RowPadX       = 13;
  RowPadY       = 6;
  RefLine       = 14;     // the reference line
  RefSnippetGap = 2;
  RefPx         = 11;     // mockup 10.5 px
  SnippetPx     = 16;     // mockup 15.5 px
  SnippetLine   = 23;     // line-height 1.5
  SectionPx     = 11;
  GroupPx       = 12;
  HeadingPx     = 12;
  CountPx       = 11;
  ColorRowHover = TColor($00F2F2F2);   // rgba(0,0,0,.04) on #fcfcfc
  ColorSnippet  = TColor($003F3F3F);   // #3f3f3f
  ColorRowCurrent  = TColor($00F5F1ED);   // the accent #3c6ea8 at .08 on #fcfcfc
  ColorVisited     = TColor($006E6E6E);   // #6e6e6e: the snippet of an opened result
  ColorVisitedRef  = TColor($008F8F8F);   // #8f8f8f: its reference line
  ColorVisitedHit  = TColor($00B3845F);   // #5f84b3: its matches, the accent faded

{ TSearchResultList }

constructor TSearchResultList.Create(AOwner: TComponent; AParent: TWinControl;
  const Scale: TResultScaleFunc);
begin
  inherited Create;
  FScale := Scale;
  FTextFont := TextFontName;
  FUiFont := UiFontName;

  FTree := TVirtualStringTree.Create(AOwner);
  FTree.Parent := AParent;
  FTree.Align := alClient;
  FTree.BorderStyle := bsNone;
  FTree.Color := ColorBackground;
  FTree.NodeDataSize := SizeOf(TNodeData);
  // toAutoChangeScale would reset row heights to the font height (see Shell.ChapterList).
  FTree.TreeOptions.AutoOptions := FTree.TreeOptions.AutoOptions - [toAutoChangeScale];
  FTree.DefaultNodeHeight := Px(HeaderHeight);
  FTree.Indent := Px(14);
  FTree.Margin := 0;
  FTree.TextMargin := 0;
  FTree.TreeOptions.PaintOptions := FTree.TreeOptions.PaintOptions
    - [toShowTreeLines, toUseExplorerTheme]
    + [toShowRoot, toShowButtons, toHideFocusRect, toHotTrack, toAlwaysHideSelection];
  FTree.TreeOptions.SelectionOptions := FTree.TreeOptions.SelectionOptions + [toFullRowSelect];
  FTree.TreeOptions.MiscOptions := FTree.TreeOptions.MiscOptions - [toEditable];
  FTree.OnInitNode := TreeInitNode;
  FTree.OnInitChildren := TreeInitChildren;
  FTree.OnGetText := TreeGetText;
  FTree.OnAfterCellPaint := TreeAfterCellPaint;
  FTree.OnAfterPaint := TreeAfterPaint;
  FTree.OnCollapsed := TreeFoldChanged;
  FTree.OnExpanded := TreeFoldChanged;
  FTree.OnNodeClick := TreeNodeClick;
  FTree.OnKeyDown := TreeKeyDown;
end;

destructor TSearchResultList.Destroy;
begin
  // The control belongs to the form and outlives this object.
  FTree.OnInitNode := nil;
  FTree.OnInitChildren := nil;
  FTree.OnGetText := nil;
  FTree.OnAfterCellPaint := nil;
  FTree.OnAfterPaint := nil;
  FTree.OnCollapsed := nil;
  FTree.OnExpanded := nil;
  FTree.OnNodeClick := nil;
  FTree.OnKeyDown := nil;
  inherited;
end;

function TSearchResultList.Px(Value: Integer): Integer;
begin
  Result := FScale(Value);
end;

procedure TSearchResultList.ApplyFonts(const TextFont, UiFont: string);
begin
  FTextFont := TextFont;
  FUiFont := UiFont;
  FTree.Font.Name := UiFont;
  FTree.Invalidate;
end;

procedure TSearchResultList.Invalidate;
begin
  FTree.Invalidate;
end;

procedure TSearchResultList.Clear;
begin
  Show(nil);
end;

procedure TSearchResultList.Show(Model: TSearchResultsModel);
begin
  FModel := Model;
  FCurrent := nil;
  FVisited := nil;
  FBulk := True;
  FTree.BeginUpdate;
  try
    FTree.Clear;
    // Not in the constructor: VST looks for its bottom node (see Shell.LibraryTree).
    FTree.BottomSpace := Px(BottomPadding);
    if Model <> nil then
      FTree.RootNodeCount := Length(Model.Parts);
    FTree.FullExpand;
  finally
    FTree.EndUpdate;
    FBulk := False;
  end;
  FTree.OffsetY := 0;
  UpdatePinned;
end;

// By books a match has no reference line: its book and chapter stand above it.
function TSearchResultList.Compact: Boolean;
begin
  Result := (FModel <> nil) and (FModel.Order = soText);
end;

// Where a heading or a match starts, from the cell's left: its text stands in
// line with the caption of what it belongs to (the block; in a flat section -
// the section), the hover box - the padding to the left of that.
function TSearchResultList.RowLeft(Node: PVirtualNode): Integer;
begin
  Result := Integer(FTree.GetNodeLevel(Node)) * Integer(FTree.Indent) + Px(2) - Px(AccentWidth + RowPadX);
  if Result < 0 then
    Result := 0;
end;

function TSearchResultList.HitHeight: Integer;
begin
  if Compact then
    Result := Px(CompactHeight)
  else
    Result := Px(RowHeight);
end;

// The books by relevance: blocks without a caption, their rows right under the section.
function TSearchResultList.IsFlat(Part: Integer): Boolean;
begin
  Result := (Length(FModel.Parts[Part].Blocks) > 0) and (FModel.Parts[Part].Blocks[0].Caption = '');
end;

// A flat section: the child of the section -> the block and its row.
procedure TSearchResultList.Locate(Part, Index: Integer; out Block, Row: Integer);
var
  I: Integer;
begin
  Block := 0;
  Row := Index;
  for I := 0 to High(FModel.Parts[Part].Blocks) do
  begin
    Block := I;
    if Row < FModel.Parts[Part].Blocks[I].RowCount then
      Exit;
    if I < High(FModel.Parts[Part].Blocks) then
      Dec(Row, FModel.Parts[Part].Blocks[I].RowCount);
  end;
end;

function TSearchResultList.HasBlocks: Boolean;
var
  I: Integer;
begin
  Result := False;
  if FModel <> nil then
    for I := 0 to High(FModel.Parts) do
      if not IsFlat(I) then
        Exit(True);
end;

procedure TSearchResultList.CollapseAll;
var
  Section, Child: PVirtualNode;
  Data: PNodeData;
begin
  FBulk := True;
  FTree.BeginUpdate;
  try
    Section := FTree.GetFirst;
    while Section <> nil do
    begin
      Child := FTree.GetFirstChild(Section);
      while Child <> nil do
      begin
        Data := FTree.GetNodeData(Child);
        if Data.Kind = nkBlock then
          FTree.Expanded[Child] := False;
        Child := FTree.GetNextSibling(Child);
      end;
      Section := FTree.GetNextSibling(Section);
    end;
  finally
    FTree.EndUpdate;
    FBulk := False;
  end;
  FTree.OffsetY := 0;
  UpdatePinned;
end;

procedure TSearchResultList.ExpandAll;
begin
  FBulk := True;
  FTree.BeginUpdate;
  try
    FTree.FullExpand;
  finally
    FTree.EndUpdate;
    FBulk := False;
  end;
  UpdatePinned;
end;

function TSearchResultList.AllCollapsed: Boolean;
var
  Section, Child: PVirtualNode;
  Data: PNodeData;
begin
  Result := False;
  Section := FTree.GetFirst;
  while Section <> nil do
  begin
    Child := FTree.GetFirstChild(Section);
    while Child <> nil do
    begin
      Data := FTree.GetNodeData(Child);
      if Data.Kind = nkBlock then
      begin
        if FTree.Expanded[Child] then
          Exit(False);
        Result := True;
      end;
      Child := FTree.GetNextSibling(Child);
    end;
    Section := FTree.GetNextSibling(Section);
  end;
end;

procedure TSearchResultList.TreeFoldChanged(Sender: TBaseVirtualTree; Node: PVirtualNode);
begin
  if not FBulk and Assigned(FOnFoldChanged) then
    FOnFoldChanged();
end;

function TSearchResultList.KeyOf(Node: PVirtualNode): TResultRowKey;
var
  Data: PNodeData;
begin
  Data := FTree.GetNodeData(Node);
  Result.Part := Data.Part;
  Result.Block := Data.Block;
  Result.Row := Data.Row;
end;

// The node of a key, nil when the list has no such place. Walks the siblings:
// used for the few nodes of a saved state, not for painting.
function TSearchResultList.NodeOf(const Key: TResultRowKey): PVirtualNode;

  function Child(Parent: PVirtualNode; Index: Integer): PVirtualNode;
  begin
    if Parent = nil then
      Result := FTree.GetFirst
    else
      Result := FTree.GetFirstChild(Parent);
    while (Result <> nil) and (Index > 0) do
    begin
      Result := FTree.GetNextSibling(Result);
      Dec(Index);
    end;
  end;

var
  I, Index: Integer;
begin
  Result := nil;
  if (FModel = nil) or (Key.Part < 0) or (Key.Part > High(FModel.Parts)) then
    Exit;
  Result := Child(nil, Key.Part);
  if (Result = nil) or (Key.Block < 0) then
    Exit;
  if Key.Block > High(FModel.Parts[Key.Part].Blocks) then
    Exit(nil);
  if IsFlat(Key.Part) then
  begin
    if Key.Row < 0 then
      Exit(nil);                             // a block without a caption has no node
    Index := Key.Row;
    for I := 0 to Key.Block - 1 do
      Inc(Index, FModel.Parts[Key.Part].Blocks[I].RowCount);
    Result := Child(Result, Index);
  end
  else
  begin
    Result := Child(Result, Key.Block);
    if (Result <> nil) and (Key.Row >= 0) then
      Result := Child(Result, Key.Row);
  end;
end;

function TSearchResultList.SaveState: TResultListState;
var
  Section, Child: PVirtualNode;
  Data: PNodeData;
begin
  Result := Default(TResultListState);
  if FModel = nil then
    Exit;
  Result.Valid := True;
  Result.OffsetY := FTree.OffsetY;
  Result.Visited := FVisited;
  Result.HasCurrent := FCurrent <> nil;
  if FCurrent <> nil then
    Result.Current := KeyOf(FCurrent);
  Section := FTree.GetFirst;
  while Section <> nil do
  begin
    if not FTree.Expanded[Section] then
      Result.Folded := Result.Folded + [KeyOf(Section)];
    Child := FTree.GetFirstChild(Section);
    while Child <> nil do
    begin
      Data := FTree.GetNodeData(Child);
      if (Data.Kind = nkBlock) and not FTree.Expanded[Child] then
        Result.Folded := Result.Folded + [KeyOf(Child)];
      Child := FTree.GetNextSibling(Child);
    end;
    Section := FTree.GetNextSibling(Section);
  end;
end;

// For a list just shown (everything unfolded, nothing opened).
procedure TSearchResultList.RestoreState(const State: TResultListState);
var
  Key: TResultRowKey;
  Node: PVirtualNode;
  Data: PNodeData;
begin
  if not State.Valid or (FModel = nil) then
    Exit;
  FBulk := True;
  FTree.BeginUpdate;
  try
    for Key in State.Visited do
    begin
      Node := NodeOf(Key);
      if Node = nil then
        Continue;
      Data := FTree.GetNodeData(Node);
      Data.Visited := True;
      FVisited := FVisited + [Key];
    end;
    if State.HasCurrent then
      FCurrent := NodeOf(State.Current);
    // Blocks before their sections: a folded section still keeps its blocks' state.
    for Key in State.Folded do
      if Key.Block >= 0 then
      begin
        Node := NodeOf(Key);
        if Node <> nil then
          FTree.Expanded[Node] := False;
      end;
    for Key in State.Folded do
      if Key.Block < 0 then
      begin
        Node := NodeOf(Key);
        if Node <> nil then
          FTree.Expanded[Node] := False;
      end;
  finally
    FTree.EndUpdate;
    FBulk := False;
  end;
  FTree.OffsetY := State.OffsetY;
  FTree.Invalidate;
  UpdatePinned;
end;

procedure TSearchResultList.TreeInitNode(Sender: TBaseVirtualTree; ParentNode, Node: PVirtualNode;
  var InitialStates: TVirtualNodeInitStates);
var
  Data, ParentData: PNodeData;
begin
  Data := Sender.GetNodeData(Node);
  Data.Visited := False;
  if (ParentNode = nil) or (FModel = nil) then
  begin
    Data.Kind := nkSection;
    Data.Part := Node.Index;
    Data.Block := -1;
    Data.Row := -1;
    InitialStates := InitialStates + [ivsHasChildren, ivsExpanded];
    Exit;
  end;

  ParentData := Sender.GetNodeData(ParentNode);
  Data.Part := ParentData.Part;
  if (ParentData.Kind = nkSection) and not IsFlat(Data.Part) then
  begin
    Data.Kind := nkBlock;
    Data.Block := Node.Index;
    Data.Row := -1;
    InitialStates := InitialStates + [ivsHasChildren, ivsExpanded];
    Exit;
  end;

  if ParentData.Kind = nkBlock then
  begin
    Data.Block := ParentData.Block;
    Data.Row := Node.Index;
  end
  else
    Locate(Data.Part, Node.Index, Data.Block, Data.Row);
  if FModel.IsHeading(Data.Part, Data.Block, Data.Row) then
  begin
    Data.Kind := nkHeading;
    Sender.NodeHeight[Node] := Px(HeadingHeight);
  end
  else
  begin
    Data.Kind := nkHit;
    Sender.NodeHeight[Node] := HitHeight + Px(RowGap);
  end;
end;

procedure TSearchResultList.TreeInitChildren(Sender: TBaseVirtualTree; Node: PVirtualNode;
  var ChildCount: Cardinal);
var
  Data: PNodeData;
  I, Count: Integer;
begin
  ChildCount := 0;
  Data := Sender.GetNodeData(Node);
  if (FModel = nil) or (Data.Part > High(FModel.Parts)) then
    Exit;
  case Data.Kind of
    nkSection:
      if IsFlat(Data.Part) then
      begin
        Count := 0;
        for I := 0 to High(FModel.Parts[Data.Part].Blocks) do
          Inc(Count, FModel.Parts[Data.Part].Blocks[I].RowCount);
        ChildCount := Count;
      end
      else
        ChildCount := Length(FModel.Parts[Data.Part].Blocks);
    nkBlock:
      ChildCount := FModel.Parts[Data.Part].Blocks[Data.Block].RowCount;
  end;
end;

procedure TSearchResultList.TreeGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
  Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
begin
  CellText := '';                            // everything is painted (C.5)
end;

procedure TSearchResultList.TreeAfterCellPaint(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
  Node: PVirtualNode; Column: TColumnIndex; CellRect: TRect);
var
  Data: PNodeData;
  R, TextR: TRect;
  Hot: Boolean;
  Fill: TColor;
  Text, Count: string;
  Line: TResultLine;
  W: Integer;
begin
  Data := Sender.GetNodeData(Node);
  if (Data = nil) or (FModel = nil) or (Data.Part > High(FModel.Parts)) then
    Exit;
  R := Rect(CellRect.Left, CellRect.Top, Sender.ClientWidth, CellRect.Bottom);
  // CellRect includes the indent, where VST draws the expand button of a
  // section or a block: their captions start after it (rows have no button
  // and keep the full width).
  if Data.Kind in [nkSection, nkBlock] then
    R.Left := CellRect.Left + Integer(Sender.GetNodeLevel(Node) + 1) * Integer(FTree.Indent)
  else
    R.Left := CellRect.Left + RowLeft(Node);
  Hot := (Node = Sender.HotNode) or ((Node = Sender.FocusedNode) and Sender.Focused);

  TargetCanvas.Brush.Style := bsSolid;
  TargetCanvas.Brush.Color := ColorBackground;
  // A section and a block keep the expand button VST has drawn left of R; a row
  // has none and is cleared from the cell's left.
  if Data.Kind in [nkSection, nkBlock] then
    TargetCanvas.FillRect(R)
  else
    TargetCanvas.FillRect(Rect(CellRect.Left, R.Top, R.Right, R.Bottom));

  case Data.Kind of
    nkSection, nkBlock:
      begin
        TargetCanvas.Brush.Style := bsClear;
        TextR := Rect(R.Left + Px(2), R.Top, R.Right - Px(4), R.Bottom);
        if Data.Kind = nkSection then
        begin
          if Assigned(FSectionCaption) then
            Text := FSectionCaption(FModel.Parts[Data.Part].Kind).ToUpper
          else
            Text := '';
          TargetCanvas.Font.Name := UiFontSemiBoldName;
          TargetCanvas.Font.Height := -Px(SectionPx);
          TargetCanvas.Font.Style := [];
          TargetCanvas.Font.Color := ColorMuted;
          SetTextCharacterExtra(TargetCanvas.Handle, Round(Px(SectionPx) * 0.1));
        end
        else
        begin
          // The number of matches of the book / translation, on the right.
          Count := IntToStr(FModel.Parts[Data.Part].Blocks[Data.Block].HitCount);
          TargetCanvas.Font.Name := FUiFont;
          TargetCanvas.Font.Height := -Px(CountPx);
          TargetCanvas.Font.Style := [];
          TargetCanvas.Font.Color := ColorMarker;
          W := TargetCanvas.TextWidth(Count);
          Winapi.Windows.DrawText(TargetCanvas.Handle, PChar(Count), Length(Count), TextR,
            DT_SINGLELINE or DT_VCENTER or DT_RIGHT or DT_NOPREFIX);
          TextR.Right := TextR.Right - W - Px(8);

          Text := FModel.Parts[Data.Part].Blocks[Data.Block].Caption;
          TargetCanvas.Font.Name := UiFontMediumName;
          TargetCanvas.Font.Height := -Px(GroupPx);
          TargetCanvas.Font.Style := [];
          TargetCanvas.Font.Color := ColorText;
        end;
        Winapi.Windows.DrawText(TargetCanvas.Handle, PChar(Text), Length(Text), TextR,
          DT_SINGLELINE or DT_VCENTER or DT_LEFT or DT_NOPREFIX or DT_END_ELLIPSIS);
        SetTextCharacterExtra(TargetCanvas.Handle, 0);
      end;
    nkHeading:
      begin
        // A chapter / a Bible book: in line with the text of its matches, on the
        // bottom of its row - closer to them than to the matches above.
        Text := FModel.Line(Data.Part, Data.Block, Data.Row).RefText;
        TargetCanvas.Brush.Style := bsClear;
        TargetCanvas.Font.Name := FUiFont;
        TargetCanvas.Font.Height := -Px(HeadingPx);
        TargetCanvas.Font.Style := [];
        TargetCanvas.Font.Color := ColorMuted;
        TextR := Rect(R.Left + Px(AccentWidth + RowPadX), R.Top, R.Right - Px(RowPadX), R.Bottom - Px(5));
        Winapi.Windows.DrawText(TargetCanvas.Handle, PChar(Text), Length(Text), TextR,
          DT_SINGLELINE or DT_BOTTOM or DT_LEFT or DT_NOPREFIX or DT_END_ELLIPSIS);
      end;
    nkHit:
      begin
        // Mockup: radius 8, hover rgba(0,0,0,.04) and border-left 2px of the
        // accent, which follows the rounding - the accent box with the hover
        // box over it 2 px in.
        TextR := Rect(R.Left, R.Top, R.Right, R.Top + HitHeight);
        // The open result keeps the bar and its own tint without hover and
        // without focus (E-18); the hover box is the mockup's.
        if Hot or (Node = FCurrent) then
        begin
          PaintRoundRect(TargetCanvas, TextR, Px(RowRadius), ColorAccent, clNone);
          if Node = FCurrent then
            Fill := ColorRowCurrent
          else
            Fill := ColorRowHover;
          PaintRoundRect(TargetCanvas, Rect(TextR.Left + Px(AccentWidth), TextR.Top, TextR.Right, TextR.Bottom),
            Px(RowRadius) - Px(AccentWidth) div 2, Fill, clNone);
        end;
        TargetCanvas.Brush.Style := bsClear;
        // Asked for here and nowhere earlier: the model reads the window of this
        // row when it is first painted (B-34). A row that could not be read is empty.
        Line := FModel.Line(Data.Part, Data.Block, Data.Row);
        if Line.Loaded then
          // The transparent border keeps the text 2 px in also without hover.
          PaintRow(TargetCanvas, Line,
            Rect(TextR.Left + Px(AccentWidth), TextR.Top, TextR.Right, TextR.Bottom),
            Data.Visited and (Node <> FCurrent));
      end;
  end;
end;

// Reference line, then the snippet word by word over two lines; what does not
// fit on the second line ends with an ellipsis. Visited: dimmed (E-18).
// Compact (by books): no reference line and one line of the snippet - the page /
// verse stands small on its right, and the line is that much shorter.
procedure TSearchResultList.PaintRow(Canvas: TCanvas; const Row: TResultLine; const R: TRect;
  Visited: Boolean);
var
  Left, Right, FirstRight, X, Y, Line, MaxLines, W, I, J: Integer;
  Runs: TArray<TTextRun>;
  TextR: TRect;
  Token: string;
  Run: TTextRun;
  Done: Boolean;

  procedure UseSnippetFont(Bold: Boolean);
  begin
    Canvas.Font.Name := FTextFont;
    Canvas.Font.Height := -Px(SnippetPx);
    if Bold then
    begin
      Canvas.Font.Style := [fsBold];
      if Visited then
        Canvas.Font.Color := ColorVisitedHit
      else
        Canvas.Font.Color := ColorAccentHover;
    end
    else
    begin
      Canvas.Font.Style := [];
      if Visited then
        Canvas.Font.Color := ColorVisited
      else
        Canvas.Font.Color := ColorSnippet;
    end;
  end;

  // One line only: when the first match would not fit on it, the words before
  // it give way - as many of the nearest ones stay as fit. No "…" in front
  // (Vitalii, 2026-11-16): a line that starts mid-sentence says so itself.
  function FitToMatch(const Source: TArray<TTextRun>; Width: Integer): TArray<TTextRun>;
  var
    B, K, P, MatchWidth: Integer;
    Lead: string;
    LeadRun: TTextRun;
  begin
    Result := Source;
    B := -1;
    for K := 0 to High(Source) do
      if Source[K].Bold then
      begin
        B := K;
        Break;
      end;
    if B <= 0 then
      Exit;                                  // no match, or the snippet starts with it
    UseSnippetFont(True);
    MatchWidth := Canvas.TextWidth(Source[B].Text);
    Lead := '';
    for K := 0 to B - 1 do
      Lead := Lead + Source[K].Text;
    UseSnippetFont(False);
    if Canvas.TextWidth(Lead) + MatchWidth <= Width then
      Exit;
    repeat
      P := Pos(' ', Lead.TrimLeft);
      if P = 0 then
        Lead := ''
      else
        Lead := Lead.TrimLeft.Substring(P);
    until (Lead = '') or (Canvas.TextWidth(Lead) + MatchWidth <= Width);
    Result := nil;
    if Lead <> '' then
    begin
      LeadRun.Text := Lead;
      LeadRun.Bold := False;
      Result := [LeadRun];
    end;
    for K := B to High(Source) do
      Result := Result + [Source[K]];
  end;

  // Where the current line ends: the first one may give room to the page.
  function Limit: Integer;
  begin
    if Line = 1 then
      Result := FirstRight
    else
      Result := Right;
  end;

  procedure DrawTail(const S: string);
  begin
    TextR := Rect(X, Y, Limit, Y + Px(SnippetLine));
    Winapi.Windows.DrawText(Canvas.Handle, PChar(S), Length(S), TextR,
      DT_SINGLELINE or DT_TOP or DT_LEFT or DT_NOPREFIX or DT_END_ELLIPSIS);
  end;

begin
  Left := R.Left + Px(RowPadX);
  Right := R.Right - Px(RowPadX);
  FirstRight := Right;

  Canvas.Font.Name := FUiFont;
  Canvas.Font.Height := -Px(RefPx);
  Canvas.Font.Style := [];
  if Visited then
    Canvas.Font.Color := ColorVisitedRef
  else
    Canvas.Font.Color := ColorMuted;
  SetTextCharacterExtra(Canvas.Handle, Round(Px(RefPx) * 0.08));   // mockup .08em
  if Compact then
  begin
    Y := R.Top + Px(CompactPadY);
    if Row.RefText <> '' then
    begin
      W := Canvas.TextWidth(Row.RefText);
      TextR := Rect(Right - W, Y, Right, Y + Px(SnippetLine));
      Winapi.Windows.DrawText(Canvas.Handle, PChar(Row.RefText), Length(Row.RefText), TextR,
        DT_SINGLELINE or DT_VCENTER or DT_RIGHT or DT_NOPREFIX);
      FirstRight := Right - W - Px(RefGap);
    end;
  end
  else
  begin
    TextR := Rect(Left, R.Top + Px(RowPadY), Right, R.Top + Px(RowPadY) + Px(RefLine));
    Winapi.Windows.DrawText(Canvas.Handle, PChar(Row.RefText), Length(Row.RefText), TextR,
      DT_SINGLELINE or DT_TOP or DT_LEFT or DT_NOPREFIX or DT_END_ELLIPSIS);
    Y := TextR.Bottom + Px(RefSnippetGap);
  end;
  SetTextCharacterExtra(Canvas.Handle, 0);

  if Compact then
  begin
    MaxLines := 1;
    Runs := FitToMatch(Row.Runs, FirstRight - Left);
  end
  else
  begin
    MaxLines := 2;
    Runs := Row.Runs;
  end;

  X := Left;
  Line := 1;
  Done := False;
  for Run in Runs do
  begin
    if Done then
      Break;
    UseSnippetFont(Run.Bold);
    I := 1;
    while (I <= Length(Run.Text)) and not Done do
    begin
      // Token = a word with the spaces after it (line breaks never lose a word).
      J := I;
      while (J <= Length(Run.Text)) and (Run.Text[J] <> ' ') do
        Inc(J);
      while (J <= Length(Run.Text)) and (Run.Text[J] = ' ') do
        Inc(J);
      Token := Copy(Run.Text, I, J - I);
      I := J;
      if (X = Left) and (Line > 1) then
        Token := TrimLeft(Token);
      W := Canvas.TextWidth(Token);
      if (X + W > Limit) and (X > Left) then
      begin
        if Line = MaxLines then
        begin
          DrawTail(Token + Copy(Run.Text, I, MaxInt));
          Done := True;
          Break;
        end;
        Inc(Line);
        X := Left;
        Y := Y + Px(SnippetLine);
        Token := TrimLeft(Token);
        W := Canvas.TextWidth(Token);
      end;
      if X + W > Limit then
      begin
        DrawTail(Token);                     // a word longer than the whole line
        if Line = MaxLines then
        begin
          Done := True;
          Break;
        end;
        Inc(Line);
        X := Left;
        Y := Y + Px(SnippetLine);
        Continue;
      end;
      Canvas.TextOut(X, Y, Token);
      X := X + W;
    end;
  end;
end;

// The pinned line (E-19): what the topmost row belongs to. A section or a block
// at the top names itself.
function TSearchResultList.TopPinnedText: string;
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Result := '';
  if FModel = nil then
    Exit;
  Node := FTree.GetNodeAt(0, 0);
  if Node = nil then
    Exit;
  Data := FTree.GetNodeData(Node);
  if (Data <> nil) and (Data.Kind in [nkHeading, nkHit]) then
    Result := FModel.PinnedText(Data.Part, Data.Block, Data.Row);
end;

procedure TSearchResultList.UpdatePinned;
var
  Text: string;
begin
  Text := TopPinnedText;
  if Text = FPinned then
    Exit;
  FPinned := Text;
  if Assigned(FOnPinnedChanged) then
    FOnPinnedChanged();
end;

// Scrolling, folding, resizing - all of them repaint.
procedure TSearchResultList.TreeAfterPaint(Sender: TBaseVirtualTree; TargetCanvas: TCanvas);
begin
  UpdatePinned;
end;

procedure TSearchResultList.Open(Node: PVirtualNode);
var
  Data: PNodeData;
  Line: TResultLine;
begin
  if (Node = nil) or (FModel = nil) then
    Exit;
  Data := FTree.GetNodeData(Node);
  if (Data = nil) or (Data.Kind <> nkHit) or not Assigned(FOnOpen) then
    Exit;
  Line := FModel.Line(Data.Part, Data.Block, Data.Row);
  if not Line.Loaded then
    Exit;
  // Marked before the chapter loads: the mark is of the click, not of its outcome.
  if FCurrent <> nil then
    FTree.InvalidateNode(FCurrent);
  FCurrent := Node;
  if not Data.Visited then
    FVisited := FVisited + [KeyOf(Node)];
  Data.Visited := True;
  FTree.InvalidateNode(Node);
  FOnOpen(FModel.Parts[Data.Part].Kind, Line);
end;

procedure TSearchResultList.TreeNodeClick(Sender: TBaseVirtualTree; const HitInfo: THitInfo);
begin
  if hiOnItemButton in HitInfo.HitPositions then
    Exit;                                    // the expand button only toggles
  Open(HitInfo.HitNode);
end;

procedure TSearchResultList.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = vkReturn) and (FTree.FocusedNode <> nil) then
  begin
    Open(FTree.FocusedNode);
    Key := 0;
  end;
end;

end.
