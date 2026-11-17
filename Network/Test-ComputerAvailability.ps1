<#
.SYNOPSIS
Tests whether one or more computers are reachable.

.DESCRIPTION
Tests computer availability using ICMP echo requests through the .NET Ping class.
Computer names or IP addresses can be supplied directly or loaded from a plain-text
file with one target per line.

The script returns structured PowerShell objects instead of raw ping output.
Results can optionally be exported to CSV.

.PARAMETER ComputerName
One or more computer names or IP addresses to test.

.PARAMETER ComputerListPath
Path to a plain-text file containing one computer name or IP address per line.
Blank lines and lines beginning with # are ignored.

.PARAMETER Count
Number of ICMP echo requests to send to each computer. Default is 1.

.PARAMETER TimeoutSeconds
ICMP reply timeout in seconds. DNS resolution may take longer. Default is 2.

.PARAMETER OutputPath
Optional CSV path for the results. If omitted, results are returned only to the
PowerShell pipeline/console.

.EXAMPLE
.\Test-ComputerAvailability.ps1 -ComputerName PC001

Tests PC001 with one ICMP request.

.EXAMPLE
.\Test-ComputerAvailability.ps1 -ComputerName PC001,PC002,192.0.2.20 -Count 2

Tests multiple targets with two ICMP requests per target.

.EXAMPLE
.\Test-ComputerAvailability.ps1 -ComputerListPath C:\Temp\computers.txt -OutputPath C:\Temp\Availability.csv

Loads targets from a text file and exports the structured results to CSV.

.NOTES
ICMP may be blocked by host or network firewalls. A result of Unreachable means
the target did not answer the configured ICMP test; it does not necessarily mean
the computer is powered off.

This utility intentionally uses built-in .NET functionality and does not require
Sysinternals PsPing.
#>

[CmdletBinding(DefaultParameterSetName = 'Direct')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Direct', Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName,

    [Parameter(Mandatory, ParameterSetName = 'File')]
    [ValidateScript({
        if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) {
            throw "Computer list file not found: $_"
        }
        $true
    })]
    [string]$ComputerListPath,

    [ValidateRange(1, 10)]
    [int]$Count = 1,

    [ValidateRange(1, 30)]
    [int]$TimeoutSeconds = 2,

    [string]$OutputPath
)

# Keep the input mode when calling the helper.
$parameterSetName = $PSCmdlet.ParameterSetName

function Get-TargetList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Direct', 'File')]
        [string]$ParameterSetName
    )

    if ($ParameterSetName -eq 'File') {
        return @(
            Get-Content -LiteralPath $ComputerListPath -ErrorAction Stop |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -and -not $_.StartsWith('#') } |
                Sort-Object -Unique
        )
    }

    return @(
        $ComputerName |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
}

$targets = Get-TargetList -ParameterSetName $parameterSetName

if (-not $targets) {
    throw 'No computer names or IP addresses were supplied.'
}

$results = foreach ($target in $targets) {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $ping = $null

    try {
        # No external ping executable is needed.
        $ping = [System.Net.NetworkInformation.Ping]::new()
        $replies = @()
        $lastException = $null

        for ($attempt = 1; $attempt -le $Count; $attempt++) {
            try {
                $reply = $ping.Send($target, ($TimeoutSeconds * 1000))
                $replies += $reply
            }
            catch {
                $lastException = $_.Exception.Message
            }
        }

        $successfulReplies = @(
            $replies | Where-Object {
                $_.Status -eq [System.Net.NetworkInformation.IPStatus]::Success
            }
        )

        $stopwatch.Stop()

        if ($successfulReplies.Count -gt 0) {
            $averageLatency = [math]::Round(
                (($successfulReplies | Measure-Object -Property RoundtripTime -Average).Average),
                2
            )

            [pscustomobject]@{
                ComputerName     = $target
                Reachable        = $true
                Status           = 'Online'
                SuccessfulPings  = $successfulReplies.Count
                AttemptedPings   = $Count
                AverageLatencyMs = $averageLatency
                TestDurationMs   = $stopwatch.ElapsedMilliseconds
                Error            = $null
            }
        }
        else {
            $lastStatus = if ($replies.Count -gt 0) {
                $replies[-1].Status.ToString()
            }
            elseif ($lastException) {
                $lastException
            }
            else {
                'NoReply'
            }

            [pscustomobject]@{
                ComputerName     = $target
                Reachable        = $false
                Status           = 'Unreachable'
                SuccessfulPings  = 0
                AttemptedPings   = $Count
                AverageLatencyMs = $null
                TestDurationMs   = $stopwatch.ElapsedMilliseconds
                Error            = $lastStatus
            }
        }
    }
    catch {
        $stopwatch.Stop()

        [pscustomobject]@{
            ComputerName     = $target
            Reachable        = $false
            Status           = 'Error'
            SuccessfulPings  = 0
            AttemptedPings   = $Count
            AverageLatencyMs = $null
            TestDurationMs   = $stopwatch.ElapsedMilliseconds
            Error            = $_.Exception.Message
        }
    }
    finally {
        if ($null -ne $ping) {
            $ping.Dispose()
        }
    }
}

if ($OutputPath) {
    $outputDirectory = Split-Path -Parent $OutputPath

    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force -ErrorAction Stop | Out-Null
    }

    $results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -ErrorAction Stop
    Write-Verbose "Results exported to $OutputPath"
}

$results
