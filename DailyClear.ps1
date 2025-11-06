[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [switch]$IncludeRecycleBin = $true
)

# Detect elevation
$IsElevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltinRole]::Administrator)

if (-not $IsElevated) {
    Write-Verbose "Not elevated: some locations (e.g. C:\Windows\Temp) may fail."
}

function Clear-Folder {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [switch]$RequireAdmin
    )

    if ($RequireAdmin -and -not $IsElevated) {
        Write-Warning "Skipping '$Path' (requires administrative privileges)."
        return
    }

    if (-not (Test-Path -Path $Path)) {
        Write-Verbose "Path not found: $Path"
        return
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Remove contents')) {
        try {
            Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue |
                ForEach-Object {
                    try {
                        Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction Stop
                        Write-Verbose "Deleted: $($_.FullName)"
                    } catch {
                        Write-Warning "Cannot delete: $($_.FullName) - $($_.Exception.Message)"
                    }
                }
            Write-Output "Cleared: $Path"
        } catch {
            Write-Warning "Failed to clear $Path - $($_.Exception.Message)"
        }
    }
}

# Standard locations
$trashDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Temporary Internet Files\Content.IE5'
$tempDir = $env:TEMP
$windowsTemp = 'C:\Windows\Temp'

# Clear Recycle Bin if requested
if ($IncludeRecycleBin) {
    if (Get-Command -Name Clear-RecycleBin -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess('Recycle Bin', 'Clear')) {
            try {
                Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                Write-Output "Recycle Bin cleared."
            } catch {
                Write-Warning "Failed to clear Recycle Bin: $($_.Exception.Message)"
            }
        }
    } else {
        Write-Verbose "Clear-RecycleBin cmdlet not available."
    }
}

# Execute clears
Clear-Folder -Path $trashDir
Clear-Folder -Path $tempDir
Clear-Folder -Path $windowsTemp -RequireAdmin

Write-Output "Bin and temporary folders clear attempt finished."