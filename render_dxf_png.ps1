param(
  [Parameter(Mandatory = $true)]
  [string]$CsvPath,
  [Parameter(Mandatory = $true)]
  [string]$OutPath,
  [Parameter(Mandatory = $true)]
  [double]$MinX,
  [Parameter(Mandatory = $true)]
  [double]$MaxX,
  [Parameter(Mandatory = $true)]
  [double]$MinY,
  [Parameter(Mandatory = $true)]
  [double]$MaxY,
  [int]$PixelWidth = 4000,
  [double]$MarginRatio = 0.02
)

Add-Type -AssemblyName System.Drawing

$segments = Import-Csv -LiteralPath $CsvPath |
  ForEach-Object {
    [pscustomobject]@{
      X1 = [double]$_.X1
      Y1 = [double]$_.Y1
      X2 = [double]$_.X2
      Y2 = [double]$_.Y2
    }
  }

$rangeX = $MaxX - $MinX
$rangeY = $MaxY - $MinY
$scale = $PixelWidth / $rangeX
$contentWidth = [int][Math]::Round($rangeX * $scale)
$contentHeight = [int][Math]::Round($rangeY * $scale)
$marginX = [int][Math]::Round($PixelWidth * $MarginRatio)
$marginY = [int][Math]::Round([Math]::Max(16, $contentHeight * $MarginRatio))
$bitmapWidth = $contentWidth + 2 * $marginX
$bitmapHeight = $contentHeight + 2 * $marginY

$bitmap = [System.Drawing.Bitmap]::new($bitmapWidth, $bitmapHeight)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.Clear([System.Drawing.Color]::White)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(24, 24, 24), 1.5)

foreach ($s in $segments) {
  if (
    [Math]::Max($s.X1, $s.X2) -lt $MinX -or
    [Math]::Min($s.X1, $s.X2) -gt $MaxX -or
    [Math]::Max($s.Y1, $s.Y2) -lt $MinY -or
    [Math]::Min($s.Y1, $s.Y2) -gt $MaxY
  ) {
    continue
  }
  $x1 = $marginX + ($s.X1 - $MinX) * $scale
  $x2 = $marginX + ($s.X2 - $MinX) * $scale
  $y1 = $marginY + ($MaxY - $s.Y1) * $scale
  $y2 = $marginY + ($MaxY - $s.Y2) * $scale
  $graphics.DrawLine($pen, [single]$x1, [single]$y1, [single]$x2, [single]$y2)
}

$bitmap.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
$pen.Dispose()
$graphics.Dispose()
$bitmap.Dispose()

Write-Output "$OutPath ($bitmapWidth x $bitmapHeight)"
