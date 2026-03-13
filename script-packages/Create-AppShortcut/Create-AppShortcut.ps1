# ─────────────────────────────────────────────────────────────────────────────
# SCRIPT IDENTITY  —  set once here, referenced throughout
# ─────────────────────────────────────────────────────────────────────────────
$ScriptName    = $MyInvocation.MyCommand.Name  # Resolved at runtime from the .ps1 filename
$ScriptTitle   = 'Microsoft Store App Shortcut Creator'  # Human-readable title shown in the header banner
$ScriptVersion = '1.2.0'                       # Semantic version — keep in sync with .VERSION HISTORY below

<#
.NOTES
    Script Name   : Create-AppShortcut.ps1
    Script Title  : Microsoft Store App Shortcut Creator
    Author        : Dean N. [dynotesting]
    Version       : 1.2.0
    Creation Date : 2026-03-13
    Git URL       : https://github.com/dynotesting


.SYNOPSIS
    Scans installed Microsoft Store apps and creates a Desktop shortcut for
    the selected app using the Windows-native shell:AppsFolder launch method.


.DESCRIPTION
    Enumerates all installed Microsoft Store apps that expose at least one real
    .exe in their install folder, displays them in a numbered alphabetical list,
    prompts the user to select one by number or name, confirms the selection,
    optionally sets Run as Administrator, then writes a .lnk shortcut to the
    current user's Desktop.

    Shortcut target  : powershell.exe  (full %SystemRoot%\System32 path)
    Shortcut argument: -NoProfile -WindowStyle Hidden -Command
                       "Start-Process 'shell:AppsFolder\<AppUserModelId>'"

    WScript.Shell's CreateShortcut() rejects shell: URIs when used as TargetPath
    directly, and setting explorer.exe as TargetPath with a shell: argument causes
    a "file not found" error at launch time on many systems.  The proven fix —
    mirroring the pattern used by Windows right-click registry entries — is to set
    TargetPath to powershell.exe and call Start-Process inside the -Command string.
    Windows resolves the shell:AppsFolder virtual path correctly from within
    Start-Process.  For the admin variant, -Verb RunAs is appended to Start-Process,
    which triggers the UAC elevation prompt at launch time with no byte-patching.

    The AppUserModelId (<PackageFamilyName>!<AppId>) is resolved by reading the
    app's AppxManifest.xml.  If the manifest is unreadable the script falls back
    to <PackageFamilyName>!App, which works for the majority of packages.

    Name matching is case-insensitive and whitespace-insensitive.
    Shortcut file is named one of:
        <AppName> Shortcut.lnk
        <AppName> ADMIN Shortcut.lnk


.PARAMETER None
    This script takes no parameters.  All input is interactive.


.INPUTS
    None


.OUTPUTS
    A .lnk shortcut file on the current user's Desktop.


.EXAMPLE
    .\Create-AppShortcut.ps1
    Launches the interactive Store app picker and creates a Desktop shortcut.


.VERSION HISTORY
    1.2.0 - 2026-03-13
        - Replaced explorer.exe shortcut target with powershell.exe + Start-Process.
          WScript.Shell rejects shell: URIs in TargetPath directly, and pairing
          explorer.exe as TargetPath with a shell: argument causes launch errors.
          Wrapping via powershell.exe -Command mirrors the proven Windows right-click
          registry pattern and resolves reliably on all tested configurations.
        - Normal shortcut Arguments:
              -NoProfile -WindowStyle Hidden -Command
              "Start-Process 'shell:AppsFolder\<AppUserModelId>'"
        - Admin shortcut Arguments:
              -NoProfile -WindowStyle Hidden -Command
              "Start-Process 'shell:AppsFolder\<AppUserModelId>' -Verb RunAs"
        - Removed raw .lnk byte-patch for Run as Administrator — no longer needed.
          Elevation is now handled cleanly by Start-Process -Verb RunAs at runtime.
        - $ExplorerExe replaced by $PowerShellExe (explicit System32 path).
        - Step 5 admin comment updated to reflect new UAC mechanism.
        - Confirmation display and summary updated to show resolved launch command.

    1.1.0 - 2026-03-13
        - Replaced direct .exe shortcut target with explorer.exe + shell:AppsFolder\.
        - Added manifest parsing to resolve AppUserModelId
          (<PackageFamilyName>!<AppId>) from AppxManifest.xml.
        - Fallback AppUserModelId format (<PackageFamilyName>!App) used when
          the manifest is missing or unreadable.
        - Shortcut TargetPath    = full path to explorer.exe
        - Shortcut Arguments     = shell:AppsFolder\<AppUserModelId>
        - WorkingDirectory       = "" (not applicable for shell: launches)
        - Run as Administrator byte-patch still applied when requested.
        - Confirmation display updated to show App ID and resolved launch command.
        - Added inline comments throughout all major code blocks.

    1.0.0 - 2026-03-13
        - Initial release.
        - Scanned Store apps with real executables, built numbered alphabetical list.
        - Name or number selection with whitespace/case-insensitive matching.
        - Confirm selection, optional Run as Administrator flag.
        - Created .lnk on Desktop targeting the app's .exe directly.
#>


# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION  —  paths resolved once at startup
# ─────────────────────────────────────────────────────────────────────────────

# Resolve the current user's Desktop path via .NET (locale-safe, works on
# non-English Windows installs where the folder may not be named "Desktop")
$DesktopPath = [Environment]::GetFolderPath("Desktop")

# Build the full path to powershell.exe from %SystemRoot%\System32.
# Using the explicit System32 path avoids any PATH-resolution ambiguity and
# guarantees we get Windows PowerShell 5.x, not PowerShell 7+ (pwsh.exe).
# Windows PowerShell is present on all supported Windows 10/11 installations.
$PowerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"


# ─────────────────────────────────────────────────────────────────────────────
# HEADER BANNER
# ─────────────────────────────────────────────────────────────────────────────

function Show-Header {
    <#
    .SYNOPSIS
        Clears the console and prints the cyan box banner with script title and version.
    #>
    Clear-Host
    Write-Host ""
    # Top border
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    # Title row — left-pad to 59 chars so the right border aligns
    Write-Host ("  ║   {0,-59}║" -f $ScriptTitle) -ForegroundColor Cyan
    # Subtitle row — filename + version, slightly dimmer
    Write-Host ("  ║   --{0,-57}║" -f "$ScriptName v$ScriptVersion") -ForegroundColor DarkCyan
    # Bottom border
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}


# ─────────────────────────────────────────────────────────────────────────────
# OUTPUT HELPERS  —  consistent color-coded console output wrappers
# ─────────────────────────────────────────────────────────────────────────────

# Plain informational message (white)
function Write-Info  { param([string]$Msg) Write-Host "  $Msg"        -ForegroundColor White    }

# Success / confirmation message (green) — prefixed with [OK]
function Write-OK    { param([string]$Msg) Write-Host "  [OK]  $Msg"  -ForegroundColor Green    }

# Warning / non-fatal alert (yellow) — prefixed with [!!]
function Write-Warn  { param([string]$Msg) Write-Host "  [!]  $Msg"  -ForegroundColor Yellow   }

# Error / fatal alert (red) — prefixed with [ERR]
function Write-Err   { param([string]$Msg) Write-Host "  [ERR] $Msg"  -ForegroundColor Red      }

# Dimmed supplementary detail (dark gray) — used for paths, metadata, hints
function Write-Dim   { param([string]$Msg) Write-Host "  $Msg"        -ForegroundColor DarkGray }

# Horizontal rule separator (dark gray line)
function Write-Rule  { Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray }


# ─────────────────────────────────────────────────────────────────────────────
# PROMPT HELPER  —  strict Y/N input with re-prompt on invalid entry
# ─────────────────────────────────────────────────────────────────────────────

function Read-YesNo {
    <#
    .SYNOPSIS
        Prompts the user for a Y or N answer.  Loops until a valid response is given.
    .PARAMETER Question
        The question text displayed before [Y/N].
    .OUTPUTS
        "y" or "n" (lowercase string).
    #>
    param([string]$Question)
    while ($true) {
        # Read input, trim surrounding whitespace, normalize to lowercase
        $ans = (Read-Host "  $Question [Y/N]").Trim().ToLower()
        if ($ans -in @("y", "n")) { return $ans }          # Valid — return immediately
        Write-Warn "Please enter Y or N."                  # Invalid — warn and loop
    }
}


# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT  —  script execution begins here
# ─────────────────────────────────────────────────────────────────────────────

Show-Header   # Clear screen and draw the banner before any output


# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — SCAN INSTALLED MICROSOFT STORE APPS
# ─────────────────────────────────────────────────────────────────────────────

Write-Info "Scanning installed Microsoft Store apps..."
Write-Host ""

# Retrieve all AppX packages for the current user.
# Filters applied:
#   IsFramework   = $false  — skip runtime/dependency framework packages (not apps)
#   SignatureKind = "Store"  — only packages distributed through the Microsoft Store
#   InstallLocation         — must have a populated install path
#   Test-Path               — install folder must actually exist on disk
$allApps = $null
try {
    $allApps = Get-AppxPackage -ErrorAction Stop |
        Where-Object {
            $_.IsFramework   -eq $false           -and
            $_.SignatureKind -eq "Store"           -and
            $_.InstallLocation                     -and
            (Test-Path $_.InstallLocation -ErrorAction SilentlyContinue)
        } |
        Sort-Object Name   # Alphabetical sort so the numbered list is predictable
} catch {
    Write-Err "Failed to enumerate Store apps: $_"
    exit 1
}

# Bail if the filtered set is empty (unusual but possible on a stripped OS image)
if (-not $allApps -or $allApps.Count -eq 0) {
    Write-Err "No Microsoft Store apps found on this system."
    exit 1
}


# ── Build the usable app list ─────────────────────────────────────────────────
# Only include packages that contain at least one .exe (confirms the package is
# a launchable application, not purely a background service or content package).
# For each qualifying package, resolve its AppUserModelId from AppxManifest.xml.
# AppUserModelId format: <PackageFamilyName>!<Application.Id>
# This value is used to build the shell:AppsFolder\ launch argument.

$appList = [System.Collections.Generic.List[PSCustomObject]]::new()  # Typed list for reliable .Count
$index   = 1  # 1-based display index shown to the user

foreach ($pkg in $allApps) {
    try {
        # ── .exe presence check ───────────────────────────────────────────────
        # A package with no .exe in its install folder is a dependency bundle,
        # a media/content package, or a sub-component — skip it.
        $exe = Get-ChildItem -Path $pkg.InstallLocation -Filter "*.exe" `
                             -ErrorAction SilentlyContinue |
               Select-Object -First 1   # Only need proof that one exists
        if (-not $exe) { continue }     # No .exe found — skip this package

        # ── Resolve AppUserModelId from AppxManifest.xml ──────────────────────
        # Every Store package ships AppxManifest.xml in its install root.
        # The relevant node is: Package > Applications > Application[Id]
        # Combining PackageFamilyName + "!" + Application.Id gives the full
        # AppUserModelId required by shell:AppsFolder.
        $appId = $null
        try {
            $manifestPath = Join-Path $pkg.InstallLocation "AppxManifest.xml"

            if (Test-Path $manifestPath) {
                [xml]$manifest = Get-Content $manifestPath -Raw -ErrorAction Stop

                # Select the first <Application> element — most packages have only one.
                # Multi-application packages are rare; using the first entry is correct
                # for the vast majority of Store titles.
                $appEntry = $manifest.Package.Applications.Application |
                            Select-Object -First 1

                if ($appEntry -and $appEntry.Id) {
                    # Compose the full AppUserModelId
                    $appId = "$($pkg.PackageFamilyName)!$($appEntry.Id)"
                }
            }
        } catch {
            # Manifest read or XML parse failed — fall through to the fallback below.
            # This can happen with locked files or malformed manifests.
        }

        # ── AppUserModelId fallback ───────────────────────────────────────────
        # If the manifest parse produced nothing, default to the conventional
        # "<PackageFamilyName>!App" pattern.  Most Store apps use "App" as the
        # Application.Id, so this fallback succeeds in the majority of cases.
        if ([string]::IsNullOrWhiteSpace($appId)) {
            $appId = "$($pkg.PackageFamilyName)!App"
        }

        # ── Add to list ───────────────────────────────────────────────────────
        $appList.Add([PSCustomObject]@{
            Index   = $index               # 1-based display number
            Name    = $pkg.Name            # Package Name (used for display + name matching)
            AppId   = $appId               # AppUserModelId for shell:AppsFolder argument
            PkgFull = $pkg.PackageFullName # Full package name (informational / debug)
        })
        $index++

    } catch {
        # Catch-all: skip any package whose install directory is inaccessible
        # (e.g., packages installed for another user, or with restrictive ACLs)
        continue
    }
}

# If every package was filtered out (no .exe found in any of them), exit cleanly
if ($appList.Count -eq 0) {
    Write-Err "No Store apps with launchable executables were found."
    Write-Dim "Apps may be installed but inaccessible (e.g. restricted package locations)."
    exit 1
}


# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — DISPLAY NUMBERED APP LIST
# ─────────────────────────────────────────────────────────────────────────────

Write-Rule
Write-Host ("  {0,5}   {1}" -f "#", "App Name") -ForegroundColor Yellow   # Column header
Write-Rule

# Print each app with its 1-based index, right-aligned in a 5-char field
foreach ($app in $appList) {
    Write-Host ("  {0,5}.  {1}" -f $app.Index, $app.Name)
}

Write-Rule
Write-Host ""
Write-Dim "Enter a number (1-$($appList.Count)) or type the app name exactly."
Write-Host ""


# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — PROMPT FOR APP SELECTION
# ─────────────────────────────────────────────────────────────────────────────

$matched = $null   # Will hold the selected PSCustomObject once a valid match is found

while ($null -eq $matched) {

    $raw = (Read-Host "  Select app").Trim()   # Read and trim surrounding whitespace

    # Guard: reject blank input immediately
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Write-Warn "Input cannot be empty. Enter a number or app name."
        continue
    }

    # ── Branch 1: numeric input ───────────────────────────────────────────────
    # If the entire input is digits, treat it as a list index
    if ($raw -match '^\d+$') {
        $num       = [int]$raw
        $candidate = $appList | Where-Object { $_.Index -eq $num }

        if ($candidate) {
            $matched = $candidate   # Valid index — accept and exit the loop
        } else {
            # Index out of range — warn and loop back for re-entry
            Write-Warn "No app at position $num. Valid range: 1 – $($appList.Count)."
        }
        continue   # Always continue after numeric branch (avoid falling into name branch)
    }

    # ── Branch 2: name input (case + whitespace insensitive) ─────────────────
    # Strip all whitespace and lowercase both sides before comparing.
    # This allows input like "microsoftedge" to match "Microsoft Edge".
    $normInput  = ($raw -replace '\s', '').ToLower()
    $candidates = $appList | Where-Object {
        ($_.Name -replace '\s', '').ToLower() -eq $normInput
    }

    switch ($candidates.Count) {
        0 {
            # No match at all — remind user that name must match the list exactly
            Write-Warn "No exact match for '$raw'."
            Write-Dim  "Check the list above — name must match exactly (spaces and case are ignored)."
        }
        1 {
            # Exactly one match — accept it
            $matched = $candidates
        }
        default {
            # More than one match (shouldn't happen after Sort-Object dedup, but
            # handle defensively by listing the collisions and asking for a number)
            Write-Warn "Multiple matches found — use the number instead:"
            foreach ($c in $candidates) {
                Write-Dim ("  {0,5}.  {1}" -f $c.Index, $c.Name)
            }
        }
    }
}


# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — CONFIRM SELECTION
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Rule
Write-OK  "Matched app  : $($matched.Name)"
Write-Dim "App ID       : $($matched.AppId)"                                           # Full AppUserModelId
Write-Dim "Launch cmd   : powershell.exe ... Start-Process 'shell:AppsFolder\$($matched.AppId)'"
Write-Rule
Write-Host ""

# Ask the user to confirm before writing anything to disk
$confirm = Read-YesNo "Create a shortcut for this app?"
if ($confirm -eq "n") {
    Write-Warn "Cancelled by user. Exiting."
    exit 0   # Clean exit — nothing was written
}


# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 — RUN AS ADMINISTRATOR FLAG
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
# Ask whether the shortcut should launch with elevation.
# When YES: -Verb RunAs is appended to Start-Process inside the -Command string,
# which triggers the standard Windows UAC prompt at click time.
# No raw .lnk byte-patching is needed — Start-Process handles elevation natively.
$makeAdmin = Read-YesNo "Run as Administrator?"


# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — BUILD AND WRITE THE .LNK SHORTCUT
# ─────────────────────────────────────────────────────────────────────────────

# Determine filename suffix based on admin choice
$suffix       = if ($makeAdmin -eq "y") { " ADMIN Shortcut" } else { " Shortcut" }
$shortcutName = "$($matched.Name)$suffix.lnk"         # e.g. "Spotify Shortcut.lnk"
$shortcutPath = Join-Path $DesktopPath $shortcutName  # Full path on user's Desktop

# ── Build the powershell.exe -Command argument string ────────────────────────
# WScript.Shell's CreateShortcut() errors if TargetPath is not a plain executable,
# and setting explorer.exe as TargetPath with a shell: argument causes a
# "file not found" error at launch time.  The proven workaround — identical to
# the pattern used by Windows right-click registry entries — is to set TargetPath
# to powershell.exe and call Start-Process with the shell:AppsFolder URI inside
# a -Command string.  Windows resolves the virtual path correctly from there.
#
# -NoProfile     : skip user profile for faster launch, no side effects
# -WindowStyle Hidden : suppress the blue powershell console window on click
# -Command       : inline script block; Start-Process spawns the Store app
#
# Normal launch  → Start-Process 'shell:AppsFolder\<AppUserModelId>'
# Admin  launch  → Start-Process 'shell:AppsFolder\<AppUserModelId>' -Verb RunAs
#                  -Verb RunAs instructs Windows to elevate via UAC at launch time
if ($makeAdmin -eq "y") {
    $psArgs = "-NoProfile -WindowStyle Hidden -Command `"Start-Process 'shell:AppsFolder\$($matched.AppId)' -Verb RunAs`""
} else {
    $psArgs = "-NoProfile -WindowStyle Hidden -Command `"Start-Process 'shell:AppsFolder\$($matched.AppId)'`""
}

Write-Host ""
Write-Info "Creating shortcut..."

# ── Create the .lnk file via WScript.Shell COM object ────────────────────────
# WScript.Shell is the standard, UAC-safe way to write .lnk files in PowerShell.
# It produces a properly structured Windows Shell Link binary.
try {
    $shell = New-Object -ComObject WScript.Shell -ErrorAction Stop
    $lnk   = $shell.CreateShortcut($shortcutPath)

    # TargetPath — must be a plain executable path; powershell.exe always satisfies this
    $lnk.TargetPath = $PowerShellExe

    # Arguments — the full -Command string built above; Start-Process handles the
    # shell:AppsFolder virtual path resolution internally at runtime
    $lnk.Arguments  = $psArgs

    # WorkingDirectory — intentionally empty; shell: launches have no meaningful CWD
    $lnk.WorkingDirectory = ""

    # Description — appears in the shortcut's Properties tooltip
    $lnk.Description = "$($matched.Name)$suffix"

    # Commit the shortcut to disk
    $lnk.Save()
} catch {
    Write-Err "Failed to create shortcut: $_"
    exit 1
}

# ── Post-write existence check ────────────────────────────────────────────────
# Verify the file actually landed on disk.
# CreateShortcut() can silently no-op on permission errors in rare edge cases.
if (-not (Test-Path $shortcutPath)) {
    Write-Err "Shortcut file was not written to disk. Path: $shortcutPath"
    exit 1
}


# ─────────────────────────────────────────────────────────────────────────────
# DONE — SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Rule
Write-OK  "Shortcut created successfully."
Write-Dim "Location  : $shortcutPath"    # Full path to the new .lnk file on the Desktop
Write-Dim "Target    : $PowerShellExe"   # powershell.exe — the .lnk TargetPath
Write-Dim "Arguments : $psArgs"          # Full -Command string — the .lnk Arguments field
if ($makeAdmin -eq "y") {
    Write-Dim "Admin     : YES — Start-Process -Verb RunAs (UAC prompt on launch)"
} else {
    Write-Dim "Admin     : No"
}
Write-Rule
Write-Host ""
Write-Info "To launch the app, double-click the shortcut on your Desktop."