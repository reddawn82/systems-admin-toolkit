# Directory contents purge

Delete_Multiple_Directories.ps1 uses an empty source with Robocopy /PURGE to remove destination contents while leaving each target folder in place.

**Destructive:** a live run permanently removes destination files and folders, without the Recycle Bin or rollback. Back up anything you need. Check the destination, not just the empty source. -Force or -Confirm:$false suppresses confirmation; neither makes the operation safer.

## Preview first

Create empty-source and log folders outside all targets before using -WhatIf. For example, create C:\PurgeSupport\Empty and C:\PurgeSupport\Logs, then run:

    .\DataManagement\Delete_Multiple_Directories.ps1 -Target C:\DisposableData -EmptySource C:\PurgeSupport\Empty -LogRoot C:\PurgeSupport\Logs -WhatIf

After reviewing the targets and logs, omit -WhatIf for a live run with confirmation. Do not use a real target just to try the script.

## Important limits

- Drive roots and UNC share roots are rejected. Targets containing the configured source or log folder are rejected using path-string checks.
- These checks do **not** establish filesystem containment. Robocopy is not passed /XJ; junctions, symbolic links, mount points, redirected ancestors and concurrent path changes are not covered. Do not use those paths or trees. Root/path checks are not a security boundary.
- Existing empty-source and log directories are needed for reliable preview: PowerShell may suppress their creation under -WhatIf, causing setup to fail. Preview invokes Robocopy with /L and can write a log, but does not request deletion.
- Robocopy codes below 8 are reported as success. This is not independent verification that every intended item was removed. Read the log and inspect the destination.
- No rollback or atomicity is provided. Permissions, open files and errors can leave a partially purged tree. Keep the source empty and control access to it for the entire run.
- The included tests do not cover UNC behavior, reparse-point behavior, live deletion or failure recovery.

## Verification

Validation is limited to syntax, path checks and list-only previews against synthetic data.

tests/DirectoryPurge.Preview.Tests.ps1 passed on Windows PowerShell 5.1.26100.9818 and PowerShell 7.6.9: syntax, real Robocopy list-only preview, unchanged synthetic file/hash, drive-root rejection, support-directory-parent rejection, missing target and nonempty-source refusal. No live purge was run. GUID-named fixtures and logs are retained under the temporary directory.
