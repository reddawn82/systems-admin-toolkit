# AD commands are replaced with in-memory fixtures. No domain is contacted.
$ErrorActionPreference = 'Stop'
$scriptDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'AD'
function Assert($condition, $message) { if (-not $condition) { throw $message } }
function Throws([scriptblock]$code) { $threw=$false; try { & $code | Out-Null } catch { $threw=$true }; Assert $threw 'Expected terminating error' }
function Import-Module { [CmdletBinding()]param([string]$Name); if($Name -ne 'ActiveDirectory'){throw 'Unexpected module'} }
$global:ADReportTestMode='normal'
$global:ADReportTestQueries=@()
function Get-ADUser {
 [CmdletBinding()]param($Filter,$SearchBase,$Properties)
 if($global:ADReportTestMode -eq 'failure'){throw 'Synthetic AD lookup failure'}
 $global:ADReportTestQueries+=@([pscustomobject]@{Filter=$Filter;SearchBase=$SearchBase;Properties=$Properties})
 if($global:ADReportTestMode -eq 'empty'){return}
 [pscustomobject]@{Name='Example User';SamAccountName='example';UserPrincipalName='example@example.invalid';Enabled=$true;EmployeeID='TEST-1'}
}
function Get-ADComputer {
 [CmdletBinding()]param($Filter,$LDAPFilter,$Properties)
 if($global:ADReportTestMode -eq 'failure'){throw 'Synthetic AD lookup failure'}
 $global:ADReportTestQueries+=@([pscustomobject]@{Filter=$Filter;LDAPFilter=$LDAPFilter;Properties=$Properties})
 if($global:ADReportTestMode -eq 'empty'){return}
 if($LDAPFilter){
  [pscustomobject]@{Name='NEVER';DistinguishedName='CN=NEVER,DC=example,DC=invalid';LastLogonDate=$null;Description='fixture';Enabled=$false}
  [pscustomobject]@{Name='OLD';DistinguishedName='CN=OLD,DC=example,DC=invalid';LastLogonDate=[datetime]'2020-01-01';Description='fixture';Enabled=$true}
 }else{
  [pscustomobject]@{Name='OLD';DistinguishedName='CN=OLD,DC=example,DC=invalid';LastLogonDate=[datetime]'2020-01-01';Description='fixture';Enabled=$true}
 }
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('ad-report-test-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $fixture|Out-Null
foreach($name in @('AD_Export_Users.ps1','Get-ADInactiveComputers.ps1')) {
 $tokens=$null;$errors=$null
 [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $scriptDirectory $name),[ref]$tokens,[ref]$errors)|Out-Null
 Assert (-not $errors) "Parse failed: $name"
}
$export=Join-Path $scriptDirectory 'AD_Export_Users.ps1'
$inactive=Join-Path $scriptDirectory 'Get-ADInactiveComputers.ps1'
$out=Join-Path $fixture 'nested\users.csv'
$r=@(& $export -SearchBase 'OU=Lab,DC=example,DC=invalid' -AdditionalProperty EmployeeID,EmployeeID -OutputPath $out)
Assert ($r.Count -eq 1 -and $r[0].EmployeeID -eq 'TEST-1' -and $r[0].Enabled) 'Export projection failed'
Assert ($global:ADReportTestQueries[0].SearchBase -eq 'OU=Lab,DC=example,DC=invalid') 'SearchBase not forwarded'
Assert (@($global:ADReportTestQueries[0].Properties | Where-Object {$_ -eq 'EmployeeID'}).Count -eq 1) 'Attribute dedupe failed'
Assert (@(Import-Csv -LiteralPath $out).Count -eq 1) 'User CSV failed'
$global:ADReportTestQueries=@()
$out=Join-Path $fixture 'inactive.csv'
$r=@(& $inactive -MonthsInactive 6 -IncludeNeverLoggedOn -OutputPath $out)
Assert ($r.Count -eq 2) 'Computer dedupe failed'
Assert (@($r | Where-Object NeverLoggedOn).Count -eq 1) 'NeverLoggedOn projection failed'
Assert ($global:ADReportTestQueries.Count -eq 2 -and $global:ADReportTestQueries[1].LDAPFilter -eq '(!(lastLogonTimestamp=*))') 'Never-logon query failed'
Assert (@(Import-Csv -LiteralPath $out).Count -eq 2) 'Computer CSV failed'
$global:ADReportTestQueries=@()
$r=@(& $inactive -OutputPath (Join-Path $fixture 'single.csv'))
Assert ($r.Count -eq 1 -and $global:ADReportTestQueries.Count -eq 1) 'Default query count failed'
Throws {& $inactive -MonthsInactive 0 -OutputPath $out}
Throws {& $inactive -MonthsInactive 121 -OutputPath $out}
$blocked=Join-Path $fixture 'blocked'; 'fixture'|Set-Content -LiteralPath $blocked
Throws {& $export -SearchBase 'DC=example,DC=invalid' -OutputPath (Join-Path $blocked 'x.csv')}
Throws {& $inactive -OutputPath (Join-Path $blocked 'x.csv')}
$global:ADReportTestMode='failure'
Throws {& $export -SearchBase 'DC=example,DC=invalid' -OutputPath $out}
Throws {& $inactive -OutputPath $out}
$global:ADReportTestMode='empty'
Assert (@(& $export -SearchBase 'DC=example,DC=invalid' -OutputPath (Join-Path $fixture 'empty-users.csv')).Count -eq 0) 'Empty user result failed'
Assert (@(& $inactive -OutputPath (Join-Path $fixture 'empty-computers.csv')).Count -eq 0) 'Empty computer result failed'
'PASS: AD reporting parser and mock fixtures; no real Active Directory commands ran'
$PSVersionTable.PSVersion.ToString()
