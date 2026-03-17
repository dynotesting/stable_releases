@echo off
REM ============================================================
set "SCRIPT_NAME=rclone-bisync-manager"
REM  Version    : 2.5.5
set "SCRIPT_VERSION=2.5.5"
REM  Author     : Dean N. [dynotesting]
REM  Date Coded : 2026-03-02
REM  Updated    : 2026-03-17
REM  Purpose    : Bidirectional sync between a local/remote path (ex Dropbox/Filen) using `rclone bisync`
REM
REM               Includes tracer file management to verify both
REM               sync endpoints are properly initialized before
REM               any sync operation is attempted.
REM
REM               MULTI-MACHINE LOCK: Before syncing, the script
REM               scans both remotes for ANY lock file matching
REM               the lock prefix (_rclone.batch.bisync.<profile>.lock.*)
REM               If a lock from a DIFFERENT host/user is present,
REM               the script waits TIMEOUT seconds and retries.
REM
REM               Supports:
REM                 /silent  - Non-interactive: no prompts, no pauses,
REM                            uses configured defaults.
REM                 /loop    - Repeat sync cycle until process is terminated.
REM                 /service - Same as /silent + /loop (service-style mode).
REM
REM  Notes v2.5.5: - Fixed SERVICE mode outputting raw ANSI escape codes
REM                  in log files. SERVICE mode now sets all color vars
REM                  to empty strings before jumping to :SKIP_ANSI,
REM                  producing clean plain-text log output.
REM                - Removed duplicate ANSI setup block that was executing
REM                  after :SKIP_ANSI, overwriting the empty color vars
REM                  set for service mode.
REM                - Removed stray leftover lines after :SKIP_ANSI.
REM                - Tracer and lock filenames now include explicit file
REM                  extensions (.lock / .tracer) for clarity.
REM                  e.g. _rclone.batch.bisync.<profile>.lock.<HOST>.<USER>.lock
REM                       _rclone.batch.bisync.<profile>.tracer.<HOST>.<USER>.tracer
REM                - REMOVELOCK now echoes each deleted path individually
REM                  for clearer log output.
REM                - WRITETRACER1 output messages updated to show each
REM                  path written individually instead of generic summary.
REM  Notes v2.5.4: - WRITETRACER1 now explicitly uploads tracer to BOTH
REM                  Path 1 and Path 2 directly (FRESH and APPEND modes).
REM                  Tracer no longer relies on bisync propagation since
REM                  tracer files are excluded from bisync transfer.
REM                - Fixed unreachable WT1_FRESH_PS_FAIL label ordering.
REM  Notes v2.5.3: - Eliminated ALL remaining () blocks containing ANSI
REM                  color variables (%OK%, %WARN%, %ERR%, %DIM%, %RST%).
REM                  Every conditional branch that echoes color output is
REM                  now a flat goto label -- no exceptions.
REM                - Fixed :NORMALRUN success/failure block (was still
REM                  using if/else () form, causing ". was unexpected").
REM                - Fixed :HANDLE_RCLONE_FAILURE fatal branch.
REM                - Fixed :END loop branch.
REM                - Fixed :END_FAILURE loop branch.
REM  Notes v2.5.2: - Lock files now written to BOTH Path 1 and Path 2
REM                  before sync starts, so all machines see the lock
REM                  immediately regardless of which remote they check.
REM                - Lock and tracer files excluded from bisync transfer
REM                  via --exclude filters to prevent them from being
REM                  treated as user data.
REM                - WRITELOCK rolls back Path 1 lock if Path 2 upload
REM                  fails, keeping remotes consistent.
REM  Notes v2.5.1: - Added explicit SERVICE mode flag for clearer
REM                  mode reporting and future service-specific branching.
REM                - Fixed CMD parse errors caused by nested IF blocks
REM                  and ANSI escape sequences inside () blocks.
REM                - Flattened all silent-mode routing to labeled gotos.
REM  Notes v2.5  : - Separated tracer files (sync history log) from
REM                  lock files (active-sync mutex).
REM                - Lock files use a shared prefix so any machine can
REM                  detect if another machine is currently syncing.
REM                - Added MAX_ABORT_RETRIES: after N consecutive bisync
REM                  abort failures, script exits with code 1 so NSSM/
REM                  servy detects the failure and restarts the process.
REM                - LOOP mode resets abort counter on each successful sync.
REM                - Foreign lock detected: always wait+retry, never abort.
REM  Notes v2.4  : - Simplified discrepancy handling and silent-mode
REM                  routing to avoid CMD "was unexpected at this time"
REM                  parse errors.
REM                - Discrepancy messages printed with flat flow and
REM                  no nested IF blocks.
REM ============================================================



REM ============================================================
REM  SILENT / LOOP DEFAULTS (GLOBAL)
REM ============================================================
set "SILENT_DEFAULT_RESYNC=N"
set "SILENT_DEFAULT_MAXDELETE=90"

REM  Max consecutive "bisync aborted" failures before exiting with
REM  code 1 so the service manager (NSSM / servy) will restart us.
set "MAX_ABORT_RETRIES=5"


REM ============================================================
REM  MODE DETECTION
REM ============================================================
REM -- SILENT  : no prompts, no pauses, uses defaults for all questions.
REM -- LOOP    : after each sync, wait TIMEOUT seconds and repeat.
REM -- SERVICE : SILENT + LOOP for background/service execution.
REM -- TIMEOUT : wait seconds between lock retries and loop cycles.
REM -- MAXDELETE    : rclone bisync --max-delete safety percentage.
REM -- ABORT_COUNT  : consecutive failure counter for service restart.

set "SILENT=0"
set "LOOP=0"
set "SERVICE=0"
set "TIMEOUT=30"
set "MAXDELETE=55"
set "ABORT_COUNT=0"


:PARSEARGS
if "%~1"=="" goto ARGS_DONE

if /I "%~1"=="/silent"  set "SILENT=1"
if /I "%~1"=="-silent"  set "SILENT=1"

if /I "%~1"=="/loop"    set "LOOP=1"
if /I "%~1"=="-loop"    set "LOOP=1"

if /I "%~1"=="/service" (
    set "SERVICE=1"
    set "SILENT=1"
    set "LOOP=1"
)
if /I "%~1"=="-service" (
    set "SERVICE=1"
    set "SILENT=1"
    set "LOOP=1"
)

shift
goto PARSEARGS


:ARGS_DONE

if "%SERVICE%"=="1" (
    set "WARN="
    set "ERR="
    set "OK="
    set "INFO="
    set "DIM="
    set "BOLD="
    set "RST="
    echo Service mode enabled: running as SILENT + LOOP for background execution.
    goto SKIP_ANSI
)

REM ============================================================
REM  ANSI COLOR SETUP
REM ============================================================
for /F %%a in ('echo prompt $E^| cmd') do set "ESC=%%a"
set "WARN=%ESC%[93m"
set "ERR=%ESC%[91m"
set "OK=%ESC%[92m"
set "INFO=%ESC%[96m"
set "DIM=%ESC%[90m"
set "BOLD=%ESC%[1m"
set "RST=%ESC%[0m"

if "%SILENT%"=="1" echo Silent mode enabled: no prompts, no pauses. Defaults: RESYNC=%SILENT_DEFAULT_RESYNC%, MAXDELETE=%SILENT_DEFAULT_MAXDELETE%%%.

:SKIP_ANSI

REM ============================================================
REM  SYNC PROFILE CONFIGURATION
REM ============================================================
set "SYNCPROFILE=Dropbox-FILEN_bisync"
set "SYNCNAME=Dropbox <-> Filen Sync 2 way bidirectional"
set "SYNCPATH1=Dropbox:1_Dropbox-FILEN_bisync"
set "SYNCPATH2=Filen:/Dropbox-FILEN_bisync"

REM -- rclone bisync state files (local AppData).
set "BISYNC_DIR=%LOCALAPPDATA%\rclone\bisync"
set "BISYNC_LST1=%BISYNC_DIR%\Dropbox_1_Dropbox-FILEN_sync..Filen__Dropbox-FILEN_sync.path1.lst"
set "BISYNC_LST2=%BISYNC_DIR%\Dropbox_1_Dropbox-FILEN_sync..Filen__Dropbox-FILEN_sync.path2.lst"

REM -- TRACER_MODE controls WRITETRACER1 behavior.
set "TRACER_MODE=FRESH"


REM ============================================================
REM  FILE NAME DESIGN
REM
REM  LOCK file  (active-sync mutex, checked by ALL machines):
REM    _rclone.batch.bisync.<profile>.lock.<HOST>.<USER>
REM    Written to BOTH Path 1 and Path 2 before sync starts.
REM    All machines see the lock immediately on either remote.
REM    Deleted from both paths after sync completes.
REM    Excluded from bisync transfer via --exclude filter.
REM
REM  TRACER file (persistent sync history log):
REM    _rclone.batch.bisync.<profile>.tracer.<HOST>.<USER>
REM    Written once on first run to Path 1, synced to Path 2
REM    by rclone bisync during the run.
REM    Appended on each subsequent run.
REM    Used to verify both sides initialized and byte-count match.
REM    Excluded from bisync transfer via --exclude filter.
REM
REM  Both file types share the _rclone.batch.bisync.* prefix so
REM  a single --exclude pattern covers all management files.
REM ============================================================

set "LOCK_PREFIX=_rclone.batch.bisync.%SYNCPROFILE%.lock."
set "TRACER_PREFIX=_rclone.batch.bisync.%SYNCPROFILE%.tracer."

REM -- Below gives you clean filenames like:
REM -- _rclone.batch.bisync.Dropbox-FILEN_bisync.lock.MSI-VECTOR.dynotesting.lock
REM -- _rclone.batch.bisync.Dropbox-FILEN_bisync.tracer.MSI-VECTOR.dynotesting.tracer

set "MY_LOCK_NAME=%LOCK_PREFIX%%COMPUTERNAME%.%USERNAME%.lock"
set "MY_TRACER_NAME=%TRACER_PREFIX%%COMPUTERNAME%.%USERNAME%.tracer"

set "LOCK_PATH1=%SYNCPATH1%/%MY_LOCK_NAME%"
set "LOCK_PATH2=%SYNCPATH2%/%MY_LOCK_NAME%"
set "TRACER_PATH1=%SYNCPATH1%/%MY_TRACER_NAME%"
set "TRACER_PATH2=%SYNCPATH2%/%MY_TRACER_NAME%"
set "LOCK_TEMP=%TEMP%\%MY_LOCK_NAME%"
set "TRACER_TEMP=%TEMP%\%MY_TRACER_NAME%"


REM ============================================================
REM  MAIN LOOP ENTRY
REM ============================================================
:MAIN_LOOP


REM ============================================================
REM  MULTI-MACHINE LOCK CHECK
REM  Scan both remotes for any lock file from a DIFFERENT machine.
REM  If found, wait TIMEOUT seconds and retry -- never abort hard.
REM ============================================================
:LOCKCHECK

echo.
echo ============================================================
echo      %SCRIPT_NAME% v%SCRIPT_VERSION%
echo ============================================================
echo.

if "%SERVICE%"=="1" goto SHOW_SERVICE_MODE
if "%SILENT%"=="1" goto SHOW_SILENT_MODE
goto SHOW_INTERACTIVE_MODE

:SHOW_SERVICE_MODE
echo  %DIM%Mode    : SERVICE (SILENT + LOOP)%RST%
echo  %DIM%Defaults: RESYNC=%SILENT_DEFAULT_RESYNC%  MAXDELETE=%SILENT_DEFAULT_MAXDELETE%%% %RST%
goto MODE_DONE

:SHOW_SILENT_MODE
echo  %DIM%Mode    : SILENT (no prompts, no pauses)%RST%
echo  %DIM%Defaults: RESYNC=%SILENT_DEFAULT_RESYNC%  MAXDELETE=%SILENT_DEFAULT_MAXDELETE%%% %RST%
goto MODE_DONE

:SHOW_INTERACTIVE_MODE
echo  %DIM%Mode    : INTERACTIVE%RST%

:MODE_DONE

echo.
echo  %BOLD%%INFO%  ============================================================%RST%
echo  %BOLD%%INFO%    MULTI-MACHINE LOCK CHECK%RST%
echo  %BOLD%%INFO%  ============================================================%RST%
echo.
echo    %DIM%Lock prefix  :%RST%  %LOCK_PREFIX%*
echo    %DIM%My lock name :%RST%  %MY_LOCK_NAME%
echo.
echo    Scanning Path 1 for active locks...

set "FOREIGN_LOCK_FOUND=0"
set "FOREIGN_LOCK_NAME="
set "LOCK_SCAN_TMP=%TEMP%\rclone_lock_scan_%RANDOM%.txt"
del "%LOCK_SCAN_TMP%" >nul 2>&1

rclone lsf "%SYNCPATH1%/" --include "%LOCK_PREFIX%*" > "%LOCK_SCAN_TMP%" 2>nul

for /f "usebackq delims=" %%F in ("%LOCK_SCAN_TMP%") do (
    call :CHECK_FOREIGN_LOCK_LINE "%%F" "1"
)

del "%LOCK_SCAN_TMP%" >nul 2>&1

if "%FOREIGN_LOCK_FOUND%"=="1" goto LOCK_WAIT_P1
echo    %OK%[ CLEAR  ]%RST%  No foreign locks on Path 1.
goto LOCKCHECK_P2

:LOCK_WAIT_P1
set "LOCK_WAIT_MSG=Path 1"
goto LOCK_WAIT

:LOCKCHECK_P2
echo    Scanning Path 2 for active locks...

set "FOREIGN_LOCK_FOUND=0"
set "FOREIGN_LOCK_NAME="
set "LOCK_SCAN_TMP=%TEMP%\rclone_lock_scan_%RANDOM%.txt"
del "%LOCK_SCAN_TMP%" >nul 2>&1

rclone lsf "%SYNCPATH2%/" --include "%LOCK_PREFIX%*" > "%LOCK_SCAN_TMP%" 2>nul

for /f "usebackq delims=" %%F in ("%LOCK_SCAN_TMP%") do (
    call :CHECK_FOREIGN_LOCK_LINE "%%F" "2"
)

del "%LOCK_SCAN_TMP%" >nul 2>&1

if "%FOREIGN_LOCK_FOUND%"=="1" goto LOCK_WAIT_P2
echo    %OK%[ CLEAR  ]%RST%  No foreign locks on Path 2.
echo.
goto TRACERCHECK

:LOCK_WAIT_P2
set "LOCK_WAIT_MSG=Path 2"
goto LOCK_WAIT


REM ============================================================
REM  TRACER FILE CHECK
REM ============================================================
:TRACERCHECK

echo  %BOLD%%INFO%  ============================================================%RST%
echo  %BOLD%%INFO%    TRACER FILE CHECK%RST%
echo  %BOLD%%INFO%  ============================================================%RST%
echo.
echo    %DIM%File    :%RST%  %MY_TRACER_NAME%
echo    %DIM%Path 1  :%RST%  %TRACER_PATH1%
echo    %DIM%Path 2  :%RST%  %TRACER_PATH2%
echo.
echo    Checking both remotes...
echo.

set "T1=0"
for /f "delims=" %%i in ('rclone lsf "%TRACER_PATH1%" 2^>nul') do set "T1=1"

set "T2=0"
for /f "delims=" %%i in ('rclone lsf "%TRACER_PATH2%" 2^>nul') do set "T2=1"

if "%T1%"=="1" goto TRACER_P1_FOUND
echo    %WARN%[ MISSING ]%RST%  Path 1 : %TRACER_PATH1%
goto TRACER_P1_DONE
:TRACER_P1_FOUND
echo    %OK%[ FOUND   ]%RST%  Path 1 : %TRACER_PATH1%
:TRACER_P1_DONE

if "%T2%"=="1" goto TRACER_P2_FOUND
echo    %WARN%[ MISSING ]%RST%  Path 2 : %TRACER_PATH2%
goto TRACER_P2_DONE
:TRACER_P2_FOUND
echo    %OK%[ FOUND   ]%RST%  Path 2 : %TRACER_PATH2%
:TRACER_P2_DONE
echo.

if "%T1%"=="1" if "%T2%"=="1" goto CHECKSIZES
if "%T1%"=="1" if "%T2%"=="0" goto DISC_T1_ONLY
if "%T1%"=="0" if "%T2%"=="1" goto DISC_T2_ONLY

REM -- T1=0 T2=0: no tracers yet, first run
echo    No tracer files found.
echo    Tracers will be created when the sync executes.
echo.
goto ASK

:DISC_T1_ONLY
echo.
echo Previous sync may have been interrupted before completion.
echo Use RESYNC once to rebuild the baseline state.
echo.
goto AFTER_DISCREPANCY

:DISC_T2_ONLY
echo.
echo Corrupted tracer state: Path 2 has a tracer but Path 1 does not.
echo Use RESYNC once to rebuild the baseline and fix this state.
echo.
goto AFTER_DISCREPANCY


REM ============================================================
REM  CHECKSIZES
REM ============================================================
:CHECKSIZES

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

echo Tracer byte counts differ (%SIZE1% vs %SIZE2%).
echo Consider using RESYNC once to rebuild the bisync baseline state.
echo.
goto AFTER_DISCREPANCY


REM ============================================================
REM  CHECKSTATE
REM ============================================================
:CHECKSTATE

echo    %OK%[ MATCH   ]%RST%  Tracer byte counts verified.
echo.
echo    Checking rclone bisync state files...
echo    %DIM%Dir : %BISYNC_DIR%%RST%
echo.

set "STATE_OK=1"

if exist "%BISYNC_LST1%" goto STATE_LST1_OK
echo    %WARN%[ MISSING ]%RST%  %BISYNC_LST1%
set "STATE_OK=0"
goto STATE_LST1_DONE
:STATE_LST1_OK
echo    %OK%[ FOUND   ]%RST%  %BISYNC_LST1%
:STATE_LST1_DONE

if exist "%BISYNC_LST2%" goto STATE_LST2_OK
echo    %WARN%[ MISSING ]%RST%  %BISYNC_LST2%
set "STATE_OK=0"
goto STATE_LST2_DONE
:STATE_LST2_OK
echo    %OK%[ FOUND   ]%RST%  %BISYNC_LST2%
:STATE_LST2_DONE
echo.

if "%STATE_OK%"=="0" goto STATE_MISSING

echo    %OK%[ READY   ]%RST%  All checks passed -- tracer mode set to APPEND.
echo    %OK%[ READY   ]%RST%  Skipping --resync prompt, defaulting to normal run.
echo.
set "TRACER_MODE=APPEND"
set "FIRSTRUN="
goto ASKDELETE

:STATE_MISSING
echo rclone bisync state files are missing. RESYNC is required.
echo State dir: %BISYNC_DIR%
echo.
goto AFTER_DISCREPANCY


REM ============================================================
REM  AFTER DISCREPANCY
REM ============================================================
:AFTER_DISCREPANCY
if "%SILENT%"=="1" goto SILENT_DISCREPANCY
echo    Continuing in 2 seconds...
timeout /t 2 /nobreak >nul
echo.
goto ASKCONFIRMRESYNC


REM ============================================================
REM  SILENT-MODE DISCREPANCY ROUTING
REM ============================================================
:SILENT_DISCREPANCY
if /I "%SILENT_DEFAULT_RESYNC%"=="Y" goto SILENT_DISC_RESYNC
goto SILENT_DISC_NORMAL

:SILENT_DISC_RESYNC
echo Silent mode: auto-selecting FIRST RUN (--resync) after discrepancy.
set "FIRSTRUN=Y"
goto ASKDELETE

:SILENT_DISC_NORMAL
echo Silent mode: auto-selecting NORMAL sync (no --resync) after discrepancy.
set "FIRSTRUN="
goto ASKDELETE


REM ============================================================
REM  SYNC PROMPTS
REM ============================================================
:ASK

if not "%SILENT%"=="1" goto ASK_INTERACTIVE
if /I "%SILENT_DEFAULT_RESYNC%"=="Y" goto ASK_SILENT_RESYNC
echo Silent mode: assuming NORMAL run (no --resync) on first-run path.
set "FIRSTRUN="
goto ASKDELETE

:ASK_SILENT_RESYNC
echo Silent mode: assuming FIRST RUN (--resync) on first-run path.
set "FIRSTRUN=Y"
goto ASKDELETE

:ASK_INTERACTIVE
echo.
echo   WARNING : INCORRECT USAGE CAN CAUSE DATA DUPLICATES/LOSS.
echo             PLEASE READ THE PROMPTS CAREFULLY.
echo.
echo   Is this the first run of this sync profile?
echo   FIRST RUN ONLY : --resync builds the baseline state file.
echo   Never use on subsequent runs -- forces full re-comparison
echo   and may cause data duplication or loss.
echo.
set "FIRSTRUN="
set /p FIRSTRUN=Use --resync flag? [y/n/q, default N]: 

if not "%FIRSTRUN%"=="" set "FIRSTRUN=%FIRSTRUN:~0,1%"
if /i "%FIRSTRUN%"=="Y" goto ASKDELETE
if /i "%FIRSTRUN%"=="Q" goto END
goto ASKDELETE


:ASKCONFIRMRESYNC

if not "%SILENT%"=="1" goto ASKCONFIRM_INTERACTIVE
if /I "%SILENT_DEFAULT_RESYNC%"=="Y" goto ASKCONFIRM_SILENT_RESYNC
set "FIRSTRUN="
goto ASKDELETE

:ASKCONFIRM_SILENT_RESYNC
set "FIRSTRUN=Y"
goto ASKDELETE

:ASKCONFIRM_INTERACTIVE
echo.
echo   A tracer file discrepancy was detected above.
echo   Please review the warning and confirm your sync mode.
echo.
set "FIRSTRUN="
set /p FIRSTRUN=Confirm --resync flag? [y/n/q, default N]: 

if not "%FIRSTRUN%"=="" set "FIRSTRUN=%FIRSTRUN:~0,1%"
if /i "%FIRSTRUN%"=="Y" goto ASKDELETE
if /i "%FIRSTRUN%"=="Q" goto END
goto ASKDELETE


:ASKDELETE

echo.
if "%SILENT%"=="1" goto ASKDELETE_SILENT

set "CUR_MAXDELETE=%MAXDELETE%"
set /p "CUR_MAXDELETE=Max safe delete percentage (1-100) [ENTER = %MAXDELETE%]: "
if "%CUR_MAXDELETE%"=="" (
    rem user hit Enter: keep existing MAXDELETE
) else (
    set "MAXDELETE=%CUR_MAXDELETE%"
)
goto VALIDATE

:ASKDELETE_SILENT
set "MAXDELETE=%SILENT_DEFAULT_MAXDELETE%"
echo  %DIM%Silent mode: MAXDELETE auto-set to %MAXDELETE%% (global default).%RST%
goto VALIDATE


:VALIDATE

for /f "delims=0123456789" %%A in ("%MAXDELETE%") do (
    echo.
    echo  WARNING : Invalid input. Please enter a whole number between 1 and 100.
    echo.
    goto ASKDELETE
)
set /a MAXDELETE=%MAXDELETE%
goto RANGECHECK

:RANGECHECK

if %MAXDELETE% LSS 1 goto RANGEERROR
if %MAXDELETE% GTR 100 goto RANGEERROR
goto ROUTERUN

:RANGEERROR
echo.
echo  WARNING : Value out of range. Please enter a number between 1 and 100.
echo.
goto ASKDELETE


:ROUTERUN

if /i "%FIRSTRUN%"=="Y" goto FIRSTRUN
goto NORMALRUN


REM ============================================================
REM  FIRST RUN (--resync)
REM ============================================================
:FIRSTRUN

set "SYNC_MODE_LABEL=First Run (--resync)"

echo.
echo  First run selected -- running with --resync flag...
echo  Safety delete limit: %MAXDELETE%%%
echo  Tracer mode: %TRACER_MODE%
if "%SILENT%"=="1" echo  Silent mode: proceeding without prompts or pauses.
echo.

echo    %DIM%Writing lock files to Path 1 and Path 2...%RST%
call :WRITELOCK
if errorlevel 1 goto FIRSTRUN_LOCK_FAIL

echo    %DIM%Writing tracer to both paths [%TRACER_MODE%]...%RST%
call :WRITETRACER1
if errorlevel 1 goto FIRSTRUN_TRACER_FAIL
echo.

rclone bisync "%SYNCPATH1%" "%SYNCPATH2%" ^
  --resync ^
  -P ^
  --exclude "_rclone.batch.bisync.*.lock.*" ^
  --exclude "_rclone.batch.bisync.*.tracer.*" ^
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

set "RCLONE_EXIT=%ERRORLEVEL%"

call :REMOVELOCK
call :WRITETRACER1

echo.
if "%RCLONE_EXIT%"=="0" goto SYNC_OK
echo    %WARN%  [ WARN  ]  rclone reported errors (exit code %RCLONE_EXIT%).%RST%
echo    %WARN%             Next run will detect tracer state and prompt accordingly.%RST%
goto HANDLE_RCLONE_FAILURE

:FIRSTRUN_LOCK_FAIL
echo.
echo    %ERR%  [ ERROR ]  Lock file write failed. Aborting.%RST%
echo.
goto END_FAILURE

:FIRSTRUN_TRACER_FAIL
echo.
echo    %ERR%  [ ERROR ]  Pre-sync tracer write failed. Aborting.%RST%
echo.
call :REMOVELOCK
goto END_FAILURE


REM ============================================================
REM  NORMAL RUN
REM ============================================================
:NORMALRUN

set "SYNC_MODE_LABEL=Normal Run"

echo.
echo  Normal run -- syncing without --resync...
echo  Safety delete limit: %MAXDELETE%%%
echo  Tracer mode: %TRACER_MODE%
if "%SILENT%"=="1" echo  Silent mode: proceeding without prompts or pauses.
echo.

echo    %DIM%Writing lock files to Path 1 and Path 2...%RST%
call :WRITELOCK
if errorlevel 1 goto NORMALRUN_LOCK_FAIL

echo    %DIM%Writing tracer to both paths [%TRACER_MODE%]...%RST%
call :WRITETRACER1
if errorlevel 1 goto NORMALRUN_TRACER_FAIL
echo.

rclone bisync "%SYNCPATH1%" "%SYNCPATH2%" ^
  -P ^
  --exclude "_rclone.batch.bisync.*.lock.*" ^
  --exclude "_rclone.batch.bisync.*.tracer.*" ^
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

set "RCLONE_EXIT=%ERRORLEVEL%"

call :REMOVELOCK
call :WRITETRACER1

echo.
if "%RCLONE_EXIT%"=="0" goto SYNC_OK
echo    %WARN%  [ WARN  ]  rclone reported errors (exit code %RCLONE_EXIT%).%RST%
echo    %WARN%             Next run will detect tracer state and prompt accordingly.%RST%
goto HANDLE_RCLONE_FAILURE

:NORMALRUN_LOCK_FAIL
echo.
echo    %ERR%  [ ERROR ]  Lock file write failed. Aborting.%RST%
echo.
goto END_FAILURE

:NORMALRUN_TRACER_FAIL
echo.
echo    %ERR%  [ ERROR ]  Pre-sync tracer write failed. Aborting.%RST%
echo.
call :REMOVELOCK
goto END_FAILURE


REM ============================================================
REM  SYNC SUCCESS
REM ============================================================
:SYNC_OK
echo    %OK%  [ OK    ]  Sync complete.%RST%
set "ABORT_COUNT=0"
goto END


REM ============================================================
REM  RCLONE FAILURE HANDLER
REM ============================================================
:HANDLE_RCLONE_FAILURE

set /a ABORT_COUNT=%ABORT_COUNT%+1
echo.
echo    %WARN%  Consecutive abort count: %ABORT_COUNT% / %MAX_ABORT_RETRIES%%RST%

if %ABORT_COUNT% GEQ %MAX_ABORT_RETRIES% goto FATAL_ABORT
goto END

:FATAL_ABORT
echo.
echo    %ERR%  [ FATAL ]  Reached max consecutive abort retries (%MAX_ABORT_RETRIES%).%RST%
echo    %ERR%             Exiting with code 1 so service manager can restart.%RST%
echo.
exit /b 1


REM ============================================================
REM  LOCK WAIT
REM ============================================================
:LOCK_WAIT
echo.
echo    %WARN%[ LOCKED ]%RST%  Another sync instance is active on %LOCK_WAIT_MSG%.
echo    %WARN%           Lock : %FOREIGN_LOCK_NAME%%RST%
echo    %WARN%           Waiting %TIMEOUT%s then retrying...%RST%
echo.
timeout /t %TIMEOUT% /nobreak >nul
goto MAIN_LOOP


REM ============================================================
REM  END (success / graceful stop)
REM ============================================================
:END
echo.
if not "%LOOP%"=="1" goto END_NLOOP
echo Loop mode enabled: waiting %TIMEOUT% seconds before next sync...
timeout /t %TIMEOUT% /nobreak >nul
goto MAIN_LOOP

:END_NLOOP
if not "%SILENT%"=="1" pause
goto :eof


REM ============================================================
REM  END_FAILURE (non-recoverable error)
REM ============================================================
:END_FAILURE
echo.
if not "%LOOP%"=="1" goto END_FAILURE_NLOOP
echo    %ERR%  Fatal error in service mode -- exiting with code 1 for service restart.%RST%
exit /b 1

:END_FAILURE_NLOOP
if not "%SILENT%"=="1" pause
exit /b 1


REM ============================================================
REM  SUBROUTINES
REM ============================================================


REM ============================================================
REM  CHECK_FOREIGN_LOCK_LINE "filename"
REM  Sets FOREIGN_LOCK_FOUND=1 and FOREIGN_LOCK_NAME if:
REM    * filename starts with LOCK_PREFIX
REM    * filename is NOT MY_LOCK_NAME
REM ============================================================
:CHECK_FOREIGN_LOCK_LINE
set "RAW_NAME=%~1"

if "%RAW_NAME%"=="" goto :eof
if "%RAW_NAME:~-1%"=="/" set "RAW_NAME=%RAW_NAME:~0,-1%"

echo "%RAW_NAME%" | findstr /b /c:"%LOCK_PREFIX%" >nul
if errorlevel 1 goto :eof

if /I "%RAW_NAME%"=="%MY_LOCK_NAME%" goto :eof

set "FOREIGN_LOCK_FOUND=1"
set "FOREIGN_LOCK_NAME=%RAW_NAME%"
goto :eof


REM ============================================================
REM  WRITELOCK
REM  Writes lock file to BOTH Path 1 and Path 2 before sync.
REM  Rolls back Path 1 if Path 2 upload fails.
REM ============================================================
:WRITELOCK

powershell -NoProfile -Command ^
  "$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss';" ^
  "$lines = @(" ^
  "  '============================================================'," ^
  "  ('  Lock File    : ' + $env:MY_LOCK_NAME)," ^
  "  ('  Created      : ' + $ts)," ^
  "  '============================================================'," ^
  "  ''," ^
  "  ('  Sync Profile : ' + $env:SYNCPROFILE)," ^
  "  ('  Host         : ' + $env:COMPUTERNAME)," ^
  "  ('  User         : ' + $env:USERNAME)," ^
  "  '============================================================'" ^
  ");" ^
  "$lines | Out-File -FilePath $env:LOCK_TEMP -Encoding ASCII -Force"

if errorlevel 1 goto WRITELOCK_PS_FAIL

rclone copyto "%LOCK_TEMP%" "%LOCK_PATH1%"
if errorlevel 1 goto WRITELOCK_P1_FAIL
echo    %OK%  [ OK    ]  Lock written : %LOCK_PATH1%%RST%

rclone copyto "%LOCK_TEMP%" "%LOCK_PATH2%"
if errorlevel 1 goto WRITELOCK_P2_FAIL
echo    %OK%  [ OK    ]  Lock written : %LOCK_PATH2%%RST%

del "%LOCK_TEMP%" >nul 2>&1
exit /b 0

:WRITELOCK_PS_FAIL
echo    %ERR%  [ ERROR ]  PowerShell failed to write lock temp file.%RST%
exit /b 1

:WRITELOCK_P1_FAIL
echo    %ERR%  [ ERROR ]  rclone failed to upload lock to Path 1.%RST%
echo    %ERR%             Remote : %LOCK_PATH1%%RST%
del "%LOCK_TEMP%" >nul 2>&1
exit /b 1

:WRITELOCK_P2_FAIL
echo    %ERR%  [ ERROR ]  rclone failed to upload lock to Path 2.%RST%
echo    %ERR%             Remote : %LOCK_PATH2%%RST%
rclone deletefile "%LOCK_PATH1%" >nul 2>&1
del "%LOCK_TEMP%" >nul 2>&1
exit /b 1


REM ============================================================
REM  REMOVELOCK
REM  Deletes lock file from both remotes after sync completes.
REM ============================================================
:REMOVELOCK

rclone deletefile "%LOCK_PATH1%" >nul 2>&1
echo    %INFO%  [ DEL   ]  %LOCK_PATH1% %RST%
rclone deletefile "%LOCK_PATH2%" >nul 2>&1
echo    %INFO%  [ DEL   ]  %LOCK_PATH2% %RST%
echo    %DIM%  [ DONE! ]  Lock files removed from both remotes.%RST%
exit /b 0
    

REM ============================================================
REM  WRITETRACER1
REM  FRESH  : delete existing tracers, write new file to Path 1.
REM  APPEND : download Path 1 tracer, append sync record,
REM           re-upload to Path 1.
REM  rclone bisync propagates tracer to Path 2 during the run.
REM ============================================================
:WRITETRACER1

if /i "%TRACER_MODE%"=="APPEND" goto WT1_APPEND

rclone deletefile "%TRACER_PATH1%" >nul 2>&1
rclone deletefile "%TRACER_PATH2%" >nul 2>&1

powershell -NoProfile -Command ^
  "$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss';" ^
  "$lines = @(" ^
  "  '============================================================'," ^
  "  ('  Tracer File  : ' + $env:MY_TRACER_NAME)," ^
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

if errorlevel 1 goto WT1_FRESH_PS_FAIL

rclone copyto "%TRACER_TEMP%" "%TRACER_PATH1%"
if errorlevel 1 goto WT1_FRESH_UPLOAD_FAIL
echo    %OK%  [ OK    ]  Tracer written : %TRACER_PATH1%%RST%

rclone copyto "%TRACER_TEMP%" "%TRACER_PATH2%"
if errorlevel 1 goto WT1_FRESH_UPLOAD_P2_FAIL
echo    %OK%  [ OK    ]  Tracer written : %TRACER_PATH2%%RST%

echo    %OK%  [ OK    ]  Tracer files created (FRESH) %RST%
del "%TRACER_TEMP%" >nul 2>&1
exit /b 0

:WT1_FRESH_PS_FAIL
echo    %ERR%  [ ERROR ]  PowerShell failed to write tracer temp file.%RST%
exit /b 1

:WT1_FRESH_UPLOAD_P2_FAIL
echo    %ERR%  [ ERROR ]  rclone failed to upload tracer to Path 2.%RST%
echo    %ERR%             Remote : %TRACER_PATH2%%RST%
del "%TRACER_TEMP%" >nul 2>&1
exit /b 1

:WT1_FRESH_UPLOAD_FAIL
echo    %ERR%  [ ERROR ]  rclone failed to upload tracer to Path 1.%RST%
echo    %ERR%             Remote : %TRACER_PATH1%%RST%
del "%TRACER_TEMP%" >nul 2>&1
exit /b 1


:WT1_APPEND

rclone copyto "%TRACER_PATH1%" "%TRACER_TEMP%"
if errorlevel 1 goto WT1_APPEND_DL_FAIL

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

if errorlevel 1 goto WT1_APPEND_PS_FAIL

rclone copyto "%TRACER_TEMP%" "%TRACER_PATH1%"
if errorlevel 1 goto WT1_APPEND_UPLOAD_FAIL
echo    %OK%  [ OK    ]  Tracer appended : %TRACER_PATH1%%RST%

rclone copyto "%TRACER_TEMP%" "%TRACER_PATH2%"
if errorlevel 1 goto WT1_APPEND_UPLOAD_P2_FAIL
echo    %OK%  [ OK    ]  Tracer appended : %TRACER_PATH2%%RST%

echo    %OK%  [ OK    ]  Tracer files appended (APPEND) %RST%
del "%TRACER_TEMP%" >nul 2>&1
exit /b 0

:WT1_APPEND_UPLOAD_P2_FAIL
echo    %ERR%  [ ERROR ]  rclone failed to upload appended tracer to Path 2.%RST%
echo    %ERR%             Remote : %TRACER_PATH2%%RST%
del "%TRACER_TEMP%" >nul 2>&1
exit /b 1

:WT1_APPEND_PS_FAIL
echo    %ERR%  [ ERROR ]  PowerShell failed to append sync record to tracer.%RST%
del "%TRACER_TEMP%" >nul 2>&1
exit /b 1

:WT1_APPEND_UPLOAD_FAIL
echo    %ERR%  [ ERROR ]  rclone failed to re-upload appended tracer.%RST%
echo    %ERR%             Remote : %TRACER_PATH1%%RST%
del "%TRACER_TEMP%" >nul 2>&1
exit /b 1


REM ============================================================
REM  OPTION REFERENCE (rclone bisync)
REM ============================================================
REM  --resync
REM    FIRST RUN ONLY -- builds the baseline file list.
REM    Required before bisync can track changes on both sides.
REM    WARNING: Never use on subsequent runs. Forces full
REM    re-comparison; may cause data duplication or loss.
REM
REM  -P / --progress
REM    Show real-time transfer progress in the console.
REM
REM  --exclude "_rclone.batch.bisync.*.lock.*"
REM  --exclude "_rclone.batch.bisync.*.tracer.*"
REM    Prevents lock and tracer management files from being
REM    treated as user data during bisync transfer.
REM
REM  --checkers 16
REM    Number of parallel file comparison threads.
REM
REM  --transfers 8
REM    Number of files to transfer simultaneously.
REM
REM  --conflict-loser num
REM    On conflict, losing file renamed with numeric suffix.
REM    Both copies preserved e.g. file(1).txt
REM    Options: num, pathname, delete
REM
REM  --max-lock 0
REM    Disables bisync lock file timeout.
REM    Prevents stale lock errors on interrupted syncs.
REM
REM  --max-delete PERCENT (default: 50)
REM    Safety threshold -- bisync aborts if more than this
REM    percentage of files would be deleted on either side.
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
