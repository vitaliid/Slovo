unit Presentation.Views;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.Menus;

type
  TMainForm = class(TForm)
    mmMain: TMainMenu;
    miFile: TMenuItem;
    miExit: TMenuItem;
    procedure miExitClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

procedure TMainForm.miExitClick(Sender: TObject);
begin
  Close;
end;

end.
