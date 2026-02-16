#Requires -Version 5.1

<#
.SYNOPSIS
    Clears temporary files, caches, and optionally the Recycle Bin.
.DESCRIPTION
    Removes contents from user and system temp folders, legacy IE cache,
    Windows Update download cache, prefetch data, and minidump files.
    Requires elevation for system-level paths (Windows\Temp, Prefetch, etc.).
    Displays a summary of total disk space freed after execution.
.PARAMETER SkipRecycleBin
    If specified, the Recycle Bin will NOT be cleared.
.PARAMETER LogFile
    Optional path to a log file. When specified, all output is also appended
    to this file with timestamps.
.EXAMPLE
    .\DailyClear.ps1
    Clears all temp folders and the Recycle Bin.
.EXAMPLE
    .\DailyClear.ps1 -SkipRecycleBin
    Clears temp folders but leaves the Recycle Bin untouched.
.EXAMPLE
    .\DailyClear.ps1 -LogFile "$env:USERPROFILE\DailyClear.log"
    Clears everything and logs results to a file.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [switch]$SkipRecycleBin,
    [string]$LogFile
)

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'WARN' { Write-Warning $Message }
        'VERB' { Write-Verbose $Message }
        default { Write-Output  $Message }
    }

    if ($LogFile) {
        $entry | Out-File -FilePath $LogFile -Append -Encoding utf8
    }
}

# ── Elevation check ─────────────────────────────────────────────────────────

$IsElevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltinRole]::Administrator)

if (-not $IsElevated) {
    Write-Log 'Not elevated: some locations (e.g. Windows\Temp, Prefetch) may be skipped.' -Level VERB
}

# ── Core function ────────────────────────────────────────────────────────────

$script:TotalFreed = 0

function Clear-Folder {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$RequireAdmin
    )

    if ($RequireAdmin -and -not $IsElevated) {
        Write-Log "Skipping '$Path' (requires administrative privileges)." -Level WARN
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log "Path not found: $Path" -Level VERB
        return
    }

    # Measure size before deletion
    $sizeBefore = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    if (-not $sizeBefore) { $sizeBefore = 0 }

    if ($PSCmdlet.ShouldProcess($Path, 'Remove contents')) {
        $deletedCount = 0
        $failedCount = 0

        Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object {
            $item = $_
            try {
                Remove-Item -LiteralPath $item.FullName -Force -Recurse -ErrorAction Stop
                $deletedCount++
                Write-Log "Deleted: $($item.FullName)" -Level VERB
            }
            catch {
                $err = $_
                $failedCount++
                Write-Log "Cannot delete: $($item.FullName) - $($err.Exception.Message)" -Level WARN
            }
        }

        # Measure size after deletion
        $sizeAfter = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if (-not $sizeAfter) { $sizeAfter = 0 }

        $freed = $sizeBefore - $sizeAfter
        if ($freed -lt 0) { $freed = 0 }
        $script:TotalFreed += $freed

        $freedStr = Format-Size $freed
        Write-Log "Cleared: $Path ($deletedCount removed, $failedCount failed, $freedStr freed)"
    }
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N2} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

# ── Target locations ─────────────────────────────────────────────────────────

$locations = @(
    # User temp
    @{ Path = $env:TEMP; RequireAdmin = $false }
    @{ Path = Join-Path $env:LOCALAPPDATA 'Temp'; RequireAdmin = $false }

    # Legacy IE cache (mostly empty on modern Windows, kept for compat)
    @{ Path          = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Temporary Internet Files\Content.IE5'
        RequireAdmin = $false 
    }

    # System locations (require elevation)
    @{ Path = Join-Path $env:SystemRoot 'Temp'; RequireAdmin = $true }
    @{ Path = Join-Path $env:SystemRoot 'Prefetch'; RequireAdmin = $true }
    @{ Path = Join-Path $env:SystemRoot 'Minidump'; RequireAdmin = $true }
    @{ Path = Join-Path $env:SystemRoot 'SoftwareDistribution\Download'; RequireAdmin = $true }
)

# ── Recycle Bin ──────────────────────────────────────────────────────────────

if (-not $SkipRecycleBin) {
    if (Get-Command -Name Clear-RecycleBin -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess('Recycle Bin', 'Clear')) {
            try {
                Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                Write-Log 'Recycle Bin cleared.'
            }
            catch {
                $err = $_
                Write-Log "Failed to clear Recycle Bin: $($err.Exception.Message)" -Level WARN
            }
        }
    }
    else {
        Write-Log 'Clear-RecycleBin cmdlet not available.' -Level VERB
    }
}

# ── Execute clears ──────────────────────────────────────────────────────────

foreach ($loc in $locations) {
    $params = @{ Path = $loc.Path }
    if ($loc.RequireAdmin) { $params['RequireAdmin'] = $true }
    Clear-Folder @params
}

# ── Summary ──────────────────────────────────────────────────────────────────

$totalStr = Format-Size $script:TotalFreed
Write-Log "Done. Total space freed: $totalStr."