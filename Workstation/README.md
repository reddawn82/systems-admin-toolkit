# Workstation administration

## Certificate-padding checks

See [CERT-PADDING.md](CERT-PADDING.md) for the detection and remediation scripts, architecture requirements, preview usage, and mocked validation limits.

## Set-RemoteServiceState.ps1

Enables or disables named services on authorized Windows computers listed in a CSV with a `ComputerName` column. Enable means Automatic + Running; Disable means Disabled + Stopped. It reports per-target results to CSV and the pipeline. Supply `-Credential` only when needed; otherwise it uses your current identity.

```powershell
.\Workstation\Set-RemoteServiceState.ps1 -ServiceName ExampleService -Action Enable -ComputerListPath .\computers.csv -WhatIf
```

Runtime requires **Windows PowerShell 5.1 and WMI/DCOM access**. PowerShell 7 cannot perform the real operations. Preview avoids WMI calls and report writes. Actual changes prompt by default. Explicitly supplying `-Confirm:$false` suppresses those prompts. The output file defaults to `%TEMP%\ServiceOutput.csv` and is overwritten; choose `-OutputPath` to retain earlier reports.

Mocked tests passed on Windows PowerShell 5.1.26100.9818 and PowerShell 7.6.9 for parsing, preview with no side effects, Enable/Disable final state, and WMI exceptions. PS7 testing only exercised mocks; it does not establish PS7 runtime support. No real remote services, credentials, networks, timeout behavior, or WMI nonzero method codes were tested. Operations are not transactional and may partially change a target before reporting failure. Use a lab first.

Run `tests/Service.Tests.ps1` in a fresh PowerShell process. It replaces WMI with in-memory objects and writes synthetic CSVs to a unique temporary folder retained for inspection.

## Uninstall-Application.ps1

Finds machine-wide installed applications by exact display name. Use `-Contains -ListOnly` for discovery, then an exact name and `-WhatIf` before removal. Multiple matches are rejected. Per-user application entries are not searched.

```powershell
.\Workstation\Uninstall-Application.ps1 -AppName 'Example App' -ListOnly
.\Workstation\Uninstall-Application.ps1 -AppName 'Example App' -WhatIf
```

Actual uninstall operations prompt by default and can remove software/data. Vendor EXE arguments differ: review the registered command and the vendor's requirements. MSI results distinguish successful and restart-required exit codes; EXE success defaults to exit 0 and can be overridden. Registry access failures can appear as a missing application, so verify permissions before treating no match as authoritative.

Mocked tests passed in Windows PowerShell 5.1.26100.9818 and PowerShell 7.6.9: parsing, full-path and bare MSI commands, EXE arguments containing the word msiexec, ListOnly/WhatIf without a process launch, MSI reboot exit, failed exit, launch exception, and ambiguous matches. Registry reads and Start-Process were mocked. No installed app was inspected or removed; real vendor/MSI behavior remains untested. The parser accepts ordinary quoted/unquoted EXE commands, not arbitrary shell syntax.

Run `tests/Uninstall.Tests.ps1` in a fresh PowerShell process.
