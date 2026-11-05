unit Shell.MainForm;

(* TMainForm - the VCL shell (Slovo_04 Part D) implementing IMainView.

  Built so far: the text column (A.2, A.5, C.4) - clickable breadcrumbs, the
  chapter as one RTF document in a TRichEdit (E-01) with the character-count
  check, zoom (E-11), the ‹ › bar, the shelf and the table of contents
  (Shell.ChapterList, C.5); the library tree on the left (Shell.LibraryTree,
  A.3). Next: the search panel (A.4), the header and the error banner (E-15).

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
  Core.Domain,
  Core.Contracts,
  Presentation.MainViewModel,
  Presentation.Theme,
  Presentation.ChapterRtf,
  Presentation.Views,
  Shell.LibraryTree,
  Shell.ChapterList;

type
  // The last chapter shown - re-rendered when the language changes ("Розділ N").
  TShownChapter = (scNone, scBook, scBible);

  TMainForm = class(TForm, IMainView)
    mmMain: TMainMenu;
    miFile: TMenuItem;
    miExit: TMenuItem;
    miView: TMenuItem;
    miZoomIn: TMenuItem;
    miZoomOut: TMenuItem;
    miZoomReset: TMenuItem;
    miViewSeparator: TMenuItem;
    miLanguage: TMenuItem;
    miLanguageUkrainian: TMenuItem;
    miLanguageRussian: TMenuItem;
    miLanguageEnglish: TMenuItem;
    miHelp: TMenuItem;
    miSQLiteDiagnostics: TMenuItem;
    alMain: TActionList;
    actZoomIn: TAction;
    actZoomOut: TAction;
    actZoomReset: TAction;
    actPrevChapter: TAction;
    actNextChapter: TAction;
    pnlStatus: TPanel;
    lblStatus: TLabel;
    pnlCenter: TPanel;
    pnlColumn: TPanel;
    pnlCrumbs: TPanel;
    redReader: TRichEdit;
    pnlChapterNav: TPanel;
    btnPrevChapter: TButton;
    btnNextChapter: TButton;
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

    procedure ApplyLocalization;
    procedure UpdateStatus;
    procedure ShowView(View: TReaderView);
    procedure FillShelf;
    procedure FillToc;
    procedure GoUp;
    procedure RenderChapter(const Args: TChapterLoadedArgs);
    procedure RenderBibleChapter(const Args: TBibleChapterLoadedArgs);
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
  Shell.RichEdit;

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

{ form }

procedure TMainForm.FormCreate(Sender: TObject);
begin
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
  redReader.AlignWithMargins := True;
  pnlChapterNav.AlignWithMargins := True;

  // E-11: Ctrl+wheel is ours, so msftedit's own zoom never drifts from the setting.
  FReaderWndProc := redReader.WindowProc;
  redReader.WindowProc := ReaderWndProc;

  CreateLeftPanel;

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
  inherited;
end;

procedure TMainForm.CreateLeftPanel;
begin
  FLeftPanel := TPanel.Create(Self);
  FLeftPanel.Parent := Self;
  FLeftPanel.Align := alLeft;
  FLeftPanel.Width := ScaleValue(LeftPanelWidth);
  FLeftPanel.BevelOuter := bvNone;
  FLeftPanel.ParentBackground := False;
  FLeftPanel.Color := ColorBackground;

  FLibraryTitle := TLabel.Create(Self);
  FLibraryTitle.Parent := FLeftPanel;
  FLibraryTitle.Align := alTop;
  FLibraryTitle.AlignWithMargins := True;
  FLibraryTitle.Margins.SetBounds(ScaleValue(12), ScaleValue(16), ScaleValue(12), ScaleValue(8));
  FLibraryTitle.Font.Style := [fsBold];

  FLibraryTree := TLibraryTree.Create(Self, FLeftPanel);
  FLibraryTree.OnActivate := LibraryNodeActivated;
  FLibraryTree.OnCheck := LibraryNodeChecked;
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
  FOnChapterLoaded := procedure(Args: TChapterLoadedArgs) begin RenderChapter(Args); end;
  FOnBibleChapterLoaded := procedure(Args: TBibleChapterLoadedArgs) begin RenderBibleChapter(Args); end;
  FOnSearchCompleted := procedure(Reply: TSearchReply) begin end;
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
  FZoomStep := EnsureRange(FSettings.GetZoomStep, MinZoomStep, MaxZoomStep);
  PrepareReader(redReader);
  SetZoomPx(redReader, ZoomPx(FZoomStep));
  ApplyLocalization;
  RestoreGeometry;

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
  miFile.Caption := L('menu.file');
  miExit.Caption := L('menu.file.exit');
  miView.Caption := L('menu.view');
  actZoomIn.Caption := L('header.bigger');
  actZoomOut.Caption := L('header.smaller');
  actZoomReset.Caption := L('menu.view.zoomReset');
  miViewSeparator.Caption := cLineCaption;
  miLanguage.Caption := L('menu.view.language');
  miHelp.Caption := L('menu.help');
  miSQLiteDiagnostics.Caption := L('menu.help.sqliteDiagnostics');

  miLanguageUkrainian.Caption := LanguageName(UILanguageCodes[0]);
  miLanguageRussian.Caption := LanguageName(UILanguageCodes[1]);
  miLanguageEnglish.Caption := LanguageName(UILanguageCodes[2]);
  miLanguageUkrainian.Checked := Localizer.Language = UILanguageCodes[0];
  miLanguageRussian.Checked := Localizer.Language = UILanguageCodes[1];
  miLanguageEnglish.Checked := Localizer.Language = UILanguageCodes[2];

  FLibraryTitle.Caption := L('library.title');
  FLibraryTree.Invalidate;
  actPrevChapter.Caption := '‹  ' + L('read.prevChapter');
  actNextChapter.Caption := L('read.nextChapter') + '  ›';
  UpdateStatus;
end;

procedure TMainForm.UpdateStatus;
begin
  lblStatus.Caption := Format('%s: %d  ·  %s  ·  %d %%', [L('library.title'),
    Length(FViewModel.Catalog.Modules), L('search.scope.checked', [FCheckedCount]),
    Round(ZoomPx(FZoomStep) / BaseTextPx * 100)]);
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
  redReader.Margins.SetBounds(LeftPad, 0, 0, 0);
  pnlChapterNav.Margins.SetBounds(LeftPad, 0, 0, 0);
  if FChapterList <> nil then
    FChapterList.SetLeftPad(LeftPad);
  pnlColumn.Width := Max(Min(ScaleValue(TextColumnMax) + LeftPad,
    pnlCenter.ClientWidth - 2 * Side), 0);
  pnlColumn.Left := (pnlCenter.ClientWidth - pnlColumn.Width) div 2;
  pnlColumn.Top := 0;
  pnlColumn.Height := pnlCenter.ClientHeight;
end;

procedure TMainForm.ShowView(View: TReaderView);
begin
  redReader.Visible := View = rvRead;
  pnlChapterNav.Visible := View = rvRead;
  FChapterList.Host.Visible := View <> rvRead;
  case View of
    rvShelf: FillShelf;
    rvToc:   FillToc;
  end;
  UpdateCrumbs;
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
  begin
    Result := TLabel.Create(Self);
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

procedure TMainForm.RenderChapter(const Args: TChapterLoadedArgs);
var
  Request: THighlightRequest;
begin
  FShown := scBook;
  FLastChapter := Args;
  Request.Hits := Args.Hits;
  Request.Focus := Args.Focus;
  LoadDocument(TChapterRtfBuilder.Build(Args.Content,
    L('read.chapter', [Args.Content.Ref.ChapterOrder]), FTheme, Request), Args.Focus);
end;

procedure TMainForm.RenderBibleChapter(const Args: TBibleChapterLoadedArgs);
var
  Request: TVerseHighlightRequest;
begin
  FShown := scBible;
  FLastBibleChapter := Args;
  Request.Hits := Args.Hits;
  Request.Focus := Args.Focus;
  LoadDocument(TChapterRtfBuilder.Build(Args.Content, Args.BookTitle,
    L('read.chapter', [Args.Content.Ref.ChapterNumber]), FTheme, Request), Args.Focus);
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

  if (Focus >= 0) and (Focus <= High(Doc.HitStarts)) and (Doc.HitStarts[Focus] >= 0) then
    ScrollToChar(redReader, Doc.HitStarts[Focus])
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

{ errors }

procedure TMainForm.ShowError(Error: TResultError);
begin
  lblStatus.Caption := L(ErrorKey(Error));       // the banner (E-15) - next step
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
  // A.6: the tree keeps its own arrows and Backspace (expand, collapse, parent).
  if ActiveControl = FLibraryTree.Control then
    Exit;
  case Key of
    vkLeft, vkRight:
      if (FViewModel.View = rvRead) and (Shift = []) then
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
        scBook:  RenderChapter(FLastChapter);
        scBible: RenderBibleChapter(FLastBibleChapter);
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
