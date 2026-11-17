$ErrorActionPreference='Stop'
$script=Join-Path $PSScriptRoot '..\Workstation\Uninstall-Application.ps1'
$global:UninstallFixture=@{}
function Assert($ok,$message){if(-not $ok){throw $message}}
function Get-ItemProperty {param($Path,$ErrorAction) if($Path -notmatch 'WOW6432Node'){return $global:UninstallFixture.Apps}}
function Start-Process {param($FilePath,$ArgumentList,$ErrorAction,[switch]$Wait,[switch]$PassThru) $global:UninstallFixture.Calls++;$global:UninstallFixture.File=$FilePath;$global:UninstallFixture.Args=$ArgumentList;if($global:UninstallFixture.Throw){throw 'Synthetic launch error'};[pscustomobject]@{ExitCode=$global:UninstallFixture.ExitCode}}
function Reset-Fixture($command){$global:UninstallFixture=@{Apps=@([pscustomobject]@{DisplayName='Synthetic App';DisplayVersion='1';Publisher='Test';UninstallString=$command;QuietUninstallString=$null;PSChildName='fixture'});Calls=0;ExitCode=0;Throw=$false}}
$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile($script,[ref]$t,[ref]$e)|Out-Null;Assert (-not $e) 'Parse failed'
Reset-Fixture '"C:\Windows\System32\msiexec.exe" /I{11111111-1111-1111-1111-111111111111}'
$r=& $script -AppName 'Synthetic App' -Confirm:$false -PassThru
Assert ($r.Success -and $r.InstallerType -eq 'MSI' -and $global:UninstallFixture.Args -like '/x*' -and $global:UninstallFixture.Args -notlike '*msiexec*') 'Full-path MSI failed'
Reset-Fixture '"C:\Tools\Uninstall.exe" /log C:\logs\msiexec.log'
$r=& $script -AppName 'Synthetic App' -Confirm:$false -PassThru
Assert ($r.InstallerType -eq 'EXE' -and $global:UninstallFixture.File -eq 'C:\Tools\Uninstall.exe') 'EXE wrongly classified'
& $script -AppName 'Synthetic App' -WhatIf
Assert ($global:UninstallFixture.Calls -eq 1) 'WhatIf launched a process'
Reset-Fixture 'msiexec /x {11111111-1111-1111-1111-111111111111}'
$r=& $script -AppName 'Synthetic App' -ListOnly
Assert ($r.InstallerType -eq 'MSI' -and $global:UninstallFixture.Calls -eq 0) 'ListOnly or bare MSI failed'
$global:UninstallFixture.ExitCode=3010
$r=& $script -AppName 'Synthetic App' -Confirm:$false -PassThru
Assert ($r.Success -and $r.RestartRequired) 'MSI reboot exit failed'
Reset-Fixture '"C:\Tools\Uninstall.exe" /S'
$global:UninstallFixture.ExitCode=17
$r=& $script -AppName 'Synthetic App' -Confirm:$false -PassThru 3>$null
Assert (-not $r.Success) 'Failure code reported success'
$global:UninstallFixture.Throw=$true
$r=& $script -AppName 'Synthetic App' -Confirm:$false -PassThru 3>$null
Assert (-not $r.Success -and $r.Error -eq 'Synthetic launch error') 'Launch failure not recorded'
$global:UninstallFixture.Apps=@($global:UninstallFixture.Apps[0],$global:UninstallFixture.Apps[0]);$threw=$false
try{& $script -AppName 'Synthetic App' -Confirm:$false}catch{$threw=$true};Assert $threw 'Ambiguous match accepted'
'PASS: uninstall parser and mocked routing/preview/error tests; no registry or process access'
$PSVersionTable.PSVersion.ToString()
