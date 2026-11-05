unit Shell.ChapterList;

(* The shelf and the table of contents in the text column (Slovo_04 A.2, C.5;
  R4-38): ONE flat VirtualStringTree for both states, rows of 56 px, painted in
  OnAfterCellPaint - the number of a chapter in the left margin, the title, a
  muted second line ("73 розд.") and the accent status ("читаю · розділ 17" on
  the shelf, "ЧИТАЮ" on the current chapter of a table of contents).

  Above the list - the header of the mockup: title (46 px), italic subtitle
  (17 px) and the 58 px rule. Sizes and colours from "Читання v2" (design\).

  The form builds the rows from the library nodes; a click reports the node
  index of the row, and the form decides what it opens. *)

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  VirtualTrees,
  VirtualTrees.Types,
  VirtualTrees.BaseTree;

type
  TListRow = record
    NodeIndex: Integer;          // into the TLibraryNode array: what a click opens
    Number: Integer;             // in the left margin; 0 = none (shelf)
    Title: string;
    Meta: string;                // muted second line; '' = a one-line row
    Status: string;              // accent; shelf: after Meta, toc: on the right
  end;

  TListOpenEvent = reference to procedure(NodeIndex: Integer);
  TScaleFunc = reference to function(Value: Integer): Integer;

  TChapterList = class
  private
    FHost: TPanel;
    FTreeHost: TPanel;
    FHeader: TPanel;
    FTitle: TLabel;
    FSubtitle: TLabel;
    FRuleRow: TPanel;
    FRule: TPanel;
    FTree: TVirtualStringTree;
    FRows: TArray<TListRow>;
    FLeftPad: Integer;
    FTitlePx: Integer;
    FTextFont: string;
    FUiFont: string;
    FOnOpen: TListOpenEvent;
    FScale: TScaleFunc;

    function RowOf(Node: PVirtualNode): Integer;
    procedure Open(Node: PVirtualNode);
    procedure TreeGetText(Sender: TBaseVirtualTree; Node: PVirtualNode; Column: TColumnIndex;
      TextType: TVSTTextType; var CellText: string);
    procedure TreeAfterCellPaint(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
      Node: PVirtualNode; Column: TColumnIndex; CellRect: TRect);
    procedure TreeNodeClick(Sender: TBaseVirtualTree; const HitInfo: THitInfo);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeHostResize(Sender: TObject);
    function Px(Value: Integer): Integer;
  public
    // Scale: 96-DPI pixels to the form's (E-14) - the form's own ScaleValue.
    constructor Create(AOwner: TComponent; AParent: TWinControl; const Scale: TScaleFunc);
    destructor Destroy; override;

    procedure Show(const Title, Subtitle: string; const Rows: TArray<TListRow>);
    // The left margin of the column (TextColumnLeft*): numbers live inside it.
    procedure SetLeftPad(Value: Integer);
    procedure ApplyFonts(const TextFont, UiFont: string);
    // Mockup h1: clamp(30px, 4.6vw, 46px) - the form passes the size in CSS px.
    procedure SetTitlePx(Value: Integer);
    procedure FocusList;

    property Host: TPanel read FHost;
    property Tree: TVirtualStringTree read FTree;
    property OnOpen: TListOpenEvent read FOnOpen write FOnOpen;
  end;

implementation

uses
  Shell.FlatControls,
  System.UITypes,
  System.Math,
  Presentation.Theme;

const
  RowHeight      = 56;                   // R4-38
  NumberGap      = 20;                   // mockup: number at left -64px, 44px wide
  TitlePx        = 21;                   // row title, EB Garamond
  MetaPx         = 12;
  NumberPx       = 11;
  StatusPx       = 11;                   // mockup 10.5 px
  HeaderTitlePx  = 46;
  HeaderSubPx    = 17;
  RuleWidth      = 58;
  ColorRowLine   = TColor($00EBEBEB);    // rgba(0,0,0,.07) on #fcfcfc
  ColorRowHover  = TColor($00F4F4F4);    // rgba(0,0,0,.03)
  ColorRule      = TColor($00C8C8C8);

{ TChapterList }

constructor TChapterList.Create(AOwner: TComponent; AParent: TWinControl;
  const Scale: TScaleFunc);
begin
  inherited Create;
  FScale := Scale;
  FHost := TPanel.Create(AOwner);
  FHost.Parent := AParent;
  FHost.Align := alClient;
  FHost.BevelOuter := bvNone;
  FHost.ParentBackground := False;
  FHost.Color := ColorBackground;
  FHost.Visible := False;

  FHeader := TPanel.Create(AOwner);
  FHeader.Parent := FHost;
  FHeader.Align := alTop;
  FHeader.BevelOuter := bvNone;
  FHeader.ParentBackground := False;
  FHeader.Color := ColorBackground;
  FHeader.AutoSize := True;

  FTitle := TLabel.Create(AOwner);
  FTitle.Parent := FHeader;
  FTitle.Align := alTop;
  FTitle.AlignWithMargins := True;
  FTitle.ShowAccelChar := False;
  FTitle.WordWrap := True;                 // a long title wraps; an ellipsis hid it (seen on Windows)
  FTitle.Font.Color := ColorHeading;

  FSubtitle := TLabel.Create(AOwner);
  FSubtitle.Parent := FHeader;
  FSubtitle.Align := alTop;
  FSubtitle.AlignWithMargins := True;
  FSubtitle.ShowAccelChar := False;
  FSubtitle.Font.Color := ColorMuted;
  FSubtitle.Top := 1000;                   // keep alTop order: title, subtitle, rule

  FRuleRow := TPanel.Create(AOwner);
  FRuleRow.Parent := FHeader;
  FRuleRow.Align := alTop;
  FRuleRow.AlignWithMargins := True;
  FRuleRow.BevelOuter := bvNone;
  FRuleRow.ParentBackground := False;
  FRuleRow.Color := ColorBackground;
  FRuleRow.Top := 2000;

  FRule := TPanel.Create(AOwner);
  FRule.Parent := FRuleRow;
  FRule.Align := alLeft;
  FRule.BevelOuter := bvNone;
  FRule.ParentBackground := False;
  FRule.Color := ColorRule;

  // The tree in its own host, wider than it by the scrollbar width: the thin
  // bar of the form shows the scroll (Shell.FlatControls, A.5).
  FTreeHost := TPanel.Create(AOwner);
  FTreeHost.Parent := FHost;
  FTreeHost.Align := alClient;
  FTreeHost.BevelOuter := bvNone;
  FTreeHost.ParentBackground := False;
  FTreeHost.Color := ColorBackground;
  FTreeHost.OnResize := TreeHostResize;

  FTree := TVirtualStringTree.Create(AOwner);
  FTree.Parent := FTreeHost;
  FTree.ScrollBarOptions.ScrollBars := System.UITypes.TScrollStyle.ssVertical;
  FTree.ScrollBarOptions.AlwaysVisible := True;
  FTree.BorderStyle := bsNone;
  FTree.Color := ColorBackground;
  // toAutoChangeScale would reset the row height to the font's text height on
  // every font change (seen on Windows: 15 px rows). The rows are ours: 56 px.
  FTree.TreeOptions.AutoOptions := FTree.TreeOptions.AutoOptions - [toAutoChangeScale];
  FTree.DefaultNodeHeight := Px(RowHeight);
  FTree.Indent := 0;
  FTree.Margin := 0;
  FTree.TextMargin := 0;
  FTree.TreeOptions.PaintOptions := FTree.TreeOptions.PaintOptions
    - [toShowTreeLines, toShowRoot, toShowButtons, toUseExplorerTheme]
    + [toHideFocusRect, toHotTrack, toAlwaysHideSelection];
  FTree.TreeOptions.SelectionOptions := FTree.TreeOptions.SelectionOptions + [toFullRowSelect];
  FTree.TreeOptions.MiscOptions := FTree.TreeOptions.MiscOptions - [toEditable];
  FTree.OnGetText := TreeGetText;
  FTree.OnAfterCellPaint := TreeAfterCellPaint;
  FTree.OnNodeClick := TreeNodeClick;
  FTree.OnKeyDown := TreeKeyDown;
  FTree.Cursor := crHandPoint;

  FLeftPad := 64;
  FTitlePx := HeaderTitlePx;
  FTextFont := TextFontName;
  FUiFont := UiFontName;
end;

destructor TChapterList.Destroy;
begin
  // The controls belong to the form and outlive this object.
  FTree.OnGetText := nil;
  FTree.OnAfterCellPaint := nil;
  FTree.OnNodeClick := nil;
  FTree.OnKeyDown := nil;
  inherited;
end;

function TChapterList.Px(Value: Integer): Integer;
begin
  Result := FScale(Value);
end;

procedure TChapterList.ApplyFonts(const TextFont, UiFont: string);
begin
  FTextFont := TextFont;
  FUiFont := UiFont;
  FTitle.Font.Name := TextFont;
  FTitle.Font.Height := -Px(FTitlePx);
  FSubtitle.Font.Name := TextFont;
  FSubtitle.Font.Height := -Px(HeaderSubPx);
  FSubtitle.Font.Style := [fsItalic];
  FTree.Font.Name := UiFont;
  FTree.DefaultNodeHeight := Px(RowHeight);
  FTree.Invalidate;
end;

procedure TChapterList.TreeHostResize(Sender: TObject);
begin
  FitHidingScrollBar(FTree, FTreeHost.ClientRect);
end;

procedure TChapterList.SetTitlePx(Value: Integer);
begin
  if Value = FTitlePx then
    Exit;
  FTitlePx := Value;
  FTitle.Font.Height := -Px(Value);
end;

procedure TChapterList.SetLeftPad(Value: Integer);
begin
  FLeftPad := Value;
  // Mockup: title margin 0 0 8px; rule margin 26px 0 34px; header text after the margin.
  FTitle.Margins.SetBounds(Value, 0, 0, Px(8));
  FSubtitle.Margins.SetBounds(Value, 0, 0, 0);
  FRuleRow.Margins.SetBounds(Value, Px(26), 0, Px(34));
  FRuleRow.Height := 1;
  FRule.Width := Px(RuleWidth);
  FTree.Invalidate;
end;

procedure TChapterList.Show(const Title, Subtitle: string; const Rows: TArray<TListRow>);
begin
  FTitle.Caption := Title;
  FSubtitle.Caption := Subtitle;
  FRows := Rows;
  FTree.BeginUpdate;
  try
    FTree.Clear;
    FTree.RootNodeCount := Length(Rows);   // row index = node index (flat list)
  finally
    FTree.EndUpdate;
  end;
  FTree.OffsetY := 0;
  if FTree.RootNodeCount > 0 then
    FTree.FocusedNode := FTree.GetFirst;
end;

procedure TChapterList.FocusList;
begin
  if FTree.Showing then
    FTree.SetFocus;
end;

function TChapterList.RowOf(Node: PVirtualNode): Integer;
begin
  if Node = nil then
    Exit(-1);
  Result := Node.Index;
  if Result > High(FRows) then
    Result := -1;
end;

procedure TChapterList.TreeGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
  Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
begin
  CellText := '';                            // everything is painted (C.5)
end;

procedure TChapterList.TreeAfterCellPaint(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
  Node: PVirtualNode; Column: TColumnIndex; CellRect: TRect);
var
  Row: TListRow;
  Index: Integer;
  R, TextR: TRect;
  Hot: Boolean;
  Text: string;
  Right, StatusWidth, Y: Integer;

  procedure UseFont(const Name: string; HeightPx: Integer; Color: TColor; Style: TFontStyles = []);
  begin
    TargetCanvas.Font.Name := Name;
    TargetCanvas.Font.Height := -Px(HeightPx);
    TargetCanvas.Font.Color := Color;
    TargetCanvas.Font.Style := Style;
    SetTextCharacterExtra(TargetCanvas.Handle, 0);
  end;

  procedure Draw(const S: string; var Area: TRect; Flags: Cardinal);
  begin
    Winapi.Windows.DrawText(TargetCanvas.Handle, PChar(S), Length(S), Area,
      Flags or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  end;

begin
  Index := RowOf(Node);
  if Index < 0 then
    Exit;
  Row := FRows[Index];
  R := Rect(0, CellRect.Top, Sender.ClientWidth, CellRect.Bottom);
  Hot := (Node = Sender.HotNode) or ((Node = Sender.FocusedNode) and Sender.Focused);

  // Background over whatever VST painted (selection is hidden anyway).
  TargetCanvas.Brush.Style := bsSolid;
  if Hot then
    TargetCanvas.Brush.Color := ColorRowHover
  else
    TargetCanvas.Brush.Color := ColorBackground;
  TargetCanvas.FillRect(R);
  TargetCanvas.Brush.Style := bsClear;

  // Bottom line, under the text only (from the margin to the right edge).
  TargetCanvas.Pen.Color := ColorRowLine;
  TargetCanvas.MoveTo(FLeftPad, R.Bottom - 1);
  TargetCanvas.LineTo(R.Right, R.Bottom - 1);

  Right := R.Right - Px(10);

  if Row.Meta = '' then
  begin
    // One line (toc): number in the margin, title, "ЧИТАЮ" on the right.
    if Row.Status <> '' then
    begin
      UseFont(FUiFont, StatusPx, ColorAccent);
      SetTextCharacterExtra(TargetCanvas.Handle, Round(Px(StatusPx) * 0.1));   // mockup .1em
      StatusWidth := TargetCanvas.TextWidth(Row.Status);
      TextR := Rect(Right - StatusWidth, R.Top, Right, R.Bottom);
      // DT_LEFT from the measured width: DrawText aligns right without the
      // letter-spacing and the last letter fell off (seen on Windows).
      Draw(Row.Status, TextR, DT_VCENTER or DT_LEFT);
      SetTextCharacterExtra(TargetCanvas.Handle, 0);
      Right := TextR.Left - Px(16);
    end;
    if Row.Number > 0 then
    begin
      UseFont(FUiFont, NumberPx, ColorMarker);
      TextR := Rect(0, R.Top, FLeftPad - Px(NumberGap), R.Bottom);
      Draw(IntToStr(Row.Number), TextR, DT_VCENTER or DT_RIGHT);
    end;
    UseFont(FTextFont, TitlePx, ColorText);
    TextR := Rect(FLeftPad, R.Top, Right, R.Bottom);
    Draw(Row.Title, TextR, DT_VCENTER or DT_LEFT);
    Exit;
  end;

  // Two lines (shelf): title, then "73 розд." muted and " · читаю · розділ 17" accent.
  Y := R.Top + Px(7);
  UseFont(FTextFont, TitlePx, ColorText);
  TextR := Rect(FLeftPad, Y, Right, Y + TargetCanvas.TextHeight('Ag'));
  Draw(Row.Title, TextR, DT_TOP or DT_LEFT);
  Y := TextR.Bottom + Px(1);

  UseFont(FUiFont, MetaPx, ColorMuted);
  Text := Row.Meta;
  TextR := Rect(FLeftPad, Y, Right, Y + TargetCanvas.TextHeight('Ag'));
  Draw(Text, TextR, DT_TOP or DT_LEFT);
  if Row.Status <> '' then
  begin
    TextR.Left := FLeftPad + TargetCanvas.TextWidth(Text);
    UseFont(FUiFont, MetaPx, ColorAccent);
    Draw('  ·  ' + Row.Status, TextR, DT_TOP or DT_LEFT);
  end;
end;

procedure TChapterList.Open(Node: PVirtualNode);
var
  Index: Integer;
begin
  Index := RowOf(Node);
  if (Index >= 0) and Assigned(FOnOpen) then
    FOnOpen(FRows[Index].NodeIndex);
end;

procedure TChapterList.TreeNodeClick(Sender: TBaseVirtualTree; const HitInfo: THitInfo);
begin
  Open(HitInfo.HitNode);
end;

procedure TChapterList.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = vkReturn) and (FTree.FocusedNode <> nil) then
  begin
    Open(FTree.FocusedNode);
    Key := 0;
  end;
end;

end.
