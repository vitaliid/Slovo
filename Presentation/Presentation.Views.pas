unit Presentation.Views;

{ IMainView - the only way the composition root touches the form (C-14).
  The form is created by the STANDARD Application.CreateForm in the .dpr;
  Bind connects it to the ViewModel afterwards (Slovo_04 C.1). }

interface

uses
  Core.Contracts,
  Presentation.MainViewModel,
  Presentation.Theme;

type
  IMainView = interface
    ['{5E2C8A1B-3F6D-4C0E-9A7B-1D2E3F4A5B6C}']
    // Subscribes to the ViewModel events, sets Application.OnException, applies the
    // localization, restores geometry, panels and zoom from Settings, and then calls
    // ViewModel.Start - the window appears on Application.Run already filled (E-16).
    procedure Bind(ViewModel: TMainViewModel; const Settings: ISettings; const Theme: TReaderTheme);
    // Unsubscribes and writes geometry and panels into Settings, then Settings.Save.
    procedure Unbind;
  end;

implementation

end.
