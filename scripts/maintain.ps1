[CmdletBinding()]
param(
    [ValidateSet('Check', 'Sync', 'Review', 'Hook')][string]$Action = 'Check',
    [string]$SessionId,
    [string]$TurnId,
    [string]$Note
)
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
. (Join-Path $PSScriptRoot 'maintenance-core.ps1')
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
try {
    $actualRoot = Git-Read $root @('rev-parse', '--show-toplevel')
    if ([IO.Path]::GetFullPath($actualRoot) -ne $root) { throw 'Script must belong to the Git repository root.' }
    switch ($Action) {
        'Check' { Check-Project $root; Write-Output 'Project checks passed.' }
        'Sync' { With-WriteLock $root { Sync-Project $root }; Write-Output 'Navigation synchronized.' }
        'Review' { With-WriteLock $root { Review-Project $root $SessionId $TurnId $Note }; Write-Output 'Review recorded for current snapshot.' }
        'Hook' {
            $event = ConvertTo-Map (ConvertFrom-Json ([Console]::In.ReadToEnd().TrimStart([char]0xfeff)))
            # No lock/state directory creation in plan mode.
            $result = if ($event.permission_mode -eq 'plan') {
                Handle-Hook $root $event
            } else { With-WriteLock $root { Handle-Hook $root $event } }
            Write-Output (Json $result)
        }
    }
} catch {
    if ($Action -eq 'Hook') {
        Write-Output (Json @{ systemMessage = "PaperRebuild maintenance failed; report unresolved state: $($_.Exception.Message)" })
    } else { [Console]::Error.WriteLine($_.Exception.Message) }
    exit 1
}
