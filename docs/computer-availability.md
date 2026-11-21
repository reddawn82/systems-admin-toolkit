# Network utilities

## Test-ComputerAvailability.ps1

Checks ICMP reachability and returns PowerShell objects. Runs independently of Node Watch; no domain membership or external ping tool is required.

```powershell
.\Network\Test-ComputerAvailability.ps1 -ComputerName 127.0.0.1 -Count 2
.\Network\Test-ComputerAvailability.ps1 -ComputerListPath .\targets.txt -OutputPath .\results.csv
```

Supply hostnames or IP addresses directly, or one per line in a text file. Blank lines and comments beginning with `#` are ignored. Duplicate targets are removed.

Results include successful/attempted pings, average reply time, elapsed time, and a status/error for unanswered targets.

- Only test systems you are authorized to access.
- `Unreachable` means no ICMP response, not proof a computer is off. Firewalls can block ICMP.
- `Online` means at least one reply, not that a service or application is healthy.
- DNS resolution can take longer than the ICMP reply timeout.
- CSV export creates missing parent folders and overwrites an existing output file. Input and export failures stop the script.

## Validation

Loopback and synthetic-file tests passed on Windows PowerShell 5.1.26100.9818 and PowerShell 7.6.9. Coverage: parsing, two loopback replies, direct/file deduplication, comments/blank lines, nested CSV output, empty targets/list, count/timeout bounds, missing input, and invalid output path.

No domain, remote-host, firewall, DNS-failure, or production-environment tests were performed. Test in your own lab before operational use.

Run the supplied smoke test from the repository root:

```powershell
.\tests\Test-ComputerAvailability.Tests.ps1
```

It uses loopback and creates a uniquely named fixture folder under your temporary directory. Fixtures are retained for inspection; no existing user files are removed.
