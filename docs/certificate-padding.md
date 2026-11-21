# Certificate-padding checks

`Test-CertPadding.ps1` reports compliance for the WinTrust EnableCertPaddingCheck setting: exit 0 for the accepted value, exit 1 otherwise. `Enable-CertPadding.ps1` sets it to 1, preserving existing DWORD/string types and normalizing other types to DWORD.

On 64-bit Windows, use a 64-bit PowerShell host. Both registry views are covered. On 32-bit Windows only the native path is used.

Preview remediation first:

```powershell
.\Workstation\Enable-CertPadding.ps1 -WhatIf
```

Applying it changes Windows signature-validation configuration and requires appropriate administrative rights. It prompts by default. For an approved unattended deployment, explicitly supply `-Confirm:$false`; do not deploy without assessing application compatibility. Restart Windows after an approved change. The script does not restart it automatically. Changes to two paths are not transactional: a later failure can leave the earlier path updated.

## Validation

Parser and mocked tests passed in 64-bit Windows PowerShell 5.1.26100.9818 and PowerShell 7.6.9. Tests cover DWORD/string compliance, noncompliance, missing path, WhatIf with zero mock writes, accepted-type preservation, missing/unsupported values, and access failure. All registry commands were replaced by local test functions. No actual registry reads or writes, deployment, restart, or signature-validation integration tests occurred. The 32-bit Windows branch has not been executed.

Run the tests in a fresh PowerShell process:

```powershell
powershell.exe -NoProfile -File .\tests\CertPadding.Tests.ps1
```

The mocks model control flow, not real registry permissions, architecture redirection, or Intune behavior. A lab deployment is still advisable before operational use.
