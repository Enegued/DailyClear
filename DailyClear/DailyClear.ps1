#Requires -Version 5.1

<#
.SYNOPSIS
    Clears temporary files, caches, and optionally the Recycle Bin.
.DESCRIPTION
    Removes contents from user and system temp folders, legacy IE cache,
    Windows Update download cache, prefetch data, and minidump files.
    Requires elevation for system-level paths (Windows\Temp, Prefetch, etc.).
    Displays a structured report of disk space freed after execution.
.PARAMETER SkipRecycleBin
    If specified, the Recycle Bin will NOT be cleared.
.PARAMETER LogFile
    Optional path to a log file. All output is appended with timestamps.
    The parent directory must already exist.
.EXAMPLE
    .\DailyClear.ps1
    Clears all temp folders and the Recycle Bin.
.EXAMPLE
    .\DailyClear.ps1 -SkipRecycleBin
    Clears temp folders but leaves the Recycle Bin untouched.
.EXAMPLE
    .\DailyClear.ps1 -LogFile "$env:USERPROFILE\DailyClear.log"
    Clears everything and logs results to a file.
.EXAMPLE
    .\DailyClear.ps1 -WhatIf -Verbose
    Preview mode - shows what would be deleted without removing anything.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [switch]$SkipRecycleBin,

    [ValidateScript({
            $parent = Split-Path $_ -Parent
            if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
                throw "Log directory does not exist: $parent"
            }
            $true
        })]
    [string]$LogFile
)

# ═══════════════════════════════════════════════════════════════════════════════
#  Self-elevation
# ═══════════════════════════════════════════════════════════════════════════════

$script:IsElevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltinRole]::Administrator)

if (-not $script:IsElevated) {
    # Re-launch the script elevated, forwarding all bound parameters
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $MyInvocation.MyCommand.Definition)
    if ($SkipRecycleBin) { $argList += '-SkipRecycleBin' }
    if ($LogFile) { $argList += '-LogFile'; $argList += $LogFile }
    if ($WhatIfPreference) { $argList += '-WhatIf' }
    if ($VerbosePreference -eq 'Continue') { $argList += '-Verbose' }

    $elevated = $false
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
        $elevated = $true
    }
    catch {
        Write-Warning 'Elevation cancelled or failed. Running without admin privileges.'
    }

    if ($elevated) { exit }
    # Otherwise, continue running non-elevated
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Utilities
# ═══════════════════════════════════════════════════════════════════════════════

function Format-Size ([long]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N2} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'VERB')][string]$Level = 'INFO'
    )

    switch ($Level) {
        'WARN' { Write-Warning $Message }
        'VERB' { Write-Verbose $Message }
        default { Write-Information $Message -InformationAction Continue }
    }

    if ($LogFile) {
        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        "[$stamp] [$Level] $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Core Logic
# ═══════════════════════════════════════════════════════════════════════════════

function Clear-Folder {
    <#
    .SYNOPSIS
        Removes the contents of a single folder and returns a result object.
    .DESCRIPTION
        Deletes only the direct children of the target path (each with -Recurse),
        avoiding double-deletion of nested items. Returns a typed PSCustomObject
        with deletion statistics.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Label,
        [switch]$RequireAdmin
    )

    # Build a default result
    $result = [PSCustomObject]@{
        Label      = if ($Label) { $Label } else { $Path }
        Path       = $Path
        Deleted    = [int]0
        Failed     = [int]0
        BytesFreed = [long]0
        Skipped    = [bool]$false
        SkipReason = [string]''
    }

    # Guard: elevation
    if ($RequireAdmin -and -not $script:IsElevated) {
        $result.Skipped = $true
        $result.SkipReason = 'Requires elevation'
        Write-Log "Skipping '$($result.Label)' (requires administrative privileges)." -Level VERB
        return $result
    }

    # Guard: path existence
    if (-not (Test-Path -LiteralPath $Path)) {
        $result.Skipped = $true
        $result.SkipReason = 'Path not found'
        Write-Log "Path not found: $Path" -Level VERB
        return $result
    }

    # Measure total size before deletion (single scan)
    $sizeBefore = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    if (-not $sizeBefore) { $sizeBefore = 0 }

    if (-not $PSCmdlet.ShouldProcess($Path, 'Remove contents')) {
        return $result
    }

    # Delete direct children only - each Remove-Item -Recurse handles its own subtree
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $item = $_
        try {
            Remove-Item -LiteralPath $item.FullName -Force -Recurse -ErrorAction Stop
            $result.Deleted++
            Write-Log "Deleted: $($item.FullName)" -Level VERB
        }
        catch {
            $err = $_
            $result.Failed++
            Write-Log "Cannot delete: $($item.FullName) - $($err.Exception.Message)" -Level VERB
        }
    }

    # Measure remaining size
    $sizeAfter = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    if (-not $sizeAfter) { $sizeAfter = 0 }

    $result.BytesFreed = [Math]::Max(0, $sizeBefore - $sizeAfter)

    $freedStr = Format-Size $result.BytesFreed
    Write-Log ('Cleared: {0} ({1} removed, {2} failed, {3} freed)' -f $result.Label, $result.Deleted, $result.Failed, $freedStr)
    return $result
}

function Clear-RecycleBinSafe {
    <#
    .SYNOPSIS
        Clears the Recycle Bin and returns a result object.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $result = [PSCustomObject]@{
        Label      = 'Recycle Bin'
        Path       = 'N/A'
        Deleted    = [int]0
        Failed     = [int]0
        BytesFreed = [long]0
        Skipped    = [bool]$false
        SkipReason = [string]''
    }

    if (-not (Get-Command -Name Clear-RecycleBin -ErrorAction SilentlyContinue)) {
        $result.Skipped = $true
        $result.SkipReason = 'Cmdlet not available'
        Write-Log 'Clear-RecycleBin cmdlet not available.' -Level VERB
        return $result
    }

    if (-not $PSCmdlet.ShouldProcess('Recycle Bin', 'Clear')) {
        return $result
    }

    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        $result.Deleted = 1
        Write-Log 'Recycle Bin cleared.'
    }
    catch {
        $err = $_
        $msg = $err.Exception.Message
        # Empty recycle bin is not an error
        if ($msg -match 'empty|vide|0x800700002|Element not found') {
            Write-Log 'Recycle Bin is already empty.' -Level VERB
        }
        else {
            $result.Failed = 1
            Write-Log ('Failed to clear Recycle Bin: {0}' -f $msg) -Level VERB
        }
    }

    return $result
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Configuration (declarative)
# ═══════════════════════════════════════════════════════════════════════════════


# Deduplicate: $env:TEMP and $env:LOCALAPPDATA\Temp often resolve to the same path
$userTemp = $env:TEMP
$localAppTemp = Join-Path $env:LOCALAPPDATA 'Temp'
$tempIsDuplicate = ($userTemp -eq $localAppTemp)

$Locations = @(
    [PSCustomObject]@{ Label = 'User Temp'; Path = $userTemp; RequireAdmin = $false }
    [PSCustomObject]@{ Label = 'IE Cache (legacy)'; Path = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Temporary Internet Files\Content.IE5'; RequireAdmin = $false }
    [PSCustomObject]@{ Label = 'Windows Temp'; Path = Join-Path $env:SystemRoot 'Temp'; RequireAdmin = $true }
    [PSCustomObject]@{ Label = 'Prefetch'; Path = Join-Path $env:SystemRoot 'Prefetch'; RequireAdmin = $true }
    [PSCustomObject]@{ Label = 'Minidump'; Path = Join-Path $env:SystemRoot 'Minidump'; RequireAdmin = $true }
    [PSCustomObject]@{ Label = 'WU Download Cache'; Path = Join-Path $env:SystemRoot 'SoftwareDistribution\Download'; RequireAdmin = $true }
)

# Only add LocalAppData\Temp if it differs from $env:TEMP
if (-not $tempIsDuplicate) {
    $Locations += [PSCustomObject]@{ Label = 'LocalAppData Temp'; Path = $localAppTemp; RequireAdmin = $false }
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Orchestration
# ═══════════════════════════════════════════════════════════════════════════════

$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

# 1. Clear folders
foreach ($loc in $Locations) {
    $r = Clear-Folder -Path $loc.Path -Label $loc.Label -RequireAdmin:$loc.RequireAdmin
    $results.Add($r)
}

# 2. Clear Recycle Bin (after folders)
if (-not $SkipRecycleBin) {
    $r = Clear-RecycleBinSafe
    $results.Add($r)
}

$stopwatch.Stop()

# ═══════════════════════════════════════════════════════════════════════════════
#  Report
# ═══════════════════════════════════════════════════════════════════════════════

$reportData = $results | ForEach-Object {
    $status = if ($_.Skipped) { "SKIP ($($_.SkipReason))" }
    elseif ($_.Failed -gt 0 -and $_.Deleted -gt 0) { 'PARTIAL' }
    elseif ($_.Failed -gt 0) { 'FAILED' }
    else { 'OK' }
    [PSCustomObject]@{
        Location = $_.Label
        Status   = $status
        Deleted  = $_.Deleted
        Failed   = $_.Failed
        Freed    = Format-Size $_.BytesFreed
    }
}

Write-Information '' -InformationAction Continue
$reportData | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Information $_.TrimEnd() -InformationAction Continue }

$totalFreed = ($results | Measure-Object -Property BytesFreed -Sum).Sum
$elapsedSecs = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
$totalFreedStr = Format-Size $totalFreed
Write-Log "Done - $totalFreedStr freed in ${elapsedSecs}s."

Write-Information '' -InformationAction Continue
Read-Host 'Press Enter to close'