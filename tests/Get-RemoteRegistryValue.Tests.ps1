$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot '..\Registry\Get-RemoteRegistryValue.ps1'
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)|Out-Null
if($errors){throw 'Parse failed'}
function Assert($ok,$msg){if(-not $ok){throw $msg}}
function Invoke-Command {
 param($ComputerName,$ErrorAction,$ArgumentList,$ScriptBlock,$Credential)
 if($ComputerName -ne 'fixture-host'){throw 'Unexpected remote target'}
 $global:seenPath=$ArgumentList[0]
 if($global:scenario -eq 'transport'){throw 'Synthetic transport error'}
 function Test-Path {param($LiteralPath,$ErrorAction) if($global:scenario -eq 'denied'){throw 'Synthetic access denied'}; $global:scenario -ne 'missing'}
 function Get-ItemProperty {param($LiteralPath,$ErrorAction) if($global:scenario -eq 'novalue'){return [pscustomobject]@{Other='x'}};[pscustomobject]@{Setting=0}}
 & $ScriptBlock @ArgumentList
}
foreach($case in @(@('success','Success'),@('missing','KeyNotFound'),@('novalue','ValueNotFound'),@('denied','Error'),@('transport','Error'))){
 $global:scenario=$case[0];$r=@(& $source -ComputerName ' fixture-host ','fixture-host' -RegistryPath 'HKLM:\SOFTWARE\Example' -ValueName Setting)
 Assert ($r.Count -eq 1 -and $r[0].Status -eq $case[1]) ('Case failed: '+$case[0])
 Assert ($global:seenPath -eq 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Example') 'Path conversion failed'
 if($case[0] -eq 'success'){Assert ($r[0].Value -eq 0 -and $r[0].ValueExists) 'Zero value lost'}
 if($case[0] -eq 'denied'){Assert ($null -eq $r[0].KeyExists) 'Access denial treated as missing key'}
}
$global:scenario='success'
$r=& $source -ComputerName fixture-host -RegistryPath 'Registry::HKEY_CURRENT_USER\Software\Example'
Assert ($r.Status -eq 'KeyFound') 'Key existence failed'
foreach($path in @('C:\private.txt','Registry::C:\private.txt','nonsense')){$threw=$false;try{& $source -ComputerName fixture-host -RegistryPath $path|Out-Null}catch{$threw=$true};Assert $threw 'Invalid provider accepted'}
'PASS: parser, target dedupe, hive conversion, key found/missing, value missing/zero, access-denial and transport errors, invalid provider rejection. Remoting mocked; PsExec not run.'
$PSVersionTable.PSVersion.ToString()
