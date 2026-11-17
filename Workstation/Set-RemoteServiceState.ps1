<#
.SYNOPSIS
Enables or disables one or more Windows services on multiple remote computers.

.DESCRIPTION
Reads computer names from a CSV file and manages one or more Windows services on
each remote system through Win32_Service/WMI.

Enable sets startup mode to Automatic and ensures the service is running.
Disable stops the service and ensures startup mode is Disabled.

The script treats an already-running or already-stopped service as a valid state,
waits for pending transitions to settle, verifies the final state, exports a CSV
report, and returns structured result objects.

.PARAMETER ServiceName
One or more Windows service names. Use service names rather than display names.

.PARAMETER Action
Mandatory action: Enable or Disable. There is no default.

.PARAMETER ComputerListPath
CSV containing a ComputerName column.

.PARAMETER OutputPath
CSV results path. Defaults to ServiceOutput.csv under TEMP.

.PARAMETER Credential
Optional credential for remote WMI. If omitted, uses the current identity.

.PARAMETER TimeoutSeconds
Maximum time to wait for a service to reach the requested running/stopped state.
Default: 30 seconds.

.EXAMPLE
.\Set-RemoteServiceState.ps1 -ServiceName RemoteRegistry -Action Enable -ComputerListPath C:\Temp\computers.csv

.EXAMPLE
.\Set-RemoteServiceState.ps1 -ServiceName RemoteRegistry,BITS -Action Disable -ComputerListPath C:\Temp\computers.csv

.NOTES
Uses Get-WmiObject for Windows PowerShell 5.1 / DCOM-style remote administration.
Get-WmiObject is not available in PowerShell 7.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ServiceName,

    [Parameter(Mandatory)]
    [ValidateSet('Enable', 'Disable')]
    [string]$Action,

    [Parameter(Mandatory)]
    [ValidateScript({
        if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) {
            throw "Computer list CSV was not found: $_"
        }
        $true
    })]
    [string]$ComputerListPath,

    [string]$OutputPath = "$env:TEMP\ServiceOutput.csv",

    [System.Management.Automation.PSCredential]$Credential,

    [ValidateRange(1, 300)]
    [int]$TimeoutSeconds = 30
)

$rows = @(Import-Csv -LiteralPath $ComputerListPath -ErrorAction Stop)
if ($rows.Count -eq 0) {
    throw 'The computer list CSV is empty.'
}

if (-not ($rows[0].PSObject.Properties.Name -contains 'ComputerName')) {
    throw "The computer list CSV must contain a column named 'ComputerName'."
}

$computers = @(
    $rows.ComputerName |
        ForEach-Object { if ($null -ne $_) { $_.ToString().Trim() } } |
        Where-Object { $_ } |
        Sort-Object -Unique
)

if ($computers.Count -eq 0) {
    throw 'The computer list CSV does not contain any non-blank ComputerName values.'
}

$serviceNames = @(
    $ServiceName |
        ForEach-Object { if ($null -ne $_) { $_.Trim() } } |
        Where-Object { $_ } |
        Sort-Object -Unique
)

if ($serviceNames.Count -eq 0) {
    throw 'No non-blank service names were supplied.'
}

function Get-RemoteWmiService {
    param(
        [Parameter(Mandatory)][string]$Computer,
        [Parameter(Mandatory)][string]$Name
    )

    $query = @{ Class='Win32_Service'; ComputerName=$Computer; ErrorAction='Stop' }
    if ($null -ne $Credential) { $query.Credential = $Credential }
    Get-WmiObject @query | Where-Object { $_.Name -eq $Name }
}

$results = foreach ($computer in $computers) {
    foreach ($name in $serviceNames) {
        if (-not $PSCmdlet.ShouldProcess("$computer/$name", "$Action service and startup mode")) { continue }
        try {
            $service = Get-RemoteWmiService -Computer $computer -Name $name
            if (-not $service) {
                throw "Service '$name' was not found."
            }

            $initialState = $service.State
            $initialStartMode = $service.StartMode
            $modeCode = 0
            $actionCode = 0

            if ($Action -eq 'Enable') {
                if ($service.StartMode -ne 'Auto') {
                    $modeCode = $service.ChangeStartMode('Automatic').ReturnValue
                }

                if ($modeCode -eq 0 -and $service.State -ne 'Running') {
                    $actionCode = $service.StartService().ReturnValue
                }

                $desiredState = 'Running'
                $desiredStartMode = 'Auto'
            }
            else {
                if ($service.State -ne 'Stopped') {
                    $actionCode = $service.StopService().ReturnValue
                }

                if ($service.StartMode -ne 'Disabled') {
                    $modeCode = $service.ChangeStartMode('Disabled').ReturnValue
                }

                $desiredState = 'Stopped'
                $desiredStartMode = 'Disabled'
            }

            $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
            do {
                $finalService = Get-RemoteWmiService -Computer $computer -Name $name
                $stateReady = ($finalService.State -eq $desiredState)
                $modeReady = ($finalService.StartMode -eq $desiredStartMode)

                if ($stateReady -and $modeReady) {
                    break
                }

                if ((Get-Date) -lt $deadline) {
                    Start-Sleep -Seconds 1
                }
            } while ((Get-Date) -lt $deadline)

            $success = (
                $modeCode -eq 0 -and
                $actionCode -in 0, 6, 10 -and
                $finalService.State -eq $desiredState -and
                $finalService.StartMode -eq $desiredStartMode
            )

            [pscustomobject]@{
                ComputerName     = $computer
                ServiceName      = $name
                Action           = $Action
                Result           = if ($success) { 'Success' } else { 'Failed' }
                InitialState     = $initialState
                InitialStartMode = $initialStartMode
                FinalState       = $finalService.State
                FinalStartMode   = $finalService.StartMode
                ModeCode         = $modeCode
                ActionCode       = $actionCode
                Error            = if ($success) { $null } else { 'The service did not reach the requested final state or a WMI method returned an error code.' }
            }
        }
        catch {
            [pscustomobject]@{
                ComputerName     = $computer
                ServiceName      = $name
                Action           = $Action
                Result           = 'Failed'
                InitialState     = $null
                InitialStartMode = $null
                FinalState       = $null
                FinalStartMode   = $null
                ModeCode         = $null
                ActionCode       = $null
                Error            = $_.Exception.Message
            }
        }
    }
}

if ($WhatIfPreference) { return }
$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force -ErrorAction Stop | Out-Null
}

$results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -ErrorAction Stop
Write-Host "Results written to: $OutputPath"
$results
