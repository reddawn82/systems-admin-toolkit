<#
.SYNOPSIS
Purges the contents of one or more folders while leaving each target folder in place.

.DESCRIPTION
Uses Robocopy /PURGE with a verified-empty source folder to remove the contents of
target folders. The script rejects drive roots and UNC share roots, validates that
the empty source really is empty, prevents a target from containing the script's
empty-source or log directories, supports -WhatIf / -Confirm, records Robocopy
exit codes, and returns structured results.

By default, live purges require confirmation. Use -Force for an unattended live
run. -Force suppresses the confirmation prompt but does not bypass any target,
path, empty-source, or Robocopy safety validation.

.PARAMETER Target
One or more local or UNC folders whose CONTENTS should be removed.

.PARAMETER EmptySource
Folder used as the empty Robocopy source. It is created if missing and the script
refuses to continue if it contains any files or folders.

.PARAMETER LogRoot
Directory used for per-target Robocopy logs.

.PARAMETER RobocopyPath
Optional explicit path to robocopy.exe. If omitted, robocopy.exe is resolved from PATH.

.PARAMETER Force
Runs a live purge without prompting for confirmation. All path and safety checks
still apply. -WhatIf remains non-destructive even when -Force is supplied.

.EXAMPLE
.\Delete_Multiple_Directories.ps1 -Target '\\server\share\OldProject' -WhatIf

Runs Robocopy in list-only mode so the purge can be reviewed without deleting data.

.EXAMPLE
.\Delete_Multiple_Directories.ps1 -Target 'D:\Archive\Project1','D:\Archive\Project2'

Prompts for confirmation before purging each target.

.EXAMPLE
.\Delete_Multiple_Directories.ps1 -Target 'D:\Archive\Project1','D:\Archive\Project2' -Force

Purges both target folders without confirmation prompts. Safety validation and
Robocopy exit-code checking remain enabled.

.NOTES
This permanently removes destination contents; it does not use the Recycle Bin.
Path checks do not establish junction/symlink containment. Do not use redirected
paths or trees with reparse points. Review every target carefully before approving a
live run. PowerShell's standard -Confirm:$false can also suppress confirmation;
-Force is provided as an explicit automation-friendly option.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Target,

    [string]$EmptySource = "$env:TEMP\ScriptLab_LPDEL_EMPTY",

    [string]$LogRoot = "$env:TEMP\ScriptLab_Logs\LPDEL",

    [string]$RobocopyPath,

    [switch]$Force
)

function Test-SafePurgeTarget {
    param([Parameter(Mandatory)][string]$Path)

    $trimmed = $Path.Trim().TrimEnd('\')

    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $false
    }

    # Never permit a drive root such as C:\ or a UNC share root such as \\server\share.
    if ($trimmed -match '^[A-Za-z]:$' -or $trimmed -match '^\\\\[^\\]+\\[^\\]+$') {
        return $false
    }

    return $true
}

function Get-NormalizedProviderPath {
    param([Parameter(Mandatory)][string]$Path)

    return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath.TrimEnd('\')
}

function Test-PathContainsPath {
    param(
        [Parameter(Mandatory)][string]$ParentPath,
        [Parameter(Mandatory)][string]$ChildPath
    )

    if ($ChildPath.Equals($ParentPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return $ChildPath.StartsWith(
        ($ParentPath + [IO.Path]::DirectorySeparatorChar),
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

if (-not $RobocopyPath) {
    $robocopyCommand = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if ($robocopyCommand) {
        $RobocopyPath = $robocopyCommand.Source
    }
}

if (-not $RobocopyPath -or -not (Test-Path -LiteralPath $RobocopyPath -PathType Leaf)) {
    throw 'robocopy.exe was not found. Supply -RobocopyPath or ensure it is available in PATH.'
}

if (-not (Test-Path -LiteralPath $EmptySource -PathType Container)) {
    New-Item -ItemType Directory -Path $EmptySource -Force | Out-Null
}

$unexpectedSourceContent = Get-ChildItem -LiteralPath $EmptySource -Force -ErrorAction Stop | Select-Object -First 1
if ($unexpectedSourceContent) {
    throw "EmptySource '$EmptySource' is not empty. Refusing to run /PURGE."
}

if (-not (Test-Path -LiteralPath $LogRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$emptySourceFull = Get-NormalizedProviderPath -Path $EmptySource
$logRootFull = Get-NormalizedProviderPath -Path $LogRoot

# -Force is an explicit unattended mode. It only suppresses ShouldProcess's
# confirmation prompt; it does not disable -WhatIf or any validation below.
if ($Force) {
    $ConfirmPreference = 'None'
}

$results = foreach ($rawTarget in ($Target | Sort-Object -Unique)) {
    $targetPath = $rawTarget.Trim()

    if (-not (Test-SafePurgeTarget -Path $targetPath)) {
        [pscustomobject]@{
            Target       = $targetPath
            Mode         = if ($WhatIfPreference) { 'Preview' } else { 'Live' }
            Result       = 'Rejected'
            RobocopyCode = $null
            LogPath      = $null
            Error        = 'Target is blank, a drive root, or a UNC share root.'
        }
        continue
    }

    if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
        [pscustomobject]@{
            Target       = $targetPath
            Mode         = if ($WhatIfPreference) { 'Preview' } else { 'Live' }
            Result       = 'NotFound'
            RobocopyCode = $null
            LogPath      = $null
            Error        = 'Target folder does not exist or is not accessible.'
        }
        continue
    }

    $targetFull = Get-NormalizedProviderPath -Path $targetPath

    # Check the resolved provider path too. Relative paths or .. segments can
    # otherwise resolve to a drive/share root after the raw input check.
    if (-not (Test-SafePurgeTarget -Path $targetFull)) {
        [pscustomobject]@{
            Target       = $targetPath
            Mode         = if ($WhatIfPreference) { 'Preview' } else { 'Live' }
            Result       = 'Rejected'
            RobocopyCode = $null
            LogPath      = $null
            Error        = "Target resolves to a drive root or UNC share root: $targetFull"
        }
        continue
    }

    if ((Test-PathContainsPath -ParentPath $targetFull -ChildPath $emptySourceFull) -or
        (Test-PathContainsPath -ParentPath $targetFull -ChildPath $logRootFull)) {
        [pscustomobject]@{
            Target       = $targetPath
            Mode         = if ($WhatIfPreference) { 'Preview' } else { 'Live' }
            Result       = 'Rejected'
            RobocopyCode = $null
            LogPath      = $null
            Error        = 'Target contains the configured EmptySource or LogRoot. Move those support directories outside the purge target.'
        }
        continue
    }

    $safeName = ($targetPath -replace '[\\/:*?"<>| ]', '_')
    $logPath = Join-Path $LogRoot ("LPDEL_{0}.log" -f $safeName)

    $arguments = @(
        $EmptySource,
        $targetPath,
        '/PURGE',
        '/R:2',
        '/W:2',
        '/NP',
        '/NDL',
        '/NJS',
        '/NJH',
        "/UNILOG:$logPath"
    )

    $approved = $PSCmdlet.ShouldProcess($targetPath, 'Purge all contents with Robocopy /PURGE')

    if ($WhatIfPreference) {
        # Give -WhatIf a useful file-level preview while keeping Robocopy non-destructive.
        $previewArguments = $arguments + '/L'
        & $RobocopyPath @previewArguments | Out-Null
        $exitCode = $LASTEXITCODE

        [pscustomobject]@{
            Target       = $targetPath
            Mode         = 'Preview'
            Result       = if ($exitCode -lt 8) { 'PreviewComplete' } else { 'PreviewFailed' }
            RobocopyCode = $exitCode
            LogPath      = $logPath
            Error        = if ($exitCode -lt 8) { $null } else { "Robocopy returned exit code $exitCode." }
        }
        continue
    }

    if (-not $approved) {
        continue
    }

    & $RobocopyPath @arguments | Out-Null
    $exitCode = $LASTEXITCODE

    [pscustomobject]@{
        Target       = $targetPath
        Mode         = 'Live'
        Result       = if ($exitCode -lt 8) { 'Success' } else { 'Failed' }
        RobocopyCode = $exitCode
        LogPath      = $logPath
        Error        = if ($exitCode -lt 8) { $null } else { "Robocopy returned exit code $exitCode." }
    }
}

$results
