unit Shell.MainForm;

{ TMainForm - the VCL shell (Slovo_04 Part D) implementing IMainView.

  At this step the form is a TEMPORARY smoke-test shell: the menu, a status line
  and a plain read-only text box that shows the shelf or the opened chapter, with
  Left/Right for the previous/next chapter. It exists to prove the composition
  root, the two-phase start and the ViewModel end to end on the real library.
  The real reading UI (VirtualTreeView, TRichEdit with RTF, search panel, banner)
  replaces the body in the next step; Bind/Unbind stay.

  No interface literal in the .dfm (E-05): every caption comes from
  ApplyLocalization. }

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Menus,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Core.Domain,
  Core.Contracts,
  Presentation.MainViewModel,
  Presentation.Theme,
  Presentation.Views;

type
  TMainForm = class(TForm, IMainView)
    mmMain: TMainMenu;
    miFile: TMenuItem;
    miExit: TMenuItem;
    miView: TMenuItem;
    miLanguage: TMenuItem;
    miLanguageUkrainian: TMenuItem;
    miLanguageRussian: TMenuItem;
    miLanguageEnglish: TMenuItem;
    miHelp: TMenuItem;
    miSQLiteDiagnostics: TMenuItem;
    pnlStatus: TPanel;
    lblStatus: TLabel;
    memText: TMemo;
    procedure miExitClick(Sender: TObject);
    procedure miLanguageItemClick(Sender: TObject);
    procedure miSQLiteDiagnosticsClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
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
    FNodeCount: Integer;

    procedure ApplyLocalization;
    procedure ShowShelf;
    procedure ShowChapter(const Args: TChapterLoadedArgs);
    procedure ShowBibleChapter(const Args: TBibleChapterLoadedArgs);
    procedure ShowError(Error: TResultError);
    procedure HandleException(Sender: TObject; E: Exception);
    procedure RestoreGeometry;
  public
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
  Vcl.Dialogs,
  Presentation.Localization,
  Infrastructure.SQLite3.Database;

{$R *.dfm}

function ErrorKey(Error: TResultError): string;
const
  Keys: array[TResultError] of string = (
    '', 'error.notFound', 'error.moduleCorrupted', 'error.ioFailure', 'error.invalidQuery',
    'error.unsupportedModule', 'error.unsupportedSchema', 'error.unexpected');
begin
  Result := Keys[Error];
end;

{ IMainView }

procedure TMainForm.Bind(ViewModel: TMainViewModel; const Settings: ISettings;
  const Theme: TReaderTheme);
begin
  FViewModel := ViewModel;
  FSettings := Settings;
  FTheme := Theme;

  FOnLibraryChanged := procedure(Nodes: TArray<TLibraryNode>) begin FNodeCount := Length(Nodes); end;
  FOnViewChanged := procedure(View: TReaderView) begin if View = rvShelf then ShowShelf; end;
  FOnChapterLoaded := procedure(Args: TChapterLoadedArgs) begin ShowChapter(Args); end;
  FOnBibleChapterLoaded := procedure(Args: TBibleChapterLoadedArgs) begin ShowBibleChapter(Args); end;
  FOnSearchCompleted := procedure(Reply: TSearchReply) begin end;
  FOnErrorOccurred := procedure(Error: TResultError) begin ShowError(Error); end;

  FViewModel.OnLibraryChanged.Add(FOnLibraryChanged);
  FViewModel.OnViewChanged.Add(FOnViewChanged);
  FViewModel.OnChapterLoaded.Add(FOnChapterLoaded);
  FViewModel.OnBibleChapterLoaded.Add(FOnBibleChapterLoaded);
  FViewModel.OnSearchCompleted.Add(FOnSearchCompleted);
  FViewModel.OnErrorOccurred.Add(FOnErrorOccurred);

  Application.OnException := HandleException;
  memText.Font.Name := FTheme.TextFont;
  Font.Name := FTheme.UiFont;
  ApplyLocalization;
  RestoreGeometry;

  FViewModel.Start;                      // phase 1: tree, position or Shelf (E-16)
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
  miLanguage.Caption := L('menu.view.language');
  miHelp.Caption := L('menu.help');
  miSQLiteDiagnostics.Caption := L('menu.help.sqliteDiagnostics');

  miLanguageUkrainian.Caption := LanguageName(UILanguageCodes[0]);
  miLanguageRussian.Caption := LanguageName(UILanguageCodes[1]);
  miLanguageEnglish.Caption := LanguageName(UILanguageCodes[2]);
  miLanguageUkrainian.Checked := Localizer.Language = UILanguageCodes[0];
  miLanguageRussian.Checked := Localizer.Language = UILanguageCodes[1];
  miLanguageEnglish.Checked := Localizer.Language = UILanguageCodes[2];

  lblStatus.Caption := L('library.title') + ': ' + IntToStr(Length(FViewModel.Catalog.Modules));
end;

{ temporary body }

procedure TMainForm.ShowShelf;
var
  M: TModule;
begin
  memText.Lines.BeginUpdate;
  try
    memText.Lines.Clear;
    memText.Lines.Add(L(CategoryKeys[FViewModel.ShelfCategory]));
    memText.Lines.Add('');
    for M in FViewModel.Catalog.Modules do
      if (M.Kind = ckBook) and (M.Category = FViewModel.ShelfCategory) then
        memText.Lines.Add(M.Title + '  ·  ' + L('library.chapters', [M.ChildCount]));
  finally
    memText.Lines.EndUpdate;
  end;
end;

procedure TMainForm.ShowChapter(const Args: TChapterLoadedArgs);
var
  P: TParagraphContent;
begin
  memText.Lines.BeginUpdate;
  try
    memText.Lines.Clear;
    memText.Lines.Add(FViewModel.ModuleTitle(Args.Content.Ref.ModuleId));
    memText.Lines.Add(L('read.chapter', [Args.Content.Ref.ChapterOrder]) + ' · ' + Args.Content.Title);
    memText.Lines.Add('');
    for P in Args.Content.Paragraphs do
    begin
      if (P.StartPageNumber > 0) and (P.ParagraphOnPage = 1) then
        memText.Lines.Add(Format('[%d] %s', [P.StartPageNumber, P.Text]))
      else
        memText.Lines.Add(P.Text);
      memText.Lines.Add('');
    end;
  finally
    memText.Lines.EndUpdate;
  end;
  memText.SelStart := 0;
end;

procedure TMainForm.ShowBibleChapter(const Args: TBibleChapterLoadedArgs);
var
  V: TVerseContent;
begin
  memText.Lines.BeginUpdate;
  try
    memText.Lines.Clear;
    memText.Lines.Add(FViewModel.ModuleTitle(Args.Content.Ref.Book.ModuleId));
    memText.Lines.Add(Format('%s %d', [Args.BookTitle, Args.Content.Ref.ChapterNumber]));
    memText.Lines.Add('');
    for V in Args.Content.Verses do
      memText.Lines.Add(Format('%d %s', [V.Ref.VerseNumber, V.Text]));
  finally
    memText.Lines.EndUpdate;
  end;
  memText.SelStart := 0;
end;

procedure TMainForm.ShowError(Error: TResultError);
begin
  lblStatus.Caption := L(ErrorKey(Error));
end;

procedure TMainForm.HandleException(Sender: TObject; E: Exception);
begin
  if FViewModel <> nil then
    FViewModel.ReportUnexpected(E.ClassName + ': ' + E.Message);
end;

{ events }

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FViewModel = nil then
    Exit;
  case Key of
    vkLeft:
      begin
        FViewModel.PreviousChapter;
        Key := 0;
      end;
    vkRight:
      begin
        FViewModel.NextChapter;
        Key := 0;
      end;
  end;
end;

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
  if FViewModel.View = rvShelf then
    ShowShelf;
end;

// The report is technical and stays English.
procedure TMainForm.miSQLiteDiagnosticsClick(Sender: TObject);
begin
  TaskMessageDlg(L('dialog.sqliteDiagnostics.title'), SQLiteSelfTest, mtInformation, [mbOK], 0);
end;

end.
