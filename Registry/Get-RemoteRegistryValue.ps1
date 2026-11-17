<#
.SYNOPSIS
Queries a registry key or value on one or more remote Windows computers.

.DESCRIPTION
Checks for a registry key or queries a value using either PowerShell remoting or
Sysinternals PsExec. Computer names can be supplied directly or read from a text
file. Results are returned as structured objects and can optionally be exported
to CSV.

.PARAMETER ComputerName
One or more remote computer names.

.PARAMETER ComputerListPath
Text file containing one computer name per line. Blank lines and # comments are ignored.

.PARAMETER RegistryPath
Registry path such as HKLM:\SOFTWARE\Vendor\Product, HKLM\SOFTWARE\Vendor\Product,
or HKEY_LOCAL_MACHINE\SOFTWARE\Vendor\Product. Standard registry hives are accepted.

.PARAMETER ValueName
Optional value to query. If omitted, only key existence is checked.

.PARAMETER Method
PowerShellRemoting (default) or PsExec.

.PARAMETER PsExecPath
Optional explicit path to PsExec64.exe/PsExec.exe. In PsExec mode the script also
tries PATH when this parameter is omitted.

.PARAMETER Credential
Optional credential for PowerShell remoting.

.PARAMETER OutputPath
Optional CSV output path.

.EXAMPLE
.\Get-RemoteRegistryValue.ps1 -ComputerName PC001 -RegistryPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ValueName ProductName

.EXAMPLE
.\Get-RemoteRegistryValue.ps1 -ComputerListPath C:\Temp\computers.txt -RegistryPath 'HKLM\SOFTWARE\Vendor\Product' -Method PsExec -PsExecPath C:\Tools\PsExec64.exe
#>

[CmdletBinding(DefaultParameterSetName = 'Direct')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Direct')]
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName,

    [Parameter(Mandatory, ParameterSetName = 'File')]
    [ValidateScript({
        if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) {
            throw "Computer list file was not found: $_"
        }
        $true
    })]
    [string]$ComputerListPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RegistryPath,

    [string]$ValueName,

    [ValidateSet('PowerShellRemoting', 'PsExec')]
    [string]$Method = 'PowerShellRemoting',

    [string]$PsExecPath,

    [System.Management.Automation.PSCredential]$Credential,

    [string]$OutputPath
)

function ConvertTo-PowerShellRegistryPath {
    param([Parameter(Mandatory)][string]$Path)

    $normalized = $Path.Trim()

    if ($normalized.StartsWith('Registry::', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $normalized
    }

    # Only HKLM: and HKCU: are default PowerShell Registry drives. Convert all
    # supported hive forms to provider-qualified paths so HKCR/HKU/HKCC work too.
    $hives = @(
        [pscustomobject]@{ Short = 'HKLM'; Long = 'HKEY_LOCAL_MACHINE' },
        [pscustomobject]@{ Short = 'HKCU'; Long = 'HKEY_CURRENT_USER' },
        [pscustomobject]@{ Short = 'HKCR'; Long = 'HKEY_CLASSES_ROOT' },
        [pscustomobject]@{ Short = 'HKU';  Long = 'HKEY_USERS' },
        [pscustomobject]@{ Short = 'HKCC'; Long = 'HKEY_CURRENT_CONFIG' }
    )

    foreach ($hive in $hives) {
        foreach ($form in @($hive.Short, "$($hive.Short):", $hive.Long)) {
            if ($normalized.Equals($form, [System.StringComparison]::OrdinalIgnoreCase)) {
                return "Registry::$($hive.Long)"
            }

            $prefix = $form + '\'
            if ($normalized.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $remainder = $normalized.Substring($prefix.Length)
                return "Registry::$($hive.Long)\$remainder"
            }
        }
    }

    return $normalized
}

function ConvertTo-RegExePath {
    param([Parameter(Mandatory)][string]$Path)

    $normalized = $Path.Trim()
    $pairs = @(
        @('^HKLM:\\', 'HKLM\'),
        @('^HKCU:\\', 'HKCU\'),
        @('^HKCR:\\', 'HKCR\'),
        @('^HKU:\\', 'HKU\'),
        @('^HKCC:\\', 'HKCC\'),
        @('^HKEY_LOCAL_MACHINE\\', 'HKLM\'),
        @('^HKEY_CURRENT_USER\\', 'HKCU\'),
        @('^HKEY_CLASSES_ROOT\\', 'HKCR\'),
        @('^HKEY_USERS\\', 'HKU\'),
        @('^HKEY_CURRENT_CONFIG\\', 'HKCC\')
    )

    foreach ($pair in $pairs) {
        if ($normalized -match $pair[0]) {
            return ($normalized -replace $pair[0], $pair[1])
        }
    }

    return $normalized
}

$targets = if ($PSCmdlet.ParameterSetName -eq 'File') {
    @(
        Get-Content -LiteralPath $ComputerListPath -ErrorAction Stop |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') } |
            Sort-Object -Unique
    )
}
else {
    @(
        $ComputerName |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
}

if (-not $targets) {
    throw 'No computer names were supplied.'
}

if ($Method -eq 'PsExec') {
    if (-not $PsExecPath) {
        foreach ($candidate in @('psexec64.exe', 'psexec.exe')) {
            $command = Get-Command $candidate -ErrorAction SilentlyContinue
            if ($command) {
                $PsExecPath = $command.Source
                break
            }
        }
    }

    if (-not $PsExecPath -or -not (Test-Path -LiteralPath $PsExecPath -PathType Leaf)) {
        throw 'PsExec was not found. Supply -PsExecPath or add PsExec to PATH.'
    }
}

$registryInput = $RegistryPath.Trim() -replace '^Registry::', ''
if ($registryInput -notmatch '^(HKLM|HKCU|HKCR|HKU|HKCC|HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER|HKEY_CLASSES_ROOT|HKEY_USERS|HKEY_CURRENT_CONFIG):?(\\.*)?$') {
    throw 'RegistryPath must use a supported registry hive.'
}
$psRegistryPath = ConvertTo-PowerShellRegistryPath -Path $registryInput
$regExePath = ($psRegistryPath -replace '^Registry::', '')

$results = foreach ($computer in $targets) {
    try {
        if ($Method -eq 'PowerShellRemoting') {
            $invokeParams = @{
                ComputerName = $computer
                ErrorAction  = 'Stop'
                ArgumentList = @($psRegistryPath, $ValueName)
                ScriptBlock  = {
                    param($RemoteRegistryPath, $RemoteValueName)

                    if (-not (Test-Path -LiteralPath $RemoteRegistryPath -ErrorAction Stop)) {
                        return [pscustomobject]@{
                            KeyExists   = $false
                            ValueExists = $false
                            Value       = $null
                            Status      = 'KeyNotFound'
                        }
                    }

                    if ([string]::IsNullOrWhiteSpace($RemoteValueName)) {
                        return [pscustomobject]@{
                            KeyExists   = $true
                            ValueExists = $null
                            Value       = $null
                            Status      = 'KeyFound'
                        }
                    }

                    $propertyBag = Get-ItemProperty -LiteralPath $RemoteRegistryPath -ErrorAction Stop
                    $valueProperty = $propertyBag.PSObject.Properties[$RemoteValueName]

                    if ($null -eq $valueProperty) {
                        return [pscustomobject]@{
                            KeyExists   = $true
                            ValueExists = $false
                            Value       = $null
                            Status      = 'ValueNotFound'
                        }
                    }

                    return [pscustomobject]@{
                        KeyExists   = $true
                        ValueExists = $true
                        Value       = $valueProperty.Value
                        Status      = 'Success'
                    }
                }
            }

            if ($Credential) {
                $invokeParams.Credential = $Credential
            }

            $remoteResult = Invoke-Command @invokeParams

            [pscustomobject]@{
                ComputerName = $computer
                Method       = $Method
                RegistryPath = $RegistryPath
                ValueName    = $ValueName
                KeyExists    = $remoteResult.KeyExists
                ValueExists  = $remoteResult.ValueExists
                Value        = $remoteResult.Value
                Status       = $remoteResult.Status
                Error        = $null
            }
        }
        else {
            $arguments = @("\\$computer", '-nobanner', 'reg', 'query', $regExePath)
            if (-not [string]::IsNullOrWhiteSpace($ValueName)) {
                $arguments += @('/v', $ValueName)
            }

            $output = & $PsExecPath @arguments 2>&1
            $exitCode = $LASTEXITCODE
            $outputText = (($output | ForEach-Object { $_.ToString() }) -join ' ').Trim()

            if ($exitCode -ne 0) {
                [pscustomobject]@{
                    ComputerName = $computer
                    Method       = $Method
                    RegistryPath = $RegistryPath
                    ValueName    = $ValueName
                    KeyExists    = $null
                    ValueExists  = $null
                    Value        = $null
                    Status       = 'QueryFailed'
                    Error        = $outputText
                }
                continue
            }

            $parsedValue = $null
            if (-not [string]::IsNullOrWhiteSpace($ValueName)) {
                $valuePattern = "^\s*$([regex]::Escape($ValueName))\s+REG_\S+\s+(.+)$"
                $matchingLine = $output | Where-Object { $_.ToString() -match $valuePattern } | Select-Object -First 1
                if ($matchingLine -and $matchingLine.ToString() -match $valuePattern) {
                    $parsedValue = $Matches[1].Trim()
                }
            }

            [pscustomobject]@{
                ComputerName = $computer
                Method       = $Method
                RegistryPath = $RegistryPath
                ValueName    = $ValueName
                KeyExists    = $true
                ValueExists  = if ($ValueName) { $null -ne $parsedValue } else { $null }
                Value        = $parsedValue
                Status       = if ($ValueName -and $null -eq $parsedValue) { 'ValueNotParsed' } else { 'Success' }
                Error        = if ($ValueName -and $null -eq $parsedValue) { 'REG QUERY succeeded but the requested value could not be parsed.' } else { $null }
            }
        }
    }
    catch {
        [pscustomobject]@{
            ComputerName = $computer
            Method       = $Method
            RegistryPath = $RegistryPath
            ValueName    = $ValueName
            KeyExists    = $null
            ValueExists  = $null
            Value        = $null
            Status       = 'Error'
            Error        = $_.Exception.Message
        }
    }
}

if ($OutputPath) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
    }

    $results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -ErrorAction Stop
    Write-Verbose "Results written to: $OutputPath"
}

$results
