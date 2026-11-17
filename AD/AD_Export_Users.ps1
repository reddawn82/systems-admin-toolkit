<#
.SYNOPSIS
Exports users from a specified Active Directory search base.

.DESCRIPTION
Exports user identity and account status, with optional extra AD attributes.

.PARAMETER SearchBase
Distinguished name of the OU/container to search.

.PARAMETER AdditionalProperty
Optional additional AD attributes to retrieve and include in the report.

.PARAMETER OutputPath
CSV output path. Defaults to AD_Users_Status.csv under TEMP.

.EXAMPLE
.\AD_Export_Users.ps1 -SearchBase 'OU=Users,DC=contoso,DC=com'

.EXAMPLE
.\AD_Export_Users.ps1 -SearchBase 'OU=Users,DC=contoso,DC=com' -AdditionalProperty EmployeeID
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SearchBase,

    [string[]]$AdditionalProperty,

    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = "$env:TEMP\AD_Users_Status.csv"
)

Import-Module ActiveDirectory -ErrorAction Stop

$baseProperties = @('Enabled')
$requestedProperties = @(
    $baseProperties +
    ($AdditionalProperty | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) |
    Sort-Object -Unique
)

$selectProperties = @('Name', 'SamAccountName', 'UserPrincipalName') +
    ($AdditionalProperty | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) +
    'Enabled'
$selectProperties = @($selectProperties | Sort-Object -Unique)

$results = @(
    Get-ADUser -Filter * -SearchBase $SearchBase -Properties $requestedProperties -ErrorAction Stop |
        Select-Object -Property $selectProperties
)

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force -ErrorAction Stop | Out-Null
}

$results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -ErrorAction Stop
Write-Host "Exported $($results.Count) user(s) to: $OutputPath"
$results
