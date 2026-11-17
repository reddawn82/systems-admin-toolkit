# Active Directory reports

Brian reports having used the original scripts during his career. The checks described here cover the revised public copies and do not independently verify that earlier operational use or establish live testing of the revisions.

These reports require the ActiveDirectory module (RSAT) and permission to read the requested directory data. They do not modify accounts. Use only in directories you administer; exported user data should remain private.

## AD_Export_Users.ps1

Exports user identity, enabled status, and optional attributes from an explicit search base.

```powershell
.\AD_Export_Users.ps1 -SearchBase 'OU=Lab,DC=example,DC=invalid' -AdditionalProperty EmployeeID -OutputPath .\users.csv
```

## Get-ADInactiveComputers.ps1

Reports accounts older than a calendar-month cutoff, optionally including accounts with no replicated logon timestamp.

```powershell
.\Get-ADInactiveComputers.ps1 -MonthsInactive 6 -IncludeNeverLoggedOn -OutputPath .\inactive.csv
```

LastLogonDate can lag actual logons. A missing timestamp does not prove a computer has never been used. Treat output as a review list, not an automatic deletion/disable list.

Both scripts overwrite the chosen CSV and create missing parent folders. Directory-query and output failures stop the script. Empty results return no objects; a CSV with useful column headers is not guaranteed when there are no rows.

## Tests and limits

AD-Reports.Mock.Tests.ps1 passed on Windows PowerShell 5.1.26100.9818 and PowerShell 7.6.9. Tests replace Import-Module, Get-ADUser, and Get-ADComputer with local functions. No domain is contacted. Coverage includes parsing, attribute projection/deduplication, SearchBase forwarding, never-logon query selection, computer deduplication, output CSVs and nested folders, empty results, invalid month bounds, lookup failures, and output failures.

Run the mock tests in a fresh PowerShell process, not by dot-sourcing them. Synthetic fixture folders are retained in TEMP for inspection.

```powershell
powershell.exe -NoProfile -File .\AD-Reports.Mock.Tests.ps1
```

Actual ActiveDirectory module loading, server-side filters, permissions, schema-specific attributes, replication behavior, and live domain results have not been tested. Review results in a lab before operational use.

## Account import and password reset

AD_Import_Users.ps1 creates accounts from CSV columns `username,password,firstname,lastname,description,ou` with an explicit UPN suffix. AD_Import_Set_Password.ps1 requires `username,password` and optionally `EmployeeID`.

Start with `-WhatIf`. WhatIf/declined confirmation returns `NotChanged`; malformed rows return `Skipped`. Creation proceeds only after an explicit ADIdentityNotFoundException; other lookup failures return `Failed`. No broad lookup failure is treated as an absent account.

Password-reset results include `CompletedSteps`. `Partial` means at least one step returned successfully before another failed. Do not blindly retry: inspect the account first. These operations are not transactional and do not roll back. Even `Failed` cannot prove that a server made no change before returning an error, especially after a connection failure. A New-ADUser error can leave an account behind; verify directory state before retrying.

Input CSVs contain plaintext passwords. Use restricted storage, avoid version control or shared folders, and follow your organization's credential-handling policy. Outputs never include a password field; caught error messages redact the exact current-row password. This is not a general secret scrubber for arbitrary server diagnostics. Avoid logging input CSV contents.

AD-Mutations.Mock.Tests.ps1 passed on Windows PowerShell 5.1.26100.9818 and PowerShell 7.6.9. It validates parsing, explicit missing-identity creation, other lookup failure suppression, existing-account skip, WhatIf no-write behavior, secure-string arguments, full reset success, first-step failure, later-step partial results, current-password error redaction, blank rows, and missing columns. It defines a local stand-in exception type and mocked AD cmdlets; no real accounts are touched. Run only in a fresh process, not by dot-sourcing. All credentials in test fixtures are deliberately synthetic. Test folders are retained in TEMP.

Live AD behavior, password policies, OU/UPN validity, permissions, server-side partial failures, and real exception wrapping remain untested. These examples require lab validation and an authorized operator before account changes.
