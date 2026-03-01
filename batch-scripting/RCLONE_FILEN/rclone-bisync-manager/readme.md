# rclone-bisync-manager v1.8

A Windows CMD batch script for safe, guided bidirectional sync between
two rclone remotes using `rclone bisync`. Built around a tracer file
checkpoint system that detects incomplete or corrupted sync states before
rclone is ever invoked.

Configured for Dropbox <-> Filen cloud sync but works with any two rclone
remotes.

Note:

For easy remote source/destination path setup, RcloneBrowser may be used to identify the path variables. [copy from upload/download dialog]
https://github.com/kapitainsky/RcloneBrowser
Credit to kapitainsky

This is a work in progress !

-Please backup all your data before executing this script. 
-Run as ADMIN if encounting permission errors.
-Recommnd small dataset test folder setup prior to full drive/cloud sync.

---

## Features

- **Tracer file checkpoint system** — small marker files written to each
  remote confirm that both endpoints were initialized together and that
  the last sync completed successfully
- **Append mode run history** — on healthy runs, each tracer file is
  updated with a timestamped record of every sync run, preserving full
  history without recreating the file
- **rclone state file detection** — proactively checks for rclone's own
  `.path1.lst` / `.path2.lst` baseline files before invoking bisync,
  preventing the cryptic `must run --resync to recover` critical error
- **Guided `--resync` prompts** — context-aware messaging tells you
  exactly *why* you're being asked, with different prompt text depending
  on the discrepancy type detected
- **Safe delete threshold** — configurable `--max-delete` percentage
  prevents runaway deletes from network issues or accidental mass deletion
- **ANSI color output** — warnings in yellow, errors in red, success in
  green; degrades gracefully to plain text if ANSI is unavailable
- **Input validation** — two-stage numeric validation with leading zero
  normalization for all numeric prompts

---

## Requirements

- Windows 10 1511+ (for ANSI color support)
- [rclone](https://rclone.org/downloads/) installed and in PATH
- Two configured rclone remotes (Dropbox, Filen, or any supported backend)
- PowerShell (included with Windows — used for tracer file writes only)

---

## Configuration

Edit the sync profile variables at the top of the script:

```batch
set "SYNCPROFILE=Dropbox-FILEN_bisync"
set "SYNCNAME=Dropbox <-> Filen Sync 2 way bidirectional"
set "SYNCPATH1=Dropbox:1_Dropbox-FILEN_sync"
set "SYNCPATH2=Filen:/Dropbox-FILEN_sync"

## Version

Version	Date	    Summary
v1.1	2026-03-01	Initial release — --resync prompt, --max-delete safety input
v1.2	2026-03-01	Tracer file system; fixed SET /A validation; quoted SET syntax; fixed ^ continuation bug
v1.3	2026-03-01	Byte count check; rclone state file detection; ANSI colors; auto-skip --resync
v1.4	2026-03-01	Checkpoint write timing; APPEND mode run history; CALL :label subroutines
v1.5	2026-03-01	Removed manual Path 2 write — rclone bisync syncs it automatically
v1.6	2026-03-01	Fixed rclone lsf --format "s" returning 0 on Dropbox; switched to rclone size --json
v1.7	2026-03-01	Fixed false positive tracer detection; switched to exact-path rclone lsf
v1.8	2026-03-01	Fixed leading-zero input bypass; SET /A normalization; script name + version banner