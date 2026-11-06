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
  Position = poScreenCenter
  OnCreate = FormCreate
  OnKeyDown = FormKeyDown
  TextHeight = 15
  object pnlCenter: TPanel
    Left = 0
    Top = 0
    Width = 1200
    Height = 760
    Align = alClient
    BevelOuter = bvNone
    ParentBackground = False
    TabOrder = 0
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
        TabOrder = 1
      end
      object redReader: TRichEdit
        Left = 0
        Top = 106
        Width = 724
        Height = 582
        Align = alClient
        BorderStyle = bsNone
        Font.Charset = RUSSIAN_CHARSET
        Font.Color = clWindowText
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        HideSelection = False
        ParentFont = False
        ReadOnly = True
        ScrollBars = ssVertical
        TabOrder = 0
        WantReturns = False
        ExplicitTop = 109
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
      end
    end
  end
  object pmMain: TPopupMenu
    Left = 32
    Top = 64
    object miZoomReset: TMenuItem
      Action = actZoomReset
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
    object miViewSeparator: TMenuItem
    end
    object miSQLiteDiagnostics: TMenuItem
      OnClick = miSQLiteDiagnosticsClick
    end
    object miHelpSeparator: TMenuItem
    end
    object miExit: TMenuItem
      OnClick = miExitClick
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
