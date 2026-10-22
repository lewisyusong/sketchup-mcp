param(
  [Parameter(Mandatory = $true)]
  [string]$CsvPath,
  [double]$Tolerance = 0.05,
  [string]$CsvOut = ""
)

$segments = @(Import-Csv -LiteralPath $CsvPath)
$parent = [int[]]::new($segments.Count)
for ($i = 0; $i -lt $parent.Length; $i++) { $parent[$i] = $i }

function Find-Root([int]$index) {
  $root = $index
  while ($script:parent[$root] -ne $root) { $root = $script:parent[$root] }
  while ($script:parent[$index] -ne $index) {
    $next = $script:parent[$index]
    $script:parent[$index] = $root
    $index = $next
  }
  return $root
}

function Join-Segments([int]$a, [int]$b) {
  $ra = Find-Root $a
  $rb = Find-Root $b
  if ($ra -ne $rb) { $script:parent[$rb] = $ra }
}

$horizontal = [System.Collections.Generic.List[object]]::new()
$vertical = [System.Collections.Generic.List[object]]::new()
for ($i = 0; $i -lt $segments.Count; $i++) {
  $s = $segments[$i]
  $x1 = [double]$s.X1
  $x2 = [double]$s.X2
  $y1 = [double]$s.Y1
  $y2 = [double]$s.Y2
  $entry = [pscustomobject]@{
    Index = $i
    X1 = [Math]::Min($x1, $x2)
    X2 = [Math]::Max($x1, $x2)
    Y1 = [Math]::Min($y1, $y2)
    Y2 = [Math]::Max($y1, $y2)
  }
  if ([Math]::Abs($y2 - $y1) -lt 0.01) {
    $horizontal.Add($entry)
  } elseif ([Math]::Abs($x2 - $x1) -lt 0.01) {
    $vertical.Add($entry)
  }
}

foreach ($h in $horizontal) {
  foreach ($v in $vertical) {
    if (
      $v.X1 -ge $h.X1 - $Tolerance -and
      $v.X1 -le $h.X2 + $Tolerance -and
      $h.Y1 -ge $v.Y1 - $Tolerance -and
      $h.Y1 -le $v.Y2 + $Tolerance
    ) {
      Join-Segments $h.Index $v.Index
    }
  }
}

$components = @{}
for ($i = 0; $i -lt $segments.Count; $i++) {
  $root = Find-Root $i
  if (-not $components.ContainsKey($root)) {
    $components[$root] = [System.Collections.Generic.List[object]]::new()
  }
  $components[$root].Add($segments[$i])
}

$result = foreach ($component in $components.Values) {
  if ($component.Count -lt 4) { continue }
  $xs = $component | ForEach-Object { [double]$_.X1; [double]$_.X2 }
  $ys = $component | ForEach-Object { [double]$_.Y1; [double]$_.Y2 }
  $minX = ($xs | Measure-Object -Minimum).Minimum
  $maxX = ($xs | Measure-Object -Maximum).Maximum
  $minY = ($ys | Measure-Object -Minimum).Minimum
  $maxY = ($ys | Measure-Object -Maximum).Maximum
  $width = $maxX - $minX
  $height = $maxY - $minY
  $ratio = if ($height -gt 0) { $width / $height } else { 0 }
  [pscustomobject]@{
    Count = $component.Count
    MinX = [Math]::Round($minX, 2)
    MaxX = [Math]::Round($maxX, 2)
    MinY = [Math]::Round($minY, 2)
    MaxY = [Math]::Round($maxY, 2)
    Width = [Math]::Round($width, 2)
    Height = [Math]::Round($height, 2)
    Ratio = [Math]::Round($ratio, 3)
  }
}

Write-Output "COMPONENTS: $($result.Count)"
Write-Output "COMPONENTS >= 4 LINES: $(@($result | Where-Object Count -ge 4).Count)"
Write-Output "WINDOW-LIKE: $(@($result | Where-Object { $_.Count -ge 4 -and $_.Width -ge 400 -and $_.Width -le 8000 -and $_.Height -ge 400 -and $_.Height -le 5000 }).Count)"

if ($CsvOut) {
  $result | Export-Csv -LiteralPath $CsvOut -NoTypeInformation -Encoding UTF8
  Write-Output "CSV: $CsvOut"
}

$result |
  Sort-Object Count -Descending |
  Select-Object -First 120 |
  Format-Table -AutoSize
