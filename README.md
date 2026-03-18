# stable_releases

**GitHub URL:** https://github.com/dynotesting/stable_releases  
**README last updated:** 2026-03-17

A collection of stable, tested scripts and utilities ready for general use.

All releases in this repository have been personally tested and are considered
production-ready. Work-in-progress and experimental builds are developed
separately before being promoted here.

A FAIR WARNING: All scripts are provided as-is.

Fine Print:
Some scripts interact with files, cloud storage, network resources, or system
configuration. Misuse, misconfiguration, or unexpected environment differences
could result in unintended behavior including **data loss or corruption**.

Backup your data :)

---

## Platform

**Designed for Windows 10 / Windows 11.**

Scripts are written for the Windows CMD batch environment and should be
compatible with most standard Windows batch terminals. Where PowerShell is
used, PowerShell Core 7+ is assumed but Windows PowerShell 5.1 (built into
Windows 10/11) will work for most scripts unless otherwise noted in the
individual project README.

---

## Repository Structure

<!-- FILE-TREE-START -->
### `script-packages/`

- **`Create-AppShortcut/`** — Scans installed Microsoft Store apps and creates a Desktop shortcut for the selected app.
  - `Create-AppShortcut.ps1`
  - `readme.md`

- **`RCLONE_FILEN/rclone-bisync-manager/`** — Bidirectional sync manager for rclone bisync between Dropbox and Filen, with tracer files, lock file handling, and loop/service mode.
  - `RCLONE_bisync-dropbox-filen_v1.8.bat` *(legacy)*
  - `RCLONE_bisync-dropbox-filen_v2.4.0.bat` *(legacy)*
  - `rclone-bisync-manager_v2.5.5.bat` *(legacy)*
  - `rclone-bisync-manager_v2.5.6.ps1` *(current stable)*
  - `servy-configuration.json`
  - `batch-powershell_efficiency-comparison.md`
  - `readme.md`

- **`Scryfall-MTG-Exporter/`** — Exports Magic: The Gathering card data from Scryfall API.
  - `Scryfall-MTG-Exporter.ps1`
  - `readme.md`
<!-- FILE-TREE-END -->

---

## Technology Stack

<!-- LINE-COUNT-START -->
**Languages and file types:**
- PowerShell (.ps1) — 3 files, 1,871 lines
- Batch scripts (.bat) — 3 files, 2,502 lines
- JSON — 1 file

**Total source lines:** 4,373
<!-- LINE-COUNT-END -->

**Development tools:**
- Visual Studio Code
- PowerShell 5.1+
- rclone

---

## Contents

Each project lives in its own subfolder with its own README covering
requirements, configuration, and usage. Check the individual project README
before running anything.

---

## General Requirements

- Windows 10 or Windows 11
- Any standard Windows CMD terminal or Windows Terminal
- Project-specific dependencies listed in each subfolder README

---

## Notes

- Scripts are released here only after testing on real hardware
- Each project is versioned independently
- Bug reports and suggestions welcome via GitHub Issues

---

## Disclaimer

All scripts in this repository have been personally tested on real hardware
and are released here only after being confirmed stable with no known bugs
at the time of release.

**However, all scripts are provided as-is. Author is not liable for data loss.**
Some scripts interact with files, cloud storage, network resources, or system
configuration. Misuse, misconfiguration, or unexpected environment differences
could result in unintended behavior including **data loss or corruption**.

You are responsible for:
- Reading the project README fully before running any script
- Ensuring your configuration matches your environment
- Maintaining your own backups of any data that matters to you

If you are unsure about what a script does, review the source code before
running it. All scripts in this repository are fully open and readable.

## License

MIT — free to use, modify, and distribute. Credit appreciated but not required.
