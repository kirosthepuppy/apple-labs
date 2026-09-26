# Helpers for the Windows tests: run the launcher's command-line mode and fail
# the step when it fails. Dot-source it: . windows/tests/cli.ps1

$script:Exe = Join-Path $PWD 'out\AppleLabs.exe'

function Invoke-AppleLabs {
    $arguments = @('--cli') + $args
    $out = Join-Path $env:RUNNER_TEMP 'applelabs-out.txt'
    $err = Join-Path $env:RUNNER_TEMP 'applelabs-err.txt'
    $p = Start-Process -FilePath $script:Exe -ArgumentList $arguments -Wait -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err
    $text = Get-Content $out -Raw
    $problems = Get-Content $err -Raw
    if ($text) { Write-Host $text }
    if ($problems) { Write-Host $problems }
    if ($p.ExitCode -ne 0) {
        Write-Host "::error::Apple Labs --cli $($args -join ' ') failed: $problems $text"
        throw "Apple Labs --cli $($args -join ' ') exited with $($p.ExitCode)"
    }
    return $text
}

function Assert($condition, $message) {
    if (-not $condition) {
        Write-Host "::error::$message"
        throw $message
    }
}

function Get-Status { (Invoke-AppleLabs status --json) | ConvertFrom-Json }
