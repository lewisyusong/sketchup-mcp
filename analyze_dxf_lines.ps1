param(
  [Parameter(Mandatory = $true)]
  [string]$Path,
  [string]$CsvOut = "",
  [string]$SvgOut = ""
)

$encoding = [System.Text.Encoding]::GetEncoding(936)
$stream = [System.IO.File]::Open(
  $Path,
  [System.IO.FileMode]::Open,
  [System.IO.FileAccess]::Read,
  [System.IO.FileShare]::ReadWrite
)
$reader = [System.IO.StreamReader]::new($stream, $encoding, $true)
$lines = ($reader.ReadToEnd() -split "\r?\n")
$reader.Dispose()
$stream.Dispose()

$section = $null
$awaitingSectionName = $false
$inEntities = $false
$current = $null
$segments = [System.Collections.Generic.List[object]]::new()

for ($i = 0; $i + 1 -lt $lines.Length; $i += 2) {
  $code = $lines[$i].Trim()
  $value = $lines[$i + 1].Trim()

  if ($code -eq '0' -and $value -eq 'SECTION') {
    $awaitingSectionName = $true
    continue
  }
  if ($awaitingSectionName -and $code -eq '2') {
    $section = $value
    $inEntities = $section -eq 'ENTITIES'
    $awaitingSectionName = $false
    continue
  }
  if ($code -eq '0' -and $value -eq 'ENDSEC') {
    $inEntities = $false
    continue
  }
  if (-not $inEntities) { continue }

  if ($code -eq '0') {
    if ($current -and $current.Type -eq 'LINE') {
      $segments.Add([pscustomobject]@{
        X1 = [double]$current.X1
        Y1 = [double]$current.Y1
        X2 = [double]$current.X2
        Y2 = [double]$current.Y2
      })
    }
    $current = [pscustomobject]@{
      Type = $value
      X1 = $null
      Y1 = $null
      X2 = $null
      Y2 = $null
    }
    continue
  }

  if (-not $current) { continue }
  switch ($code) {
    '10' { $current.X1 = $value }
    '20' { $current.Y1 = $value }
    '11' { $current.X2 = $value }
    '21' { $current.Y2 = $value }
  }
}
if ($current -and $current.Type -eq 'LINE') {
  $segments.Add([pscustomobject]@{
    X1 = [double]$current.X1
    Y1 = [double]$current.Y1
    X2 = [double]$current.X2
    Y2 = [double]$current.Y2
  })
}

$xs = $segments | ForEach-Object { $_.X1; $_.X2 }
$ys = $segments | ForEach-Object { $_.Y1; $_.Y2 }
$minX = ($xs | Measure-Object -Minimum).Minimum
$maxX = ($xs | Measure-Object -Maximum).Maximum
$minY = ($ys | Measure-Object -Minimum).Minimum
$maxY = ($ys | Measure-Object -Maximum).Maximum
$vertical = $segments | Where-Object { [Math]::Abs($_.X2 - $_.X1) -lt 0.001 }
$horizontal = $segments | Where-Object { [Math]::Abs($_.Y2 - $_.Y1) -lt 0.001 }

Write-Output "LINES: $($segments.Count)"
Write-Output "BOUNDS: ($minX, $minY) to ($maxX, $maxY)"
Write-Output "VERTICAL: $($vertical.Count); HORIZONTAL: $($horizontal.Count)"

Write-Output "`nX OCCUPANCY (10,000 UNIT BINS)"
$segments |
  ForEach-Object {
    $start = [Math]::Floor([Math]::Min($_.X1, $_.X2) / 10000) * 10000
    $end = [Math]::Floor([Math]::Max($_.X1, $_.X2) / 10000) * 10000
    for ($bin = $start; $bin -le $end; $bin += 10000) { $bin }
  } |
  Group-Object |
  Sort-Object { [double]$_.Name } |
  ForEach-Object { "{0,9}  {1,5} {2}" -f $_.Name, $_.Count, ('#' * [Math]::Min(80, [int]($_.Count / 20))) }

Write-Output "`nHORIZONTAL LINE Y HISTOGRAM (100 UNIT BINS, TOP 40)"
$horizontal |
  Group-Object { [Math]::Round($_.Y1 / 100) * 100 } |
  Sort-Object -Property Count -Descending |
  Select-Object -First 40 |
  ForEach-Object { "{0,9}  {1,5}" -f $_.Name, $_.Count }

Write-Output "`nVERTICAL LINE X HISTOGRAM (100 UNIT BINS, TOP 50)"
$vertical |
  Group-Object { [Math]::Round($_.X1 / 100) * 100 } |
  Sort-Object -Property Count -Descending |
  Select-Object -First 50 |
  ForEach-Object { "{0,9}  {1,5}" -f $_.Name, $_.Count }

if ($CsvOut) {
  $segments | Export-Csv -LiteralPath $CsvOut -NoTypeInformation -Encoding UTF8
  Write-Output "`nCSV: $CsvOut"
}

if ($SvgOut) {
  $margin = 1000
  $width = [Math]::Max(1, $maxX - $minX + 2 * $margin)
  $height = [Math]::Max(1, $maxY - $minY + 2 * $margin)
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.AppendLine("<svg xmlns='http://www.w3.org/2000/svg' viewBox='$($minX - $margin) $($minY - $margin) $width $height'>")
  [void]$sb.AppendLine("<path fill='none' stroke='#111' stroke-width='20' stroke-linecap='round' stroke-linejoin='round' d='")
  foreach ($s in $segments) {
    [void]$sb.AppendLine("M$($s.X1),$($s.Y1) L$($s.X2),$($s.Y2)")
  }
  [void]$sb.AppendLine("'/>")
  [void]$sb.AppendLine("</svg>")
  [System.IO.File]::WriteAllText($SvgOut, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
  Write-Output "SVG: $SvgOut"
}
