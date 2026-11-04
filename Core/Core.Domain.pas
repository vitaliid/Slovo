unit Core.Domain;

{ Domain model of Slovo (Slovo_01, "Domain-models").
  Pure data: no VCL, no SQLite, no I/O. Two content models are kept apart on
  purpose (B-01): books are addressed by chapter + paragraph, Bible translations
  by book + chapter + verse.

  Rule for every enum that the library.db format stores as INTEGER
  (TContentKind, TBookCategory, TParagraphKind, TInlineSpanKind): new values are
  appended at the END only (B-16). }

interface

type
  // ---------------------------------------------------------------- common

  // Module = a book or a Bible translation, i.e. one row of the Modules table
  // (B-29). Globally unique and never renamed (B-30). Format: no '=', ',', ':';
  // does not start with ';' or '[' - it is a key in settings.ini.
  TModuleId = type string;

  TContentKind = (
    ckBook,               // any book: Spirit of Prophecy, history, spiritual life, prophecy study
    ckBibleTranslation
  );

  // Only groups the library tree in the UI; has no effect on structure.
  TBookCategory = (
    bcSpiritOfProphecy,
    bcHistory,
    bcSpiritualLife,
    bcProphecyStudy,
    bcDailyReadings       // "Утренние чтения" - outside the MVP, placeholder only
  );

  TModule = record
    Id: TModuleId;
    Kind: TContentKind;
    Category: TBookCategory;          // meaningful for ckBook only
    Language: string;                 // ISO 639-1; also selects the stemmed search table (B-31)
    Title: string;
    Author: string;                   // '' for Bible translations

    // Series (B-25): series nodes by SeriesOrder, modules inside by SortOrder;
    // modules outside a series follow by Title. Sorting itself is the ViewModel's job.
    Series: string;                   // '' = not in a series
    SeriesTitle: string;              // in the language of the book, not a localization key
    SeriesOrder: Integer;
    SortOrder: Integer;

    // E-09: children in the tree - chapters of a book, books of a translation.
    // Not stored in the database; TLibraryCatalog fills it in.
    ChildCount: Integer;
  end;

  // ---------------------------------------------------------------- books

  // An address and only an address (B-20).
  TChapterRef = record
    ModuleId: TModuleId;
    ChapterOrder: Integer;            // 1..N within the module
  end;

  // What the library tree needs: address + title (TLibraryCatalog.Chapters).
  TChapterInfo = record
    Ref: TChapterRef;
    Title: string;
  end;

  TParagraphKind = (
    pkChapterTitle,
    pkSubChapterTitle,
    pkEpigraph,
    pkSectionHeading,
    pkSourceCitation,
    pkPageMarker,                     // technical; never stored in Paragraphs (CHECK Kind <> 5)
    pkText
  );

  TParagraphRef = record
    Chapter: TChapterRef;
    LogicalIndex: Integer;            // number of the LOGICAL (not HTML) paragraph in the chapter
  end;

  // Inline formatting range (B-18): written by the importer, not rendered in the MVP.
  TInlineSpanKind = (iskBold, iskItalic);

  TInlineSpan = record
    StartOffset: Integer;             // UTF-16 code units, 0-based (B-24)
    Len: Integer;
    Kind: TInlineSpanKind;
  end;

  TParagraphContent = record
    Ref: TParagraphRef;
    Kind: TParagraphKind;
    Text: string;                     // plain text, no inline markup
    StartPageNumber: Integer;         // original page where the paragraph starts; 0 = no page system
    PageBreakOffset: Integer;         // B-17: where the next page marker stood; -1 = none
    ParagraphOnPage: Integer;         // B-17: second half of a reference like GC 595.2
    InlineSpans: TArray<TInlineSpan>;
  end;

  TChapterContent = record
    Ref: TChapterRef;
    Title: string;
    Paragraphs: TArray<TParagraphContent>;   // ordered by LogicalIndex
  end;

  // ---------------------------------------------------------------- Bible

  TBookCode = type string;            // OSIS/USFM: 'GEN', 'MAT'... (B-14)

  // An address and only an address (B-20).
  TBookRef = record
    ModuleId: TModuleId;
    BookCode: TBookCode;
  end;

  // What the tree and navigation need (TLibraryCatalog.Books).
  TBookInfo = record
    Ref: TBookRef;
    OrderInModule: Integer;
    DisplayTitle: string;
    ChapterCount: Integer;            // B-22: chapters 1..ChapterCount in THIS translation
  end;

  TBibleChapterRef = record
    Book: TBookRef;
    ChapterNumber: Integer;           // 1..TBookInfo.ChapterCount
  end;

  TVerseRef = record
    Chapter: TBibleChapterRef;
    VerseNumber: Integer;
  end;

  TVerseContent = record
    Ref: TVerseRef;
    Text: string;
  end;

  TBibleChapterContent = record
    Ref: TBibleChapterRef;
    Verses: TArray<TVerseContent>;    // ordered by VerseNumber
  end;

  // ---------------------------------------------------------------- reading position

  // E-07. The module id lives in Chapter or BibleChapter.Book depending on Kind.
  TReadingPosition = record
    Kind: TContentKind;
    Chapter: TChapterRef;             // ckBook
    BibleChapter: TBibleChapterRef;   // ckBibleTranslation
    function ModuleId: TModuleId;
  end;

  // ---------------------------------------------------------------- result

  TResultError = (
    reNone,
    reNotFound,
    reModuleCorrupted,
    reIOFailure,
    reInvalidQuery,                   // FTS5 syntax that got past sanitizing
    reUnsupportedModule,
    reUnsupportedSchema,              // phase 0 only (C-22)
    reUnexpected                      // Application.OnException
  );

  // roError FIRST (R4-82): a zero-initialized record reads as an error, never as
  // a silent success. Not stored in the database, so the order is free to choose.
  TResultOutcome = (roError, roSuccess);

  // Used for single-value methods and for Search*/Find* (A-06).
  TResult<T> = record
    Outcome: TResultOutcome;
    Value: T;                         // valid only for roSuccess
    Error: TResultError;              // valid only for roError
    class function Success(const AValue: T): TResult<T>; static;
    class function Failure(AError: TResultError): TResult<T>; static;
    function IsSuccess: Boolean; inline;
  end;

  // ---------------------------------------------------------------- search

  TSearchQuery = record
    ModuleIds: TArray<TModuleId>;     // B-27: empty = the whole library
    Text: string;                     // raw user text; sanitizing is Infrastructure's job
    ExactPhrase: Boolean;
    WordForms: Boolean;               // B-28/B-31: stemmed tables instead of exact ones
    MaxResults: Integer;              // B-19: <= 0 means DefaultMaxResults
  end;

  TSearchHighlight = record
    StartOffset: Integer;             // in Snippet or Text; UTF-16 code units, 0-based (B-24)
    Len: Integer;
  end;

  TBookSearchResult = record
    Ref: TParagraphRef;
    PageNumber: Integer;              // B-23: StartPageNumber of the paragraph; 0 = no page system
    ParagraphOnPage: Integer;
    Snippet: string;
    Highlights: TArray<TSearchHighlight>;
  end;

  TBibleSearchResult = record
    Ref: TVerseRef;
    Snippet: string;
    Highlights: TArray<TSearchHighlight>;
  end;

  // Items: by relevance within a language group; groups follow one another (B-31).
  // Truncated: at least one group was cut by LIMIT MaxResults + 1.
  TSearchPage<T> = record
    Items: TArray<T>;
    Truncated: Boolean;
  end;

  // Matches inside one chapter (E-08), in chapter order.
  TParagraphHit = record
    LogicalIndex: Integer;
    Highlights: TArray<TSearchHighlight>;   // offsets in TParagraphContent.Text
  end;

  TVerseHit = record
    VerseNumber: Integer;
    Highlights: TArray<TSearchHighlight>;   // offsets in TVerseContent.Text
  end;

const
  DefaultMaxResults = 200;            // B-19

implementation

{ TReadingPosition }

function TReadingPosition.ModuleId: TModuleId;
begin
  if Kind = ckBibleTranslation then
    Result := BibleChapter.Book.ModuleId
  else
    Result := Chapter.ModuleId;
end;

{ TResult<T> }

class function TResult<T>.Success(const AValue: T): TResult<T>;
begin
  Result := Default(TResult<T>);
  Result.Outcome := roSuccess;
  Result.Value := AValue;
  Result.Error := reNone;
end;

class function TResult<T>.Failure(AError: TResultError): TResult<T>;
begin
  Result := Default(TResult<T>);
  Result.Outcome := roError;
  Result.Error := AError;
end;

function TResult<T>.IsSuccess: Boolean;
begin
  Result := Outcome = roSuccess;
end;

end.
