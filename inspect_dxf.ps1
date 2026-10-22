param(
  [Parameter(Mandatory = $true)]
  [string]$Path
)

$encoding = [System.Text.Encoding]::GetEncoding(936)
$stream = [System.IO.File]::Open(
  $Path,
  [System.IO.FileMode]::Open,
  [System.IO.FileAccess]::Read,
  [System.IO.FileShare]::ReadWrite
)
$reader = [System.IO.StreamReader]::new($stream, $encoding, $true)
$content = $reader.ReadToEnd()
$reader.Dispose()
$stream.Dispose()
$lines = $content -split "\r?\n"

$pairs = [System.Collections.Generic.List[object]]::new()
for ($i = 0; $i + 1 -lt $lines.Length; $i += 2) {
  $pairs.Add([pscustomobject]@{
    Code  = $lines[$i].Trim()
    Value = $lines[$i + 1]
  })
}

$sections = @{}
$currentSection = $null
$awaitingSectionName = $false
foreach ($pair in $pairs) {
  if ($pair.Code -eq '0' -and $pair.Value.Trim() -eq 'SECTION') {
    $currentSection = $null
    $awaitingSectionName = $true
    continue
  }
  if ($awaitingSectionName -and $pair.Code -eq '2') {
    $currentSection = $pair.Value.Trim()
    $sections[$currentSection] = [System.Collections.Generic.List[object]]::new()
    $awaitingSectionName = $false
    continue
  }
  if ($null -ne $currentSection) {
    if ($pair.Code -eq '0' -and $pair.Value.Trim() -eq 'ENDSEC') {
      $currentSection = $null
      $awaitingSectionName = $false
    } else {
      $sections[$currentSection].Add($pair)
    }
  }
}

Write-Output "FILE: $Path"
Write-Output "PAIRS: $($pairs.Count)"
Write-Output "SECTIONS: $((($sections.Keys | Sort-Object) -join ', '))"

$entities = $sections['ENTITIES']
$entityTypes = [ordered]@{}
$entityLayers = [ordered]@{}
$blocks = [System.Collections.Generic.List[string]]::new()
$texts = [System.Collections.Generic.List[object]]::new()
$currentType = $null
$currentLayer = $null
$currentText = $null
foreach ($pair in $entities) {
  if ($pair.Code -eq '0') {
    if ($null -ne $currentType) {
      $entityTypes[$currentType] = 1 + [int]($entityTypes[$currentType])
      if ($currentLayer) {
        $entityLayers[$currentLayer] = 1 + [int]($entityLayers[$currentLayer])
      }
      if ($currentType -in @('TEXT', 'MTEXT', 'ATTRIB') -and $currentText) {
        $texts.Add([pscustomobject]@{ Type = $currentType; Layer = $currentLayer; Text = $currentText })
      }
      if ($currentType -eq 'INSERT' -and $currentText) {
        $blocks.Add($currentText)
      }
    }
    $currentType = $pair.Value.Trim()
    $currentLayer = $null
    $currentText = $null
    continue
  }
  if ($pair.Code -eq '8') { $currentLayer = $pair.Value.Trim() }
  if ($currentType -eq 'INSERT' -and $pair.Code -eq '2') { $currentText = $pair.Value.Trim() }
  elseif ($currentType -in @('TEXT', 'MTEXT', 'ATTRIB') -and $pair.Code -in @('1', '3')) {
    $currentText = "$currentText$($pair.Value.Trim())"
  }
}

Write-Output "`nENTITIES BY TYPE"
$entityTypes.GetEnumerator() |
  Sort-Object -Property Value -Descending |
  ForEach-Object { "{0,6}  {1}" -f $_.Value, $_.Key }

Write-Output "`nENTITIES BY LAYER"
$entityLayers.GetEnumerator() |
  Sort-Object -Property Value -Descending |
  ForEach-Object { "{0,6}  {1}" -f $_.Value, $_.Key }

Write-Output "`nBLOCK INSERTS"
$blocks |
  Group-Object |
  Sort-Object -Property Count -Descending |
  Select-Object -First 40 |
  ForEach-Object { "{0,6}  {1}" -f $_.Count, $_.Name }

Write-Output "`nTEXT / MTEXT - FIRST 120"
$texts |
  Select-Object -First 120 |
  ForEach-Object { "[$($_.Layer)] $($_.Type): $($_.Text)" }
