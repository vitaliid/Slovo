object ErrorBannerFrame: TErrorBannerFrame
  Left = 0
  Top = 0
  Width = 640
  Height = 36
  TabOrder = 0
  object lblMessage: TLabel
    AlignWithMargins = True
    Left = 20
    Top = 0
    Width = 584
    Height = 36
    Margins.Left = 20
    Margins.Top = 0
    Margins.Right = 8
    Margins.Bottom = 0
    Align = alClient
    AutoSize = False
    EllipsisPosition = epEndEllipsis
    Layout = tlCenter
    ShowAccelChar = False
  end
  object tmrHide: TTimer
    Enabled = False
    Interval = 6000
    OnTimer = tmrHideTimer
    Left = 560
    Top = 4
  end
end
