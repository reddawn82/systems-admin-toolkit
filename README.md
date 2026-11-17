# Systems administration toolkit

Brian reports having used the original scripts during his career. The checks described here cover the revised public copies and do not independently verify that earlier operational use or establish live testing of the revisions.

Practical Windows administration scripts with usage notes and reproducible checks.

## Utilities

| Area | Scripts | Notes |
| --- | --- | --- |
| [Active Directory](AD/README.md) | User export/import, password updates, inactive-computer report | AD commands tested with mocks; no live domain validation |
| [Data management](DataManagement/README.md) | Folder-size report, directory-contents purge | Folder report: synthetic/junction fixtures. Purge: list-only preview, no live deletion; [warnings](DataManagement/DIRECTORY-PURGE.md) |
| [Network](Network/README.md) | ICMP availability | Real loopback and file/CSV tests |
| [Network and sessions](docs/network-session-utilities.md) | iPerf3 launcher, remote logged-on sessions | Harmless native stub and command mocks |
| [Registry](Registry/README.md) | Remote registry key/value report | Remoting and registry-query mocks |
| [Workstation](Workstation/README.md) | Certificate-padding check/remediation, service state, application uninstall, Windows Update cache reset | Registry, WMI, process-launch and reset-recovery mocks |

## Use and verification

Tests passed on Windows PowerShell 5.1.26100.9818 and PowerShell 7.6.9. This does not mean every script supports both runtimes: the remote-service utility needs Windows PowerShell 5.1 for real WMI operations. See each area's documentation for dependencies, examples, tested cases, and gaps.

No real AD accounts, remote services, registry settings, installed applications, or Windows Update state were changed during validation. Mock tests establish local logic, not production compatibility. Test in your own lab before operational use, especially for account changes, remediation, service changes, and uninstall operations. Use `-WhatIf` where supported.

Keep credentials, target lists, and generated reports private. Only operate on systems you are authorized to administer. Mutation operations are not transactional and may partially succeed before an error.

See [tests](tests/README.md) for reproduction steps. No production-readiness or comprehensive security certification is implied.
