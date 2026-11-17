<#
.SYNOPSIS
Reports interactive user sessions on one or more Windows computers.

.DESCRIPTION
Queries remote Windows computers for interactive user sessions. Computer names
can be supplied directly or loaded from a plain-text file.

By default, the script uses the built-in QUser command to query console and RDP
sessions without requiring Sysinternals. An optional PSLoggedOn method is
available for environments where Sysinternals PSLoggedOn is preferred.

The script returns structured PowerShell objects and can optionally export them
to CSV.

.PARAMETER ComputerName
One or more remote computer names to query.

.PARAMETER ComputerListPath
Path to a plain-text file containing one computer name per line. Blank lines and
lines beginning with # are ignored.

.PARAMETER Method
Remote query method to use.

QUser:
Uses the built-in quser.exe command with /server. This is the default and is best
for interactive console/RDP session reporting.

PSLoggedOn:
Uses Sysinternals PSLoggedOn. Supply -PSLoggedOnPath when the executable is not
available through PATH.

.PARAMETER PSLoggedOnPath
Path to PSLoggedOn.exe or PSLoggedOn64.exe. Used only with -Method PSLoggedOn.
If omitted, the script attempts to invoke psloggedon.exe from PATH.

.PARAMETER OutputPath
Optional CSV output path.

.EXAMPLE
.\Get-RemoteLoggedOnUser.ps1 -ComputerName PC001

Queries PC001 using QUser.

.EXAMPLE
.\Get-RemoteLoggedOnUser.ps1 -ComputerName PC001,PC002

Queries multiple computers.

.EXAMPLE
.\Get-RemoteLoggedOnUser.ps1 -ComputerListPath C:\Temp\computers.txt -OutputPath C:\Temp\LoggedOnUsers.csv

Loads computers from a text file and exports results to CSV.

.EXAMPLE
.\Get-RemoteLoggedOnUser.ps1 -ComputerListPath C:\Temp\computers.txt -Method PSLoggedOn -PSLoggedOnPath C:\Tools\PSLoggedOn.exe

Uses Sysinternals PSLoggedOn instead of QUser.

.NOTES
QUser and PSLoggedOn expose different kinds of logon information. QUser focuses
on interactive terminal sessions such as console and RDP. PSLoggedOn can report
additional local/resource logon information. PSLoggedOn records are returned as
RawOutput, not parsed usernames. Review and accept its license separately before
using it; this script does not accept license terms for you.

QUser parsing assumes whitespace-separated fields and a username without spaces.
Localized state and date text are preserved, not interpreted. Unsupported rows
are returned as ParseError. CSV output overwrites an existing file.

Remote querying depends on network reachability, permissions, and the remote
services/protocols required by the selected method.
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

    [ValidateSet('QUser', 'PSLoggedOn')]
    [string]$Method = 'QUser',

    [string]$PSLoggedOnPath,

    [string]$OutputPath
)

$parameterSetName = $PSCmdlet.ParameterSetName

$targets = if ($parameterSetName -eq 'File') {
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

function ConvertFrom-QUserOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Output,

        [Parameter(Mandatory)]
        [string]$Computer
    )

    $dataLines = @(
        $Output |
            Select-Object -Skip 1 |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    foreach ($line in $dataLines) {
        # Session names are absent for disconnected sessions. Keep the date as text.
        $normalized = $line.TrimStart().TrimStart('>').Trim()
        $pattern = '^(?<user>\S+)\s+(?:(?<session>\S+)\s+)?(?<id>\d+)\s+(?<state>\S+)\s+(?<idle>\S+)\s+(?<logon>.+)$'
        if ($normalized -notmatch $pattern) {
            [pscustomobject]@{
                ComputerName = $Computer
                UserName     = $null
                SessionName  = $null
                SessionId    = $null
                State        = $null
                IdleTime     = $null
                LogonTime    = $null
                RawOutput    = $null
                Method       = 'QUser'
                Status       = 'ParseError'
                Error        = "Unable to parse QUser output: $line"
            }
            continue
        }
        $userName = $Matches['user']
        $sessionName = if ($Matches['session']) { $Matches['session'] } else { $null }
        $sessionId = $Matches['id']
        $state = $Matches['state']
        $idleTime = $Matches['idle']
        $logonTime = $Matches['logon']

        [pscustomobject]@{
            ComputerName = $Computer
            UserName     = $userName
            SessionName  = $sessionName
            SessionId    = $sessionId
            State        = $state
            IdleTime     = $idleTime
            LogonTime    = $logonTime
            RawOutput    = $null
            Method       = 'QUser'
            Status       = 'Success'
            Error        = $null
        }
    }
}

function Invoke-QUserQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Computer
    )

    $output = & quser.exe "/server:$Computer" 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        $parsed = @(ConvertFrom-QUserOutput -Output $output -Computer $Computer)

        if ($parsed.Count -gt 0) {
            return $parsed
        }

        return [pscustomobject]@{
            ComputerName = $Computer
            UserName     = $null
            SessionName  = $null
            SessionId    = $null
            State        = $null
            IdleTime     = $null
            LogonTime    = $null
            RawOutput    = $null
            Method       = 'QUser'
            Status       = 'NoSessions'
            Error        = $null
        }
    }

    return [pscustomobject]@{
        ComputerName = $Computer
        UserName     = $null
        SessionName  = $null
        SessionId    = $null
        State        = $null
        IdleTime     = $null
        LogonTime    = $null
        RawOutput    = $null
        Method       = 'QUser'
        Status       = 'Error'
        Error        = (($output | ForEach-Object { $_.ToString() }) -join ' ').Trim()
    }
}

function Invoke-PSLoggedOnQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Computer
    )

    $command = if ($PSLoggedOnPath) {
        if (-not (Test-Path -LiteralPath $PSLoggedOnPath -PathType Leaf)) {
            throw "PSLoggedOn executable not found: $PSLoggedOnPath"
        }
        $PSLoggedOnPath
    }
    else {
        'psloggedon.exe'
    }

    $output = & $command "\\$Computer" 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        return [pscustomobject]@{
            ComputerName = $Computer
            UserName     = $null
            SessionName  = $null
            SessionId    = $null
            State        = $null
            IdleTime     = $null
            LogonTime    = $null
            RawOutput    = $null
            Method       = 'PSLoggedOn'
            Status       = 'Error'
            Error        = (($output | ForEach-Object { $_.ToString() }) -join ' ').Trim()
        }
    }

    $users = @(
        $output |
            ForEach-Object { $_.ToString().Trim() } |
            Where-Object {
                $_ -and
                $_ -notmatch '^PsLoggedon' -and
                $_ -notmatch '^Copyright' -and
                $_ -notmatch '^Sysinternals' -and
                $_ -notmatch '^Users logged on locally:' -and
                $_ -notmatch '^Users logged on via resource shares:' -and
                $_ -notmatch '^No one is logged on'
            } |
            Where-Object { $_ -match '\\' } |
            Sort-Object -Unique
    )

    if ($users.Count -eq 0) {
        return [pscustomobject]@{
            ComputerName = $Computer
            UserName     = $null
            SessionName  = $null
            SessionId    = $null
            State        = $null
            IdleTime     = $null
            LogonTime    = $null
            RawOutput    = $null
            Method       = 'PSLoggedOn'
            Status       = 'NoSessions'
            Error        = $null
        }
    }

    foreach ($user in $users) {
        [pscustomobject]@{
            ComputerName = $Computer
            UserName     = $null
            SessionName  = $null
            SessionId    = $null
            State        = $null
            IdleTime     = $null
            LogonTime    = $null
            RawOutput    = $user
            Method       = 'PSLoggedOn'
            Status       = 'RawOutput'
            Error        = $null
        }
    }
}

$results = foreach ($target in $targets) {
    try {
        if ($Method -eq 'PSLoggedOn') {
            Invoke-PSLoggedOnQuery -Computer $target
        }
        else {
            Invoke-QUserQuery -Computer $target
        }
    }
    catch {
        [pscustomobject]@{
            ComputerName = $target
            UserName     = $null
            SessionName  = $null
            SessionId    = $null
            State        = $null
            IdleTime     = $null
            LogonTime    = $null
            RawOutput    = $null
            Method       = $Method
            Status       = 'Error'
            Error        = $_.Exception.Message
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
