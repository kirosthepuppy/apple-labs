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
        # Each failing line becomes its own annotation, readable on the run's summary page.
        $lines = @("$problems`n$text" -split "`r?`n" | Where-Object { $_ -match 'FAIL|error|exception|at AppleLabs\.' } | Select-Object -First 9)
        foreach ($line in $lines) { Write-Host "::error::$($line.Trim())" }
        if ($lines.Count -eq 0) { Write-Host "::error::Apple Labs --cli $($args -join ' ') exited with $($p.ExitCode)" }
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
