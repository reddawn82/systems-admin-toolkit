# Remote registry reporting

`Get-RemoteRegistryValue.ps1` reads a key or named value and returns one structured result per target. It defaults to PowerShell remoting; optional PsExec support requires a separately installed executable and permissions to run it. The script does not automatically accept the Sysinternals EULA.

```powershell
.\Registry\Get-RemoteRegistryValue.ps1 -ComputerName PC001 -RegistryPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ValueName ProductName
```

Only supported registry hives are accepted. Access/transport failures are reported as errors, not as missing keys. CSV output overwrites the selected file and creates missing parent folders. Keep exported values private; registry data can contain sensitive configuration. Query only systems you administer. PsExec can create a service on the target as part of execution, so it is not a side-effect-free transport even though the query itself is read-only.

## Verification

Local mocked tests passed on Windows PowerShell 5.1.26100.9818 and PowerShell 7.6.9: parser, target deduplication, hive normalization, found/missing keys, missing/zero values, access-denied and transport failures, invalid-provider rejection. Tests replace Invoke-Command and registry queries; no actual remote connection or registry modification occurred.

Real remoting, authentication, PsExec execution/output parsing, empty/default registry values, and remote architecture views remain untested. Use a lab before operational use. Run `tests/Get-RemoteRegistryValue.Tests.ps1` in a fresh PowerShell process; do not dot-source test mocks into your normal session.
