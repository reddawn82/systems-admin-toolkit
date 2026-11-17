<#
.SYNOPSIS
Creates Active Directory users from a CSV file.

.DESCRIPTION
Creates users from a CSV containing username, password, firstname, lastname,
description, and ou columns. The UPN suffix is supplied explicitly rather than
being hard-coded. Existing sAMAccountName values are skipped.

Supports -WhatIf / -Confirm and returns a result object for every CSV row.

.PARAMETER InputPath
Path to the user-import CSV.

.PARAMETER UserPrincipalNameSuffix
UPN suffix such as contoso.com or another suffix configured in Active Directory.

.PARAMETER ChangePasswordAtLogon
Whether users must change the imported initial password at first logon. Defaults to true.

.EXAMPLE
.\AD_Import_Users.ps1 -InputPath C:\Temp\users.csv -UserPrincipalNameSuffix contoso.com -WhatIf

.NOTES
The CSV contains plaintext initial passwords and must be treated as sensitive.
Restrict access to it and securely remove it when the provisioning task is complete.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({
        if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) {
            throw "User import CSV was not found: $_"
        }
        $true
    })]
    [string]$InputPath,

    [Parameter(Mandatory)]
    [ValidatePattern('^[^@\s]+$')]
    [string]$UserPrincipalNameSuffix,

    [bool]$ChangePasswordAtLogon = $true
)

Import-Module ActiveDirectory -ErrorAction Stop

$users = @(Import-Csv -LiteralPath $InputPath -ErrorAction Stop)
if ($users.Count -eq 0) {
    throw 'The user import CSV is empty.'
}

$requiredColumns = @('username', 'password', 'firstname', 'lastname', 'description', 'ou')
$availableColumns = @($users[0].PSObject.Properties.Name)
$missingColumns = @($requiredColumns | Where-Object { $_ -notin $availableColumns })
if ($missingColumns.Count -gt 0) {
    throw "The CSV is missing required column(s): $($missingColumns -join ', ')"
}

$results = foreach ($user in $users) {
    $username = ([string]$user.username).Trim()
    $password = ([string]$user.password)
    $firstName = ([string]$user.firstname).Trim()
    $lastName = ([string]$user.lastname).Trim()
    $description = if ($null -ne $user.description) { $user.description.ToString() } else { '' }
    $ou = ([string]$user.ou).Trim()

    if ([string]::IsNullOrWhiteSpace($username) -or
        [string]::IsNullOrWhiteSpace($password) -or
        [string]::IsNullOrWhiteSpace($firstName) -or
        [string]::IsNullOrWhiteSpace($lastName) -or
        [string]::IsNullOrWhiteSpace($ou)) {
        [pscustomobject]@{
            UserName = $username
            Result   = 'Skipped'
            Error    = 'One or more required values are blank.'
        }
        continue
    }

    try {
        $existingUser = $null
        try {
            $existingUser = Get-ADUser -Identity $username -ErrorAction Stop
        }
        catch {
            # Only an explicit missing identity allows creation to proceed.
            if ($_.Exception.GetType().FullName -ne 'Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException') {
                throw
            }
        }
        if ($existingUser) {
            [pscustomobject]@{
                UserName = $username
                Result   = 'AlreadyExists'
                Error    = $null
            }
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($username, "Create Active Directory user in '$ou'")) {
            [pscustomobject]@{ UserName = $username; Result = 'NotChanged'; Error = $null }
            continue
        }

        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force

        New-ADUser `
            -SamAccountName $username `
            -UserPrincipalName "$username@$UserPrincipalNameSuffix" `
            -Name "$firstName $lastName" `
            -GivenName $firstName `
            -Surname $lastName `
            -Enabled $true `
            -ChangePasswordAtLogon $ChangePasswordAtLogon `
            -DisplayName "$lastName, $firstName" `
            -Description $description `
            -Path $ou `
            -AccountPassword $securePassword `
            -ErrorAction Stop

        [pscustomobject]@{
            UserName = $username
            Result   = 'Created'
            Error    = $null
        }
    }
    catch {
        [pscustomobject]@{
            UserName = $username
            Result   = 'Failed'
            Error    = $_.Exception.Message.Replace($password, '[redacted]')
        }
    }
}

$results
