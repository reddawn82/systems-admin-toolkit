$ErrorActionPreference='Stop'
$script=Join-Path $PSScriptRoot '..\DataManagement\Get-FolderSizeReport.ps1'
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($script,[ref]$tokens,[ref]$errors)|Out-Null
if($errors){throw 'Parser failure'}
function Assert($ok,$message){if(-not $ok){throw $message}}
function Throws([scriptblock]$action){$caught=$false;try{& $action|Out-Null}catch{$caught=$true};Assert $caught 'Expected terminating error'}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('folder-size-tests-'+[guid]::NewGuid())
$scan=Join-Path $fixture 'scan'
$empty=Join-Path $fixture 'empty'
$outside=Join-Path $fixture 'outside'
New-Item -ItemType Directory -Path $scan,$empty,$outside|Out-Null
[IO.File]::WriteAllBytes((Join-Path $scan 'one.bin'),[byte[]]::new(100))
$nested=Join-Path $scan 'nested'
New-Item -ItemType Directory -Path $nested|Out-Null
[IO.File]::WriteAllBytes((Join-Path $nested 'two.bin'),[byte[]]::new(200))
[IO.File]::WriteAllBytes((Join-Path $outside 'excluded.bin'),[byte[]]::new(400))
$link=Join-Path $scan 'link'
New-Item -ItemType Junction -Path $link -Target $outside|Out-Null
$r=& $script -Path $scan
Assert ($r.Status -eq 'Success' -and $r.SizeBytes -eq 300 -and $r.FileCount -eq 2 -and $r.SkippedReparsePoints -eq 1) 'Nested/junction size mismatch'
$r=& $script -Path $link
Assert ($r.Status -eq 'Failed' -and $null -eq $r.SizeBytes) 'Junction root must fail'
$r=& $script -Path $empty
Assert ($r.SizeBytes -eq 0 -and $r.FileCount -eq 0 -and $r.Status -eq 'Success') 'Empty folder mismatch'
$r=@($scan,$empty|& $script)
Assert ($r.Count -eq 2) 'Pipeline input failed'
$list=Join-Path $fixture 'paths.txt'
@('',$scan,$empty)|Set-Content -LiteralPath $list
$csv=Join-Path $fixture 'reports\sizes.csv'
$r=@(& $script -PathListFile $list -OutputPath $csv)
Assert ($r.Count -eq 2 -and @(Import-Csv -LiteralPath $csv).Count -eq 2) 'CSV/list failure'
$r=& $script -Path (Join-Path $fixture 'missing')
Assert ($r.Status -eq 'Failed' -and $null -eq $r.SizeBytes) 'Missing folder must not report zero'
Throws {& $script -Path '   '}
Throws {& $script -PathListFile (Join-Path $fixture 'missing.txt')}
Throws {& $script -Path $scan -OutputPath (Join-Path (Join-Path $scan 'one.bin') 'bad.csv')}
'PASS: parser, exact nested byte count, empty folder, pipeline, list, CSV, missing input, invalid output, junction child exclusion and root rejection'
$PSVersionTable.PSVersion.ToString()
"Synthetic fixture retained: $fixture"
