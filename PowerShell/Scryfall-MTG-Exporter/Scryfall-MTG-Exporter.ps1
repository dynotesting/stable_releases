#Requires -Version 5.1
<#
.SYNOPSIS
    Scryfall MTG Card Exporter - Bulk card search and CSV/Excel export using the Scryfall API.

.DESCRIPTION
    Reads one or more CSV files containing Magic: The Gathering card names,
    queries the Scryfall REST API for every known paper printing of each card,
    and exports a consolidated master spreadsheet (CSV) with pricing, set info,
    mana cost, rarity, color identity, and a direct Scryfall URL for each result.

    Uses a two-step API approach to avoid URL encoding issues:
      Step 1 - /cards/named?exact= resolves the canonical card and returns a
               prints_search_uri pointing to all known printings.
      Step 2 - Follow prints_search_uri (with games=paper filter) and paginate
               through all results using has_more / next_page.

    Handles Scryfall API pagination so cards with many printings (e.g. Lightning
    Bolt) are fully captured. Includes timestamped logging, colored console output,
    and graceful error handling so one bad card never kills the whole run.

.NOTES
    Version    : 1.4
    API Docs   : https://scryfall.com/docs/api
    Rate Limit : Scryfall requests ~50-100ms between calls. This script enforces 100ms.

.WORKFLOW
    1. Export missing/wanted card names from Archidekt, Moxfield, etc. as a CSV.
    2. Ensure the card name column header contains the word "card" (e.g. "Card", "CardName").
    3. Optionally prefix rows with quantities like "3 Thoughtseize" or "2x Bolt" -
       the script strips those automatically.
    4. Save as many CSVs as you want (one per deck, one per want list, etc.) into a
       single input folder.
    5. Run this script. It will prompt for paths and options interactively.
    6. Open the resulting ScryfallExport_YYYY-MM-DD.csv in Excel and sort/filter to hunt deals.

.EXAMPLE
    .\Scryfall-MTG-Exporter.ps1

.OUTPUTS
    ScryfallExport_YYYY-MM-DD.csv  - Master spreadsheet of all card printings found
    ScryfallMTGExporter_*.log      - Timestamped log of all actions, warnings, and errors

.CHANGELOG
    1.4 - Added extensive error handling around file I/O and API calls to ensure one bad card or file doesn't stop the whole run.
        - Errors are logged with details and the script continues processing remaining cards/files.
        - Improved console output formatting for better readability during long runs.
    1.3 - Added extensive comments and documentation for every field in the Scryfall card object.
          Users can easily customize which fields to include in the export by editing the
          [PSCustomObject] block in the code.
        - Added a new "Related URIs" section in the comments to highlight useful links like
          the Scryfall card page URL and EDHREC page URL that users might want to include.
    1.2 - All results collected in memory and written in a single Export-Csv call.
          PowerShell 5.1 drops the UTF-8 BOM on -Append writes, causing Excel to
          misread Unicode characters (e.g. em dash renders as â€"). Writing once
          guarantees one BOM, consistent encoding, and atomic output.
        - Output filename is now datestamped (ScryfallExport_YYYY-MM-DD.csv) and
          auto-increments if a file for today already exists.
        - Input file discovery uses GetFullPath() string comparison instead of
          Resolve-Path to safely exclude the output file even before it exists.
        - ScryfallExport_*.csv files in the input folder are always excluded from
          processing so previous output runs are never re-ingested as input.
    1.1 - Fixed 400 Bad Request errors by adding required User-Agent and Accept
          headers to all Scryfall API requests.
        - Switched URL encoding from [Uri]::EscapeDataString to
          [System.Web.HttpUtility]::UrlEncode to prevent .NET Uri class from
          re-normalizing %20 sequences before the request is sent.
        - Fixed Get-ChildItem token mash ($csvFiles inside cmdlet name).
        - Fixed Resolve-Path .Path property error when output file doesn't exist.
    1.0 - Initial release.
#>

# ---------------------------------------------------------------
#  GLOBAL FIXES - applied at startup before anything else runs
# ---------------------------------------------------------------

# Fix 1: Force TLS 1.2
# PowerShell 5.1 defaults to TLS 1.0/1.1. Scryfall requires TLS 1.2+.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Fix 2: Load System.Web for proper URL form encoding.
# UrlEncode() outputs spaces as + and special chars as %XX.
# Avoids .NET Uri re-normalization issues that caused 400 errors
# when using [Uri]::EscapeDataString() which encodes spaces as %20.
Add-Type -AssemblyName System.Web

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ---------------------------------------------------------------
#  SCRIPT-LEVEL VARIABLES
# ---------------------------------------------------------------

$Script:Version  = "1.4"
$Script:AppName = "Scryfall MTG Card Exporter"

# Each run gets its own datestamped log file in ProgramData.
$script:LogPath = "$env:PROGRAMDATA\ScryfallMTGExporter_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Required headers for every Scryfall API request.
# Scryfall REQUIRES both User-Agent and Accept on all requests or it returns 400.
# Reference: https://scryfall.com/docs/api
$script:Headers = @{
    "User-Agent" = "ScryfallMTGExporter/$Script:Version ($env:USERNAME@$env:COMPUTERNAME)"
    "Accept"     = "application/json"
}

# ===============================================================
#  SECTION 1 - CONSOLE OUTPUT HELPERS
#  [v] = success  (White)
#  [i] = info     (Yellow)
#  [x] = error    (Red)
# ===============================================================

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |      SCRYFALL MTG CARD EXPORTER  v$Script:Version                  |" -ForegroundColor Cyan
    Write-Host "  |      Bulk card search  --->  CSV / Excel export         |" -ForegroundColor Cyan
    Write-Host "  |      API: https://scryfall.com/docs/api                 |" -ForegroundColor Cyan
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""
}

function Write-OK      { param([string]$m) Write-Host "  |   [v] $m" -ForegroundColor White  }
function Write-Info    { param([string]$m) Write-Host "  |   [i] $m" -ForegroundColor Yellow }
function Write-Err     { param([string]$m) Write-Host "  |   [x] $m" -ForegroundColor Red    }
function Write-Section { param([string]$m) Write-Host "  +-- $m"     -ForegroundColor DarkCyan }
function Write-Divider { Write-Host ("  +" + ("-" * 57)) -ForegroundColor DarkCyan }

# ===============================================================
#  SECTION 2 - LOGGING
#  All events written to a timestamped log file.
#  Levels: INFO, WARN, ERROR
# ===============================================================

function Write-Log {
    param(
        [string]$Level,    # INFO | WARN | ERROR
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp][$($Level.PadRight(5))] $Message"
    $entry | Add-Content -Path $script:LogPath -Encoding UTF8
}

# ===============================================================
#  SECTION 3 - PATH INPUT HELPER
#  Prompts for a folder path and re-asks if it doesn't exist.
# ===============================================================

function Read-ValidPath {
    param(
        [string]$Prompt,
        [bool]$MustExist = $true
    )
    do {
        $path = (Read-Host $Prompt).Trim('"').Trim()
        if ($MustExist -and -not (Test-Path $path)) {
            Write-Host "  |   [i] Path not found, please try again." -ForegroundColor Yellow
            $path = $null
        }
    } while (-not $path)
    return $path
}

# ===============================================================
#  SECTION 4 - SCRYFALL API FUNCTION
#
#  WHY TWO STEPS?
#  The /cards/named?exact= endpoint accepts a plain card name as
#  a query parameter and handles exact matching server-side.
#  It returns prints_search_uri - a Scryfall-built URL listing
#  all printings by oracle_id. We follow that URL for all results.
#
#  WHY HttpUtility.UrlEncode?
#  [Uri]::EscapeDataString encodes spaces as %20. .NET's Uri class
#  sometimes re-normalizes those back to spaces before sending,
#  producing a malformed query that Scryfall rejects with 400.
#  UrlEncode() uses + for spaces (standard form encoding) which
#  .NET does not touch, so the request arrives at Scryfall intact.
#
#  WHY BOTH User-Agent AND Accept HEADERS?
#  Scryfall explicitly requires both headers on every request.
#  Omitting either one causes a 400 Bad Request with the message:
#  "HTTP requests to api.scryfall.com must contain a User-Agent
#  and Accept header."
#
#  ENCODING EXAMPLES:
#    "Bloodbraid Elf"            -> "Bloodbraid+Elf"
#    "Kolaghan's Command"        -> "Kolaghan%27s+Command"
#    "Kongming, Sleeping Dragon" -> "Kongming%2c+Sleeping+Dragon"
# ===============================================================

function Get-ScryfallPrintings {
    param(
        [string]$CardName
    )

    $allCards = [System.Collections.Generic.List[object]]::new()

    $encodedName = [System.Web.HttpUtility]::UrlEncode($CardName)
    $namedUri    = "https://api.scryfall.com/cards/named?exact=$encodedName"

    # Step 1 - Resolve canonical card object by exact name.
    # Returns 404 if the name doesn't match any card exactly.
    try {
        $canonical = Invoke-RestMethod -Uri $namedUri -Method Get -Headers $script:Headers -ErrorAction Stop
    }
    catch {
        # Extract Scryfall's error detail message from the response body if available.
        $detail = ""
        if ($_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = [System.IO.StreamReader]::new($stream)
                $parsed = $reader.ReadToEnd() | ConvertFrom-Json
                $detail = " | Scryfall: $($parsed.details)"
            } catch {}
        }
        throw "$($_.Exception.Message)$detail"
    }

    # Step 2 - Follow prints_search_uri for all paper printings.
    # &games=paper excludes digital-only printings (MTGO and Arena).
    $searchUri = $canonical.prints_search_uri + "&games=paper"

    do {
        try {
            $response  = Invoke-RestMethod -Uri $searchUri -Method Get -Headers $script:Headers -ErrorAction Stop
            foreach ($card in $response.data) { $allCards.Add($card) }

            # Scryfall paginates at 175 results per page - follow next_page if present.
            $searchUri = if ($response.has_more) { $response.next_page } else { $null }
            if ($searchUri) { Start-Sleep -Milliseconds 110 }
        }
        catch {
            throw $_
        }
    } while ($searchUri)

    return $allCards
}

# ===============================================================
#  MAIN
# ===============================================================

Write-Banner

Write-Host "  |   [i] Log file: $script:LogPath" -ForegroundColor Yellow
Write-Host ""
Write-Log "INFO" "Script started | Version: $($Script:Version)"

# ---------------------------------------------------------------
#  Step 1 - Collect folder paths
# ---------------------------------------------------------------

Write-Host "  +-- Configure Paths" -ForegroundColor DarkCyan
Write-Divider
Write-Host ""

$InputFolder  = Read-ValidPath "  Input folder   (e.g. C:\temp\mtg)" -MustExist $true
$OutputFolder = (Read-Host "  Output folder  (e.g. C:\temp\mtg\out)").Trim('"').Trim()

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    Write-Host "  |   [v] Created output folder: $OutputFolder" -ForegroundColor White
}

# Build a datestamped output filename.
# Auto-increments if a file for today already exists:
#   ScryfallExport_2026-03-01.csv
#   ScryfallExport_2026-03-01_2.csv
#   ScryfallExport_2026-03-01_3.csv  ...
$dateStr   = Get-Date -Format "yyyy-MM-dd"
$OutputCsv = Join-Path $OutputFolder "ScryfallExport_$dateStr.csv"
$counter   = 2
while (Test-Path $OutputCsv) {
    $OutputCsv = Join-Path $OutputFolder "ScryfallExport_$dateStr`_$counter.csv"
    $counter++
}

# Resolve to a full absolute path string for reliable exclusion comparison.
# GetFullPath works even before the file exists on disk, unlike Resolve-Path
# which throws if the path doesn't exist yet.
$OutputCsvFull = [System.IO.Path]::GetFullPath($OutputCsv)

Write-Host "  |   [i] Output file : $OutputCsv" -ForegroundColor Yellow
Write-Host ""
Write-Log "INFO" "Session started | Input: $InputFolder | Output: $OutputCsv"

# ---------------------------------------------------------------
#  Step 2 - Discover CSV input files
#
#  Files are collected BEFORE any output is written so that a
#  previous run's output sitting in the same folder is never
#  picked up as input.
#
#  Two exclusion rules:
#    1. Exact full path match against $OutputCsvFull - blocks the
#       current session's output file even before it exists.
#    2. Filename pattern ScryfallExport_*.csv - blocks all previous
#       output files from prior runs in the same folder. Those files
#       contain a CardName column that matches the card header regex
#       and would cause every printing row to be re-queried.
# ---------------------------------------------------------------

$csvFiles = @(Get-ChildItem $InputFolder -Filter "*.csv" |
    Where-Object {
        $fileFull = [System.IO.Path]::GetFullPath($_.FullName)
        if ($fileFull -eq $OutputCsvFull)       { return $false }
        if ($_.Name -like "ScryfallExport_*.csv") { return $false }
        return $true
    })

if ($csvFiles.Count -eq 0) {
    Write-Host "  |   [x] No CSV files found in: $InputFolder" -ForegroundColor Red
    Write-Log "ERROR" "No CSV files found in $InputFolder"
    exit 1
}

Write-Host "  |   [v] Found $($csvFiles.Count) CSV file(s) to process." -ForegroundColor White
Write-Divider
Write-Host ""

# ---------------------------------------------------------------
#  Step 3 - Initialize counters and results collection
#
#  WHY collect results in memory instead of Export-Csv -Append?
#  PowerShell 5.1 writes the UTF-8 BOM only on the first write.
#  Subsequent -Append calls drop the BOM and can re-encode bytes
#  inconsistently, causing Unicode characters (e.g. the em dash
#  in "Creature — Elf Berserker") to render as mojibake in Excel
#  (e.g. "Creature â€" Elf Berserker").
#  Writing all rows in one Export-Csv call at the end guarantees
#  a single BOM, consistent UTF-8 encoding throughout, and atomic
#  output - nothing is written if the script errors partway through.
# ---------------------------------------------------------------

$allResults         = [System.Collections.Generic.List[object]]::new()
$totalCardsSearched = 0
$totalRowsWritten   = 0
$totalErrors        = 0

# ---------------------------------------------------------------
#  Step 4 - Process each CSV file
# ---------------------------------------------------------------

foreach ($file in $csvFiles) {

    Write-Host "  +-- File: $($file.Name)" -ForegroundColor DarkCyan

    try {
        $list = Import-Csv -Path $file.FullName -ErrorAction Stop
    }
    catch {
        Write-Host "  |   [x] Could not read $($file.Name): $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "ERROR" "Failed to import $($file.Name): $($_.Exception.Message)"
        continue
    }

    # Auto-detect card name column - matches any header containing "card".
    $cardHeader = $list[0].PSObject.Properties.Name |
        Where-Object { $_ -match 'card' } |
        Select-Object -First 1

    if (-not $cardHeader) {
        Write-Host "  |   [i] No 'Card' column found in $($file.Name) - skipping." -ForegroundColor Yellow
        Write-Log "WARN" "No card column detected in $($file.Name)"
        continue
    }

    $fileSearched = 0
    $fileRows     = 0

    foreach ($row in $list) {

        $rawName = $row.$cardHeader
        if ([string]::IsNullOrWhiteSpace($rawName)) { continue }

        # Strip leading quantity prefixes e.g. "3 " or "2x " from deck exports.
        $cleanName = $rawName.Trim() -replace '^\d+x?\s+', ''

        $totalCardsSearched++
        $fileSearched++

        Write-Host "  |   Querying : $cleanName" -ForegroundColor Gray

        try {
            $cards = Get-ScryfallPrintings -CardName $cleanName

            if ($cards.Count -eq 0) {
                Write-Host "  |   [i] No paper printings found for: $cleanName" -ForegroundColor Yellow
                Write-Log "WARN" "No results for '$cleanName' (file: $($file.Name))"
                $totalErrors++
                continue
            }

            foreach ($card in $cards) {

                # ==============================================================
                #  AVAILABLE SCRYFALL CARD OBJECT FIELDS
                #  Full reference: https://scryfall.com/docs/api/cards
                #
                #  To add a field to your export:
                #    1. Find the property in the comments below
                #    2. Add a matching line in the [PSCustomObject] block
                #  Example: add   Artist = $card.artist
                # ==============================================================

                # ---- IDENTIFICATION ------------------------------------
                # $card.id                   # Scryfall UUID - unique per printing
                # $card.oracle_id            # Oracle ID - same across all printings
                # $card.mtgo_id              # Magic Online card ID
                # $card.mtgo_foil_id         # Magic Online foil card ID
                # $card.tcgplayer_id         # TCGPlayer product ID
                # $card.tcgplayer_etched_id  # TCGPlayer etched foil product ID
                # $card.cardmarket_id        # Cardmarket product ID (European market)
                # $card.multiverse_ids       # Array of Gatherer multiverse IDs

                # ---- CORE CARD DATA -----------------------------------
                # $card.name                 # Full card name
                # $card.lang                 # Language: en ja de fr it pt es ru ko zhs zht
                # $card.layout               # normal split flip transform modal_dfc meld
                #                            # leveler saga adventure mutate prototype battle
                #                            # planar scheme vanguard token emblem augment
                # $card.mana_cost            # Mana cost string e.g. "{1}{B}{R}"
                # $card.cmc                  # Converted mana cost as float e.g. 3.0
                # $card.type_line            # Full type line e.g. "Legendary Creature - Human"
                # $card.oracle_text          # Oracle rules text
                # $card.flavor_text          # Flavor/lore text (not always present)
                # $card.power                # Creature power e.g. "3" (can be "*")
                # $card.toughness            # Creature toughness e.g. "4" (can be "*")
                # $card.loyalty              # Planeswalker starting loyalty
                # $card.defense              # Battle card defense value
                # $card.hand_modifier        # Vanguard hand modifier e.g. "+1"
                # $card.life_modifier        # Vanguard life modifier e.g. "-3"

                # ---- COLORS -------------------------------------------
                # $card.colors               # Array e.g. ["W","U"] ; empty = colorless
                #                            # W=White U=Blue B=Black R=Red G=Green
                # $card.color_identity       # Array of color identity (incl. rules text pips)
                # $card.color_indicator      # Color indicator for cards without mana cost
                # $card.produced_mana        # Array of mana types this card can produce
                # $card.keywords             # Array of keyword abilities e.g. ["Flying","Haste"]

                # ---- SET & PRINTING ------------------------------------
                # $card.set                  # Set code lowercase e.g. "dtk" "lea" "mh2"
                # $card.set_name             # Full set name e.g. "Dragons of Tarkir"
                # $card.set_type             # core expansion masters commander draft_innovation
                #                            # planechase archenemy funny starter box promo
                #                            # token memorabilia minigame alchemy
                # $card.collector_number     # Collector number string e.g. "102" or "102a"
                # $card.rarity               # common uncommon rare special mythic bonus
                # $card.released_at          # Release date string e.g. "2015-03-27"
                # $card.reprint              # True if printed in a prior set
                # $card.variation            # True if variant of another card in same set
                # $card.digital              # True if digital-only (MTGO or Arena)
                # $card.promo                # True if promotional printing
                # $card.promo_types          # Array e.g. ["prerelease","datestamped"]
                # $card.finishes             # Array: nonfoil foil etched glossy
                # $card.foil                 # True if foil version exists (legacy field)
                # $card.nonfoil              # True if nonfoil version exists (legacy field)
                # $card.oversized            # True if oversized card
                # $card.full_art             # True if full-art treatment
                # $card.textless             # True if no text box on this printing
                # $card.story_spotlight      # True if story spotlight card
                # $card.booster              # True if appears in booster packs
                # $card.reserved             # True if on the Reserved List
                # $card.border_color         # black white gold silver borderless
                # $card.frame                # Frame edition: 1993 1997 2003 2015 future
                # $card.frame_effects        # Array: legendary showcase extendedart etched
                #                            # colorshifted inverted snow lesson tombstone etc.
                # $card.security_stamp       # oval triangle acorn arena heart

                # ---- ARTIST & ART -------------------------------------
                # $card.artist               # Artist name as printed on card
                # $card.artist_ids           # Array of Scryfall artist UUIDs
                # $card.illustration_id      # Illustration UUID (same for reprints of same art)
                # $card.watermark            # Watermark name e.g. "set" "planeswalker" "dci"
                # $card.highres_image        # True if high-res scan is available
                # $card.image_status         # missing / placeholder / lowres / highres_scan
                #
                # NOTE: DFC/transform cards store images in card_faces[].image_uris
                # $card.image_uris.small        # JPG ~146x204
                # $card.image_uris.normal       # JPG ~488x680  (good default for display)
                # $card.image_uris.large        # JPG ~672x936
                # $card.image_uris.png          # PNG ~745x1040 (transparent corners)
                # $card.image_uris.art_crop     # Cropped illustration only
                # $card.image_uris.border_crop  # Full card cropped to border edge

                # ---- PRICING ------------------------------------------
                # NOTE: Prices update daily. Null if no market data available.
                # $card.prices.usd           # Nonfoil USD price (TCGPlayer)
                # $card.prices.usd_foil      # Foil USD price
                # $card.prices.usd_etched    # Etched foil USD price
                # $card.prices.eur           # Nonfoil EUR price (Cardmarket)
                # $card.prices.eur_foil      # Foil EUR price
                # $card.prices.tix           # MTGO ticket price (Cardhoarder)

                # ---- LEGALITIES ---------------------------------------
                # Values: "legal"  "not_legal"  "restricted"  "banned"
                # $card.legalities.standard
                # $card.legalities.pioneer
                # $card.legalities.modern
                # $card.legalities.legacy
                # $card.legalities.vintage
                # $card.legalities.commander
                # $card.legalities.pauper
                # $card.legalities.paupercommander
                # $card.legalities.explorer
                # $card.legalities.historic
                # $card.legalities.alchemy
                # $card.legalities.brawl
                # $card.legalities.historicbrawl
                # $card.legalities.oathbreaker
                # $card.legalities.duel
                # $card.legalities.oldschool
                # $card.legalities.premodern
                # $card.legalities.predh

                # ---- RANKINGS & METADATA ------------------------------
                # $card.edhrec_rank          # EDHREC rank (lower = more popular in EDH)
                # $card.penny_rank           # Penny Dreadful format rank

                # ---- PURCHASE & EXTERNAL LINKS ------------------------
                # $card.purchase_uris.tcgplayer    # TCGPlayer direct listing URL
                # $card.purchase_uris.cardmarket   # Cardmarket direct listing URL
                # $card.purchase_uris.cardhoarder  # Cardhoarder (MTGO) listing URL
                # $card.related_uris.gatherer      # Gatherer official page URL
                # $card.related_uris.edhrec        # EDHREC page URL
                # $card.related_uris.tcgplayer_infinite_decks  # TCGPlayer decklists
                # $card.scryfall_uri         # Scryfall card page URL (human-readable)
                # $card.uri                  # Scryfall API URI for this printing
                # $card.prints_search_uri    # API search URL for all printings
                # $card.rulings_uri          # API URI for official rulings

                # ---- DOUBLE-FACED / MULTI-FACE CARDS ------------------
                # For transform, modal_dfc, flip, meld, adventure cards.
                # Face data is in card_faces[] instead of the root object.
                # $card.card_faces[0].name
                # $card.card_faces[0].mana_cost
                # $card.card_faces[0].type_line
                # $card.card_faces[0].oracle_text
                # $card.card_faces[0].flavor_text
                # $card.card_faces[0].power
                # $card.card_faces[0].toughness
                # $card.card_faces[0].loyalty
                # $card.card_faces[0].colors
                # $card.card_faces[0].image_uris.normal
                # $card.card_faces[0].artist
                # $card.card_faces[1].name
                # $card.card_faces[1].oracle_text
                # $card.card_faces[1].image_uris.normal

                # ---- RELATED TOKENS / PARTS ---------------------------
                # $card.all_parts                   # Array of related card objects
                # $card.all_parts[0].name           # Related card name
                # $card.all_parts[0].uri            # Related card API URI
                # $card.all_parts[0].component      # token / meld_part / meld_result / combo_piece

                # ==============================================================
                #  EXPORTED FIELDS
                #  Edit the PSCustomObject below to add/remove output columns.
                # ==============================================================

                $colorStr  = if ($card.color_identity.Count -gt 0) { $card.color_identity -join "/" } else { "Colorless" }
                $priceUSD  = if ($card.prices.usd)      { $card.prices.usd }      else { "N/A" }
                $priceFoil = if ($card.prices.usd_foil) { $card.prices.usd_foil } else { "N/A" }

                $allResults.Add([PSCustomObject]@{
                    CardName      = $card.name
                    SetName       = $card.set_name
                    SetCode       = $card.set.ToUpper()
                    ColorIdentity = $colorStr
                    TypeLine      = ($card.type_line -replace [char]0x2014, '-')   # em dash -> hyphen
                    # Strip/replace problem characters before writing (defensive). Scryfall data is usually clean but some cards have weird unicode in their type lines that can break Excel imports.
                    ManaCost      = $card.mana_cost
                    Rarity        = $card.rarity
                    Price_USD     = $priceUSD
                    Price_Foil    = $priceFoil
                    ScryfallURL   = $card.scryfall_uri
                    SourceFile    = $file.Name
                })

                $totalRowsWritten++
                $fileRows++
            }

            Write-Host "  |   [v] $($cards.Count) printing(s) found" -ForegroundColor White
            Write-Log "INFO" "'$cleanName' -> $($cards.Count) result(s)"

        }
        catch {
            $errMsg = $_.Exception.Message
            Write-Host "  |   [x] Failed: '$cleanName' -- $errMsg" -ForegroundColor Red
            Write-Log "ERROR" "Card '$cleanName' | File '$($file.Name)' | $errMsg"
            $totalErrors++
        }

        # Courtesy delay - Scryfall asks for ~100ms between requests.
        Start-Sleep -Milliseconds 100
    }

    Write-Host "  +-- Done: $fileSearched searched, $fileRows rows staged" -ForegroundColor Green
    Write-Host ""
}

# ---------------------------------------------------------------
#  Step 5 - Write all results to CSV in a single call
#
#  A single Export-Csv call writes exactly one UTF-8 BOM at the
#  start of the file. Using -Append in a loop causes PS 5.1 to
#  drop the BOM on every write after the first, which corrupts
#  Unicode characters when the file is opened in Excel.
# ---------------------------------------------------------------

if ($allResults.Count -gt 0) {
    $allResults | Export-Csv -Path $OutputCsv -Encoding UTF8 -NoTypeInformation
    Write-Host "  |   [v] CSV written: $OutputCsv" -ForegroundColor White
} else {
    Write-Host "  |   [i] No results to write - output file not created." -ForegroundColor Yellow
}

# ===============================================================
#  SECTION 5 - RUN SUMMARY
# ===============================================================

Write-Divider
Write-Host "  +-- SUMMARY" -ForegroundColor Cyan
Write-Divider
Write-Host "  |   Cards searched : $totalCardsSearched" -ForegroundColor White
Write-Host "  |   Rows exported  : $totalRowsWritten"   -ForegroundColor White
Write-Host "  |   Errors / missed: $totalErrors" `
    -ForegroundColor $(if ($totalErrors -gt 0) { "Yellow" } else { "White" })
Write-Host "  |   Output CSV     : $OutputCsv"          -ForegroundColor White
Write-Host "  |   Log file       : $script:LogPath"     -ForegroundColor White
Write-Divider
Write-Host ""

Write-Log "INFO" "Session complete | Searched: $totalCardsSearched | Rows: $totalRowsWritten | Errors: $totalErrors"

$open = Read-Host "  Open output CSV now? (Y/N)"
if ($open.ToUpper() -eq 'Y') { Start-Process $OutputCsv }
