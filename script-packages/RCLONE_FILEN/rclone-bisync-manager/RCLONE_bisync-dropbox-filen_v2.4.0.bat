@echo off
REM ============================================================
set "SCRIPT_NAME=rclone-bisync-manager"
REM  Version    : 2.4.0
set "SCRIPT_VERSION=2.4.0"
REM  Author     : Dean N. [dynotesting]
REM  Date Coded : 2026-03-02
REM  Purpose    : Bidirectional sync between Dropbox and Filen
REM               cloud storage using rclone bisync.
REM
REM               Includes tracer file management to verify both
REM               sync endpoints are properly initialized before
REM               any sync operation is attempted.
REM
REM               Supports:
REM                 /silent  - Non-interactive: no prompts, no pauses,
REM                            uses configured defaults.
REM                 /loop    - Repeat sync cycle until process is terminated.
REM                 /service - Same as /silent + /loop (service-style mode).
REM
REM  Notes v2.4 : - Simplified discrepancy handling and silent-mode routing
REM                 to avoid CMD \"was unexpected at this time\" parse errors.
REM               - Discrepancy messages are now printed with flat flow and
REM                 no nested IF blocks.
REM ============================================================



REM ============================================================
REM  SILENT / LOOP DEFAULTS (GLOBAL)
REM ============================================================
set "SILENT_DEFAULT_RESYNC=N"
set "SILENT_DEFAULT_MAXDELETE=90"



REM ============================================================
REM  MODE DETECTION (no %* inside FOR, no blocks)
REM ============================================================
set "SILENT=0"
set "LOOP=0"
set "TIMEOUT=10"
set "MAXDELETE=55"


:PARSEARGS
if "%~1"=="" goto ARGS_DONE

if /I "%~1"=="/silent"  set "SILENT=1"
if /I "%~1"=="-silent"  set "SILENT=1"

if /I "%~1"=="/loop"    set "LOOP=1"
if /I "%~1"=="-loop"    set "LOOP=1"

if /I "%~1"=="/service" (
    set "SILENT=1"
    set "LOOP=1"
)
if /I "%~1"=="-service" (
    set "SILENT=1"
    set "LOOP=1"
)

shift
goto PARSEARGS


:ARGS_DONE

if "%SILENT%"=="1" (
    echo Silent mode enabled: running with no prompts, no pauses. Defaults: RESYNC=%SILENT_DEFAULT_RESYNC%, MAXDELETE=%SILENT_DEFAULT_MAXDELETE%%%.
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
REM  MAIN LOOP ENTRY
REM ============================================================
:MAIN_LOOP



REM ============================================================
REM  TRACER FILE CHECK
REM ============================================================
:TRACERCHECK

set "TRACER_NAME=_rclone.batch.bisync.%SYNCPROFILE%.host.%COMPUTERNAME%.%USERNAME%.tracer"
set "TRACER_PATH1=%SYNCPATH1%/%TRACER_NAME%"
set "TRACER_PATH2=%SYNCPATH2%/%TRACER_NAME%"
set "TRACER_TEMP=%TEMP%\%TRACER_NAME%"

echo.
echo ============================================================
echo      %SCRIPT_NAME% v%SCRIPT_VERSION%
echo ============================================================
echo.

if "%SILENT%"=="1" goto SHOW_SILENT_MODE
goto SHOW_INTERACTIVE_MODE

:SHOW_SILENT_MODE
echo  %DIM%Mode    : SILENT (no prompts, no pauses)%RST%
echo  %DIM%Defaults: RESYNC=%SILENT_DEFAULT_RESYNC%  MAXDELETE=%SILENT_DEFAULT_MAXDELETE%%% %RST%
goto MODE_DONE

:SHOW_INTERACTIVE_MODE
echo  %DIM%Mode    : INTERACTIVE%RST%

:MODE_DONE

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

set "T1=0"
for /f "delims=" %%i in ('rclone lsf "%TRACER_PATH1%" 2^>nul') do set "T1=1"

set "T2=0"
for /f "delims=" %%i in ('rclone lsf "%TRACER_PATH2%" 2^>nul') do set "T2=1"

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

if "%T1%"=="1" if "%T2%"=="1" goto CHECKSIZES

if "%T1%"=="0" if "%T2%"=="0" (
    echo    %DIM%No tracer files found.%RST%
    echo    %DIM%Tracers will be created when the sync executes.%RST%
    echo.
    goto ASK
)

REM ============================================================
REM  DISCREPANCY CASES – ULTRA SIMPLE MESSAGES
REM ============================================================

if "%T1%"=="1" if "%T2%"=="0" (
    echo.
    echo Previous sync may have been interrupted before completion. Use RESYNC once to rebuild the baseline state.
    echo.
    goto AFTER_DISCREPANCY
)

if "%T1%"=="0" if "%T2%"=="1" (
    echo.
    echo Corrupted tracer state: Path 2 has a tracer but Path 1 does not. Use RESYNC once to rebuild the baseline and fix this state.
    echo.
    goto AFTER_DISCREPANCY
)



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

echo.
echo Tracer byte counts differ (%SIZE1% vs %SIZE2%). Consider using RESYNC once to rebuild the bisync baseline state.
echo.
goto AFTER_DISCREPANCY



:CHECKSTATE

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
    echo.
    echo rclone bisync state files are missing. RESYNC is required for initial sync or recovery. State dir: %BISYNC_DIR%.
    echo.
    goto AFTER_DISCREPANCY
)

echo    %OK%[ READY   ]%RST%  All checks passed -- tracer mode set to APPEND.
echo    %OK%[ READY   ]%RST%  Skipping --resync prompt, defaulting to normal run.
echo.
set "TRACER_MODE=APPEND"
set "FIRSTRUN="
goto ASKDELETE



:AFTER_DISCREPANCY
if "%SILENT%"=="1" goto SILENT_DISCREPANCY

echo    Continuing in 2 seconds...
timeout /t 2 /nobreak >nul
echo.
goto ASKCONFIRMRESYNC



REM ============================================================
REM  SILENT-MODE DISCREPANCY ROUTING (FLAT, NO NESTED IF)
REM ============================================================
:SILENT_DISCREPANCY
if /I "%SILENT_DEFAULT_RESYNC%"=="Y" goto SILENT_DISC_RESYNC
goto SILENT_DISC_NORMAL

:SILENT_DISC_RESYNC
echo Silent mode: auto-selecting FIRST RUN (--resync) after discrepancy.
set "FIRSTRUN=Y"
goto ASKDELETE

:SILENT_DISC_NORMAL
pause
echo Silent mode: auto-selecting NORMAL sync (no --resync) after discrepancy.
set "FIRSTRUN="
goto ASKDELETE



REM ============================================================
REM  SYNC PROMPTS
REM ============================================================
:ASK

if "%SILENT%"=="1" (
    if /I "%SILENT_DEFAULT_RESYNC%"=="Y" (
        echo  %DIM%Silent mode: assuming FIRST RUN (--resync) on first-run path.%RST%
        set "FIRSTRUN=Y"
    ) else (
        echo  %DIM%Silent mode: assuming NORMAL run (no --resync) on first-run path.%RST%
        set "FIRSTRUN="
    )
    goto ASKDELETE
)

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

if "%SILENT%"=="1" (
    if /I "%SILENT_DEFAULT_RESYNC%"=="Y" (
        set "FIRSTRUN=Y"
    ) else (
        set "FIRSTRUN="
    )
    goto ASKDELETE
)

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
echo  %DIM%Silent mode: MAXDELETE auto-set to %MAXDELETE%%% (global default). %RST%
goto VALIDATE



:VALIDATE

for /f "delims=0123456789" %%A in ("%MAXDELETE%") do (
    echo.
    echo  %WARN%  WARNING : Invalid input. Please enter a whole number between 1 and 100.%RST%
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
echo  %WARN%  WARNING : Value out of range. Please enter a number between 1 and 100.%RST%
echo.
goto ASKDELETE



:ROUTERUN

if /i "%FIRSTRUN%"=="Y" goto FIRSTRUN
goto NORMALRUN



:FIRSTRUN

set "SYNC_MODE_LABEL=First Run (--resync)"

echo.
echo  First run selected -- running with --resync flag...
echo  Safety delete limit: %MAXDELETE%%%
echo  Tracer mode: %TRACER_MODE%
if "%SILENT%"=="1" echo  %DIM%Silent mode: proceeding without prompts or pauses.%RST%
echo.

echo    %DIM%Writing pre-sync tracer to Path 1 [%TRACER_MODE%]...%RST%
call :WRITETRACER1
if errorlevel 1 (
    echo.
    echo    %ERR%  [ ERROR ]  Pre-sync tracer write failed. Aborting.%RST%
    echo.
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

set "SYNC_MODE_LABEL=Normal Run"

echo.
echo  Normal run -- syncing without --resync...
echo  Safety delete limit: %MAXDELETE%%%
echo  Tracer mode: %TRACER_MODE%
if "%SILENT%"=="1" echo  %DIM%Silent mode: proceeding without prompts or pauses.%RST%
echo.

echo    %DIM%Writing pre-sync tracer to Path 1 [%TRACER_MODE%]...%RST%
call :WRITETRACER1
if errorlevel 1 (
    echo.
    echo    %ERR%  [ ERROR ]  Pre-sync tracer write failed. Aborting.%RST%
    echo.
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
if "%LOOP%"=="1" (
    echo Loop mode enabled: waiting %TIMEOUT% seconds before next sync...
    timeout /t %TIMEOUT% /nobreak >nul
    goto MAIN_LOOP
)

if not "%SILENT%"=="1" pause
goto :eof



REM ============================================================
REM  SUBROUTINES
REM ============================================================
:WRITETRACER1

if /i "%TRACER_MODE%"=="APPEND" goto WT1_APPEND

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
REM  OPTION REFERENCE (rclone bisync)
REM ============================================================
REM  --resync
REM    FIRST RUN ONLY -- builds the baseline file list.
REM    Required before bisync can track changes on both sides.
REM    WARNING: Never use on subsequent runs. It forces a full
REM    re-comparison and may cause data duplication or loss.
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
