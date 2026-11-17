$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\DataManagement\Delete_Multiple_Directories.ps1'
$tokens=$null; $errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw "Parser errors: $errors" }
$fixture=Join-Path $env:TEMP ('toolkit-purge-preview-'+[guid]::NewGuid())
$empty=Join-Path $fixture 'empty'
$logs=Join-Path $fixture 'logs'
$target=Join-Path $fixture 'target'
$nested=Join-Path $target 'nested'
@($empty,$logs,$target,$nested) | ForEach-Object { [void](New-Item -ItemType Directory -Path $_) }
$file=Join-Path $nested 'keep.txt'
Set-Content -LiteralPath $file -Value 'Synthetic preview fixture, not user data.'
$hash=(Get-FileHash -LiteralPath $file).Hash
$r=& $scriptPath -Target $target -EmptySource $empty -LogRoot $logs -WhatIf -Force
if ($r.Result -ne 'PreviewComplete') { throw "Preview failed: $($r|Out-String)" }
if (-not (Test-Path -LiteralPath $file)) { throw 'Preview removed fixture file' }
if ((Get-FileHash -LiteralPath $file).Hash -ne $hash) { throw 'Preview modified fixture file' }
$r=& $scriptPath -Target ([IO.Path]::GetPathRoot($fixture)) -EmptySource $empty -LogRoot $logs -WhatIf
if ($r.Result -ne 'Rejected') { throw 'Drive root was not rejected' }
$r=& $scriptPath -Target $fixture -EmptySource $empty -LogRoot $logs -WhatIf
if ($r.Result -ne 'Rejected') { throw 'Support-directory parent was not rejected' }
$r=& $scriptPath -Target (Join-Path $fixture 'missing') -EmptySource $empty -LogRoot $logs -WhatIf
if ($r.Result -ne 'NotFound') { throw 'Missing target was not reported' }
Set-Content -LiteralPath (Join-Path $empty 'not-empty.txt') -Value 'Synthetic source validation fixture.'
$refused=$false
try { & $scriptPath -Target $target -EmptySource $empty -LogRoot $logs -WhatIf | Out-Null }
catch { $refused=$_.Exception.Message -like '*not empty*' }
if (-not $refused) { throw 'Nonempty source was not refused' }
"PASS: parser, real Robocopy list-only preview, unchanged fixture, drive-root/support-directory rejection, missing target, nonempty source. Fixtures retained: $fixture"
