<#
.NOTES
    Script Name   : rclone-bisync-manager.ps1
    Script Title  : RClone Bisync Manager
    Author        : Dean N. [dynotesting]
    Version       : 2.5.6
    Creation Date : 2026-03-17
    Git URL       : https://github.com/dynotesting

    Converted from : rclone-bisync-manager.bat v2.5.5
    Conversion Date: 2026-03-17
    Conversion Notes:
        - Batch script rewritten in native PowerShell.
        - Eliminated all CMD parse workarounds.
        - All subroutines converted to proper PowerShell functions.
        - ANSI color replaced with Write-Host -ForegroundColor.
        - File I/O via Out-File and Add-Content - no subprocess overhead.
        - rclone size output parsed via ConvertFrom-Json.
        - param() block replaces manual PARSEARGS loop.
        - Boolean function returns replace errorlevel chains.
        - Logging via Write-Log with levels (INFO / WARN / ERROR / FILE).

.DESCRIPTION
    Manages bidirectional rclone bisync between two remotes with multi-machine
    lock file coordination, tracer file state tracking, configurable max-delete
    safety threshold, and optional silent/loop/service execution modes.

    Supports three run modes:
        -silent   : No prompts or pauses; uses built-in defaults.
        -loop     : Repeats sync continuously with a sleep interval between runs.
        -service  : Implies -silent and -loop for use as a Windows service.

    Lock and tracer files are written to both remotes before each sync and
    removed (or appended) after completion to prevent concurrent sync conflicts
    across multiple machines.

    *** See servy-configuration.json for recommended Windows service setup using NSSM. ***

.VERSION HISTORY
    2.5.6 - 2026-03-17
        - Post-sync cleanup order corrected: Invoke-WriteTracer APPEND now
          runs before Invoke-RemoveLock. Lock files remain in place until
          post-sync tracer write completes.
        - Removed all non-ASCII characters from script structure and strings
          to prevent PS 5.1 service host parse errors.
        - Replaced double-dash strings inside Write-Host and Write-Log calls
          with safe equivalents to prevent PS 5.1 unary operator misparse.
        - Script confirmed working end-to-end under PowerShell 5.1 and 7.x.

    2.5.5 - 2026-03-17
        - Initial PowerShell release. Converted from batch v2.5.5.
        - Fixed exit code capture via $script:rcloneExitCode.
        - Fixed console encoding to UTF-8.
        - Fixed variable-colon parser errors using ${varName} syntax.
#>

[CmdletBinding()]
param(
    [switch]$silent,
    [switch]$loop,
    [switch]$service
)

$ScriptName    = $MyInvocation.MyCommand.Name
$ScriptTitle   = 'RClone Bisync Manager'
$ScriptVersion = '2.5.6'

# -----------------------------------------------------------------------------
# CONSOLE ENCODING
# -----------------------------------------------------------------------------

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# -----------------------------------------------------------------------------
# SERVICE MODE INIT
# -----------------------------------------------------------------------------

if ($service) {
    $silent = $true
    $loop   = $true
}

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------

$ScriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptName)
$DataFolder     = "C:\ProgramData\$ScriptBaseName"
$DatePrefix     = (Get-Date -Format 'yyyy-MM-dd')
$LogFile        = "$DataFolder\${DatePrefix}_${ScriptBaseName}.log"

# Silent/loop defaults
$silentDefaultResync    = "N"
$silentDefaultMaxDelete = 90
$maxAbortRetries        = 5
$timeoutSeconds         = 30
$maxDelete              = 55
$abortCount             = 0
$script:rcloneExitCode  = 0

# Sync profile
$syncProfile = "Dropbox-FILEN_bisync"
$syncName    = "Dropbox to Filen Sync 2 way bidirectional"
$syncPath1   = "Dropbox:1_Dropbox-FILEN_bisync"
$syncPath2   = "Filen:/Dropbox-FILEN_bisync"

# rclone bisync state files (local AppData)
$bisyncDir  = "$env:LOCALAPPDATA\rclone\bisync"
$bisyncLst1 = "$bisyncDir\Dropbox_1_Dropbox-FILEN_sync..Filen__Dropbox-FILEN_sync.path1.lst"
$bisyncLst2 = "$bisyncDir\Dropbox_1_Dropbox-FILEN_sync..Filen__Dropbox-FILEN_sync.path2.lst"

# Lock and tracer file naming
$lockPrefix   = "rclone.batch.bisync.$syncProfile.lock."
$tracerPrefix = "rclone.batch.bisync.$syncProfile.tracer."
$myLockName   = "$lockPrefix$env:COMPUTERNAME.$env:USERNAME.lock"
$myTracerName = "$tracerPrefix$env:COMPUTERNAME.$env:USERNAME.tracer"

$lockPath1   = "$syncPath1/$myLockName"
$lockPath2   = "$syncPath2/$myLockName"
$tracerPath1 = "$syncPath1/$myTracerName"
$tracerPath2 = "$syncPath2/$myTracerName"
$lockTemp    = "$env:TEMP\$myLockName"
$tracerTemp  = "$env:TEMP\$myTracerName"

$tracerMode    = "FRESH"
$syncModeLabel = "Normal Run"

# -----------------------------------------------------------------------------
# ENSURE DATA FOLDER EXISTS
# -----------------------------------------------------------------------------

if (-not (Test-Path $DataFolder)) {
    New-Item -ItemType Directory -Path $DataFolder -Force | Out-Null
    Write-Host "  Created data folder: $DataFolder" -ForegroundColor DarkGray
}

# -----------------------------------------------------------------------------
# LOGGING
# Write-Log        - general activity log entry INFO/WARN/ERROR
# Write-Log-File   - dedicated FILE entry logged after every file operation
# Write-LogDivider - writes a visual separator to the log on session end
# -----------------------------------------------------------------------------

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogFile -Value "[$timestamp] [$Level] $Message"
}

function Write-Log-File {
    param([string]$Action, [string]$FilePath)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogFile -Value "[$timestamp] [FILE]  $Action => $FilePath"
}

function Write-LogDivider {
    Add-Content -Path $LogFile -Value ""
    Add-Content -Path $LogFile -Value ("=" * 80)
    Add-Content -Path $LogFile -Value ""
}

# -----------------------------------------------------------------------------
# HEADER - clears screen and prints title banner
# -----------------------------------------------------------------------------

function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  +================================================================+" -ForegroundColor Cyan
    Write-Host ("  |   {0,-63}|" -f $ScriptTitle) -ForegroundColor Cyan
    Write-Host ("  |   {0,-63}|" -f "$ScriptName v$ScriptVersion") -ForegroundColor DarkCyan
    Write-Host "  +================================================================+" -ForegroundColor Cyan
    Write-Host ""

    if ($service) {
        Write-Host "  Mode    : SERVICE - SILENT + LOOP" -ForegroundColor DarkGray
        Write-Host "  Defaults: RESYNC=${silentDefaultResync}  MAXDELETE=${silentDefaultMaxDelete}%" -ForegroundColor DarkGray
    } elseif ($silent) {
        Write-Host "  Mode    : SILENT - no prompts, no pauses" -ForegroundColor DarkGray
        Write-Host "  Defaults: RESYNC=${silentDefaultResync}  MAXDELETE=${silentDefaultMaxDelete}%" -ForegroundColor DarkGray
    } else {
        Write-Host "  Mode    : INTERACTIVE" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# -----------------------------------------------------------------------------
# LOCK FUNCTIONS
# Invoke-WriteLock  - writes lock file to both remotes before sync
#                     Rolls back Path 1 if Path 2 upload fails
# Invoke-RemoveLock - deletes lock file from both remotes after sync
# -----------------------------------------------------------------------------

function Invoke-WriteLock {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    @(
        "============================================================",
        "  Lock File    : $myLockName",
        "  Created      : $ts",
        "============================================================",
        "",
        "  Sync Profile : $syncProfile",
        "  Host         : $env:COMPUTERNAME",
        "  User         : $env:USERNAME",
        "============================================================"
    ) | Out-File -FilePath $lockTemp -Encoding ASCII -Force

    & rclone copyto $lockTemp $lockPath1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ ERROR ]  rclone failed to upload lock to Path 1." -ForegroundColor Red
        Write-Log "Lock upload failed: $lockPath1" -Level 'ERROR'
        Remove-Item $lockTemp -ErrorAction SilentlyContinue
        return $false
    }
    Write-Host "  [ OK    ]  Lock written : $lockPath1" -ForegroundColor Green
    Write-Log-File "LOCK WRITE" $lockPath1

    & rclone copyto $lockTemp $lockPath2
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ ERROR ]  rclone failed to upload lock to Path 2." -ForegroundColor Red
        Write-Log "Lock upload failed: $lockPath2 - rolling back Path 1" -Level 'ERROR'
        & rclone deletefile $lockPath1 2>$null
        Remove-Item $lockTemp -ErrorAction SilentlyContinue
        return $false
    }
    Write-Host "  [ OK    ]  Lock written : $lockPath2" -ForegroundColor Green
    Write-Log-File "LOCK WRITE" $lockPath2

    Remove-Item $lockTemp -ErrorAction SilentlyContinue
    return $true
}

function Invoke-RemoveLock {
    & rclone deletefile $lockPath1 2>$null
    Write-Host "  [ DEL   ]  $lockPath1" -ForegroundColor Cyan
    Write-Log-File "LOCK DEL" $lockPath1

    & rclone deletefile $lockPath2 2>$null
    Write-Host "  [ DEL   ]  $lockPath2" -ForegroundColor Cyan
    Write-Log-File "LOCK DEL" $lockPath2

    Write-Host "  [ DONE! ]  Lock files removed from both remotes." -ForegroundColor DarkGray
    Write-Log "Lock files removed from both remotes."
}

# -----------------------------------------------------------------------------
# TRACER FUNCTIONS
# Invoke-WriteTracer - FRESH: deletes existing tracers, writes new file to
#                      both paths. APPEND: downloads Path 1 tracer, appends
#                      sync record, re-uploads to both paths.
# -----------------------------------------------------------------------------

function Invoke-WriteTracer {
    param([string]$Mode)

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    if ($Mode -eq "FRESH") {
        & rclone deletefile $tracerPath1 2>$null
        & rclone deletefile $tracerPath2 2>$null

        @(
            "============================================================",
            "  Tracer File  : $myTracerName",
            "  Created      : $ts",
            "============================================================",
            "",
            "  Sync Profile : $syncProfile",
            "  Sync Name    : $syncName",
            "  Path 1       : $syncPath1",
            "  Path 2       : $syncPath2",
            "",
            "  Host         : $env:COMPUTERNAME",
            "  User         : $env:USERNAME",
            "============================================================"
        ) | Out-File -FilePath $tracerTemp -Encoding ASCII -Force

    } else {
        & rclone copyto $tracerPath1 $tracerTemp
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [ ERROR ]  Failed to download tracer from Path 1 for append." -ForegroundColor Red
            Write-Log "Tracer download failed for append: $tracerPath1" -Level 'ERROR'
            return $false
        }

        @(
            "",
            "------------------------------------------------------------",
            "  Sync Run  : $ts",
            "  Mode      : $syncModeLabel",
            "  Host      : $env:COMPUTERNAME",
            "  User      : $env:USERNAME",
            "------------------------------------------------------------"
        ) | Add-Content -Path $tracerTemp -Encoding ASCII
    }

    & rclone copyto $tracerTemp $tracerPath1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ ERROR ]  rclone failed to upload tracer to Path 1." -ForegroundColor Red
        Write-Log "Tracer upload failed: $tracerPath1" -Level 'ERROR'
        Remove-Item $tracerTemp -ErrorAction SilentlyContinue
        return $false
    }
    Write-Host "  [ OK    ]  Tracer written : $tracerPath1" -ForegroundColor Green
    Write-Log-File "TRACER $Mode" $tracerPath1

    & rclone copyto $tracerTemp $tracerPath2
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ ERROR ]  rclone failed to upload tracer to Path 2." -ForegroundColor Red
        Write-Log "Tracer upload failed: $tracerPath2" -Level 'ERROR'
        Remove-Item $tracerTemp -ErrorAction SilentlyContinue
        return $false
    }
    Write-Host "  [ OK    ]  Tracer written : $tracerPath2" -ForegroundColor Green
    Write-Log-File "TRACER $Mode" $tracerPath2

    Write-Host "  [ OK    ]  Tracer files updated - ${Mode}" -ForegroundColor Green
    Write-Log "Tracer files updated - ${Mode}."
    Remove-Item $tracerTemp -ErrorAction SilentlyContinue
    return $true
}

# -----------------------------------------------------------------------------
# TEST-FOREIGNLOCK
# Scans a remote path for any lock file not belonging to this host/user.
# Returns $true and sleeps $timeoutSeconds if a foreign lock is found.
# -----------------------------------------------------------------------------

function Test-ForeignLock {
    param([string]$scanPath, [string]$pathLabel)

    Write-Host "    Scanning ${pathLabel} for active locks..." -ForegroundColor DarkGray
    Write-Log "Scanning ${pathLabel} for active locks: $scanPath"

    $scanTmp = "$env:TEMP\rcloneLockScan$([System.IO.Path]::GetRandomFileName()).txt"
    & rclone lsf "$scanPath/" --include "$lockPrefix*" 2>$null | Out-File $scanTmp -Encoding ASCII
    $lines = Get-Content $scanTmp -ErrorAction SilentlyContinue
    Remove-Item $scanTmp -ErrorAction SilentlyContinue

    foreach ($line in $lines) {
        $name = $line.TrimEnd('/')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if (-not $name.StartsWith($lockPrefix))  { continue }
        if ($name -ieq $myLockName)              { continue }

        Write-Host ""
        Write-Host "    [ LOCKED ]  Another sync instance is active on ${pathLabel}." -ForegroundColor Yellow
        Write-Host "                Lock : $name" -ForegroundColor Yellow
        Write-Host "                Waiting ${timeoutSeconds}s then retrying..." -ForegroundColor Yellow
        Write-Host ""
        Write-Log "Foreign lock detected on ${pathLabel}: $name - waiting ${timeoutSeconds}s" -Level 'WARN'
        Start-Sleep -Seconds $timeoutSeconds
        return $true
    }

    Write-Host "    [ CLEAR  ]  No foreign locks on ${pathLabel}." -ForegroundColor Green
    Write-Log "No foreign locks on ${pathLabel}."
    return $false
}

# -----------------------------------------------------------------------------
# INVOKE-RCLONEBISYNC
# Runs rclone bisync with all configured flags.
# Exit code written to $script:rcloneExitCode immediately after rclone returns
# to bypass PowerShell function output stream contamination.
# -----------------------------------------------------------------------------

function Invoke-RcloneBisync {
    param([bool]$Resync)

    $rcloneArgs = @(
        "bisync", $syncPath1, $syncPath2,
        "-P",
        "--exclude", "*rclone.batch.bisync.*.lock.*",
        "--exclude", "*rclone.batch.bisync.*.tracer.*",
        "--checkers", "16",
        "--transfers", "8",
        "--conflict-loser", "num",
        "--max-lock", "0",
        "--max-delete", $maxDelete,
        "--multi-thread-cutoff", "64M",
        "--multi-thread-streams", "8",
        "--multi-thread-chunk-size", "8M",
        "--fast-list",
        "--use-server-modtime",
        "--buffer-size", "32M"
    )

    if ($Resync) { $rcloneArgs += "--resync" }

    Write-Log "Starting rclone bisync - resync=${Resync} maxDelete=${maxDelete}%"
    Write-Log "Args: $($rcloneArgs -join ' ')"

    & rclone @rcloneArgs
    $script:rcloneExitCode = $LASTEXITCODE
}

# -----------------------------------------------------------------------------
# GET-MAXDELETE
# Prompts for max-delete percentage or uses silent default.
# -----------------------------------------------------------------------------

function Get-MaxDelete {
    if ($silent) {
        $script:maxDelete = $silentDefaultMaxDelete
        Write-Host "  Silent mode: MAXDELETE auto-set to ${silentDefaultMaxDelete}% - global default." -ForegroundColor DarkGray
        Write-Log "Silent mode: MAXDELETE=${silentDefaultMaxDelete}%"
        return
    }

    while ($true) {
        $userInput = Read-Host "Max safe delete percentage 1-100 [ENTER = $maxDelete]"
        if ([string]::IsNullOrWhiteSpace($userInput)) { return }

        if ($userInput -match '^\d+$') {
            $val = [int]$userInput
            if ($val -ge 1 -and $val -le 100) {
                $script:maxDelete = $val
                Write-Log "User set MAXDELETE=${val}%"
                return
            }
        }
        Write-Host ""
        Write-Host "  WARNING : Value must be a whole number between 1 and 100." -ForegroundColor Yellow
        Write-Host ""
    }
}

# -----------------------------------------------------------------------------
# GET-RESYNCCHOICE
# Prompts for resync flag or uses silent default.
# -----------------------------------------------------------------------------

function Get-ResyncChoice {
    param([bool]$isDiscrepancy = $false)

    if ($silent) {
        if ($silentDefaultResync -ieq "Y") {
            Write-Host "  Silent mode: auto-selecting FIRST RUN with resync." -ForegroundColor DarkGray
            Write-Log "Silent mode: RESYNC=Y"
            return $true
        }
        Write-Host "  Silent mode: auto-selecting NORMAL sync - no resync." -ForegroundColor DarkGray
        Write-Log "Silent mode: RESYNC=N"
        return $false
    }

    Write-Host ""
    if ($isDiscrepancy) {
        Write-Host "  A tracer file discrepancy was detected above." -ForegroundColor Yellow
        Write-Host "  Please review the warning and confirm your sync mode." -ForegroundColor Yellow
    } else {
        Write-Host "  WARNING : INCORRECT USAGE CAN CAUSE DATA DUPLICATES/LOSS." -ForegroundColor Yellow
        Write-Host "            PLEASE READ THE PROMPTS CAREFULLY." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Is this the first run of this sync profile?" -ForegroundColor White
        Write-Host "  FIRST RUN ONLY : resync builds the baseline state file." -ForegroundColor White
        Write-Host "  Never use resync on subsequent runs." -ForegroundColor White
    }
    Write-Host ""

    $answer = Read-Host "Use resync flag? [y/n/q, default N]"
    if ($answer -ieq "Q") {
        Write-Log "User chose to quit at resync prompt."
        Write-LogDivider
        exit 0
    }
    $choice = ($answer -ieq "Y")
    Write-Log "User resync choice: ${choice}"
    return $choice
}

# -----------------------------------------------------------------------------
# ENTRY POINT
# -----------------------------------------------------------------------------

Show-Header
Write-Log "=== Session Start === $ScriptTitle v$ScriptVersion"
Write-Log "$ScriptName v$ScriptVersion initializing..."
Write-Log "Data folder : $DataFolder"
Write-Log "Mode        : $(if ($service) { 'SERVICE' } elseif ($silent) { 'SILENT' } else { 'INTERACTIVE' })"
Write-Log "Profile     : $syncProfile"
Write-Log "Path 1      : $syncPath1"
Write-Log "Path 2      : $syncPath2"

# -----------------------------------------------------------------------------
# MAIN LOOP
# -----------------------------------------------------------------------------

while ($true) {

    Show-Header

    # MULTI-MACHINE LOCK CHECK
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "    MULTI-MACHINE LOCK CHECK" -ForegroundColor Cyan
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    Lock prefix  :  $lockPrefix*" -ForegroundColor DarkGray
    Write-Host "    My lock name :  $myLockName" -ForegroundColor DarkGray
    Write-Host ""

    if (Test-ForeignLock -scanPath $syncPath1 -pathLabel "Path 1") { continue }
    if (Test-ForeignLock -scanPath $syncPath2 -pathLabel "Path 2") { continue }
    Write-Host ""

    # TRACER FILE CHECK
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "    TRACER FILE CHECK" -ForegroundColor Cyan
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    File    :  $myTracerName" -ForegroundColor DarkGray
    Write-Host "    Path 1  :  $tracerPath1" -ForegroundColor DarkGray
    Write-Host "    Path 2  :  $tracerPath2" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    Checking both remotes..." -ForegroundColor DarkGray
    Write-Host ""

    $t1 = [bool](& rclone lsf $tracerPath1 2>$null)
    $t2 = [bool](& rclone lsf $tracerPath2 2>$null)

    Write-Host ("    " + $(if ($t1) { "[ FOUND   ]" } else { "[ MISSING ]" }) + "  Path 1 : $tracerPath1") `
        -ForegroundColor $(if ($t1) { "Green" } else { "Yellow" })
    Write-Host ("    " + $(if ($t2) { "[ FOUND   ]" } else { "[ MISSING ]" }) + "  Path 2 : $tracerPath2") `
        -ForegroundColor $(if ($t2) { "Green" } else { "Yellow" })
    Write-Host ""
    Write-Log "Tracer check - Path1:${t1}  Path2:${t2}"

    $tracerMode  = "FRESH"
    $firstRun    = $false
    $discrepancy = $false

    if (-not $t1 -and -not $t2) {
        Write-Host "    No tracer files found." -ForegroundColor DarkGray
        Write-Host "    Tracers will be created when the sync executes." -ForegroundColor DarkGray
        Write-Host ""
        Write-Log "No tracer files found - first run path."
        $firstRun = Get-ResyncChoice -isDiscrepancy $false

    } elseif ($t1 -and -not $t2) {
        Write-Host ""
        Write-Host "  Previous sync may have been interrupted before completion." -ForegroundColor Yellow
        Write-Host "  Use RESYNC once to rebuild the baseline state." -ForegroundColor Yellow
        Write-Host ""
        Write-Log "Tracer discrepancy: Path 1 only." -Level 'WARN'
        $discrepancy = $true

    } elseif (-not $t1 -and $t2) {
        Write-Host ""
        Write-Host "  Corrupted tracer state: Path 2 has a tracer but Path 1 does not." -ForegroundColor Yellow
        Write-Host "  Use RESYNC once to rebuild the baseline and fix this state." -ForegroundColor Yellow
        Write-Host ""
        Write-Log "Tracer discrepancy: Path 2 only." -Level 'WARN'
        $discrepancy = $true

    } else {
        Write-Host "    Both tracers present. Verifying byte counts..." -ForegroundColor DarkGray
        Write-Host ""

        $s1Json = & rclone size $tracerPath1 --json 2>$null | ConvertFrom-Json
        $s2Json = & rclone size $tracerPath2 --json 2>$null | ConvertFrom-Json
        $size1  = $s1Json.bytes
        $size2  = $s2Json.bytes

        Write-Host "    Path 1  : $size1 bytes" -ForegroundColor DarkGray
        Write-Host "    Path 2  : $size2 bytes" -ForegroundColor DarkGray
        Write-Host ""
        Write-Log "Tracer sizes - Path1:${size1}  Path2:${size2}"

        if ($size1 -ne $size2) {
            Write-Host "  Tracer byte counts differ. Path1=${size1} Path2=${size2}" -ForegroundColor Yellow
            Write-Host "  Consider using RESYNC once to rebuild the bisync baseline state." -ForegroundColor Yellow
            Write-Host ""
            Write-Log "Tracer byte count mismatch: ${size1} vs ${size2}" -Level 'WARN'
            $discrepancy = $true
        } else {
            Write-Host "    [ MATCH   ]  Tracer byte counts verified." -ForegroundColor Green
            Write-Host ""
            Write-Host "    Checking rclone bisync state files..." -ForegroundColor DarkGray
            Write-Host "    Dir : $bisyncDir" -ForegroundColor DarkGray
            Write-Host ""

            $stateOk = $true
            foreach ($lst in @($bisyncLst1, $bisyncLst2)) {
                if (Test-Path $lst) {
                    Write-Host "    [ FOUND   ]  $lst" -ForegroundColor Green
                } else {
                    Write-Host "    [ MISSING ]  $lst" -ForegroundColor Yellow
                    Write-Log "Bisync state file missing: $lst" -Level 'WARN'
                    $stateOk = $false
                }
            }
            Write-Host ""

            if (-not $stateOk) {
                Write-Host "  rclone bisync state files are missing. RESYNC is required." -ForegroundColor Yellow
                Write-Host "  State dir: $bisyncDir" -ForegroundColor Yellow
                Write-Host ""
                Write-Log "Bisync state files missing - RESYNC required." -Level 'WARN'
                $discrepancy = $true
            } else {
                Write-Host "    [ READY   ]  All checks passed - tracer mode set to APPEND." -ForegroundColor Green
                Write-Host "    [ READY   ]  Skipping resync prompt, defaulting to normal run." -ForegroundColor Green
                Write-Host ""
                Write-Log "All checks passed. TRACER_MODE=APPEND."
                $tracerMode = "APPEND"
            }
        }
    }

    if ($discrepancy) {
        if (-not $silent) {
            Write-Host "    Continuing in 2 seconds..." -ForegroundColor DarkGray
            Start-Sleep -Seconds 2
            Write-Host ""
        }
        $firstRun = Get-ResyncChoice -isDiscrepancy $true
    }

    # GET MAXDELETE
    Get-MaxDelete

    # RUN SYNC
    if ($firstRun) {
        $syncModeLabel = "First Run with resync"
        Write-Host ""
        Write-Host "  First run selected - running with resync flag..." -ForegroundColor White
    } else {
        $syncModeLabel = "Normal Run"
        Write-Host ""
        Write-Host "  Normal run - syncing without resync..." -ForegroundColor White
    }

    Write-Host "  Safety delete limit : ${maxDelete}%" -ForegroundColor DarkGray
    Write-Host "  Tracer mode         : $tracerMode" -ForegroundColor DarkGray
    if ($silent) { Write-Host "  Silent mode: proceeding without prompts or pauses." -ForegroundColor DarkGray }
    Write-Host ""
    Write-Log "Starting sync - Mode:${syncModeLabel}  MaxDelete:${maxDelete}%  TracerMode:${tracerMode}"

    Write-Host "    Writing lock files to Path 1 and Path 2..." -ForegroundColor DarkGray
    if (-not (Invoke-WriteLock)) {
        Write-Host ""
        Write-Host "    [ ERROR ]  Lock file write failed. Aborting." -ForegroundColor Red
        Write-Log "Lock write failed. Aborting sync." -Level 'ERROR'
        Write-LogDivider
        if ($loop) { exit 1 }
        if (-not $silent) { Read-Host "Press Enter to exit" }
        exit 1
    }

    Write-Host "    Writing tracer to both paths - ${tracerMode}..." -ForegroundColor DarkGray
    if (-not (Invoke-WriteTracer -Mode $tracerMode)) {
        Write-Host ""
        Write-Host "    [ ERROR ]  Pre-sync tracer write failed. Aborting." -ForegroundColor Red
        Write-Log "Tracer write failed. Aborting sync." -Level 'ERROR'
        Invoke-RemoveLock
        Write-LogDivider
        if ($loop) { exit 1 }
        if (-not $silent) { Read-Host "Press Enter to exit" }
        exit 1
    }
    Write-Host ""

    # RCLONE BISYNC
    $script:rcloneExitCode = 0
    Invoke-RcloneBisync -Resync $firstRun
    $rcloneExit = $script:rcloneExitCode

    # POST-SYNC CLEANUP
    Invoke-WriteTracer -Mode "APPEND" | Out-Null
    Invoke-RemoveLock

    Write-Host ""
    Write-Log "rclone bisync exited with code ${rcloneExit}."

    if ($rcloneExit -eq 0) {
        Write-Host "    [ OK    ]  Sync complete." -ForegroundColor Green
        Write-Log "Sync completed successfully."
        $abortCount = 0
    } else {
        Write-Host "    [ WARN  ]  rclone reported errors. Exit code: ${rcloneExit}" -ForegroundColor Yellow
        Write-Host "               Next run will detect tracer state and prompt accordingly." -ForegroundColor Yellow
        $abortCount++
        Write-Log "rclone errors detected. Abort count: ${abortCount} / ${maxAbortRetries}" -Level 'WARN'
        Write-Host ""
        Write-Host "    Consecutive abort count: ${abortCount} / ${maxAbortRetries}" -ForegroundColor Yellow

        if ($abortCount -ge $maxAbortRetries) {
            Write-Host ""
            Write-Host "    [ FATAL ]  Reached max consecutive abort retries: ${maxAbortRetries}" -ForegroundColor Red
            Write-Host "               Exiting with code 1 so service manager can restart." -ForegroundColor Red
            Write-Log "FATAL: max abort retries reached - ${maxAbortRetries}. Exiting with code 1." -Level 'ERROR'
            Write-LogDivider
            exit 1
        }
    }

    # LOOP / EXIT
    if (-not $loop) {
        Write-Log "=== Session End === $ScriptTitle v$ScriptVersion"
        Write-LogDivider
        if (-not $silent) { Read-Host "Press Enter to exit" }
        exit 0
    }

    Write-Host ""
    Write-Host "  Loop mode: waiting ${timeoutSeconds} seconds before next sync..." -ForegroundColor DarkGray
    Write-Log "Loop mode: sleeping ${timeoutSeconds}s before next cycle."
    Start-Sleep -Seconds $timeoutSeconds
}
