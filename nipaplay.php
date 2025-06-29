<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST');
header('Access-Control-Allow-Headers: Content-Type');

// 配置
$logDir = 'nipa_logs/';  // 日志存储目录
$logLifetime = 3600;     // 日志保存时间（1小时）

// 创建日志目录
if (!file_exists($logDir)) {
    mkdir($logDir, 0777, true);
}

// 清理过期日志
function cleanOldLogs($dir, $lifetime) {
    foreach (glob($dir . "*.json") as $file) {
        if (is_file($file) && (time() - filemtime($file) > $lifetime)) {
            unlink($file);
        }
    }
}

// 生成唯一ID
function generateUniqueId() {
    return substr(md5(uniqid(mt_rand(), true)), 0, 8);
}

// 处理请求
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    $input = file_get_contents('php://input');
    $data = json_decode($input, true);
    
    if (isset($data['logs']) && is_array($data['logs'])) {
        $logId = generateUniqueId();
        $logFile = $logDir . $logId . '.json';
        
        // 保存日志
        file_put_contents($logFile, json_encode([
            'timestamp' => time(),
            'logs' => $data['logs']
        ], JSON_UNESCAPED_UNICODE));
        
        // 返回查看URL
        $viewUrl = 'https://www.aimes-soft.com/nipaplay.php?id=' . $logId;
        echo json_encode([
            'success' => true,
            'logId' => $logId,
            'viewUrl' => $viewUrl
        ]);
    } else {
        echo json_encode([
            'success' => false,
            'error' => '无效的日志数据'
        ]);
    }
} elseif ($_SERVER['REQUEST_METHOD'] === 'GET') {
    if (isset($_GET['id'])) {
        $logId = preg_replace('/[^a-zA-Z0-9]/', '', $_GET['id']); // 安全过滤
        $logFile = $logDir . $logId . '.json';
        
        if (file_exists($logFile)) {
            if (isset($_GET['raw'])) {
                // 返回JSON数据
                header('Content-Type: application/json; charset=utf-8');
                echo file_get_contents($logFile);
            } else {
                // 显示HTML页面
                header('Content-Type: text/html; charset=utf-8');
                $logData = json_decode(file_get_contents($logFile), true);
                ?>
                <!DOCTYPE html>
                <html>
                <head>
                    <title>NipaPlay 日志查看器</title>
                    <meta name="viewport" content="width=device-width, initial-scale=1">
                    <meta charset="utf-8">
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
                            word-break: break-all;
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
                        @media (max-width: 600px) {
                            body { padding: 10px; }
                            .log-entry { font-size: 12px; }
                            .timestamp { display: block; }
                        }
                    </style>
                </head>
                <body>
                    <div class="header">
                        <h1>NipaPlay 日志查看器</h1>
                        <div class="auto-refresh">
                            <label>
                                <input type="checkbox" id="autoRefresh"> 自动刷新
                            </label>
                        </div>
                    </div>
                    <div id="logContent">
                    <?php foreach ($logData['logs'] as $log): ?>
                        <div class="log-entry">
                            <span class="timestamp"><?= date('H:i:s', strtotime($log['timestamp'])) ?></span>
                            <span class="level level-<?= htmlspecialchars($log['level']) ?>"><?= htmlspecialchars($log['level']) ?></span>
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
                'error' => '日志不存在'
            ]);
        }
    } else {
        echo json_encode([
            'success' => false,
            'error' => '未提供日志ID'
        ]);
    }
}

// 清理过期日志
cleanOldLogs($logDir, $logLifetime);
?> 