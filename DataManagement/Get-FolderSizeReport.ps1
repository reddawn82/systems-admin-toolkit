<#
.SYNOPSIS
Reports logical file sizes beneath local or UNC folders.
.DESCRIPTION
Returns structured results and optionally exports CSV. Reparse points are skipped,
including junctions and symbolic links. Sizes are logical bytes, not disk usage;
hard-linked files are counted once per directory entry.
.PARAMETER Path
Folders to scan, supplied directly or through the pipeline.
.PARAMETER PathListFile
Text file containing one folder path per line. Blank lines are ignored.
.PARAMETER OutputPath
Optional CSV file. Missing parent folders are created; an existing file is overwritten.
.EXAMPLE
.\Get-FolderSizeReport.ps1 -Path C:\Data -OutputPath .\sizes.csv
.NOTES
Use only on folders you are authorized to read. Inaccessible contents produce a
Failed result without a misleading partial total. UNC access depends on your session.
#>
[CmdletBinding(DefaultParameterSetName='Path')]
param(
    [Parameter(Mandatory,ParameterSetName='Path',ValueFromPipeline,ValueFromPipelineByPropertyName)]
    [Alias('FullName')][ValidateNotNullOrEmpty()][string[]]$Path,
    [Parameter(Mandatory,ParameterSetName='PathList')][string]$PathListFile,
    [string]$OutputPath
)
begin { $paths=[Collections.Generic.List[string]]::new() }
process {
    if($PSCmdlet.ParameterSetName -eq 'Path') {
        foreach($p in $Path){if(-not [string]::IsNullOrWhiteSpace($p)){$paths.Add($p.Trim())}}
    }
}
end {
    if($PSCmdlet.ParameterSetName -eq 'PathList') {
        Get-Content -LiteralPath $PathListFile -ErrorAction Stop | ForEach-Object {
            if(-not [string]::IsNullOrWhiteSpace($_)){$paths.Add($_.Trim())}
        }
    }
    if($paths.Count -eq 0){throw 'No folder paths were provided.'}
    $results=foreach($p in $paths){
        $bytes=[long]0; $count=0; $skipped=0; $status='Success'; $message=$null
        try {
            $root=Get-Item -LiteralPath $p -Force -ErrorAction Stop
            if($root.PSProvider.Name -ne 'FileSystem' -or -not $root.PSIsContainer){throw 'Path must be a filesystem folder.'}
            if($root.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'A reparse-point root is not supported.'}
            $pending=[Collections.Generic.Stack[string]]::new()
            $pending.Push($root.FullName)
            while($pending.Count -gt 0){
                foreach($entry in (Get-ChildItem -LiteralPath $pending.Pop() -Force -ErrorAction Stop)){
                    if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){$skipped++;continue}
                    if($entry.PSIsContainer){$pending.Push($entry.FullName)}
                    else{$bytes+=$entry.Length;$count++}
                }
            }
        } catch {$status='Failed';$message=$_.Exception.Message;$bytes=$null;$count=$null}
        [pscustomobject]@{
            Path=$p
            SizeBytes=$bytes
            SizeGB=if($null -ne $bytes){[math]::Round($bytes/1GB,4)}else{$null}
            FileCount=$count
            SkippedReparsePoints=$skipped
            Status=$status
            Error=$message
        }
    }
    if($OutputPath){
        $parent=Split-Path -Parent $OutputPath
        if($parent -and -not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop|Out-Null}
        $results|Export-Csv -LiteralPath $OutputPath -NoTypeInformation -ErrorAction Stop
    }
    $results
}
