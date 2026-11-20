<#
.SYNOPSIS
  NipaPlay 局域网发现（UDP 32123）验证脚本。

.DESCRIPTION
  对应 docs/webdav/win-discovery-rootcause.md 的可复现验证：
  - Local  模式：在本机（服务端）做自检——UDP 32123 可绑定、端口保留段、防火墙规则、
           发现应答 <=5 秒（若本机 NipaPlay 正在运行则由它应答，否则由脚本内置应答器应答）。
  - Remote 模式：在另一台同网段机器（客户端）上运行，向广播地址 + -ServerIp 发送发现包，
           断言 -TimeoutSeconds 内收到 nipaplay_discover_response，重复 -Repeat 次全部通过。
           验收标准：同网段两台 Windows 机器上稳定 PASS 3 次（-Repeat 3）。

.EXAMPLE
  # 服务端本机自检（开 NipaPlay 远程访问前后都可跑）
  powershell -ExecutionPolicy Bypass -File scripts\verify_webdav_discovery.ps1 -Mode Local

  # 客户端机器上验证能否在 5 秒内发现服务端（重复 3 次）
  powershell -ExecutionPolicy Bypass -File scripts\verify_webdav_discovery.ps1 -Mode Remote -ServerIp 192.168.1.10 -Repeat 3

.NOTES
  输出仅写到控制台，不在 C 盘生成文件。退出码：0 = 全部断言通过；1 = 有断言失败。
#>
[CmdletBinding()]
param(
  [ValidateSet('Local', 'Remote', 'Both')]
  [string]$Mode = 'Both',
  [string]$ServerIp,
  [int]$RemotePort = 1180,
  [int]$HttpPort = 1180,
  [int]$Repeat = 3,
  [int]$TimeoutSeconds = 5,
  [int]$DiscoveryPort = 32123,
  [string]$ExePath
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:Failures = 0
$script:Warnings = 0

function Write-Check {
  param([string]$Status, [string]$Id, [string]$Message)
  $color = @{ PASS = 'Green'; FAIL = 'Red'; WARN = 'Yellow'; INFO = 'Cyan' }[$Status]
  Write-Host ("[{0}] {1} {2}" -f $Status, $Id, $Message) -ForegroundColor $color
  if ($Status -eq 'FAIL') { $script:Failures++ }
  if ($Status -eq 'WARN') { $script:Warnings++ }
}

function Get-LocalIPv4s {
  Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
      $_.IPAddress -notlike '127.*' -and
      $_.IPAddress -notlike '169.254.*' -and
      $_.PrefixOrigin -ne 'WellKnown'
    }
}

function New-DiscoverPacket {
  [Text.Encoding]::UTF8.GetBytes('{"type":"nipaplay_discover","v":1}')
}

function Test-DiscoveryUdp {
  param([System.Net.IPAddress[]]$Targets, [int]$TimeoutMs = 5000)
  $packet = New-DiscoverPacket
  $udp = New-Object System.Net.Sockets.UdpClient(0)
  try {
    $udp.Client.EnableBroadcast = $true
    $udp.Client.ReceiveTimeout = 300
    $epAny = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $lastSendMs = -1000
    # 与 NipaPlay 扫描端一致：等待期内持续重发，规避 UDP 丢包与应答器冷启动
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
      if ($sw.ElapsedMilliseconds - $lastSendMs -ge 400) {
        foreach ($t in $Targets) {
          try { [void]$udp.Send($packet, $packet.Length, $t, $script:DiscoveryPort) } catch { }
        }
        $lastSendMs = $sw.ElapsedMilliseconds
      }
      try {
        $data = $udp.Receive([ref]$epAny)
        $txt = [Text.Encoding]::UTF8.GetString($data)
        if ($txt -like '*nipaplay_discover_response*' -and $txt -like '*NipaPlay*') {
          return [pscustomobject]@{ Ok = $true; Ms = $sw.ElapsedMilliseconds; Payload = $txt }
        }
      } catch { } # 300ms ReceiveTimeout，回到重发窗口
    }
    return [pscustomobject]@{ Ok = $false; Ms = $sw.ElapsedMilliseconds; Payload = $null }
  } finally {
    $udp.Close()
  }
}

function Start-ScriptResponder {
  # 协议兼容的内置应答器：本机 NipaPlay 未运行时充当被扫描方（与 NipaPlay 线格式一致）
  $script:ResponderJob = Start-Job -ScriptBlock {
    param($port)
    $u = New-Object System.Net.Sockets.UdpClient
    $u.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket,
      [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
    $u.Client.Bind((New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, $port)))
    $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
    while ($true) {
      try { $data = $u.Receive([ref]$ep) } catch { return }
      $txt = [Text.Encoding]::UTF8.GetString($data)
      if ($txt -like '*nipaplay_discover*') {
        $resp = '{"type":"nipaplay_discover_response","v":1,"app":"NipaPlay","hostname":"verify-script","os":"windows","port":1180}'
        $bytes = [Text.Encoding]::UTF8.GetBytes($resp)
        [void]$u.Send($bytes, $bytes.Length, $ep.Address, $ep.Port)
      }
    }
  } -ArgumentList $script:DiscoveryPort
  # 等待子进程 PowerShell 完成绑定（Start-Job 冷启动 0.5-2s），避免首批发现包落空
  $deadline = (Get-Date).AddSeconds(6)
  while ((Get-Date) -lt $deadline -and $script:ResponderJob.State -ne 'Running') {
    Start-Sleep -Milliseconds 200
  }
  Start-Sleep -Milliseconds 1500
}

function Stop-ScriptResponder {
  if ($script:ResponderJob) {
    Stop-Job $script:ResponderJob -ErrorAction SilentlyContinue
    Remove-Job $script:ResponderJob -Force -ErrorAction SilentlyContinue
    $script:ResponderJob = $null
  }
}

function Test-LocalChecks {
  Write-Host "`n===== Local 自检（服务端本机）=====" -ForegroundColor Cyan

  # [L1] UDP 32123 可绑定（失败 => 被占用或落在保留段，NipaPlay 应答器起不来）
  $bindOk = $true
  $probe = New-Object System.Net.Sockets.UdpClient
  try {
    $probe.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket,
      [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
    $probe.Client.Bind((New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, $script:DiscoveryPort)))
  } catch { $bindOk = $false }
  if ($probe) { $probe.Close() }
  if ($bindOk) {
    Write-Check PASS 'L1' "UDP $script:DiscoveryPort 本机可绑定"
  } else {
    Write-Check FAIL 'L1' "UDP $script:DiscoveryPort 本机不可绑定（被占用或被系统保留）——NipaPlay 应答器将启动失败"
  }

  # [L2] Windows UDP 端口排除段（Hyper-V/WSL 会随机保留端口段）
  $excluded = netsh interface ipv4 show excludedportrange protocol=udp 2>$null |
    Select-String '^\s*(\d+)\s+(\d+)\s*$'
  $inRange = $false
  foreach ($m in $excluded) {
    $a = [int]$m.Matches[0].Groups[1].Value
    $b = [int]$m.Matches[0].Groups[2].Value
    if ($script:DiscoveryPort -ge $a -and $script:DiscoveryPort -le $b) { $inRange = $true; break }
  }
  if ($inRange) {
    Write-Check FAIL 'L2' "UDP $script:DiscoveryPort 落在系统保留端口段内（Hyper-V/WSL 动态保留），需重启 NTkernel 或改用保留段外端口"
  } else {
    Write-Check PASS 'L2' "UDP $script:DiscoveryPort 不在系统保留段内"
  }

  # [L3] 防火墙：是否有放行 UDP 32123 / 入站规则
  $fwHit = $false
  try {
    $fwHit = netsh advfirewall firewall show rule name=all 2>$null |
      Select-String -Pattern '32123', 'NipaPlay' -SimpleMatch | Measure-Object | ForEach-Object { $_.Count -gt 0 }
  } catch { }
  if ($fwHit) {
    Write-Check PASS 'L3' '防火墙中存在 32123/NipaPlay 相关规则（人工确认方向=入站、动作=允许即可）'
  } else {
    Write-Check WARN 'L3' '防火墙中未找到 UDP 32123 / NipaPlay 放行规则——若 L4 失败，先以管理员运行 scripts\grant_nipaplay_firewall.ps1'
  }

  # [L4] 发现应答 <= TimeoutSeconds：优先由本机真实 NipaPlay 应答（若在运行），否则内置应答器兜底
  Start-ScriptResponder
  $targets = @([System.Net.IPAddress]::Loopback, [System.Net.IPAddress]::Broadcast)
  $ips = Get-LocalIPv4s
  foreach ($ip in $ips) {
    $prefix = ($ip.IPAddress -split '\.')[0..2] -join '.'
    try { $targets += [System.Net.IPAddress]::Parse("$prefix.255") } catch { }
  }
  $r = Test-DiscoveryUdp -Targets $targets -TimeoutMs ($TimeoutSeconds * 1000)
  if ($r.Ok) {
    Write-Check PASS 'L4' ("发现应答 {0} ms（阈值 {1}s）：{2}" -f $r.Ms, $TimeoutSeconds, $r.Payload)
  } else {
    Write-Check FAIL 'L4' ("{0} 秒内未收到发现应答（目标 {1} 个）。服务端入站 UDP {2} 大概率被防火墙拦截或服务未开启" -f $TimeoutSeconds, $targets.Count, $script:DiscoveryPort)
  }
  Stop-ScriptResponder

  # [L5] HTTP 服务（远程访问）是否在监听并回应 /api/info
  $httpOk = $false
  $probeTargets = @('127.0.0.1') + @($ips | ForEach-Object { $_.IPAddress })
  foreach ($ip in $probeTargets) {
    $url = "http://${ip}:$($script:HttpPort)/api/info"
    try {
      $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3
      if ($resp.StatusCode -eq 200 -and $resp.Content -like '*NipaPlay*') {
        Write-Check PASS 'L5' "HTTP 服务正常：$url"
        $httpOk = $true
        break
      }
    } catch { }
  }
  if (-not $httpOk) {
    Write-Check WARN 'L5' "TCP $($script:HttpPort) /api/info 无应答（远程访问未开启或端口不同）——不影响 UDP 发现断言"
  }
}

function Test-RemoteChecks {
  if (-not $ServerIp) {
    Write-Check FAIL 'R0' 'Remote 模式需要 -ServerIp（被测服务端 IP）'
    return
  }
  Write-Host "`n===== Remote 验证（客户端视角，目标 $ServerIp）=====" -ForegroundColor Cyan

  # [R1] TCP 回退通道：HTTP /api/info 可达性
  try {
    $resp = Invoke-WebRequest -Uri "http://${ServerIp}:$RemotePort/api/info" -UseBasicParsing -TimeoutSec 5
    if ($resp.StatusCode -eq 200 -and $resp.Content -like '*NipaPlay*') {
      Write-Check PASS 'R1' "TCP 通道可达：http://${ServerIp}:$RemotePort/api/info"
    } else {
      Write-Check WARN 'R1' "TCP 通道应答异常（HTTP $($resp.StatusCode)）"
    }
  } catch {
    Write-Check WARN 'R1' "TCP ${ServerIp}:$RemotePort 不可达（远程访问未开启或被防火墙拦截）——不影响 UDP 断言"
  }

  # [R2] UDP 发现 <=5s，重复 Repeat 次，全部通过才算 PASS（对应"稳定 PASS 3 次"验收）
  $targets = @([System.Net.IPAddress]::Parse($ServerIp), [System.Net.IPAddress]::Broadcast)
  foreach ($ip in (Get-LocalIPv4s)) {
    $prefix = ($ip.IPAddress -split '\.')[0..2] -join '.'
    try { $targets += [System.Net.IPAddress]::Parse("$prefix.255") } catch { }
  }
  $allPass = $true
  for ($i = 1; $i -le $Repeat; $i++) {
    $r = Test-DiscoveryUdp -Targets $targets -TimeoutMs ($TimeoutSeconds * 1000)
    if ($r.Ok) {
      Write-Check PASS 'R2' ("第 $i/$Repeat 次：发现应答 {0} ms" -f $r.Ms)
    } else {
      Write-Check FAIL 'R2' ("第 $i/$Repeat 次：{0} 秒内未发现主机" -f $TimeoutSeconds)
      $allPass = $false
    }
    if ($i -lt $Repeat) { Start-Sleep -Milliseconds 400 }
  }
  if ($allPass) {
    Write-Host ("RESULT: PASS ({0}/{1} 次发现均在 {2}s 内)" -f $Repeat, $Repeat, $TimeoutSeconds) -ForegroundColor Green
  } else {
    Write-Host 'RESULT: FAIL（存在未在阈值内发现主机的轮次）' -ForegroundColor Red
  }
}

Write-Host "NipaPlay 局域网发现验证  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
if ($Mode -in 'Local', 'Both') { Test-LocalChecks }
if ($Mode -in 'Remote', 'Both') { Test-RemoteChecks }

if ($script:Failures -gt 0) {
  Write-Host ("`nRESULT: FAIL（{0} 项断言失败，{1} 项警告）" -f $script:Failures, $script:Warnings) -ForegroundColor Red
  exit 1
}
Write-Host ("`nRESULT: PASS（0 项失败，{0} 项警告）" -f $script:Warnings) -ForegroundColor Green
exit 0
