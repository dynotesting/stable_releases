# Scryfall-MTG-Exporter.ps1

A PowerShell script that bulk-queries the [Scryfall API](https://scryfall.com/docs/api) 
for Magic: The Gathering card printings and exports a consolidated CSV spreadsheet with 
pricing, set info, mana cost, rarity, color identity, and direct Scryfall URLs.

Designed to work with exports from Archidekt, Moxfield, or any deck builder that can 
produce a CSV with card names.

---

## Features

- Reads one or more CSV files from a single input folder in one run
- Queries every known **paper printing** of each card (excludes MTGO and Arena)
- Handles Scryfall API pagination — cards with many printings (e.g. Lightning Bolt) are fully captured
- Strips quantity prefixes automatically (`3x Thoughtseize` → `Thoughtseize`)
- Datestamped output file (`ScryfallExport_YYYY-MM-DD.csv`) with auto-increment if run multiple times per day
- Single-pass CSV write guarantees correct UTF-8 encoding and clean Excel import
- Timestamped log file written to `%PROGRAMDATA%` on every run
- Colored console output with per-card status and run summary
- Graceful error handling — one bad card name never kills the whole run

---

## Requirements

- Windows PowerShell 5.1 or later
- Internet access to `api.scryfall.com`
- No external modules or dependencies required

---

## Usage

### 1. Prepare your input CSV(s)

Export card names from your deck builder of choice. The column containing card names 
must have a header that includes the word **card** (case-insensitive):

| CardName | Quantity |
|----------|----------|
| Thoughtseize   | 4 |
| Lightning Bolt | 4 |
| Tarmogoyf      | 2 |

Quantity prefixes in the name column are stripped automatically:
- `4 Thoughtseize` → `Thoughtseize`
- `2x Lightning Bolt` → `Lightning Bolt`

Save one or more CSVs into a single input folder.

### 2. Run the script

```powershell
.\Scryfall-MTG-Exporter.ps1
