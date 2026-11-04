object MainForm: TMainForm
  Left = 0
  Top = 0
  ClientHeight = 700
  ClientWidth = 1000
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  Menu = mmMain
  Position = poScreenCenter
  OnKeyDown = FormKeyDown
  TextHeight = 15
  object pnlStatus: TPanel
    Left = 0
    Top = 0
    Width = 1000
    Height = 28
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblStatus: TLabel
      AlignWithMargins = True
      Left = 8
      Top = 6
      Width = 984
      Height = 16
      Margins.Left = 8
      Margins.Top = 6
      Margins.Right = 8
      Align = alClient
    end
  end
  object memText: TMemo
    Left = 0
    Top = 28
    Width = 1000
    Height = 672
    Align = alClient
    BorderStyle = bsNone
    Font.Charset = DEFAULT_CHARSET
    Font.Color = 3092271
    Font.Height = -21
    Font.Name = 'Georgia'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 1
  end
  object mmMain: TMainMenu
    Left = 32
    Top = 64
    object miFile: TMenuItem
      object miExit: TMenuItem
        OnClick = miExitClick
      end
    end
    object miView: TMenuItem
      object miLanguage: TMenuItem
        object miLanguageUkrainian: TMenuItem
          GroupIndex = 1
          RadioItem = True
          OnClick = miLanguageItemClick
        end
        object miLanguageRussian: TMenuItem
          Tag = 1
          GroupIndex = 1
          RadioItem = True
          OnClick = miLanguageItemClick
        end
        object miLanguageEnglish: TMenuItem
          Tag = 2
          GroupIndex = 1
          RadioItem = True
          OnClick = miLanguageItemClick
        end
      end
    end
    object miHelp: TMenuItem
      object miSQLiteDiagnostics: TMenuItem
        OnClick = miSQLiteDiagnosticsClick
      end
    end
  end
end
