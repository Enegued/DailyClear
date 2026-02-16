# DailyClear.ps1

Lightweight PowerShell script to clear common temporary folders, caches, and (optionally) the Recycle Bin on Windows.

## What it does
- Clears contents of:
  - `%TEMP%` (current user temporary folder)
  - `%LOCALAPPDATA%\Temp`
  - `%LOCALAPPDATA%\Microsoft\Windows\Temporary Internet Files\Content.IE5` (legacy IE cache)
  - `%SystemRoot%\Temp` (requires elevation)
  - `%SystemRoot%\Prefetch` (requires elevation)
  - `%SystemRoot%\Minidump` (requires elevation)
  - `%SystemRoot%\SoftwareDistribution\Download` (requires elevation)
- Optionally clears the system Recycle Bin (enabled by default).
- Displays a summary of total disk space freed.
- Respects PowerShell `ShouldProcess` (`-WhatIf`) and supports `-Verbose`.

## Usage

```powershell
# Preview actions (no deletion):
.\DailyClear.ps1 -WhatIf -Verbose

# Run normally (clears everything including Recycle Bin):
.\DailyClear.ps1

# Skip clearing the Recycle Bin:
.\DailyClear.ps1 -SkipRecycleBin

# Log results to a file:
.\DailyClear.ps1 -LogFile "$env:USERPROFILE\DailyClear.log"

# Clean system paths — run an elevated PowerShell (Run as Administrator):
.\DailyClear.ps1
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-SkipRecycleBin` | Switch | `$false` | Skip clearing the Recycle Bin |
| `-LogFile` | String | *(none)* | Path to a log file (timestamped entries are appended) |

## Behavior and safety
- Checks for elevation and skips admin-only locations if not elevated.
- Tests each target path with `Test-Path` before attempting removal.
- Directory roots are preserved; only contents are removed.
- Uses per-item error handling to continue if files are locked.
- Shows how much space was freed per folder and in total.

## Notes & troubleshooting
- Locked files or antivirus may prevent deletion. Re-run after a reboot or run elevated.
- If `Clear-RecycleBin` is not available, the script skips that step.
- Use `-WhatIf` to verify what will be removed before running for real.

## Compatibility
- Requires PowerShell 5.1+ on Windows.
- Compatible with PowerShell Core (7+) on Windows.

## License
Use as needed. No warranty.