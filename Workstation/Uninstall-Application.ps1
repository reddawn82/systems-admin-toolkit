<#
.SYNOPSIS
Finds and uninstalls a Windows application registered in the machine uninstall registry.

.DESCRIPTION
Searches the 64-bit and 32-bit machine uninstall registry locations. Exact display
name matching is the default. -Contains enables discovery by partial name, and
-ListOnly safely returns matching applications without uninstalling anything.

Supports MSI and EXE uninstallers, -WhatIf / -Confirm, optional EXE argument
overrides, and structured result output with -PassThru.

.PARAMETER AppName
Application display name. Exact match is used unless -Contains is supplied.

.PARAMETER Contains
Use partial display-name matching.

.PARAMETER ListOnly
Return all matches without uninstalling.

.PARAMETER ExeArguments
Override arguments for an EXE uninstaller.

.PARAMETER NoSilent
Prefer the normal registered uninstall command and do not add MSI silent flags.
If only a quiet uninstall command is registered, that command is used as a fallback.

.PARAMETER ExeSuccessCode
Exit codes considered successful for EXE uninstallers. Default: 0.

.PARAMETER PassThru
Return a structured uninstall result.

.EXAMPLE
.\Uninstall-Application.ps1 -AppName Adobe -Contains -ListOnly

.EXAMPLE
.\Uninstall-Application.ps1 -AppName 'Contoso Agent' -WhatIf

.EXAMPLE
.\Uninstall-Application.ps1 -AppName 'Vendor App' -ExeArguments '/S' -ExeSuccessCode 0,3010 -PassThru

.NOTES
Run elevated when required by the target application. Vendor EXE switches and
success codes vary; verify them before overriding arguments or success codes.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$AppName,

    [switch]$Contains,

    [switch]$ListOnly,

    [string]$ExeArguments,

    [switch]$NoSilent,

    [int[]]$ExeSuccessCode = @(0),

    [switch]$PassThru
)

function Split-ExecutableCommand {
    param([Parameter(Mandatory)][string]$Command)

    if ($Command -match '(?i)^\s*msiexec(?=\s)') { $Command = $Command -replace '(?i)^\s*msiexec(?=\s)', 'msiexec.exe' }
    $quoted = [regex]::Match($Command, '^\s*"([^"]+)"\s*(.*)$')
    if ($quoted.Success) {
        return [pscustomobject]@{
            Executable = $quoted.Groups[1].Value
            Arguments  = $quoted.Groups[2].Value
        }
    }

    # Some uninstall entries contain an unquoted executable path with spaces.
    # Capture through the first .exe boundary instead of splitting at the first space.
    $unquoted = [regex]::Match(
        $Command,
        '^\s*(.+?\.exe)(?:\s+(.*)|\s*)$',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($unquoted.Success) {
        return [pscustomobject]@{
            Executable = $unquoted.Groups[1].Value.Trim()
            Arguments  = $unquoted.Groups[2].Value
        }
    }

    throw "Unable to parse executable uninstall command: $Command"
}

$uninstallPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$installedApps = foreach ($path in $uninstallPaths) {
    Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and ($_.UninstallString -or $_.QuietUninstallString) } |
        Select-Object DisplayName, DisplayVersion, Publisher, UninstallString,
            QuietUninstallString, PSChildName
}

$appMatches = if ($Contains) {
    @($installedApps | Where-Object { $_.DisplayName -like "*$AppName*" })
}
else {
    @($installedApps | Where-Object { $_.DisplayName -eq $AppName })
}

if ($appMatches.Count -eq 0) {
    throw "Application '$AppName' was not found in the machine uninstall registry."
}

if ($ListOnly) {
    $appMatches |
        Sort-Object DisplayName, DisplayVersion |
        ForEach-Object {
            $command = if ($_.QuietUninstallString) { $_.QuietUninstallString } else { $_.UninstallString }
            [pscustomobject]@{
                Application   = $_.DisplayName
                Version       = $_.DisplayVersion
                Publisher     = $_.Publisher
                InstallerType = if ([IO.Path]::GetFileName((Split-ExecutableCommand $command).Executable) -ieq 'msiexec.exe') { 'MSI' } else { 'EXE' }
            }
        }
    return
}

if ($appMatches.Count -gt 1) {
    $names = ($appMatches | Sort-Object DisplayName, DisplayVersion | ForEach-Object {
        if ($_.DisplayVersion) { "$($_.DisplayName) [$($_.DisplayVersion)]" } else { $_.DisplayName }
    }) -join '; '

    throw "Multiple applications matched '$AppName'. Use -ListOnly or a more specific name. Matches: $names"
}

$app = $appMatches[0]
$preferredCommand = if (-not $NoSilent -and $app.QuietUninstallString) {
    $app.QuietUninstallString
}
elseif ($app.UninstallString) {
    $app.UninstallString
}
else {
    $app.QuietUninstallString
}

if ($preferredCommand -match '(?i)^\s*msiexec(?=\s)') { $preferredCommand = $preferredCommand -replace '(?i)^\s*msiexec(?=\s)', 'msiexec.exe' }
$parsedCommand = Split-ExecutableCommand -Command $preferredCommand
$isMsi = [IO.Path]::GetFileName($parsedCommand.Executable) -ieq 'msiexec.exe'
$executable = $null
$arguments = $null

if ($isMsi) {
    $executable = 'msiexec.exe'
    $arguments = $parsedCommand.Arguments.Trim()

    # Convert install/maintenance form to uninstall form without discarding
    # registered transforms, properties, logging switches, or other arguments.
    $arguments = $arguments -replace '(?i)(^|\s)/i(?=\s*\{)', '$1/x'

    if ($arguments -notmatch '(?i)(^|\s)/(x|uninstall)(?=\s|\{)') {
        $productCodeMatch = [regex]::Match($arguments, '\{[0-9A-Fa-f-]{36}\}')
        if (-not $productCodeMatch.Success) {
            throw "Unable to determine an MSI uninstall target from: $preferredCommand"
        }

        $productCode = $productCodeMatch.Value
        $remainingArguments = ($arguments -replace [regex]::Escape($productCode), '').Trim()
        $arguments = "/x $productCode"
        if ($remainingArguments) {
            $arguments += " $remainingArguments"
        }
    }

    if (-not $NoSilent -and $arguments -notmatch '(?i)(/q|/quiet|/passive)') {
        $arguments += ' /qn /norestart'
    }
}
else {
    $parsedCommand = Split-ExecutableCommand -Command $preferredCommand
    $executable = $parsedCommand.Executable
    $arguments = if ($PSBoundParameters.ContainsKey('ExeArguments')) {
        $ExeArguments
    }
    else {
        $parsedCommand.Arguments
    }
}

$commandPreview = if ([string]::IsNullOrWhiteSpace($arguments)) {
    $executable
}
else {
    "$executable $arguments"
}

if (-not $PSCmdlet.ShouldProcess($app.DisplayName, "Uninstall using: $commandPreview")) {
    return
}

$startTime = Get-Date
$errorMessage = $null
$exitCode = $null
$success = $false

try {
    $processParameters = @{
        FilePath    = $executable
        Wait        = $true
        PassThru    = $true
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($arguments)) {
        $processParameters.ArgumentList = $arguments
    }

    $process = Start-Process @processParameters
    $exitCode = $process.ExitCode

    $success = if ($isMsi) {
        $exitCode -in 0, 1641, 3010
    }
    else {
        $exitCode -in $ExeSuccessCode
    }
}
catch {
    $errorMessage = $_.Exception.Message
}

$result = [pscustomobject]@{
    Application     = $app.DisplayName
    Version         = $app.DisplayVersion
    Publisher       = $app.Publisher
    InstallerType   = if ($isMsi) { 'MSI' } else { 'EXE' }
    Command         = $commandPreview
    ExitCode        = $exitCode
    Success         = $success
    RestartRequired = ($isMsi -and $exitCode -in 1641, 3010)
    Started         = $startTime
    Completed       = Get-Date
    Error           = $errorMessage
}

if (-not $success) {
    if ($errorMessage) {
        Write-Warning "Uninstall failed for '$($app.DisplayName)': $errorMessage"
    }
    else {
        Write-Warning "Uninstaller for '$($app.DisplayName)' returned exit code $exitCode."
    }
}

if ($PassThru) {
    $result
}
