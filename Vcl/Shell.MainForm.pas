unit Shell.MainForm;

(* TMainForm - the VCL shell (Slovo_04 Part D) implementing IMainView.

  Built so far: the text column (A.2, A.5, C.4) - clickable breadcrumbs, the
  chapter as one RTF document in a TRichEdit (E-01) with the character-count
  check, zoom (E-11), the ‹ › bar, the shelf and the table of contents
  (Shell.ChapterList, C.5); the library tree on the left (Shell.LibraryTree,
  A.3); the search panel on the right (A.4, Shell.SearchResults) with F3 /
  Shift+F3 over the matches of the open chapter (A.6); the header ☰ · SLOVO ·
  A− 100% A+ · «Тиша» · 🔍 · ⋯ and the error banner under it (E-15,
  Shell.ErrorBannerFrame). There is no menu bar: its items open from ⋯ (pmMain).
  «Тиша» and the narrow-window rules (A.5) - ApplyLayout.

  No interface literal in the .dfm (E-05): every caption comes from
  ApplyLocalization. *)

interface

uses
  System.SysUtils,
  System.Classes,
  System.Actions,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.Menus,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.ActnList,
  Vcl.AppEvnts,
  Core.Domain,
  Core.Contracts,
  Presentation.MainViewModel,
  Presentation.Theme,
  Presentation.ChapterRtf,
  Presentation.Views,
  Presentation.SearchResults,
  Shell.LibraryTree,
  Shell.ChapterList,
  Shell.SearchResults,
  Shell.FlatControls,
  Shell.ErrorBannerFrame;

type
  // Interposer (the .dfm's redReader): ES_DISABLENOSCROLL keeps the reader's own
  // scrollbar always there - disabled when the chapter fits - so the text width
  // never jumps; that scrollbar is pushed out of the column and clipped, the
  // thin bar of the centre shows the scroll (A.5).
  TRichEdit = class(Vcl.ComCtrls.TRichEdit)
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  end;

  // The last chapter shown - re-rendered when the language changes ("Розділ N").
  TShownChapter = (scNone, scBook, scBible);

  TMainForm = class(TForm, IMainView)
    pmMain: TPopupMenu;
    miZoomReset: TMenuItem;
    miLanguage: TMenuItem;
    miLanguageUkrainian: TMenuItem;
    miLanguageRussian: TMenuItem;
    miLanguageEnglish: TMenuItem;
    miViewSeparator: TMenuItem;
    miSQLiteDiagnostics: TMenuItem;
    miHelpSeparator: TMenuItem;
    miExit: TMenuItem;
    alMain: TActionList;
    actZoomIn: TAction;
    actZoomOut: TAction;
    actZoomReset: TAction;
    actPrevChapter: TAction;
    actNextChapter: TAction;
    pnlCenter: TPanel;
    pnlColumn: TPanel;
    pnlCrumbs: TPanel;
    redReader: TRichEdit;
    pnlChapterNav: TPanel;
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure pnlCenterResize(Sender: TObject);
    procedure actZoomInExecute(Sender: TObject);
    procedure actZoomOutExecute(Sender: TObject);
    procedure actZoomResetExecute(Sender: TObject);
    procedure actPrevChapterExecute(Sender: TObject);
    procedure actNextChapterExecute(Sender: TObject);
    procedure alMainUpdate(Action: TBasicAction; var Handled: Boolean);
    procedure miExitClick(Sender: TObject);
    procedure miLanguageItemClick(Sender: TObject);
    procedure miSQLiteDiagnosticsClick(Sender: TObject);
  private
    FScale: TFlatScaleFunc;              // ScaleValue for the controls made in code (E-14)
    FViewModel: TMainViewModel;
    FSettings: ISettings;
    FTheme: TReaderTheme;
    FOnLibraryChanged: TProc<TArray<TLibraryNode>>;
    FOnViewChanged: TProc<TReaderView>;
    FOnChapterLoaded: TProc<TChapterLoadedArgs>;
    FOnBibleChapterLoaded: TProc<TBibleChapterLoadedArgs>;
    FOnSearchCompleted: TProc<TSearchReply>;
    FOnErrorOccurred: TProc<TResultError>;

    FNodes: TArray<TLibraryNode>;        // from OnLibraryChanged: shelf and toc rows come from it
    FZoomStep: Integer;
    FShown: TShownChapter;
    FLastChapter: TChapterLoadedArgs;
    FLastBibleChapter: TBibleChapterLoadedArgs;
    FDoc: TChapterRtf;                   // the map of what the reader shows (E-13 later)
    FReaderWndProc: TWndMethod;

    // Left panel (A.3), created in code: the tree is a VST, built at run time.
    FLeftPanel: TPanel;
    FLibraryTitle: TLabel;
    FLibraryTree: TLibraryTree;
    FCheckedCount: Integer;              // "Відмічені книги · N" is counted by the form (R4-42)
    procedure CreateLeftPanel;
    procedure LibraryNodeActivated(const Node: TLibraryNode);
    procedure LibraryNodeChecked(const Node: TLibraryNode; Checked: Boolean);

  private
    // Shelf and table of contents (A.2, C.5) and the breadcrumbs.
    FChapterList: TChapterList;
    FLeftPad: Integer;
    FCrumbActions: TArray<TProc>;
    function FindNode(Kind: TLibraryNodeKind; const ModuleId: TModuleId; const BookCode: TBookCode = ''): Integer;
    function IsUnder(Index, Ancestor: Integer): Boolean;
    procedure AddCrumb(const Caption: string; const Action: TProc);
    procedure CrumbClick(Sender: TObject);
    procedure CrumbMouseEnter(Sender: TObject);
    procedure CrumbMouseLeave(Sender: TObject);

  private
    // Right panel (A.4), created in code like the left one; the status line
    // and the list are the form's (C.1: the empty query / scope never reach
    // the ViewModel).
    FRightPanel: TPanel;
    FSearchTitle: TLabel;
    FSearchEdit: TEdit;
    FSearchRow: TPanel;
    FSearchIcon: TPaintBox;
    FScopeTitle: TLabel;
    FScope: TScopeSwitch;
    FExactPhrase: TFlatCheckBox;
    FWordForms: TFlatCheckBox;
    FSearchStatus: TLabel;
    FResultList: TSearchResultList;
    FLastReply: TSearchReply;
    FHasReply: Boolean;
    FSearchDone: Boolean;
    FSearchStatusKey: string;            // '' = empty line; kept to re-localize
    FSearchStatusArg: Integer;           // -1 = the key takes no argument
    FSearchHint: string;
    FSearchEditWndProc: TWndMethod;
    procedure SearchEditWndProc(var Message: TMessage);
    procedure SearchIconPaint(Sender: TObject);
    procedure SearchEditChange(Sender: TObject);
    procedure CreateRightPanel;
    procedure OpenSearch;
    procedure RunSearch;
    procedure ShowSearchStatus(const Key: string; Arg: Integer = -1);
    procedure ShowSearchReply(const Reply: TSearchReply);
    procedure SearchResultOpened(Section: TResultSectionKind; Index: Integer);
    procedure SearchEditKeyPress(Sender: TObject; var Key: Char);
    procedure FormKeyPress(Sender: TObject; var Key: Char);
    procedure MoveHit(Delta: Integer);

  private
    // Header (E-15, mockup "Читання v2"), created in code: ☰ · SLOVO · A− 100% A+ ·
    // «Тиша» · 🔍 · ⋯; the error banner right under it.
    FHeader: TPanel;
    FLibraryButton: TFlatButton;
    FBrand: TLabel;
    FZoomOutButton: TFlatButton;
    FZoomLabel: TLabel;
    FZoomInButton: TFlatButton;
    FSilenceButton: TFlatButton;
    FSearchButton: TFlatButton;
    FMoreButton: TFlatButton;
    FBanner: TErrorBannerFrame;
    FBannerKey: string;                  // the shown error's text key - re-localized
    procedure CreateHeader;
    procedure HeaderResize(Sender: TObject);
    procedure LibraryButtonClick(Sender: TObject);
    procedure SearchButtonClick(Sender: TObject);
    procedure MoreButtonClick(Sender: TObject);

  private
    // Thin scrollbars (mockup ::-webkit-scrollbar 9 px), full height at the
    // right edge of each zone (Vitalii, 2026-11-06): the library, the centre
    // (the reader or the shelf / toc list - re-attached in ShowView), the
    // results. The controls' own scrollbars are clipped in their hosts.
    FLeftBar: TThinScrollBar;
    FCenterBar: TThinScrollBar;
    FRightBar: TThinScrollBar;
    FLibraryHost: TPanel;
    FResultsHost: TPanel;
    FReaderHost: TPanel;
    procedure LibraryHostResize(Sender: TObject);
    procedure ResultsHostResize(Sender: TObject);
    procedure ReaderHostResize(Sender: TObject);

  private
    // A.5, as the mockup: the user's choice of the side panels (settings.ini)
    // and what the window shows are apart - a narrow window hides a panel only
    // while it is narrow (< 1180: the right one, < 780: the left one), a panel
    // opened by its button in a narrow window stays ("forced"), below 1180 the
    // panel opened last wins. «Тиша» hides the header and both panels; the
    // mouse in the top 28 px brings the header back in the flow (R4-36).
    FLeftWanted: Boolean;
    FRightWanted: Boolean;
    FLeftForced: Boolean;
    FRightForced: Boolean;
    FRightLast: Boolean;                 // below 1180 the right panel was opened last
    FSilence: Boolean;
    FPeek: Boolean;
    FAppEvents: TApplicationEvents;
    procedure ApplyLayout;
    procedure SetLeftWanted(Value: Boolean);
    procedure SetRightWanted(Value: Boolean);
    procedure SetSilence(Value: Boolean);
    procedure SilenceButtonClick(Sender: TObject);
    procedure ScopeChanged(Sender: TObject);
    procedure FormResized(Sender: TObject);
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);

  private
    // Navigator of the matches in the open chapter (E-08, A.6), centred between
    // the chapter buttons; visible only when the chapter has matches.
    FHitNav: TPanel;
    FHitBox: TPanel;
    FHitPrev: TFlatButton;
    FHitLabel: TLabel;
    FHitNext: TFlatButton;
    FHitQuery: string;                   // the query the shown highlights came from
    FFocusMatch: Integer;                // the current word in the open chapter; -1 = none
    FMatchCount: Integer;                // highlighted words in the open chapter
    procedure CreateHitNav;
    procedure UpdateHitNav;

  private
    // The chapter bar under the text (A.2, as the mockup's end-of-chapter
    // links, but fixed at the bottom - Vitalii, 2026-11-05): a hairline over
    // the text width, "← Розділ 2 · Створення" left, "Розділ 4 · … →" right,
    // EB Garamond 17 px #6b6b6b, hover - the accent; the match navigator
    // between them.
    FPrevLink: TLabel;
    FNextLink: TLabel;
    procedure CreateChapterLinks;
    procedure UpdateChapterLinks;
    procedure ChapterBarResize(Sender: TObject);
    function NeighbourCaption(Delta: Integer; out Caption: string): Boolean;
    procedure LinkMouseEnter(Sender: TObject);
    procedure LinkMouseLeave(Sender: TObject);
    procedure PrevLinkClick(Sender: TObject);
    procedure NextLinkClick(Sender: TObject);
    procedure HitNavResize(Sender: TObject);
    procedure HitPrevClick(Sender: TObject);
    procedure HitNextClick(Sender: TObject);
    function FocusReaderOrList: Boolean;

    procedure ApplyLocalization;
    procedure UpdateStatus;
    procedure ShowView(View: TReaderView);
    procedure FillShelf;
    procedure FillToc;
    procedure GoUp;
    // FocusMatch - the current word (E-08, by words); -1 = take the first word
    // of the paragraph Args.Focus names (a search result), if any.
    procedure RenderChapter(const Args: TChapterLoadedArgs; FocusMatch: Integer = -1);
    procedure RenderBibleChapter(const Args: TBibleChapterLoadedArgs; FocusMatch: Integer = -1);
    procedure ShowDocument(var Doc: TChapterRtf; ParagraphFocus, FocusMatch: Integer;
      const Rebuild: TFunc<Integer, TChapterRtf>);
    procedure LoadDocument(const Doc: TChapterRtf; Focus: Integer);
    procedure UpdateCrumbs;
    procedure SetZoomStep(Value: Integer);
    procedure ReaderWndProc(var Message: TMessage);
    procedure HideReaderCaret;
    procedure ShowError(Error: TResultError);
    procedure HandleException(Sender: TObject; E: Exception);
    procedure RestoreGeometry;
  public
    destructor Destroy; override;
    // IMainView
    procedure Bind(ViewModel: TMainViewModel; const Settings: ISettings; const Theme: TReaderTheme);
    procedure Unbind;
  end;

var
  MainForm: TMainForm;

// Banner text key for a TResultError (Slovo_04 C.3).
function ErrorKey(Error: TResultError): string;

implementation

uses
  System.Types,
  System.UITypes,
  System.Math,
  Winapi.RichEdit,
  Vcl.Dialogs,
  Presentation.Localization,
  Infrastructure.SQLite3.Database,
  Shell.RichEdit,
  VirtualTrees.BaseTree;

{$R *.dfm}

const
  MinZoomStep = -4;                      // E-11: 15..30 px
  MaxZoomStep = 6;

function ErrorKey(Error: TResultError): string;
const
  Keys: array[TResultError] of string = (
    '', 'error.notFound', 'error.moduleCorrupted', 'error.ioFailure', 'error.invalidQuery',
    'error.unsupportedModule', 'error.unsupportedSchema', 'error.unexpected');
begin
  Result := Keys[Error];
end;

function ZoomPx(Step: Integer): Double;
begin
  Result := BaseTextPx + ZoomStepPx * Step;
end;

{ TRichEdit }

procedure TRichEdit.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := Params.Style or $2000;           // ES_DISABLENOSCROLL
end;

{ scrolling of the VSTs for the thin bars }

type
  TTreeAccess = class(TBaseVirtualTree);  // RangeY is protected in VST 8.3

function TreeMetrics(Tree: TBaseVirtualTree): TScrollMetricsFunc;
begin
  Result := function: TScrollMetrics
    begin
      Result.Range := Integer(TTreeAccess(Tree).RangeY);
      Result.Page := Tree.ClientHeight;
      Result.Pos := -Tree.OffsetY;
    end;
end;

function TreeScrollTo(Tree: TBaseVirtualTree): TScrollToProc;
begin
  Result := procedure(Pos: Integer)
    begin
      Tree.OffsetY := -Pos;
    end;
end;

{ form }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FScale := function(Value: Integer): Integer
    begin
      Result := ScaleValue(Value);
    end;
  // A.6: Ctrl+= / Ctrl+- / Ctrl+0, numeric keypad as the second shortcut.
  actZoomIn.ShortCut := ShortCut(VK_OEM_PLUS, [ssCtrl]);
  actZoomIn.SecondaryShortCuts.Add(ShortCutToText(ShortCut(VK_ADD, [ssCtrl])));
  actZoomOut.ShortCut := ShortCut(VK_OEM_MINUS, [ssCtrl]);
  actZoomOut.SecondaryShortCuts.Add(ShortCutToText(ShortCut(VK_SUBTRACT, [ssCtrl])));
  actZoomReset.ShortCut := ShortCut(Ord('0'), [ssCtrl]);

  pnlCenter.Color := ColorBackground;
  pnlColumn.Color := ColorBackground;
  pnlChapterNav.Color := ColorBackground;
  redReader.Color := ColorBackground;
  pnlCrumbs.Color := ColorBackground;
  pnlCrumbs.Margins.Top := ScaleValue(TextColumnTop);
  pnlCrumbs.Margins.Bottom := ScaleValue(CrumbsBottom);
  pnlCrumbs.Height := ScaleValue(18);
  pnlChapterNav.AlignWithMargins := True;

  // The reader in its own host: placed by hand (ReaderHostResize), wider than
  // the column by its clipped scrollbar.
  FReaderHost := TPanel.Create(Self);
  FReaderHost.Parent := pnlColumn;
  FReaderHost.Align := alClient;
  FReaderHost.BevelOuter := bvNone;
  FReaderHost.ParentBackground := False;
  FReaderHost.Color := ColorBackground;
  redReader.Parent := FReaderHost;
  redReader.Align := alNone;
  FReaderHost.OnResize := ReaderHostResize;
  FCenterBar := TThinScrollBar.Create(Self, FScale);
  FCenterBar.Parent := pnlCenter;
  FCenterBar.BringToFront;

  // E-11: Ctrl+wheel is ours, so msftedit's own zoom never drifts from the setting.
  FReaderWndProc := redReader.WindowProc;
  redReader.WindowProc := ReaderWndProc;

  CreateHeader;                          // alTop first: above the side panels
  CreateLeftPanel;
  CreateRightPanel;
  CreateChapterLinks;
  CreateHitNav;
  OnKeyPress := FormKeyPress;
  OnResize := FormResized;
  FScope.OnChange := ScopeChanged;
  FAppEvents := TApplicationEvents.Create(Self);
  FAppEvents.OnMessage := AppMessage;

  FChapterList := TChapterList.Create(Self, pnlColumn,
    function(Value: Integer): Integer
    begin
      Result := ScaleValue(Value);
    end);
  FChapterList.OnOpen := procedure(NodeIndex: Integer)
    begin
      LibraryNodeActivated(FNodes[NodeIndex]);
    end;
  pnlCenterResize(nil);                  // the list exists now: give it the margin
end;

destructor TMainForm.Destroy;
begin
  FChapterList.Free;                     // the controls themselves are owned by the form
  FLibraryTree.Free;
  FResultList.Free;
  inherited;
end;

// E-15, mockup "Читання v2": 57 px with a 1 px line below, padding 12 20;
// the buttons are placed by HeaderResize.
procedure TMainForm.CreateHeader;

  function NewButton(Glyph: TFlatButtonGlyph; const Click: TNotifyEvent): TFlatButton;
  begin
    Result := TFlatButton.Create(Self, FScale);
    Result.Parent := FHeader;
    Result.Glyph := Glyph;
    Result.ShowHint := True;
    Result.OnClick := Click;
  end;

  function NewText(Px: Integer): TTrackedLabel;
  begin
    Result := TTrackedLabel.Create(Self);
    Result.Parent := FHeader;
    Result.ShowAccelChar := False;
    Result.Transparent := True;
    Result.Font.Name := UiFontName;
    Result.Font.Height := -ScaleValue(Px);
    Result.Font.Color := ColorMuted;
  end;

var
  Line: TPanel;
begin
  FHeader := TPanel.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FHeader.Top := 0;
  FHeader.Height := ScaleValue(HeaderHeight);
  FHeader.BevelOuter := bvNone;
  FHeader.ParentBackground := False;
  FHeader.Color := ColorBackground;

  Line := TPanel.Create(Self);
  Line.Parent := FHeader;
  Line.Align := alBottom;
  Line.Height := 1;
  Line.BevelOuter := bvNone;
  Line.ParentBackground := False;
  Line.Color := TColor($00E6E6E6);       // rgba(0,0,0,.09)

  FLibraryButton := NewButton(fgMenu, LibraryButtonClick);
  FBrand := NewText(11);
  // "Slovo": caps, letter-spacing .14em.
  FBrand.Caption := 'SLOVO';
  (FBrand as TTrackedLabel).Tracking := 0.14;
  FZoomOutButton := NewButton(fgNone, actZoomOutExecute);
  FZoomOutButton.Caption := 'A'#$2212;
  FZoomOutButton.FontPx := 13;
  FZoomLabel := NewText(11);
  FZoomLabel.AutoSize := False;
  FZoomLabel.Alignment := taCenter;
  FZoomLabel.Layout := tlCenter;
  FZoomInButton := NewButton(fgNone, actZoomInExecute);
  FZoomInButton.Caption := 'A+';
  FZoomInButton.FontPx := 15;
  FSilenceButton := NewButton(fgNone, SilenceButtonClick);
  FSilenceButton.Pill := True;
  FSilenceButton.FontPx := 12;
  FSearchButton := NewButton(fgSearch, SearchButtonClick);
  FMoreButton := NewButton(fgMore, MoreButtonClick);
  FHeader.OnResize := HeaderResize;

  FBanner := TErrorBannerFrame.Create(Self, FScale);
  FBanner.Attach(Self);
end;

// Mockup: the left group ☰ · SLOVO, gap 14; the right group A− 100% A+ (gap 2,
// the label 42 px), «Тиша», 🔍, gap 14; ⋯ right after 🔍.
procedure TMainForm.HeaderResize(Sender: TObject);
var
  Mid, X, B, W: Integer;

  procedure PlaceAt(Control: TControl; Left, Width, Height: Integer);
  begin
    Control.SetBounds(Left, Mid - Height div 2, Width, Height);
  end;

begin
  if FMoreButton = nil then
    Exit;
  Mid := (FHeader.ClientHeight - 1) div 2;
  B := ScaleValue(32);
  X := ScaleValue(20);
  PlaceAt(FLibraryButton, X, B, B);
  Inc(X, B + ScaleValue(14));
  PlaceAt(FBrand, X, FBrand.Width, FBrand.Height);

  X := FHeader.ClientWidth - ScaleValue(20) - B;
  PlaceAt(FMoreButton, X, B, B);
  Dec(X, ScaleValue(2) + B);
  PlaceAt(FSearchButton, X, B, B);
  W := FSilenceButton.PillWidth;
  Dec(X, ScaleValue(14) + W);
  PlaceAt(FSilenceButton, X, W, ScaleValue(30));
  Dec(X, ScaleValue(14) + B);
  PlaceAt(FZoomInButton, X, B, B);
  Dec(X, ScaleValue(2) + ScaleValue(42));
  PlaceAt(FZoomLabel, X, ScaleValue(42), B);
  Dec(X, ScaleValue(2) + B);
  PlaceAt(FZoomOutButton, X, B, B);
end;

procedure TMainForm.LibraryButtonClick(Sender: TObject);
begin
  SetLeftWanted(not FLeftPanel.Visible);
end;

{ A.5: side panels, narrow window, «Тиша» }

procedure TMainForm.SetLeftWanted(Value: Boolean);
begin
  FLeftWanted := Value;
  if Value then
  begin
    FLeftForced := True;                 // shown even below 780 until the window widens
    FRightForced := False;
    FRightLast := False;
  end;
  FSettings.SetLeftPanelVisible(Value);
  FSilence := False;
  FPeek := False;
  ApplyLayout;
end;

procedure TMainForm.SetRightWanted(Value: Boolean);
begin
  FRightWanted := Value;
  FRightForced := Value;                 // shown even below 1180 until the window widens
  if Value then
    FRightLast := True;
  FSettings.SetRightPanelVisible(Value);
  FSilence := False;
  FPeek := False;
  ApplyLayout;
end;

procedure TMainForm.SetSilence(Value: Boolean);
begin
  if FSilence = Value then
    Exit;
  FSilence := Value;
  FPeek := False;
  ApplyLayout;
end;

procedure TMainForm.SilenceButtonClick(Sender: TObject);
begin
  SetSilence(not FSilence);
end;

// A.5: "Відмічені книги" opens the left panel - the check boxes are there.
procedure TMainForm.ScopeChanged(Sender: TObject);
begin
  if not FScope.WholeLibrary and not FLeftPanel.Visible then
    SetLeftWanted(True);
end;

procedure TMainForm.LibraryHostResize(Sender: TObject);
begin
  FitHidingScrollBar(FLibraryTree.Control, FLibraryHost.ClientRect);
end;

procedure TMainForm.ResultsHostResize(Sender: TObject);
begin
  FitHidingScrollBar(FResultList.Control, FResultsHost.ClientRect);
end;

// The text starts after the column's left margin (A.5).
procedure TMainForm.ReaderHostResize(Sender: TObject);
begin
  FitHidingScrollBar(redReader, Rect(FLeftPad, 0, FReaderHost.ClientWidth, FReaderHost.ClientHeight));
end;

procedure TMainForm.FormResized(Sender: TObject);
begin
  ApplyLayout;
end;

procedure TMainForm.ApplyLayout;
var
  W: Integer;
  ShowLeft, ShowRight, ShowHeader: Boolean;

  function Loses(Panel: TWinControl; Shown: Boolean): Boolean;
  begin
    Result := Panel.Visible and not Shown and Panel.ContainsControl(ActiveControl);
  end;

begin
  if FSettings = nil then                // before Bind: nothing is decided yet
    Exit;
  W := ClientWidth;
  if W >= ScaleValue(NarrowWidth) then
    FRightForced := False;
  if W >= ScaleValue(VeryNarrowWidth) then
    FLeftForced := False;
  ShowLeft := FLeftWanted and ((W >= ScaleValue(VeryNarrowWidth)) or FLeftForced) and not FSilence;
  ShowRight := FRightWanted and ((W >= ScaleValue(NarrowWidth)) or FRightForced) and not FSilence;
  if ShowLeft and ShowRight and (W < ScaleValue(NarrowWidth)) then
    if FRightLast then
      ShowLeft := False
    else
      ShowRight := False;
  ShowHeader := not FSilence or FPeek;

  // The focus must not stay in a control that goes away.
  if Loses(FLeftPanel, ShowLeft) or Loses(FRightPanel, ShowRight) or Loses(FHeader, ShowHeader) then
    FocusReaderOrList;

  DisableAlign;
  try
    if FHeader.Visible <> ShowHeader then
    begin
      FHeader.Top := 0;                  // alTop keeps the order of Top: above the banner
      FHeader.Visible := ShowHeader;
    end;
    FLeftPanel.Visible := ShowLeft;
    FRightPanel.Visible := ShowRight;
  finally
    EnableAlign;
  end;

  if FSilence then
    FSilenceButton.Caption := L('header.silence.exit')
  else
    FSilenceButton.Caption := L('header.silence');
  HeaderResize(nil);
  pnlCenterResize(nil);
end;

// «Тиша»: TApplicationEvents.OnMessage sees WM_MOUSEMOVE over every child,
// where TForm.OnMouseMove does not (A.5).
procedure TMainForm.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  P: TPoint;
  C: TWinControl;
begin
  // Mockup: the whole centre scrolls - the wheel over its margins, crumbs or
  // chapter bar goes to the reader or the list.
  if Msg.message = WM_MOUSEWHEEL then
  begin
    C := FindControl(Msg.hwnd);
    if (C <> nil) and (FCenterBar.Target <> nil) and (C <> FCenterBar.Target)
      and ((C = pnlCenter) or pnlCenter.ContainsControl(C)) then
    begin
      SendMessage(FCenterBar.Target.Handle, WM_MOUSEWHEEL, Msg.wParam, Msg.lParam);
      Handled := True;
    end;
    Exit;
  end;
  if not FSilence or (Msg.message <> WM_MOUSEMOVE) then
    Exit;
  P := ScreenToClient(Msg.pt);
  if (P.X < 0) or (P.X >= ClientWidth) then
    Exit;
  if not FPeek and (P.Y >= 0) and (P.Y < ScaleValue(SilencePeekStrip)) then
  begin
    FPeek := True;
    ApplyLayout;
  end
  else if FPeek and (P.Y >= FHeader.Height) then
  begin
    FPeek := False;
    ApplyLayout;
  end;
end;

// The former menu bar, under ⋯: aligned to the button's right edge.
procedure TMainForm.MoreButtonClick(Sender: TObject);
var
  P: TPoint;
begin
  P := FMoreButton.ClientToScreen(Point(FMoreButton.Width, FMoreButton.Height + ScaleValue(4)));
  pmMain.Alignment := paRight;
  pmMain.Popup(P.X, P.Y);
end;

procedure TMainForm.CreateLeftPanel;
var
  Border, Content: TPanel;
  Title: TTrackedLabel;
begin
  FLeftPanel := TPanel.Create(Self);
  FLeftPanel.Parent := Self;
  FLeftPanel.Align := alLeft;
  FLeftPanel.Width := ScaleValue(LeftPanelWidth);
  FLeftPanel.BevelOuter := bvNone;
  FLeftPanel.ParentBackground := False;
  FLeftPanel.Color := ColorBackground;

  // Mockup: border-right 1px rgba(0,0,0,.09); full height only beside a client
  // panel (alTop is laid out before alRight).
  Border := TPanel.Create(Self);
  Border.Parent := FLeftPanel;
  Border.Align := alRight;
  Border.Width := 1;
  Border.BevelOuter := bvNone;
  Border.ParentBackground := False;
  Border.Color := TColor($00E6E6E6);
  FLeftBar := TThinScrollBar.Create(Self, FScale);
  FLeftBar.Left := Border.Left - FLeftBar.Width;     // alRight: left of the border
  FLeftBar.Parent := FLeftPanel;
  FLeftBar.Align := alRight;
  Content := TPanel.Create(Self);
  Content.Parent := FLeftPanel;
  Content.Align := alClient;
  Content.BevelOuter := bvNone;
  Content.ParentBackground := False;
  Content.Color := ColorBackground;

  Title := TTrackedLabel.Create(Self);
  Title.Tracking := 0.11;
  FLibraryTitle := Title;
  FLibraryTitle.Parent := Content;
  FLibraryTitle.Align := alTop;
  FLibraryTitle.AlignWithMargins := True;
  // Mockup: aside padding 26 10 40 18, the caption 10.5 px caps, muted, 18 px below.
  FLibraryTitle.Margins.SetBounds(ScaleValue(26), ScaleValue(26), ScaleValue(12), ScaleValue(18));
  FLibraryTitle.Font.Name := UiFontName;
  FLibraryTitle.Font.Height := -ScaleValue(11);
  FLibraryTitle.Font.Color := ColorMuted;

  FLibraryHost := TPanel.Create(Self);
  FLibraryHost.Parent := Content;
  FLibraryHost.Align := alClient;
  FLibraryHost.AlignWithMargins := True;
  FLibraryHost.Margins.SetBounds(ScaleValue(10), 0, ScaleValue(4), ScaleValue(8));
  FLibraryHost.BevelOuter := bvNone;
  FLibraryHost.ParentBackground := False;
  FLibraryHost.Color := ColorBackground;
  FLibraryHost.OnResize := LibraryHostResize;
  FLibraryTree := TLibraryTree.Create(Self, FLibraryHost,
    function(Value: Integer): Integer
    begin
      Result := ScaleValue(Value);
    end);
  FLibraryTree.Control.Align := alNone;
  FLibraryTree.Control.ScrollBarOptions.AlwaysVisible := True;
  FLeftBar.Attach(FLibraryTree.Control, TreeMetrics(FLibraryTree.Control),
    TreeScrollTo(FLibraryTree.Control));
  FLibraryTree.OnActivate := LibraryNodeActivated;
  FLibraryTree.OnCheck := LibraryNodeChecked;
end;

// A.4, mockup "Читання v2": 320 px, a 1 px line on the left, padding 26 22;
// from the top - "ПОШУК", the field (EB Garamond 19 px) over a line, "ДЕ ШУКАТИ"
// and the scope pill, the two square options (Shell.FlatControls), a line, the
// status, the list.
procedure TMainForm.SearchIconPaint(Sender: TObject);
begin
  PaintLineGlyph(FSearchIcon.Canvas, fgSearch,
    Rect(0, 0, ScaleValue(14), FSearchIcon.Height), ScaleValue(14), ColorMarker);
end;

procedure TMainForm.CreateRightPanel;
var
  Order: Integer;
  Content: TPanel;

  procedure Place(Control: TControl; Left, Top, Right, Bottom: Integer);
  begin
    Inc(Order);
    Control.Parent := Content;
    Control.Top := Order * 1000;         // alTop keeps the order of Top
    Control.Align := alTop;
    Control.AlignWithMargins := True;
    Control.Margins.SetBounds(ScaleValue(Left), ScaleValue(Top), ScaleValue(Right), ScaleValue(Bottom));
  end;

  function NewCaption(Px: Integer; Tracking: Single): TLabel;
  var
    Caption: TTrackedLabel;
  begin
    Caption := TTrackedLabel.Create(Self);
    Caption.Tracking := Tracking;
    Result := Caption;
    Result.Font.Name := UiFontName;
    Result.ShowAccelChar := False;
    Result.Font.Height := -ScaleValue(Px);
    Result.Font.Color := ColorMuted;
  end;

  function NewLine(Color: TColor): TPanel;
  begin
    Result := TPanel.Create(Self);
    Result.BevelOuter := bvNone;
    Result.ParentBackground := False;
    Result.Color := Color;
    Result.Height := 1;
  end;

var
  Border: TPanel;
begin
  Order := 0;
  FRightPanel := TPanel.Create(Self);
  FRightPanel.Parent := Self;
  FRightPanel.Align := alRight;
  FRightPanel.Width := ScaleValue(RightPanelWidth);
  FRightPanel.BevelOuter := bvNone;
  FRightPanel.ParentBackground := False;
  FRightPanel.Color := ColorBackground;

  Border := NewLine(TColor($00E6E6E6));  // rgba(0,0,0,.09)
  Border.Parent := FRightPanel;
  Border.Align := alLeft;
  Border.Width := 1;
  // The line runs the full height only beside a client panel: VCL lays out
  // alTop children before alLeft ones.
  FRightBar := TThinScrollBar.Create(Self, FScale);
  FRightBar.Parent := FRightPanel;
  FRightBar.Align := alRight;
  Content := TPanel.Create(Self);
  Content.Parent := FRightPanel;
  Content.Align := alClient;
  Content.BevelOuter := bvNone;
  Content.ParentBackground := False;
  Content.Color := ColorBackground;

  FSearchTitle := NewCaption(11, 0.11);
  Place(FSearchTitle, 22, 26, 22, 16);

  FSearchEdit := TEdit.Create(Self);
  FSearchEdit.BorderStyle := bsNone;
  FSearchEdit.ParentColor := False;
  FSearchEdit.Color := ColorBackground;
  FSearchEdit.Font.Color := ColorHeading;
  FSearchEdit.OnKeyPress := SearchEditKeyPress;
  FSearchEdit.OnChange := SearchEditChange;
  // The placeholder is painted by us: the native cue banner (TextHint) does
  // not show in a borderless edit (seen on Windows 11).
  FSearchEditWndProc := FSearchEdit.WindowProc;
  FSearchEdit.WindowProc := SearchEditWndProc;
  // Mockup: the 14 px magnifier #8a8a8a, gap 10, then the field.
  FSearchRow := TPanel.Create(Self);
  FSearchRow.BevelOuter := bvNone;
  FSearchRow.ParentBackground := False;
  FSearchRow.Color := ColorBackground;
  Place(FSearchRow, 22, 0, 22, 0);
  FSearchIcon := TPaintBox.Create(Self);
  FSearchIcon.Parent := FSearchRow;
  FSearchIcon.Align := alLeft;
  FSearchIcon.Width := ScaleValue(14 + 10);
  FSearchIcon.OnPaint := SearchIconPaint;
  FSearchEdit.Parent := FSearchRow;
  FSearchEdit.Align := alClient;
  Place(NewLine(TColor($00D1D1D1)), 22, 9, 22, 0);   // rgba(0,0,0,.18)

  FScopeTitle := NewCaption(11, 0.08);
  Place(FScopeTitle, 22, 20, 22, 8);
  FScope := TScopeSwitch.Create(Self,
    function(Value: Integer): Integer
    begin
      Result := ScaleValue(Value);
    end);
  Place(FScope, 22, 0, 22, 0);

  FExactPhrase := TFlatCheckBox.Create(Self,
    function(Value: Integer): Integer
    begin
      Result := ScaleValue(Value);
    end);
  Place(FExactPhrase, 22, 20, 22, 0);
  FWordForms := TFlatCheckBox.Create(Self,
    function(Value: Integer): Integer
    begin
      Result := ScaleValue(Value);
    end);
  FWordForms.ShowHint := True;
  Place(FWordForms, 22, 11, 22, 0);

  Place(NewLine(TColor($00E6E6E6)), 22, 24, 22, 0);
  FSearchStatus := NewCaption(11, 0.1);
  Place(FSearchStatus, 22, 14, 22, 8);

  FResultsHost := TPanel.Create(Self);
  FResultsHost.Parent := Content;
  FResultsHost.Top := Order * 1000 + 1000;           // after the alTop rows
  FResultsHost.Align := alClient;
  FResultsHost.AlignWithMargins := True;
  FResultsHost.Margins.SetBounds(ScaleValue(9), 0, ScaleValue(9), ScaleValue(8));
  FResultsHost.BevelOuter := bvNone;
  FResultsHost.ParentBackground := False;
  FResultsHost.Color := ColorBackground;
  FResultsHost.OnResize := ResultsHostResize;
  FResultList := TSearchResultList.Create(Self, FResultsHost,
    function(Value: Integer): Integer
    begin
      Result := ScaleValue(Value);
    end);
  FResultList.Control.Align := alNone;
  FResultList.Control.ScrollBarOptions.AlwaysVisible := True;
  FRightBar.Attach(FResultList.Control, TreeMetrics(FResultList.Control),
    TreeScrollTo(FResultList.Control));
  FResultList.SectionCaption := function(Section: TResultSectionKind): string
    begin
      if Section = rsBooks then
        Result := L('search.section.books')
      else
        Result := L('search.section.bible');
    end;
  FResultList.OnOpen := SearchResultOpened;
  FSearchStatusArg := -1;
end;

{ IMainView }

procedure TMainForm.Bind(ViewModel: TMainViewModel; const Settings: ISettings;
  const Theme: TReaderTheme);
begin
  FViewModel := ViewModel;
  FSettings := Settings;
  FTheme := Theme;

  FOnLibraryChanged := procedure(Nodes: TArray<TLibraryNode>)
    begin
      FNodes := Nodes;
      FLibraryTree.Build(Nodes);
      FCheckedCount := FLibraryTree.CheckedCount;
      UpdateStatus;
    end;
  FOnViewChanged := procedure(View: TReaderView) begin ShowView(View); end;
  // The hits of a loaded chapter come from the active query (E-08); a later
  // search does not reload the open chapter, so the navigator keeps the text of
  // the query its highlights came from - F3 and a language change re-render
  // without touching it.
  FOnChapterLoaded := procedure(Args: TChapterLoadedArgs)
    begin
      FHitQuery := FViewModel.ActiveQuery.Text;
      RenderChapter(Args);
    end;
  FOnBibleChapterLoaded := procedure(Args: TBibleChapterLoadedArgs)
    begin
      FHitQuery := FViewModel.ActiveQuery.Text;
      RenderBibleChapter(Args);
    end;
  FOnSearchCompleted := procedure(Reply: TSearchReply) begin ShowSearchReply(Reply); end;
  FOnErrorOccurred := procedure(Error: TResultError) begin ShowError(Error); end;

  FViewModel.OnLibraryChanged.Add(FOnLibraryChanged);
  FViewModel.OnViewChanged.Add(FOnViewChanged);
  FViewModel.OnChapterLoaded.Add(FOnChapterLoaded);
  FViewModel.OnBibleChapterLoaded.Add(FOnBibleChapterLoaded);
  FViewModel.OnSearchCompleted.Add(FOnSearchCompleted);
  FViewModel.OnErrorOccurred.Add(FOnErrorOccurred);

  Application.OnException := HandleException;
  Font.Name := FTheme.UiFont;
  FLibraryTree.ApplyFont(FTheme.UiFont);
  FChapterList.ApplyFonts(FTheme.TextFont, FTheme.UiFont);
  FResultList.ApplyFonts(FTheme.TextFont, FTheme.UiFont);
  FSearchEdit.Font.Name := FTheme.TextFont;
  FPrevLink.Font.Name := FTheme.TextFont;
  FNextLink.Font.Name := FTheme.TextFont;
  FSearchEdit.Font.Height := -ScaleValue(19);
  // EB Garamond 19 px with its descenders: the edit's own height is taken
  // before the font (the placeholder was cut at the bottom).
  FSearchRow.Height := ScaleValue(28);
  FScope.WholeLibrary := FSettings.GetSearchWholeLibrary;
  FExactPhrase.Checked := FSettings.GetExactPhrase;
  FWordForms.Checked := FSettings.GetWordForms;
  FLeftWanted := FSettings.GetLeftPanelVisible;
  FRightWanted := FSettings.GetRightPanelVisible;
  FZoomStep := EnsureRange(FSettings.GetZoomStep, MinZoomStep, MaxZoomStep);
  PrepareReader(redReader);
  SetZoomPx(redReader, ZoomPx(FZoomStep));
  ApplyLocalization;
  RestoreGeometry;
  ApplyLayout;

  FViewModel.Start;                      // phase 1: position or Shelf (E-16)
end;

procedure TMainForm.Unbind;
begin
  if FViewModel = nil then
    Exit;
  Application.OnException := nil;
  FViewModel.OnLibraryChanged.Remove(FOnLibraryChanged);
  FViewModel.OnViewChanged.Remove(FOnViewChanged);
  FViewModel.OnChapterLoaded.Remove(FOnChapterLoaded);
  FViewModel.OnBibleChapterLoaded.Remove(FOnBibleChapterLoaded);
  FViewModel.OnSearchCompleted.Remove(FOnSearchCompleted);
  FViewModel.OnErrorOccurred.Remove(FOnErrorOccurred);

  if WindowState = wsNormal then
    FSettings.SetWindowBounds(BoundsRect, False)
  else
    FSettings.SetWindowBounds(BoundsRect, WindowState = wsMaximized);
  FSettings.SetZoomStep(FZoomStep);
  FSettings.SetLeftPanelVisible(FLeftWanted);
  FSettings.SetRightPanelVisible(FRightWanted);
  FSettings.Save;
  FViewModel := nil;
end;

procedure TMainForm.RestoreGeometry;
var
  R: TRect;
  Maximized: Boolean;
begin
  // A monitor that is gone must not leave the window off-screen.
  if FSettings.GetWindowBounds(R, Maximized) and Screen.DesktopRect.IntersectsWith(R) then
  begin
    Position := poDesigned;
    BoundsRect := R;
  end;
  if Maximized then
    WindowState := wsMaximized;
end;

{ Localization (E-05): every control that shows text is listed here. }

procedure TMainForm.ApplyLocalization;
begin
  Caption := L('app.title');
  miExit.Caption := L('menu.file.exit');
  actZoomIn.Caption := L('header.bigger');
  actZoomOut.Caption := L('header.smaller');
  actZoomReset.Caption := L('menu.view.zoomReset');
  miViewSeparator.Caption := cLineCaption;
  miLanguage.Caption := L('menu.view.language');
  miSQLiteDiagnostics.Caption := L('menu.help.sqliteDiagnostics');
  miHelpSeparator.Caption := cLineCaption;

  FLibraryButton.Hint := L('header.library');
  FZoomOutButton.Hint := L('header.smaller');
  FZoomInButton.Hint := L('header.bigger');
  if FSilence then
    FSilenceButton.Caption := L('header.silence.exit')
  else
    FSilenceButton.Caption := L('header.silence');
  FSilenceButton.Hint := L('header.silence.hint');
  FSearchButton.Hint := L('header.search');
  FMoreButton.Hint := L('header.more');
  FBanner.CloseHint := L('banner.close');
  if FBanner.Visible and (FBannerKey <> '') then
    FBanner.lblMessage.Caption := L(FBannerKey);
  HeaderResize(nil);                     // the pill's width follows its caption

  miLanguageUkrainian.Caption := LanguageName(UILanguageCodes[0]);
  miLanguageRussian.Caption := LanguageName(UILanguageCodes[1]);
  miLanguageEnglish.Caption := LanguageName(UILanguageCodes[2]);
  miLanguageUkrainian.Checked := Localizer.Language = UILanguageCodes[0];
  miLanguageRussian.Checked := Localizer.Language = UILanguageCodes[1];
  miLanguageEnglish.Checked := Localizer.Language = UILanguageCodes[2];

  FLibraryTitle.Caption := L('library.title').ToUpper;
  FLibraryTree.Invalidate;

  FSearchTitle.Caption := L('search.title').ToUpper;
  FSearchHint := L('search.placeholder');
  FSearchEdit.Invalidate;
  FScopeTitle.Caption := L('search.where').ToUpper;
  FScope.AllCaption := L('search.scope.all');
  FExactPhrase.Caption := L('search.exactPhrase');
  FWordForms.Caption := L('search.wordForms');
  FWordForms.Hint := L('search.wordForms.hint');
  ShowSearchStatus(FSearchStatusKey, FSearchStatusArg);
  if FHasReply then
    ShowSearchReply(FLastReply)          // "Розділ N" in the reference lines
  else
    FResultList.Invalidate;
  FPrevLink.Hint := L('read.prevChapter') + ' (←)';
  FNextLink.Hint := L('read.nextChapter') + ' (→)';
  FHitPrev.Hint := L('read.prevHit') + ' (Shift+F3)';
  FHitNext.Hint := L('read.nextHit') + ' (F3)';
  UpdateHitNav;
  UpdateStatus;
end;

procedure TMainForm.UpdateStatus;
begin
  FScope.CheckedCaption := L('search.scope.checked', [FCheckedCount]);
  FZoomLabel.Caption := Format('%d%%', [Round(ZoomPx(FZoomStep) / BaseTextPx * 100)]);
  FZoomOutButton.Enabled := FZoomStep > MinZoomStep;
  FZoomInButton.Enabled := FZoomStep < MaxZoomStep;
end;

{ the text column (A.2) }

procedure TMainForm.pnlCenterResize(Sender: TObject);
var
  Side, LeftPad: Integer;
begin
  // A.5 with the mockup's CSS (Presentation.Theme): side padding of the centre,
  // then a column of at most 724 px of text plus its left margin, centred.
  // "vw" is the window width.
  Side := EnsureRange(ClientWidth * TextColumnSidePercent div 100,
    ScaleValue(TextColumnSideMin), ScaleValue(TextColumnSideMax));
  LeftPad := EnsureRange(ClientWidth * TextColumnLeftPercent div 100,
    ScaleValue(TextColumnLeftMin), ScaleValue(TextColumnLeftMax));
  // The left margin belongs to every child but the list, which draws chapter
  // numbers inside it (mockup: number at left -64px).
  FLeftPad := LeftPad;
  pnlCrumbs.Margins.Left := LeftPad;
  pnlChapterNav.Margins.SetBounds(LeftPad, 0, 0, 0);
  if FChapterList <> nil then
    FChapterList.SetLeftPad(LeftPad);
  // border-box as the mockup's CSS: the left margin is inside the 724 px.
  pnlColumn.Width := Max(Min(ScaleValue(TextColumnMax), pnlCenter.ClientWidth - 2 * Side), 0);
  pnlColumn.Left := (pnlCenter.ClientWidth - pnlColumn.Width) div 2;
  pnlColumn.Top := 0;
  pnlColumn.Height := pnlCenter.ClientHeight;
  if FReaderHost <> nil then
    ReaderHostResize(nil);
  // Mockup: the scrollbar of <main> - at the right edge of the centre.
  if FCenterBar <> nil then
    FCenterBar.SetBounds(pnlCenter.ClientWidth - FCenterBar.Width, 0, FCenterBar.Width,
      pnlCenter.ClientHeight);
end;

procedure TMainForm.ShowView(View: TReaderView);
begin
  // A.5: the shelf and the table of contents leave «Тиша»; ‹ › keep it.
  if View <> rvRead then
    SetSilence(False);
  FReaderHost.Visible := View = rvRead;
  pnlChapterNav.Visible := View = rvRead;
  FChapterList.Host.Visible := View <> rvRead;
  case View of
    rvShelf: FillShelf;
    rvToc:   FillToc;
  end;
  UpdateCrumbs;
  if View = rvRead then
    FCenterBar.Attach(redReader, NativeScrollMetrics(redReader), NativeScrollTo(redReader))
  else
    FCenterBar.Attach(FChapterList.Tree, TreeMetrics(FChapterList.Tree),
      TreeScrollTo(FChapterList.Tree));
  // During Start the form is not shown yet: CanFocus ignores the form's own
  // visibility, Showing does not.
  if (View = rvRead) and redReader.Showing then
    redReader.SetFocus
  else if View <> rvRead then
    FChapterList.FocusList;
end;

// A.2: КАТЕГОРІЯ / КНИГА / РОЗДІЛ 3 · НАЗВА - every part but the last opens its level.
procedure TMainForm.UpdateCrumbs;
var
  M: TModule;
  P: TReadingPosition;
  Category: TBookCategory;
  Translation: TModuleId;
  Book: TBookRef;
  ModuleId: TModuleId;
begin
  pnlCrumbs.DisableAlign;
  try
    while pnlCrumbs.ControlCount > 0 do
      pnlCrumbs.Controls[0].Free;
    FCrumbActions := nil;

    case FViewModel.View of
      rvShelf:
        if FViewModel.ShelfTranslation <> '' then
          AddCrumb(L(BibleCategoryKey) + ' · ' + FViewModel.ModuleTitle(FViewModel.ShelfTranslation), nil)
        else
          AddCrumb(L(CategoryKeys[FViewModel.ShelfCategory]), nil);
      rvToc:
        if FViewModel.TocBook.BookCode <> '' then
        begin
          Translation := FViewModel.TocBook.ModuleId;
          AddCrumb(L(BibleCategoryKey) + ' · ' + FViewModel.ModuleTitle(Translation),
            procedure begin FViewModel.ShowShelf(Translation); end);
          AddCrumb(FViewModel.BookTitle(FViewModel.TocBook), nil);
        end
        else if FViewModel.Catalog.FindModule(FViewModel.TocModule, M) then
        begin
          Category := M.Category;
          AddCrumb(L(CategoryKeys[Category]), procedure begin FViewModel.ShowShelf(Category); end);
          AddCrumb(M.Title, nil);
        end;
      rvRead:
        begin
          P := FViewModel.Position;
          if P.Kind = ckBibleTranslation then
          begin
            Book := P.BibleChapter.Book;
            Translation := Book.ModuleId;
            AddCrumb(L(BibleCategoryKey) + ' · ' + FViewModel.ModuleTitle(Translation),
              procedure begin FViewModel.ShowShelf(Translation); end);
            AddCrumb(FViewModel.BookTitle(Book), procedure begin FViewModel.ShowToc(Book); end);
            AddCrumb(FViewModel.BookTitle(Book) + ' ' + IntToStr(P.BibleChapter.ChapterNumber), nil);
          end
          else if FViewModel.Catalog.FindModule(P.Chapter.ModuleId, M) then
          begin
            Category := M.Category;
            ModuleId := M.Id;
            AddCrumb(L(CategoryKeys[Category]), procedure begin FViewModel.ShowShelf(Category); end);
            AddCrumb(M.Title, procedure begin FViewModel.ShowToc(ModuleId); end);
            AddCrumb(L('read.chapter', [P.Chapter.ChapterOrder]) + ' · ' +
              FViewModel.ChapterTitle(P.Chapter), nil);
          end;
        end;
    end;
  finally
    pnlCrumbs.EnableAlign;
  end;
end;

// Action = nil: the current level, not a link. Mockup: 11 px, uppercase,
// links #767676 -> accent on hover, the current part #2f2f2f, "/" #c8c8c8.
procedure TMainForm.AddCrumb(const Caption: string; const Action: TProc);

  function NewLabel(const Text: string; Color: TColor): TLabel;
  var
    Crumb: TTrackedLabel;
  begin
    Crumb := TTrackedLabel.Create(Self);
    Crumb.Tracking := 0.08;              // mockup: 11 px caps, letter-spacing .08em
    Result := Crumb;
    Result.Left := 100000 + pnlCrumbs.ControlCount;     // alLeft keeps creation order
    Result.Parent := pnlCrumbs;
    Result.Align := alLeft;
    Result.AlignWithMargins := True;
    Result.Margins.SetBounds(0, 0, ScaleValue(10), 0);
    Result.ShowAccelChar := False;
    Result.Caption := Text;
    Result.Font.Name := FTheme.UiFont;
    Result.Font.Height := -ScaleValue(11);
    Result.Font.Color := Color;
  end;

var
  Lbl: TLabel;
begin
  if Length(FCrumbActions) > 0 then
    NewLabel('/', TColor($00C8C8C8));
  if Assigned(Action) then
    Lbl := NewLabel(Caption.ToUpper, ColorMuted)
  else
    Lbl := NewLabel(Caption.ToUpper, ColorText);
  Lbl.Tag := Length(FCrumbActions);
  FCrumbActions := FCrumbActions + [Action];
  if Assigned(Action) then
  begin
    Lbl.Cursor := crHandPoint;
    Lbl.OnClick := CrumbClick;
    Lbl.OnMouseEnter := CrumbMouseEnter;
    Lbl.OnMouseLeave := CrumbMouseLeave;
  end;
end;

procedure TMainForm.CrumbClick(Sender: TObject);
var
  Action: TProc;
  Queued: TThreadProcedure;
begin
  // The action rebuilds the crumbs, which frees Sender - never inside its own
  // OnClick: run it after the click has finished.
  Action := FCrumbActions[(Sender as TLabel).Tag];
  Queued := procedure begin Action(); end;
  TThread.ForceQueue(nil, Queued);
end;

procedure TMainForm.CrumbMouseEnter(Sender: TObject);
begin
  (Sender as TLabel).Font.Color := ColorAccent;
end;

procedure TMainForm.CrumbMouseLeave(Sender: TObject);
begin
  (Sender as TLabel).Font.Color := ColorMuted;
end;

{ shelf and table of contents (A.2, C.5) - rows from the library nodes }

function TMainForm.FindNode(Kind: TLibraryNodeKind; const ModuleId: TModuleId;
  const BookCode: TBookCode): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNodes) do
    if (FNodes[I].Kind = Kind) and (FNodes[I].ModuleId = ModuleId) and (FNodes[I].BookCode = BookCode) then
      Exit(I);
  Result := -1;
end;

function TMainForm.IsUnder(Index, Ancestor: Integer): Boolean;
begin
  Index := FNodes[Index].Parent;
  while Index >= 0 do
  begin
    if Index = Ancestor then
      Exit(True);
    Index := FNodes[Index].Parent;
  end;
  Result := False;
end;

procedure TMainForm.FillShelf;
var
  Rows: TArray<TListRow>;
  Row: TListRow;
  P: TReadingPosition;
  HasPosition: Boolean;
  Root, I: Integer;
  Title, Subtitle: string;
begin
  Rows := nil;
  if FViewModel.ShelfTranslation <> '' then
  begin
    // A translation's shelf: its books; "читаю" on the book of the saved position.
    Root := FindNode(lnBibleTranslation, FViewModel.ShelfTranslation);
    HasPosition := FSettings.GetPosition(FViewModel.ShelfTranslation, P) and
      (P.Kind = ckBibleTranslation);
    for I := 0 to High(FNodes) do
      if (Root >= 0) and (FNodes[I].Parent = Root) and (FNodes[I].Kind = lnBibleBook) then
      begin
        Row := Default(TListRow);
        Row.NodeIndex := I;
        Row.Title := FNodes[I].Caption;
        Row.Meta := L('library.bibleChapters', [FNodes[I].Count]);
        if HasPosition and (P.BibleChapter.Book.BookCode = FNodes[I].BookCode) then
          Row.Status := L('shelf.reading', [P.BibleChapter.ChapterNumber]);
        Rows := Rows + [Row];
      end;
    Title := L(BibleCategoryKey) + ' · ' + FViewModel.ModuleTitle(FViewModel.ShelfTranslation);
    Subtitle := L('library.bibleBooks', [Length(Rows)]);
  end
  else
  begin
    // A category: every book under it in tree order (B-25), series included.
    Root := -1;
    for I := 0 to High(FNodes) do
      if (FNodes[I].Kind = lnCategory) and (FNodes[I].CaptionKey = CategoryKeys[FViewModel.ShelfCategory]) then
        Root := I;
    for I := 0 to High(FNodes) do
      if (Root >= 0) and (FNodes[I].Kind = lnModule) and IsUnder(I, Root) then
      begin
        Row := Default(TListRow);
        Row.NodeIndex := I;
        Row.Title := FNodes[I].Caption;
        Row.Meta := L('library.chapters', [FNodes[I].Count]);
        if FSettings.GetPosition(FNodes[I].ModuleId, P) and (P.Kind = ckBook) then
          Row.Status := L('shelf.reading', [P.Chapter.ChapterOrder]);
        Rows := Rows + [Row];
      end;
    Title := L(CategoryKeys[FViewModel.ShelfCategory]);
    Subtitle := L('shelf.booksCount', [Length(Rows)]);
  end;
  FChapterList.Show(Title, Subtitle, Rows);
end;

procedure TMainForm.FillToc;
var
  Rows: TArray<TListRow>;
  Row: TListRow;
  P: TReadingPosition;
  HasPosition: Boolean;
  Root, I: Integer;
  Book: TBookRef;
  Title: string;
begin
  Rows := nil;
  Book := FViewModel.TocBook;
  if Book.BookCode <> '' then
  begin
    Root := FindNode(lnBibleBook, Book.ModuleId, Book.BookCode);
    HasPosition := FSettings.GetPosition(Book.ModuleId, P) and (P.Kind = ckBibleTranslation) and
      (P.BibleChapter.Book.BookCode = Book.BookCode);
    Title := FViewModel.BookTitle(Book);
  end
  else
  begin
    Root := FindNode(lnModule, FViewModel.TocModule);
    HasPosition := FSettings.GetPosition(FViewModel.TocModule, P) and (P.Kind = ckBook);
    Title := FViewModel.ModuleTitle(FViewModel.TocModule);
  end;

  for I := 0 to High(FNodes) do
    if (Root >= 0) and (FNodes[I].Parent = Root) and (FNodes[I].Kind = lnChapter) then
    begin
      Row := Default(TListRow);
      Row.NodeIndex := I;
      Row.Number := FNodes[I].ChapterOrder;
      if Book.BookCode <> '' then
      begin
        Row.Title := Title + ' ' + IntToStr(FNodes[I].ChapterOrder);
        if HasPosition and (P.BibleChapter.ChapterNumber = FNodes[I].ChapterOrder) then
          Row.Status := L('toc.reading').ToUpper;
      end
      else
      begin
        Row.Title := FNodes[I].Caption;
        if HasPosition and (P.Chapter.ChapterOrder = FNodes[I].ChapterOrder) then
          Row.Status := L('toc.reading').ToUpper;
      end;
      Rows := Rows + [Row];
    end;
  FChapterList.Show(Title, L('toc.title'), Rows);
end;

// Backspace: what the breadcrumbs will do (A.2) - Read -> Toc -> Shelf.
procedure TMainForm.GoUp;
var
  P: TReadingPosition;
begin
  case FViewModel.View of
    rvRead:
      begin
        P := FViewModel.Position;
        if P.Kind = ckBibleTranslation then
          FViewModel.ShowToc(P.BibleChapter.Book)
        else
          FViewModel.ShowToc(P.Chapter.ModuleId);
      end;
    rvToc:
      if FViewModel.TocBook.BookCode <> '' then
        FViewModel.ShowShelf(FViewModel.TocBook.ModuleId)
      else
        FViewModel.ShowShelf(FViewModel.ShelfCategory);
    rvShelf:
      if FViewModel.ShelfTranslation <> '' then
        FViewModel.ShowShelf(FViewModel.ShelfCategory);
  end;
end;

{ reading (C.4) }

procedure TMainForm.RenderChapter(const Args: TChapterLoadedArgs; FocusMatch: Integer);
var
  Doc: TChapterRtf;
  Build: TFunc<Integer, TChapterRtf>;
begin
  FShown := scBook;
  FLastChapter := Args;
  Build := function(Focus: Integer): TChapterRtf
    var
      Request: THighlightRequest;
    begin
      Request.Hits := FLastChapter.Hits;
      Request.Focus := Focus;
      Result := TChapterRtfBuilder.Build(FLastChapter.Content,
        L('read.chapter', [FLastChapter.Content.Ref.ChapterOrder]), FTheme, Request);
    end;
  Doc := Build(FocusMatch);
  ShowDocument(Doc, Args.Focus, FocusMatch, Build);
end;

procedure TMainForm.RenderBibleChapter(const Args: TBibleChapterLoadedArgs; FocusMatch: Integer);
var
  Doc: TChapterRtf;
  Build: TFunc<Integer, TChapterRtf>;
begin
  FShown := scBible;
  FLastBibleChapter := Args;
  Build := function(Focus: Integer): TChapterRtf
    var
      Request: TVerseHighlightRequest;
    begin
      Request.Hits := FLastBibleChapter.Hits;
      Request.Focus := Focus;
      Result := TChapterRtfBuilder.Build(FLastBibleChapter.Content, FLastBibleChapter.BookTitle,
        L('read.chapter', [FLastBibleChapter.Content.Ref.ChapterNumber]), FTheme, Request);
    end;
  Doc := Build(FocusMatch);
  ShowDocument(Doc, Args.Focus, FocusMatch, Build);
end;

// The ViewModel names the current PARAGRAPH (the clicked result); the
// navigator works by words, so the paragraph becomes its first word - known
// only after a build, hence a second one with that word as the focus.
procedure TMainForm.ShowDocument(var Doc: TChapterRtf; ParagraphFocus, FocusMatch: Integer;
  const Rebuild: TFunc<Integer, TChapterRtf>);
begin
  if (FocusMatch < 0) and (ParagraphFocus >= 0) and (ParagraphFocus <= High(Doc.HitFirstMatch))
    and (Doc.HitFirstMatch[ParagraphFocus] >= 0) then
  begin
    FocusMatch := Doc.HitFirstMatch[ParagraphFocus];
    Doc := Rebuild(FocusMatch);
  end;
  FFocusMatch := FocusMatch;
  FMatchCount := Length(Doc.MatchStarts);
  LoadDocument(Doc, FocusMatch);
  UpdateHitNav;
end;

{ the library tree (A.3) }

procedure TMainForm.LibraryNodeActivated(const Node: TLibraryNode);
var
  Category: TBookCategory;
  Book: TBookRef;
  Chapter: TChapterRef;
  BibleChapter: TBibleChapterRef;
begin
  Book.ModuleId := Node.ModuleId;
  Book.BookCode := Node.BookCode;
  case Node.Kind of
    lnCategory:
      for Category := Low(TBookCategory) to High(TBookCategory) do
        if CategoryKeys[Category] = Node.CaptionKey then
          FViewModel.ShowShelf(Category);
    lnModule:           FViewModel.ShowToc(Node.ModuleId);
    lnBibleTranslation: FViewModel.ShowShelf(Node.ModuleId);
    lnBibleBook:        FViewModel.ShowToc(Book);
    lnChapter:
      if Node.BookCode <> '' then
      begin
        BibleChapter.Book := Book;
        BibleChapter.ChapterNumber := Node.ChapterOrder;
        FViewModel.OpenChapter(BibleChapter);
      end
      else
      begin
        Chapter.ModuleId := Node.ModuleId;
        Chapter.ChapterOrder := Node.ChapterOrder;
        FViewModel.OpenChapter(Chapter);
      end;
  end;                                   // lnSeries: the tree only expands it
end;

procedure TMainForm.LibraryNodeChecked(const Node: TLibraryNode; Checked: Boolean);
begin
  FViewModel.SetChecked(Node.ModuleId, Checked);
  if Checked then
    Inc(FCheckedCount)
  else
    Dec(FCheckedCount);
  UpdateStatus;
end;

procedure TMainForm.LoadDocument(const Doc: TChapterRtf; Focus: Integer);
var
  StreamError, Actual: Integer;
begin
  FDoc := Doc;
  redReader.Lines.BeginUpdate;
  try
    StreamInRtf(redReader, Doc.Rtf, StreamError);
    SetZoomPx(redReader, ZoomPx(FZoomStep));
  finally
    redReader.Lines.EndUpdate;
  end;

  // C.4: the user sees what got in; only the log knows about a shortfall.
  Actual := PreciseLength(redReader);
  if (StreamError <> 0) or (Actual <> Doc.ExpectedChars) then
    FViewModel.ReportRenderProblem(Format(
      'Chapter %s rendered incompletely: expected %d chars, got %d, stream error %d',
      [Doc.Where, Doc.ExpectedChars, Actual, StreamError]));

  if (Focus >= 0) and (Focus <= High(Doc.MatchStarts)) then
    ScrollToChar(redReader, Doc.MatchStarts[Focus])
  else
    ScrollToChar(redReader, 0);
  UpdateCrumbs;
  FLibraryTree.SetActive(FViewModel.Position);
end;

{ zoom (E-11) }

procedure TMainForm.SetZoomStep(Value: Integer);
begin
  Value := EnsureRange(Value, MinZoomStep, MaxZoomStep);
  if Value = FZoomStep then
    Exit;
  FZoomStep := Value;
  SetZoomPx(redReader, ZoomPx(FZoomStep));
  FSettings.SetZoomStep(FZoomStep);
  UpdateStatus;
end;

procedure TMainForm.ReaderWndProc(var Message: TMessage);
begin
  if (Message.Msg = WM_MOUSEWHEEL) and (LoWord(Message.WParam) and MK_CONTROL <> 0) then
  begin
    if SmallInt(HiWord(Message.WParam)) > 0 then
      SetZoomStep(FZoomStep + 1)
    else
      SetZoomStep(FZoomStep - 1);
    Message.Result := 0;
    Exit;
  end;
  FReaderWndProc(Message);
  // A book, not an editor: no blinking caret. RichEdit shows the caret again
  // after focus, clicks, keys and selection changes, so it is hidden after each
  // of them. Extra HideCaret calls are harmless: the caret is destroyed on
  // WM_KILLFOCUS and its hide count starts over with the next one.
  case Message.Msg of
    // WM_PAINT: when the window first appears, msftedit shows the caret after
    // painting, not in WM_SETFOCUS (seen on Windows 11).
    // WM_MOUSEMOVE: while the button is held, every move re-shows it.
    WM_SETFOCUS, WM_PAINT, WM_MOUSEMOVE, WM_LBUTTONDOWN, WM_LBUTTONUP, WM_LBUTTONDBLCLK,
    WM_KEYDOWN, WM_KEYUP,
    EM_EXSETSEL, EM_SCROLLCARET:
      HideReaderCaret;
  end;
end;

procedure TMainForm.HideReaderCaret;
begin
  if redReader.HandleAllocated and (GetFocus = redReader.Handle) then
    HideCaret(redReader.Handle);
end;

procedure TMainForm.actZoomInExecute(Sender: TObject);
begin
  SetZoomStep(FZoomStep + 1);
end;

procedure TMainForm.actZoomOutExecute(Sender: TObject);
begin
  SetZoomStep(FZoomStep - 1);
end;

procedure TMainForm.actZoomResetExecute(Sender: TObject);
begin
  SetZoomStep(0);
end;

procedure TMainForm.actPrevChapterExecute(Sender: TObject);
begin
  FViewModel.PreviousChapter;
end;

procedure TMainForm.actNextChapterExecute(Sender: TObject);
begin
  FViewModel.NextChapter;
end;

procedure TMainForm.alMainUpdate(Action: TBasicAction; var Handled: Boolean);
begin
  if FViewModel = nil then
    Exit;
  actZoomIn.Enabled := FZoomStep < MaxZoomStep;
  actZoomOut.Enabled := FZoomStep > MinZoomStep;
  actZoomReset.Enabled := FZoomStep <> 0;
  actPrevChapter.Enabled := (FViewModel.View = rvRead) and FViewModel.CanGoPrevious;
  actNextChapter.Enabled := (FViewModel.View = rvRead) and FViewModel.CanGoNext;
  Handled := True;
end;

{ search (A.4, C.1) }


procedure TMainForm.OpenSearch;
begin
  if not FRightPanel.Visible or FSilence then
    SetRightWanted(True);
  if FSearchEdit.CanFocus then
  begin
    FSearchEdit.SetFocus;
    FSearchEdit.SelectAll;
  end;
end;

procedure TMainForm.SearchButtonClick(Sender: TObject);
begin
  if FRightPanel.Visible then
    SetRightWanted(False)                // ApplyLayout moves the focus out
  else
    OpenSearch;
end;

procedure TMainForm.ShowSearchStatus(const Key: string; Arg: Integer);
begin
  FSearchStatusKey := Key;
  FSearchStatusArg := Arg;
  if Key = '' then
    FSearchStatus.Caption := ''
  else if Arg >= 0 then
    FSearchStatus.Caption := L(Key, [Arg]).ToUpper
  else
    FSearchStatus.Caption := L(Key).ToUpper;
end;

// C.1: the form checks the empty query and the empty scope itself (R4-24) -
// a status line, never the banner; the search itself is synchronous (C-21).
procedure TMainForm.RunSearch;
begin
  if Trim(StringReplace(FSearchEdit.Text, #$00A0, ' ', [rfReplaceAll])) = '' then
  begin
    ShowSearchStatus('search.enterWord');
    Exit;
  end;
  if not FScope.WholeLibrary and (FCheckedCount = 0) then
  begin
    ShowSearchStatus('search.checkSome');
    Exit;
  end;
  ShowSearchStatus('search.busy');
  FSearchStatus.Update;                  // a synchronous WM_PAINT, not ProcessMessages
  FSearchDone := False;
  Screen.Cursor := crHourGlass;
  try
    FViewModel.Search(FSearchEdit.Text, FScope.WholeLibrary, FExactPhrase.Checked, FWordForms.Checked);
  finally
    Screen.Cursor := crDefault;
  end;
  if not FSearchDone then
    ShowSearchStatus('');                // an error: the banner (status bar for now) says it
end;

procedure TMainForm.ShowSearchReply(const Reply: TSearchReply);
begin
  FSearchDone := True;
  FLastReply := Reply;
  FHasReply := True;
  FResultList.Show(BuildResultSections(Reply, FViewModel.Catalog,
    function(ChapterOrder: Integer): string
    begin
      Result := L('read.chapter', [ChapterOrder]);
    end));
  // E-12: "Збіги: 172", or "Показано перші 200" when any page was cut.
  if ResultTruncated(Reply) then
    ShowSearchStatus('search.truncated', DefaultMaxResults)
  else
    ShowSearchStatus('search.hits', ResultCount(Reply));
end;

procedure TMainForm.SearchResultOpened(Section: TResultSectionKind; Index: Integer);
var
  Queued: TThreadProcedure;
begin
  // Opening a chapter moves the focus; do it after the click has finished.
  Queued := procedure
    begin
      if Section = rsBooks then
      begin
        if Index <= High(FLastReply.Books.Items) then
          FViewModel.OpenSearchResult(FLastReply.Books.Items[Index].Ref);
      end
      else if Index <= High(FLastReply.Bible.Items) then
        FViewModel.OpenSearchResult(FLastReply.Bible.Items[Index].Ref);
    end;
  TThread.ForceQueue(nil, Queued);
end;

// Mockup: the placeholder stays while the field is empty, focused or not.
procedure TMainForm.SearchEditWndProc(var Message: TMessage);
var
  DC: HDC;
  Canvas: TCanvas;
  Margins: LRESULT;
begin
  FSearchEditWndProc(Message);
  if (Message.Msg <> WM_PAINT) or (FSearchEdit.GetTextLen > 0) or (FSearchHint = '') then
    Exit;
  DC := GetDC(FSearchEdit.Handle);
  Canvas := TCanvas.Create;
  try
    Canvas.Handle := DC;
    Canvas.Font := FSearchEdit.Font;
    Canvas.Font.Color := ColorMarker;
    Canvas.Brush.Style := bsClear;
    Margins := SendMessage(FSearchEdit.Handle, EM_GETMARGINS, 0, 0);
    Canvas.TextOut(LoWord(Margins), 0, FSearchHint);
  finally
    Canvas.Handle := 0;
    Canvas.Free;
    ReleaseDC(FSearchEdit.Handle, DC);
  end;
end;

procedure TMainForm.SearchEditChange(Sender: TObject);
begin
  FSearchEdit.Invalidate;                // the placeholder comes and goes with the text
end;

procedure TMainForm.SearchEditKeyPress(Sender: TObject; var Key: Char);
begin
  case Key of
    #13:
      begin
        Key := #0;                       // no beep
        RunSearch;
      end;
    #27:
      begin
        Key := #0;
        FocusReaderOrList;               // A.6: Esc takes the focus off the field
      end;
  end;
end;

function TMainForm.FocusReaderOrList: Boolean;
begin
  Result := True;
  if redReader.Visible and redReader.CanFocus then
    redReader.SetFocus
  else if FChapterList.Host.Visible then
    FChapterList.FocusList
  else
    Result := False;
end;

// F3 / Shift+F3 (A.6): the next / previous highlighted word; the RTF is
// rebuilt with the new Focus (E-01) and scrolled to it.
procedure TMainForm.MoveHit(Delta: Integer);

  function Step(Focus, Count: Integer): Integer;
  begin
    if Focus < 0 then
    begin
      if Delta > 0 then
        Result := 0
      else
        Result := Count - 1;
    end
    else
      Result := (Focus + Delta + Count) mod Count;
  end;

begin
  if (FViewModel.View <> rvRead) or (FMatchCount = 0) then
    Exit;
  case FShown of
    scBook:  RenderChapter(FLastChapter, Step(FFocusMatch, FMatchCount));
    scBible: RenderBibleChapter(FLastBibleChapter, Step(FFocusMatch, FMatchCount));
  end;
end;

{ the match navigator (E-08) }

procedure TMainForm.CreateHitNav;

  function NewButton(const Caption: string; const OnClick: TNotifyEvent): TFlatButton;
  begin
    Result := TFlatButton.Create(Self, FScale);
    Result.Parent := FHitBox;
    Result.Align := alLeft;
    Result.Caption := Caption;
    Result.FontPx := 17;
    Result.Width := ScaleValue(28);
    Result.TabStop := False;
    Result.ShowHint := True;
    Result.OnClick := OnClick;
  end;

begin
  // Between the alLeft / alRight chapter links: the client area of the bar.
  FHitNav := TPanel.Create(Self);
  FHitNav.Parent := pnlChapterNav;
  FHitNav.Align := alClient;
  FHitNav.BevelOuter := bvNone;
  FHitNav.ParentBackground := False;
  FHitNav.Color := ColorBackground;
  FHitNav.OnResize := HitNavResize;

  // A box sized to its content, centred by HitNavResize.
  FHitBox := TPanel.Create(Self);
  FHitBox.Parent := FHitNav;
  FHitBox.BevelOuter := bvNone;
  FHitBox.ParentBackground := False;
  FHitBox.Color := ColorBackground;
  FHitBox.Height := ScaleValue(28);

  FHitPrev := NewButton('‹', HitPrevClick);
  FHitLabel := TLabel.Create(Self);
  FHitLabel.Parent := FHitBox;
  FHitLabel.Left := 1000;                // alLeft keeps the order of Left
  FHitLabel.Align := alLeft;
  FHitLabel.AlignWithMargins := True;
  FHitLabel.Margins.SetBounds(ScaleValue(10), 0, ScaleValue(10), 0);
  FHitLabel.Layout := tlCenter;
  FHitLabel.ShowAccelChar := False;
  FHitLabel.Font.Color := ColorMuted;
  FHitNext := NewButton('›', HitNextClick);
  FHitNext.Left := 2000;
  FHitNav.Visible := False;
end;

procedure TMainForm.HitNavResize(Sender: TObject);
var
  W: Integer;
begin
  W := FHitPrev.Width + FHitLabel.Width + FHitLabel.Margins.Left + FHitLabel.Margins.Right + FHitNext.Width;
  FHitBox.SetBounds(Max((FHitNav.ClientWidth - W) div 2, 0),
    (FHitNav.ClientHeight - FHitBox.Height) div 2, W, FHitBox.Height);
end;

// "«дети» · 2 з 3 у розділі"; before a current match is chosen (the chapter
// came from the tree with an active search) - "«дети» · у розділі: 3".
procedure TMainForm.UpdateHitNav;
var
  Count, Focus: Integer;
begin
  UpdateChapterLinks;
  Count := 0;
  Focus := -1;
  if (FViewModel <> nil) and (FShown <> scNone) then
  begin
    Count := FMatchCount;
    Focus := FFocusMatch;
  end;
  FHitNav.Visible := Count > 0;
  if Count = 0 then
  begin
    ChapterBarResize(nil);
    Exit;
  end;
  if Focus >= 0 then
    FHitLabel.Caption := L('read.hitNav', [FHitQuery, Focus + 1, Count])
  else
    FHitLabel.Caption := L('read.hitCount', [FHitQuery, Count]);
  HitNavResize(nil);
  ChapterBarResize(nil);                 // the links share the bar with the navigator
end;

{ the chapter bar (A.2) }

procedure TMainForm.CreateChapterLinks;

  function NewLink(Alignment: TAlignment; Align: TAlign; const Click: TNotifyEvent): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := pnlChapterNav;
    Result.AutoSize := False;
    Result.Align := Align;
    Result.Alignment := Alignment;
    Result.Layout := tlCenter;
    Result.ShowAccelChar := False;
    Result.EllipsisPosition := epEndEllipsis;
    Result.Transparent := True;
    Result.Cursor := crHandPoint;
    Result.ShowHint := True;
    Result.Font.Height := -ScaleValue(17);
    Result.Font.Color := ColorButtonText;
    Result.OnClick := Click;
    Result.OnMouseEnter := LinkMouseEnter;
    Result.OnMouseLeave := LinkMouseLeave;
  end;

var
  Line: TPanel;
begin
  pnlChapterNav.Height := ScaleValue(64);
  pnlChapterNav.OnResize := ChapterBarResize;
  Line := TPanel.Create(Self);
  Line.Parent := pnlChapterNav;
  Line.Align := alTop;
  Line.Height := 1;
  Line.BevelOuter := bvNone;
  Line.ParentBackground := False;
  Line.Color := TColor($00E6E6E6);       // rgba(0,0,0,.09)
  FPrevLink := NewLink(taLeftJustify, alLeft, PrevLinkClick);
  FNextLink := NewLink(taRightJustify, alRight, NextLinkClick);
end;

// Mockup: chLabel - "Розділ N · Назва" for a book, the title for a Bible chapter.
function TMainForm.NeighbourCaption(Delta: Integer; out Caption: string): Boolean;
var
  P: TReadingPosition;
  T: TChapterRef;
  TB: TBibleChapterRef;
begin
  Result := False;
  Caption := '';
  if (FViewModel = nil) or (FViewModel.View <> rvRead) or (FShown = scNone) then
    Exit;
  P := FViewModel.Position;
  if P.Kind = ckBibleTranslation then
  begin
    Result := FViewModel.Catalog.Neighbour(P.BibleChapter, Delta, TB);
    if Result then
      Caption := FViewModel.BookTitle(TB.Book) + ' ' + IntToStr(TB.ChapterNumber);
  end
  else
  begin
    Result := FViewModel.Catalog.Neighbour(P.Chapter, Delta, T);
    if Result then
      Caption := L('read.chapter', [T.ChapterOrder]) + ' · ' + FViewModel.ChapterTitle(T);
  end;
end;

procedure TMainForm.UpdateChapterLinks;
var
  S: string;
begin
  FPrevLink.Visible := NeighbourCaption(-1, S);
  FPrevLink.Caption := '← ' + S;
  FNextLink.Visible := NeighbourCaption(+1, S);
  FNextLink.Caption := S + ' →';
  ChapterBarResize(nil);
end;

// Each link takes its text's width, at most what the match navigator leaves.
procedure TMainForm.ChapterBarResize(Sender: TObject);
var
  Room, Middle: Integer;

  function TextWidth(Link: TLabel): Integer;
  begin
    Canvas.Font := Link.Font;
    Result := Canvas.TextWidth(Link.Caption) + ScaleValue(4);
  end;

begin
  if FPrevLink = nil then
    Exit;
  Middle := 0;
  if (FHitNav <> nil) and FHitNav.Visible then
    Middle := FHitBox.Width + ScaleValue(24);
  Room := Max((pnlChapterNav.ClientWidth - Middle) div 2, 0);
  FPrevLink.Width := Min(TextWidth(FPrevLink), Room);
  FNextLink.Width := Min(TextWidth(FNextLink), Room);
end;

procedure TMainForm.LinkMouseEnter(Sender: TObject);
begin
  (Sender as TLabel).Font.Color := ColorAccent;
end;

procedure TMainForm.LinkMouseLeave(Sender: TObject);
begin
  (Sender as TLabel).Font.Color := ColorButtonText;
end;

procedure TMainForm.PrevLinkClick(Sender: TObject);
begin
  FViewModel.PreviousChapter;
end;

procedure TMainForm.NextLinkClick(Sender: TObject);
begin
  FViewModel.NextChapter;
end;

procedure TMainForm.HitPrevClick(Sender: TObject);
begin
  MoveHit(-1);
end;

procedure TMainForm.HitNextClick(Sender: TObject);
begin
  MoveHit(1);
end;

{ errors }

procedure TMainForm.ShowError(Error: TResultError);
begin
  FBannerKey := ErrorKey(Error);
  FBanner.Top := FHeader.BoundsRect.Bottom;      // alTop keeps the order of Top: under the header
  FBanner.ShowText(L(FBannerKey));
end;

procedure TMainForm.HandleException(Sender: TObject; E: Exception);
begin
  if FViewModel <> nil then
    FViewModel.ReportUnexpected(E.ClassName + ': ' + E.Message);
end;

{ keyboard (A.6) }

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FViewModel = nil then
    Exit;
  if (Key = vkEscape) and FSilence then  // A.6: Esc leaves «Тиша» first
  begin
    SetSilence(False);
    Key := 0;
    Exit;
  end;
  if Key = vkF3 then
  begin
    if Shift = [ssShift] then
      MoveHit(-1)
    else if Shift = [] then
      MoveHit(1);
    Key := 0;
    Exit;
  end;
  // A.6: the trees keep their own arrows and Backspace (expand, collapse, parent);
  // the search field keeps all its keys.
  if (ActiveControl = FLibraryTree.Control) or (ActiveControl = FSearchEdit) then
    Exit;
  case Key of
    vkLeft, vkRight:
      if (FViewModel.View = rvRead) and (Shift = []) and (ActiveControl <> FResultList.Control) then
      begin
        if Key = vkLeft then
          FViewModel.PreviousChapter
        else
          FViewModel.NextChapter;
        Key := 0;
      end;
    vkBack:
      begin
        GoUp;
        Key := 0;
      end;
  end;
end;

// A.6: "/" opens the search and puts the focus into the field - by the
// character, so it works whatever the keyboard layout.
procedure TMainForm.FormKeyPress(Sender: TObject; var Key: Char);
begin
  if (Key = '/') and (ActiveControl <> FSearchEdit) and (FViewModel <> nil) then
  begin
    Key := #0;
    OpenSearch;
  end;
end;

{ menu }

procedure TMainForm.miExitClick(Sender: TObject);
begin
  Close;
end;

// Shared by the three language items; Tag = index in UILanguageCodes (R3-25).
procedure TMainForm.miLanguageItemClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := (Sender as TMenuItem).Tag;
  if (Index < Low(UILanguageCodes)) or (Index > High(UILanguageCodes)) then
    Exit;
  Localizer.SetLanguage(UILanguageCodes[Index]);
  FSettings.SetLanguage(UILanguageCodes[Index]);
  ApplyLocalization;
  // "Розділ N" is inside the document - rebuild it; lists carry localized counters.
  case FViewModel.View of
    rvShelf: FillShelf;
    rvToc:   FillToc;
    rvRead:
      case FShown of
        scBook:  RenderChapter(FLastChapter, FFocusMatch);
        scBible: RenderBibleChapter(FLastBibleChapter, FFocusMatch);
      end;
  end;
  UpdateCrumbs;
end;

// The report is technical and stays English.
procedure TMainForm.miSQLiteDiagnosticsClick(Sender: TObject);
begin
  TaskMessageDlg(L('dialog.sqliteDiagnostics.title'), SQLiteSelfTest, mtInformation, [mbOK], 0);
end;

end.
