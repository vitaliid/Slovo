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
    FOnSearchCompleted: TProc<TSearchSummary>;
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
    function FindSeries(const Series: string): Integer;
    function SeriesTitle(const Series: string): string;
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
    FSummary: TSearchSummary;            // the counts of the last search: the list is rebuilt from them
    FModel: TSearchResultsModel;         // what FResultList shows; owned here
    FViewSwitch: TScopeSwitch;           // E-20: "за книгами" | "за релевантністю"
    FResultBar: TPanel;                  // E-19: the pinned line and "collapse all"
    FPinned: TLabel;
    FCollapseAll: TLabel;
    // What the reader did to the list in each view, to find it again after a
    // switch and back; reset by a new search.
    FViewState: array[TSearchOrder] of TResultListState;
    FHasReply: Boolean;
    FSearchDone: Boolean;
    FSearchStatusKey: string;            // '' = empty line; kept to re-localize
    FSearchStatusArg: Integer;           // -1 = the key takes no argument
    FSearchHint: string;
    FSearchEditWndProc: TWndMethod;
    procedure SearchEditWndProc(var Message: TMessage);
    procedure SearchIconPaint(Sender: TObject);
    procedure SearchEditChange(Sender: TObject);
    procedure ClearSearchResults;
    procedure CreateRightPanel;
    procedure OpenSearch;
    procedure RunSearch;
    procedure ShowSearchStatus(const Key: string; Arg: Integer = -1);
    procedure ShowSearchSummary(const Summary: TSearchSummary);
    procedure RebuildResults;
    procedure UpdateResultBar;
    procedure ViewSwitchChanged(Sender: TObject);
    procedure CollapseAllClick(Sender: TObject);
    procedure SearchResultOpened(Section: TResultSectionKind; const Line: TResultLine);
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
    // E-22: the inner edges of the side panels are dragged with the mouse.
    FLeftGrip, FRightGrip: TPanel;
    FSplitPanel: TPanel;                 // the panel being resized; nil = no drag
    FSplitStartX, FSplitStartWidth: Integer;
    FSplitWidth: Integer;                // the width the drag has reached; applied on release
    FSplitGuide: TPanel;                 // the line that follows the mouse meanwhile
    // E-23: the width of the text column - a switch of three segments in the header.
    FTextWidthMode: Integer;             // 0 narrow, 1 medium, 2 wide
    FWidthSwitch: TWidthSwitch;
    FCenterBar: TThinScrollBar;
    FRightBar: TThinScrollBar;
    FLibraryHost: TPanel;
    FResultsHost: TPanel;
    FReaderHost: TPanel;
    FTitlePx: Integer;                   // the chapter title's size now, CSS px
    procedure UpdateTitleSize(Force: Boolean);
    procedure LibraryHostResize(Sender: TObject);
    procedure ResultsHostResize(Sender: TObject);
    procedure ReaderHostResize(Sender: TObject);
    procedure MakeSplitGrip(Grip: TPanel; LineAlign: TAlign);
    function ClampSidePanelWidth(Panel: TPanel; Value: Integer): Integer;
    procedure SetSidePanelWidth(Panel: TPanel; Value: Integer);
    procedure MoveSplitGuide;
    procedure SaveSidePanelWidths;
    procedure SplitMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure SplitMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure SplitMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure SplitDblClick(Sender: TObject);
    procedure WidthSwitchChanged(Sender: TObject);

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
    procedure SearchOptionClick(Sender: TObject);
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
    FDocQuery: TSearchQuery;             // the search the shown highlights came from (R8-05)
    FDocHasQuery: Boolean;
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
    procedure ShowDocument(const Doc: TChapterRtf; ParagraphFocus, FocusMatch: Integer);
    // R8-04: another match of the document that is already shown.
    procedure GoToMatch(Index: Integer);
    // R8-05: the chapter of the active search is the one the reader shows.
    function ShownQueryIsActive: Boolean;
    function ShowsChapter(const Ref: TChapterRef): Boolean; overload;
    function ShowsChapter(const Ref: TBibleChapterRef): Boolean; overload;
    procedure RememberShownQuery;
    procedure FocusShownHit(ParagraphFocus: Integer);
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
  HitRowHeight = 28;                     // the match navigator's row under the crumbs
  HitRowGap = 8;                         // crumbs 8 + row 28 + 8 = CrumbsBottom 44
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
  FExactPhrase.OnClick := SearchOptionClick;
  FWordForms.OnClick := SearchOptionClick;
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
  FModel.Free;                           // after the list that showed it
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
  FTextWidthMode := 1;
  FWidthSwitch := TWidthSwitch.Create(Self, FScale);
  FWidthSwitch.Parent := FHeader;
  FWidthSwitch.ShowHint := True;
  FWidthSwitch.OnChange := WidthSwitchChanged;
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
  W := FWidthSwitch.PillWidth;           // E-23: the width of the text, left of «Тиша»
  Dec(X, ScaleValue(14) + W);
  PlaceAt(FWidthSwitch, X, W, FWidthSwitch.Height);
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
// The scope and the options are kept at once, not only by a search (Vitalii,
// 2026-11-06: switched and closed - the choice was lost).
procedure TMainForm.ScopeChanged(Sender: TObject);
begin
  FSettings.SetSearchWholeLibrary(FScope.WholeLibrary);
  if not FScope.WholeLibrary and not FLeftPanel.Visible then
    SetLeftWanted(True);
end;

// Mockup h1: font-size clamp(30px, 4.6vw, 46px), vw - the window. The RTF is
// built at 46 px; here the title's characters get the size (EM_SETCHARFORMAT
// on 0..TitleLen, no rebuild, the scroll kept); the shelf / toc title too.
procedure TMainForm.UpdateTitleSize(Force: Boolean);
var
  Px: Integer;
  CF: TCharFormat2;
  Sel, Title: TCharRange;
  SI: TScrollInfo;
begin
  Px := EnsureRange(Round(ClientWidth * 96 / CurrentPPI * 0.046), 30, 46);
  if (Px = FTitlePx) and not Force then
    Exit;
  FTitlePx := Px;
  if FChapterList <> nil then
    FChapterList.SetTitlePx(Px);
  if (FShown = scNone) or (FDoc.TitleLen <= 0) or not redReader.HandleAllocated then
    Exit;
  SI.cbSize := SizeOf(SI);
  SI.fMask := SIF_POS;
  GetScrollInfo(redReader.Handle, SB_VERT, SI);
  SendMessage(redReader.Handle, WM_SETREDRAW, 0, 0);
  try
    SendMessage(redReader.Handle, EM_EXGETSEL, 0, LPARAM(@Sel));
    Title.cpMin := 0;
    Title.cpMax := FDoc.TitleLen;
    SendMessage(redReader.Handle, EM_EXSETSEL, 0, LPARAM(@Title));
    FillChar(CF, SizeOf(CF), 0);
    CF.cbSize := SizeOf(CF);
    CF.dwMask := CFM_SIZE;
    CF.yHeight := Px * 15;               // twips: px * 0.75 pt * 20
    SendMessage(redReader.Handle, EM_SETCHARFORMAT, SCF_SELECTION, LPARAM(@CF));
    SendMessage(redReader.Handle, EM_EXSETSEL, 0, LPARAM(@Sel));
    SendMessage(redReader.Handle, WM_VSCROLL, MakeWParam(SB_THUMBPOSITION, Word(SI.nPos)), 0);
  finally
    SendMessage(redReader.Handle, WM_SETREDRAW, 1, 0);
    redReader.Invalidate;
  end;
  HideReaderCaret;
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
var
  Shift: Integer;
begin
  // The RTF keeps the markers' zone as its left margin (\li960 = 64 px), but
  // EM_SETZOOM scales it with the text: the reader moves left by the zoom's
  // surplus, so the text stays under the crumbs at FLeftPad.
  Shift := FLeftPad - Round(ScaleValue(TextMarkerMargin) * ZoomPx(FZoomStep) / BaseTextPx);
  FitHidingScrollBar(redReader, Rect(Shift, 0, FReaderHost.ClientWidth, FReaderHost.ClientHeight));
end;

procedure TMainForm.SearchOptionClick(Sender: TObject);
begin
  FSettings.SetExactPhrase(FExactPhrase.Checked);
  FSettings.SetWordForms(FWordForms.Checked);
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

{ the width of the text column (E-23) }

procedure TMainForm.WidthSwitchChanged(Sender: TObject);
begin
  FTextWidthMode := FWidthSwitch.Mode;
  if FSettings <> nil then
    FSettings.SetTextWidthMode(FTextWidthMode);
  pnlCenterResize(nil);
end;

{ the side panels' widths (E-22) }

// The 1 px border of a side panel becomes a strip that takes the mouse: the
// page's colour, the line itself a disabled child on its outer edge (a disabled
// child gives its mouse messages to the parent).
procedure TMainForm.MakeSplitGrip(Grip: TPanel; LineAlign: TAlign);
var
  Line: TPanel;
begin
  Line := TPanel.Create(Self);
  Line.Parent := Grip;
  Line.Align := LineAlign;
  Line.Width := 1;
  Line.BevelOuter := bvNone;
  Line.ParentBackground := False;
  Line.Color := Grip.Color;
  Line.Enabled := False;
  Grip.Color := ColorBackground;
  Grip.Width := ScaleValue(SplitGripWidth);
  Grip.Cursor := crHSplit;
  Grip.OnMouseDown := SplitMouseDown;
  Grip.OnMouseMove := SplitMouseMove;
  Grip.OnMouseUp := SplitMouseUp;
  Grip.OnDblClick := SplitDblClick;
end;

// Between the limits, and the centre keeps its minimum beside the other panel.
function TMainForm.ClampSidePanelWidth(Panel: TPanel; Value: Integer): Integer;
var
  Other, Limit: Integer;
begin
  Other := 0;
  if (Panel = FLeftPanel) and FRightPanel.Visible then
    Other := FRightPanel.Width;
  if (Panel = FRightPanel) and FLeftPanel.Visible then
    Other := FLeftPanel.Width;
  Limit := Min(ScaleValue(SidePanelMaxWidth), ClientWidth - Other - ScaleValue(CenterMinWidth));
  Result := Max(Min(Value, Limit), ScaleValue(SidePanelMinWidth));
end;

procedure TMainForm.SetSidePanelWidth(Panel: TPanel; Value: Integer);
begin
  Value := ClampSidePanelWidth(Panel, Value);
  if Value <> Panel.Width then
    Panel.Width := Value;
end;

procedure TMainForm.SaveSidePanelWidths;
begin
  if FSettings = nil then
    Exit;
  FSettings.SetLeftPanelWidth(MulDiv(FLeftPanel.Width, 96, CurrentPPI));
  FSettings.SetRightPanelWidth(MulDiv(FRightPanel.Width, 96, CurrentPPI));
end;

// While the edge is dragged NOTHING is laid out again (Vitalii, 2026-11-16: a
// live resize re-flowed the chapter and repainted three lists on every mouse
// move - heavy, with trails of the previous picture). Only a thin line follows
// the mouse; the panel takes its width once, when the button is released.
procedure TMainForm.MoveSplitGuide;
var
  X: Integer;
begin
  if FSplitGuide = nil then
  begin
    FSplitGuide := TPanel.Create(Self);
    FSplitGuide.Visible := False;
    FSplitGuide.Parent := Self;
    FSplitGuide.Align := alNone;
    FSplitGuide.BevelOuter := bvNone;
    FSplitGuide.ParentBackground := False;
    FSplitGuide.Color := ColorAccent;
    FSplitGuide.Enabled := False;        // never takes the mouse from the strip
  end;
  // Where the panel's inner edge will be.
  if FSplitPanel = FLeftPanel then
    X := FLeftPanel.Left + FSplitWidth - ScaleValue(SplitGripWidth)
  else
    X := FRightPanel.Left + FRightPanel.Width - FSplitWidth + ScaleValue(SplitGripWidth) - ScaleValue(2);
  FSplitGuide.SetBounds(X, FSplitPanel.Top, ScaleValue(2), FSplitPanel.Height);
  if not FSplitGuide.Visible then
  begin
    FSplitGuide.Visible := True;
    FSplitGuide.BringToFront;
  end;
end;

procedure TMainForm.SplitMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  if Button <> mbLeft then
    Exit;
  if Sender = FLeftGrip then
    FSplitPanel := FLeftPanel
  else
    FSplitPanel := FRightPanel;
  FSplitStartX := Mouse.CursorPos.X;
  FSplitStartWidth := FSplitPanel.Width;
  FSplitWidth := FSplitStartWidth;
end;

procedure TMainForm.SplitMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Delta, Width: Integer;
begin
  if (FSplitPanel = nil) or not (ssLeft in Shift) then
    Exit;
  Delta := Mouse.CursorPos.X - FSplitStartX;
  if FSplitPanel = FRightPanel then
    Delta := -Delta;                     // its inner edge is the left one
  Width := ClampSidePanelWidth(FSplitPanel, FSplitStartWidth + Delta);
  if Width = FSplitWidth then
    Exit;
  FSplitWidth := Width;
  MoveSplitGuide;
end;

procedure TMainForm.SplitMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Panel: TPanel;
begin
  if FSplitPanel = nil then
    Exit;
  Panel := FSplitPanel;
  FSplitPanel := nil;
  if FSplitGuide <> nil then
    FSplitGuide.Visible := False;
  // One layout and one repaint for the whole drag.
  SetSidePanelWidth(Panel, FSplitWidth);
  SaveSidePanelWidths;
end;

// A double click on the edge: back to the width of the design.
procedure TMainForm.SplitDblClick(Sender: TObject);
begin
  FSplitPanel := nil;
  if FSplitGuide <> nil then
    FSplitGuide.Visible := False;
  if Sender = FLeftGrip then
    SetSidePanelWidth(FLeftPanel, ScaleValue(LeftPanelWidth))
  else
    SetSidePanelWidth(FRightPanel, ScaleValue(RightPanelWidth));
  SaveSidePanelWidths;
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
  FLeftGrip := Border;
  // The line on the strip's LEFT edge: the scrollbar stands right at the line,
  // the rest of the strip is on the reading side, where the page is blank anyway.
  MakeSplitGrip(Border, alLeft);
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
  // Mockup aside padding: 18 left, 10 right; the 40 at the bottom is the tree's BottomSpace.
  FLibraryHost.Margins.SetBounds(ScaleValue(18), 0, ScaleValue(10), 0);
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
  FRightGrip := Border;
  MakeSplitGrip(Border, alRight);        // the strip on the reading side here too
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

  Place(NewLine(TColor($00E6E6E6)), 22, 32, 22, 0);   // options margin-bottom 4 + 28
  FSearchStatus := NewCaption(11, 0.1);
  Place(FSearchStatus, 22, 16, 22, 8);

  // E-20: the two views of the results. The same pill as the scope: its first
  // segment ("WholeLibrary") is "за книгами".
  FViewSwitch := TScopeSwitch.Create(Self,
    function(Value: Integer): Integer
    begin
      Result := ScaleValue(Value);
    end);
  FViewSwitch.OnChange := ViewSwitchChanged;
  Place(FViewSwitch, 22, 2, 22, 8);

  // E-19: the pinned line - the book and the chapter of the topmost row - and
  // "collapse all" on its right.
  FResultBar := TPanel.Create(Self);
  FResultBar.BevelOuter := bvNone;
  FResultBar.ParentBackground := False;
  FResultBar.Color := ColorBackground;
  FResultBar.Height := ScaleValue(18);
  Place(FResultBar, 22, 0, 22, 6);
  FCollapseAll := NewCaption(11, 0);
  FCollapseAll.Parent := FResultBar;
  FCollapseAll.Align := alRight;
  FCollapseAll.Layout := tlCenter;
  FCollapseAll.Font.Color := ColorAccent;
  FCollapseAll.Cursor := crHandPoint;
  FCollapseAll.OnClick := CollapseAllClick;
  FCollapseAll.Visible := False;
  FPinned := NewCaption(11, 0);
  FPinned.Parent := FResultBar;
  FPinned.AutoSize := False;
  FPinned.Align := alClient;
  FPinned.Layout := tlCenter;

  FResultsHost := TPanel.Create(Self);
  FResultsHost.Parent := Content;
  FResultsHost.Top := Order * 1000 + 1000;           // after the alTop rows
  FResultsHost.Align := alClient;
  FResultsHost.AlignWithMargins := True;
  // Mockup aside padding 22; the rows keep 8 of it inside (the accent bar 2 +
  // padding 6), so their text stands on the panel's left edge with the captions
  // above. 60 at the bottom is the list's BottomSpace.
  FResultsHost.Margins.SetBounds(ScaleValue(14), 0, ScaleValue(22), 0);
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
  // Vertical only: with AlwaysVisible VST's default ssBoth showed a horizontal bar.
  FResultList.Control.ScrollBarOptions.ScrollBars := System.UITypes.TScrollStyle.ssVertical;
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
  FResultList.OnPinnedChanged := procedure
    begin
      FPinned.Caption := FResultList.PinnedText;
    end;
  FResultList.OnFoldChanged := procedure
    begin
      UpdateResultBar;                   // "collapse all" <-> "expand all"
    end;
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
  // R8-05: a result of the chapter that is already shown, with the same search,
  // only moves the current match - nothing is rebuilt.
  FOnChapterLoaded := procedure(Args: TChapterLoadedArgs)
    begin
      if ShowsChapter(Args.Content.Ref) then
        FocusShownHit(Args.Focus)
      else
      begin
        RememberShownQuery;
        RenderChapter(Args);
      end;
    end;
  FOnBibleChapterLoaded := procedure(Args: TBibleChapterLoadedArgs)
    begin
      if ShowsChapter(Args.Content.Ref) then
        FocusShownHit(Args.Focus)
      else
      begin
        RememberShownQuery;
        RenderBibleChapter(Args);
      end;
    end;
  FOnSearchCompleted := procedure(Summary: TSearchSummary) begin ShowSearchSummary(Summary); end;
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
  FViewSwitch.WholeLibrary := FSettings.GetResultOrder = soText;
  FExactPhrase.Checked := FSettings.GetExactPhrase;
  FWordForms.Checked := FSettings.GetWordForms;
  // E-22: the widths the reader left; the limit by the centre is applied when
  // a panel is dragged, not here - the window has not got its size yet.
  if FSettings.GetLeftPanelWidth > 0 then
    FLeftPanel.Width := EnsureRange(ScaleValue(FSettings.GetLeftPanelWidth),
      ScaleValue(SidePanelMinWidth), ScaleValue(SidePanelMaxWidth));
  if FSettings.GetRightPanelWidth > 0 then
    FRightPanel.Width := EnsureRange(ScaleValue(FSettings.GetRightPanelWidth),
      ScaleValue(SidePanelMinWidth), ScaleValue(SidePanelMaxWidth));
  FTextWidthMode := FSettings.GetTextWidthMode;
  if FWidthSwitch <> nil then
    FWidthSwitch.Mode := FTextWidthMode;
  pnlCenterResize(nil);                  // the column takes the chosen width
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
  if FWidthSwitch <> nil then
    FWidthSwitch.Hint := L('header.textWidth');
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
  FViewSwitch.AllCaption := L('search.view.books');
  FViewSwitch.CheckedCaption := L('search.view.relevance');
  if FHasReply then
    RebuildResults                       // "Розділ N" in the headings and reference lines
  else
    FResultList.Invalidate;
  UpdateResultBar;
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
  Side, LeftPad, ColumnWidth, TextLeft, Margin: Integer;
begin
  // A.5 with the mockup's CSS (Presentation.Theme): side padding of the centre,
  // then a column of at most 724 px of text plus its left margin, centred.
  // "vw" is the window width.
  Side := EnsureRange(ClientWidth * TextColumnSidePercent div 100,
    ScaleValue(TextColumnSideMin), ScaleValue(TextColumnSideMax));
  LeftPad := EnsureRange(ClientWidth * TextColumnLeftPercent div 100,
    ScaleValue(TextColumnLeftMin), ScaleValue(TextColumnLeftMax));
  // border-box as the mockup's CSS: the left padding is inside the 724 px, the
  // text starts after it.
  ColumnWidth := Min(ScaleValue(TextColumnMax), pnlCenter.ClientWidth - 2 * Side);
  // E-23: medium and wide take a share of the centre, up to their limit - the
  // column grows and shrinks with the window and the side panels - and are
  // never narrower than narrow.
  case FTextWidthMode of
    1: ColumnWidth := Max(ColumnWidth, Min(pnlCenter.ClientWidth * TextColumnMediumPercent div 100,
         ScaleValue(TextColumnMediumMax)));
    2: ColumnWidth := Max(ColumnWidth, Min(pnlCenter.ClientWidth * TextColumnWidePercent div 100,
         ScaleValue(TextColumnWideMax)));
  end;
  ColumnWidth := Max(Min(ColumnWidth, pnlCenter.ClientWidth - 2 * Side), 0);
  TextLeft := (pnlCenter.ClientWidth - ColumnWidth) div 2 + LeftPad;
  // pnlColumn itself starts the markers' zone (64 px) left of the text, so
  // inside it the text is always at 64: crumbs, chapter bar, toc numbers
  // (mockup: left -64px) and the RTF's \li960 line up.
  Margin := ScaleValue(TextMarkerMargin);
  FLeftPad := Margin;
  pnlCrumbs.Margins.Left := Margin;
  pnlChapterNav.Margins.SetBounds(Margin, 0, 0, 0);
  if FHitNav <> nil then                 // OnResize may come before CreateHitNav
    FHitNav.Margins.SetBounds(Margin, 0, 0, ScaleValue(HitRowGap));
  if FChapterList <> nil then
    FChapterList.SetLeftPad(Margin);
  pnlColumn.Width := Max(ColumnWidth - LeftPad, 0) + Margin;
  pnlColumn.Left := TextLeft - Margin;
  pnlColumn.Top := 0;
  pnlColumn.Height := pnlCenter.ClientHeight;
  if FReaderHost <> nil then
    ReaderHostResize(nil);
  UpdateTitleSize(False);
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
        else if FViewModel.ShelfSeries <> '' then
        begin
          Category := FViewModel.ShelfCategory;
          AddCrumb(L(CategoryKeys[Category]), procedure begin FViewModel.ShowShelf(Category); end);
          AddCrumb(SeriesTitle(FViewModel.ShelfSeries), nil);
        end
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

function TMainForm.FindSeries(const Series: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNodes) do
    if (FNodes[I].Kind = lnSeries) and (FNodes[I].Series = Series) then
      Exit(I);
  Result := -1;
end;

function TMainForm.SeriesTitle(const Series: string): string;
var
  I: Integer;
begin
  I := FindSeries(Series);
  if I >= 0 then
    Result := FNodes[I].Caption
  else
    Result := Series;
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
  else if FViewModel.ShelfSeries <> '' then
  begin
    // A series: its books in tree order (SortOrder, B-25).
    Root := FindSeries(FViewModel.ShelfSeries);
    for I := 0 to High(FNodes) do
      if (Root >= 0) and (FNodes[I].Kind = lnModule) and (FNodes[I].Parent = Root) then
      begin
        Row := Default(TListRow);
        Row.NodeIndex := I;
        Row.Title := FNodes[I].Caption;
        Row.Meta := L('library.chapters', [FNodes[I].Count]);
        if FSettings.GetPosition(FNodes[I].ModuleId, P) and (P.Kind = ckBook) then
          Row.Status := L('shelf.reading', [P.Chapter.ChapterOrder]);
        Rows := Rows + [Row];
      end;
    Title := SeriesTitle(FViewModel.ShelfSeries);
    Subtitle := L('shelf.seriesBooks', [Length(Rows)]);
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
  FChapterList.Show(Title, Subtitle, Rows, True);   // the mockup's cards
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
  Request: THighlightRequest;
begin
  FShown := scBook;
  FLastChapter := Args;
  // R8-04: the boxes of the matches are painted by the form (E-21), so the
  // document does not depend on the current match - it is built once.
  Request.Hits := Args.Hits;
  ShowDocument(TChapterRtfBuilder.Build(Args.Content,
    L('read.chapter', [Args.Content.Ref.ChapterOrder]), FTheme, Request), Args.Focus, FocusMatch);
end;

procedure TMainForm.RenderBibleChapter(const Args: TBibleChapterLoadedArgs; FocusMatch: Integer);
var
  Request: TVerseHighlightRequest;
begin
  FShown := scBible;
  FLastBibleChapter := Args;
  Request.Hits := Args.Hits;
  ShowDocument(TChapterRtfBuilder.Build(Args.Content, Args.BookTitle,
    L('read.chapter', [Args.Content.Ref.ChapterNumber]), FTheme, Request), Args.Focus, FocusMatch);
end;

// The ViewModel names the current PARAGRAPH (the clicked result); the
// navigator works by words, so the paragraph becomes its first word.
procedure TMainForm.ShowDocument(const Doc: TChapterRtf; ParagraphFocus, FocusMatch: Integer);
begin
  if (FocusMatch < 0) and (ParagraphFocus >= 0) and (ParagraphFocus <= High(Doc.HitFirstMatch))
    and (Doc.HitFirstMatch[ParagraphFocus] >= 0) then
    FocusMatch := Doc.HitFirstMatch[ParagraphFocus];
  FFocusMatch := FocusMatch;
  FMatchCount := Length(Doc.MatchStarts);
  LoadDocument(Doc, FocusMatch);
  UpdateTitleSize(True);
  UpdateHitNav;
end;

// R8-04: the document stays as it is - the current match moves, the reader
// scrolls to it and the boxes are painted again. Out of range - no current
// match, the top of the chapter.
procedure TMainForm.GoToMatch(Index: Integer);
begin
  if (Index >= 0) and (Index <= High(FDoc.MatchStarts)) then
  begin
    FFocusMatch := Index;
    ScrollToChar(redReader, FDoc.MatchStarts[Index]);
  end
  else
  begin
    FFocusMatch := -1;
    ScrollToChar(redReader, 0);
  end;
  redReader.Invalidate;                  // the former current box and the new one
  UpdateHitNav;
end;

procedure TMainForm.RememberShownQuery;
begin
  FDocHasQuery := FViewModel.HasActiveQuery;
  FDocQuery := FViewModel.ActiveQuery;
  FHitQuery := FDocQuery.Text;
end;

function TMainForm.ShownQueryIsActive: Boolean;
var
  Query: TSearchQuery;
begin
  if FDocHasQuery <> FViewModel.HasActiveQuery then
    Exit(False);
  if not FDocHasQuery then
    Exit(True);
  Query := FViewModel.ActiveQuery;
  Result := (Query.Text = FDocQuery.Text) and (Query.ExactPhrase = FDocQuery.ExactPhrase)
    and (Query.WordForms = FDocQuery.WordForms);
end;

function TMainForm.ShowsChapter(const Ref: TChapterRef): Boolean;
begin
  Result := (FShown = scBook) and ShownQueryIsActive
    and (FLastChapter.Content.Ref.ModuleId = Ref.ModuleId)
    and (FLastChapter.Content.Ref.ChapterOrder = Ref.ChapterOrder);
end;

function TMainForm.ShowsChapter(const Ref: TBibleChapterRef): Boolean;
begin
  Result := (FShown = scBible) and ShownQueryIsActive
    and (FLastBibleChapter.Content.Ref.Book.ModuleId = Ref.Book.ModuleId)
    and (FLastBibleChapter.Content.Ref.Book.BookCode = Ref.Book.BookCode)
    and (FLastBibleChapter.Content.Ref.ChapterNumber = Ref.ChapterNumber);
end;

// The paragraph / verse the ViewModel names (index in the hits of the shown
// document) -> its first word; none - the top of the chapter.
procedure TMainForm.FocusShownHit(ParagraphFocus: Integer);
begin
  if (ParagraphFocus >= 0) and (ParagraphFocus <= High(FDoc.HitFirstMatch)) then
    GoToMatch(FDoc.HitFirstMatch[ParagraphFocus])
  else
    GoToMatch(-1);
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
    lnSeries:
      for Category := Low(TBookCategory) to High(TBookCategory) do
        if (Node.Parent >= 0) and (CategoryKeys[Category] = FNodes[Node.Parent].CaptionKey) then
          FViewModel.ShowSeriesShelf(Category, Node.Series);
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
  end;
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
  ReaderHostResize(nil);                 // the margin scales with the zoom
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
  // The boxes of the matches go over what RichEdit has just painted (its own
  // \highlight stood higher than the words - see Shell.RichEdit).
  if (Message.Msg = WM_PAINT) and (FShown <> scNone) and (Length(FDoc.MatchStarts) > 0) then
    PaintMatchBoxes(redReader, FDoc.MatchStarts, FDoc.MatchLens, FFocusMatch,
      Round(ScaleValue(100) * ZoomPx(FZoomStep) / 100));
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
    ClearSearchResults;                  // no query - nothing to show, no "enter a word"
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

procedure TMainForm.ShowSearchSummary(const Summary: TSearchSummary);
begin
  FSearchDone := True;
  // A new search: nothing of the previous list is kept.
  FResultList.Clear;
  FreeAndNil(FModel);
  FViewState[soText] := Default(TResultListState);
  FViewState[soRelevance] := Default(TResultListState);
  FSummary := Summary;
  FHasReply := True;
  RebuildResults;
end;

// The list is built from the counts of the last search (B-34): after a search,
// a change of the view (E-20) or of the language ("Розділ N"). No rows are read
// here - the list asks for them as it paints.
procedure TMainForm.RebuildResults;
var
  ModuleOrder: TArray<TModuleId>;
  View: TSearchOrder;
  Model: TSearchResultsModel;
  I: Integer;
begin
  if not FHasReply then
    Exit;
  // The list of the same search is rebuilt (the view or the language changed):
  // keep how the reader left it.
  if FModel <> nil then
    FViewState[FModel.Order] := FResultList.SaveState;
  // The books and translations as the library tree lists them (B-25).
  ModuleOrder := nil;
  for I := 0 to High(FNodes) do
    if FNodes[I].Kind in [lnModule, lnBibleTranslation] then
      ModuleOrder := ModuleOrder + [FNodes[I].ModuleId];
  if FViewSwitch.WholeLibrary then
    View := soText
  else
    View := soRelevance;
  Model := TSearchResultsModel.Create(FSummary.Books, FSummary.Bible, FViewModel.Catalog,
    ModuleOrder, View,
    function(ChapterOrder: Integer): string
    begin
      Result := L('read.chapter', [ChapterOrder]);
    end,
    function(const ModuleIds: TArray<TModuleId>; Order: TSearchOrder;
      Offset, Count: Integer): TArray<TBookSearchResult>
    begin
      Result := FViewModel.FetchBookResults(ModuleIds, Order, Offset, Count);
    end,
    function(const ModuleIds: TArray<TModuleId>; Order: TSearchOrder;
      Offset, Count: Integer): TArray<TBibleSearchResult>
    begin
      Result := FViewModel.FetchBibleResults(ModuleIds, Order, Offset, Count);
    end);
  FResultList.Show(Model);
  FModel.Free;                           // the list no longer shows the previous one
  FModel := Model;
  FResultList.RestoreState(FViewState[View]);
  UpdateResultBar;
  ShowSearchStatus('search.hits', Model.TotalHits);   // always the exact number (B-34)
end;

procedure TMainForm.UpdateResultBar;
begin
  if FCollapseAll = nil then
    Exit;
  // By books only: by relevance the list is flat (the Bible keeps its
  // translations, each folds by its own button).
  FCollapseAll.Visible := FHasReply and FViewSwitch.WholeLibrary and FResultList.HasBlocks;
  if FResultList.AllCollapsed then
    FCollapseAll.Caption := L('search.expandAll')
  else
    FCollapseAll.Caption := L('search.collapseAll');
  FPinned.Caption := FResultList.PinnedText;
end;

// E-20: the view is kept at once and the list is rebuilt from the same counts -
// no new search.
procedure TMainForm.ViewSwitchChanged(Sender: TObject);
begin
  if FViewSwitch.WholeLibrary then
    FSettings.SetResultOrder(soText)
  else
    FSettings.SetResultOrder(soRelevance);
  RebuildResults;
end;

procedure TMainForm.CollapseAllClick(Sender: TObject);
begin
  if FResultList.AllCollapsed then
    FResultList.ExpandAll
  else
    FResultList.CollapseAll;
  UpdateResultBar;
end;

procedure TMainForm.SearchResultOpened(Section: TResultSectionKind; const Line: TResultLine);
var
  Queued: TThreadProcedure;
  IsBook: Boolean;
  BookRef: TParagraphRef;
  BibleRef: TVerseRef;
begin
  IsBook := Section = rsBooks;
  BookRef := Line.BookRef;
  BibleRef := Line.BibleRef;
  // Opening a chapter moves the focus; do it after the click has finished.
  Queued := procedure
    begin
      if IsBook then
        FViewModel.OpenSearchResult(BookRef)
      else
        FViewModel.OpenSearchResult(BibleRef);
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
  // An emptied field clears the results and the status (Vitalii, 2026-11-06).
  if FSearchEdit.GetTextLen = 0 then
    ClearSearchResults;
end;

procedure TMainForm.ClearSearchResults;
begin
  FHasReply := False;
  FResultList.Clear;
  FreeAndNil(FModel);
  FViewState[soText] := Default(TResultListState);
  FViewState[soRelevance] := Default(TResultListState);
  UpdateResultBar;
  ShowSearchStatus('');
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

// F3 / Shift+F3 (A.6): the next / previous highlighted word of the shown
// document (R8-04: nothing is rebuilt).
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
  if (FViewModel.View <> rvRead) or (FMatchCount = 0) or (FShown = scNone) then
    Exit;
  GoToMatch(Step(FFocusMatch, FMatchCount));
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
    Result.Width := ScaleValue(20);
    Result.TabStop := False;
    Result.ShowHint := True;
    Result.OnClick := OnClick;
  end;

begin
  // A row of its own under the crumbs, the box at the right, fixed (Vitalii,
  // 2026-11-06: at the bottom it was not clear what it is). With it the gap
  // crumbs - text stays 44 px: crumbs 8 + row 28 + 8.
  FHitNav := TPanel.Create(Self);
  FHitNav.Parent := pnlColumn;
  FHitNav.Align := alTop;
  FHitNav.AlignWithMargins := True;
  FHitNav.Height := ScaleValue(HitRowHeight);
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
  // Flush right: the "›" glyph (centred in its 20 px button) ends at the text's
  // right edge, the button's empty half goes past it.
  FHitBox.SetBounds(Max(FHitNav.ClientWidth - W + ScaleValue(6), 0),
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
  if (Count > 0) <> FHitNav.Visible then
  begin
    // alTop keeps the order of Top: right under the crumbs.
    FHitNav.Top := pnlCrumbs.BoundsRect.Bottom + 1;
    FHitNav.Visible := Count > 0;
    if Count > 0 then
      pnlCrumbs.Margins.Bottom := ScaleValue(HitRowGap)
    else
      pnlCrumbs.Margins.Bottom := ScaleValue(CrumbsBottom);
  end;
  if Count = 0 then
    Exit;
  if Focus >= 0 then
    FHitLabel.Caption := L('read.hitNav', [FHitQuery, Focus + 1, Count])
  else
    FHitLabel.Caption := L('read.hitCount', [FHitQuery, Count]);
  HitNavResize(nil);
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

// Each link takes its text's width, at most half of the bar.
procedure TMainForm.ChapterBarResize(Sender: TObject);
var
  Room: Integer;

  function TextWidth(Link: TLabel): Integer;
  begin
    Canvas.Font := Link.Font;
    Result := Canvas.TextWidth(Link.Caption) + ScaleValue(4);
  end;

begin
  if FPrevLink = nil then
    Exit;
  Room := Max((pnlChapterNav.ClientWidth - ScaleValue(24)) div 2, 0);
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
