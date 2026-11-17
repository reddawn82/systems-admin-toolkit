$ErrorActionPreference = 'Continue'
$base = Join-Path $PSScriptRoot '..\Workstation'
function Assert($value,$message) { if (-not $value) { throw $message } }
$global:CertFixture = @{}
function Test-Path { param($LiteralPath) return $global:CertFixture.Exists }
function Get-Item { param($LiteralPath,$ErrorAction)
    if ($global:CertFixture.FailRead) { throw 'Synthetic access denied' }
    $key = [pscustomobject]@{}
    $key | Add-Member ScriptMethod GetValueKind { param($n) if(-not $global:CertFixture.HasValue){throw 'Missing'}; return $global:CertFixture.Kind }
    $key | Add-Member ScriptMethod GetValue { param($n) return $global:CertFixture.Value }
    $key | Add-Member ScriptMethod GetValueNames { if($global:CertFixture.HasValue){return @('EnableCertPaddingCheck')};return @() }
    return $key
}
function New-Item { param($Path,$ErrorAction,[switch]$Force) $global:CertFixture.Creates++; $global:CertFixture.Exists=$true }
function New-ItemProperty { param($LiteralPath,$Name,$Value,$PropertyType,$ErrorAction,[switch]$Force) $global:CertFixture.New++;$global:CertFixture.HasValue=$true;$global:CertFixture.Kind=[Microsoft.Win32.RegistryValueKind]::DWord;$global:CertFixture.Value=$Value }
function Set-ItemProperty { param($LiteralPath,$Name,$Value,$ErrorAction,[switch]$Force) $global:CertFixture.Sets++;$global:CertFixture.Value=$Value }
function Remove-ItemProperty { param($LiteralPath,$Name,$ErrorAction,[switch]$Force) $global:CertFixture.Removes++;$global:CertFixture.HasValue=$false }
function Reset-Fixture { $global:CertFixture=@{Exists=$true;HasValue=$true;Kind=[Microsoft.Win32.RegistryValueKind]::DWord;Value=1;Sets=0;New=0;Removes=0;Creates=0;FailRead=$false} }
foreach($file in @('Test-CertPadding.ps1','Enable-CertPadding.ps1')){
 $t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $base $file),[ref]$t,[ref]$e)|Out-Null;Assert (-not $e) "$file parse failed"
}
Reset-Fixture
& "$base\Test-CertPadding.ps1"; Assert ($LASTEXITCODE -eq 0) 'DWord 1 detection failed'
$global:CertFixture.Kind=[Microsoft.Win32.RegistryValueKind]::String
$global:CertFixture.Value='1'
& "$base\Test-CertPadding.ps1"; Assert ($LASTEXITCODE -eq 0) 'String 1 detection failed'
$global:CertFixture.Value='0'
& "$base\Test-CertPadding.ps1"; Assert ($LASTEXITCODE -eq 1) 'Noncompliant detection failed'
$global:CertFixture.Exists=$false
& "$base\Test-CertPadding.ps1"; Assert ($LASTEXITCODE -eq 1) 'Missing path detection failed'
Reset-Fixture
& "$base\Enable-CertPadding.ps1" -WhatIf
Assert (($global:CertFixture.Sets+$global:CertFixture.New+$global:CertFixture.Removes+$global:CertFixture.Creates) -eq 0) 'WhatIf changed mock state'
& "$base\Enable-CertPadding.ps1" -Confirm:$false
Assert ($LASTEXITCODE -eq 0 -and $global:CertFixture.Sets -eq 2) 'Existing DWord repair failed'
Reset-Fixture
$global:CertFixture.Kind=[Microsoft.Win32.RegistryValueKind]::String
& "$base\Enable-CertPadding.ps1" -Confirm:$false
Assert ($global:CertFixture.Kind -eq [Microsoft.Win32.RegistryValueKind]::String -and $global:CertFixture.Sets -eq 2) 'String preservation failed'
Reset-Fixture
$global:CertFixture.HasValue=$false
& "$base\Enable-CertPadding.ps1" -Confirm:$false
Assert ($LASTEXITCODE -eq 0 -and $global:CertFixture.New -eq 1 -and $global:CertFixture.Sets -eq 1) 'Missing-value repair failed'
Reset-Fixture
$global:CertFixture.Kind=[Microsoft.Win32.RegistryValueKind]::QWord
& "$base\Enable-CertPadding.ps1" -Confirm:$false
Assert ($LASTEXITCODE -eq 0 -and $global:CertFixture.Removes -eq 1 -and $global:CertFixture.New -eq 1) 'Unsupported-type repair failed'
Reset-Fixture
$global:CertFixture.FailRead=$true
& "$base\Enable-CertPadding.ps1" -Confirm:$false 2>$null
Assert ($LASTEXITCODE -eq 1 -and $global:CertFixture.New -eq 0) 'Access failure treated as success'
'PASS: certificate-padding parser and mocked behavior tests; no registry accessed'
$PSVersionTable.PSVersion.ToString()
