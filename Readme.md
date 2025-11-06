# DailyClear.ps1

Lightweight PowerShell script to clear common temporary folders and (optionally) the Recycle Bin on Windows.

## What it does
- Clears contents of:
  - %LOCALAPPDATA%\Microsoft\Windows\Temporary Internet Files\Content.IE5
  - %TEMP% (current user temporary folder)
  - C:\Windows\Temp (requires elevation)
- Optionally clears the system Recycle Bin.
- Respects PowerShell ShouldProcess (`-WhatIf`) and supports `-Verbose`.

## Usage
Open PowerShell and run:

- Preview actions (no deletion):
  powershell -File "DailyClear.ps1" -WhatIf -Verbose

- Run normally:
  powershell -File "DailyClear.ps1"

- Run and skip clearing Recycle Bin:
  powershell -File "DailyClear.ps1" -IncludeRecycleBin:$false

- To clean C:\Windows\Temp, run an elevated PowerShell (Run as Administrator).

## Parameters
- `-IncludeRecycleBin` (switch, default: $true)
  - When present, attempts to clear the system Recycle Bin using `Clear-RecycleBin` if available.

## Behavior and safety
- The script checks for elevation and skips admin-only locations if not elevated.
- It tests each target path with `Test-Path` before attempting removal.
- Directory objects themselves are preserved; only contents are removed.
- Uses per-item error handling to continue if files are locked or cannot be deleted.

## Notes & troubleshooting
- Locked files or antivirus may prevent deletion. Re-run after a reboot or run elevated if necessary.
- If `Clear-RecycleBin` is not present on the system, the script will skip that step.
- Use `-WhatIf` to verify what will be removed before running for real.

## Compatibility
- PowerShell 5.1+ on Windows. Should work in PowerShell Core on Windows for the same cmdlets.

## License
Use as needed. No warranty. Replace or extend paths in the script for custom cleanup locations.