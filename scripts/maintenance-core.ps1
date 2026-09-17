# Library for maintenance. Dot-source only; no implicit writes or Git mutations.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Utf8 = [Text.UTF8Encoding]::new($false)

function ConvertTo-Map($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [Collections.IDictionary]) { return ,$Value }
    if ($Value -is [pscustomobject]) {
        $map = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $map[$property.Name] = ConvertTo-Map $property.Value
        }
        return ,$map
    }
    if ($Value -is [array]) {
        $items = @($Value | ForEach-Object { ConvertTo-Map $_ })
        return ,$items
    }
    return $Value
}

function Read-Json([string]$Path) {
    return ConvertTo-Map (ConvertFrom-Json ([IO.File]::ReadAllText($Path).TrimStart([char]0xfeff)))
}

function Json($Value) { return ConvertTo-Json -InputObject $Value -Depth 64 -Compress }

function Text-Hash([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($script:Utf8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function File-Hash([string]$Path) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Safe-Path([string]$Root, [string]$Relative) {
    if (!$Relative -or $Relative -match '[:\\\x00-\x1f]' -or $Relative.StartsWith('/') -or
        @($Relative.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
        throw "Unsafe repository-relative path: $Relative"
    }
    $full = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    $base = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if (!$full.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escaped repository: $Relative"
    }
    $cursor = $full
    while ($cursor.Length -ge $base.Length) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -Force -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Linked path is not supported for maintenance: $Relative"
            }
        }
        $cursor = Split-Path -Parent $cursor
        if (!$cursor) { break }
    }
    return $full
}

function Git-Read([string]$Root, [string[]]$Arguments) {
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $value = @(& git -C $Root -c core.quotepath=false @Arguments 2>&1)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    if ($code -ne 0) { throw "Git read failed: $($value -join ' ')" }
    return ($value -join "`n")
}

function Candidate-Paths([string]$Root) {
    $raw = Git-Read $Root @('ls-files', '-z', '--cached', '--others', '--exclude-standard')
    # .NET Framework needs char[] here; a scalar char binds the params overload
    # and leaves the trailing empty path on Windows PowerShell 5.1.
    [string[]]$paths = @($raw.Split([char[]]@([char]0), [StringSplitOptions]::RemoveEmptyEntries) | Select-Object -Unique)
    [Array]::Sort([Array]$paths, [Collections.IComparer][StringComparer]::Ordinal)
    foreach ($path in $paths) {
        $absolute = Safe-Path $Root $path
        if (Test-Path -LiteralPath $absolute -PathType Leaf) { $path }
    }
}

function Snapshot([string]$Root) {
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add((Git-Read $Root @('rev-parse', 'HEAD')))
    foreach ($path in @(Candidate-Paths $Root)) {
        $absolute = Safe-Path $Root $path
        if ((Get-Item -Force -LiteralPath $absolute).Length -gt 5MB) { throw "File exceeds 5 MiB public-source limit: $path" }
        $lines.Add($path + '=' + (File-Hash $absolute))
    }
    return Text-Hash ($lines -join "`n")
}

function Write-Atomic([string]$Root, [string]$Relative, [string]$Content, [string]$Expected) {
    $path = Safe-Path $Root $Relative
    if ((File-Hash $path) -ne $Expected) { throw "Concurrent modification; reread before retrying: $Relative" }
    if ((Test-Path -LiteralPath $path) -and [IO.File]::ReadAllText($path) -ceq $Content) { return }
    $parent = Split-Path $path -Parent
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temp = $path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temp, $Content, $script:Utf8)
        if ((File-Hash $path) -ne $Expected) { throw "Concurrent modification: $Relative" }
        if (Test-Path -LiteralPath $path) { [IO.File]::Replace($temp, $path, [NullString]::Value) }
        else { [IO.File]::Move($temp, $path) }
    }
    finally { if (Test-Path -LiteralPath $temp) { [IO.File]::Delete($temp) } }
}

function With-WriteLock([string]$Root, [scriptblock]$Operation) {
    $path = Safe-Path $Root '.codex/.local/maintenance/write.lock'
    [IO.Directory]::CreateDirectory((Split-Path $path -Parent)) | Out-Null
    # An exclusive handle coordinates our sessions. UI edits are checked separately by hash.
    $stream = [IO.File]::Open($path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { & $Operation } finally { $stream.Dispose() }
}

function Validate-Groups([string]$Root, $Document, [bool]$RequireExisting) {
    if ($Document.version -ne 2 -or $null -eq $Document.groups) { throw 'Expected CodeGroup version 2 and groups array.' }
    $ids = @{}
    $sources = Read-Json (Safe-Path $Root 'docs/reading/sources.json')
    $optional = @($sources.files | Where-Object { $_.local_only } | ForEach-Object { $_.path })
    foreach ($group in $Document.groups) {
        if (!$group.id -or $ids.ContainsKey($group.id)) { throw 'Missing or duplicate CodeGroup ID.' }
        $ids[$group.id] = $group
        $seen = @{}
        foreach ($file in @($group.files)) {
            $absolute = Safe-Path $Root $file.path
            if ($seen.ContainsKey($file.path)) { throw "Duplicate file entry: $($file.path)" }
            $seen[$file.path] = $true
            if ($RequireExisting -and !(Test-Path -LiteralPath $absolute) -and $file.path -notin $optional) {
                throw "Missing CodeGroup path: $($file.path)"
            }
            if (Test-Path -LiteralPath $absolute) {
                $actualDirectory = Test-Path -LiteralPath $absolute -PathType Container
                if ($actualDirectory -ne [bool]$file.isDirectory) { throw "CodeGroup path type mismatch: $($file.path)" }
            }
        }
    }
    foreach ($group in $Document.groups) {
        $visited = @{}
        $id = $group.id
        while ($id) {
            if ($visited.ContainsKey($id)) { throw 'CodeGroup parent cycle.' }
            if (!$ids.ContainsKey($id)) { throw "Unknown CodeGroup parent: $id" }
            $visited[$id] = $true
            $id = $ids[$id]['parentId']
        }
    }
}

function Desired-Groups([string]$Root, $Document) {
    $policy = Read-Json (Safe-Path $Root '.codex/maintenance-policy.json')
    $paths = @(Candidate-Paths $Root)
    $groups = [Collections.Generic.List[object]]::new()
    foreach ($group in $Document.groups) { $groups.Add($group) }
    foreach ($definition in $policy.groups) {
        $existing = @($groups | Where-Object { $_.id -eq $definition.id })
        if ($existing.Count -gt 1) { throw 'Duplicate owned group ID.' }
        if ($existing.Count -eq 0) {
            $group = [ordered]@{ id = $definition.id; name = $definition.name; files = @(); order = $groups.Count; parentId = $null; createdBy = 'PaperRebuild'; collapsed = $true }
            $groups.Add($group)
        } else { $group = $existing[0] }
        $wanted = @($paths | Where-Object { $_ -cmatch $definition.pattern })
        $members = [Collections.Generic.List[object]]::new()
        # Keep aliases, ordering and unknown metadata for surviving members.
        foreach ($file in @($group.files)) { if ($file.path -cin $wanted) { $members.Add($file) } }
        foreach ($path in $wanted) {
            if (@($members | Where-Object { $_.path -ceq $path }).Count -eq 0) {
                $members.Add([ordered]@{ path = $path; name = ($path.Split('/')[-1]); isDirectory = $false })
            }
        }
        $group.files = @($members.ToArray())
    }
    $Document.groups = @($groups.ToArray())
    return ,$Document
}

function Inventory-Text([string]$Root) {
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('# 项目文件索引')
    $lines.Add('')
    $lines.Add('由 `scripts/maintain.ps1 -Action Sync` 生成；仅列入版本控制候选文件，不表示科研完成。')
    $lines.Add('')
    $assets = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in @(Candidate-Paths $Root)) {
        # 人类入口按批次汇总重复图源；CodeGroup仍维护每个真实文件。
        if ($path -match '^((?:docs/src/assets|results/summaries)/[^/]+/[^/]+)/') {
            [void]$assets.Add($Matches[1])
            continue
        }
        if ($path -ne 'docs/src/generated-inventory.md') { $lines.Add('- `' + $path + '`') }
    }
    if ($assets.Count -gt 0) {
        $lines.Add('')
        $lines.Add('## 图表与结果批次')
        $lines.Add('')
        $lines.Add('批次内图源和逐式残差见对应结果页、哈希清单及 CodeGroup 文件分组；此处只列目录，避免重复展开全部图源。')
        $lines.Add('')
        foreach ($directory in $assets) { $lines.Add('- `' + $directory + '/`') }
    }
    return ($lines -join "`n") + "`n"
}

function Sync-Project([string]$Root) {
    $relative = '.vscode/file-groups.json'
    $path = Safe-Path $Root $relative
    $hash = File-Hash $path
    $document = if ($hash) { Read-Json $path } else { [ordered]@{ version = 2; groups = @() } }
    Validate-Groups $Root $document $false
    $before = Json $document
    $desired = Desired-Groups $Root $document
    Validate-Groups $Root $desired $true
    if ((Json $desired) -cne $before -or !$hash) {
        Write-Atomic $Root $relative (((ConvertTo-Json -InputObject $desired -Depth 64) -replace "`r`n", "`n") + "`n") $hash
    }
    $index = 'docs/src/generated-inventory.md'
    Write-Atomic $Root $index (Inventory-Text $Root) (File-Hash (Safe-Path $Root $index))
}

function Check-Project([string]$Root) {
    $required = @('README.md', 'AGENTS.md', 'CONTRIBUTING.md', 'LICENSE', 'NOTICE.md', 'Project.toml', 'Manifest.toml',
        'docs/Project.toml', 'docs/Manifest.toml', 'tools/Project.toml', 'tools/Manifest.toml',
        'docs/agent/current-state.md', 'docs/agent/handbook.md', '.codex/hooks.json',
        '.vscode/settings.json', '.vscode/tasks.json', '.github/workflows/ci.yml')
    foreach ($relative in $required) {
        if (!(Test-Path -LiteralPath (Safe-Path $Root $relative) -PathType Leaf)) { throw "Required file missing: $relative" }
    }
    foreach ($relative in @('.vscode/settings.json', '.vscode/tasks.json', '.vscode/extensions.json', '.vscode/launch.json', '.codex/hooks.json', '.codex/maintenance-policy.json', 'docs/reading/sources.json')) {
        $null = Read-Json (Safe-Path $Root $relative)
    }
    $groupPath = Safe-Path $Root '.vscode/file-groups.json'
    $document = Read-Json $groupPath
    Validate-Groups $Root $document $true
    $before = Json $document
    if ((Json (Desired-Groups $Root $document)) -cne $before) { throw 'CodeGroup membership is stale. Run Sync.' }
    $index = Safe-Path $Root 'docs/src/generated-inventory.md'
    if ([IO.File]::ReadAllText($index) -cne (Inventory-Text $Root)) { throw 'Generated inventory is stale. Run Sync.' }
    $sources = Read-Json (Safe-Path $Root 'docs/reading/sources.json')
    $candidates = @(Candidate-Paths $Root)
    foreach ($source in $sources.files) {
        $null = Safe-Path $Root $source.path
        if ($source.sha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid source SHA-256.' }
        if ($source.local_only -and $source.path -in $candidates) { throw "Local-only source would be published: $($source.path)" }
    }
    foreach ($relative in $candidates) {
        $path = Safe-Path $Root $relative
        if ((Get-Item -Force -LiteralPath $path).Length -gt 5MB) { throw "File exceeds 5 MiB: $relative" }
        if ($relative -match '(^|/)(\.env($|\.)|[^/]+\.(pem|key|pfx)$)' -and $relative -notmatch '\.env.example$') {
            throw "Credential-like file in publication candidates: $relative"
        }
        if ($relative -match '^(docs/build/|\.codex/\.local/|\.julia/|\.venv/|tmp/)' -or
            ($relative -match '^(data/(raw|processed)|results/runs)/' -and $relative -notmatch '/README.md$')) {
            throw "Local output would be published: $relative"
        }
    }
}

function State-Relative([string]$SessionId) {
    if (!$SessionId) { throw 'session_id is required.' }
    return '.codex/.local/maintenance/' + (Text-Hash $SessionId) + '.json'
}

function Save-State([string]$Root, [string]$Relative, $State, [string]$Expected) {
    Write-Atomic $Root $Relative ((Json $State) + "`n") $Expected
}

function Handle-Hook([string]$Root, $Event) {
    $name = [string]$Event.hook_event_name
    if ($Event.permission_mode -eq 'plan') { return @{ systemMessage = 'PaperRebuild maintenance is read-only in plan mode.' } }
    if ($name -eq 'SessionStart') {
        if (!$Event.session_id) { throw 'SessionStart requires session_id.' }
        $receipt = '.codex/.local/maintenance/startup-' + (Text-Hash $Event.session_id) + '.json'
        $record = @{ session_id = $Event.session_id; event = $name; source = $Event['source']; observed_utc = [DateTime]::UtcNow.ToString('o'); script_sha256 = (File-Hash (Safe-Path $Root 'scripts/maintenance-core.ps1')) }
        Save-State $Root $receipt $record (File-Hash (Safe-Path $Root $receipt))
        return @{ hookSpecificOutput = @{ hookEventName = $name; additionalContext = 'PaperRebuild: read AGENTS.md and docs/agent/current-state.md; follow docs/agent/handbook.md. Julia 1.12.6. Read current-state.md for implemented scope; distinguish synthetic method validation from thesis-scale reproduction.' } }
    }
    if ($name -notin @('UserPromptSubmit', 'Stop')) { throw "Unsupported event: $name" }
    if (!$Event.session_id -or !$Event.turn_id) { throw 'session_id and turn_id are required; no baseline fabricated.' }
    $relative = State-Relative $Event.session_id
    $path = Safe-Path $Root $relative
    $hash = File-Hash $path
    $state = if ($hash) { Read-Json $path } else { $null }
    if ($name -eq 'UserPromptSubmit') {
        if ($state -and $state.turn_id -eq $Event.turn_id) { return @{} }
        $state = [ordered]@{ session_id = $Event.session_id; turn_id = $Event.turn_id; baseline = (Snapshot $Root); requested = $false; review = $null; status = 'baseline'; last_event = $name; observed_utc = [DateTime]::UtcNow.ToString('o') }
        Save-State $Root $relative $state $hash
        return @{}
    }
    if (!$state -or $state.turn_id -ne $Event.turn_id) {
        return @{ systemMessage = 'PaperRebuild: missing/stale baseline; run Check and report manual review. Native lifecycle not verified for this turn.' }
    }
    $current = Snapshot $Root
    if ($current -eq $state.baseline) { $state.status = 'unchanged' }
    elseif ($state.review -and $state.review.snapshot -eq $current) { $state.status = 'reviewed' }
    else {
        Sync-Project $Root
        $state.status = 'needs-review'
        $reason = "PaperRebuild changed: update affected human docs and docs/agent/current-state.md; review handbook/rules if behavior changed. Run Sync, Check, then Review with -SessionId '$($Event.session_id)' -TurnId '$($Event.turn_id)' -Note describing actual review. Do not run research or commit from this hook."
        $repeat = $state.requested -or [bool]$Event.stop_hook_active
        $state.requested = $true
        $state.last_event = $name
        $state.observed_utc = [DateTime]::UtcNow.ToString('o')
        Save-State $Root $relative $state $hash
        if ($repeat) { return @{ systemMessage = "PaperRebuild maintenance unresolved after one continuation. $reason" } }
        return @{ decision = 'block'; reason = $reason }
    }
    $state.last_event = $name
    $state.observed_utc = [DateTime]::UtcNow.ToString('o')
    Save-State $Root $relative $state $hash
    return @{}
}

function Review-Project([string]$Root, [string]$SessionId, [string]$TurnId, [string]$Note) {
    if ([string]::IsNullOrWhiteSpace($Note) -or !$TurnId) { throw 'Review requires TurnId and a meaningful Note.' }
    Check-Project $Root
    $relative = State-Relative $SessionId
    $path = Safe-Path $Root $relative
    $hash = File-Hash $path
    if (!$hash) { throw 'No baseline exists for this session.' }
    $state = Read-Json $path
    if ($state.turn_id -ne $TurnId) { throw 'Review turn does not match current baseline.' }
    $state.review = @{ snapshot = (Snapshot $Root); note = $Note; reviewed_utc = [DateTime]::UtcNow.ToString('o') }
    Save-State $Root $relative $state $hash
}
