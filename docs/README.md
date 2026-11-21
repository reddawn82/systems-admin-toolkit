# Usage guides

Run the examples from the repository root unless the guide says otherwise. Examples use Windows PowerShell or PowerShell for Windows as described in each guide. Review its requirements and limitations before running anything beyond the local example.

## Start with reporting

- [Computer availability](computer-availability.md): ICMP reachability with a local loopback example.
- [Folder-size report](folder-size-report.md): logical bytes and file counts.
- [Active Directory](active-directory.md): report users and inactive computers; the same guide has a separate account-change section.
- [Remote registry report](remote-registry-report.md): query keys and values only.
- [Network and session utilities](network-session-utilities.md): read remote session state, or use iPerf3 for authorized throughput testing.
- [Certificate padding](certificate-padding.md): check the current setting before considering remediation.

## Review before making changes

- [AD account imports and password resets](active-directory.md#account-import-and-password-reset)
- [Directory contents purge](directory-purge.md)
- [Certificate-padding remediation](certificate-padding.md)
- [Service changes and application uninstall](workstation-administration.md)
- [Windows Update cache reset](windows-update-reset.md)

See the [toolkit overview](../README.md) and [test instructions](../tests/README.md).
