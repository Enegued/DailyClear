# DailyClear.ps1

Lightweight PowerShell script to clear common temporary folders, caches, and (optionally) the Recycle Bin on Windows. Outputs a structured report of space freed per location.

## What it does

- Clears contents of:
  - `%TEMP%` — current user temporary folder
  - `%LOCALAPPDATA%\Temp`
  - `%LOCALAPPDATA%\...\Content.IE5` — legacy IE cache (kept for compat)
  - `%SystemRoot%\Temp` *(elevation required)*
  - `%SystemRoot%\Prefetch` *(elevation required)*
  - `%SystemRoot%\Minidump` *(elevation required)*
  - `%SystemRoot%\SoftwareDistribution\Download` *(elevation required)*
- Optionally clears the system Recycle Bin (enabled by default).
- Displays a **formatted report table** with per-location status and space freed.
- Respects PowerShell `ShouldProcess` (`-WhatIf` / `-Confirm`) and `-Verbose`.

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
```

> **Note:** To clean system paths, run from an elevated PowerShell (Run as Administrator).

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-SkipRecycleBin` | Switch | `$false` | Skip clearing the Recycle Bin |
| `-LogFile` | String | *(none)* | Path to a log file (parent directory must exist) |

## Output

The script prints a summary table after execution:

```
Location          Status              Deleted Failed Freed
--------          ------              ------- ------ -----
User Temp         OK                       12      0 48.23 MB
LocalAppData Temp OK                        3      0 1.20 MB
IE Cache (legacy) OK                        0      0 0 B
Windows Temp      SKIP (Requires elevation) 0      0 0 B
Prefetch          SKIP (Requires elevation) 0      0 0 B
Minidump          SKIP (Path not found)     0      0 0 B
WU Download Cache SKIP (Requires elevation) 0      0 0 B
Recycle Bin       OK                        1      0 0 B

Done — 49.43 MB freed in 2.3s.
```

## Behavior and safety

- Checks for elevation and skips admin-only locations if not elevated.
- Tests each target path with `Test-Path` before attempting removal.
- Deletes only **direct children** of each target (each with `-Recurse`) — avoids double-deletion errors.
- Directory roots are always preserved; only contents are removed.
- Per-item error handling: locked files are reported but do not stop execution.
- All functions return typed `[PSCustomObject]` results — no global mutable state.

## Compatibility

- Requires **PowerShell 5.1+** on Windows.
- Compatible with PowerShell Core (7+) on Windows.

## License

Use as needed. No warranty.