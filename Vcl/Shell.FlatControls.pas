unit Shell.FlatControls;

(* The small controls of the mockup "Читання v2" (Slovo_04 A.3, A.4).

  - PaintRoundRect / PaintCheckBox / PaintDot: anti-aliased shapes (GDI+) used
    by the controls below and by the library tree;
  - TScopeSwitch: the pill "Уся бібліотека | Відмічені книги · N" of the search
    panel (rounded 999px, 3 px inner padding, the active half #2f2f2f / white);
  - TFlatCheckBox: the square option box - a 14 px frame rgba(0,0,0,.26),
    an 8 px accent square when checked, the caption 13 px #4a4a4a.

  Sizes are 96-DPI pixels scaled by the function the form passes (E-14).
  Both controls take focus: Space toggles, ←/→ switch the scope. *)

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Graphics;

type
  TFlatScaleFunc = reference to function(Value: Integer): Integer;

  TScopeSwitch = class(TCustomControl)
  private
    FScale: TFlatScaleFunc;
    FWholeLibrary: Boolean;
    FAllCaption: string;
    FCheckedCaption: string;
    FOnChange: TNotifyEvent;
    FFocusCue: Boolean;                     // focus came from the keyboard
    function Px(Value: Integer): Integer;
    procedure SetWholeLibrary(Value: Boolean);
    procedure SetAllCaption(const Value: string);
    procedure SetCheckedCaption(const Value: string);
    procedure Segments(out AllRect, CheckedRect: TRect);
    procedure Change(Value: Boolean);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent; const Scale: TFlatScaleFunc); reintroduce;
    // Set from code - no OnChange.
    property WholeLibrary: Boolean read FWholeLibrary write SetWholeLibrary;
    property AllCaption: string read FAllCaption write SetAllCaption;
    property CheckedCaption: string read FCheckedCaption write SetCheckedCaption;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  TFlatCheckBox = class(TCustomControl)
  private
    FScale: TFlatScaleFunc;
    FChecked: Boolean;
    FHot: Boolean;
    FFocusCue: Boolean;
    function Px(Value: Integer): Integer;
    procedure SetChecked(Value: Boolean);
    procedure Toggle;
    procedure CMMouseEnter(var Message: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure CMTextChanged(var Message: TMessage); message CM_TEXTCHANGED;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent; const Scale: TFlatScaleFunc); reintroduce;
    // Set from code - no OnClick.
    property Checked: Boolean read FChecked write SetChecked;
    property Caption;
    property OnClick;
  end;

// A filled rounded rectangle with a 1 px border; Border = clNone - no border.
procedure PaintRoundRect(Canvas: TCanvas; const R: TRect; Radius: Single; Fill, Border: TColor);
// The mockup box: Size (14) frame, an Inner (8) accent square when checked.
procedure PaintCheckBox(Canvas: TCanvas; const R: TRect; Checked: Boolean; Inner: Integer);
// The dot "читаю": a filled circle.
procedure PaintDot(Canvas: TCanvas; CenterX, CenterY: Integer; Diameter: Single; Color: TColor);

const
  ColorBoxBorder   = TColor($00BDBDBD);   // rgba(0,0,0,.26) on white
  ColorBoxFill     = TColor($00FFFFFF);
  ColorPillBorder  = TColor($00E0E0E0);   // rgba(0,0,0,.12) on white
  ColorPillActive  = TColor($002F2F2F);   // #2f2f2f
  ColorOptionText  = TColor($004A4A4A);   // #4a4a4a
  ColorOptionHover = TColor($001F1F1F);   // #1f1f1f

implementation

uses
  System.UITypes,
  System.Math,
  Winapi.GDIPAPI,
  Winapi.GDIPOBJ,
  Presentation.Theme;

function ToArgb(Color: TColor): ARGB;
var
  C: COLORREF;
begin
  C := ColorToRGB(Color);
  Result := $FF000000 or (ARGB(GetRValue(C)) shl 16) or (ARGB(GetGValue(C)) shl 8) or ARGB(GetBValue(C));
end;

function RoundPath(X, Y, W, H, Radius: Single): TGPGraphicsPath;
var
  D: Single;
begin
  Result := TGPGraphicsPath.Create;
  D := 2 * Radius;
  if D > W then D := W;
  if D > H then D := H;
  if D <= 0 then
  begin
    Result.AddRectangle(MakeRect(X, Y, W, H));
    Exit;
  end;
  Result.AddArc(X, Y, D, D, 180, 90);
  Result.AddArc(X + W - D, Y, D, D, 270, 90);
  Result.AddArc(X + W - D, Y + H - D, D, D, 0, 90);
  Result.AddArc(X, Y + H - D, D, D, 90, 90);
  Result.CloseFigure;
end;

procedure PaintRoundRect(Canvas: TCanvas; const R: TRect; Radius: Single; Fill, Border: TColor);
var
  G: TGPGraphics;
  Path: TGPGraphicsPath;
  Brush: TGPSolidBrush;
  Pen: TGPPen;
begin
  G := TGPGraphics.Create(Canvas.Handle);
  try
    G.SetSmoothingMode(SmoothingModeAntiAlias);
    // Half a pixel in: a 1 px line falls on whole pixels.
    Path := RoundPath(R.Left + 0.5, R.Top + 0.5, R.Width - 1, R.Height - 1, Radius);
    try
      if Fill <> clNone then
      begin
        Brush := TGPSolidBrush.Create(ToArgb(Fill));
        try
          G.FillPath(Brush, Path);
        finally
          Brush.Free;
        end;
      end;
      if Border <> clNone then
      begin
        Pen := TGPPen.Create(ToArgb(Border), 1);
        try
          G.DrawPath(Pen, Path);
        finally
          Pen.Free;
        end;
      end;
    finally
      Path.Free;
    end;
  finally
    G.Free;
  end;
end;

procedure PaintCheckBox(Canvas: TCanvas; const R: TRect; Checked: Boolean; Inner: Integer);
var
  Box: TRect;
begin
  PaintRoundRect(Canvas, R, 3 * R.Width / 14, ColorBoxFill, ColorBoxBorder);
  if not Checked then
    Exit;
  Box.Left := R.Left + (R.Width - Inner) div 2;
  Box.Top := R.Top + (R.Height - Inner) div 2;
  Box.Right := Box.Left + Inner;
  Box.Bottom := Box.Top + Inner;
  // A filled square without border: no half-pixel shift.
  PaintRoundRect(Canvas, Rect(Box.Left, Box.Top, Box.Right + 1, Box.Bottom + 1),
    Inner / 8, ColorAccent, clNone);
end;

procedure PaintDot(Canvas: TCanvas; CenterX, CenterY: Integer; Diameter: Single; Color: TColor);
var
  G: TGPGraphics;
  Brush: TGPSolidBrush;
begin
  G := TGPGraphics.Create(Canvas.Handle);
  try
    G.SetSmoothingMode(SmoothingModeAntiAlias);
    Brush := TGPSolidBrush.Create(ToArgb(Color));
    try
      G.FillEllipse(Brush, CenterX - Diameter / 2, CenterY - Diameter / 2, Diameter, Diameter);
    finally
      Brush.Free;
    end;
  finally
    G.Free;
  end;
end;

// The focus rectangle only after keyboard use: focus taken by a mouse click
// shows none until a key is pressed (the window's UI state is not relied on -
// with "underline access keys" on, Windows never hides the cues).
function FocusedByMouse: Boolean;
begin
  Result := GetKeyState(VK_LBUTTON) < 0;
end;

{ TScopeSwitch }

constructor TScopeSwitch.Create(AOwner: TComponent; const Scale: TFlatScaleFunc);
begin
  inherited Create(AOwner);
  FScale := Scale;
  FWholeLibrary := True;
  ControlStyle := ControlStyle + [csOpaque] - [csDoubleClicks];
  DoubleBuffered := True;
  TabStop := True;
  Color := ColorBackground;
  Height := Px(32);
  Cursor := crHandPoint;
end;

function TScopeSwitch.Px(Value: Integer): Integer;
begin
  Result := FScale(Value);
end;

procedure TScopeSwitch.SetWholeLibrary(Value: Boolean);
begin
  if FWholeLibrary = Value then
    Exit;
  FWholeLibrary := Value;
  Invalidate;
end;

procedure TScopeSwitch.SetAllCaption(const Value: string);
begin
  FAllCaption := Value;
  Invalidate;
end;

procedure TScopeSwitch.SetCheckedCaption(const Value: string);
begin
  FCheckedCaption := Value;
  Invalidate;
end;

procedure TScopeSwitch.Change(Value: Boolean);
begin
  if FWholeLibrary = Value then
    Exit;
  FWholeLibrary := Value;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

// Mockup: inline-flex, padding 3 px, each button padding 5 12, font 12 px.
procedure TScopeSwitch.Segments(out AllRect, CheckedRect: TRect);
var
  Pad, W1, W2: Integer;
begin
  Canvas.Font.Name := UiFontName;
  Canvas.Font.Height := -Px(12);
  Canvas.Font.Style := [];
  Pad := Px(3);
  W1 := Canvas.TextWidth(FAllCaption) + 2 * Px(12);
  W2 := Canvas.TextWidth(FCheckedCaption) + 2 * Px(12);
  AllRect := Rect(Pad, Pad, Pad + W1, Height - Pad);
  CheckedRect := Rect(AllRect.Right, Pad, AllRect.Right + W2, Height - Pad);
end;

procedure TScopeSwitch.Paint;
var
  AllRect, CheckedRect, Active, Outer: TRect;

  procedure DrawSegment(const R: TRect; const Text: string; On: Boolean);
  var
    TextR: TRect;
  begin
    if On then
      Canvas.Font.Color := clWhite
    else
      Canvas.Font.Color := ColorOptionText;
    TextR := R;
    Canvas.Brush.Style := bsClear;
    Winapi.Windows.DrawText(Canvas.Handle, PChar(Text), Length(Text), TextR,
      DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
  end;

begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  Segments(AllRect, CheckedRect);
  Outer := Rect(0, 0, CheckedRect.Right + Px(3), Height);
  PaintRoundRect(Canvas, Outer, Height / 2, ColorBoxFill, ColorPillBorder);
  if FWholeLibrary then
    Active := AllRect
  else
    Active := CheckedRect;
  PaintRoundRect(Canvas, Active, Active.Height / 2, ColorPillActive, clNone);
  DrawSegment(AllRect, FAllCaption, FWholeLibrary);
  DrawSegment(CheckedRect, FCheckedCaption, not FWholeLibrary);
  if Focused and FFocusCue then
  begin
    InflateRect(Active, -Px(2), -Px(2));
    Canvas.Font.Color := clWhite;      // DrawFocusRect XORs with the text colour
    Canvas.Brush.Color := ColorPillActive;
    Canvas.DrawFocusRect(Active);
  end;
end;

procedure TScopeSwitch.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  AllRect, CheckedRect: TRect;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  if CanFocus then
    SetFocus;
  Segments(AllRect, CheckedRect);
  if X < AllRect.Right then
    Change(True)
  else if X < CheckedRect.Right then
    Change(False);
end;

procedure TScopeSwitch.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  if not FFocusCue then
  begin
    FFocusCue := True;
    Invalidate;
  end;
  case Key of
    vkLeft:  Change(True);
    vkRight: Change(False);
    vkSpace: Change(not FWholeLibrary);
  else
    Exit;
  end;
  Key := 0;
end;

procedure TScopeSwitch.DoEnter;
begin
  inherited;
  FFocusCue := not FocusedByMouse;
  Invalidate;
end;

procedure TScopeSwitch.DoExit;
begin
  inherited;
  FFocusCue := False;
  Invalidate;
end;

{ TFlatCheckBox }

constructor TFlatCheckBox.Create(AOwner: TComponent; const Scale: TFlatScaleFunc);
begin
  inherited Create(AOwner);
  FScale := Scale;
  ControlStyle := ControlStyle + [csOpaque] - [csDoubleClicks];
  DoubleBuffered := True;
  TabStop := True;
  Color := ColorBackground;
  Height := Px(20);
  Cursor := crHandPoint;
end;

function TFlatCheckBox.Px(Value: Integer): Integer;
begin
  Result := FScale(Value);
end;

procedure TFlatCheckBox.SetChecked(Value: Boolean);
begin
  if FChecked = Value then
    Exit;
  FChecked := Value;
  Invalidate;
end;

procedure TFlatCheckBox.Toggle;
begin
  FChecked := not FChecked;
  Invalidate;
  Click;
end;

procedure TFlatCheckBox.Paint;
var
  Box, TextR: TRect;
  Size: Integer;
  Text: string;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);

  Size := Px(14);
  Box := Rect(0, (Height - Size) div 2, Size, (Height - Size) div 2 + Size);
  PaintCheckBox(Canvas, Box, FChecked, Px(8));

  Text := Caption;
  Canvas.Font.Name := UiFontName;
  Canvas.Font.Height := -Px(13);
  Canvas.Font.Style := [];
  if FHot then
    Canvas.Font.Color := ColorOptionHover
  else
    Canvas.Font.Color := ColorOptionText;
  Canvas.Brush.Style := bsClear;
  TextR := Rect(Box.Right + Px(10), 0, ClientWidth, Height);
  Winapi.Windows.DrawText(Canvas.Handle, PChar(Text), Length(Text), TextR,
    DT_SINGLELINE or DT_VCENTER or DT_LEFT or DT_NOPREFIX or DT_END_ELLIPSIS);
  if Focused and FFocusCue then
  begin
    TextR.Right := Min(TextR.Left + Canvas.TextWidth(Text) + Px(2), ClientWidth);
    TextR.Left := TextR.Left - Px(2);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := Color;
    Canvas.DrawFocusRect(TextR);
  end;
end;

procedure TFlatCheckBox.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  if CanFocus then
    SetFocus;
  Toggle;
end;

procedure TFlatCheckBox.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  if not FFocusCue then
  begin
    FFocusCue := True;
    Invalidate;
  end;
  if Key = vkSpace then
  begin
    Toggle;
    Key := 0;
  end;
end;

procedure TFlatCheckBox.DoEnter;
begin
  inherited;
  FFocusCue := not FocusedByMouse;
  Invalidate;
end;

procedure TFlatCheckBox.DoExit;
begin
  inherited;
  FFocusCue := False;
  Invalidate;
end;

procedure TFlatCheckBox.CMMouseEnter(var Message: TMessage);
begin
  inherited;
  FHot := True;
  Invalidate;
end;

procedure TFlatCheckBox.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  FHot := False;
  Invalidate;
end;

procedure TFlatCheckBox.CMTextChanged(var Message: TMessage);
begin
  inherited;
  Invalidate;
end;

end.
