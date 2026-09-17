# No external testing framework; isolate all Git writes and fault injection under tmp/.
param([switch]$Compact)
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
. (Join-Path $PSScriptRoot '../scripts/maintenance-core.ps1')
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixture = Join-Path $sourceRoot ('tmp/maintenance-' + [Guid]::NewGuid().ToString('N'))
$script:Assertions = 0
function Assert([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw "ASSERTION FAILED: $Message" }
    $script:Assertions++
}
function Must-Throw([scriptblock]$Operation, [string]$Message) {
    $thrown = $false
    try { & $Operation | Out-Null } catch { $thrown = $true }
    Assert $thrown $Message
}
function Put([string]$Relative, [string]$Text) {
    $path = Safe-Path $fixture $Relative
    [IO.Directory]::CreateDirectory((Split-Path $path -Parent)) | Out-Null
    [IO.File]::WriteAllText($path, $Text, $script:Utf8)
}
function Git-Write([string[]]$Arguments) {
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& git -C $fixture @Arguments 2>&1)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    if ($code -ne 0) { throw ($output -join "`n") }
}
function Event([string]$Name, [string]$Session = 'fixture-session', [string]$Turn = 'turn-1', [bool]$Active = $false) {
    return @{ hook_event_name = $Name; session_id = $Session; turn_id = $Turn; permission_mode = 'default'; stop_hook_active = $Active }
}
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$compactFiles = @('README.md', 'AGENTS.md', 'CONTRIBUTING.md', 'LICENSE', 'NOTICE.md',
    '.gitignore', '.gitattributes', 'Project.toml', 'Manifest.toml', 'src/PaperRebuild.jl',
    'test/runtests.jl', 'docs/make.jl', 'docs/Project.toml', 'docs/Manifest.toml',
    'tools/Project.toml', 'tools/Manifest.toml', 'docs/agent/current-state.md',
    'docs/agent/handbook.md', 'docs/src/quality.md', 'docs/src/generated-inventory.md', 'docs/reading/sources.json',
    '.codex/hooks.json', '.codex/maintenance-policy.json', '.vscode/file-groups.json',
    '.vscode/settings.json', '.vscode/tasks.json', '.vscode/extensions.json',
    '.vscode/launch.json', '.github/workflows/ci.yml', 'scripts/maintenance-core.ps1',
    'scripts/maintain.ps1')
$fixturePaths = if ($Compact) { $compactFiles } else { @(Candidate-Paths $sourceRoot) }
foreach ($relative in $fixturePaths) {
    $destination = Safe-Path $fixture $relative
    [IO.Directory]::CreateDirectory((Split-Path $destination -Parent)) | Out-Null
    [IO.File]::Copy((Safe-Path $sourceRoot $relative), $destination)
}
if ($Compact) {
    # 用代表图源执行同一组状态/竞态断言，避免测试成本随历史研究数据增长。
    Put 'docs/src/assets/test-batch/run/F04.csv' "value`n1`n"
    Put 'results/summaries/test-batch/run/F04.csv' "value`n1`n"
}
Git-Write @('init', '-q')
Git-Write @('config', 'user.name', 'Fixture')
Git-Write @('config', 'user.email', 'fixture@example.invalid')
Git-Write @('config', 'core.autocrlf', 'false')
Git-Write @('add', '.')
Git-Write @('commit', '-qm', 'fixture baseline')
Sync-Project $fixture
Check-Project $fixture
Assert $true 'clean clone checks without original documents'
if ($Compact) {
    $index = Inventory-Text $fixture
    Assert ($index -match 'docs/src/assets/test-batch/run/') 'artifact batch directory visible'
    Assert ($index -notmatch 'test-batch/run/F04.csv') 'repeated artifact members summarized'
    Assert ($index -match 'src/PaperRebuild.jl') 'source entry preserved'
}
Assert (!(Test-Path -LiteralPath (Join-Path $fixture 'docs/摘要.pdf'))) 'original PDF absent'
$snapshot = Snapshot $fixture
Sync-Project $fixture
Assert ((Snapshot $fixture) -eq $snapshot) 'Sync is idempotent'

# Manual groups, unknown fields, aliases, ordering and folded state survive synchronization.
$groupPath = Safe-Path $fixture '.vscode/file-groups.json'
$document = Read-Json $groupPath
$document.extra = 'unknown root field'
$document.groups[0].name = 'My entry'
$document.groups[0].collapsed = $false
$document.groups[0].order = 99
$document.groups[0].files[0].name = 'My alias'
$document.groups += [ordered]@{ id = 'manual'; name = '个人'; parentId = $null; files = @(); extra = 'keep' }
Put '.vscode/file-groups.json' (Json $document)
Sync-Project $fixture
$after = Read-Json $groupPath
Assert ($after.extra -eq 'unknown root field') 'unknown root field preserved'
Assert ($after.groups[0].name -eq 'My entry') 'custom group name preserved'
Assert (!$after.groups[0].collapsed) 'fold state preserved'
Assert ($after.groups[0].order -eq 99) 'UI order preserved'
Assert ($after.groups[0].files[0].name -eq 'My alias') 'alias preserved'
Assert ($after.groups[-1].extra -eq 'keep') 'manual group preserved'
Assert ($after.groups[-1].files.Count -eq 0) 'deleted manual bookmark not resurrected'
Put 'src/new_module.jl' "# fixture addition`n"
Sync-Project $fixture
Check-Project $fixture
Assert (@((Read-Json $groupPath).groups | Where-Object { $_.id -eq 'paperrebuild-code' } | ForEach-Object { $_.files } | Where-Object { $_.path -eq 'src/new_module.jl' }).Count -eq 1) 'new file discovered'
[IO.File]::Delete((Safe-Path $fixture 'src/new_module.jl'))
Sync-Project $fixture
Check-Project $fixture
Assert $true 'deleted owned member removed'

# Invalid graph and path behavior.
$valid = [IO.File]::ReadAllText($groupPath)
$bad = Read-Json $groupPath
$bad.groups += $bad.groups[0]
Must-Throw { Validate-Groups $fixture $bad $true } 'duplicate IDs rejected'
$bad = Read-Json $groupPath
$bad.groups[0].parentId = $bad.groups[0].id
Must-Throw { Validate-Groups $fixture $bad $true } 'cycles rejected'
$bad.groups[0].parentId = 'absent'
Must-Throw { Validate-Groups $fixture $bad $true } 'missing parent rejected'
foreach ($unsafe in @('../escape', 'C:/outside', '/absolute', 'a\b', 'a//b', 'a/./b')) {
    Must-Throw { Safe-Path $fixture $unsafe } "reject unsafe $unsafe"
}
$bad = Read-Json $groupPath
$bad.groups[0].files[0].isDirectory = $true
Must-Throw { Validate-Groups $fixture $bad $true } 'wrong type rejected'
Put '.vscode/file-groups.json' '{invalid'
Must-Throw { Sync-Project $fixture } 'malformed JSON does not get overwritten'
Assert ([IO.File]::ReadAllText($groupPath) -eq '{invalid') 'malformed file preserved'
Put '.vscode/file-groups.json' $valid

# Compare-and-swap and lock contention.
$oldHash = File-Hash $groupPath
Put '.vscode/file-groups.json' ($valid + ' ')
Must-Throw { Write-Atomic $fixture '.vscode/file-groups.json' '{}' $oldHash } 'stale write rejected'
Assert ([IO.File]::ReadAllText($groupPath) -eq ($valid + ' ')) 'concurrent content preserved'
Put '.vscode/file-groups.json' $valid
With-WriteLock $fixture { Must-Throw { With-WriteLock $fixture {} } 'exclusive writer lock' }
Assert ((Read-Json $groupPath).version -eq 2) 'atomic replacement keeps valid JSON'

# User dirtiness is the baseline, not a reason for needless documentation edits.
Put 'configs/preexisting.toml' 'existing = true'
$null = Handle-Hook $fixture (Event 'UserPromptSubmit')
$unchanged = Snapshot $fixture
$result = Handle-Hook $fixture (Event 'Stop')
Assert (!$result.ContainsKey('decision')) 'unchanged dirty workspace does not block'
Assert ((Snapshot $fixture) -eq $unchanged) 'read-only turn does not sync tracked files'
$plan = Event 'UserPromptSubmit' 'plan-session'
$plan.permission_mode = 'plan'
$null = Handle-Hook $fixture $plan
Assert (!(Test-Path -LiteralPath (Safe-Path $fixture (State-Relative 'plan-session')))) 'plan mode writes no state'
$start = Handle-Hook $fixture (Event 'SessionStart')
Assert ($start.hookSpecificOutput.additionalContext -match 'AGENTS.md') 'startup routes context'
Assert (Test-Path -LiteralPath (Safe-Path $fixture ('.codex/.local/maintenance/startup-' + (Text-Hash 'fixture-session') + '.json'))) 'startup receipt recorded'
$planStart = Event 'SessionStart' 'plan-start'
$planStart.permission_mode = 'plan'
$null = Handle-Hook $fixture $planStart
Assert (!(Test-Path -LiteralPath (Safe-Path $fixture ('.codex/.local/maintenance/startup-' + (Text-Hash 'plan-start') + '.json')))) 'plan startup records nothing'
$missing = Handle-Hook $fixture (Event 'Stop' 'missing')
Assert ($missing.systemMessage -match 'missing/stale') 'missing baseline visible'

# New change triggers one continuation; another session cannot consume the review.
Put 'src/new_module.jl' '# substantive change'
$first = Handle-Hook $fixture (Event 'Stop')
Assert ($first.decision -eq 'block') 'first relevant change requests continuation'
$second = Handle-Hook $fixture (Event 'Stop')
Assert (!$second.ContainsKey('decision')) 'second stop cannot loop'
Assert ($second.systemMessage -match 'unresolved') 'unresolved warning remains visible'
Review-Project $fixture 'fixture-session' 'turn-1' 'Reviewed toolchain and current state; fixture only.'
$reviewed = Handle-Hook $fixture (Event 'Stop')
Assert (!$reviewed.ContainsKey('decision') -and !$reviewed.ContainsKey('systemMessage')) 'matching review accepted'
Assert ((Read-Json (Safe-Path $fixture (State-Relative 'fixture-session'))).status -eq 'reviewed') 'receipt recorded'
Must-Throw { Review-Project $fixture 'other-session' 'turn-1' 'not a baseline' } 'sessions isolated'
Must-Throw { Review-Project $fixture 'fixture-session' 'wrong-turn' 'stale' } 'turn mismatch rejected'
Put 'src/new_module.jl' '# changed after review'
$stale = Handle-Hook $fixture (Event 'Stop')
Assert ($stale.systemMessage -match 'unresolved') 'edits invalidate receipt'
$null = Handle-Hook $fixture (Event 'UserPromptSubmit' 'second' 'turn-2')
Put 'src/new_module.jl' '# active stop change'
$active = Handle-Hook $fixture (Event 'Stop' 'second' 'turn-2' $true)
Assert (!$active.ContainsKey('decision')) 'stop_hook_active never blocks'
Assert ($active.systemMessage -match 'unresolved') 'active stop reports missing review'

# A commit in the same turn also invalidates a snapshot (even after working tree becomes clean).
Sync-Project $fixture
Git-Write @('add', '.')
$null = Handle-Hook $fixture (Event 'UserPromptSubmit' 'commit-session' 'turn-3')
Git-Write @('commit', '-qm', 'fixture changed within turn')
$committed = Handle-Hook $fixture (Event 'Stop' 'commit-session' 'turn-3')
Assert ($committed.decision -eq 'block') 'same-turn commit noticed'
$baseline = (Read-Json (Safe-Path $fixture (State-Relative 'commit-session'))).baseline
$null = Handle-Hook $fixture (Event 'UserPromptSubmit' 'commit-session' 'turn-3')
Assert ((Read-Json (Safe-Path $fixture (State-Relative 'commit-session'))).baseline -eq $baseline) 'duplicate prompt does not reset baseline'

# Real wrapper stdin: BOM, Chinese input, malformed JSON, and plan-mode no write.
$engine = (Get-Process -Id $PID).Path
$entry = Join-Path $fixture 'scripts/maintain.ps1'
$payload = [char]0xfeff + '{"hook_event_name":"SessionStart","permission_mode":"plan","prompt":"中文测试"}'
$output = $payload | & $engine -NoProfile -ExecutionPolicy Bypass -File $entry -Action Hook
Assert ($LASTEXITCODE -eq 0) 'BOM and Unicode stdin accepted'
Assert ((ConvertFrom-Json ($output -join "`n")).systemMessage -match 'read-only') 'plan wrapper result'
$badOutput = '{invalid' | & $engine -NoProfile -ExecutionPolicy Bypass -File $entry -Action Hook
Assert ($LASTEXITCODE -ne 0) 'invalid stdin exits nonzero'
Assert ((ConvertFrom-Json ($badOutput -join "`n")).systemMessage -match 'failed') 'invalid stdin reports failure'

Write-Output "Maintenance tests passed: $script:Assertions assertions. Fixture retained under tmp/."
# GitHub's PowerShell runner propagates the last native exit code, including
# the deliberately failing malformed-input test. The suite itself succeeded.
exit 0
