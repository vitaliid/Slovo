object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'Slovo'
  ClientHeight = 446
  ClientWidth = 624
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Menu = mmMain
  Position = poScreenCenter
  TextHeight = 15
  object mmMain: TMainMenu
    Left = 32
    Top = 32
    object miFile: TMenuItem
      Caption = '&'#1060#1072#1081#1083
      object miExit: TMenuItem
        Caption = '&'#1042#1080#1093#1110#1076
        OnClick = miExitClick
      end
    end
  end
end
