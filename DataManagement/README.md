# Folder size reporting

`Get-FolderSizeReport.ps1` reports logical bytes, file count, and rounded GB for each supplied filesystem folder. It accepts paths, pipeline input, or a text list and can export CSV.

```powershell
.\Get-FolderSizeReport.ps1 -Path C:\Data
.\Get-FolderSizeReport.ps1 -PathListFile .\folders.txt -OutputPath .\sizes.csv
```

## Boundaries

- Reparse-point entries are skipped, and a root that is itself a junction/symlink is rejected. Do not use a path whose ancestors redirect outside the scope you intend to scan.
- A traversal error returns `Failed` and null totals rather than a partial size presented as complete.
- `SizeBytes` is logical file length, not allocated disk usage. Hard links are counted per directory entry; files changing during enumeration can produce a non-atomic snapshot.
- A folder-name-specific project-number field was removed from this standalone version.
- CSV output overwrites an existing output file and creates missing parent directories.
- Use only on authorized paths. Large trees may take time. No remote systems are contacted unless you supply a remote path.

## Tests

`Get-FolderSizeReport.Tests.ps1` passed on Windows PowerShell 5.1.26100.9818 and PowerShell 7.6.9: parser, exact nested byte counts, empty directory, pipeline input, text-list input, nested CSV export, blank input, missing input, invalid output path, junction child exclusion and junction root rejection.

Tests create and retain GUID-named synthetic folders under the temporary directory. Their junction targets remain inside the same synthetic fixture. No user files are removed. Live UNC shares, ACL-denied subtrees, concurrent mutations, long-path limits and file-symlink variants were not tested.

## Directory contents purge

See [directory purge](DIRECTORY-PURGE.md) for the separate destructive utility, required precautions and preview-only test coverage. Folder-report reparse protections above do not apply to the purge script.
