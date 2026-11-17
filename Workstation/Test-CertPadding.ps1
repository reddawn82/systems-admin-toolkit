<#
.SYNOPSIS
Detects whether EnableCertPaddingCheck is enabled in both WinTrust registry locations.

.DESCRIPTION
Checks the native and WOW6432Node WinTrust Config keys. Microsoft has published
both REG_DWORD 1 and REG_SZ "1" for CVE-2013-3900. When a validation tool cannot
inspect the raw 1-4 byte data requirement directly, Microsoft recommends accepting
those two published forms.

This detection therefore requires either REG_DWORD 1 or REG_SZ "1" at both paths.
Returns exit code 0 when both locations are compliant and 1 otherwise.

.NOTES
A restart is required for the Windows signature-validation behavior change to take effect.
#>

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell on 64-bit Windows.' }

$regPaths = @(
    'HKLM:\Software\Microsoft\Cryptography\Wintrust\Config',
    'HKLM:\Software\Wow6432Node\Microsoft\Cryptography\Wintrust\Config'
)
if (-not [Environment]::Is64BitOperatingSystem) { $regPaths = @($regPaths[0]) }
$regName = 'EnableCertPaddingCheck'

function Test-EnableCertPaddingValue {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        $kind = $key.GetValueKind($regName)
        $value = $key.GetValue($regName)

        if ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) {
            return ([int32]$value -eq 1)
        }

        if ($kind -eq [Microsoft.Win32.RegistryValueKind]::String) {
            return ([string]$value -eq '1')
        }

        return $false
    }
    catch {
        return $false
    }
}

foreach ($regPath in $regPaths) {
    if (-not (Test-EnableCertPaddingValue -Path $regPath)) {
        exit 1
    }
}

exit 0
