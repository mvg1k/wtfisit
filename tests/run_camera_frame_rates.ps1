param(
    [string]$Godot = 'godot',
    [switch]$Render,
    [switch]$RealTime
)

$ErrorActionPreference = 'Stop'
$taskProject = Split-Path -Parent $PSScriptRoot
$taskOutput = Join-Path $taskProject '.validation'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
$taskOriginalAppData = $env:APPDATA
try {
    $taskMode = if ($Render) { 'render' } else { 'headless' }
    if ($RealTime) { $taskMode = "live_$taskMode" }
    foreach ($taskRate in @(30, 60, 75, 120, 144, 180)) {
        $env:APPDATA = Join-Path $taskOutput "camera_matrix_${taskMode}_${taskRate}_appdata"
        $taskLog = Join-Path $taskOutput "camera_matrix_${taskMode}_${taskRate}.log"
        # FPS is a test parameter; the project has no display-specific limit.
        $taskClockFlag = if ($RealTime) { '--max-fps' } else { '--fixed-fps' }
        $taskArgs = @('--path', $taskProject, $taskClockFlag, $taskRate,
            '--script', 'res://tests/camera_smoothness_smoke.gd',
            '--quit-after', [int][Math]::Ceiling($taskRate * 60))
        if ($Render) {
            if (!$RealTime) { $taskArgs += @('--max-fps', $taskRate) }
        } else {
            $taskArgs += '--headless'
        }
        $taskArgs += @('--', "--output=${taskMode}_${taskRate}")
        if ($Render) { $taskArgs += '--render' }
        # Windows PowerShell treats native stderr as error records.
        $ErrorActionPreference = 'Continue'
        & $Godot @taskArgs *> $taskLog
        $taskExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        $taskResult = Get-Content -LiteralPath $taskLog
        $taskSummary = $taskResult | Select-String '^CAMERA SMOOTHNESS:'
        Write-Output "$taskMode requested $taskRate FPS: $taskSummary"
        if ($taskExit -ne 0 -or !$taskSummary -or ($taskResult | Select-String 'FAIL:|SCRIPT ERROR:')) {
            throw "Camera validation failed at $taskRate FPS. See $taskLog"
        }
        $taskDataPath = Join-Path $taskOutput "camera_matrix_${taskMode}_${taskRate}.json"
        $taskData = Get-Content -LiteralPath $taskDataPath -Raw | ConvertFrom-Json
        Write-Output ("  Clock: {0:N2} FPS; wall: {1:N2} FPS; physics: {2} Hz" -f
            $taskData.timing.walk.measured_fps, $taskData.timing.walk.wall_fps,
            $taskData.timing.runtime.physics_tps)
    }
} finally {
    $env:APPDATA = $taskOriginalAppData
}
