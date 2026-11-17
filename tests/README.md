# Reproducing checks

Run each suite in a fresh PowerShell process from the repository root. Do not dot-source mocks into a normal administrative session.

```powershell
powershell.exe -NoProfile -File .\tests\Test-ComputerAvailability.Tests.ps1
powershell.exe -NoProfile -File .\tests\Get-FolderSizeReport.Tests.ps1
powershell.exe -NoProfile -File .\tests\Get-RemoteRegistryValue.Tests.ps1
powershell.exe -NoProfile -File .\AD\AD-Reports.Mock.Tests.ps1
powershell.exe -NoProfile -File .\AD\AD-Mutations.Mock.Tests.ps1
powershell.exe -NoProfile -File .\tests\CertPadding.Tests.ps1
powershell.exe -NoProfile -File .\tests\Uninstall.Tests.ps1
powershell.exe -NoProfile -File .\tests\Service.Tests.ps1
```

For network launcher/session tests, first build the harmless argument-echo fixture with Windows PowerShell 5.1. It does not open sockets. Do not commit the compiled executable.

```powershell
New-Item -ItemType Directory -Path .\tests\fixtures -Force
powershell.exe -NoProfile -File .\tests\BuildStub.ps1 -Output "$PWD\tests\fixtures\iperf stub.exe"
powershell.exe -NoProfile -File .\tests\Network.Tests.ps1
```

The test runs above also passed using `pwsh -NoProfile -File` with PowerShell 7.6.9. BuildStub is a Windows PowerShell 5.1 build step. Remote-service tests use mocks on PS7; the actual service script needs Windows PowerShell 5.1.

Availability uses loopback. Folder-size tests use synthetic files and a junction. Other suites replace external administrative commands with mocks, except the harmless iPerf argument-echo executable. No real domain, registry modification, uninstall, or remote service operation is tested. Unique temporary fixture directories are retained for inspection.

## Directory purge preview only

Run: powershell.exe -NoProfile -File .\tests\DirectoryPurge.Preview.Tests.ps1 (also tested with pwsh). Uses real Robocopy /L and synthetic retained folders. Never runs a live purge. See the directory-purge documentation for untested containment and deletion behavior.

## Windows Update reset mocks

Run powershell.exe -NoProfile -File .\tests\Reset.Tests.ps1, or use pwsh. Run in a fresh process: all service, cache-path, move and reboot operations are mocked. Never invoke the production reset as a test on your working machine.
