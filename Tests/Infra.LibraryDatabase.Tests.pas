unit Infra.LibraryDatabase.Tests;

{ TLibraryDatabase.Open / CheckStemTokenizer on a real file built by our
  sqlite3.dll (Slovo_03 Part C): valid library in a Cyrillic path, missing
  file, garbage file, file without Meta, newer SchemaVersion, read-only
  connection, stemmed tables usable. }

interface

uses
  DUnitX.TestFramework,
  Slovo.TestSupport;

type
  [TestFixture]
  TLibraryDatabaseTests = class
  private
    FDir: string;
    FLibrary: string;
    FLogger: TTestLogger;
    FLoggerRef: IInterface;
  public
    [SetupFixture]
    procedure SetupFixture;
    [TearDownFixture]
    procedure TearDownFixture;
    [Setup]
    procedure Setup;

    [Test] procedure Open_ValidLibrary_InCyrillicPath;
    [Test] procedure Open_ConnectionIsReadOnly;
    [Test] procedure Open_MissingFile_IsNotFound;
    [Test] procedure Open_GarbageFile_IsCorrupted;
    [Test] procedure Open_NoMetaTable_IsCorrupted;
    [Test] procedure Open_NewerSchema_IsUnsupported;
    [Test] procedure CheckStemTokenizer_WithOurDll_Succeeds;
    [Test] procedure Fixture_StemmedSearchFindsWordForms;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Core.Domain,
  Infrastructure.SQLite3.Database,
  Infra.SQLite.LibraryDatabase;

procedure TLibraryDatabaseTests.SetupFixture;
begin
  FDir := NewTempDir('Бібліотека Слово');
  FLibrary := BuildTestLibrary(TPath.Combine(FDir, 'library.db'));
end;

procedure TLibraryDatabaseTests.TearDownFixture;
begin
  try
    TDirectory.Delete(TPath.GetDirectoryName(FDir), True);
  except
    // A leftover temp folder is not a test failure.
  end;
end;

procedure TLibraryDatabaseTests.Setup;
begin
  FLogger := TTestLogger.Create;
  FLoggerRef := FLogger;          // keeps the reference-counted logger alive
end;

procedure TLibraryDatabaseTests.Open_ValidLibrary_InCyrillicPath;
var
  Db: TLibraryDatabase;
  Error: TResultError;
begin
  Db := TLibraryDatabase.Create(FLogger);
  try
    Assert.IsTrue(Db.Open(FLibrary, Error), 'Open failed');
    Assert.IsTrue(Error = reNone);
    Assert.IsNotNull(Db.Connection);
    Assert.AreEqual(0, FLogger.Count);
  finally
    Db.Free;
  end;
end;

procedure TLibraryDatabaseTests.Open_ConnectionIsReadOnly;
var
  Db: TLibraryDatabase;
  Error: TResultError;
begin
  Db := TLibraryDatabase.Create(FLogger);
  try
    Assert.IsTrue(Db.Open(FLibrary, Error));
    Assert.IsTrue(Db.Connection.IsReadOnly);
    Assert.WillRaise(
      procedure
      begin
        Db.Connection.Execute('DELETE FROM Modules;');
      end, ESQLiteError);
  finally
    Db.Free;
  end;
end;

procedure TLibraryDatabaseTests.Open_MissingFile_IsNotFound;
var
  Db: TLibraryDatabase;
  Error: TResultError;
begin
  Db := TLibraryDatabase.Create(FLogger);
  try
    Assert.IsFalse(Db.Open(TPath.Combine(FDir, 'absent.db'), Error));
    Assert.IsTrue(Error = reNotFound);
    Assert.IsNull(Db.Connection);
    Assert.IsTrue(FLogger.Contains('absent.db'));
  finally
    Db.Free;
  end;
end;

procedure TLibraryDatabaseTests.Open_GarbageFile_IsCorrupted;
var
  Db: TLibraryDatabase;
  Error: TResultError;
  FileName: string;
begin
  FileName := TPath.Combine(FDir, 'garbage.db');
  TFile.WriteAllText(FileName, StringOfChar('x', 4096));
  Db := TLibraryDatabase.Create(FLogger);
  try
    Assert.IsFalse(Db.Open(FileName, Error));
    Assert.IsTrue(Error = reModuleCorrupted);
    Assert.IsNull(Db.Connection);
  finally
    Db.Free;
  end;
end;

procedure TLibraryDatabaseTests.Open_NoMetaTable_IsCorrupted;
var
  Db: TLibraryDatabase;
  Error: TResultError;
  FileName: string;
begin
  FileName := BuildTestLibrary(TPath.Combine(FDir, 'nometa.db'));
  ExecOnLibrary(FileName, 'DROP TABLE Meta;');
  Db := TLibraryDatabase.Create(FLogger);
  try
    Assert.IsFalse(Db.Open(FileName, Error));
    Assert.IsTrue(Error = reModuleCorrupted);
  finally
    Db.Free;
  end;
end;

procedure TLibraryDatabaseTests.Open_NewerSchema_IsUnsupported;
var
  Db: TLibraryDatabase;
  Error: TResultError;
  FileName: string;
begin
  FileName := BuildTestLibrary(TPath.Combine(FDir, 'newer.db'));
  ExecOnLibrary(FileName, 'UPDATE Meta SET SchemaVersion = SchemaVersion + 1;');
  Db := TLibraryDatabase.Create(FLogger);
  try
    Assert.IsFalse(Db.Open(FileName, Error));
    Assert.IsTrue(Error = reUnsupportedSchema);
    Assert.IsTrue(FLogger.Contains('SchemaVersion 2'));
  finally
    Db.Free;
  end;
end;

procedure TLibraryDatabaseTests.CheckStemTokenizer_WithOurDll_Succeeds;
var
  Db: TLibraryDatabase;
  Error: TResultError;
begin
  Db := TLibraryDatabase.Create(FLogger);
  try
    Assert.IsTrue(Db.Open(FLibrary, Error));
    Assert.IsTrue(Db.CheckStemTokenizer, 'snowball tokenizer missing - wrong sqlite3.dll next to the EXE?');
  finally
    Db.Free;
  end;
end;

procedure TLibraryDatabaseTests.Fixture_StemmedSearchFindsWordForms;
var
  Db: TLibraryDatabase;
  Error: TResultError;
begin
  Db := TLibraryDatabase.Create(FLogger);
  try
    Assert.IsTrue(Db.Open(FLibrary, Error));
    // «жертва» -> «жертву», «Жертви» (Slovo_02, перевірка 2026-11-01)
    Assert.AreEqual(Int64(2), Db.Connection.QueryInt64(
      'SELECT count(*) FROM VersesStem_uk WHERE VersesStem_uk MATCH ''"жертва"'';'));
    // books: «жертву», «Жертва», «жертвою» in stemmed; only «Жертва» in exact
    Assert.AreEqual(Int64(3), Db.Connection.QueryInt64(
      'SELECT count(*) FROM ParagraphsStem_ru WHERE ParagraphsStem_ru MATCH ''"жертва"'';'));
    Assert.AreEqual(Int64(1), Db.Connection.QueryInt64(
      'SELECT count(*) FROM ParagraphsFTS WHERE ParagraphsFTS MATCH ''"жертва"'';'));
  finally
    Db.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLibraryDatabaseTests);

end.
