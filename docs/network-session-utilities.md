# Network and session utilities

## Invoke-Iperf3.ps1

Launches a locally installed iPerf3 executable. Client mode requires `-Server`; server mode listens until stopped. Use only on networks and endpoints you are authorized to test. This wrapper does not install iPerf3, open firewall ports, or start a remote server.

```powershell
.\Network\Invoke-Iperf3.ps1 -Mode Client -Server 192.0.2.10 -IperfPath C:\Tools\iperf3.exe -IperfArguments '-t','10'
```

Executable lookup uses application files on PATH, then `iperf3.exe` beside the script. An explicit `-IperfPath` must resolve to a file with an `.exe` extension; that is not a signature or trust check. Supply only a trusted iPerf3 build. Extra arguments pass directly to it and can override its behavior. Nonzero exit codes stop the wrapper.

Tested with a locally compiled stub, not a real iPerf3 server/client. Client/server argument assembly, a spaced executable path, a spaced argument, missing server/file, invalid mode, and nonzero exit were checked. No bandwidth, listener, firewall, or remote endpoint tests were performed.

## Get-RemoteLoggedOnUser.ps1

Reports interactive Windows sessions using QUser, with optional Sysinternals PSLoggedOn output. Remote access requires appropriate permissions and service/network configuration; domain membership is not itself required. Only query authorized hosts. Results may contain personal information, so protect exported CSVs.

```powershell
.\Workstation\Get-RemoteLoggedOnUser.ps1 -ComputerName PC001
```

QUser rows support an optional session name and single or multiple spaces. Usernames containing spaces and unfamiliar formats are not supported. State and logon-date text are preserved verbatim rather than translated or converted. Malformed rows report `ParseError`.

PSLoggedOn lines containing a backslash are returned verbatim in `RawOutput`, with `Status = RawOutput` and no asserted username. Review them as tool output, not validated identities. Its license must be reviewed and accepted separately; the wrapper does not accept it automatically.

Input and CSV errors stop the script. CSV export creates missing parent directories and overwrites existing output. Per-host query errors are returned as structured error records.

Tests used mocked commands only: active and disconnected rows, current-session marker, localized state/date preservation, malformed rows, no sessions, command failure, deduplication, file comments/blanks, CSV, raw PSLoggedOn lines, and absence of automatic EULA acceptance. No actual remote session query or Sysinternals execution was performed.

## Reproducing the checks

Both scripts parsed and the tests passed on Windows PowerShell 5.1.26100.9818 and PowerShell 7.6.9. Run these from the repository root in Windows PowerShell 5.1 to build the harmless argument-echo stub, then run the test in either shell:

```powershell
New-Item -ItemType Directory .\tests\fixtures -Force
.\tests\BuildStub.ps1 -Output "$PWD\tests\fixtures\iperf stub.exe"
.\tests\Network.Tests.ps1
```

The stub opens no sockets. The tests temporarily mock native command names and create synthetic files in a GUID-named temporary folder. Run in a disposable PowerShell process. Fixtures are retained for inspection. Compiled stub binaries are not included in the repository. These are focused mock tests, not production certification.
