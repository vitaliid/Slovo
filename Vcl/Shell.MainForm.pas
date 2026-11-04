unit Shell.MainForm;

(* TMainForm - the VCL shell (Slovo_04 Part D) implementing IMainView.

  This step: the CENTRE of the window - the text column (A.2, A.5, C.4):
  breadcrumbs, the chapter as one RTF document in a TRichEdit (E-01), the
  character-count check (C.4), zoom (E-11) and the ‹ › bar.

  Still temporary: the shelf and the table of contents are a plain list box in
  the same column (double click or Enter opens, Backspace goes up). It is
  replaced by the VirtualTreeView panels in the next step; Bind/Unbind stay.

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
  Shell.LibraryTree;

type
  // What the temporary list shows in each row and what a double click opens.
  TShellItemKind = (likModule, likTranslation, likBibleBook, likChapter, likBibleChapter);

  TShellListItem = record
    Kind: TShellItemKind;
    ModuleId: TModuleId;
    BookCode: TBookCode;
    Number: Integer;                     // ChapterOrder / ChapterNumber
  end;

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
    lblCrumbs: TLabel;
    redReader: TRichEdit;
    lstItems: TListBox;
    pnlChapterNav: TPanel;
    btnPrevChapter: TButton;
    btnNextChapter: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure pnlCenterResize(Sender: TObject);
    procedure lstItemsDblClick(Sender: TObject);
    procedure lstItemsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
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

    FItems: TArray<TShellListItem>;
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

    procedure ApplyLocalization;
    procedure UpdateStatus;
    procedure ShowView(View: TReaderView);
    procedure FillShelf;
    procedure FillToc;
    procedure AddItem(const Caption: string; const Item: TShellListItem);
    procedure OpenItem(Index: Integer);
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
  lstItems.Color := ColorBackground;
  lblCrumbs.Font.Color := ColorMuted;

  // E-11: Ctrl+wheel is ours, so msftedit's own zoom never drifts from the setting.
  FReaderWndProc := redReader.WindowProc;
  redReader.WindowProc := ReaderWndProc;

  CreateLeftPanel;
end;

destructor TMainForm.Destroy;
begin
  FLibraryTree.Free;                     // the VST itself is owned by the form
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
  lstItems.Font.Name := FTheme.TextFont;
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
begin
  // A.5: Width = Min(724, available), centred; the scroll bar sits by the column.
  pnlColumn.Width := Min(ScaleValue(TextColumnMax), pnlCenter.ClientWidth);
  pnlColumn.Left := (pnlCenter.ClientWidth - pnlColumn.Width) div 2;
  pnlColumn.Top := 0;
  pnlColumn.Height := pnlCenter.ClientHeight;
end;

procedure TMainForm.ShowView(View: TReaderView);
begin
  redReader.Visible := View = rvRead;
  pnlChapterNav.Visible := View = rvRead;
  lstItems.Visible := View <> rvRead;
  case View of
    rvShelf: FillShelf;
    rvToc:   FillToc;
  end;
  UpdateCrumbs;
  // During Start the form is not shown yet: CanFocus ignores the form's own
  // visibility, Showing does not.
  if (View = rvRead) and redReader.Showing then
    redReader.SetFocus
  else if (View <> rvRead) and lstItems.Showing then
    lstItems.SetFocus;
end;

procedure TMainForm.UpdateCrumbs;
var
  M: TModule;
  Parts: TArray<string>;
  P: TReadingPosition;
begin
  Parts := nil;
  case FViewModel.View of
    rvShelf:
      if FViewModel.ShelfTranslation <> '' then
        Parts := [L(BibleCategoryKey), FViewModel.ModuleTitle(FViewModel.ShelfTranslation)]
      else
        Parts := [L(CategoryKeys[FViewModel.ShelfCategory])];
    rvToc:
      if FViewModel.TocBook.BookCode <> '' then
        Parts := [L(BibleCategoryKey) + ' · ' + FViewModel.ModuleTitle(FViewModel.TocBook.ModuleId),
          FViewModel.BookTitle(FViewModel.TocBook)]
      else if FViewModel.Catalog.FindModule(FViewModel.TocModule, M) then
        Parts := [L(CategoryKeys[M.Category]), M.Title];
    rvRead:
      begin
        P := FViewModel.Position;
        if P.Kind = ckBibleTranslation then
          Parts := [L(BibleCategoryKey) + ' · ' + FViewModel.ModuleTitle(P.BibleChapter.Book.ModuleId),
            FViewModel.BookTitle(P.BibleChapter.Book),
            FViewModel.BookTitle(P.BibleChapter.Book) + ' ' + IntToStr(P.BibleChapter.ChapterNumber)]
        else if FViewModel.Catalog.FindModule(P.Chapter.ModuleId, M) then
          Parts := [L(CategoryKeys[M.Category]), M.Title,
            L('read.chapter', [P.Chapter.ChapterOrder]) + ' · ' + FViewModel.ChapterTitle(P.Chapter)];
      end;
  end;
  lblCrumbs.Caption := string.Join('  /  ', Parts).ToUpper;
end;

{ temporary shelf and table of contents - replaced by VST (C.5) }

procedure TMainForm.AddItem(const Caption: string; const Item: TShellListItem);
begin
  lstItems.Items.Add(Caption);
  FItems := FItems + [Item];
end;

procedure TMainForm.FillShelf;
var
  M: TModule;
  B: TBookInfo;
  Item: TShellListItem;
begin
  lstItems.Items.BeginUpdate;
  try
    lstItems.Items.Clear;
    FItems := nil;
    Item := Default(TShellListItem);
    if FViewModel.ShelfTranslation <> '' then
      for B in FViewModel.Catalog.Books(FViewModel.ShelfTranslation) do
      begin
        Item.Kind := likBibleBook;
        Item.ModuleId := B.Ref.ModuleId;
        Item.BookCode := B.Ref.BookCode;
        AddItem(B.DisplayTitle + '  ·  ' + L('library.bibleChapters', [B.ChapterCount]), Item);
      end
    else
      // Temporary: every module, so that the Bible is reachable without the tree.
      for M in FViewModel.Catalog.Modules do
      begin
        Item.ModuleId := M.Id;
        if M.Kind = ckBibleTranslation then
        begin
          Item.Kind := likTranslation;
          AddItem(L(BibleCategoryKey) + ' · ' + M.Title + '  ·  ' + L('library.bibleBooks', [M.ChildCount]), Item);
        end
        else
        begin
          Item.Kind := likModule;
          AddItem(M.Title + '  ·  ' + L('library.chapters', [M.ChildCount]), Item);
        end;
      end;
  finally
    lstItems.Items.EndUpdate;
  end;
  if lstItems.Count > 0 then
    lstItems.ItemIndex := 0;
end;

procedure TMainForm.FillToc;
var
  C: TChapterInfo;
  B: TBookInfo;
  Item: TShellListItem;
  I: Integer;
begin
  lstItems.Items.BeginUpdate;
  try
    lstItems.Items.Clear;
    FItems := nil;
    Item := Default(TShellListItem);
    if FViewModel.TocBook.BookCode <> '' then
    begin
      for B in FViewModel.Catalog.Books(FViewModel.TocBook.ModuleId) do
        if B.Ref.BookCode = FViewModel.TocBook.BookCode then
          for I := 1 to B.ChapterCount do
          begin
            Item.Kind := likBibleChapter;
            Item.ModuleId := B.Ref.ModuleId;
            Item.BookCode := B.Ref.BookCode;
            Item.Number := I;
            AddItem(B.DisplayTitle + ' ' + IntToStr(I), Item);
          end;
    end
    else
      for C in FViewModel.Catalog.Chapters(FViewModel.TocModule) do
      begin
        Item.Kind := likChapter;
        Item.ModuleId := C.Ref.ModuleId;
        Item.Number := C.Ref.ChapterOrder;
        AddItem(Format('%3d   %s', [C.Ref.ChapterOrder, C.Title]), Item);
      end;
  finally
    lstItems.Items.EndUpdate;
  end;
  if lstItems.Count > 0 then
    lstItems.ItemIndex := 0;
end;

procedure TMainForm.OpenItem(Index: Integer);
var
  Item: TShellListItem;
  Book: TBookRef;
  Chapter: TChapterRef;
  BibleChapter: TBibleChapterRef;
begin
  if (Index < 0) or (Index > High(FItems)) then
    Exit;
  Item := FItems[Index];
  Book.ModuleId := Item.ModuleId;
  Book.BookCode := Item.BookCode;
  case Item.Kind of
    likModule:      FViewModel.ShowToc(Item.ModuleId);
    likTranslation: FViewModel.ShowShelf(Item.ModuleId);
    likBibleBook:   FViewModel.ShowToc(Book);
    likChapter:
      begin
        Chapter.ModuleId := Item.ModuleId;
        Chapter.ChapterOrder := Item.Number;
        FViewModel.OpenChapter(Chapter);
      end;
    likBibleChapter:
      begin
        BibleChapter.Book := Book;
        BibleChapter.ChapterNumber := Item.Number;
        FViewModel.OpenChapter(BibleChapter);
      end;
  end;
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

procedure TMainForm.lstItemsDblClick(Sender: TObject);
begin
  OpenItem(lstItems.ItemIndex);
end;

procedure TMainForm.lstItemsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = vkReturn then
  begin
    OpenItem(lstItems.ItemIndex);
    Key := 0;
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
