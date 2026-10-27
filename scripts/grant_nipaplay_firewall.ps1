<#
.SYNOPSIS
  以管理员身份为 NipaPlay 创建防火墙入站放行规则（UDP 32123 局域网发现 + TCP 1180 远程访问）。

.DESCRIPTION
  NipaPlay 以 zip 分发、无安装器，Windows 首次绑定端口时的"允许访问"弹窗一旦被取消，
  入站 UDP/TCP 将被默认拦截，表现为其他设备"扫描局域网"搜不到主机。
  本脚本创建按程序路径限定的放行规则，可重复执行（幂等）。

.EXAMPLE
  # 管理员 PowerShell 中执行；-ExePath 缺省时按常见位置自动探测
  powershell -ExecutionPolicy Bypass -File scripts\grant_nipaplay_firewall.ps1 -ExePath "D:\Tools\NipaPlay\NipaPlay.exe"
#>
[CmdletBinding()]
param(
  [string]$ExePath,
  [int]$HttpPort = 1180,
  [int]$DiscoveryPort = 32123
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Error '需要管理员权限。请右键 PowerShell"以管理员身份运行"后重试。'
  exit 1
}

if (-not $ExePath) {
  $candidates = @(
    (Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release\NipaPlay.exe'),
    (Join-Path $PSScriptRoot '..\build\windows\x64\runner\Debug\NipaPlay.exe'),
    "$env:LOCALAPPDATA\Programs\NipaPlay\NipaPlay.exe"
  )
  $ExePath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $ExePath) {
    # 不限定程序路径，退而求其次按端口放行（作用域=LocalSubnet，降低暴露面）
    Write-Warning '未找到 NipaPlay.exe，退化为按端口+本地子网放行。'
  }
}
$resolved = Resolve-Path $ExePath -ErrorAction SilentlyContinue
if ($resolved) { $ExePath = $resolved.Path }

$rules = @(
  @{ Name = 'NipaPlay LAN Discovery (UDP-In)'; Proto = 'UDP'; Port = $DiscoveryPort },
  @{ Name = 'NipaPlay Remote Access (TCP-In)'; Proto = 'TCP'; Port = $HttpPort }
)

foreach ($r in $rules) {
  netsh advfirewall firewall delete rule name="$($r.Name)" | Out-Null
  if ($ExePath -and (Test-Path $ExePath)) {
    netsh advfirewall firewall add rule name="$($r.Name)" `
      dir=in action=allow program="$ExePath" protocol=$($r.Proto) localport=$($r.Port) profile=any | Out-Null
  } else {
    netsh advfirewall firewall add rule name="$($r.Name)" `
      dir=in action=allow protocol=$($r.Proto) localport=$($r.Port) profile=any remoteip=localsubnet | Out-Null
  }
  Write-Host "已创建规则：$($r.Name) [$($r.Proto) $($r.Port)]" -ForegroundColor Green
}

Write-Host "`n当前规则核对："
netsh advfirewall firewall show rule name=all | Select-String -Pattern 'NipaPlay' -Context 0,8
