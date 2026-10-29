param(
    [string]$Godot = 'godot',
    [int[]]$FrameRates = @(30, 120, 180),
    [switch]$Render
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$validation = Join-Path $projectRoot '.validation'
New-Item -ItemType Directory -Force -Path $validation | Out-Null
$originalAppData = $env:APPDATA
try {
    $mode = if ($Render) { 'render' } else { 'headless' }
    foreach ($rate in $FrameRates) {
        if ($rate -le 0) { throw 'FrameRates must contain positive rates.' }
        $env:APPDATA = Join-Path $validation "pickup_${mode}_${rate}_appdata"
        $log = Join-Path $validation "pickup_targeting_${mode}_${rate}.log"
        $arguments = @('--path', $projectRoot, '--fixed-fps', $rate, '--script',
            'res://tests/pickup_targeting_smoke.gd', '--quit-after', ($rate * 120))
        if (!$Render) { $arguments += '--headless' }
        $arguments += @('--', "--output=${mode}_${rate}")
        if ($Render) { $arguments += '--render' }
        $ErrorActionPreference = 'Continue'
        & $Godot @arguments *> $log
        $result = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        $lines = Get-Content -LiteralPath $log
        $issues = @($lines | Where-Object {
            $_ -match '^ERROR:|SCRIPT ERROR:|: ERROR:|FAIL:' -and
            $_ -notmatch 'Failed to read the root certificate store'
        })
        $summary = @($lines | Where-Object { $_ -match '^PICKUP TARGETING: \d+ checks, 0 failure\(s\)$' })
        if ($result -ne 0 -or $issues.Count -gt 0 -or $summary.Count -ne 1) {
            $issues | ForEach-Object { Write-Output $_ }
            throw "Pickup targeting failed at $rate (exit $result). See $log"
        }
        Write-Output "$mode $rate FPS clock: $summary; no unexpected engine errors"
    }
}
finally {
    $env:APPDATA = $originalAppData
}
