<?php
header('Access-Control-Allow-Origin: *');
header('Content-Type: application/json');

// 配置
$logDir = 'logs/';  // 日志存储目录
$logLifetime = 3600; // 日志保存时间（1小时）

// 创建日志目录
if (!file_exists($logDir)) {
    mkdir($logDir, 0777, true);
}

// 清理过期日志
function cleanOldLogs($dir, $lifetime) {
    foreach (glob($dir . "*") as $file) {
        if (is_file($file) && (time() - filemtime($file) > $lifetime)) {
            unlink($file);
        }
    }
}

// 生成唯一ID
function generateUniqueId() {
    return bin2hex(random_bytes(8));
}

// 获取当前域名
function getCurrentDomain() {
    $protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? 'https://' : 'http://';
    return $protocol . $_SERVER['HTTP_HOST'];
}

// 处理请求
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // 接收日志数据
    $input = file_get_contents('php://input');
    $data = json_decode($input, true);
    
    if (isset($data['logs'])) {
        $logId = generateUniqueId();
        $logFile = $logDir . $logId . '.json';
        
        // 保存日志
        file_put_contents($logFile, json_encode([
            'timestamp' => time(),
            'logs' => $data['logs']
        ]));
        
        // 返回日志ID和实际的查看URL
        echo json_encode([
            'success' => true,
            'logId' => $logId,
            'viewUrl' => getCurrentDomain() . '/nipaplay.php?id=' . $logId
        ]);
    } else {
        echo json_encode([
            'success' => false,
            'error' => 'No log data provided'
        ]);
    }
} elseif ($_SERVER['REQUEST_METHOD'] === 'GET') {
    // 获取日志数据
    if (isset($_GET['id'])) {
        $logId = preg_replace('/[^a-zA-Z0-9]/', '', $_GET['id']); // 安全过滤
        $logFile = $logDir . $logId . '.json';
        
        if (file_exists($logFile)) {
            if (isset($_GET['raw'])) {
                // 返回JSON数据
                $logData = json_decode(file_get_contents($logFile), true);
                echo json_encode($logData);
            } else {
                // 显示HTML页面
                $logData = json_decode(file_get_contents($logFile), true);
                ?>
                <!DOCTYPE html>
                <html>
                <head>
                    <title>NipaPlay Log Viewer</title>
                    <meta name="viewport" content="width=device-width, initial-scale=1">
                    <style>
                        body {
                            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
                            line-height: 1.6;
                            margin: 0;
                            padding: 20px;
                            background: #1a1a1a;
                            color: #fff;
                        }
                        .log-entry {
                            padding: 8px;
                            border-bottom: 1px solid #333;
                            font-family: monospace;
                        }
                        .timestamp {
                            color: #888;
                            margin-right: 10px;
                        }
                        .level {
                            padding: 2px 6px;
                            border-radius: 3px;
                            margin-right: 10px;
                            font-size: 12px;
                        }
                        .level-DEBUG { background: #666; }
                        .level-INFO { background: #0066cc; }
                        .level-WARN { background: #cc8800; }
                        .level-ERROR { background: #cc0000; }
                        .tag {
                            background: rgba(255,255,255,0.2);
                            padding: 2px 6px;
                            border-radius: 3px;
                            margin-right: 10px;
                            font-size: 12px;
                        }
                        .message {
                            margin-left: 10px;
                        }
                        .header {
                            margin-bottom: 20px;
                            padding-bottom: 10px;
                            border-bottom: 2px solid #333;
                        }
                        .auto-refresh {
                            float: right;
                            color: #888;
                        }
                    </style>
                </head>
                <body>
                    <div class="header">
                        <h1>NipaPlay Log Viewer</h1>
                        <div class="auto-refresh">
                            <label>
                                <input type="checkbox" id="autoRefresh"> Auto refresh
                            </label>
                        </div>
                    </div>
                    <div id="logContent">
                    <?php foreach ($logData['logs'] as $log): ?>
                        <div class="log-entry">
                            <span class="timestamp"><?= date('H:i:s', strtotime($log['timestamp'])) ?></span>
                            <span class="level level-<?= $log['level'] ?>"><?= $log['level'] ?></span>
                            <span class="tag"><?= htmlspecialchars($log['tag']) ?></span>
                            <span class="message"><?= htmlspecialchars($log['message']) ?></span>
                        </div>
                    <?php endforeach; ?>
                    </div>
                    <script>
                        let autoRefreshInterval;
                        const autoRefreshCheckbox = document.getElementById('autoRefresh');
                        
                        function refreshLogs() {
                            fetch(window.location.href + '&raw=1')
                                .then(response => response.json())
                                .then(data => {
                                    const logContent = document.getElementById('logContent');
                                    logContent.innerHTML = data.logs.map(log => `
                                        <div class="log-entry">
                                            <span class="timestamp">${new Date(log.timestamp).toTimeString().split(' ')[0]}</span>
                                            <span class="level level-${log.level}">${log.level}</span>
                                            <span class="tag">${log.tag}</span>
                                            <span class="message">${log.message}</span>
                                        </div>
                                    `).join('');
                                });
                        }
                        
                        autoRefreshCheckbox.addEventListener('change', function() {
                            if (this.checked) {
                                autoRefreshInterval = setInterval(refreshLogs, 5000);
                            } else {
                                clearInterval(autoRefreshInterval);
                            }
                        });
                    </script>
                </body>
                </html>
                <?php
            }
        } else {
            echo json_encode([
                'success' => false,
                'error' => 'Log not found'
            ]);
        }
    } else {
        echo json_encode([
            'success' => false,
            'error' => 'No log ID provided'
        ]);
    }
}

// 清理过期日志
cleanOldLogs($logDir, $logLifetime);
?> 