# RCLONE Bisync Manager

Version: 2.4.0  
Author: Dean N. (dynotesting)  
Date: 2026‑03‑02

Batch wrapper for `rclone bisync` that manages a two‑way sync between Dropbox and Filen, with extra safety checks using tracer files and rclone’s bisync state files.

The script is designed to prevent accidental data loss or duplication by validating both endpoints and the bisync state before each run, and by guiding you when a one‑time `--resync` is required.

## Features

- Bidirectional sync between a Dropbox path and a Filen path using `rclone bisync`
- Tracer file system to detect incomplete or corrupted sync runs
- Validation of rclone bisync state files (`*.lst`) before running
- Interactive and silent modes
- Optional loop/service mode for repeated runs
- Configurable max delete safety percentage
- Simplified discrepancy handling and silent‑mode routing to avoid fragile CMD parsing edge cases

## Requirements

- Windows 10 (or later)
- rclone` installed and configured with:  
  `Dropbox:` remote  
  `Filen:` remote
- PowerShell available in `PATH` (used to build tracer file content)
- Command prompt with ANSI escape support (for colored output), or a terminal that supports ANSI (for example, Windows Terminal)

## Configuration

Built‑in defaults (change directly in the script if desired):

- **Sync profile name**  
  `Dropbox-FILEN_bisync`

- **Dropbox path**  
  `Dropbox:1_Dropbox-FILEN_bisync`

- **Filen path**  
  `Filen:/Dropbox-FILEN_bisync`

- **Initial `MAXDELETE` default**  
  `55`

- **Silent mode defaults**  
  ```bat
  set "SILENT_DEFAULT_RESYNC=N"
  set "SILENT_DEFAULT_MAXDELETE=90"
  ```

## Version History
v2.4 (2026-03-02)

-Simplified tracer discrepancy handling to avoid CMD “was unexpected at this time” parse errors.
-Flattened silent-mode discrepancy routing into separate labels instead of nested IF blocks.
-Kept tracer presence/size/state checks and RESYNC guidance intact while reducing parser-sensitive formatting.
-Left rclone bisync options and safety parameters (MAXDELETE, --resync first-run logic) unchanged.

v2.3 (2026-03-02)
-Added comprehensive tracer file presence and size checks on both endpoints.
-Integrated rclone bisync state file validation and explicit RESYNC guidance.
-Implemented detailed discrepancy warnings explaining risks and recommended actions.
-Added silent and service modes with configurable RESYNC and MAXDELETE defaults.
-Added loop mode with configurable timeout between runs.
-Enhanced tracer file format to include sync run history and environment metadata.
-Improved validation for the max delete safety percentage.