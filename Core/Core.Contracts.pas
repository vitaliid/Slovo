unit Core.Contracts;

{ Ports of the hexagon (Slovo_01 "Contracts", Slovo_04 C.2).
  Implementations live in Infrastructure; Core only declares them.
  Every interface has a GUID (A-08) so Supports()/as work for mocks. }

interface

uses
  System.Types,
  Core.Domain,
  Core.Catalog;

type
  // B-29: one port instead of a module registry plus per-module repositories.
  ILibrary = interface
    ['{CA78078A-183F-4827-AB54-78C72F217C95}']
    // Once, in phase 0 (C-22); the caller owns the result. Failure raises (A-07).
    function LoadCatalog: TLibraryCatalog;
    function GetChapterContent(const Ref: TChapterRef): TResult<TChapterContent>;
    function GetBibleChapter(const Ref: TBibleChapterRef): TResult<TBibleChapterContent>;
  end;

  // Synchronous (C-08, C-21). CountPrefix is deliberately absent until Sprint 3.
  ISearchIndex = interface
    ['{0B1B7C4E-6C2A-4D0E-9C1F-2A5D3E7B4A11}']
    function SearchBook(const Query: TSearchQuery): TResult<TSearchPage<TBookSearchResult>>;
    function SearchBible(const Query: TSearchQuery): TResult<TSearchPage<TBibleSearchResult>>;
    // E-08: same MATCH and table, limited to one chapter. Query.ModuleIds and
    // MaxResults are ignored - the module comes from Ref.
    function FindInChapter(const Query: TSearchQuery; const Ref: TChapterRef): TResult<TArray<TParagraphHit>>;
    function FindInBibleChapter(const Query: TSearchQuery; const Ref: TBibleChapterRef): TResult<TArray<TVerseHit>>;
  end;

  ILogger = interface
    ['{1D74C0A9-5B62-4E38-A7D1-0C9E4B83F605}']
    // C-18: must never raise, under any circumstances.
    procedure LogError(const Source, Msg: string);
  end;

  // E-06: user settings over data\settings.ini (format - Slovo_04 C.2).
  ISettings = interface
    ['{9B4F2E7A-6C1D-4E8B-A3F5-7D0C1B2A3E4F}']
    // [Ui]
    function GetLanguage: string;                 // 'uk' | 'ru' | 'en'; default 'uk'
    procedure SetLanguage(const Value: string);
    function GetZoomStep: Integer;                // E-11: -4..+6, 0 = 20.5 px; out of range -> clamp
    procedure SetZoomStep(Value: Integer);
    function GetLeftPanelVisible: Boolean;
    procedure SetLeftPanelVisible(Value: Boolean);
    function GetRightPanelVisible: Boolean;
    procedure SetRightPanelVisible(Value: Boolean);
    // [Window]
    function GetWindowBounds(out Bounds: TRect; out Maximized: Boolean): Boolean;   // False = not saved yet
    procedure SetWindowBounds(const Bounds: TRect; Maximized: Boolean);
    // [Reading] + [Positions] (E-07)
    function GetLastPosition(out Position: TReadingPosition): Boolean;
    procedure SetLastPosition(const Position: TReadingPosition);   // writes Last AND the [Positions] row
    function GetPosition(const ModuleId: TModuleId; out Position: TReadingPosition): Boolean;
    procedure SetPosition(const Position: TReadingPosition);
    // [Search] (B-27, B-28)
    function GetCheckedModules: TArray<TModuleId>;
    procedure SetCheckedModules(const Value: TArray<TModuleId>);
    function GetSearchWholeLibrary: Boolean;
    procedure SetSearchWholeLibrary(Value: Boolean);
    function GetExactPhrase: Boolean;
    procedure SetExactPhrase(Value: Boolean);
    function GetWordForms: Boolean;
    procedure SetWordForms(Value: Boolean);

    procedure Save;                               // never raises; read-only folder -> logged once (D-04)
  end;

implementation

end.
