# NipaPlay installer helper: inbound firewall rules for NipaPlay.exe.
#
# When NipaPlay listens on a non-loopback port for the first time Windows shows a firewall prompt; if it is
# dismissed or cancelled, the system creates an inbound Block rule for the program. Such a rule makes the
# device network (TLS port, mDNS UDP 5353) unreachable. The installers therefore add their own Allow rule and
# delete the Block rule.
#
#   -Action Install     delete the "NipaPlay" rules of this path, add TCP and UDP Allow rules for the Domain
#                       and Private profiles (never Public), then do CleanBlock
#   -Action Remove      delete the "NipaPlay" rules of this path
#   -Action CleanBlock  delete the inbound Block rules whose program path equals -Path (default)
#
# Only rules named NipaPlay for exactly this program path, and inbound Block rules for exactly this program
# path, are touched. Nothing else is. Needs an elevated session. Exit code 0 on success, 1 on failure.
# -LogFile appends what was done (the installer reads it back into its own log).
param(
    [ValidateSet('Install', 'Remove', 'CleanBlock')][string]$Action = 'CleanBlock',
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$LogFile = ''
)

$ErrorActionPreference = 'Stop'
$ruleName = 'NipaPlay'
$netsh = Join-Path $env:SystemRoot 'System32\netsh.exe'

function Say([string]$text) {
    Write-Output $text
    if ($LogFile) { Add-Content -LiteralPath $LogFile -Value $text -Encoding UTF8 }
}

function Invoke-Netsh([string[]]$arguments, [bool]$tolerateNoMatch) {
    $out = & $netsh @arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    Say ("netsh {0} -> {1}" -f ($arguments -join ' '), $code)
    # delete rule returns 1 when there is nothing to delete
    if ($code -ne 0 -and -not ($tolerateNoMatch -and $code -eq 1)) {
        throw ("netsh failed with {0}: {1}" -f $code, $out.Trim())
    }
}

function Remove-OwnRules {
    Invoke-Netsh @('advfirewall', 'firewall', 'delete', 'rule', "name=$ruleName", "program=$Path") $true
}

function Remove-BlockRules {
    $target = [Environment]::ExpandEnvironmentVariables($Path)
    $removed = 0
    $rules = Get-NetFirewallRule -Direction Inbound -Action Block -ErrorAction SilentlyContinue
    foreach ($rule in $rules) {
        $filter = $rule | Get-NetFirewallApplicationFilter
        $program = [Environment]::ExpandEnvironmentVariables([string]$filter.Program)
        if ($program -ieq $target) {
            Say ("removing Block rule: {0} ({1})" -f $rule.DisplayName, $rule.Name)
            $rule | Remove-NetFirewallRule
            $removed++
        }
    }
    Say ("removed {0} inbound Block rule(s) for {1}" -f $removed, $target)
}

try {
    switch ($Action) {
        'Install' {
            Remove-OwnRules
            foreach ($protocol in 'TCP', 'UDP') {
                Invoke-Netsh @('advfirewall', 'firewall', 'add', 'rule', "name=$ruleName", 'dir=in', 'action=allow',
                    "program=$Path", 'enable=yes', 'profile=domain,private', "protocol=$protocol") $false
            }
            Remove-BlockRules
        }
        'Remove' { Remove-OwnRules }
        'CleanBlock' { Remove-BlockRules }
    }
    exit 0
} catch {
    Say ("failed: {0}" -f $_.Exception.Message)
    exit 1
}
