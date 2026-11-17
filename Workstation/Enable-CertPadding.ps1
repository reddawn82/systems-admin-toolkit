<#
.SYNOPSIS
Enables the WinVerifyTrust certificate-padding validation setting for CVE-2013-3900.

.DESCRIPTION
Ensures EnableCertPaddingCheck is configured in both the native and WOW6432Node
WinTrust Config registry locations. Existing REG_DWORD or REG_SZ values are set to
1 while preserving those accepted types. Missing values and unsupported registry
types are normalized to REG_DWORD 1.

Intended for Intune remediation/deployment contexts. Returns exit code 0 on
success and 1 on failure.

.NOTES
A restart is required for the Windows signature-validation behavior change to take effect.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param()

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell on 64-bit Windows.' }

$regPaths = @(
    'HKLM:\Software\Microsoft\Cryptography\Wintrust\Config',
    'HKLM:\Software\Wow6432Node\Microsoft\Cryptography\Wintrust\Config'
)
if (-not [Environment]::Is64BitOperatingSystem) { $regPaths = @($regPaths[0]) }
$regName = 'EnableCertPaddingCheck'

try {
    foreach ($regPath in $regPaths) {
        if (-not $PSCmdlet.ShouldProcess($regPath, 'Set EnableCertPaddingCheck to 1')) { continue }
        if (-not (Test-Path -LiteralPath $regPath)) {
            New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
        }

        $key = Get-Item -LiteralPath $regPath -ErrorAction Stop
        $valueExists = $key.GetValueNames() -contains $regName
        $kind = if ($valueExists) { $key.GetValueKind($regName) } else { $null }

        if (-not $valueExists) {
            New-ItemProperty `
                -LiteralPath $regPath `
                -Name $regName `
                -Value 1 `
                -PropertyType DWord `
                -Force `
                -ErrorAction Stop | Out-Null
            continue
        }

        if ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord -or
            $kind -eq [Microsoft.Win32.RegistryValueKind]::String) {
            Set-ItemProperty -LiteralPath $regPath -Name $regName -Value 1 -Force -ErrorAction Stop
            continue
        }

        # Normalize unsupported types such as QWORD or Binary to the published DWORD form.
        Remove-ItemProperty -LiteralPath $regPath -Name $regName -Force -ErrorAction Stop
        New-ItemProperty `
            -LiteralPath $regPath `
            -Name $regName `
            -Value 1 `
            -PropertyType DWord `
            -Force `
            -ErrorAction Stop | Out-Null
    }

    exit 0
}
catch {
    Write-Error "Failed to configure $regName. $($_.Exception.Message)"
    exit 1
}
