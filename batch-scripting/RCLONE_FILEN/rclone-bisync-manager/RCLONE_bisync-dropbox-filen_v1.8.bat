@echo off
REM ============================================================
set "SCRIPT_NAME=RCLONE bisync manager"
REM  Version : 1.8
set "SCRIPT_VERSION=1.8"
REM  Author  : Dean
REM  Date Developed : 2026-03-01
REM  Purpose : Bidirectional sync between Dropbox and Filen
REM            cloud storage using rclone bisync.
REM
REM            Includes tracer file management to verify both
REM            sync endpoints are properly initialized before
REM            any sync operation is attempted.
REM ============================================================

REM -- Path 1 : Dropbox rclone remote (1_Dropbox-FILEN_sync)
REM -- Path 2 : Filen rclone remote   (Dropbox-FILEN_sync)
REM --
REM -- IMPORTANT: Both paths are rclone remotes.
REM --            All file operations (check, write, delete)
REM --            must go through rclone -- never CMD native
REM --            commands like IF EXIST, DEL, or COPY.
REM --
REM -- First run requires --resync to build the baseline state.
REM -- Subsequent runs must NOT use --resync or it will force
REM -- a full re-comparison and may cause data loss or
REM -- duplication.

REM ============================================================
REM  ANSI COLOR SETUP
REM  Requires Windows 10 1511+ with VT100/ANSI support.
REM  If ESC capture fails, output degrades to plain text safely.
REM ============================================================

for /F %%a in ('echo prompt $E^| cmd') do set "ESC=%%a"
set "WARN=%ESC%[93m"
set "ERR=%ESC%[91m"
set "OK=%ESC%[92m"
set "INFO=%ESC%[96m"
set "DIM=%ESC%[90m"
set "BOLD=%ESC%[1m"
set "RST=%ESC%[0m"

REM ============================================================
REM  SYNC PROFILE CONFIGURATION
REM ============================================================

set "SYNCPROFILE=Dropbox-FILEN_bisync"
set "SYNCNAME=Dropbox <-> Filen Sync 2 way bidirectional"
set "SYNCPATH1=Dropbox:1_Dropbox-FILEN_sync"
set "SYNCPATH2=Filen:/Dropbox-FILEN_sync"

REM -- rclone bisync state files (local AppData).
REM -- Named by rclone from the remote paths with special chars
REM -- replaced by underscores. Required for bisync to run
REM -- without --resync. If missing, rclone aborts with a
REM -- critical error and --resync is required to recover.
set "BISYNC_DIR=%LOCALAPPDATA%\rclone\bisync"
set "BISYNC_LST1=%BISYNC_DIR%\Dropbox_1_Dropbox-FILEN_sync..Filen__Dropbox-FILEN_sync.path1.lst"
set "BISYNC_LST2=%BISYNC_DIR%\Dropbox_1_Dropbox-FILEN_sync..Filen__Dropbox-FILEN_sync.path2.lst"

REM -- TRACER_MODE controls how WRITETRACER1 behaves at sync time:
REM --
REM --   FRESH  : Both existing tracers are deleted and a new
REM --            file is created from scratch with the profile
REM --            header. Used on first run or after any
REM --            discrepancy/warning path.
REM --
REM --   APPEND : The existing Path 1 tracer is downloaded, a
REM --            new timestamped sync run record is appended,
REM --            and the file is re-uploaded. rclone bisync
REM --            then syncs the updated file to Path 2
REM --            automatically. Preserves full run history.
REM --            Used only when all checks pass cleanly.
REM --
REM -- Defaults to FRESH. Only CHECKSTATE sets it to APPEND.
set "TRACER_MODE=FRESH"


REM ============================================================
REM  TRACER FILE CHECK
REM
REM  Tracer files are small marker files on each sync remote
REM  that act as start/complete checkpoints for each sync run.
REM  They are NOT created during this check phase -- they are
REM  written only at the moment the sync executes.
REM
REM  Write timing:
REM    Path 1 tracer : written immediately BEFORE rclone runs
REM    Path 2 tracer : synced to Path 2 BY rclone bisync itself
REM                    (no manual write to Path 2 is needed)
REM
REM  This means:
REM    Both present  = last sync completed successfully
REM    T1 only       = sync was started but may not have finished
REM    T2 only       = corrupted state (should not occur normally)
REM    Neither       = first run on this machine/profile
REM
REM  Tracer write modes (controlled by TRACER_MODE):
REM
REM    FRESH  (first run or any discrepancy/warning path)
REM      Both remote tracers deleted. New file created from
REM      scratch with profile header. Uploaded to Path 1.
REM      rclone bisync syncs it to Path 2.
REM
REM    APPEND (all checks pass: sizes match, state files found)
REM      Path 1 tracer downloaded, new sync run record appended
REM      with timestamp/mode/host/user, re-uploaded to Path 1.
REM      rclone bisync syncs the updated file to Path 2.
REM      Full run history is preserved in the tracer file.
REM
REM  Decision tree:
REM
REM    T1=FOUND / T2=FOUND
REM      Proceed to byte count check then rclone state file
REM      check. If all pass: TRACER_MODE=APPEND, skip --resync
REM      prompt, jump directly to ASKDELETE.
REM
REM    T1=MISSING / T2=MISSING
REM      First run on this machine/profile. TRACER_MODE=FRESH.
REM      No tracers created here -- created at sync time.
REM      Show standard first-run prompt (ASK).
REM
REM    T1=FOUND / T2=MISSING
REM      Sync started but Path 2 never received the tracer.
REM      Prior run may have been interrupted. TRACER_MODE=FRESH.
REM      Warn and show confirm --resync prompt.
REM
REM    T1=MISSING / T2=FOUND
REM      Corrupted tracer state. Path 2 cannot have the tracer
REM      without Path 1 having been written first. Should not
REM      occur under normal operation. TRACER_MODE=FRESH.
REM      Warn and show confirm --resync prompt.
REM
REM  Filename pattern:
REM    _rclone.batch.bisync.<SYNCPROFILE>.host.<HOST>.<USER>.tracer
REM ============================================================

:TRACERCHECK

REM -- Build tracer filename using profile, hostname, and username
set "TRACER_NAME=_rclone.batch.bisync.%SYNCPROFILE%.host.%COMPUTERNAME%.%USERNAME%.tracer"

REM -- Full remote paths for each tracer
set "TRACER_PATH1=%SYNCPATH1%/%TRACER_NAME%"
set "TRACER_PATH2=%SYNCPATH2%/%TRACER_NAME%"

REM -- Local temp file used by WRITETRACER1 during upload
set "TRACER_TEMP=%TEMP%\%TRACER_NAME%"

echo.
echo  %BOLD%%INFO%  ============================================================%RST%
echo  %BOLD%%INFO%    %SCRIPT_NAME% v%SCRIPT_VERSION%%RST%
echo  %BOLD%%INFO%  ============================================================%RST%
echo.
echo.
echo  %BOLD%%INFO%  ============================================================%RST%
echo  %BOLD%%INFO%    TRACER FILE CHECK%RST%
echo  %BOLD%%INFO%  ============================================================%RST%
echo.
echo    %DIM%File    :%RST%  %TRACER_NAME%
echo    %DIM%Path 1  :%RST%  %TRACER_PATH1%
echo    %DIM%Path 2  :%RST%  %TRACER_PATH2%
echo.
echo    Checking both remotes...
echo.

REM -- Check each path using an exact full-path rclone lsf call.
REM -- Pointing lsf at the complete file path (not a directory)
REM -- returns the filename only if that exact file exists.
REM -- This avoids false positives from filter-based directory
REM -- scans which can match cached or partial remote listings.
set "T1=0"
for /f "delims=" %%i in ('rclone lsf "%TRACER_PATH1%" 2^>nul') do set "T1=1"

set "T2=0"
for /f "delims=" %%i in ('rclone lsf "%TRACER_PATH2%" 2^>nul') do set "T2=1"

REM -- Display found/missing status for each side
if "%T1%"=="1" (
    echo    %OK%[ FOUND   ]%RST%  Path 1 : %TRACER_PATH1%
) else (
    echo    %WARN%[ MISSING ]%RST%  Path 1 : %TRACER_PATH1%
)
if "%T2%"=="1" (
    echo    %OK%[ FOUND   ]%RST%  Path 2 : %TRACER_PATH2%
) else (
    echo    %WARN%[ MISSING ]%RST%  Path 2 : %TRACER_PATH2%
)
echo.

REM -- Both found: proceed to byte count and state file checks
if "%T1%"=="1" if "%T2%"=="1" goto CHECKSIZES

REM -- Neither found: first run on this machine/profile.
REM -- TRACER_MODE stays FRESH. No action here -- tracers are
REM -- created only when the sync executes.
if "%T1%"=="0" if "%T2%"=="0" (
    echo    %DIM%No tracer files found.%RST%
    echo    %DIM%Tracers will be created when the sync executes.%RST%
    echo.
    goto ASK
)

REM -- T1 found, T2 missing: sync started but may not have completed
if "%T1%"=="1" if "%T2%"=="0" (
    set "DISC_MSG=Previous sync may have been interrupted before completion"
    set "DISC_D1=Path 1 tracer : FOUND   ^(pre-sync marker -- written before rclone starts^)"
    set "DISC_D2=Path 2 tracer : MISSING ^(post-sync marker -- synced by rclone on completion^)"
    set "DISC_D3=The previous bisync run may not have finished -- consider using --resync"
    goto DISCREPANCY
)

REM -- T1 missing, T2 found: corrupted state -- should not occur
if "%T1%"=="0" if "%T2%"=="1" (
    set "DISC_MSG=Corrupted tracer state -- Path 2 exists without Path 1"
    set "DISC_D1=Path 1 tracer : MISSING ^(pre-sync marker -- must always be written first^)"
    set "DISC_D2=Path 2 tracer : FOUND   ^(synced by rclone -- cannot exist without Path 1^)"
    set "DISC_D3=Tracer state is inconsistent -- running --resync is strongly recommended"
    goto DISCREPANCY
)


:CHECKSIZES

REM -- Retrieve raw byte count for each tracer via rclone size --json.
REM -- rclone lsf --format "s" was unreliable on Dropbox remotes,
REM -- returning 0 for files confirmed to exist. rclone size --json
REM -- outputs {"count":N,"bytes":N} and is consistent across all
REM -- remote types. FOR /F extracts the value after "bytes":
REM -- and the second FOR /F strips any surrounding whitespace.
echo    Both tracers present. Verifying byte counts...
echo.

set "SIZE1=0"
for /f "tokens=2 delims=:," %%i in ('rclone size "%TRACER_PATH1%" --json 2^>nul ^| findstr "bytes"') do set "SIZE1=%%i"
for /f "tokens=*" %%i in ("%SIZE1%") do set "SIZE1=%%i"

set "SIZE2=0"
for /f "tokens=2 delims=:," %%i in ('rclone size "%TRACER_PATH2%" --json 2^>nul ^| findstr "bytes"') do set "SIZE2=%%i"
for /f "tokens=*" %%i in ("%SIZE2%") do set "SIZE2=%%i"

echo    %DIM%Path 1  : %SIZE1% bytes%RST%
echo    %DIM%Path 2  : %SIZE2% bytes%RST%
echo.

if "%SIZE1%"=="%SIZE2%" goto CHECKSTATE

REM -- Sizes differ: TRACER_MODE stays FRESH
set "DISC_MSG=Tracer byte count mismatch -- files may not be from the same run"
set "DISC_D1=Path 1 tracer : %SIZE1% bytes"
set "DISC_D2=Path 2 tracer : %SIZE2% bytes"
set "DISC_D3=Consider running --resync to rebuild the bisync baseline state"
goto DISCREPANCY


:CHECKSTATE

REM -- Tracer sizes match. Now verify rclone's own bisync state
REM -- files exist locally. These are required for bisync to run
REM -- without --resync. Even with healthy tracers, missing state
REM -- files cause rclone to abort with a critical error.
echo    %OK%[ MATCH   ]%RST%  Tracer byte counts verified.
echo.
echo    Checking rclone bisync state files...
echo    %DIM%Dir : %BISYNC_DIR%%RST%
echo.

set "STATE_OK=1"

if not exist "%BISYNC_LST1%" (
    echo    %WARN%[ MISSING ]%RST%  %BISYNC_LST1%
    set "STATE_OK=0"
) else (
    echo    %OK%[ FOUND   ]%RST%  %BISYNC_LST1%
)

if not exist "%BISYNC_LST2%" (
    echo    %WARN%[ MISSING ]%RST%  %BISYNC_LST2%
    set "STATE_OK=0"
) else (
    echo    %OK%[ FOUND   ]%RST%  %BISYNC_LST2%
)
echo.

if "%STATE_OK%"=="0" (
    REM -- State files missing: TRACER_MODE stays FRESH
    set "DISC_MSG=rclone bisync state files are missing -- --resync is required"
    set "DISC_D1=State files track what changed since the last successful sync"
    set "DISC_D2=Without them rclone bisync will abort with a critical error"
    set "DISC_D3=State dir: %BISYNC_DIR%"
    goto DISCREPANCY
)

REM -- All checks passed: tracers verified, state files present.
REM -- Set TRACER_MODE to APPEND so WRITETRACER1 appends a new
REM -- sync run record rather than replacing the tracer file.
REM -- Default FIRSTRUN to empty (= normal run) and jump
REM -- directly to ASKDELETE -- the --resync prompt is skipped.
echo    %OK%[ READY   ]%RST%  All checks passed -- tracer mode set to APPEND.
echo    %OK%[ READY   ]%RST%  Skipping --resync prompt, defaulting to normal run.
echo.
set "TRACER_MODE=APPEND"
set "FIRSTRUN="
goto ASKDELETE


:DISCREPANCY

REM -- Display yellow warning block with reason and three detail
REM -- lines. TRACER_MODE remains FRESH for the upcoming sync.
REM -- Pause 2 seconds then route to ASKCONFIRMRESYNC so the
REM -- user can decide whether to force a full --resync.
echo.
echo    %WARN%  +----------------------------------------------------------+%RST%
echo    %WARN%  ^|  WARNING : Tracer File Discrepancy Detected              ^|%RST%
echo    %WARN%  +----------------------------------------------------------+%RST%
echo    %WARN%  ^|  %DISC_MSG%%RST%
echo    %WARN%  +----------------------------------------------------------+%RST%
echo    %WARN%  ^|  %DISC_D1%%RST%
echo    %WARN%  ^|  %DISC_D2%%RST%
echo    %WARN%  ^|  %DISC_D3%%RST%
echo    %WARN%  +----------------------------------------------------------+%RST%
echo.
echo    Continuing in 2 seconds...
timeout /t 2 /nobreak >nul
echo.
goto ASKCONFIRMRESYNC


REM ============================================================
REM  SYNC PROMPTS
REM ============================================================

:ASK

REM -- Standard first-run prompt. Reached only when neither
REM -- tracer exists (first run on this machine/profile).
REM -- TRACER_MODE=FRESH. Tracers created at sync time only --
REM -- Path 1 written before rclone, Path 2 synced by rclone.
echo  %WARN%  WARNING : INCORRECT USAGE CAN CAUSE DATA DUPLICATES/LOSS.%RST%
echo  %WARN%            PLEASE READ THE PROMPTS CAREFULLY.%RST%
echo.
echo  %WARN%  Is this the first run of this sync profile?%RST%
echo  %WARN%  FIRST RUN ONLY : --resync builds the baseline state file.%RST%
echo  %WARN%  Never use on subsequent runs -- forces full re-comparison%RST%
echo  %WARN%  and may cause data duplication or loss.%RST%
echo.
set "FIRSTRUN="
set /p "FIRSTRUN=Use --resync flag? [y/n/q | ENTER = N]: "

if "%FIRSTRUN%"=="" goto ASKDELETE
if /i "%FIRSTRUN%"=="Y" goto ASKDELETE
if /i "%FIRSTRUN%"=="N" goto ASKDELETE
if /i "%FIRSTRUN%"=="Q" goto END

echo.
echo  %WARN%  WARNING : Invalid input. Please enter Y, N, or Q. Press Enter for default (N).%RST%
echo.
goto ASK


:ASKCONFIRMRESYNC

REM -- Rephrased prompt shown only after a tracer discrepancy.
REM -- TRACER_MODE=FRESH -- tracer wiped and recreated regardless
REM -- of y/n choice. User decides only whether to add --resync.
REM -- Clear FIRSTRUN before prompt to prevent stale values.
echo  %WARN%  A tracer file discrepancy was detected above.%RST%
echo  %WARN%  Please review the warning and confirm your sync mode.%RST%
echo.
set "FIRSTRUN="
set /p "FIRSTRUN=Confirm --resync flag? [y/n/q | ENTER = N (normal sync)]: "

if "%FIRSTRUN%"=="" goto ASKDELETE
if /i "%FIRSTRUN%"=="Y" goto ASKDELETE
if /i "%FIRSTRUN%"=="N" goto ASKDELETE
if /i "%FIRSTRUN%"=="Q" goto END

echo.
echo  %WARN%  WARNING : Invalid input. Please enter Y, N, or Q. Press Enter for default (N).%RST%
echo.
goto ASKCONFIRMRESYNC


:ASKDELETE

REM -- Prompt for max safe delete percentage.
REM -- Clear variable before prompt (stale-value guard).
REM -- Empty input (Enter only) defaults to 50.
echo.
set "MAXDELETE="
set /p "MAXDELETE=Max safe delete percentage (1-100) [ENTER = 50]: "

if "%MAXDELETE%"=="" set "MAXDELETE=50"
goto VALIDATE


:VALIDATE

REM -- Two-stage numeric validation:
REM --
REM -- Stage 1: FOR /F digit-delimiter check.
REM --   Rejects any input containing non-digit characters
REM --   (letters, symbols, spaces, decimals). If a non-digit
REM --   is found, the loop body fires and re-prompts.
REM --   If all digits, no token is found and falls through.
REM --
REM -- Stage 2: SET /A normalization.
REM --   Converts the confirmed-digit string to a clean base-10
REM --   integer. Strips leading zeros that would cause LSS/GTR
REM --   to behave unexpectedly ("01"->1, "007"->7, "099"->99).
REM --   Safe to use here because non-digit input was already
REM --   rejected in Stage 1.
for /f "delims=0123456789" %%A in ("%MAXDELETE%") do (
    echo.
    echo  %WARN%  WARNING : Invalid input. Please enter a whole number between 1 and 100.%RST%
    echo.
    goto ASKDELETE
)
set /a MAXDELETE=%MAXDELETE%
goto RANGECHECK


:RANGECHECK

REM -- LSS / GTR comparisons enforce the 1-100 range strictly.
REM -- MAXDELETE is guaranteed a clean integer at this point
REM -- due to the two-stage validation above.
if %MAXDELETE% LSS 1 goto RANGEERROR
if %MAXDELETE% GTR 100 goto RANGEERROR
goto ROUTERUN


:RANGEERROR
echo.
echo  %WARN%  WARNING : Value out of range. Please enter a number between 1 and 100.%RST%
echo.
goto ASKDELETE


:ROUTERUN

REM -- Route to FIRSTRUN or NORMALRUN based on FIRSTRUN flag.
REM -- Empty FIRSTRUN (default) and explicit N both route to
REM -- NORMALRUN. Only an explicit Y routes to FIRSTRUN.
if /i "%FIRSTRUN%"=="Y" goto FIRSTRUN
goto NORMALRUN


:FIRSTRUN

REM -- SYNC_MODE_LABEL is embedded in APPEND mode tracer records
REM -- to identify what kind of run produced each history entry.
set "SYNC_MODE_LABEL=First Run (--resync)"

echo.
echo  First run selected -- running with --resync flag...
echo  Safety delete limit: %MAXDELETE%%%
echo  Tracer mode: %TRACER_MODE%
echo.

REM -- Write Path 1 tracer immediately before rclone starts.
REM -- FRESH: deletes both tracers, creates new file, uploads to P1.
REM -- APPEND: downloads P1 tracer, appends run record, re-uploads.
REM -- rclone bisync then syncs the P1 tracer to P2 automatically.
REM -- Abort if this fails -- never invoke rclone without the marker.
echo    %DIM%Writing pre-sync tracer to Path 1 [%TRACER_MODE%]...%RST%
call :WRITETRACER1
if errorlevel 1 (
    echo.
    echo    %ERR%  [ ERROR ]  Pre-sync tracer write failed. Aborting.%RST%
    echo.
    pause
    goto END
)
echo.

rclone bisync "%SYNCPATH1%" "%SYNCPATH2%" ^
  --resync ^
  -P ^
  --checkers 16 ^
  --transfers 8 ^
  --conflict-loser num ^
  --max-lock 0 ^
  --max-delete %MAXDELETE% ^
  --multi-thread-cutoff 64M ^
  --multi-thread-streams 8 ^
  --multi-thread-chunk-size 8M ^
  --fast-list ^
  --use-server-modtime ^
  --buffer-size 32M

REM -- Capture exit code immediately before any other command
REM -- can overwrite errorlevel. On success, rclone has synced
REM -- the Path 1 tracer to Path 2 -- no manual write needed.
REM -- On failure, Path 2 tracer will be absent and the next
REM -- run detects T1=FOUND/T2=MISSING and prompts for --resync.
set "RCLONE_OK=1"
if errorlevel 1 set "RCLONE_OK=0"

echo.
if "%RCLONE_OK%"=="1" (
    echo    %OK%  [ OK    ]  Sync complete. Path 2 tracer synced by rclone.%RST%
) else (
    echo    %WARN%  [ WARN  ]  rclone reported errors.%RST%
    echo    %WARN%             Path 2 tracer may not have synced.%RST%
    echo    %WARN%             Next run will detect T1=FOUND T2=MISSING and prompt for --resync.%RST%
)
goto END


:NORMALRUN

REM -- SYNC_MODE_LABEL is embedded in APPEND mode tracer records
REM -- to identify what kind of run produced each history entry.
set "SYNC_MODE_LABEL=Normal Run"

echo.
echo  Normal run -- syncing without --resync...
echo  Safety delete limit: %MAXDELETE%%%
echo  Tracer mode: %TRACER_MODE%
echo.

REM -- Write Path 1 tracer immediately before rclone starts.
REM -- FRESH: deletes both tracers, creates new file, uploads to P1.
REM -- APPEND: downloads P1 tracer, appends run record, re-uploads.
REM -- rclone bisync then syncs the P1 tracer to P2 automatically.
REM -- Abort if this fails -- never invoke rclone without the marker.
echo    %DIM%Writing pre-sync tracer to Path 1 [%TRACER_MODE%]...%RST%
call :WRITETRACER1
if errorlevel 1 (
    echo.
    echo    %ERR%  [ ERROR ]  Pre-sync tracer write failed. Aborting.%RST%
    echo.
    pause
    goto END
)
echo.

rclone bisync "%SYNCPATH1%" "%SYNCPATH2%" ^
  -P ^
  --checkers 16 ^
  --transfers 8 ^
  --conflict-loser num ^
  --max-lock 0 ^
  --max-delete %MAXDELETE% ^
  --multi-thread-cutoff 64M ^
  --multi-thread-streams 8 ^
  --multi-thread-chunk-size 8M ^
  --fast-list ^
  --use-server-modtime ^
  --buffer-size 32M

REM -- Capture exit code immediately before any other command
REM -- can overwrite errorlevel. On success, rclone has synced
REM -- the Path 1 tracer to Path 2 -- no manual write needed.
REM -- On failure, Path 2 tracer will be absent and the next
REM -- run detects T1=FOUND/T2=MISSING and prompts for --resync.
set "RCLONE_OK=1"
if errorlevel 1 set "RCLONE_OK=0"

echo.
if "%RCLONE_OK%"=="1" (
    echo    %OK%  [ OK    ]  Sync complete. Path 2 tracer synced by rclone.%RST%
) else (
    echo    %WARN%  [ WARN  ]  rclone reported errors.%RST%
    echo    %WARN%             Path 2 tracer may not have synced.%RST%
    echo    %WARN%             Next run will detect T1=FOUND T2=MISSING and prompt for --resync.%RST%
)
goto END


:END
echo.
pause
goto :eof


REM ============================================================
REM  SUBROUTINES
REM  Called via CALL :label -- return via EXIT /B [code]
REM  WRITETRACER1 is the ONLY place tracer files are created.
REM  WRITETRACER2 was removed in v1.5 -- rclone bisync syncs
REM  the Path 1 tracer to Path 2 automatically on completion.
REM ============================================================

:WRITETRACER1

if /i "%TRACER_MODE%"=="APPEND" goto WT1_APPEND

REM -- FRESH mode -----------------------------------------------
REM -- Delete both existing remote tracers first to ensure a
REM -- clean slate. Errors suppressed -- files may not exist on
REM -- first run or after a previously failed sync.
REM --
REM -- Write new tracer content via PowerShell to TRACER_TEMP.
REM -- Variables passed as $env:VAR so CMD never expands SYNCNAME
REM -- inline -- prevents <-> from being parsed as redirection.
REM --
REM -- Upload TRACER_TEMP to Path 1. Temp file is NOT deleted
REM -- here -- it is reused by WT1_APPEND on the next run if
REM -- TRACER_MODE is ever APPEND (defensive, safe to leave).
REM -- Returns exit /b 1 on any failure so caller can abort.

rclone deletefile "%TRACER_PATH1%" >nul 2>&1
rclone deletefile "%TRACER_PATH2%" >nul 2>&1

powershell -NoProfile -Command ^
  "$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss';" ^
  "$lines = @(" ^
  "  '============================================================'," ^
  "  ('  Tracer File  : ' + $env:TRACER_NAME)," ^
  "  ('  Created      : ' + $ts)," ^
  "  '============================================================'," ^
  "  ''," ^
  "  ('  Sync Profile : ' + $env:SYNCPROFILE)," ^
  "  ('  Sync Name    : ' + $env:SYNCNAME)," ^
  "  ('  Path 1       : ' + $env:SYNCPATH1)," ^
  "  ('  Path 2       : ' + $env:SYNCPATH2)," ^
  "  ''," ^
  "  ('  Host         : ' + $env:COMPUTERNAME)," ^
  "  ('  User         : ' + $env:USERNAME)," ^
  "  '============================================================'" ^
  ");" ^
  "$lines | Out-File -FilePath $env:TRACER_TEMP -Encoding ASCII -Force"

if errorlevel 1 (
    echo    %ERR%  [ ERROR ]  PowerShell failed to write tracer temp file.%RST%
    echo    %ERR%             Temp : %TRACER_TEMP%%RST%
    exit /b 1
)

rclone copyto "%TRACER_TEMP%" "%TRACER_PATH1%"
if errorlevel 1 (
    echo    %ERR%  [ ERROR ]  rclone failed to upload pre-sync tracer.%RST%
    echo    %ERR%             Remote : %TRACER_PATH1%%RST%
    del "%TRACER_TEMP%" >nul 2>&1
    exit /b 1
)

echo    %OK%  [ OK    ]  Pre-sync tracer created (FRESH) : %TRACER_PATH1%%RST%
exit /b 0


:WT1_APPEND
REM -- APPEND mode ----------------------------------------------
REM -- Download the existing Path 1 tracer to TRACER_TEMP.
REM -- Append a new sync run record via PowerShell Add-Content.
REM -- Re-upload the modified file to Path 1.
REM -- rclone bisync will sync the updated file to Path 2.
REM -- Returns exit /b 1 on any failure so caller can abort.

rclone copyto "%TRACER_PATH1%" "%TRACER_TEMP%"
if errorlevel 1 (
    echo    %ERR%  [ ERROR ]  rclone failed to download Path 1 tracer for append.%RST%
    echo    %ERR%             Remote : %TRACER_PATH1%%RST%
    exit /b 1
)

powershell -NoProfile -Command ^
  "$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss';" ^
  "$lines = @(" ^
  "  ''," ^
  "  '------------------------------------------------------------'," ^
  "  ('  Sync Run  : ' + $ts)," ^
  "  ('  Mode      : ' + $env:SYNC_MODE_LABEL)," ^
  "  ('  Host      : ' + $env:COMPUTERNAME)," ^
  "  ('  User      : ' + $env:USERNAME)," ^
  "  '------------------------------------------------------------'" ^
  ");" ^
  "$lines | Add-Content -Path $env:TRACER_TEMP -Encoding ASCII"

if errorlevel 1 (
    echo    %ERR%  [ ERROR ]  PowerShell failed to append sync record to tracer.%RST%
    echo    %ERR%             Temp : %TRACER_TEMP%%RST%
    del "%TRACER_TEMP%" >nul 2>&1
    exit /b 1
)

rclone copyto "%TRACER_TEMP%" "%TRACER_PATH1%"
if errorlevel 1 (
    echo    %ERR%  [ ERROR ]  rclone failed to re-upload appended tracer.%RST%
    echo    %ERR%             Remote : %TRACER_PATH1%%RST%
    del "%TRACER_TEMP%" >nul 2>&1
    exit /b 1
)

echo    %OK%  [ OK    ]  Pre-sync tracer appended (APPEND) : %TRACER_PATH1%%RST%
del "%TRACER_TEMP%" >nul 2>&1
exit /b 0


REM ============================================================
REM  OPTION REFERENCE
REM ============================================================
REM  --resync
REM    FIRST RUN ONLY -- builds the baseline file list.
REM    Required before bisync can track changes on both sides.
REM    WARNING: Never use on subsequent runs. It forces a full
REM    forced re-comparison and may cause data duplication.
REM
REM  -P / --progress
REM    Show real-time transfer progress in the console.
REM
REM  --checkers 16
REM    Number of parallel file comparison threads.
REM    Higher values = faster scanning of large directories.
REM
REM  --transfers 8
REM    Number of files to transfer simultaneously.
REM    Tuned for high-bandwidth connections.
REM
REM  --conflict-loser num
REM    On conflict, the losing file is renamed with a numeric
REM    suffix -- both copies are preserved e.g. file(1).txt
REM    Options: num, pathname, delete
REM
REM  --max-lock 0
REM    Disables bisync lock file timeout.
REM    Prevents stale lock errors on interrupted syncs.
REM
REM  --max-delete PERCENT (default: 50)
REM    Safety threshold -- bisync aborts if more than this
REM    percentage of files would be deleted on either side.
REM    Protects against runaway deletes caused by network
REM    issues or accidental mass-deletion on one side.
REM    Range: 1-100 | To bypass entirely, use --force instead.
REM
REM  --multi-thread-cutoff 64M
REM    Files larger than 64MB use multi-threaded download.
REM
REM  --multi-thread-streams 8
REM    Number of concurrent threads per large file transfer.
REM
REM  --multi-thread-chunk-size 8M
REM    Size of each chunk when using multi-thread transfers.
REM
REM  --fast-list
REM    Uses fewer API calls by listing remotes in bulk.
REM    Reduces Dropbox and Filen API rate limiting risk.
REM
REM  --use-server-modtime
REM    Uses server-reported modification time instead of
REM    computing file hashes for change detection.
REM    Faster comparisons; less CPU and API overhead.
REM
REM  --buffer-size 32M
REM    In-memory read buffer per active file transfer.
REM    Improves throughput on fast connections.
REM ============================================================
