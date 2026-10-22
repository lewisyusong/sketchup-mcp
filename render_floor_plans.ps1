param(
  [Parameter(Mandatory = $true)]
  [string]$EntitiesCsv,
  [string]$OutputDir = "."
)

Add-Type -AssemblyName System.Drawing

$entities = Import-Csv -LiteralPath $EntitiesCsv
$floors = @(
  [pscustomobject]@{
    Name = "01_First_Floor"
    MinX = 455000.0
    MaxX = 525000.0
    MinY = 346000.0
    MaxY = 372500.0
  },
  [pscustomobject]@{
    Name = "02_Second_Floor"
    MinX = 455000.0
    MaxX = 525000.0
    MinY = 276500.0
    MaxY = 303000.0
  },
  [pscustomobject]@{
    Name = "03_Floors_3_to_6"
    MinX = 455000.0
    MaxX = 525000.0
    MinY = 207000.0
    MaxY = 233500.0
  },
  [pscustomobject]@{
    Name = "04_Roof"
    MinX = 455000.0
    MaxX = 525000.0
    MinY = 147000.0
    MaxY = 168000.0
  }
)

$layerColors = @{
  "C-墙体" = [System.Drawing.Color]::FromArgb(20, 20, 20)
  "C-墙柱" = [System.Drawing.Color]::FromArgb(84, 84, 84)
  "C-门窗" = [System.Drawing.Color]::FromArgb(30, 94, 150)
  "C-楼电梯" = [System.Drawing.Color]::FromArgb(180, 118, 24)
  "C-轴网" = [System.Drawing.Color]::FromArgb(190, 190, 190)
  "C-结构看线" = [System.Drawing.Color]::FromArgb(94, 50, 140)
  "C-屋面线" = [System.Drawing.Color]::FromArgb(30, 130, 86)
  "C-排水-分水线" = [System.Drawing.Color]::FromArgb(60, 155, 175)
  "C-面积线" = [System.Drawing.Color]::FromArgb(210, 75, 75)
  "C-标注" = [System.Drawing.Color]::FromArgb(145, 145, 145)
  "J-门窗编号" = [System.Drawing.Color]::FromArgb(145, 145, 145)
  "J-文字" = [System.Drawing.Color]::FromArgb(65, 65, 65)
  "C-标高" = [System.Drawing.Color]::FromArgb(65, 65, 65)
}

function Add-Segment {
  param(
    [System.Collections.Generic.List[object]]$Segments,
    [double]$X1,
    [double]$Y1,
    [double]$X2,
    [double]$Y2,
    [string]$Layer
  )

  $Segments.Add([pscustomobject]@{
    X1 = $X1
    Y1 = $Y1
    X2 = $X2
    Y2 = $Y2
    Layer = $Layer
  })
}

foreach ($floor in $floors) {
  $segments = [System.Collections.Generic.List[object]]::new()

  foreach ($entity in $entities) {
    if ($entity.Type -eq "LINE" -and $entity.X -and $entity.Y -and $entity.X2 -and $entity.Y2) {
      Add-Segment $segments ([double]$entity.X) ([double]$entity.Y) ([double]$entity.X2) ([double]$entity.Y2) $entity.Layer
    } elseif ($entity.Type -eq "LWPOLYLINE" -and $entity.Points) {
      $points = @(
        $entity.Points.Split(";") |
          ForEach-Object {
            $parts = $_.Split(",")
            if ($parts.Count -eq 2) {
              [pscustomobject]@{ X = [double]$parts[0]; Y = [double]$parts[1] }
            }
          }
      )
      for ($i = 0; $i + 1 -lt $points.Count; $i++) {
        Add-Segment $segments $points[$i].X $points[$i].Y $points[$i + 1].X $points[$i + 1].Y $entity.Layer
      }
    }
  }

  $segments = @(
    $segments |
      Where-Object {
        [Math]::Min($_.X1, $_.X2) -ge $floor.MinX -and
        [Math]::Max($_.X1, $_.X2) -le $floor.MaxX -and
        [Math]::Min($_.Y1, $_.Y2) -ge $floor.MinY -and
        [Math]::Max($_.Y1, $_.Y2) -le $floor.MaxY
      } |
      Sort-Object {
        switch ($_.Layer) {
          "C-轴网" { 0 }
          "C-标注" { 1 }
          "C-结构看线" { 2 }
          "C-排水-分水线" { 3 }
          "C-面积线" { 4 }
          "C-墙柱" { 5 }
          "C-墙体" { 6 }
          "C-门窗" { 7 }
          "C-楼电梯" { 8 }
          default { 6 }
        }
      }
  )

  $pixelWidth = 3200
  $rangeX = $floor.MaxX - $floor.MinX
  $rangeY = $floor.MaxY - $floor.MinY
  $scale = $pixelWidth / $rangeX
  $margin = 45
  $bitmapWidth = [int][Math]::Round($rangeX * $scale) + 2 * $margin
  $bitmapHeight = [int][Math]::Round($rangeY * $scale) + 2 * $margin
  $bitmap = [System.Drawing.Bitmap]::new($bitmapWidth, $bitmapHeight)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.Clear([System.Drawing.Color]::White)
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

  foreach ($segment in $segments) {
    $color = if ($layerColors.ContainsKey($segment.Layer)) {
      $layerColors[$segment.Layer]
    } else {
      [System.Drawing.Color]::FromArgb(105, 105, 105)
    }
    $width = if ($segment.Layer -in @("C-墙体", "C-墙柱")) { 2.2 } else { 1.1 }
    $pen = [System.Drawing.Pen]::new($color, [single]$width)
    $x1 = $margin + ($segment.X1 - $floor.MinX) * $scale
    $x2 = $margin + ($segment.X2 - $floor.MinX) * $scale
    $y1 = $margin + ($floor.MaxY - $segment.Y1) * $scale
    $y2 = $margin + ($floor.MaxY - $segment.Y2) * $scale
    $graphics.DrawLine($pen, [single]$x1, [single]$y1, [single]$x2, [single]$y2)
    $pen.Dispose()
  }

  $outPath = Join-Path $OutputDir "$($floor.Name).png"
  $bitmap.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $graphics.Dispose()
  $bitmap.Dispose()
  Write-Output "$outPath ($($segments.Count) segments)"
}
