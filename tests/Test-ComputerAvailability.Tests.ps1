$ErrorActionPreference='Stop'
$script=Join-Path $PSScriptRoot '..\Network\Test-ComputerAvailability.ps1'
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($script,[ref]$tokens,[ref]$errors)|Out-Null
if($errors){throw 'Parser failed'}
function Assert($ok,$message){if(-not $ok){throw $message}}
function Throws([scriptblock]$code){$yes=$false;try{& $code|Out-Null}catch{$yes=$true};Assert $yes 'Expected terminating error'}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('fixture-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $fixture|Out-Null
$r=@(& $script -ComputerName '127.0.0.1',' 127.0.0.1 ' -Count 2)
Assert ($r.Count -eq 1 -and $r[0].SuccessfulPings -eq 2 -and $r[0].Reachable) 'Loopback/dedupe failed'
$list=Join-Path $fixture 'targets.txt'
@('# comment','',' 127.0.0.1 ','127.0.0.1')|Set-Content -LiteralPath $list
$csv=Join-Path $fixture 'nested\report.csv'
$r=@(& $script -ComputerListPath $list -OutputPath $csv)
$saved=@(Import-Csv -LiteralPath $csv)
Assert ($r.Count -eq 1 -and $saved.Count -eq 1 -and $saved[0].ComputerName -eq '127.0.0.1') 'File/CSV failed'
Throws {& $script -ComputerName '   '}
Throws {& $script -ComputerName '127.0.0.1' -Count 0}
Throws {& $script -ComputerName '127.0.0.1' -TimeoutSeconds 0}
Throws {& $script -ComputerListPath (Join-Path $fixture 'missing.txt')}
$blocked=Join-Path $fixture 'blocked'
'x'|Set-Content -LiteralPath $blocked
Throws {& $script -ComputerName '127.0.0.1' -OutputPath (Join-Path $blocked 'output.csv')}
$empty=Join-Path $fixture 'empty.txt'
'# only a comment'|Set-Content -LiteralPath $empty
Throws {& $script -ComputerListPath $empty}
'PASS: parser, loopback, direct and file dedupe, comments, CSV and nested folders, blank targets, empty list, count/timeout validation, missing input, invalid output path'
$PSVersionTable.PSVersion.ToString()
