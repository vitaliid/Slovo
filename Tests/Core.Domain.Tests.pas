unit Core.Domain.Tests;

{ TResult<T> (A-06, R4-82) and TReadingPosition (E-07). }

interface

uses
  DUnitX.TestFramework,
  Core.Domain;

type
  [TestFixture]
  TDomainTests = class
  public
    [Test] procedure Result_Default_IsError;
    [Test] procedure Result_Success;
    [Test] procedure Result_Failure;
    [Test] procedure ReadingPosition_ModuleId_Book;
    [Test] procedure ReadingPosition_ModuleId_Bible;
  end;

implementation

procedure TDomainTests.Result_Default_IsError;
var
  R: TResult<Integer>;
begin
  // R4-82: a forgotten Outcome must never read as success.
  R := Default(TResult<Integer>);
  Assert.IsTrue(R.Outcome = roError);
  Assert.IsFalse(R.IsSuccess);
end;

procedure TDomainTests.Result_Success;
var
  R: TResult<string>;
begin
  R := TResult<string>.Success('жертва');
  Assert.IsTrue(R.IsSuccess);
  Assert.AreEqual('жертва', R.Value);
  Assert.IsTrue(R.Error = reNone);
end;

procedure TDomainTests.Result_Failure;
var
  R: TResult<Integer>;
begin
  R := TResult<Integer>.Failure(reNotFound);
  Assert.IsFalse(R.IsSuccess);
  Assert.IsTrue(R.Error = reNotFound);
end;

procedure TDomainTests.ReadingPosition_ModuleId_Book;
var
  P: TReadingPosition;
begin
  P := Default(TReadingPosition);
  P.Kind := ckBook;
  P.Chapter.ModuleId := 'PP';
  P.Chapter.ChapterOrder := 3;
  Assert.AreEqual('PP', string(P.ModuleId));
end;

procedure TDomainTests.ReadingPosition_ModuleId_Bible;
var
  P: TReadingPosition;
begin
  P := Default(TReadingPosition);
  P.Kind := ckBibleTranslation;
  P.Chapter.ModuleId := 'ignored';
  P.BibleChapter.Book.ModuleId := 'ohienko-uk';
  P.BibleChapter.Book.BookCode := 'GEN';
  P.BibleChapter.ChapterNumber := 3;
  Assert.AreEqual('ohienko-uk', string(P.ModuleId));
end;

initialization
  TDUnitX.RegisterTestFixture(TDomainTests);

end.
