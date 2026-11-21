# Run in a fresh process. All AD commands are local mocks.
$ErrorActionPreference='Stop'
$scriptDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'AD'
Add-Type 'namespace Microsoft.ActiveDirectory.Management { public class ADIdentityNotFoundException : System.Exception { public ADIdentityNotFoundException(string m) : base(m) {} } }'
function Assert($ok,$m){if(-not $ok){throw $m}}
function Throws([scriptblock]$c){$yes=$false;try{& $c|Out-Null}catch{$yes=$true};Assert $yes 'Expected error'}
function Import-Module { [CmdletBinding()]param($Name);Assert ($Name -eq 'ActiveDirectory') 'Unexpected module' }
$global:ADMutationMode='missing';$global:ADMutationCalls=@()
function Get-ADUser {
 [CmdletBinding()]param($Identity)
 if($global:ADMutationMode -eq 'missing'){throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]::new('Synthetic missing identity')}
 if($global:ADMutationMode -eq 'lookup-failure'){throw 'Synthetic directory unavailable'}
 [pscustomobject]@{SamAccountName=$Identity}
}
function New-ADUser {
 [CmdletBinding()]param($SamAccountName,$UserPrincipalName,$Name,$GivenName,$Surname,$Enabled,$ChangePasswordAtLogon,$DisplayName,$Description,$Path,$AccountPassword)
 Assert ($AccountPassword -is [securestring]) 'Password must be SecureString'
 $global:ADMutationCalls+='Create'
}
function Set-ADAccountPassword {
 [CmdletBinding()]param($Identity,$NewPassword,[switch]$Reset)
 Assert ($NewPassword -is [securestring]) 'Password must be SecureString'
 if($global:ADMutationMode -eq 'reset-failure'){throw 'Synthetic reset failure TEST-ONLY-NOT-A-REAL-PASSWORD'}
 $global:ADMutationCalls+='Reset'
}
function Set-ADUser {
 [CmdletBinding()]param($Identity,$ChangePasswordAtLogon,$EmployeeID)
 if($PSBoundParameters.ContainsKey('EmployeeID')){
  if($global:ADMutationMode -eq 'employee-failure'){throw 'Synthetic attribute failure'}
  $global:ADMutationCalls+='EmployeeID'
 }else{
  if($global:ADMutationMode -eq 'logon-failure'){throw 'Synthetic logon flag failure'}
  $global:ADMutationCalls+='Logon'
 }
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('ad-mutation-test-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $fixture|Out-Null
$create=Join-Path $scriptDirectory 'AD_Import_Users.ps1';$reset=Join-Path $scriptDirectory 'AD_Import_Set_Password.ps1'
foreach($p in @($create,$reset)){$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e)|Out-Null;Assert (-not $e) 'Parser failed'}
$csv=Join-Path $fixture 'users.csv'
[pscustomobject]@{username='fixture';password='TEST-ONLY-NOT-A-REAL-PASSWORD';firstname='Example';lastname='User';description='fixture';ou='OU=Lab,DC=example,DC=invalid';EmployeeID='TEST1'}|Export-Csv -LiteralPath $csv -NoTypeInformation
$r=@(& $create -InputPath $csv -UserPrincipalNameSuffix example.invalid -WhatIf)
Assert ($r[0].Result -eq 'NotChanged' -and $global:ADMutationCalls.Count -eq 0) 'Create WhatIf failed'
$r=@(& $create -InputPath $csv -UserPrincipalNameSuffix example.invalid -Confirm:$false)
Assert ($r[0].Result -eq 'Created' -and $global:ADMutationCalls.Count -eq 1) 'Create failed'
$global:ADMutationCalls=@();$global:ADMutationMode='lookup-failure'
$r=@(& $create -InputPath $csv -UserPrincipalNameSuffix example.invalid -Confirm:$false)
Assert ($r[0].Result -eq 'Failed' -and $global:ADMutationCalls.Count -eq 0) 'Lookup failure must not create'
$global:ADMutationMode='exists'
$r=@(& $create -InputPath $csv -UserPrincipalNameSuffix example.invalid -Confirm:$false)
Assert ($r[0].Result -eq 'AlreadyExists' -and $global:ADMutationCalls.Count -eq 0) 'Existing account failed'
$r=@(& $reset -InputPath $csv -WhatIf)
Assert ($r[0].Result -eq 'NotChanged' -and $global:ADMutationCalls.Count -eq 0) 'Reset WhatIf failed'
$r=@(& $reset -InputPath $csv -Confirm:$false)
Assert ($r[0].Result -eq 'Updated' -and $r[0].CompletedSteps.Count -eq 3) 'Reset success failed'
$global:ADMutationMode='reset-failure'
$r=@(& $reset -InputPath $csv -Confirm:$false)
Assert ($r[0].Result -eq 'Failed' -and $r[0].CompletedSteps.Count -eq 0) 'Reset failure failed'
Assert ($r[0].Error -notmatch 'TEST-ONLY-NOT-A-REAL-PASSWORD') 'Password leaked in error'
$global:ADMutationMode='logon-failure'
$r=@(& $reset -InputPath $csv -Confirm:$false)
Assert ($r[0].Result -eq 'Partial' -and $r[0].CompletedSteps.Count -eq 1 -and $r[0].CompletedSteps[0] -eq 'PasswordReset') 'Partial reset failed'
$global:ADMutationMode='employee-failure'
$r=@(& $reset -InputPath $csv -Confirm:$false)
Assert ($r[0].Result -eq 'Partial' -and $r[0].CompletedSteps.Count -eq 2) 'Partial attribute failed'
$blank=Join-Path $fixture 'blank.csv'
[pscustomobject]@{username='';password='';firstname='';lastname='';description='';ou=''}|Export-Csv -LiteralPath $blank -NoTypeInformation
Assert ((& $create -InputPath $blank -UserPrincipalNameSuffix example.invalid).Result -eq 'Skipped') 'Blank row failed'
Assert ((& $reset -InputPath $blank).Result -eq 'Skipped') 'Blank reset row failed'
$bad=Join-Path $fixture 'missing-columns.csv';'username','fixture'|Set-Content -LiteralPath $bad
Throws {& $create -InputPath $bad -UserPrincipalNameSuffix example.invalid}
Throws {& $reset -InputPath $bad}
'PASS: mutation parser/mocks; no real AD operations'
$PSVersionTable.PSVersion.ToString()
