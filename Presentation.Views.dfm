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
  OnCreate = FormCreate
  TextHeight = 15
  object mmMain: TMainMenu
    Left = 32
    Top = 32
    object miFile: TMenuItem
      Caption = '&File'
      object miExit: TMenuItem
        Caption = 'E&xit'
        OnClick = miExitClick
      end
    end
    object miView: TMenuItem
      Caption = '&View'
      object miLanguage: TMenuItem
        Caption = '&Language'
        object miLanguageUkrainian: TMenuItem
          Tag = 0
          Caption = 'Ukrainian'
          GroupIndex = 1
          RadioItem = True
          OnClick = miLanguageItemClick
        end
        object miLanguageRussian: TMenuItem
          Tag = 1
          Caption = 'Russian'
          GroupIndex = 1
          RadioItem = True
          OnClick = miLanguageItemClick
        end
        object miLanguageEnglish: TMenuItem
          Tag = 2
          Caption = 'English'
          GroupIndex = 1
          RadioItem = True
          OnClick = miLanguageItemClick
        end
      end
    end
    object miHelp: TMenuItem
      Caption = '&Help'
      object miSQLiteDiagnostics: TMenuItem
        Caption = 'SQLite &diagnostics...'
        OnClick = miSQLiteDiagnosticsClick
      end
    end
  end
end
