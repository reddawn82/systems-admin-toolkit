<#
.SYNOPSIS
Runs iPerf3 in client or server mode.

.DESCRIPTION
Launches an installed iPerf3 executable in client or server mode.

The script locates iperf3.exe, requires an explicit Client or Server mode, and
passes any additional iPerf3 arguments through unchanged.

.PARAMETER Mode
Selects whether iPerf3 runs as a Client or Server.

.PARAMETER Server
Hostname or IP address of the iPerf3 server. Required when -Mode Client is used.

.PARAMETER IperfPath
Path to iperf3.exe. If omitted, the script first tries PATH and then looks beside
this script.

.PARAMETER IperfArguments
Optional additional arguments passed directly to iPerf3.

.EXAMPLE
.\Invoke-Iperf3.ps1 -Mode Server

Starts an iPerf3 server using the default iPerf3 settings.

.EXAMPLE
.\Invoke-Iperf3.ps1 -Mode Client -Server 192.0.2.10

Runs a default iPerf3 client test against 192.0.2.10.

.EXAMPLE
.\Invoke-Iperf3.ps1 -Mode Client -Server 192.0.2.10 -IperfArguments '-t','30','-P','4','-R'

Runs a 30-second test with four parallel streams in reverse mode.

.EXAMPLE
.\Invoke-Iperf3.ps1 -Mode Server -IperfArguments '-p','5202'

Starts the iPerf3 server on port 5202.

.NOTES
Requires iPerf3 on both endpoints. This script does not install or remotely start
iPerf3 on another machine.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Client', 'Server')]
    [string]$Mode,

    [string]$Server,

    [string]$IperfPath,

    [string[]]$IperfArguments
)

if ($Mode -eq 'Client' -and [string]::IsNullOrWhiteSpace($Server)) {
    throw '-Server is required when -Mode Client is used.'
}

if (-not $IperfPath) {
    $command = Get-Command 'iperf3.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($command) {
        $IperfPath = $command.Source
    }
    else {
        $localIperf = Join-Path $PSScriptRoot 'iperf3.exe'
        if (Test-Path -LiteralPath $localIperf -PathType Leaf) {
            $IperfPath = $localIperf
        }
    }
}

if (-not $IperfPath -or -not (Test-Path -LiteralPath $IperfPath -PathType Leaf)) {
    throw 'iperf3.exe was not found. Add it to PATH, place it beside this script, or supply -IperfPath.'
}

if ([IO.Path]::GetExtension($IperfPath) -ne '.exe') {
    throw '-IperfPath must point to an executable (.exe).'
}
$IperfPath = (Resolve-Path -LiteralPath $IperfPath -ErrorAction Stop).ProviderPath

$arguments = @()

if ($Mode -eq 'Server') {
    $arguments += '-s'
}
else {
    $arguments += '-c'
    $arguments += $Server
}

if ($IperfArguments) {
    $arguments += $IperfArguments
}

Write-Verbose ("Running: {0} {1}" -f $IperfPath, ($arguments -join ' '))

& $IperfPath @arguments
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    throw "iPerf3 exited with code $exitCode."
}
