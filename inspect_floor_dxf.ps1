param(
  [Parameter(Mandatory = $true)]
  [string]$Path,
  [string]$EntitiesCsv = "",
  [string]$TextCsv = ""
)

$stream = [System.IO.File]::Open(
  $Path,
  [System.IO.FileMode]::Open,
  [System.IO.FileAccess]::Read,
  [System.IO.FileShare]::ReadWrite
)
$reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
$lines = $reader.ReadToEnd().Split("`r`n")
$reader.Dispose()
$stream.Dispose()

$inEntities = $false
$awaitingSectionName = $false
$current = $null
$entities = [System.Collections.Generic.List[object]]::new()
$texts = [System.Collections.Generic.List[object]]::new()

function Complete-Entity {
  if ($null -eq $script:current) {
    return
  }

  $entity = $script:current
  $pointText = ""
  if ($entity.Type -eq "LWPOLYLINE") {
    $pointText = ($entity.Points |
      ForEach-Object {
        if ($null -ne $_.X -and $null -ne $_.Y) {
          "{0:R},{1:R}" -f [double]$_.X, [double]$_.Y
        }
      }) -join ";"
  }

  if ($entity.Type -in @("LINE", "LWPOLYLINE", "TEXT", "MTEXT", "ATTRIB", "INSERT", "HATCH", "DIMENSION", "CIRCLE")) {
    $script:entities.Add([pscustomobject]@{
      Type = $entity.Type
      Handle = $entity.Handle
      Layer = $entity.Layer
      Block = $entity.Block
      Text = $entity.Text
      X = $entity.X
      Y = $entity.Y
      X2 = $entity.X2
      Y2 = $entity.Y2
      Points = $pointText
    })
  }

  if ($entity.Type -in @("TEXT", "MTEXT", "ATTRIB") -and $entity.Text) {
    $script:texts.Add([pscustomobject]@{
      Type = $entity.Type
      Layer = $entity.Layer
      Text = $entity.Text
      X = $(if ($null -eq $entity.X) { $null } else { [double]$entity.X })
      Y = $(if ($null -eq $entity.Y) { $null } else { [double]$entity.Y })
    })
  }
}

for ($i = 0; $i + 1 -lt $lines.Length; $i += 2) {
  $code = $lines[$i].Trim()
  $value = $lines[$i + 1].Trim()

  if ($code -eq "0" -and $value -eq "SECTION") {
    $awaitingSectionName = $true
    continue
  }
  if ($awaitingSectionName -and $code -eq "2") {
    $inEntities = $value -eq "ENTITIES"
    $awaitingSectionName = $false
    continue
  }
  if ($code -eq "0" -and $value -eq "ENDSEC") {
    $inEntities = $false
    continue
  }
  if (-not $inEntities) {
    continue
  }

  if ($code -eq "0") {
    Complete-Entity
    $current = [pscustomobject]@{
      Type = $value
      Handle = ""
      Layer = ""
      Block = ""
      Text = ""
      X = $null
      Y = $null
      X2 = $null
      Y2 = $null
      Points = [System.Collections.Generic.List[object]]::new()
    }
    continue
  }
  if ($null -eq $current) {
    continue
  }

  switch ($code) {
    "5" { $current.Handle = $value }
    "8" { $current.Layer = $value }
    "1" { $current.Text += $value }
    "3" { $current.Text += $value }
    "2" {
      if ($current.Type -eq "INSERT") {
        $current.Block = $value
      }
    }
    "10" {
      if ($current.Type -eq "LWPOLYLINE") {
        $current.Points.Add([pscustomobject]@{ X = [double]$value; Y = $null })
      } else {
        $current.X = $value
      }
    }
    "20" {
      if ($current.Type -eq "LWPOLYLINE" -and $current.Points.Count -gt 0) {
        $current.Points[$current.Points.Count - 1].Y = [double]$value
      } else {
        $current.Y = $value
      }
    }
    "11" { $current.X2 = $value }
    "21" { $current.Y2 = $value }
  }
}
Complete-Entity

Write-Output "ENTITIES: $($entities.Count)"
Write-Output "TEXT: $($texts.Count)"

Write-Output "`nENTITY TYPES"
$entities |
  Group-Object Type |
  Sort-Object Count -Descending |
  Select-Object Count, Name |
  Format-Table -AutoSize

Write-Output "`nLAYERS"
$entities |
  Group-Object Layer |
  Sort-Object Count -Descending |
  Select-Object Count, Name |
  Format-Table -AutoSize

Write-Output "`nPLAN TITLES"
$texts |
  Where-Object { $_.Text -match "平面图|屋面层" } |
  Select-Object Type, Layer, Text, X, Y |
  Format-Table -AutoSize

Write-Output "`nINSERT BLOCKS"
$entities |
  Where-Object { $_.Type -eq "INSERT" } |
  Group-Object Block |
  Sort-Object Count -Descending |
  Select-Object Count, Name |
  Format-Table -AutoSize

if ($EntitiesCsv) {
  $entities |
    Export-Csv -LiteralPath $EntitiesCsv -NoTypeInformation -Encoding UTF8
  Write-Output "ENTITIES CSV: $EntitiesCsv"
}

if ($TextCsv) {
  $texts |
    Export-Csv -LiteralPath $TextCsv -NoTypeInformation -Encoding UTF8
  Write-Output "TEXT CSV: $TextCsv"
}
