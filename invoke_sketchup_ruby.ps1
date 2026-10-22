param(
  [Parameter(Mandatory = $true)]
  [string]$RubyFile,
  [int]$TimeoutSeconds = 300
)

if (-not (Test-Path -LiteralPath $RubyFile)) {
  throw "Ruby file not found: $RubyFile"
}

$code = Get-Content -LiteralPath $RubyFile -Raw -Encoding UTF8
$client = [System.Net.Sockets.TcpClient]::new()

try {
  $client.Connect("127.0.0.1", 9876)
  $stream = $client.GetStream()
  $stream.ReadTimeout = $TimeoutSeconds * 1000

  $writer = [System.IO.StreamWriter]::new(
    $stream,
    [System.Text.UTF8Encoding]::new($false)
  )
  $writer.NewLine = "`n"
  $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)

  $request = @{
    jsonrpc = "2.0"
    method = "tools/call"
    params = @{
      name = "eval_ruby"
      arguments = @{
        code = $code
      }
    }
    id = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  } | ConvertTo-Json -Depth 8 -Compress

  $writer.WriteLine($request)
  $writer.Flush()
  $response = $reader.ReadLine()

  if (-not $response) {
    throw "SketchUp returned an empty response."
  }

  $parsed = $response | ConvertFrom-Json
  if ($parsed.error) {
    throw ($parsed.error | ConvertTo-Json -Depth 8 -Compress)
  }

  $text = $parsed.result.content[0].text
  $rubyResult = $text | ConvertFrom-Json -ErrorAction SilentlyContinue
  if ($rubyResult -and $rubyResult.success -eq $false) {
    throw ($rubyResult | ConvertTo-Json -Depth 8)
  }

  Write-Output $text
} finally {
  if ($reader) { $reader.Dispose() }
  if ($writer) { $writer.Dispose() }
  $client.Close()
}
