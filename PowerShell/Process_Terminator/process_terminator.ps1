<#
Dean Newton
2025-05-17 initial commit
Version 1.1.0

.SYNOPSIS
Terminates processes with safe wildcard support and confirmation safeguards.

.DESCRIPTION
Features:
- Blocks single asterisk (*) wildcard
- Requires confirmation for multiple processes
- Color-coded output with process listings
- Configurable safety thresholds
#>

param(
    [Parameter(Mandatory = $false)]
    [Alias("pid")]
    [int[]]$ProcessID,
    
    [Parameter(Mandatory = $false)]
    [Alias("name")]
    [string[]]$ProcessName
)

#region Logging Setup
$scriptName = "Process_Terminator"
$logDir = "$env:ProgramData\${scriptName}_Logs"
$transcriptPath = "$logDir\${scriptName}$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

try {
    Start-Transcript -Path $transcriptPath -Append -ErrorAction Stop
    $transcriptStarted = $true
}
catch {
    Write-Warning "Transcript failed: $_"
    $transcriptStarted = $false
}
#endregion

#region Initialization
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Administrator rights required" -ErrorAction Stop
    exit 1
}

# Show syntax help
Write-Host @" 

================== Process Terminator Usage ===================
Command-line parameters (override config):
  -Pid         Comma-separated process IDs
  -Name        Comma-separated process name patterns

Examples:
  .\$($MyInvocation.MyCommand.Name) -Pid 1234,5678
  .\$($MyInvocation.MyCommand.Name) -Name "chrome*","nginx.*"
  .\$($MyInvocation.MyCommand.Name) -Pid 1234 -Name "temp*.exe"

Config file usage:
  Create config.json with format:
  {
    "PIDs": [1234, 5678],
    "TaskNames": ["process*", "regex.*pattern"]
  }
================================================================

"@ -ForegroundColor White 

$configPath = Join-Path $PSScriptRoot "config.json"
$examplePath = Join-Path $PSScriptRoot "config_example.json"
#endregion

#region Process Termination Logic
function Invoke-ProcessTerminator {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [object]$InputObject
    )

    begin {
        $dangerousPatterns = @('^\*$')  # Block single asterisk only
        $confirmThreshold = 1          # Confirm for >1 process
    }

    process {
        $targetProcesses = @()

        #region Process Collection
        # Handle PIDs
        if ($InputObject.PIDs) {
            foreach ($pid in $InputObject.PIDs) {
                if ($process = Get-Process -Id $pid -ErrorAction SilentlyContinue) {
                    $targetProcesses += $process
                }
                else {
                    Write-Host "[Warning] PID $pid not found" -ForegroundColor Yellow
                }
            }
        }

        # Handle process names with safe wildcards
        if ($InputObject.TaskNames) {
            foreach ($pattern in $InputObject.TaskNames) {
                if ($dangerousPatterns -contains $pattern) {
                    Write-Host "[Blocked] Dangerous pattern: $pattern" -ForegroundColor Red
                    continue
                }

                try {
                    $matched = Get-Process | Where-Object { 
                        $_.ProcessName -like $pattern 
                    } -ErrorAction Stop
                    
                    if ($matched) {
                        $targetProcesses += $matched
                    }
                    else {
                        Write-Host "[Info] No matches for: $pattern" -ForegroundColor Yellow
                    }
                }
                catch {
                    Write-Host "[Error] Invalid pattern: $pattern" -ForegroundColor Red
                }
            }
        }
        #endregion

        #region Safety Checks
        $uniqueTargets = $targetProcesses | Sort-Object Id -Unique

        if ($uniqueTargets.Count -eq 0) {
            Write-Host "No valid targets" -ForegroundColor Cyan
            return
        }

        Write-Host "`n=== Matched Processes ===" -ForegroundColor Cyan
        $uniqueTargets | ForEach-Object {
            Write-Host " - $($_.ProcessName) " -NoNewline -ForegroundColor DarkYellow
            Write-Host "(PID: $($_.Id))" -ForegroundColor Gray
        }

        if ($uniqueTargets.Count -gt $confirmThreshold) {
            $confirmation = Read-Host "`nConfirm termination of $($uniqueTargets.Count) processes? (Y/N)"
            if ($confirmation -notmatch '^[yY]') {
                Write-Host "Termination cancelled" -ForegroundColor Green
                return
            }
        }
        #endregion

        #region Process Termination
        foreach ($process in $uniqueTargets) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                
                if (-not (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) {
                    Write-Host "[Terminated] " -NoNewline -ForegroundColor Green
                    Write-Host "$($process.ProcessName) (PID: $($process.Id))" -ForegroundColor DarkYellow
                }
                else {
                    Write-Host "[Failed] " -NoNewline -ForegroundColor Red
                    Write-Host "$($process.ProcessName) (PID: $($process.Id))" -ForegroundColor DarkYellow
                }
            }
            catch {
                Write-Host "[Error] " -NoNewline -ForegroundColor Red
                Write-Host "$($process.ProcessName) (PID: $($process.Id)): $_" -ForegroundColor DarkYellow
            }
        }
        #endregion
    }
}
#endregion

#region Execution Flow
if ($ProcessID -or $ProcessName) {
    [PSCustomObject]@{
        PIDs      = $ProcessID
        TaskNames = $ProcessName
    } | Invoke-ProcessTerminator
}
else {
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json -ErrorAction Stop
            $config | Invoke-ProcessTerminator
        }
        catch {
            Write-Host "Invalid config: $configPath" -ForegroundColor Red
        }
    }
    else {
    # Interactive mode
    $userInput = Read-Host "No config found. Enter PID/Process name"

    if (-not $userInput) {
        [PSCustomObject]@{
            PIDs      = @(1234)
            TaskNames = @("example*")
        } | ConvertTo-Json | Set-Content $examplePath
        Write-Host "Example config created: $examplePath" -ForegroundColor Green
        exit
    }

    if ($userInput -match '^\d+$') {
        [PSCustomObject]@{ PIDs = @([int]$userInput) } | Invoke-ProcessTerminator
    }
    else {
        # Remove .exe from end if present (case-insensitive)
        $safeInput = $userInput -replace '\.exe$',''
        if ($safeInput -eq "*") {
            Write-Host "Single asterisk wildcard not allowed" -ForegroundColor Red
            exit
        }
        [PSCustomObject]@{ TaskNames = @($safeInput) } | Invoke-ProcessTerminator
    }
}
}

#endregion


#region Transcript and Log Maintenance
if ($transcriptStarted) {
    try { Stop-Transcript | Out-Null } catch {}
}

# Retain only the 10 most recent log files
Get-ChildItem $logDir\*.log | Sort-Object CreationTime -Desc | Select-Object -Skip 10 | Remove-Item -Force
#endregion

# Final messages and cleanup
Write-Host "Operation completed. Logs available at $logDir" -ForegroundColor Green
Write-Host "Press any key to exit..." -ForegroundColor Cyan
[void][System.Console]::ReadKey($true)
# End of script 
