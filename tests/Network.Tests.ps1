param([string]$Root = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
function Assert($ok,$message){if(-not $ok){throw $message}}
function Throws([scriptblock]$code){$yes=$false;try{& $code|Out-Null}catch{$yes=$true};Assert $yes 'Expected failure'}
$exe=Join-Path $PSScriptRoot 'fixtures\iperf stub.exe'
$iperf=Join-Path $Root 'Network\Invoke-Iperf3.ps1'
$logged=Join-Path $Root 'Workstation\Get-RemoteLoggedOnUser.ps1'
foreach($p in @($iperf,$logged)){$t=$null;$e=$null;[Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e)|Out-Null;Assert (-not $e) "Parse failed: $p"}
$r=@(& $iperf -Mode Client -Server '192.0.2.10' -IperfPath $exe -IperfArguments '-t','30','two words')
Assert (($r -join '|') -eq '-c|192.0.2.10|-t|30|two words') 'Client argument forwarding failed'
$r=@(& $iperf -Mode Server -IperfPath $exe -IperfArguments '-p','5202')
Assert (($r -join '|') -eq '-s|-p|5202') 'Server argument forwarding failed'
Throws {& $iperf -Mode Client -IperfPath $exe}
Throws {& $iperf -Mode Server -IperfPath (Join-Path $PSScriptRoot 'absent.exe')}
Throws {& $iperf -Mode Server -IperfPath $exe -IperfArguments '--fail'}
Throws {& $iperf -Mode Invalid -IperfPath $exe}
$global:queryMode='rows'
function global:quser.exe {
 $global:LASTEXITCODE=0
 if($global:queryMode -eq 'failure'){$global:LASTEXITCODE=5;'Access denied';return}
 'USERNAME SESSIONNAME ID STATE IDLE TIME LOGON TIME'
 if($global:queryMode -eq 'empty'){return}
 '>alice console 1 Active . 11/16/2026 8:00 AM'
 'bob                      2 Disc            3+04:12 11/15/2026 7:00 PM'
 'carol rdp-tcp#4 3 Aktiv . 16.11.2026 08:00'
 'bad line'
}
$r=@(& $logged -ComputerName 'fixture-host',' fixture-host ')
Assert ($r.Count -eq 4) 'Deduplication or row count failed'
Assert ($r[0].UserName -eq 'alice' -and $r[0].SessionId -eq '1' -and $r[0].SessionName -eq 'console') 'Active row parse failed'
Assert ($r[1].UserName -eq 'bob' -and $r[1].SessionId -eq '2' -and -not $r[1].SessionName) 'Disconnected row parse failed'
Assert ($r[2].State -eq 'Aktiv' -and $r[2].LogonTime -eq '16.11.2026 08:00') 'Locale text preservation failed'
Assert ($r[3].Status -eq 'ParseError') 'Malformed row not reported'
$global:queryMode='empty';$r=& $logged -ComputerName fixture-host
Assert ($r.Status -eq 'NoSessions') 'Header-only response failed'
$global:queryMode='failure';$r=& $logged -ComputerName fixture-host
Assert ($r.Status -eq 'Error' -and $r.Error -match 'Access denied') 'Native failure reporting failed'
function global:psloggedon.exe { $global:LASTEXITCODE=0; if($args -contains '-accepteula'){throw 'Unexpected EULA acceptance'}; 'Users logged on locally:'; '11/16/2026 8:00 AM LAB\alice' }
$r=& $logged -ComputerName fixture-host -Method PSLoggedOn
Assert ($r.Status -eq 'RawOutput' -and $r.RawOutput -match 'LAB\\alice' -and -not $r.UserName) 'Raw Sysinternals reporting failed'
Throws {& $logged -ComputerName ' '}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('network-review-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $fixture|Out-Null
@('# comment','','fixture-host',' fixture-host ')|Set-Content (Join-Path $fixture 'targets.txt')
$global:queryMode='rows'
$r=@(& $logged -ComputerListPath (Join-Path $fixture 'targets.txt') -OutputPath (Join-Path $fixture 'nested\results.csv'))
Assert ($r.Count -eq 4) 'File targets failed'
Assert (@(Import-Csv (Join-Path $fixture 'nested\results.csv')).Count -eq 4) 'CSV failed'
Remove-Item Function:\quser.exe,Function:\psloggedon.exe
'PASS: parser, native stub arguments/exit, parameter validation, mocked session formats/failures/raw output, dedupe and CSV'
$PSVersionTable.PSVersion.ToString()
