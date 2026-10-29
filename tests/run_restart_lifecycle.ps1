param(
    [string]$Godot = 'godot',
    [switch]$Headless
)

# Native Godot can exit successfully after reporting an engine error. Check both.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$mode = if ($Headless) { 'headless' } else { 'render' }
$validation = Join-Path $projectRoot '.validation'
New-Item -ItemType Directory -Force -Path $validation | Out-Null
$log = Join-Path $validation "restart_lifecycle_$mode.log"
$originalAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $validation "restart_${mode}_appdata"
    $arguments = @('--path', $projectRoot, '--fixed-fps', '30', '--script',
        'res://tests/restart_lifecycle_smoke.gd', '--quit-after', '3600')
    if ($Headless) { $arguments += '--headless' }
    else { $arguments += @('--', '--render') }
    $ErrorActionPreference = 'Continue'
    & $Godot @arguments *> $log
    $result = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $lines = Get-Content -LiteralPath $log
    # This machine's certificate-store warning is unrelated to the scene lifecycle.
    $errors = @($lines | Where-Object {
        $_ -match '^ERROR:|SCRIPT ERROR:|: ERROR:|FAIL:' -and
        $_ -notmatch 'Failed to read the root certificate store'
    })
    $summary = @($lines | Where-Object { $_ -match '^RESTART LIFECYCLE:' })
    if ($result -ne 0 -or $errors.Count -gt 0 -or $summary.Count -ne 1) {
        $errors | ForEach-Object { Write-Output $_ }
        throw "Restart lifecycle failed (exit $result, $($errors.Count) errors). See $log"
    }
    $summary
    Write-Output "No lifecycle/script or unexpected engine errors. Log: $log"
}
finally {
    $env:APPDATA = $originalAppData
}
