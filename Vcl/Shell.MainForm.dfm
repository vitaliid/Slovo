object MainForm: TMainForm
  Left = 0
  Top = 0
  ClientHeight = 760
  ClientWidth = 1200
  Color = clBtnFace
  Constraints.MinHeight = 600
  Constraints.MinWidth = 900
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  Menu = mmMain
  Position = poScreenCenter
  OnCreate = FormCreate
  OnKeyDown = FormKeyDown
  TextHeight = 15
  object pnlStatus: TPanel
    Left = 0
    Top = 0
    Width = 1200
    Height = 28
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblStatus: TLabel
      AlignWithMargins = True
      Left = 8
      Top = 6
      Width = 1184
      Height = 19
      Margins.Left = 8
      Margins.Top = 6
      Margins.Right = 8
      Align = alClient
    end
  end
  object pnlCenter: TPanel
    Left = 0
    Top = 28
    Width = 1200
    Height = 732
    Align = alClient
    BevelOuter = bvNone
    ParentBackground = False
    TabOrder = 1
    OnResize = pnlCenterResize
    object pnlColumn: TPanel
      Left = 238
      Top = 0
      Width = 724
      Height = 732
      BevelOuter = bvNone
      ParentBackground = False
      TabOrder = 0
      object pnlCrumbs: TPanel
        AlignWithMargins = True
        Left = 0
        Top = 44
        Width = 724
        Height = 18
        Margins.Left = 0
        Margins.Top = 44
        Margins.Right = 0
        Margins.Bottom = 44
        Align = alTop
        BevelOuter = bvNone
        ParentBackground = False
        TabOrder = 3
      end
      object redReader: TRichEdit
        Left = 0
        Top = 47
        Width = 724
        Height = 641
        Align = alClient
        BorderStyle = bsNone
        HideSelection = False
        ReadOnly = True
        ScrollBars = ssVertical
        TabOrder = 0
        WantReturns = False
      end
      object pnlChapterNav: TPanel
        Left = 0
        Top = 688
        Width = 724
        Height = 44
        Align = alBottom
        BevelOuter = bvNone
        ParentBackground = False
        TabOrder = 2
        object btnPrevChapter: TButton
          AlignWithMargins = True
          Left = 0
          Top = 8
          Width = 200
          Height = 28
          Margins.Left = 0
          Margins.Top = 8
          Margins.Bottom = 8
          Action = actPrevChapter
          Align = alLeft
          TabOrder = 0
          TabStop = False
        end
        object btnNextChapter: TButton
          AlignWithMargins = True
          Left = 524
          Top = 8
          Width = 200
          Height = 28
          Margins.Top = 8
          Margins.Right = 0
          Margins.Bottom = 8
          Action = actNextChapter
          Align = alRight
          TabOrder = 1
          TabStop = False
        end
      end
    end
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
      object miZoomIn: TMenuItem
        Action = actZoomIn
      end
      object miZoomOut: TMenuItem
        Action = actZoomOut
      end
      object miZoomReset: TMenuItem
        Action = actZoomReset
      end
      object miViewSeparator: TMenuItem
      end
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
  object alMain: TActionList
    OnUpdate = alMainUpdate
    Left = 104
    Top = 64
    object actZoomIn: TAction
      OnExecute = actZoomInExecute
    end
    object actZoomOut: TAction
      OnExecute = actZoomOutExecute
    end
    object actZoomReset: TAction
      OnExecute = actZoomResetExecute
    end
    object actPrevChapter: TAction
      OnExecute = actPrevChapterExecute
    end
    object actNextChapter: TAction
      OnExecute = actNextChapterExecute
    end
  end
end
