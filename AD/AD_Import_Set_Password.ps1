<#
.SYNOPSIS
Resets AD user passwords and optionally updates EmployeeID from CSV.

.DESCRIPTION
Reads username and password values from CSV, resets each account password, and
optionally updates EmployeeID when that column/value is present. Supports
-WhatIf / -Confirm and returns per-user results.

.PARAMETER InputPath
Path to the CSV. Required columns: username and password. EmployeeID is optional.

.PARAMETER ChangePasswordAtLogon
Whether to require the user to change the imported password at next logon.
Defaults to true.

.EXAMPLE
.\AD_Import_Set_Password.ps1 -InputPath C:\Temp\ADUsers.csv -WhatIf

.NOTES
The CSV contains plaintext passwords and must be treated as sensitive. Restrict
access to it and securely remove it after the administrative task is complete.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({
        if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) {
            throw "AD user CSV was not found: $_"
        }
        $true
    })]
    [string]$InputPath,

    [bool]$ChangePasswordAtLogon = $true
)

Import-Module ActiveDirectory -ErrorAction Stop

$users = @(Import-Csv -LiteralPath $InputPath -ErrorAction Stop)
if ($users.Count -eq 0) {
    throw 'The AD user CSV is empty.'
}

$requiredColumns = @('username', 'password')
$availableColumns = @($users[0].PSObject.Properties.Name)
$missingColumns = @($requiredColumns | Where-Object { $_ -notin $availableColumns })
if ($missingColumns.Count -gt 0) {
    throw "The CSV is missing required column(s): $($missingColumns -join ', ')"
}

$hasEmployeeId = $availableColumns -contains 'EmployeeID'

$results = foreach ($user in $users) {
    $username = if ($null -ne $user.username) { $user.username.ToString().Trim() } else { '' }
    $password = if ($null -ne $user.password) { $user.password.ToString() } else { '' }
    $employeeId = if ($hasEmployeeId -and $null -ne $user.EmployeeID) { $user.EmployeeID.ToString().Trim() } else { '' }

    if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password)) {
        [pscustomobject]@{
            UserName   = $username
            EmployeeID = $employeeId
            Result     = 'Skipped'
            Error      = 'Username or password is blank.'
        }
        continue
    }

    $completedSteps = @()
    try {
        Get-ADUser -Identity $username -ErrorAction Stop | Out-Null

        if (-not $PSCmdlet.ShouldProcess($username, 'Reset password and update requested user attributes')) {
            [pscustomobject]@{ UserName = $username; EmployeeID = $employeeId; Result = 'NotChanged'; CompletedSteps = @(); Error = $null }
            continue
        }

        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        Set-ADAccountPassword -Identity $username -NewPassword $securePassword -Reset -ErrorAction Stop
        $completedSteps += 'PasswordReset'
        Set-ADUser -Identity $username -ChangePasswordAtLogon $ChangePasswordAtLogon -ErrorAction Stop
        $completedSteps += 'ChangePasswordAtLogon'

        if (-not [string]::IsNullOrWhiteSpace($employeeId)) {
            Set-ADUser -Identity $username -EmployeeID $employeeId -ErrorAction Stop
            $completedSteps += 'EmployeeID'
        }

        [pscustomobject]@{
            UserName   = $username
            EmployeeID = $employeeId
            Result     = 'Updated'
            CompletedSteps = $completedSteps
            Error      = $null
        }
    }
    catch {
        [pscustomobject]@{
            UserName   = $username
            EmployeeID = $employeeId
            Result     = if ($completedSteps.Count) { 'Partial' } else { 'Failed' }
            CompletedSteps = $completedSteps
            Error      = $_.Exception.Message.Replace($password, '[redacted]')
        }
    }
}

$results
