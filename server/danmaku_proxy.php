<?php
/**
 * danmaku_proxy.php
 *
 * 部署在 https://nipaplay.aimes-soft.com 上，用于代理调用 https://api.dandanplay.net 的弹幕接口。
 * 客户端会把最终需要请求的路径（含查询字符串）通过 path 参数传入，本脚本会附带全部验证头转发请求并返回原始响应。
 */

declare(strict_types=1);

define('TARGET_BASE_URL', 'https://api.dandanplay.net');
define('ALLOWED_PATH_PREFIX', '/api/v2/comment/');

function respond_json_error(int $statusCode, string $message, array $extra = []): void
{
    http_response_code($statusCode);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(array_merge(['success' => false, 'message' => $message], $extra), JSON_UNESCAPED_UNICODE);
    exit;
}

function get_request_headers(): array
{
    if (function_exists('getallheaders')) {
        $headers = getallheaders();
        if ($headers !== false) {
            return $headers;
        }
    }

    $headers = [];
    foreach ($_SERVER as $name => $value) {
        if (strpos($name, 'HTTP_') !== 0) {
            continue;
        }
        $headerName = str_replace(' ', '-', ucwords(strtolower(str_replace('_', ' ', substr($name, 5)))));
        $headers[$headerName] = $value;
    }

    return $headers;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    respond_json_error(405, '仅支持 GET 请求');
}

$targetPath = $_GET['path'] ?? '';
if (!is_string($targetPath) || $targetPath === '') {
    respond_json_error(400, '缺少 path 参数');
}

$questionPos = strpos($targetPath, '?');
$pathForValidation = $questionPos === false ? $targetPath : substr($targetPath, 0, $questionPos);
if (strpos($pathForValidation, ALLOWED_PATH_PREFIX) !== 0) {
    respond_json_error(400, '仅允许代理 /api/v2/comment/ 开头的弹幕接口');
}

$targetUrl = TARGET_BASE_URL . $targetPath;

$incomingHeaders = get_request_headers();
$normalizedHeaders = [];
foreach ($incomingHeaders as $name => $value) {
    $normalizedHeaders[strtolower((string) $name)] = $value;
}

$headerMap = [
    'accept' => 'Accept',
    'user-agent' => 'User-Agent',
    'x-appid' => 'X-AppId',
    'x-signature' => 'X-Signature',
    'x-timestamp' => 'X-Timestamp',
    'authorization' => 'Authorization',
];

$forwardHeaders = [];
foreach ($headerMap as $key => $originalName) {
    if (isset($normalizedHeaders[$key])) {
        $forwardHeaders[] = $originalName . ': ' . $normalizedHeaders[$key];
    }
}

$curl = curl_init($targetUrl);
curl_setopt_array($curl, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HEADER => true,
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_TIMEOUT => 12,
    CURLOPT_CONNECTTIMEOUT => 5,
    CURLOPT_HTTPHEADER => $forwardHeaders,
    CURLOPT_SSL_VERIFYPEER => true,
    CURLOPT_SSL_VERIFYHOST => 2,
    CURLOPT_ENCODING => '',
]);

$response = curl_exec($curl);
if ($response === false) {
    $errorMessage = curl_error($curl);
    curl_close($curl);
    respond_json_error(502, '代理服务器无法连接到弹弹play接口', ['detail' => $errorMessage]);
}

$headerSize = (int) curl_getinfo($curl, CURLINFO_HEADER_SIZE);
$statusCode = (int) curl_getinfo($curl, CURLINFO_HTTP_CODE);
curl_close($curl);

$responseHeaders = substr($response, 0, $headerSize);
$responseBody = substr($response, $headerSize);

http_response_code($statusCode);

$headersToForward = ['Content-Type', 'X-Error-Message'];
$headerLines = preg_split("/\r?\n/", trim((string) $responseHeaders));
if ($headerLines !== false) {
    foreach ($headerLines as $line) {
        if ($line === '' || stripos($line, 'HTTP/') === 0) {
            continue;
        }
        if (strpos($line, ':') === false) {
            continue;
        }
        [$name, $value] = array_map('trim', explode(':', $line, 2));
        if (in_array($name, $headersToForward, true)) {
            header($name . ': ' . $value);
        }
    }
}

if ($statusCode >= 200 && $statusCode < 300) {
    echo $responseBody;
    exit;
}

if ($responseBody === '') {
    echo json_encode([
        'success' => false,
        'message' => '弹弹play接口返回了空响应',
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

echo $responseBody;
