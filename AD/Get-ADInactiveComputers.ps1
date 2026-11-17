<#
.SYNOPSIS
Reports Active Directory computer accounts that have been inactive for a selected period.

.DESCRIPTION
Uses LastLogonDate to identify computer accounts older than the requested cutoff.
Optionally includes accounts that have no lastLogonTimestamp at all. Exports a CSV
and returns the same structured objects to the pipeline.

.NOTES
LastLogonDate is replicated and can lag actual logons. Treat this as a review list,
not proof an account is unused. This script never disables or deletes accounts.

.PARAMETER MonthsInactive
Number of months of inactivity. Default: 3.

.PARAMETER IncludeNeverLoggedOn
Also include computer accounts with no lastLogonTimestamp.

.PARAMETER OutputPath
CSV output path. Defaults to InactiveComputers.csv under TEMP.

.EXAMPLE
.\Get-ADInactiveComputers.ps1 -MonthsInactive 6

.EXAMPLE
.\Get-ADInactiveComputers.ps1 -MonthsInactive 3 -IncludeNeverLoggedOn -OutputPath C:\Temp\Inactive.csv
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 120)]
    [int]$MonthsInactive = 3,

    [switch]$IncludeNeverLoggedOn,

    [string]$OutputPath = "$env:TEMP\InactiveComputers.csv"
)

Import-Module ActiveDirectory -ErrorAction Stop

$cutoffDate = (Get-Date).AddMonths(-$MonthsInactive)
$properties = @('LastLogonDate', 'Description', 'Enabled')

$computers = @(
    Get-ADComputer -Filter { LastLogonDate -lt $cutoffDate } -Properties $properties -ErrorAction Stop
)

if ($IncludeNeverLoggedOn) {
    $neverLoggedOn = @(
        Get-ADComputer -LDAPFilter '(!(lastLogonTimestamp=*))' -Properties $properties -ErrorAction Stop
    )
    $computers += $neverLoggedOn
}

$results = @(
    $computers |
        Sort-Object DistinguishedName -Unique |
        Select-Object Name, DistinguishedName, LastLogonDate, Description, Enabled,
            @{ Name = 'NeverLoggedOn'; Expression = { $null -eq $_.LastLogonDate } }
)

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force -ErrorAction Stop | Out-Null
}

$results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -ErrorAction Stop
Write-Host "Found $($results.Count) inactive computer account(s)."
Write-Host "Report written to: $OutputPath"
$results
