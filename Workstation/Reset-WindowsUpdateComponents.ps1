<#
.SYNOPSIS
Backs up the Windows Update caches while preserving service state.
.DESCRIPTION
Stops running BITS, Windows Update and Cryptographic Services, moves their cache
folders to unique backup paths, then restores the services that were running.
Initially stopped services stay stopped. Existing backups are never overwritten.
If a cache move fails, completed moves are rolled back before services restart.
No automatic rollback occurs after service restoration begins: caches may already
have been recreated. Review the returned backup paths if recovery is incomplete.
.PARAMETER RestartComputer
Requests a restart only after the reset and service restoration both succeed.
.EXAMPLE
.\Reset-WindowsUpdateComponents.ps1 -WhatIf
.NOTES
Run elevated for actual changes. Test in a disposable Windows lab before deployment.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param([switch]$RestartComputer)

if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Back up Windows Update caches and restore initial service states')) { return }
$principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run from an elevated PowerShell session.' }

$serviceNames = @('bits','wuauserv','cryptsvc')
$initial = @{}
$stopAttempts = [Collections.Generic.List[string]]::new()
$moved = [Collections.Generic.List[object]]::new()
$restored = [Collections.Generic.List[string]]::new()
$errors = [Collections.Generic.List[string]]::new()
$suffix = (Get-Date -Format 'yyyyMMdd_HHmmss') + '.' + [guid]::NewGuid().ToString('N')
$root = [IO.Path]::GetFullPath($env:SystemRoot)
$folders = @('SoftwareDistribution','System32\catroot2') | ForEach-Object {
    $path = Join-Path $root $_
    [pscustomobject]@{Path=$path;BackupPath="$path.bak.$suffix";RolledBack=$false}
}
$resetComplete = $false
try {
    # Preflight everything before stopping the first service.
    foreach ($name in $serviceNames) {
        $svc = Get-Service -Name $name -ErrorAction Stop
        if ($svc.Status.ToString() -notin @('Running','Stopped')) { throw "Service $name is in transitional state $($svc.Status); retry when stable." }
        $initial[$name] = $svc.Status.ToString()
    }
    foreach ($folder in $folders) {
        if (Test-Path -LiteralPath $folder.Path) {
            $item = Get-Item -LiteralPath $folder.Path -Force -ErrorAction Stop
            if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Not an ordinary cache directory: $($folder.Path)" }
        }
        if (Test-Path -LiteralPath $folder.BackupPath) { throw "Backup already exists: $($folder.BackupPath)" }
    }
    foreach ($name in $serviceNames) {
        if ($initial[$name] -eq 'Running') {
            $stopAttempts.Add($name)
            # Do not force-stop dependent services that this script does not track.
            Stop-Service -Name $name -ErrorAction Stop
            (Get-Service -Name $name -ErrorAction Stop).WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped,[TimeSpan]::FromSeconds(30))
        }
    }
    foreach ($folder in $folders) {
        if (Test-Path -LiteralPath $folder.Path -PathType Container) {
            Move-Item -LiteralPath $folder.Path -Destination $folder.BackupPath -ErrorAction Stop
            $moved.Add($folder)
        }
    }
    $resetComplete = $true
}
catch {
    $errors.Add($_.Exception.Message)
    # Roll back only before service restoration, without overwriting a new path.
    for ($i=$moved.Count-1; $i -ge 0; $i--) {
        $folder=$moved[$i]
        try {
            if (Test-Path -LiteralPath $folder.Path) { throw "Rollback destination already exists: $($folder.Path)" }
            if (-not (Test-Path -LiteralPath $folder.BackupPath -PathType Container)) { throw "Backup unavailable: $($folder.BackupPath)" }
            Move-Item -LiteralPath $folder.BackupPath -Destination $folder.Path -ErrorAction Stop
            $folder.RolledBack=$true
        }
        catch { $errors.Add("Rollback failed: $($_.Exception.Message)") }
    }
}
finally {
    foreach ($name in @('cryptsvc','bits','wuauserv')) {
        if ($stopAttempts -contains $name) {
            try {
                $svc=Get-Service -Name $name -ErrorAction Stop
                if ($svc.Status -ne 'Running') {
                    Start-Service -Name $name -ErrorAction Stop
                    (Get-Service -Name $name -ErrorAction Stop).WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running,[TimeSpan]::FromSeconds(30))
                }
                $restored.Add($name)
            }
            catch { $errors.Add("Could not restore ${name}: $($_.Exception.Message)") }
        }
    }
}
$success=$resetComplete -and $errors.Count -eq 0
[pscustomobject]@{
    ComputerName=$env:COMPUTERNAME
    Success=$success
    InitialServiceStates=$initial
    ServicesRestored=$restored.ToArray()
    CacheMoves=$moved.ToArray()
    RestartRequested=[bool]$RestartComputer
    Errors=$errors.ToArray()
}
if (-not $success) { throw ('Reset incomplete: ' + ($errors -join '; ')) }
if ($RestartComputer -and $PSCmdlet.ShouldProcess($env:COMPUTERNAME,'Restart computer after successful reset')) { Restart-Computer -Force -ErrorAction Stop }
