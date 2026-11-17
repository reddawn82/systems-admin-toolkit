$ErrorActionPreference='Stop'
$script=Join-Path $PSScriptRoot '..\Workstation\Set-RemoteServiceState.ps1'
$root=Join-Path ([IO.Path]::GetTempPath()) ('service-mock-'+[guid]::NewGuid());New-Item -ItemType Directory $root|Out-Null
$csv=Join-Path $root 'hosts.csv';'ComputerName','synthetic'|Set-Content $csv
function Assert($ok,$message){if(-not $ok){throw $message}}
$global:ServiceFixture=@{}
function Get-WmiObject {param($Class,$ComputerName,$Credential,$ErrorAction)
 $global:ServiceFixture.Reads++
 if($global:ServiceFixture.Throw){throw 'Synthetic WMI failure'}
 $obj=[pscustomobject]@{Name='SyntheticService';State=$global:ServiceFixture.State;StartMode=$global:ServiceFixture.Mode}
 $obj|Add-Member ScriptMethod ChangeStartMode {param($mode) $global:ServiceFixture.Changes++;$global:ServiceFixture.Mode=if($mode -eq 'Automatic'){'Auto'}else{$mode};[pscustomobject]@{ReturnValue=0}}
 $obj|Add-Member ScriptMethod StartService {$global:ServiceFixture.Changes++;$global:ServiceFixture.State='Running';[pscustomobject]@{ReturnValue=0}}
 $obj|Add-Member ScriptMethod StopService {$global:ServiceFixture.Changes++;$global:ServiceFixture.State='Stopped';[pscustomobject]@{ReturnValue=0}}
 return $obj
}
function Reset-Fixture {$global:ServiceFixture=@{State='Stopped';Mode='Disabled';Reads=0;Changes=0;Throw=$false}}
$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile($script,[ref]$t,[ref]$e)|Out-Null;Assert (-not $e) 'Parse failed'
Reset-Fixture
& $script -ServiceName SyntheticService -Action Enable -ComputerListPath $csv -OutputPath (Join-Path $root 'whatif.csv') -WhatIf
Assert ($global:ServiceFixture.Reads -eq 0 -and $global:ServiceFixture.Changes -eq 0 -and -not (Test-Path (Join-Path $root 'whatif.csv'))) 'WhatIf had side effects'
$r=& $script -ServiceName SyntheticService -Action Enable -ComputerListPath $csv -OutputPath (Join-Path $root 'enabled.csv') -Confirm:$false
Assert ($r.Result -eq 'Success' -and $r.FinalState -eq 'Running' -and $r.FinalStartMode -eq 'Auto') 'Enable failed'
$r=& $script -ServiceName SyntheticService -Action Disable -ComputerListPath $csv -OutputPath (Join-Path $root 'disabled.csv') -Confirm:$false
Assert ($r.Result -eq 'Success' -and $r.FinalState -eq 'Stopped' -and $r.FinalStartMode -eq 'Disabled') 'Disable failed'
$global:ServiceFixture.Throw=$true
$r=& $script -ServiceName SyntheticService -Action Enable -ComputerListPath $csv -OutputPath (Join-Path $root 'failed.csv') -Confirm:$false
Assert ($r.Result -eq 'Failed' -and $r.Error -eq 'Synthetic WMI failure') 'WMI failure lost'
'PASS: remote-service parser and mocked preview/state/error tests; no service or network operations'
$PSVersionTable.PSVersion.ToString()
