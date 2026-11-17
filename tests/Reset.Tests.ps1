Add-Type -AssemblyName System.ServiceProcess
$ErrorActionPreference='Stop'
$script=Join-Path $PSScriptRoot '..\Workstation\Reset-WindowsUpdateComponents.ps1'
function Assert($ok,$message){if(-not $ok){throw $message}}
function New-Object {param($TypeName,$ArgumentList) if($TypeName -ne 'Security.Principal.WindowsPrincipal'){throw 'Unexpected constructor'}; $p=[pscustomobject]@{};$p|Add-Member ScriptMethod IsInRole {param($role) return $true};$p}
function Get-Service {param($Name,$ErrorAction)
 $global:R.Calls.Add("read:$Name")
 if($global:R.Missing -eq $Name){throw 'Synthetic missing service'}
 $s=[pscustomobject]@{Name=$Name;Status=$global:R.States[$Name]}
 $s|Add-Member ScriptMethod WaitForStatus {param($status,$timeout) if($global:R.WaitFailure -eq $this.Name){throw 'Synthetic timeout'};if($global:R.States[$this.Name] -ne $status.ToString()){throw 'State mismatch'}}
 $s
}
function Stop-Service {param($Name,$ErrorAction) $global:R.Calls.Add("stop:$Name");if($global:R.StopFailure -eq $Name){throw 'Synthetic stop failure'};$global:R.States[$Name]='Stopped'}
function Start-Service {param($Name,$ErrorAction) $global:R.Calls.Add("start:$Name");if($global:R.StartFailure -eq $Name){throw 'Synthetic start failure'};$global:R.States[$Name]='Running'}
function Test-Path {param($LiteralPath,$PathType) if($global:R.Collision -and $LiteralPath -like '*.bak.*'){return $true};return $global:R.Paths.ContainsKey($LiteralPath)}
function Get-Item {param($LiteralPath,$ErrorAction,[switch]$Force) [pscustomobject]@{PSIsContainer=$true;Attributes=if($global:R.Reparse){[IO.FileAttributes]::ReparsePoint}else{[IO.FileAttributes]::Directory}}}
function Move-Item {param($LiteralPath,$Destination,$ErrorAction)
 $global:R.Calls.Add("move:$LiteralPath")
 if($global:R.MoveFailure -and $LiteralPath -like '*catroot2'){throw 'Synthetic second move failure'}
 if($global:R.RollbackFailure -and $LiteralPath -like '*.bak.*'){throw 'Synthetic rollback failure'}
 if(-not $global:R.Paths.ContainsKey($LiteralPath)){throw 'Mock source missing'}
 if($global:R.Paths.ContainsKey($Destination)){throw 'Mock destination exists'}
 $global:R.Paths.Remove($LiteralPath);$global:R.Paths[$Destination]=$true
}
function Restart-Computer {param([switch]$Force,$ErrorAction) $global:R.Calls.Add('restart')}
function Reset-Fixture {
 $global:R=@{States=@{bits='Running';wuauserv='Stopped';cryptsvc='Running'};Paths=@{};Calls=[Collections.Generic.List[string]]::new();Missing='';StopFailure='';StartFailure='';MoveFailure=$false;RollbackFailure=$false;Reparse=$false;Collision=$false;WaitFailure=''}
 $global:R.Paths[(Join-Path $env:SystemRoot 'SoftwareDistribution')]=$true
 $global:R.Paths[(Join-Path $env:SystemRoot 'System32\catroot2')]=$true
 $global:Results=[Collections.Generic.List[object]]::new();$global:Failed=$false
}
function Run([switch]$Restart) {try{& $script -Confirm:$false -RestartComputer:$Restart | ForEach-Object {$global:Results.Add($_)}}catch{$global:Failed=$true;$global:FailureMessage=$_.Exception.Message}}
$t=$null;$e=$null;[Management.Automation.Language.Parser]::ParseFile($script,[ref]$t,[ref]$e)|Out-Null;Assert (-not $e) 'Parser failed'
Reset-Fixture
& $script -WhatIf
Assert ($global:R.Calls.Count -eq 0) 'WhatIf called system mocks'
Reset-Fixture;Run
Assert (-not $global:Failed -and $global:Results[0].Success) ("Success case failed: " + $global:FailureMessage)
Assert ($global:R.States.wuauserv -eq 'Stopped' -and $global:R.Calls -notcontains 'start:wuauserv') 'Initially stopped service started'
Assert ($global:R.States.bits -eq 'Running' -and $global:R.States.cryptsvc -eq 'Running') 'Running states not restored'
Assert ($global:R.Paths.Keys.Count -eq 2 -and @($global:R.Paths.Keys|Where-Object{$_ -like '*.bak.*'}).Count -eq 2) 'Backups missing'
Assert ($global:R.Calls -notcontains 'restart') 'Unexpected restart'
Reset-Fixture;$global:R.Missing='cryptsvc';Run
Assert ($global:Failed -and @($global:R.Calls|Where-Object{$_ -match '^(start|stop|move|restart):?'}).Count -eq 0) 'Preflight had writes'
Reset-Fixture;$global:R.States.bits='StartPending';Run
Assert ($global:Failed -and $global:R.Calls -notcontains 'stop:bits') 'Transitional state accepted'
Reset-Fixture;$global:R.Reparse=$true;Run
Assert ($global:Failed -and $global:R.Calls -notcontains 'stop:bits') 'Reparse directory accepted'
Reset-Fixture;$global:R.Collision=$true;Run
Assert ($global:Failed -and $global:R.Calls -notcontains 'stop:bits') 'Backup collision accepted'
Reset-Fixture;$global:R.StopFailure='cryptsvc';Run
Assert ($global:Failed -and $global:R.States.bits -eq 'Running' -and @($global:R.Calls|Where-Object{$_ -like 'move:*'}).Count -eq 0) 'Stop failure recovery failed'
Reset-Fixture;$global:R.WaitFailure='bits';Run
Assert ($global:Failed -and $global:R.States.bits -eq 'Running' -and $global:R.Calls -notcontains 'restart') 'Wait failure recovery failed'
Reset-Fixture;$global:R.MoveFailure=$true;Run
Assert ($global:Failed -and $global:Results[0].CacheMoves[0].RolledBack -and @($global:R.Paths.Keys|Where-Object{$_ -like '*.bak.*'}).Count -eq 0) 'Move rollback failed'
Reset-Fixture;$global:R.MoveFailure=$true;$global:R.RollbackFailure=$true;Run -Restart
Assert ($global:Failed -and -not $global:Results[0].CacheMoves[0].RolledBack -and $global:Results[0].Errors.Count -ge 2 -and $global:R.Calls -notcontains 'restart') 'Rollback failure hidden'
Reset-Fixture;$global:R.StartFailure='bits';Run -Restart
Assert ($global:Failed -and $global:R.Calls -notcontains 'restart' -and @($global:R.Paths.Keys|Where-Object{$_ -like '*.bak.*'}).Count -eq 2) 'Restart failure rolled caches back or rebooted'
Reset-Fixture;Run -Restart
Assert (-not $global:Failed -and $global:R.Calls -contains 'restart') 'Successful explicit restart not invoked'
'PASS: 12 mocked recovery/preview scenarios; no service/cache/restart operations performed'
$PSVersionTable.PSVersion.ToString()
