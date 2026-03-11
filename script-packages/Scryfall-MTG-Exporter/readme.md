# Scryfall MTG Card Exporter v1.4

## Overview
Bulk search and export Magic: The Gathering card data using the [Scryfall API](https://scryfall.com/docs/api), with full CSV/Excel output including pricing, set info, rarity, mana cost, and more.

## Features
- **Two-step Scryfall API calls** for reliable exact-name lookups.
- **Automatic retry & error logging** to skip bad entries safely.
- **Unicode-safe exports** that open cleanly in Excel (one BOM, no corrupted characters).
- **Timestamped logs** for every run.
- **Interactive path prompts** — no parameters needed.
- **Built-in 100ms rate limiting** to respect Scryfall's API delay recommendations.

## Requirements
- **PowerShell Core 7.x** (default for your environment) or Windows PowerShell 5.1+
- **Internet access**
- **TLS 1.2+** support (enabled automatically by script)

## Quick Start
1. Put CSV files (deck lists, wishlists) in a folder like `C:\mtg\inputs`
2. Run: `.\Scryfall-MTG-Exporter.ps1`
3. Enter input folder: `C:\mtg\inputs`
4. Enter output folder: `C:\mtg\out`
5. Get: `ScryfallExport_2026-03-02.csv` + log file

## How It Works
1. **Parse Input:** Auto-detects card name column (any header with "card").
2. **Clean Names:** Strips "3x Lightning Bolt" → "Lightning Bolt".
3. **Query Scryfall:** 
   - `/cards/named?exact=` → canonical card
   - `prints_search_uri` → all paper printings
4. **Export:** Single UTF-8 CSV write for perfect Excel compatibility.

## Usage

.\Scryfall-MTG-Exporter.ps1

## Version History
Scryfall MTG Card Exporter - Version History

v1.4
- Added extensive error handling around file I/O and API calls so one bad card or file does not stop the entire run.
- Logged errors now include more detailed context for easier troubleshooting.
- Improved console output formatting for better readability during long runs.

v1.3
- Added detailed inline documentation for Scryfall card object fields to simplify customizing the exported columns.
- Highlighted useful related URIs (Scryfall card page, EDHREC, etc.) that users may choose to add to the export.

v1.2
- Switched to collecting all results in memory and writing them with a single Export-Csv call to preserve a single UTF-8 BOM and prevent Unicode issues in Excel.
- Introduced datestamped output filenames (ScryfallExport_YYYY-MM-DD.csv) with automatic numeric suffixing for multiple runs on the same day.
- Updated input file discovery to use GetFullPath comparison so the current run’s output file is never re-ingested as input.
- Ensured ScryfallExport_*.csv files in the input folder are always excluded from processing.

v1.1
- Fixed 400 Bad Request errors by adding required User-Agent and Accept headers to all Scryfall API requests.
- Replaced [Uri]::EscapeDataString with [System.Web.HttpUtility]::UrlEncode to avoid .NET URI re-normalization issues that broke certain card lookups.
- Corrected minor bugs including a Get-ChildItem token mash and Resolve-Path usage when the output file does not yet exist.

v1.0
- Initial release with bulk CSV input, full Scryfall printings lookup, and consolidated CSV export of all card printings.
