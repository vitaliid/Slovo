unit Shell.ErrorBannerFrame;

(* TErrorBannerFrame - the error strip under the header (Slovo_04 E-15, C-10).

  36 px, background #fff4e5, text #5c4b1e, the close button ✕ at the right;
  hides itself after 6 s (tmrHide), a new error restarts the 6 s. The banner
  knows only the text it shows: the form turns the TResultError into
  L('error.<code>') (C.3) and places the frame right under the header.

  The .dfm holds the label and the timer; colours and sizes are set here from
  Presentation.Theme and scaled by the form's function (E-14), the close button
  is a TFlatButton created in code. No interface literal in the .dfm (E-05). *)

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Shell.FlatControls;

type
  TErrorBannerFrame = class(TFrame)
    lblMessage: TLabel;
    tmrHide: TTimer;
    procedure tmrHideTimer(Sender: TObject);
  private
    FScale: TFlatScaleFunc;
    FClose: TFlatButton;
    function Px(Value: Integer): Integer;
    procedure CloseClick(Sender: TObject);
    function GetCloseHint: string;
    procedure SetCloseHint(const Value: string);
  public
    // Scale: 96-DPI pixels to the form's - the form's own ScaleValue.
    constructor Create(AOwner: TComponent; const Scale: TFlatScaleFunc); reintroduce;
    // Parents the frame (alTop, hidden) and only then sets its sizes: a frame
    // is rescaled to its parent's DPI when parented, so sizes set before would
    // be scaled twice.
    procedure Attach(AParent: TWinControl);
    // Shows the text and (re)starts the 6 s.
    procedure ShowText(const Text: string);
    procedure HideBanner;
    property CloseHint: string read GetCloseHint write SetCloseHint;
  end;

implementation

uses
  Vcl.Graphics,
  Presentation.Theme;

{$R *.dfm}

const
  TextPx      = 13;
  TextLeft    = 20;
  CloseSize   = 28;
  CloseRight  = 14;

constructor TErrorBannerFrame.Create(AOwner: TComponent; const Scale: TFlatScaleFunc);
begin
  inherited Create(AOwner);
  FScale := Scale;
  Visible := False;
  ParentBackground := False;
  ParentColor := False;
  Color := ColorBannerBack;
  lblMessage.ParentFont := False;
  lblMessage.Font.Name := UiFontName;
  lblMessage.Font.Color := ColorBannerText;

  FClose := TFlatButton.Create(Self, Scale);
  FClose.Parent := Self;
  FClose.Glyph := fgClose;
  FClose.Color := ColorBannerBack;
  FClose.TabStop := False;
  FClose.ShowHint := True;
  FClose.Align := alRight;
  FClose.AlignWithMargins := True;
  FClose.OnClick := CloseClick;
end;

procedure TErrorBannerFrame.Attach(AParent: TWinControl);
var
  Gap: Integer;
begin
  Parent := AParent;
  Align := alTop;
  Height := Px(BannerHeight);
  lblMessage.Font.Height := -Px(TextPx);
  lblMessage.Margins.SetBounds(Px(TextLeft), 0, Px(8), 0);
  Gap := (Px(BannerHeight) - Px(CloseSize)) div 2;
  FClose.Width := Px(CloseSize);
  FClose.Margins.SetBounds(0, Gap, Px(CloseRight), Gap);
end;

function TErrorBannerFrame.Px(Value: Integer): Integer;
begin
  Result := FScale(Value);
end;

procedure TErrorBannerFrame.ShowText(const Text: string);
begin
  lblMessage.Caption := Text;
  tmrHide.Enabled := False;
  tmrHide.Enabled := True;
  Visible := True;
end;

procedure TErrorBannerFrame.HideBanner;
begin
  tmrHide.Enabled := False;
  Visible := False;
end;

procedure TErrorBannerFrame.tmrHideTimer(Sender: TObject);
begin
  HideBanner;
end;

procedure TErrorBannerFrame.CloseClick(Sender: TObject);
begin
  HideBanner;
end;

function TErrorBannerFrame.GetCloseHint: string;
begin
  Result := FClose.Hint;
end;

procedure TErrorBannerFrame.SetCloseHint(const Value: string);
begin
  FClose.Hint := Value;
end;

end.
