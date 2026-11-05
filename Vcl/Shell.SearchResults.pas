unit Shell.SearchResults;

(* The search result list of the right panel (Slovo_04 A.4, C.5; R4-37).

  One VirtualStringTree: root nodes are the sections "Книги" / "Біблія" with
  the standard expand buttons; under "Біблія" - one node per translation
  (B-31); then the result rows. Rows have a fixed height: the reference line
  (10.5 px, muted) and the snippet in two lines of EB Garamond 15.5 px, the
  matches bold #2f5f95, an ellipsis at the end of the second line. Everything
  is painted in OnAfterCellPaint (OnGetText = '').

  The rows come ready from Presentation.SearchResults; a click or Enter
  reports the section and the index of the item in the reply. *)

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
  Presentation.SearchResults;

type
  TResultOpenEvent = reference to procedure(Section: TResultSectionKind; Index: Integer);
  TSectionCaptionFunc = reference to function(Section: TResultSectionKind): string;
  TResultScaleFunc = reference to function(Value: Integer): Integer;

  TSearchResultList = class
  private
    FTree: TVirtualStringTree;
    FSections: TArray<TResultSection>;
    FTextFont: string;
    FUiFont: string;
    FScale: TResultScaleFunc;
    FSectionCaption: TSectionCaptionFunc;
    FOnOpen: TResultOpenEvent;

    function Px(Value: Integer): Integer;
    procedure Open(Node: PVirtualNode);
    procedure TreeInitNode(Sender: TBaseVirtualTree; ParentNode, Node: PVirtualNode;
      var InitialStates: TVirtualNodeInitStates);
    procedure TreeInitChildren(Sender: TBaseVirtualTree; Node: PVirtualNode; var ChildCount: Cardinal);
    procedure TreeGetText(Sender: TBaseVirtualTree; Node: PVirtualNode; Column: TColumnIndex;
      TextType: TVSTTextType; var CellText: string);
    procedure TreeAfterCellPaint(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
      Node: PVirtualNode; Column: TColumnIndex; CellRect: TRect);
    procedure TreeNodeClick(Sender: TBaseVirtualTree; const HitInfo: THitInfo);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure PaintRow(Canvas: TCanvas; const Row: TResultRow; const R: TRect);
  public
    constructor Create(AOwner: TComponent; AParent: TWinControl; const Scale: TResultScaleFunc);
    destructor Destroy; override;

    procedure Show(const Sections: TArray<TResultSection>);
    procedure Clear;
    procedure ApplyFonts(const TextFont, UiFont: string);
    procedure Invalidate;

    property Control: TVirtualStringTree read FTree;
    property SectionCaption: TSectionCaptionFunc read FSectionCaption write FSectionCaption;
    property OnOpen: TResultOpenEvent read FOnOpen write FOnOpen;
  end;

implementation

uses
  System.UITypes,
  System.Math,
  Presentation.Theme;

type
  // Section -> Group -> Row; Group = -1 / Row = -1 for the upper levels.
  // A Books section has one group without a node of its own.
  TNodeKind = (nkSection, nkGroup, nkRow);
  TNodeData = record
    Kind: TNodeKind;
    Section, Group, Row: Integer;
  end;
  PNodeData = ^TNodeData;

const
  RowHeight     = 88;     // 11 + ref 15 + 5 + 2 x 23 + 11 (mockup: padding 11px 13px)
  HeaderHeight  = 30;
  RowPadX       = 13;
  RowPadY       = 11;
  RefPx         = 11;     // mockup 10.5 px
  SnippetPx     = 16;     // mockup 15.5 px
  SnippetLine   = 23;     // line-height 1.5
  SectionPx     = 11;
  GroupPx       = 12;
  ColorRowHover = TColor($00F2F2F2);   // rgba(0,0,0,.04) on #fcfcfc
  ColorSnippet  = TColor($003F3F3F);   // #3f3f3f

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

procedure TSearchResultList.Show(const Sections: TArray<TResultSection>);
begin
  FSections := Sections;
  FTree.BeginUpdate;
  try
    FTree.Clear;
    FTree.RootNodeCount := Length(Sections);
    FTree.FullExpand;
  finally
    FTree.EndUpdate;
  end;
  FTree.OffsetY := 0;
end;

procedure TSearchResultList.TreeInitNode(Sender: TBaseVirtualTree; ParentNode, Node: PVirtualNode;
  var InitialStates: TVirtualNodeInitStates);
var
  Data, ParentData: PNodeData;
  Section: TResultSection;
begin
  Data := Sender.GetNodeData(Node);
  if ParentNode = nil then
  begin
    Data.Kind := nkSection;
    Data.Section := Node.Index;
    Data.Group := -1;
    Data.Row := -1;
    InitialStates := InitialStates + [ivsHasChildren, ivsExpanded];
    Exit;
  end;

  ParentData := Sender.GetNodeData(ParentNode);
  Section := FSections[ParentData.Section];
  Data.Section := ParentData.Section;
  if (ParentData.Kind = nkSection) and (Section.Kind = rsBible) then
  begin
    Data.Kind := nkGroup;
    Data.Group := Node.Index;
    Data.Row := -1;
    InitialStates := InitialStates + [ivsHasChildren, ivsExpanded];
  end
  else
  begin
    Data.Kind := nkRow;
    if ParentData.Kind = nkGroup then
      Data.Group := ParentData.Group
    else
      Data.Group := 0;
    Data.Row := Node.Index;
    Sender.NodeHeight[Node] := Px(RowHeight);
  end;
end;

procedure TSearchResultList.TreeInitChildren(Sender: TBaseVirtualTree; Node: PVirtualNode;
  var ChildCount: Cardinal);
var
  Data: PNodeData;
  Section: TResultSection;
begin
  Data := Sender.GetNodeData(Node);
  Section := FSections[Data.Section];
  case Data.Kind of
    nkSection:
      if Section.Kind = rsBible then
        ChildCount := Length(Section.Groups)
      else if Length(Section.Groups) > 0 then
        ChildCount := Length(Section.Groups[0].Rows)
      else
        ChildCount := 0;
    nkGroup:
      ChildCount := Length(Section.Groups[Data.Group].Rows);
  else
    ChildCount := 0;
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
  Text: string;
begin
  Data := Sender.GetNodeData(Node);
  if (Data = nil) or (Data.Section > High(FSections)) then
    Exit;
  R := Rect(CellRect.Left, CellRect.Top, Sender.ClientWidth, CellRect.Bottom);
  // CellRect includes the indent, where VST draws the expand button of a
  // section or translation: headers start after it (rows have no button and
  // keep the full width).
  if Data.Kind <> nkRow then
    R.Left := CellRect.Left + Integer(Sender.GetNodeLevel(Node) + 1) * Integer(FTree.Indent);
  Hot := (Node = Sender.HotNode) or ((Node = Sender.FocusedNode) and Sender.Focused);

  TargetCanvas.Brush.Style := bsSolid;
  if Hot and (Data.Kind = nkRow) then
    TargetCanvas.Brush.Color := ColorRowHover
  else
    TargetCanvas.Brush.Color := ColorBackground;
  TargetCanvas.FillRect(R);

  case Data.Kind of
    nkSection, nkGroup:
      begin
        TargetCanvas.Brush.Style := bsClear;
        if Data.Kind = nkSection then
        begin
          if Assigned(FSectionCaption) then
            Text := FSectionCaption(FSections[Data.Section].Kind).ToUpper
          else
            Text := '';
          TargetCanvas.Font.Name := FUiFont;
          TargetCanvas.Font.Height := -Px(SectionPx);
          TargetCanvas.Font.Style := [fsBold];
          TargetCanvas.Font.Color := ColorMuted;
        end
        else
        begin
          Text := FSections[Data.Section].Groups[Data.Group].Caption;
          TargetCanvas.Font.Name := FUiFont;
          TargetCanvas.Font.Height := -Px(GroupPx);
          TargetCanvas.Font.Style := [];
          TargetCanvas.Font.Color := ColorText;
        end;
        TextR := Rect(R.Left + Px(2), R.Top, R.Right - Px(4), R.Bottom);
        Winapi.Windows.DrawText(TargetCanvas.Handle, PChar(Text), Length(Text), TextR,
          DT_SINGLELINE or DT_VCENTER or DT_LEFT or DT_NOPREFIX or DT_END_ELLIPSIS);
      end;
    nkRow:
      begin
        if Hot then
        begin
          // Mockup: a 2 px accent bar on the left of the hovered row.
          TargetCanvas.Brush.Color := ColorAccent;
          TargetCanvas.FillRect(Rect(R.Left, R.Top + Px(2), R.Left + Px(2), R.Bottom - Px(2)));
        end;
        TargetCanvas.Brush.Style := bsClear;
        PaintRow(TargetCanvas, FSections[Data.Section].Groups[Data.Group].Rows[Data.Row], R);
      end;
  end;
end;

// Reference line, then the snippet word by word over two lines; what does not
// fit on the second line ends with an ellipsis.
procedure TSearchResultList.PaintRow(Canvas: TCanvas; const Row: TResultRow; const R: TRect);
var
  Left, Right, X, Y, Line, W, I, J: Integer;
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
      Canvas.Font.Color := ColorAccentHover;
    end
    else
    begin
      Canvas.Font.Style := [];
      Canvas.Font.Color := ColorSnippet;
    end;
  end;

  procedure DrawTail(const S: string);
  begin
    TextR := Rect(X, Y, Right, Y + Px(SnippetLine));
    Winapi.Windows.DrawText(Canvas.Handle, PChar(S), Length(S), TextR,
      DT_SINGLELINE or DT_TOP or DT_LEFT or DT_NOPREFIX or DT_END_ELLIPSIS);
  end;

begin
  Left := R.Left + Px(RowPadX);
  Right := R.Right - Px(RowPadX);

  Canvas.Font.Name := FUiFont;
  Canvas.Font.Height := -Px(RefPx);
  Canvas.Font.Style := [];
  Canvas.Font.Color := ColorMuted;
  TextR := Rect(Left, R.Top + Px(RowPadY), Right, R.Top + Px(RowPadY) + Px(15));
  Winapi.Windows.DrawText(Canvas.Handle, PChar(Row.RefText), Length(Row.RefText), TextR,
    DT_SINGLELINE or DT_TOP or DT_LEFT or DT_NOPREFIX or DT_END_ELLIPSIS);

  X := Left;
  Y := TextR.Bottom + Px(5);
  Line := 1;
  Done := False;
  for Run in Row.Runs do
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
      if (X + W > Right) and (X > Left) then
      begin
        if Line = 2 then
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
      if X + W > Right then
      begin
        DrawTail(Token);                     // a word longer than the whole line
        if Line = 2 then
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

procedure TSearchResultList.Open(Node: PVirtualNode);
var
  Data: PNodeData;
  Row: TResultRow;
begin
  if Node = nil then
    Exit;
  Data := FTree.GetNodeData(Node);
  if (Data = nil) or (Data.Kind <> nkRow) or not Assigned(FOnOpen) then
    Exit;
  Row := FSections[Data.Section].Groups[Data.Group].Rows[Data.Row];
  FOnOpen(FSections[Data.Section].Kind, Row.Index);
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
