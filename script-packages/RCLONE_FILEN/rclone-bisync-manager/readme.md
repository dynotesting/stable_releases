# RClone Bisync Manager

**Version:** 2.5.6
**Author:** Dean N. ([dynotesting](https://github.com/dynotesting))
**Created:** 2026-03-02
**Updated:** 2026-03-17

> **Note:** As of v2.5.5 this script has been fully rewritten in native PowerShell. The original batch version (`.bat`) is retained for legacy reference only.

Bidirectional sync manager for `rclone bisync` that manages a two-way sync between local/remote paths, with extra safety checks using tracer files, lock files, and rclone's bisync state files.

The script prevents accidental data loss or duplication by validating both endpoints and the bisync state before each run, and by guiding you through a one-time `--resync` when required.

---

## Features

- Bidirectional sync between two remotes (e.g. Dropbox / Filen) using `rclone bisync`
- **Multi-machine lock system** ΓÇö scans both remotes for any active lock file before syncing; waits and retries if another machine is currently syncing
- Lock files written to **both** Path 1 and Path 2 before sync starts so all machines see the lock immediately
- Tracer file system to detect incomplete or corrupted sync runs; tracer uploaded directly to both remotes (not via bisync propagation)
- Post-sync tracer write completes **before** lock files are removed, ensuring other machines never see an unlocked but unfinished tracer state
- Lock and tracer files **excluded from bisync transfer** via `--exclude` filters so they are never treated as user data
- Validation of rclone bisync state files (`*.lst`) before running
- Interactive, silent, loop, and service modes
- **SERVICE mode** ΓÇö combined silent + loop for background/service execution
- **MAX_ABORT_RETRIES** ΓÇö after N consecutive bisync failures, exits with code 1 so a service manager (NSSM / Servy) can restart the process; counter resets on successful sync
- Configurable max delete safety percentage
- Structured logging to `C:\ProgramData\rclone-bisync-manager\` with daily log files
- UTF-8 console encoding enforced to prevent garbled output on machines with non-ASCII hostnames

---

## Requirements

- Windows 10 or later
- PowerShell 5.1 or later available in `PATH`
- `rclone` installed and available in `PATH`
- `Dropbox:` and `Filen:` remotes configured in rclone (see [rclone Remote Setup](#rclone-remote-setup) below)

---

## rclone Remote Setup

The `Dropbox:` and `Filen:` identifiers used in this script are **rclone remote names**, not Windows drive letters. They are defined in rclone's configuration file (`rclone.conf`) and require a one-time setup via `rclone config` on each machine that will run this script.

### Dropbox

Dropbox uses **OAuth2**. During setup, rclone opens a browser window, you log in to Dropbox and authorize the app, and rclone stores a refresh token in `rclone.conf`. That token refreshes silently on every subsequent run ΓÇö no user interaction needed after initial setup.

```powershell
rclone config
# Choose: New remote > name it "Dropbox" > type: dropbox > follow OAuth prompts
```

### Filen

Filen requires your account **email**, **password**, and an **API key**. Generate the API key first using the Filen CLI:

```powershell
filen-cli export-api-key
```

Then configure the remote:

```powershell
rclone config
# Choose: New remote > name it "Filen" > type: filen > enter email, password, API key
```

### Credential Storage

Both sets of credentials are stored (encrypted) in:

```
%APPDATA%\rclone\rclone.conf
```

Once configured, this script references `Dropbox:` and `Filen:` by name and rclone handles all authentication transparently in the background ΓÇö no credentials are needed in the script itself.

---

## Configuration

Edit these defaults directly in the script:

| Setting | Default | Description |
|---|---|---|
| Sync profile name | `Dropbox-FILEN_bisync` | Used in file naming and log output |
| Dropbox path | `Dropbox:1_Dropbox-FILEN_bisync` | rclone remote path for Path 1 |
| Filen path | `Filen:/Dropbox-FILEN_bisync` | rclone remote path for Path 2 |
| `$maxDelete` | `55` | Initial interactive default for max delete % |
| `$silentDefaultResync` | `N` | Silent/service mode resync default |
| `$silentDefaultMaxDelete` | `90` | Silent/service mode max delete % |
| `$timeoutSeconds` | `30` | Seconds between lock retries and loop cycles |
| `$maxAbortRetries` | `5` | Consecutive failures before service exit |

---

## Usage

```powershell
.\rclone-bisync-manager.ps1 [-silent] [-loop] [-service]
```

| Flag | Description |
|---|---|
| `-silent` | Non-interactive: no prompts, no pauses; uses configured defaults |
| `-loop` | Repeat sync cycle indefinitely until the process is terminated |
| `-service` | Combines `-silent` + `-loop` for background/service use |

Flags can be combined freely:

```powershell
.\rclone-bisync-manager.ps1 -silent -loop
.\rclone-bisync-manager.ps1 -service
```

### NSSM Service Registration

```powershell
nssm install rclone-bisync-manager powershell.exe `
    "-ExecutionPolicy Bypass -File C:\Scripts\rclone-bisync-manager.ps1 -service"
nssm set rclone-bisync-manager AppStdout C:\Logs\bisync.log
nssm set rclone-bisync-manager AppStderr C:\Logs\bisync-err.log
nssm start rclone-bisync-manager
```

### Servy Service Registration

See `servy-configuration.json` for a full example with recommended Windows Service settings.

```powershell
servy-cli install `
    --name "rclone-bisync-manager" `
    --path "powershell.exe" `
    --args "-ExecutionPolicy Bypass -File C:\Scripts\rclone-bisync-manager.ps1 -service" `
    --stdout "C:\Logs\bisync.log" `
    --stderr "C:\Logs\bisync-err.log"
servy-cli start --name "rclone-bisync-manager"
```

---

## File Naming Convention

All management files share the `rclone.batch.bisync.*` prefix so a single `--exclude` pattern family covers them all. Both file types are excluded from bisync transfer.

**Lock file** (active-sync mutex ΓÇö checked by all machines):

```
rclone.batch.bisync.<profile>.lock.<HOST>.<USER>.lock
```

Example:
```
rclone.batch.bisync.Dropbox-FILEN_bisync.lock.MSI-VECTOR.dynotesting.lock
```

- Written to **both** Path 1 and Path 2 before sync starts
- Removed from both paths only **after** the post-sync tracer write completes
- If Path 2 upload fails, Path 1 lock is rolled back to keep remotes consistent
- Excluded via: `--exclude "*rclone.batch.bisync.*.lock.*"`

**Tracer file** (persistent sync history log):

```
rclone.batch.bisync.<profile>.tracer.<HOST>.<USER>.tracer
```

Example:
```
rclone.batch.bisync.Dropbox-FILEN_bisync.tracer.MSI-VECTOR.dynotesting.tracer
```

- Uploaded directly to **both** Path 1 and Path 2 (FRESH on first run, APPEND on subsequent runs)
- Does **not** rely on bisync propagation since tracer files are excluded from bisync transfer
- Used to verify both sides are initialized and that byte counts match
- Written **before** lock removal so remotes are never in an inconsistent state
- Excluded via: `--exclude "*rclone.batch.bisync.*.tracer.*"`

---

## bisync State Files

rclone stores bisync state on the local machine. The script checks for these files before every run and prompts for `--resync` if they are missing:

```
%LOCALAPPDATA%\rclone\bisync\
  Dropbox_1_Dropbox-FILEN_sync..Filen__Dropbox-FILEN_sync.path1.lst
  Dropbox_1_Dropbox-FILEN_sync..Filen__Dropbox-FILEN_sync.path2.lst
```

If either `.lst` file is absent, bisync cannot track changes and a `--resync` first run is required.

---

## rclone Flags Reference

| Flag | Value | Purpose |
|---|---|---|
| `--resync` | *(first-run only)* | Builds baseline `.lst` state files. **Never use on subsequent runs** ΓÇö forces full re-comparison and may cause data duplication or loss. |
| `--exclude` | `"*rclone.batch.bisync.*.lock.*"` | Excludes all lock files from bisync transfer |
| `--exclude` | `"*rclone.batch.bisync.*.tracer.*"` | Excludes all tracer files from bisync transfer |
| `-P` | ΓÇö | Show real-time transfer progress in the console |
| `--checkers` | `16` | Parallel file comparison threads |
| `--transfers` | `8` | Files transferred simultaneously |
| `--conflict-loser` | `num` | On conflict, losing file renamed with numeric suffix (e.g. `file(1).txt`) ΓÇö both copies preserved |
| `--max-lock` | `0` | Disables bisync lock file timeout; prevents stale lock errors on interrupted syncs |
| `--max-delete` | `MAXDELETE%` | Safety threshold ΓÇö bisync aborts if more than this percentage of files would be deleted on either side; range 1-100 |
| `--multi-thread-cutoff` | `64M` | Files larger than 64 MB use multi-threaded download |
| `--multi-thread-streams` | `8` | Concurrent threads per large-file transfer |
| `--multi-thread-chunk-size` | `8M` | Chunk size per multi-thread transfer |
| `--fast-list` | ΓÇö | Lists remotes in bulk to reduce API calls and rate-limiting risk |
| `--use-server-modtime` | ΓÇö | Uses server-reported modification time instead of file hashes; faster, less CPU/API overhead |
| `--buffer-size` | `32M` | In-memory read buffer per active file transfer |

---

## Logging

Log files are written to:

```
C:\ProgramData\rclone-bisync-manager\YYYY-MM-DD_rclone-bisync-manager.log
```

Each log entry is timestamped with one of the following level tags:

| Tag | Meaning |
|---|---|
| `[INFO]` | Normal activity and status messages |
| `[WARN]` | Non-fatal issues: lock detected, tracer mismatch, rclone errors |
| `[ERROR]` | Failures that prevented a sync step from completing |
| `[FILE]` | Dedicated file operation entries (lock/tracer writes and deletions) |

A session divider (`=` x 80) is written to the log at the end of each run.

---

## Version History

### v2.5.6 (2026-03-17)

- Post-sync cleanup order corrected: tracer APPEND write now runs **before** `Invoke-RemoveLock`; lock files remain in place until the post-sync tracer write completes, preventing other machines from syncing against an unfinished tracer state
- Removed all non-ASCII characters from script structure and strings to prevent PS 5.1 service host parse errors
- Replaced double-dash strings inside `Write-Host` and `Write-Log` calls with safe equivalents to prevent PS 5.1 unary operator misparse
- Confirmed working end-to-end under PowerShell 5.1 and 7.x

### v2.5.5 (2026-03-17)

- **Full rewrite in native PowerShell.** Converted from `rclone-bisync-manager.bat` v2.5.5
- Eliminated all CMD parse workarounds: ANSI codes in `()` blocks, `goto` spaghetti, `errorlevel` chains, and subprocess `powershell -Command` file writes
- Fixed `--exclude` patterns: added leading wildcard (`*rclone.batch.bisync.*`) so lock and tracer files are properly excluded at any path depth
- Fixed exit code capture: `Invoke-RcloneBisync` writes exit code directly to `$script:rcloneExitCode` immediately after rclone returns, bypassing output stream contamination
- Fixed console encoding: `[Console]::OutputEncoding` set to UTF-8 at startup
- Fixed variable-colon parser errors: all log strings with variables followed by `:` now use `${varName}` syntax
- `[CmdletBinding()]` / `param()` block moved to line 1 as required by PowerShell parser
- `Write-Host -ForegroundColor` replaces raw ANSI escape code injection
- `Out-File` / `Add-Content` replace subprocess PowerShell `-Command` file writes
- `ConvertFrom-Json` replaces `findstr`/`tokens` parsing of `rclone size --json`
- `while($true)` loop replaces `goto MAIN_LOOP`
- Structured logging via `Write-Log` / `Write-Log-File` / `Write-LogDivider` integrated into all key operations
- Data folder and daily log file auto-created under `C:\ProgramData\rclone-bisync-manager`

### v2.5.4 (2026-03-17)

- `WRITETRACER1` now explicitly uploads tracer to **both** Path 1 and Path 2 directly (FRESH and APPEND modes); tracer no longer relies on bisync propagation
- Fixed unreachable `WT1_FRESH_PS_FAIL` label ordering

### v2.5.3 (2026-03-17)

- Eliminated ALL remaining `()` blocks containing ANSI color variables; every conditional branch that echoes color output is now a flat goto label
- Fixed `:NORMALRUN`, `:HANDLE_RCLONE_FAILURE`, `:END`, and `:END_FAILURE` blocks that were still using `if/else ()` form causing `". was unexpected"` errors

### v2.5.2 (2026-03-17)

- Lock files now written to **both** Path 1 and Path 2 before sync starts
- Lock and tracer files excluded from bisync transfer via `--exclude` filters
- `WRITELOCK` rolls back Path 1 lock if Path 2 upload fails

### v2.5.1 (2026-03-17)

- Added explicit SERVICE mode flag for clearer mode reporting
- Fixed CMD parse errors caused by nested `IF` blocks and ANSI escape sequences inside `()` blocks
- Flattened all silent-mode routing to labeled gotos

### v2.5 (2026-03-17)

- Separated tracer files (sync history log) from lock files (active-sync mutex)
- Lock files use a shared prefix so any machine can detect an active sync
- Added `MAX_ABORT_RETRIES`: exits with code 1 after N consecutive failures for NSSM/Servy auto-restart
- LOOP mode resets abort counter on each successful sync
- Foreign lock detected: always wait + retry, never abort

### v2.4 (2026-03-02)

- Simplified tracer discrepancy handling to avoid CMD parse errors
- Flattened silent-mode discrepancy routing into separate labels

### v2.3 (2026-03-02)

- Added tracer file presence and size checks on both endpoints
- Integrated bisync state file validation and explicit RESYNC guidance
- Added silent, service, and loop modes with configurable defaults
- Enhanced tracer file format to include sync run history and environment metadata
- Improved validation for the max delete safety percentage
