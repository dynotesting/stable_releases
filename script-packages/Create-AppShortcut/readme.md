# Microsoft Store App Shortcut Creator

Version: 1.2.0  
Author: Dean N. (dynotesting)  
Date: 2026-03-13

Interactive PowerShell script that scans installed Microsoft Store apps and creates a Desktop shortcut for the selected app using the Windows-native `shell:AppsFolder` launch method.

Shortcut target is `powershell.exe` calling `Start-Process 'shell:AppsFolder\<AppUserModelId>'` — the same pattern Windows uses internally for Store app shortcuts. No byte-patching or elevated rights required to create the shortcut; if Admin mode is selected, UAC appears only at launch time via `-Verb RunAs`.

## Features

- Enumerates Store apps that expose at least one real `.exe` in their install folder
- Displays a numbered alphabetical list — select by number or type the app name
- Resolves `AppUserModelId` (`<PackageFamilyName>!<AppId>`) from `AppxManifest.xml`, with `<PackageFamilyName>!App` fallback
- Optional **Run as Administrator** mode via `Start-Process -Verb RunAs`
- Shortcut named `<AppName> Shortcut.lnk` or `<AppName> ADMIN Shortcut.lnk`
- Post-write existence check confirms the file was created successfully

## Requirements

- Windows 10 / Windows 11
- Windows PowerShell 5.1+ (no PS7 / pwsh required)
- Standard user privileges (no elevation needed to run the script)

## Quick Start

```powershell
.\Create-AppShortcut.ps1
```

1. A numbered list of installed Store apps appears
2. Enter a number or type the app name (case and whitespace ignored)
3. Confirm your selection
4. Choose whether to enable **Run as Administrator**
5. A `.lnk` file is written to your Desktop

## Version History

v1.2.0 (2026-03-13)

- Replaced `explorer.exe` shortcut target with `powershell.exe` + `Start-Process`. `WScript.Shell` rejects `shell:` URIs in `TargetPath` directly, and pairing `explorer.exe` with a `shell:` argument causes launch errors on many systems. Wrapping via `powershell.exe -Command` mirrors the proven Windows right-click registry pattern and resolves reliably on all tested configurations.
- Normal shortcut Arguments: `-NoProfile -WindowStyle Hidden -Command "Start-Process 'shell:AppsFolder\<AppUserModelId>'"`
- Admin shortcut Arguments: `-NoProfile -WindowStyle Hidden -Command "Start-Process 'shell:AppsFolder\<AppUserModelId>' -Verb RunAs"`
- Removed raw `.lnk` byte-patch for Run as Administrator — elevation is now handled cleanly by `Start-Process -Verb RunAs` at runtime.
- `$ExplorerExe` replaced by `$PowerShellExe` (explicit `System32` path).

v1.1.0 (2026-03-13)

- Replaced direct `.exe` shortcut target with `explorer.exe` + `shell:AppsFolder\`.
- Added manifest parsing to resolve `AppUserModelId` from `AppxManifest.xml`.
- Fallback `AppUserModelId` format (`<PackageFamilyName>!App`) used when manifest is missing or unreadable.
- Run as Administrator byte-patch applied when requested.

v1.0.0 (2026-03-13)

- Initial release. Scanned Store apps with real executables, built numbered alphabetical list.
- Name or number selection with whitespace/case-insensitive matching.
- Confirm selection, optional Run as Administrator flag.
- Created `.lnk` on Desktop targeting the app's `.exe` directly.
