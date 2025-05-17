<#
Dean Newton
2025-05-17 initial commit
Version 1.0.0

.SYNOPSIS
This script automates the process of terminating specified processes, replacing specific executable files with a dummy
executable, and optionally setting up a scheduled task for silent mode execution. It includes error handling.

.DESCRIPTION
This script is designed to be run as an Administrator and performs the following tasks:
1. Checks if the script is run as Administrator.
2. Terminates processes by PID or name (with regex support) from command-line, config file, or interactive prompt.
3. Logs all actions and maintains up to 10 log files.
#>

param(
    [Parameter(Mandatory = $false)]
    [Alias("pid")]
    [int[]]$ProcessID,
    
    [Parameter(Mandatory = $false)]
    [Alias("name")]
    [string[]]$ProcessName
    # Add more parameters as needed
)

# Show syntax help
Write-Host @"

=== Process Terminator Usage ===
Command-line parameters (override config):
-pid         Comma-separated process IDs
-name        Comma-separated process name patterns

Examples:
.\$($MyInvocation.MyCommand.Name) -pid 1234,5678
.\$($MyInvocation.MyCommand.Name) -name "chrome*","nginx.*"
.\$($MyInvocation.MyCommand.Name) -pid 1234 -name "temp*.exe"

Config file usage:
Create config.json with format:
{
    `"PIDs`": [1234, 5678],
    `"TaskNames`": [ `"process*`", `"regex.*pattern`" ]
}
    
"@  -ForegroundColor Yellow

#region Logging Setup
# Setup logging directory and transcript file
$scriptName = "Process_Terminator"
$logDir = "$env:ProgramData\${scriptName}_Logs"
$transcriptPath = "$logDir\${scriptName}$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path $transcriptPath -Append | Out-Null
$transcriptStarted = $true
#endregion

#region Initialization
# Ensure the script is run as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

# Config paths
$configPath = Join-Path $PSScriptRoot "config.json"
$examplePath = Join-Path $PSScriptRoot "config_example.json"
#endregion

#region Process Terminator Function
function Invoke-ProcessTerminator {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [object]$InputObject
    )

    process {
        # Process PIDs
        if ($InputObject.PIDs) {
            foreach ($ProcessID in $InputObject.PIDs) {
                try {
                    Stop-Process -Id $ProcessID -Force -ErrorAction Stop
                    # Check if process still exists
                    $proc = Get-Process -Id $ProcessID -ErrorAction SilentlyContinue
                    if ($null -eq $proc) {
                        Write-Host "PID: $ProcessID - Status: " -ForegroundColor DarkYellow -NoNewline
                        Write-Host "Terminated" -ForegroundColor Green
                    }
                    else {
                        Write-Host "PID: $ProcessID - Status: " -ForegroundColor DarkYellow -NoNewline
                        Write-Host "Error (Still Running)" -ForegroundColor Red
                    }
                }
                catch {
                    Write-Host "PID: $ProcessID - Status: " -ForegroundColor DarkYellow -NoNewline
                    Write-Host "Error (Exception)" -ForegroundColor Red
                }
            }
        }

        # Process names with regex support
        if ($InputObject.TaskNames) {
            foreach ($namePattern in $InputObject.TaskNames) {
                $matchedProcs = Get-Process | Where-Object { $_.ProcessName -match $namePattern }
                if ($matchedProcs) {
                    foreach ($proc in $matchedProcs) {
                        try {
                            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                            # Check if process still exists
                            $checkProc = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
                            if ($null -eq $checkProc) {
                                Write-Host "Name: $($proc.ProcessName) (PID: $($proc.Id)) - Status: " -ForegroundColor DarkYellow -NoNewline
                                Write-Host "Terminated" -ForegroundColor Green
                            }
                            else {
                                Write-Host "Name: $($proc.ProcessName) (PID: $($proc.Id)) - Status: " -ForegroundColor DarkYellow -NoNewline
                                Write-Host "Error (Still Running)" -ForegroundColor Red
                            }
                        }
                        catch {
                            Write-Host "Name: $($proc.ProcessName) (PID: $($proc.Id)) - Status: " -ForegroundColor DarkYellow -NoNewline
                            Write-Host "Error (Exception)" -ForegroundColor Red
                        }
                    }
                }
                else {
                    Write-Host "No processes matched pattern: $namePattern" -ForegroundColor Yellow
                }
            }
        }
    }
}
#endregion

#region Main Logic
# Handle command-line parameters
if ($ProcessID -or $ProcessName) {
    $paramObject = [PSCustomObject]@{
        PIDs      = $ProcessID
        TaskNames = $ProcessName
    }
    $paramObject | Invoke-ProcessTerminator
}
else {
    # Load config if exists
    if (Test-Path $configPath) {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    }

    if ($config -and ($config.PIDs -or $config.TaskNames)) {
        $config | Invoke-ProcessTerminator
    }
    else {
        # Interactive mode
        Write-Host "No valid config found."
        $userInput = Read-Host "Enter PID or Process name to TERMINATE (wildcards allowed): "
        
        if (-not $userInput) {
            # Create example config
            $exampleConfig = @{
                PIDs      = @(1234, 5678)
                TaskNames = @("chrome*", "node*", "nginx.*")
            }
            $exampleConfig | ConvertTo-Json -Depth 3 | Set-Content $examplePath
            Write-Host "Created example config at: $examplePath"
            exit
        }

        # Try parse as PID first
        if ($userInput -match '^\d+$') {
            try {
                Stop-Process -Id $userInput -Force -ErrorAction Stop
                $proc = Get-Process -Id $userInput -ErrorAction SilentlyContinue
                if ($null -eq $proc) {
                    Write-Host "PID: $userInput - Status: " -ForegroundColor DarkYellow -NoNewline
                    Write-Host "Terminated" -ForegroundColor Green
                }
                else {
                    Write-Host "PID: $userInput - Status: " -ForegroundColor DarkYellow -NoNewline
                    Write-Host "Error (Still Running)" -ForegroundColor Red
                }
            }
            catch {
                Write-Host "PID: $userInput - Status: " -ForegroundColor DarkYellow -NoNewline
                Write-Host "Error (Exception)" -ForegroundColor Red
            }
        }
        else {
            $matchedProcs = Get-Process | Where-Object { $_.ProcessName -match $userInput }
            if ($matchedProcs) {
                foreach ($proc in $matchedProcs) {
                    try {
                        Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                        $checkProc = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
                        if ($null -eq $checkProc) {
                            Write-Host "Name: $($proc.ProcessName) (PID: $($proc.Id)) - Status: " -ForegroundColor DarkYellow -NoNewline
                            Write-Host "Terminated" -ForegroundColor Green
                        }
                        else {
                            Write-Host "Name: $($proc.ProcessName) (PID: $($proc.Id)) - Status: " -ForegroundColor DarkYellow -NoNewline
                            Write-Host "Error (Still Running)" -ForegroundColor Red
                        }
                    }
                    catch {
                        Write-Host "Name: $($proc.ProcessName) (PID: $($proc.Id)) - Status: " -ForegroundColor DarkYellow -NoNewline
                        Write-Host "Error (Exception)" -ForegroundColor Red
                    }
                }
            }
            else {
                Write-Host "No processes matched pattern: $userInput" -ForegroundColor Yellow
            }
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
