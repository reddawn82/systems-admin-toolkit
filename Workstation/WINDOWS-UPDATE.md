# Windows Update cache reset

Brian reports using the original script during his career. This revised public copy received the mock checks below, not a live Windows Update reset. Prior operational use has not been independently verified.

## Usage

Run Reset-WindowsUpdateComponents.ps1 -WhatIf to preview. Actual execution requires an elevated PowerShell session and confirmation. It moves cache folders and stops/restarts services; plan a maintenance window. Add -RestartComputer only if you want a reboot after successful completion. Keep returned backup paths and error details for recovery.

## Recovery behavior

- Preview returns before elevation checks or service/filesystem reads.
- Actual execution still requires administrator membership and confirmation.
- Preflight all three service states and both cache paths before changing anything. Refuse transitional service states, non-directory/reparse-point caches, and existing backup destinations.
- Preserve initial service state: stop only services initially running and restore only services whose stop was attempted. Initially stopped services are not deliberately started.
- Do not use Force to stop services, avoiding an implicit stop of untracked dependents.
- Use timestamp-plus-GUID backup names; never overwrite backups or delete cache contents.
- If stopping or moving fails, roll back completed cache moves in reverse order before restoring services. Refuse rollback if the original path now exists.
- If a service fails to restart, retain backups and report failure. Do not roll caches back after service restoration begins because Windows may already have recreated them.
- Return initial states, restored services, move/rollback details and accumulated errors, then throw on incomplete recovery.
- Restart only when explicitly requested and all reset/restoration steps succeeded, with its own ShouldProcess check.

## Validation

Parser and 12 mock scenarios passed in Windows PowerShell 5.1.26100.9818 and PowerShell 7.6.9: WhatIf, mixed initial service states, missing/transitional services, reparse path, backup collision, stop failure, wait timeout, second-folder move failure with rollback, rollback failure, service-restart failure, and explicit successful restart.

All Get/Stop/Start-Service, Test-Path, Get-Item, Move-Item and Restart-Computer operations were replaced by in-memory mocks. Administrator membership was mocked. The test harness reads the current Windows identity only to satisfy the production constructor expression; it does not change security settings. No real services, caches, registry, reboot, or Windows Update state was changed.

## Remaining limitations

Mocks do not reproduce Windows Update locks, dependent-service behavior, ACLs, disk faults, reboots, or races with other administrators/services. Recovery is best effort, not a transaction. A partial failure can leave backups or require manual service recovery; errors and backup locations are retained for inspection. No automatic rollback happens after service restoration starts. Validate in a disposable Windows VM before operational deployment. Re-running is possible but is not a substitute for reviewing a prior failure.
