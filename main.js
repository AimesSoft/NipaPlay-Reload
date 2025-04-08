const { app, BrowserWindow, BrowserView, ipcMain, dialog, session, screen, nativeTheme, Menu, globalShortcut, isMac } = require('electron');
const { autoUpdater } = require('electron-updater');
const { execFile } = require('child_process');
const fs = require('fs');
const fs2 = require('fs').promises;
const path = require('path');
const crypto = require('crypto');
const os = require('os');
const SMB2 = require('smb2');
let smbClient = null; // SMB 客户端实例
const { processComments } = require('./danmaku_tran.js');
const downloadsPath = app.getPath('userData');
const nipaPath = path.join(downloadsPath, 'nipaplay');
const tokenFilePath = path.join(nipaPath, 'token.json');
const binaryFilePath = path.join(nipaPath, 'loginData.bin');
const video_commentPath = path.join(nipaPath, 'video_comment');
const danmakuPath = path.join(nipaPath, 'danmaku');
const subPath = path.join(nipaPath, 'sub');
const https = require('https');
const Store = require('electron-store');
const store = new Store();
const { v4: uuidv4 } = require('uuid');
const { JSDOM } = require('jsdom');
const { exec } = require('child_process');
const ffmpegmac = path.join(__dirname, 'ffmpeg', 'ffmpeg_mac');
const ffmpeglinux64 = path.join(__dirname, 'ffmpeg', 'ffmpeg_linux64');
const ffmpeglinuxarm = path.join(__dirname, 'ffmpeg', 'ffmpeg_linuxarm');
const ffmpegwin = path.join(__dirname, 'ffmpeg', 'ffmpeg_win', 'bin', 'ffmpeg.exe')
const logFilePath = path.join(downloadsPath, 'app.log');
const windowModePath = path.join(nipaPath, 'windowMode.json');
// 获取应用的用户数据目录
const userDataPath = app.getPath('userData');
const userName = '';
const password = '';
let loginUserName;
let loginPassword;
const appId = "nipaplayv1";
let token = null;
log(`User Data Path: ${userDataPath}`);
function log(message) {
    fs.appendFileSync(logFilePath, `${new Date().toISOString()} - ${message}\n`);
}
//const steamworks = require('steamworks.js');
//const client = steamworks.init(2520710);
//const steamId = client.localplayer.getSteamId();
// 创建主窗口实例
let windowIcon;
let windowPlayIcon;
let mainWindow;
let urlWindow;
let loginWindow;
let window;
// 创建关于窗口实例
let videoWindow; // 假设这是创建视频播放窗口时的引用
let loadWindow;
let selectionWindow;
let mainBrowserView;
let topBrowserView;
let subtitleSelectionWindow;
let isFullScreen;
let isTogglingFullScreen = false;
let windowMode;
// 监听应用程序退出事件
app.on('window-all-closed', () => {
    // 在 macOS 上，关闭所有窗口后退出应用程序
    if (process.platform !== 'darwin') {
        app.quit();
    }
});
app.on('ready', () => {
    // Windows: handle file opening at startup
    moveMessagesToNipa();
    if (process.platform === 'win32' && process.argv.length >= 2) {
        const filePath = process.argv.find(arg => arg.match(/\.(mp4|avi|mov|mkv|wmv|flv|m4v|webm)$/));
        if (filePath) {
            ffmpegif(filePath);
        }
    }
});
app.setAsDefaultProtocolClient('Nipaplay', process.execPath, ['--open-file']);
// macOS: handle file opening
app.on('open-file', (event, filePath) => {
    console.log('open-file event triggered');
    console.log('Dropped file path:', filePath);

    event.preventDefault();

    if (app.isReady()) {
        console.log('App is ready, processing file...');
        ffmpegif(filePath);
    } else {
        console.log('App is not ready, waiting...');
        app.on('ready', () => {
            console.log('App is now ready, processing file...');
            ffmpegif(filePath);
        });
    }
});
// All platforms: handle second instance
if (!app.requestSingleInstanceLock()) {
    app.quit();
} else {
    app.on('second-instance', (event, argv) => {
        if (mainWindow) {
            if (mainWindow.isMinimized()) mainWindow.restore();
            mainWindow.focus();

            if (process.platform === 'win32') {
                const filePath = argv.find(arg => arg.match(/\.(mp4|avi|mov|mkv|wmv|flv|m4v|webm)$/));
                if (filePath) {
                    ffmpegif(filePath);
                }
            }
        }
    });
}
// 监听应用程序激活事件
app.on('activate', () => {
    // 在 macOS 上，点击 Dock 图标时没有打开的窗口时，创建一个新的窗口
    if (BrowserWindow.getAllWindows().length === 0) {
        createMainWindow();
    }
});
app.whenReady().then(() => {
    app.setAppUserModelId('com.dfsteve.nipaplay'); // 设置应用程序的 User Model ID
    app.setBadgeCount(0); // 设置任务栏图标上的计数
    app.dock.setIcon(path.join(__dirname, windowIcon));
});
app.on('before-quit', () => {
    app.isQuitting = true;
});
// 监听应用程序准备就绪事件
app.on('ready', () => {
    app.commandLine.appendSwitch('disable-features', 'MediaRouter');
    // 清空指定文件夹
    clearDirectory(subPath);
    clearDirectory(danmakuPath);
    clearDirectory(video_commentPath);
    // 清除缓存
    session.defaultSession.clearCache().then(() => {
        //console.log('Cache cleared');
    });
    // 监听下载事件
    session.defaultSession.on('will-download', async (event, item, webContents) => {
        const url = item.getURL();
        if (urlWindow && !urlWindow.isDestroyed()) {
            urlWindow.close();
        }
        // 阻止默认的下载行为
        event.preventDefault();
        // 处理捕获到的下载 URL
        handleDownloadURL(url);
    });
    // 当应用程序获得焦点时注册快捷键
    app.on('browser-window-focus', () => {
        registerShortcuts();
    });

    // 当应用程序失去焦点时注销快捷键
    app.on('browser-window-blur', () => {
        unregisterShortcuts();
    });
    const isMacOS = process.platform === 'darwin';
    windowIcon = isMacOS ? 'window_icon.png' : 'icon.png';
    windowPlayIcon = isMacOS ? 'window_play_icon.png' : 'play_icon.png';
    // 创建主窗口
    createMainWindow();
    loginAndGetToken();
    initializeWindowModeFile();
    autoUpdater.checkForUpdatesAndNotify();

    autoUpdater.on('checking-for-update', () => {
        //console.log('Checking for update...');
    });

    autoUpdater.on('update-available', (info) => {
        //console.log('Update available.');
    });

    autoUpdater.on('update-not-available', (info) => {
        //console.log('Update not available.');
    });

    autoUpdater.on('error', (err) => {
        console.error('Error in auto-updater:', err);
    });

    autoUpdater.on('download-progress', (progressObj) => {
        let log_message = "Download speed: " + progressObj.bytesPerSecond;
        log_message = log_message + ' - Downloaded ' + progressObj.percent + '%';
        log_message = log_message + ' (' + progressObj.transferred + "/" + progressObj.total + ')';
        //console.log(log_message);
    });

    autoUpdater.on('update-downloaded', (info) => {
        //console.log('Update downloaded');

        // 获取发布说明
        let releaseNotes = info.releaseNotes;
        if (typeof releaseNotes === 'string') {
            releaseNotes = releaseNotes.replace(/(<([^>]+)>)/gi, ""); // 去除HTML标签
        } else if (Array.isArray(releaseNotes)) {
            releaseNotes = releaseNotes.map(note => note.body).join('\n');
        }

        // 提示更新的对话框
        dialog.showMessageBox({
            type: 'info',
            title: '版本更新',
            message: '有一个新的版本可以更新，要现在更新到最新版吗?',
            detail: releaseNotes, // 在对话框中显示发布说明
            buttons: ['更新', '稍后']
        }).then((result) => {
            if (result.response === 0) {
                autoUpdater.quitAndInstall();
            }
        });
    });
});
ipcMain.on('log-message', (event, message) => {
    console.log(message);
});
ipcMain.on('load-smb', async (event, smbUrl) => {
    console.log(`尝试连接到 SMB 地址: ${smbUrl}`);

    try {
        // 动态解析 SMB URL
        const { host, port, share } = parseSmbUrl(smbUrl);

        // 初始化 SMB 客户端
        const smbClient = new SMB2({
            share: `\\\\${host}\\${share}`, // SMB 格式路径
            port: port || 445, // 默认端口为 445
            domain: '', // 根据实际情况填写域
            username: '', // 初始为空
            password: ''  // 初始为空
        });

        // 测试连接
        await testSmbConnection(smbClient);

        // 如果成功，发送成功消息
        event.sender.send('smb-connection-success', `成功连接到 SMB 地址: ${smbUrl}`);
    } catch (error) {
        if (error.code === 'STATUS_LOGON_FAILURE') {
            console.log('需要身份验证');
            event.sender.send('smb-auth-required', {
                message: '需要输入账号和密码以访问 SMB 地址',
                smbUrl
            });
        } else {
            console.error('SMB 错误:', error.message);
            event.sender.send('smb-connection-error', `无法连接到 SMB 地址: ${error.message}`);
        }
    }
});

ipcMain.on('smb-auth-credentials', async (event, credentials) => {
    const { smbUrl, username, password } = credentials;

    console.log(`尝试重新连接到 SMB 地址: ${smbUrl} 使用用户名: ${username}`);

    smbClient = new SMB2({
        share: smbUrl,
        username,
        password,
        domain: ''
    });

    try {
        await testSmbConnection(smbClient);
        event.sender.send('smb-connection-success', `成功连接到 SMB 地址: ${smbUrl}`);
    } catch (error) {
        console.error('重新连接失败:', error);
        event.sender.send('smb-connection-error', `无法连接到 SMB 地址: ${error.message}`);
    }
});

ipcMain.on('login-dandanplay', (event) => {
    CreateLoginWindow();
});
ipcMain.on('login-out-dandanplay', (event) => {
    try {
        // 删除 token 文件
        if (fs.existsSync(tokenFilePath)) {
            fs.unlinkSync(tokenFilePath);
            console.log(`Deleted token file: ${tokenFilePath}`);
        } else {
            console.log(`Token file does not exist: ${tokenFilePath}`);
        }

        // 删除二进制文件
        if (fs.existsSync(binaryFilePath)) {
            fs.unlinkSync(binaryFilePath);
            console.log(`Deleted binary file: ${binaryFilePath}`);
        } else {
            console.log(`Binary file does not exist: ${binaryFilePath}`);
        }

        // 可以选择发送响应到渲染进程，表示登出成功
        event.reply('logout-success', { message: 'Logged out successfully' });
    } catch (error) {
        console.error('Error during logout:', error);
        event.reply('logout-error', { message: 'Logout failed', error: error.message });
    }
});
ipcMain.on('login-client', (event, { username, password }) => {
    loginUserName = username;
    loginPassword = password;
    console.log(loginUserName, loginPassword);
    loginAndGetToken();
});
ipcMain.on('danmaku-shoot', async (event, text, formattedTime, mode, color, episodeId) => {
    // 构建请求数据
    const requestData = JSON.stringify({
        time: formattedTime,
        mode: mode,
        color: color,
        comment: text
    });

    // 获取当前时间戳
    const timestamp = Math.floor(Date.now() / 1000);


    const apiPath = `/api/v2/comment/${episodeId}`;


    const encryptedAppSecret = await fetchEncryptedAppSecret();
    const appSecret = co(encryptedAppSecret);

    // 计算签名
    const signatureString = `${appId}${timestamp}${apiPath}${appSecret}`;
    const signature = crypto.createHash('sha256').update(signatureString).digest('base64');

    // 设置请求选项
    const options = {
        hostname: 'api.dandanplay.net',
        path: `/api/v2/comment/${episodeId}`,
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`,
            'Accept': 'application/json',
            'Content-Length': Buffer.byteLength(requestData),
            'X-AppId': appId,
            'X-Signature': signature,
            'X-Timestamp': timestamp
        }
    };

    // 发送 HTTPS 请求
    const req = https.request(options, (res) => {
        let data = '';

        // 接收数据块
        res.on('data', (chunk) => {
            data += chunk;
        });

        // 响应结束
        res.on('end', () => {
            try {
                const responseData = JSON.parse(data);
                console.log('Response from server:', responseData);
                // 将响应数据发送回渲染进程
                event.reply('danmaku-response', responseData);
            } catch (parseError) {
                console.error('解析响应数据失败:', parseError);
                event.reply('danmaku-response', { error: '解析失败' });
            }
        });
    });

    // 请求错误处理
    req.on('error', (error) => {
        console.error('发送请求时发生错误:', error);
        event.reply('danmaku-response', { error: '请求失败' });
    });

    // 发送请求数据
    req.write(requestData);
    req.end();
});
ipcMain.on('set-window-mode', (event, windowMode) => {
    fs.readFile(windowModePath, 'utf8', (err, data) => {
        if (err) {
            console.error('Error reading JSON file:', err);
            return;
        }

        let windowConfig;
        try {
            windowConfig = JSON.parse(data);
        } catch (parseError) {
            console.error('Error parsing JSON:', parseError);
            return;
        }

        // 更新 windowMode 值
        windowConfig.windowMode = windowMode;

        // 写入更新后的 JSON 文件
        fs.writeFile(windowModePath, JSON.stringify(windowConfig, null, 2), 'utf8', (err) => {
            if (err) {
                console.error('Error writing JSON file:', err);
                return;
            }
            console.log('windowMode:', windowMode);
            // 向渲染进程发送确认消息
            event.sender.send('window-mode-updated', windowMode, windowModePath);
        });
    });
});
ipcMain.on('window-action', (event, action) => {
    const window = BrowserWindow.getFocusedWindow();
    if (action === 'close') {
        window.close();
    }
});
ipcMain.on('load-folder-contents', async (event, folderPath) => {
    try {
        //console.log("Received folder path:", folderPath);
        if (!folderPath) {
            console.error("folderPath is undefined");
            event.reply('folder-contents-loaded', []);
            return;
        }
        const videoFiles = await getVideoFiles(folderPath);
        //console.log('Found video files:', videoFiles);
        event.reply('folder-contents-loaded', videoFiles);
        event.reply('config-updated2');
    } catch (err) {
        console.error("Error reading directory:", err);
        event.reply('folder-contents-loaded', []);
    }
});
ipcMain.on('get-window-mode-url', async (event) => {
    // 检查 JSON 文件是否存在
    if (fs.existsSync(windowModePath)) {
        // 异步读取 JSON 文件
        fs.readFile(windowModePath, 'utf8', (err, data) => {
            if (err) {
                console.error('Error reading JSON file:', err);
                return;
            }

            // 解析 JSON 数据
            let windowConfig;
            try {
                windowConfig = JSON.parse(data);
            } catch (parseError) {
                console.error('Error parsing JSON:', parseError);
                return;
            }

            // 将 JSON 中的 windowMode 发送回渲染进程
            event.reply('return-window-mode-url', windowConfig.windowMode);
        });
    } else {
        // 如果 JSON 文件不存在，返回一个默认值
        const defaultConfig = { windowMode: 'full' };
        event.reply('return-window-mode-url', defaultConfig.windowMode);
    }
});
ipcMain.on('import-folder', async (event) => {
    const { canceled, filePaths } = await dialog.showOpenDialog({
        properties: ['openDirectory']
    });
    if (!canceled && filePaths.length > 0) {
        const configPath = path.join(downloadsPath, 'nipaplay', 'nipaplay_config.json');
        const configDir = path.dirname(configPath);

        if (!fs.existsSync(configDir)) {
            fs.mkdirSync(configDir, { recursive: true });
        }

        let config = {};
        if (fs.existsSync(configPath)) {
            config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
        }
        if (!config.selectedFolders) {
            config.selectedFolders = [];
        }
        if (!config.selectedFolders.includes(filePaths[0])) {
            config.selectedFolders.push(filePaths[0]);
        }
        fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
        event.reply('config-updated');
    }
});
ipcMain.on('remove-folder', async (event, folderToRemove) => {
    const configPath = path.join(downloadsPath, 'nipaplay', 'nipaplay_config.json');

    if (fs.existsSync(configPath)) {
        const data = fs.readFileSync(configPath, 'utf8');
        const config = JSON.parse(data);

        // 过滤掉要删除的文件夹路径
        config.selectedFolders = config.selectedFolders.filter(folderPath => folderPath !== folderToRemove);

        // 保存更新后的配置
        fs.writeFileSync(configPath, JSON.stringify(config, null, 2));

        // 可以发送一个事件回渲染进程以更新界面
        event.reply('config-updated');
    }
});
ipcMain.on('open-url-window', () => {
    createUrlWindow();
});
ipcMain.on('load-config', async (event) => {
    const configPath = path.join(downloadsPath, 'nipaplay', 'nipaplay_config.json');
    try {
        //console.log('Config path:', configPath); // 输出配置文件路径
        if (fs.existsSync(configPath)) {
            const fileContent = fs.readFileSync(configPath, 'utf8');
            const config = JSON.parse(fileContent);
            event.reply('config-loaded', config.selectedFolders);
        } else {
            event.reply('config-loaded', null);
        }
    } catch (error) {
        console.error('Failed to read config:', error);
        event.reply('config-loaded', null);
    }
});
ipcMain.on('close-url-window', () => {
    if (urlWindow) {
        if (urlWindow && !urlWindow.isDestroyed()) {
            urlWindow.close();
        }
    }
});
ipcMain.on('close-login-window', () => {
    if (loginWindow) {
        if (loginWindow && !loginWindow.isDestroyed()) {
            loginWindow.close();
        }
    }
});
ipcMain.on('close-selection-window', () => {
    if (selectionWindow) {
        //console.log('nipa');
        selectionWindow.close();
    }
});
ipcMain.on('close-main-window', () => {
    if (mainWindow) {
        app.quit();
    }
});
ipcMain.on('fullscreen-window', handleFullscreen);
ipcMain.on('restore-window', handleRestore);
ipcMain.on('minimize-window', (event) => {
    if (mainWindow) {
        const window = BrowserWindow.fromWebContents(event.sender);
        window.minimize();
    }
});
ipcMain.on('get-downloads-path', (event) => {
    event.reply('downloads-path', downloadsPath);
});
ipcMain.on('get-downloads-path2', (event) => {
    event.reply('downloads-path2', downloadsPath);
});
ipcMain.on('get-downloads-path3', (event) => {
    event.reply('downloads-path3', downloadsPath);
});
// 监听来自 video-player.html 的消息，更新观看记录并重新加载 index.html 页面
ipcMain.on('update-watched-video', (event, videoRecord) => {
    // 发送消息到主窗口的渲染进程，而不是重新加载窗口
    // 在Dock上设置这个菜单
    app.addRecentDocument(videoRecord.path);
    mainWindow.webContents.send('watched-video-updated', videoRecord);
});
ipcMain.on('toggle-fullscreen', (event) => {
    const window = BrowserWindow.getFocusedWindow();
    if (window) {
        //console.log('ohhhhhh');
        isFullScreen = 'nanami';
        window.setFullScreen(!window.isFullScreen());
    }
});
ipcMain.handle('dialog:openFile', async (event, options) => {
    const { canceled, filePaths } = await dialog.showOpenDialog({
        properties: ['openFile'],
        filters: options.filters || []
    });
    if (canceled || filePaths.length === 0) {
        return '';
    } else {
        return filePaths[0]; // 返回选择的第一个文件路径
    }
});
ipcMain.handle('open-file-dialog', async () => {
    const result = await dialog.showOpenDialog({
        properties: ['openFile'],
        filters: [
            { name: 'Danmaku Files', extensions: ['xml', 'json'] }
        ]
    });
    return result;
});
ipcMain.handle('read-file', async (event, filePath) => {
    try {
        const content = fs.readFileSync(path.join(__dirname, filePath), { encoding: 'utf-8' });
        return { success: true, content };
    } catch (error) {
        return { success: false, error: error.message };
    }
});
// 在main.js中添加一个新的IPC事件监听器来处理从渲染进程发来的请求
ipcMain.on('open-video-file', (event, filePath) => {
    //console.log("Received file path:", filePath);
    if (filePath) {
        //console.log("Received file path:", filePath);
        ffmpegif(filePath); // 使用接收到的文件路径打开视频窗口
    } else {
        console.error('No file path provided');
    }
});
ipcMain.on('load-url', (event, url) => {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'http://' + url; // 默认添加http://协议
    }
    createBrowserView(url);
    //console.log('URL loaded:', url);
    urlWindow.once('ready-to-show', () => {
        urlWindow.setSize(800, 600);
        urlWindow.center(); // 调整大小后重新居中
    });
    mainBrowserView.webContents.on('did-finish-load', () => {
        //console.log('BrowserView loaded:', url);
        setTimeout(startCheckingForVideo, 2000); // 延迟2秒再启动检查视频的逻辑
    });
});
ipcMain.on('select-video', async (event) => {
    const { canceled, filePaths } = await dialog.showOpenDialog(mainWindow, {
        properties: ['openFile'], // 允许选择文件和文件夹
        filters: [{ name: 'Videos', extensions: ['mp4', 'avi', 'mov', 'mkv', 'wmv', 'flv', 'm4v', 'webm'] }]
    });

    if (!canceled && filePaths.length > 0) {
        const selectedPath = filePaths[0];

        fs.stat(selectedPath, (err, stats) => {
            if (err) {
                console.error(`An error occurred: ${err.message}`);
                return;
            }

            // 直接使用目录名作为文件名尝试构建视频文件路径
            if (stats.isDirectory()) {
                // 通过目录名获取可能的文件名（包括扩展名）
                const dirName = path.basename(selectedPath);
                // 构建假定的视频文件路径
                const assumedFilePath = path.join(selectedPath, dirName);

                // 检查假定的文件是否存在
                if (fs.existsSync(assumedFilePath)) {
                    //console.log('Found video file path:', assumedFilePath);
                    ffmpegif(assumedFilePath);
                } else {
                    const errorMsg = `The assumed video file does not exist: ${assumedFilePath}`;
                    console.error(errorMsg);
                    // Optionally, send this error back to the renderer process
                    event.sender.send('file-not-found', errorMsg);
                }
            } else if (stats.isFile()) {
                ffmpegif(selectedPath); // 直接打开选择的视频文件
            }
        });
    }
});
ipcMain.handle('search-anime', async (event, searchTerm) => {
    const urlEncodedSearchTerm = encodeURIComponent(searchTerm);
    const url = `https://api.dandanplay.net/api/v2/search/episodes?anime=${urlEncodedSearchTerm}`;

    // 获取当前时间戳
    const timestamp = Math.floor(Date.now() / 1000);
    const apiPath = `/api/v2/search/episodes`;
    const encryptedAppSecret = await fetchEncryptedAppSecret();
    const appSecret = co(encryptedAppSecret);

    // 计算签名
    const signatureString = `${appId}${timestamp}${apiPath}${appSecret}`;
    const signature = crypto.createHash('sha256').update(signatureString).digest('base64');

    // 设置请求头
    const options = {
        headers: {
            'Accept': 'application/json',
            'Authorization': `Bearer ${token}`,
            'X-AppId': appId,
            'X-Signature': signature,
            'X-Timestamp': timestamp,
        }
    };

    return new Promise((resolve, reject) => {
        https.get(url, options, (response) => {
            let data = '';

            // 接收数据块
            response.on('data', (chunk) => data += chunk);

            // 响应结束
            response.on('end', () => {
                try {
                    const parsedData = JSON.parse(data);
                    // 如果请求成功并且返回了动漫数据
                    if (parsedData.success && parsedData.animes) {
                        resolve(parsedData.animes); // 返回数组
                    } else {
                        resolve([]); // 如果没有数据或请求不成功，返回空数组
                    }
                } catch (error) {
                    console.error('解析响应数据失败:', error);
                    reject(error);
                }
            });
        }).on('error', (error) => {
            console.error('请求失败:', error);
            reject(error);
        });
    });
});
function loadWindowMode() {
    if (fs.existsSync(windowModePath)) {
        try {
            const data = fs.readFileSync(windowModePath, 'utf8');
            const windowConfig = JSON.parse(data);
            if (windowConfig.windowMode) {
                windowMode = windowConfig.windowMode;
            }
        } catch (error) {
            console.error('Error reading or parsing windowMode.json:', error);
        }
    } else {
        console.log('windowMode.json not found. Using default windowMode:', windowMode);
    }
}
function initializeWindowModeFile() {
    if (!fs.existsSync(windowModePath)) {
        const defaultWindowConfig = {
            windowMode: 'full'  // 默认模式为 'win'
        };

        fs.writeFileSync(windowModePath, JSON.stringify(defaultWindowConfig, null, 2), 'utf8', (err) => {
            if (err) {
                console.error('Error creating JSON file:', err);
            }
        });
    }
}
///全屏按钮按下以后的动画
function animateWindowResize(window, targetWidth, targetHeight, duration) {
    const { width: startWidth, height: startHeight, x: startX, y: startY } = window.getBounds();
    const { width: screenWidth, height: screenHeight } = screen.getPrimaryDisplay().workAreaSize;
    const startTime = Date.now();

    const interval = setInterval(() => {
        const now = Date.now();
        const progress = Math.min((now - startTime) / duration, 1);
        const currentWidth = startWidth + (targetWidth - startWidth) * progress;
        const currentHeight = startHeight + (targetHeight - startHeight) * progress;
        const currentX = Math.round(screenWidth / 2 - currentWidth / 2);
        const currentY = Math.round(screenHeight / 2 - currentHeight / 2);

        window.setBounds({
            width: Math.round(currentWidth),
            height: Math.round(currentHeight),
            x: currentX,
            y: currentY
        });

        if (progress >= 1) {
            clearInterval(interval);
            window.unfreezeFrame();
        }
    }, 16); // 每帧约16ms, 对应60fps

    window.freezeFrame();
}
// 从二进制文件提取用户名和密码的函数
function loadCredentialsFromBinaryFile(filePath) {
    if (fs.existsSync(filePath)) {
        const buffer = fs.readFileSync(filePath);

        // 假设用户名和密码之间用 0 字节分隔
        const [usernameBuffer, passwordBuffer] = buffer.toString('utf-8').split('\0'); // 使用 0 字节作为分隔符

        // 去掉多余的空格，并赋值给变量
        loginUserName = usernameBuffer.trim();
        loginPassword = passwordBuffer.trim();
    } else {
        console.error('二进制文件不存在');
    }
}
// 解析 SMB URL
function parseSmbUrl(smbUrl) {
    const url = new URL(smbUrl);
    const pathParts = url.pathname.split('/').filter(Boolean); // 去掉空路径片段
    return {
        host: url.hostname,
        port: url.port ? parseInt(url.port, 10) : undefined,
        share: pathParts[0] || '' // 取第一个路径片段作为共享路径
    };
}

// 测试 SMB 连接
async function testSmbConnection(client) {
    return new Promise((resolve, reject) => {
        client.readdir('', (err, files) => {
            if (err) {
                return reject(err);
            }
            console.log('根目录文件列表:', files);
            resolve(files);
        });
    });
}
// 登录并获取 token 的函数
async function loginAndGetToken() {
    // 从二进制文件中加载用户名和密码
    loadCredentialsFromBinaryFile(binaryFilePath); // 假设文件名为 'loginData.bin'

    const currentTimestamp = Math.floor(Date.now() / 1000);
    const twentyDaysInSeconds = 20 * 24 * 60 * 60;
    //console.log("loginUserName:", loginUserName);
    //console.log("loginPassword:", loginPassword);
    // 检查 token 文件是否存在且时间戳是否有效
    if (fs.existsSync(tokenFilePath)) {
        const tokenData = JSON.parse(fs.readFileSync(tokenFilePath, 'utf-8'));
        if (tokenData.timestamp && currentTimestamp - tokenData.timestamp < twentyDaysInSeconds) {
            token = tokenData.token;
            if (loginWindow) {
                loginWindow.webContents.send('login-success', loginUserName);
            }
            mainWindow.webContents.send('login-success', loginUserName);
            return;
        }
    }

    try {
        const encryptedAppSecret = await fetchEncryptedAppSecret();
        const appSecret = co(encryptedAppSecret);
        const hashString = `${appId}${loginPassword}${currentTimestamp}${loginUserName}${appSecret}`; // 使用提取的变量
        const hash = crypto.createHash('md5').update(hashString).digest('hex');
        const finalRequestData = JSON.stringify({
            userName: loginUserName,
            password: loginPassword,
            appId: appId,
            unixTimestamp: currentTimestamp,
            hash: hash
        });
        fetchToken(finalRequestData, currentTimestamp);
    } catch (error) {
        loginWindow.webContents.send('login-failed');
        console.error(error);
    }
}

// 请求加密的 appSecret
function fetchEncryptedAppSecret() {
    return new Promise((resolve, reject) => {
        const options = {
            hostname: 'nipaplay.aimes-soft.com',
            port: 443,
            path: '/nipaplay.php',
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            }
        };

        const req = https.request(options, (res) => {
            let data = '';
            res.on('data', (chunk) => {
                data += chunk;
            });
            res.on('end', () => {
                try {
                    const response = JSON.parse(data);
                    if (response.encryptedAppSecret) {
                        resolve(response.encryptedAppSecret);
                    } else {
                        reject('未返回');
                    }
                } catch (error) {
                    reject('解析响应数据失败');
                }
            });
        });

        req.on('error', (error) => reject(error));
        req.write('{}'); // 空的 POST 请求
        req.end();
    });
}
function ba(b) {
    return b.split('').map(char => {
        if (/[a-z]/.test(char)) {
            return String.fromCharCode(219 - char.charCodeAt(0));
        } else if (/[A-Z]/.test(char)) {
            return String.fromCharCode(155 - char.charCodeAt(0));
        } else {
            return char;
        }
    }).join('');
}
function tr(b) {
    return b.split('').map(char => {
        if (/[a-z]/.test(char)) return char.toUpperCase();
        if (/[A-Z]/.test(char)) return char.toLowerCase();
        return char;
    }).join('');
}
async function fetchToken(requestData, currentTimestamp) {
    const apiPath = '/api/v2/login';

    const timestamp = Math.floor(Date.now() / 1000);
    const apiPathFull = apiPath;

    const encryptedAppSecret = await fetchEncryptedAppSecret();
    const appSecret = co(encryptedAppSecret);

    const signatureString = `${'nipaplayv1'}${timestamp}${apiPathFull}${appSecret}`;
    const signature = crypto.createHash('sha256').update(signatureString).digest('base64');

    const options = {
        hostname: 'api.dandanplay.net',
        port: 443,
        path: apiPath,
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Content-Length': requestData.length,
            'X-AppId': 'nipaplayv1',
            'X-Signature': signature,
            'X-Timestamp': timestamp
        }
    };

    const req = https.request(options, (res) => {
        let data = '';
        res.on('data', (chunk) => {
            data += chunk;
        });
        res.on('end', () => {
            try {
                const response = JSON.parse(data);
                if (response.token) {
                    token = response.token;

                    loginWindow.webContents.send('login-success', loginUserName);
                    mainWindow.webContents.send('login-success', loginUserName);
                    fs.writeFileSync(tokenFilePath, JSON.stringify({ token, timestamp: currentTimestamp }), 'utf-8');

                    saveCredentialsToBinaryFile(loginUserName, loginPassword);
                } else {
                    loginWindow.webContents.send('login-failed');
                    console.error('登录失败，未返回 token:', response);
                }
            } catch (error) {
                console.error('解析响应数据失败:', error);
            }
        });
    });

    req.on('error', (error) => {
        console.error('请求出错:', error);
    });

    req.write(requestData);
    req.end();
}
function saveCredentialsToBinaryFile(username, password) {
    // 创建一个缓冲区，先转换用户名和密码为字节
    const usernameBuffer = Buffer.from(username, 'utf-8');
    const passwordBuffer = Buffer.from(password, 'utf-8');

    // 创建一个总的缓冲区，包含用户名和密码
    const buffer = Buffer.concat([usernameBuffer, Buffer.from([0]), passwordBuffer]); // 以 0 字节分隔用户名和密码

    // 将缓冲区写入二进制文件
    fs.writeFileSync(binaryFilePath, buffer);
}
function handleFullscreen() {
    if (mainWindow) {
        const { width, height } = screen.getPrimaryDisplay().workAreaSize;
        animateWindowResize(mainWindow, width, height, 100); // 500ms 动画时间
    }
}

function handleRestore() {
    if (mainWindow) {
        animateWindowResize(mainWindow, 800, 600, 100); // 500ms 动画时间
    }
}

BrowserWindow.prototype.freezeFrame = function () {
    this.webContents.executeJavaScript('document.body.style.visibility = "hidden";');
};

BrowserWindow.prototype.unfreezeFrame = function () {
    this.webContents.executeJavaScript('document.body.style.visibility = "";');
};
function createUrlWindow() {
    urlWindow = new BrowserWindow({
        width: 300,
        height: 200,
        maxWidth: 800,
        maxHeight: 600,
        minWidth: 300,
        minHeight: 200,
        fullscreen: false,
        show: false,
        frame: false,
        modal: true, // 设置为模态窗口
        vibrancy: 'popover',
        parent: mainWindow, // 设置父窗口
        icon: path.join(__dirname, windowIcon),
        autoHideMenuBar: true,
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false,
            webSecurity: false, // 允许跨域
            experimentalFeatures: true // 启用实验性功能
        }
    });
    urlWindow.webContents.loadFile('urlmenu.html'); // 加载外部的HTML文件
    urlWindow.once('ready-to-show', () => {
        urlWindow.show(); // 显示窗口
    });
}
function registerShortcuts() {
    const ret = globalShortcut.register('CommandOrControl+Q', () => {
        const allWindows = BrowserWindow.getAllWindows();
        const isAnyWindowFocused = allWindows.some(win => win.isFocused());

        if (isAnyWindowFocused) {
            // 结束应用程序
            app.quit();
        }
    });

    // 检查注册快捷键的状态
    if (!ret) {
        console.error('Registration failed');
    }
}

function unregisterShortcuts() {
    globalShortcut.unregister('CommandOrControl+Q');
}
function createBrowserView(url) {
    topBrowserView = new BrowserView({
        webPreferences: {
            nodeIntegration: false,
            contextIsolation: true,
            webSecurity: false,
            experimentalFeatures: true
        }
    });
    urlWindow.setBrowserView(topBrowserView);
    let topBounds = calculateTopBounds();
    topBrowserView.setBounds(topBounds);
    topBrowserView.webContents.loadFile('close.html');
    mainBrowserView = new BrowserView({
        webPreferences: {
            nodeIntegration: false,
            contextIsolation: true,
            webSecurity: false,
            experimentalFeatures: true
        }
    });
    urlWindow.setBrowserView(mainBrowserView);
    let mainBounds = calculateMainBounds();
    mainBrowserView.setBounds(mainBounds);
    mainBrowserView.webContents.loadURL(url);
}
function calculateMainBounds() {
    const width = mainWindow.getBounds().width;
    const height = mainWindow.getBounds().height - 30; // 留出顶部视图的高度
    return { x: 0, y: 30, width: width, height: height };
}
function ds(c) {
    return c.replace(/\d/g, digit => 10 - parseInt(digit));
}
function calculateTopBounds() {
    const width = mainWindow.getBounds().width;
    const height = 50; // 顶部视图高度
    return { x: 0, y: 0, width: width, height: height };
}
function calculateFileHash(filePath, algorithm = 'md5') {
    return new Promise((resolve, reject) => {
        const hash = crypto.createHash(algorithm);
        const stream = fs.createReadStream(filePath);
        let totalBytes = 0;
        const limit = 16 * 1024 * 1024; // 16 MB的限制
        let digestCalled = false; // 添加标志位，防止多次调用digest
        stream.on('error', err => reject(err));
        stream.on('data', chunk => {
            totalBytes += chunk.length;
            if (totalBytes <= limit) {
                hash.update(chunk);
            } else {
                // 如果读取超过16MB，停止更新哈希并关闭流
                stream.close();
            }
        });
        stream.on('end', () => {
            // 仅在正常结束流（未提前关闭）时返回哈希
            if (totalBytes <= limit && !digestCalled) {
                digestCalled = true;
                console.log("end")
                resolve(hash.digest('hex'));
            }
        });
        stream.on('close', () => {
            // 如果流被提前关闭，返回当前哈希状态
            if (!digestCalled) {
                digestCalled = true;
                resolve(hash.digest('hex'));
            }
        });
    });
}
function startCheckingForVideo() {
    const checkInterval = 1000; // 每秒检查一次

    const interval = setInterval(async () => {
        if (mainBrowserView && mainBrowserView.webContents) {
            try {
                const result = await mainBrowserView.webContents.executeJavaScript(`
                    (function() {
                        const videoElement = document.querySelector('video');
                        const title = document.title;
                        if (videoElement && videoElement.src) {
                            return { videoUrl: videoElement.src, title: title };
                        } else {
                            return null;
                        }
                    })()
                `);
                if (result && result.videoUrl) {
                    const response = await recognizeVideo2(result.title);
                    // Step 1: Fetch subtitle tracks from the video file
                    const subtitleTracks = await fetchSubtitleTracks(result.videoUrl);
                    if (subtitleTracks.length > 0) {
                        // Step 2: Show subtitle selection window
                        const selectedTrack = await showSubtitleSelection(subtitleTracks);
                        if (selectedTrack == null || selectedTrack == undefined) {
                            return
                        }
                        // Step 3: Extract selected subtitle
                        const subtitlePath = await extractSubtitles(result.videoUrl, selectedTrack, subPath);
                    }
                    clearInterval(interval);
                    if (response.isMatched) {
                        const newTitle = `${response.animeTitle} ${response.episodeTitle}`;
                        const newepisodeId = response.episodeId;
                        //console.log('id+title:', newTitle, newepisodeId);
                        if (urlWindow && !urlWindow.isDestroyed()) {
                            urlWindow.close();
                        }
                        danmakudownload(newTitle, result.videoUrl, newepisodeId);
                    } else {
                        if (urlWindow && !urlWindow.isDestroyed()) {
                            urlWindow.close();
                        }
                        createSelectionWindow(response.matches, result.videoUrl, response.episodeId);
                    }
                }
            } catch (err) {
                clearInterval(interval);
            }
        } else {
            clearInterval(interval);
            console.error('mainBrowserView is undefined or has been destroyed');
        }
    }, checkInterval);
}

async function handleDownloadURL(url) {
    CreateloadWindow();
    const response = await recognizeVideo2(url);
    ////console.log('response:', response);
    // Step 1: Fetch subtitle tracks from the video file
    const subtitleTracks = await fetchSubtitleTracks(url);
    if (subtitleTracks.length > 0) {
        // Step 2: Show subtitle selection window
        const selectedTrack = await showSubtitleSelection(subtitleTracks);
        if (selectedTrack == null || selectedTrack == undefined) {
            return
        }
        // Step 3: Extract selected subtitle
        const subtitlePath = await extractSubtitles(url, selectedTrack, subPath);
    }
    // 调用 recognizeVideo2 识别视频
    ////console.log("post结果:", response.isMatched, response.animeTitle, response.episodeId, response.animeId);
    if (response.isMatched) {
        const newTitle = `${response.animeTitle} ${response.episodeTitle}`;
        const episodeId = response.episodeId;
        // 下载并处理弹幕
        await danmakudownload(newTitle, url, episodeId);
    } else {
        createSelectionWindow(response.matches, url, response.episodeId);
    }
    loadWindow.webContents.close();
}
function ffmpegif(videoPath) {
    const ext = path.extname(videoPath).toLowerCase();
    if (ext === '.gif') {
        ffmpegWindow(videoPath);
    } else {
        openVideoAndFetchDetails(videoPath);
    }
};
function ffmpegWindow(videoPath) {
    const isMac = process.platform === 'darwin';
    const ffmpegPath = isMac ? './ffmpeg/ffmpeg_mac' : './ffmpeg/ffmpeg_win/bin/ffmpeg.exe';
    const outputVideoPath = path.join('./cache', videoPath);  // 定义输出文件路径

    const { spawn } = require('child_process');
    const ffmpeg = spawn(ffmpegPath, [
        '-i', videoPath,            // 输入文件
        '-c:v', 'h264',             // 视频编解码器
        '-c:a', 'aac',              // 音频编解码器
        '-f', 'mp4',             // 使用 ffplay 播放器
        outputVideoPath             // 输出文件路径
    ]);

    // 监听 FFmpeg 子进程的输出
    ffmpeg.stdout.on('data', (data) => {
        //console.log(`FFmpeg output: ${data}`);
    });

    // 监听 FFmpeg 子进程的错误输出
    ffmpeg.stderr.on('data', (data) => {
        console.error(`FFmpeg error: ${data}`);
    });

    // 监听 FFmpeg 子进程的退出事件
    ffmpeg.on('close', (code) => {
        //console.log(`FFmpeg process exited with code ${code}`);

        // 如果 FFmpeg 成功处理视频，则创建视频窗口播放处理后的视频
        if (code === 0) {
            createVideoWindow(outputVideoPath); // 将处理后的视频路径传递给 createVideoWindow 函数
        }
    });
}
// 递归遍历目录以查找视频文件
async function getVideoFiles(dir) {
    let results = [];
    const entries = await fs2.readdir(dir, { withFileTypes: true });
    for (let entry of entries) {
        const entryPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            results = results.concat(await getVideoFiles(entryPath)); // 递归遍历子目录
        } else if (entry.isFile() && /\.(mp4|avi|mov|mkv)$/i.test(entry.name)) {
            results.push(entryPath); // 添加视频文件
        }
    }
    return results;
}
function clearDirectory(directory) {
    // 读取目录中的文件
    fs.readdir(directory, (err, files) => {
        if (err) {
            console.error('Error reading directory:', err);
            return;
        }

        // 删除目录中的每个文件
        files.forEach(file => {
            const filePath = path.join(directory, file);

            // 删除文件
            fs.unlink(filePath, err => {
                if (err) {
                    console.error('Error deleting file:', err);
                }
            });
        });
    });
}
function getFileSize(filePath) {
    try {
        const stats = fs.statSync(filePath);
        return stats.size;  // 返回文件大小（单位：字节）
    } catch (error) {
        console.error('获取文件大小时发生错误:', error);
        return null;  // 如果发生错误，返回 null
    }
}
// 保存识别结果
function saveRecognitionResult(videoPath, result) {
    const hash = crypto.createHash('md5').update(videoPath).digest('hex');
    store.set(hash, result);
}
async function getVideoUrlFromPage(url) {
    return new Promise((resolve, reject) => {
        JSDOM.fromURL(url).then(dom => {
            const videoElement = dom.window.document.querySelector('video');
            if (videoElement && videoElement.src) {
                resolve(videoElement.src);
            } else {
                reject('No video found');
            }
        }).catch(err => reject(err));
    });
}
// 获取识别结果
function getRecognitionResult(videoPath) {
    const hash = crypto.createHash('md5').update(videoPath).digest('hex');
    return store.get(hash);
}
async function recognizeVideo(videoPath, center) {
    console.log("vaideopath and center:", videoPath, center);
    const fileName = path.basename(videoPath);
    console.log("fileName:", fileName);
    let hash;
    if (center === 'lain') {
        hash = 'd41d8cd98f00b204e9800998ecf8427e';
    } else {
        hash = await calculateFileHash(videoPath, 'md5');
    }
    console.log("hash:", hash);
    const fileSize = getFileSize(videoPath);
    console.log("fileSize:", fileSize);

    const requestData = JSON.stringify({
        fileName: fileName,
        fileHash: hash,
        fileSize: fileSize,
        matchMode: 'hashAndFileName',
        token: token
    });

    // 获取 appSecret
    const encryptedAppSecret = await fetchEncryptedAppSecret();
    const appSecret = co(encryptedAppSecret);

    // 获取当前时间戳并计算签名
    const timestamp = Math.floor(Date.now() / 1000);
    const apiPath = '/api/v2/match';
    const signatureString = `${appId}${timestamp}${apiPath}${appSecret}`;
    const signature = crypto.createHash('sha256').update(signatureString).digest('base64');
/*
    console.log('Request Data:', requestData);  // 打印发送的请求数据
    console.log('Request Headers:', {
        'X-AppId': appId,
        'X-Signature': signature,
        'X-Timestamp': timestamp
    });  // 打印请求头部信息
*/
    const options = {
        hostname: 'api.dandanplay.net',
        path: apiPath,
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Content-Length': Buffer.byteLength(requestData),
            'X-AppId': appId,
            'X-Signature': signature,
            'X-Timestamp': timestamp
        },
        rejectUnauthorized: false,  // 忽略证书验证
        timeout: 5000
    };

    if (token) {
        options.headers['Authorization'] = `Bearer ${token}`;
    }

    return new Promise((resolve, reject) => {
        const request = https.request(options, (response) => {
            let data = '';
            response.on('data', (chunk) => {
                data += chunk;
            });
            response.on('end', () => {
                try {
                    const responseData = JSON.parse(data);
                    resolve({
                        isMatched: responseData.isMatched,
                        matches: responseData.matches,
                        episodeId: responseData.matches[0]?.episodeId,
                        animeId: responseData.matches[0]?.animeId,
                        animeTitle: responseData.matches[0]?.animeTitle,
                        episodeTitle: responseData.matches[0]?.episodeTitle
                    });
                } catch (parseError) {
                    console.error('解析 HTTPS 请求响应时发生错误:', parseError);
                    resolve(false);
                }
            });
        });
        request.on('error', (error) => {
            console.error('发送 HTTPS 请求时发生错误:', error);
            resolve(false);
        });

        request.on('timeout', () => {
            console.error('请求超时');
            request.destroy();
            resolve(false);
        });

        request.write(requestData);
        request.end();
    });
}

async function recognizeVideo2(title) {
    let videoPath = title;
    let hash = 'd41d8cd98f00b204e9800998ecf8427e';
    let fileSize = 0;

    if (title.startsWith('https')) {
        const url = title;
        const ext = path.extname(url);
        const filename = `${uuidv4()}${ext}`;
        const filepath = path.join(danmakuPath, filename);
        try {
            const { default: got } = await import('got');
            const response = await got(url, {
                headers: {
                    'Range': 'bytes=0-16777215'
                },
                responseType: 'buffer'
            });

            fs.writeFileSync(filepath, response.body);
            videoPath = filepath;
            hash = await calculateFileHash(videoPath, 'md5');
            fileSize = response.body.length;
        } catch (error) {
            console.error('Error downloading video:', error);
            throw new Error('Failed to download video');
        }
    }

    const fileName = path.basename(videoPath);

    const requestData = JSON.stringify({
        fileName: fileName,
        fileHash: hash,
        fileSize: fileSize,
        matchMode: 'hashAndFileName',
        token: token
    });

    // 获取 appSecret
    const encryptedAppSecret = await fetchEncryptedAppSecret();
    const appSecret = co(encryptedAppSecret);

    // 获取当前时间戳并计算签名
    const timestamp = Math.floor(Date.now() / 1000);
    const apiPath = '/api/v2/match';
    const signatureString = `${appId}${timestamp}${apiPath}${appSecret}`;
    const signature = crypto.createHash('sha256').update(signatureString).digest('base64');
/*
    console.log('Request Data:', requestData);  // 打印发送的请求数据
    console.log('Request Headers:', {
        'X-AppId': appId,
        'X-Signature': signature,
        'X-Timestamp': timestamp
    });  // 打印请求头部信息
*/
    const options = {
        hostname: 'api.dandanplay.net',
        path: apiPath,
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Content-Length': Buffer.byteLength(requestData),
            'X-AppId': appId,
            'X-Signature': signature,
            'X-Timestamp': timestamp
        },
        rejectUnauthorized: false,  // 忽略证书验证
        timeout: 5000
    };

    if (token) {
        options.headers['Authorization'] = `Bearer ${token}`;
    }

    return new Promise((resolve, reject) => {
        const request = https.request(options, (response) => {
            let data = '';

            response.on('data', (chunk) => {
                data += chunk;
            });

            response.on('end', () => {
                try {
                    const responseData = JSON.parse(data);
                    resolve({
                        isMatched: responseData.isMatched,
                        matches: responseData.matches,
                        episodeId: responseData.matches[0]?.episodeId,
                        animeId: responseData.matches[0]?.animeId,
                        animeTitle: responseData.matches[0]?.animeTitle,
                        episodeTitle: responseData.matches[0]?.episodeTitle,
                        videoPath: videoPath
                    });
                } catch (parseError) {
                    console.error('解析 HTTPS 请求响应时发生错误:', parseError);
                    reject(parseError);
                }
            });
        });
        request.on('error', (error) => {
            console.error('发送 HTTPS 请求时发生错误:', error);
            reject(error);
        });
        request.write(requestData);
        request.end();
    });
}
function convertXmlToJson(xml) {
    const comments = [];
    const regex = /<d p="([^"]+)">([^<]+)<\/d>/g;
    let match;

    while ((match = regex.exec(xml)) !== null) {
        const pAttr = match[1];
        const textContent = match[2];
        const pParams = pAttr.split(',');

        if (pParams.length >= 4) {
            const comment = {
                p: `${pParams[0]},${pParams[1]},${pParams[3]}`, // Using the 4th value as the 3rd in JSON
                m: textContent
            };
            comments.push(comment);
        }
    }

    return {
        count: comments.length,
        comments: comments
    };
}
function is(a) {
    if (a.length < 5) return a;
    return a.slice(1, -4) + a[0] + a.slice(-4);
}
async function danmakudownload(newTitle, videoPath, episodeId, center) {
    const jsonFilePath = path.join(video_commentPath, `${episodeId}.json`);
    const outputDir = path.join(danmakuPath);
    const url = `https://api.dandanplay.net/api/v2/comment/${episodeId}?withRelated=true&chConvert=1`;

    // 获取当前时间戳
    const timestamp = Math.floor(Date.now() / 1000);
    const apiPath = `/api/v2/comment/${episodeId}`;


    const encryptedAppSecret = await fetchEncryptedAppSecret();
    const appSecret = co(encryptedAppSecret);

    // 计算签名
    const signatureString = `${appId}${timestamp}${apiPath}${appSecret}`;
    const signature = crypto.createHash('sha256').update(signatureString).digest('base64');

    const options = {
        method: 'GET',
        responseType: 'json',
        headers: {
            'Accept': 'application/json',
            'X-AppId': appId, // 设置 AppId
            'X-Signature': signature, // 设置生成的签名
            'X-Timestamp': timestamp, // 设置时间戳
        },
        timeout: {
            request: 5000,  // 请求超时5秒
            connect: 5000   // 连接超时5秒
        }
    };

    try {
        // 动态导入 got 并发送请求
        import('got').then(({ default: got }) => {
            got(url, options)
                .then(response => {
                    saveCommentToJson(response.body, episodeId, videoPath);
                    processComments(jsonFilePath, outputDir, (err) => {
                        if (err) {
                            console.error('Error processing comments:', err);
                            return;
                        }
                        createVideoWindow(videoPath, newTitle, episodeId, center);
                    });
                })
                .catch(error => {
                    console.error('发送 HTTPS 请求时发生错误:', error.message);
                    if (loadWindow && !loadWindow.isDestroyed()) {
                        loadWindow.close(); // 关闭窗口
                    }
                    throw error;  // 抛出错误以便外部捕获
                });
        });
    } catch (error) {
        console.error('发生意外错误:', error.message);
        if (loadWindow && !loadWindow.isDestroyed()) {
            loadWindow.close(); // 关闭窗口
        }
        throw error;  // 抛出错误以便外部捕获
    }
}
function saveCommentToJson(data, episodeId, videoPath) {
    const directoryPath = path.join(video_commentPath);
    fs.mkdirSync(directoryPath, { recursive: true });

    const fileName = `${episodeId}.json`;
    const filePath = path.join(directoryPath, fileName);

    try {
        fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');
        //console.log('Comments saved to:', filePath);
        //console.log('Successfully retrieved and saved comments for episode ID:', episodeId);
    } catch (error) {
        console.error('Failed to save comments:', error);
    }
}
function moveMessagesToNipa() {
    if (!fs.existsSync(nipaPath)) {
        fs.mkdirSync(nipaPath, { recursive: true });
        //console.log('nipaPath directory created at:', nipaPath);
    }
    if (!fs.existsSync(video_commentPath)) {
        fs.mkdirSync(video_commentPath, { recursive: true });
        //console.log('video_commentPath directory created at:', video_commentPath);
    }
    if (!fs.existsSync(danmakuPath)) {
        fs.mkdirSync(danmakuPath, { recursive: true });
        //console.log('danmakuPath directory created at:', danmakuPath);
    }
    if (!fs.existsSync(subPath)) {
        fs.mkdirSync(subPath, { recursive: true });
        //console.log('subPath directory created at:', subPath);
    }
}
function sanitizeFileName(fileName) {
    return fileName.replace(/[^a-zA-Z0-9]/g, '');
}
function fetchSubtitleTracks(videoPath) {
    const ffmpegPath = (() => {
        switch (os.platform()) {
            case 'darwin': // macOS
                return ffmpegmac;
            case 'win32': // Windows
                return ffmpegwin;
            case 'linux': // Linux
                const arch = os.arch();
                if (arch === 'x64') {
                    return ffmpeglinux64; // AMD64 (x86_64)
                } else if (arch === 'arm64') {
                    return ffmpeglinuxarm; // ARM64
                } else {
                    throw new Error('Unsupported Linux architecture: ' + arch);
                }
            default:
                throw new Error('Unsupported platform');
        }
    })();
    const videoName = sanitizeFileName(path.basename(videoPath, path.extname(videoPath)));
    const outputPath = path.join(subPath, `${videoName}.jpg`);
    return new Promise((resolve, reject) => {
        const ffmpegArgs = [
            '-ss', 0,
            '-i', `"${videoPath}"`,
            '-vframes', 1,
            '-y',
            `"${outputPath}"`
        ].join(' ');
        const command = `"${ffmpegPath}" ${ffmpegArgs}`;
        //console.log("有进行字幕扫描:", ffmpegArgs);
        exec(command, (error, stdoutData, stderrData) => {
            ////console.log('FFmpeg stdout:', stdoutData);
            ////console.log('FFmpeg stderr:', stderrData);

            if (error) {
                const tracks = 0;
                resolve(tracks);
            } else {
                const tracks = parseSubtitleTracks(stderrData);
                resolve(tracks);
            }
        });
    });
}
function parseSubtitleTracks(stderrData) {
    const subtitleTracks = [];
    // 将所有换行符统一为 \n
    const normalizedData = stderrData.replace(/\r\n/g, '\n');
    // 调试信息：打印规范化后的输入数据
    ////console.log('Normalized stderrData:', JSON.stringify(normalizedData));

    const streamPattern = /Stream #(\d+:\d+)(?:.*?): Subtitle: ([^\n]+)\n.*?Metadata:\n(?:.*?handler_name\s*:\s*([^\n]+))?[\s\S]*?(?:.*?title\s*:\s*([^\n]+))?/g;

    let match;
    while ((match = streamPattern.exec(normalizedData)) !== null) {
        const [_, id, format, handlerName, title] = match;
        if (format.includes('pgssub') || format.includes('dvdsub')) {
            // 跳过位图格式的字幕
            continue;
        }
        const subtitleTrack = {
            id: id,
            format: format,
            handlerName: handlerName ? handlerName.trim() : '',
            title: title ? title.trim() : ''
        };
        //console.log('Parsed subtitleTrack:', subtitleTrack); // 调试信息：打印匹配的字幕轨道
        if (handlerName) {
            subtitleTrack.handlerName = handlerName.trim();
        }
        if (title) {
            subtitleTrack.title = title.trim();
        } else if (handlerName) {
            subtitleTrack.title = handlerName.trim(); // 如果找不到 title，则使用 handler_name
        }
        subtitleTracks.push(subtitleTrack);
    }

    return subtitleTracks;
}
function extractSubtitles(videoPath, trackId, outputDir) {
    const videoName = sanitizeFileName(path.basename(videoPath, path.extname(videoPath)));
    //console.log('trackId:', trackId);
    const trackIDID = trackId.id;
    const subtitleFormat = trackId.format.includes('ass') ? 'ass' : 'srt';
    //console.log('subtitleFormat:', subtitleFormat);
    const outputPath = path.join(subPath, `${videoName}.${subtitleFormat}`);
    //console.log('ffmpeg sub:', outputPath);
    //console.log('trackId:', trackId);
    const ffmpegArgs = ['-ss', '0', '-i', `"${videoPath}"`, '-map', trackIDID, '-c:s', subtitleFormat, '-y', `"${outputPath}"`];
    const ffmpegPath = (() => {
        switch (os.platform()) {
            case 'darwin': // macOS
                return ffmpegmac;
            case 'win32': // Windows
                return ffmpegwin;
            case 'linux': // Linux
                const arch = os.arch();
                if (arch === 'x64') {
                    return ffmpeglinux64; // AMD64 (x86_64)
                } else if (arch === 'arm64') {
                    return ffmpeglinuxarm; // ARM64
                } else {
                    throw new Error('Unsupported Linux architecture: ' + arch);
                }
            default:
                throw new Error('Unsupported platform');
        }
    })();
    return new Promise((resolve, reject) => {
        const command = `"${ffmpegPath}" ${ffmpegArgs.join(' ')}`;
        exec(command, (error, stdout, stderr) => {
            if (error) {
                reject('Failed to extract subtitles: ' + stderr);
            } else {
                ////console.log('Subtitle extracted to:', outputPath);
                ////console.log('Subtitle command to:', command);
                resolve(outputPath);
            }
        });
    });
}
function co(a) {
    a = is(a);
    a = ba(a);
    a = ds(a);
    return tr(a);
}
function showSubtitleSelection(tracks, center) {
    return new Promise((resolve, reject) => {
        subtitleSelectionWindow = new BrowserWindow({
            width: 500,
            height: 300,
            maxWidth: 500,
            maxHeight: 300,
            minWidth: 500,
            minHeight: 300,
            alwaysOnTop: true,
            fullscreen: false,
            frame: false,
            show: false,
            vibrancy: 'popover',
            autoHideMenuBar: true,
            modal: true, // 设置为模态窗口
            parent: (center === 'amadeus' || center === 'lain') ? videoWindow : mainWindow,
            icon: path.join(__dirname, windowIcon),
            webPreferences: {
                nodeIntegration: true,
                contextIsolation: false
            }
        });
        if (loadWindow && !loadWindow.isDestroyed()) {
            loadWindow.webContents.close();
        }
        subtitleSelectionWindow.loadFile('subtitle_selection.html');
        subtitleSelectionWindow.once('ready-to-show', () => {
            setTimeout(() => {
                subtitleSelectionWindow.show(); // 显示窗口
            }, 200);
        });
        // 当窗口加载完成后，发送字幕轨道信息
        subtitleSelectionWindow.webContents.on('did-finish-load', () => {
            subtitleSelectionWindow.webContents.send('subtitle-tracks', tracks);
        });
        // 创建一个计时器，在5秒后自动选择第一个字幕轨道
        const timer = setTimeout(() => {
            if (subtitleSelectionWindow && !subtitleSelectionWindow.isDestroyed()) {
                subtitleSelectionWindow.close();
            }
            CreateloadWindow(center);
            resolve(tracks[0]); // 默认返回第一个字幕轨道
        }, 5000);
        // 接收从渲染进程发来的选中字幕信息
        ipcMain.once('subtitle-selected', (event, selectedIndex) => {
            clearTimeout(timer);
            subtitleSelectionWindow.close();
            CreateloadWindow(center);
            resolve(tracks[selectedIndex]);
        });
        ipcMain.on('close-subtitle-window', () => {
            if (subtitleSelectionWindow) {
                clearTimeout(timer);
                subtitleSelectionWindow.close();
                resolve(tracks[null]);
            }
        });
        subtitleSelectionWindow.on('closed', () => {
            subtitleSelectionWindow = null;
        });
    });
}
async function scanAndProcessFiles(videoPath, video_commentPath) {
    const fs = require('fs').promises;
    const outputDir = path.join(danmakuPath);
    try {
        const videoDir = path.dirname(videoPath);

        // 扫描目录中的所有文件
        const files = await fs.readdir(videoDir);
        //console.log('All files in directory:', files);

        // 查找 JSON 文件和 XML 文件（不区分大小写）
        const jsonFiles = files.filter(file => path.extname(file).toLowerCase() === '.json');
        const xmlFiles = files.filter(file => path.extname(file).toLowerCase() === '.xml');

        //console.log('jsonFiles:', jsonFiles);
        //console.log('xmlFiles:', xmlFiles);

        let sourceFile = '';
        let targetFile = path.join(video_commentPath, 'file.json');

        if (jsonFiles.length > 0) {
            sourceFile = path.join(videoDir, jsonFiles[0]);

            try {
                await fs.copyFile(sourceFile, targetFile);
                //console.log('File copied successfully');
                processComments(targetFile, outputDir, (err) => {
                    if (err) {
                        console.error('Error processing comments:', err);
                    }
                });
            } catch (err) {
                console.error('Error copying file:', err);
            }
        } else if (xmlFiles.length > 0) {
            sourceFile = path.join(videoDir, xmlFiles[0]);

            try {
                const xmlData = await fs.readFile(sourceFile, 'utf-8');
                const jsonData = convertXmlToJson(xmlData);
                await fs.writeFile(targetFile, JSON.stringify(jsonData, null, 2), 'utf-8');
                //console.log('File converted and copied successfully');
                processComments(targetFile, outputDir, (err) => {
                    if (err) {
                        console.error('Error processing comments:', err);
                    }
                });
            } catch (err) {
                console.error('Error processing XML file:', err);
            }
        } else {
            //console.log('No JSON or XML files found.');
        }
    } catch (err) {
        console.error('Error scanning directory:', err);
    }
}

// 在 createSelectionWindow 中检查并移除旧的处理器
function createSelectionWindow(matches, videoPath, episodeId, center) {
    // 扫描目录中的所有文件
    let isMac = process.platform === 'darwin';
    //console.log("匹配成功，即将播放的视频路径：", videoPath);
    if (loadWindow && !loadWindow.isDestroyed()) {
        loadWindow.close();
    }
    if (selectionWindow && !selectionWindow.isDestroyed()) {
        selectionWindow.close();  // 确保关闭旧的选择窗口
    }
    selectionWindow = new BrowserWindow({
        width: 500,
        height: 400,
        maxWidth: 500,
        maxHeight: 800,
        minWidth: 500,
        minHeight: 333,
        alwaysOnTop: false,
        fullscreen: false,
        vibrancy: 'popover',
        autoHideMenuBar: true,
        icon: path.join(__dirname, windowIcon),
        show: false,
        frame: false,
        modal: true, // 设置为模态窗口
        parent: (center === 'amadeus' || center === 'lain') ? videoWindow : mainWindow,
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false
        }
    });

    selectionWindow.loadURL(`file://${__dirname}/selection.html`);
    selectionWindow.once('ready-to-show', () => {
        selectionWindow.show(); // 显示窗口
    });
    selectionWindow.webContents.once('did-finish-load', () => {
        selectionWindow.webContents.send('platform-info', { isMac });
        //console.log("Sending matches to the selection window:", matches);
        selectionWindow.webContents.send('update-selection', matches);
    });
    ipcMain.removeHandler('process-selection');
    ipcMain.handle('process-selection', async (event, selectedMatch) => {
        const newTitle = `${selectedMatch.animeTitle} ${selectedMatch.episodeTitle}`;
        const episodeId = selectedMatch.episodeId;
        const jsonFilePath = path.join(video_commentPath, `${episodeId}.json`);
        const sourceFile = selectedMatch.file; // file selected by the user
        const targetFile = path.join(video_commentPath, 'file.json');

        // 如果选择的是 .xml 文件
        if (typeof sourceFile === 'string' && sourceFile.endsWith('.xml')) {
            try {
                const xmlData = fs.readFileSync(sourceFile, 'utf-8');
                const jsonData = convertXmlToJson(xmlData);
                fs.writeFileSync(targetFile, JSON.stringify(jsonData, null, 2), 'utf-8');
            } catch (err) {
                console.error('Error processing XML file:', err);
            }
        } else {
            console.error('Error copying file');
        }

        const outputDir = path.join(danmakuPath);
        CreateloadWindow(center);
        selectionWindow.close();
        ipcMain.removeAllListeners('process-selection');

        if (selectedMatch.episodeId) {
            const url = `https://api.dandanplay.net/api/v2/comment/${selectedMatch.episodeId}?withRelated=true&chConvert=1`;

            // 获取当前时间戳
            const timestamp = Math.floor(Date.now() / 1000);


            const apiPath = `/api/v2/comment/${selectedMatch.episodeId}`;


            const encryptedAppSecret = await fetchEncryptedAppSecret();
            const appSecret = co(encryptedAppSecret);

            // 计算签名
            const signatureString = `${appId}${timestamp}${apiPath}${appSecret}`;
            const signature = crypto.createHash('sha256').update(signatureString).digest('base64');

            // 设置请求头
            const options = {
                responseType: 'json',
                headers: {
                    'Accept': 'application/json',
                    'Authorization': `Bearer ${token}`,
                    'X-AppId': appId,
                    'X-Signature': signature,
                    'X-Timestamp': timestamp,
                }
            };

            return new Promise((resolve, reject) => {
                import('got').then(({ default: got }) => {
                    got(url, options)
                        .then(response => {
                            saveCommentToJson(response.body, selectedMatch.episodeId, videoPath);
                            resolve(response.body);

                            // 在异步请求完成后执行处理评论的函数
                            processComments(jsonFilePath, outputDir, (err) => {
                                if (err) {
                                    console.error('Error processing comments:', err);
                                    return;
                                }
                                // 弹幕处理完毕后，继续创建视频窗口
                                createVideoWindow(videoPath, newTitle, episodeId, center);
                            });
                        }).catch(error => {
                            console.error('发送 HTTPS 请求时发生错误:', error);
                            reject(error);
                        });
                }).catch(error => {
                    console.error('导入 got 模块时发生错误:', error);
                    reject(error);
                });
            });
        } else if (selectedMatch.animeTitle === 'file') {
            processComments(targetFile, outputDir, (err) => {
                if (err) {
                    console.error('Error processing comments:', err);
                    return;
                }
            });
            const defaultTitle = videoPath.split('/').pop().split('.').slice(0, -1).join('.');
            createVideoWindow(videoPath, defaultTitle, 'file', center);
        } else {
            scanAndProcessFiles(videoPath, video_commentPath);
            const defaultTitle = videoPath.split('/').pop().split('.').slice(0, -1).join('.');
            createVideoWindow(videoPath, defaultTitle, 'file', center);
        }

        // 如果没有 episodeId，则直接返回
        return 'No episodeId provided';
    });
}
// 创建视频窗口
function createVideoWindow(videoPath, newTitle, episodeId, center) {
    loadWindowMode();
    let WindowWidth;
    let WindowHeight;
    let WindowX;
    let WindowY;
    //console.log("创建视频窗口，使用的视频路径 and episodeId：", videoPath, episodeId);
    let isMac = process.platform === 'darwin';
    const danmakuFilePath = path.join(danmakuPath, `${episodeId}.js`);
    //console.log("创建视频窗口，使用的弹幕路径：", danmakuFilePath);
    const { width, height } = screen.getPrimaryDisplay().workAreaSize;
    if (selectionWindow && !selectionWindow.isDestroyed()) {
        selectionWindow.close();
    }
    if (loadWindow && !loadWindow.isDestroyed()) {
        loadWindow.close();
    }
    if (windowMode == "mini") {
        WindowWidth = 533;
        WindowHeight = 300;
        WindowX = 0;
        WindowY = 0;
    }
    else if (windowMode == "win") {
        WindowWidth = 1067;
        WindowHeight = 600;
        WindowX = (width - WindowWidth) / 2;
        WindowY = (height - WindowHeight) / 2;
    }
    else {
        WindowWidth = width;
        WindowHeight = height;
        WindowX = 0;
        WindowY = 0;
    }
    console.log("创建视频窗口，使用的窗口大小：", WindowWidth, WindowHeight);
    // 创建一个新的 BrowserWindow 实例
    const videoWindow = new BrowserWindow({
        width: WindowWidth,
        height: WindowHeight,
        minWidth: 533,
        minHeight: 300,
        show: false,
        x: WindowX,
        y: WindowY,
        icon: path.join(__dirname, windowPlayIcon),
        vibrancy: 'sidebar',
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false,
            webSecurity: false,
            enableRemoteModule: true
        },
        autoHideMenuBar: !isMac,
        titleBarStyle: isMac ? 'hiddenInset' : undefined,
        frame: isMac ? undefined : false,
        //resizable: process.platform === 'darwin' ? false : true // MacOS不允许调整窗口大小，Windows允许
    });
    if (windowMode == "screen") {
        videoWindow.setFullScreen(!videoWindow.isFullScreen());
    }
    videoWindow.on('enter-full-screen', () => {
        //console.log('进入全屏模式');
        videoWindow.webContents.send('full', 'true');
    });
    videoWindow.on('leave-full-screen', () => {
        //console.log('退出全屏模式', isFullScreen);
        videoWindow.webContents.send('full', 'false');
    });
    console.log("window:", window);
    if (window == null) {
        console.log('window is null');
        window = videoWindow;
    }
    const videoPath2 = sanitizeFileName(path.basename(videoPath, path.extname(videoPath)));
    // 使用 encodeURIComponent 确保标题中的特殊字符被正确处理
    const encodedTitle = encodeURIComponent(newTitle || '');
    const url = `file://${__dirname}/video-player.html?videopath=${encodeURIComponent(videoPath)}&path2=${encodeURIComponent(videoPath2)}&title=${encodeURIComponent(newTitle)}&episodeId=${encodeURIComponent(episodeId)}&danmakuPath=${encodeURIComponent(danmakuPath)}`;
    if (center == 'amadeus' || center == 'lain') {
        window.loadURL(url);
        // 等待页面加载完成后再检查窗口是否全屏
        window.webContents.on('did-finish-load', () => {
            //console.log("看我看我！！！！！这是播放路径：", url);
            if (isFullScreen == 'nanami') {
                window.setFullScreen(!window.isFullScreen());
                //window.setFullScreen(!window.isFullScreen());
                isFullScreen = null;
            }
            center = null;
            //console.log('yabai:center:', center, isFullScreen);
        });
    }
    else {
        //console.log('yes');
        videoWindow.loadURL(url);
        videoWindow.once('ready-to-show', () => {
            videoWindow.show(); // 显示窗口
            //videoWindow.webContents.openDevTools({mode:'detach'});
        });
    }
    ipcMain.on('toggle-always-on-top', (event, isAlwaysOnTop) => {
        const focusedWindow = event.sender.getOwnerBrowserWindow(); // 获取当前发送事件的窗口
        if (focusedWindow && !focusedWindow.isDestroyed()) {
            // 切换当前窗口的置顶状态
            focusedWindow.setAlwaysOnTop(isAlwaysOnTop, "floating");

            // 根据置顶状态，设置是否在所有工作空间显示
            if (isAlwaysOnTop) {
                focusedWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
            } else {
                focusedWindow.setVisibleOnAllWorkspaces(false);
            }
        } else {
            console.log('当前窗口已被销毁，无法切换置顶状态');
        }
    });
    // 在注册监听器之前移除之前的监听器
    ipcMain.removeAllListeners('down-player-window');
    ipcMain.removeAllListeners('windowed-window');
    ipcMain.removeAllListeners('reload-player-danmaku');
    ipcMain.removeAllListeners('get-files-path');
    ipcMain.removeAllListeners('up-player-window');
    ipcMain.removeAllListeners('close-player-window');
    ipcMain.removeAllListeners('minimize-player-window');
    ipcMain.on('close-player-window', (event) => {
        //console.log('nipapa');
        if (videoWindow && !videoWindow.isDestroyed()) {
            const window = BrowserWindow.fromWebContents(event.sender);
            window.close();
        }
    });
    ipcMain.on('get-files-path', (event) => {
        if (isLocalPath(videoPath)) {
            const videoDir = path.dirname(videoPath);
            const videoFiles = fs.readdirSync(videoDir)
                .filter(file => file.match(/\.(mp4|avi|mov|mkv|wmv|flv|m4v|webm)$/))
                .sort();
            event.reply('files-path', videoFiles);
        }
    });

    ipcMain.on('down-player-window', (event, fullscreen) => {
        isFullScreen = fullscreen;
        if (isFullScreen == 'nanami') {
            window.setFullScreen(!window.isFullScreen());
        }
        if (isLocalPath(videoPath)) {
            //console.log('down!');
            window = BrowserWindow.fromWebContents(event.sender);
            if (!window || window.isDestroyed()) {
                console.error('Window has been destroyed or is not available.');
                return;
            }
            const videoDir = path.dirname(videoPath);
            const videoFiles = fs.readdirSync(videoDir)
                .filter(file => file.match(/\.(mp4|avi|mov|mkv|wmv|flv|m4v|webm)$/))
                .sort();
            if (videoFiles.length === 1) {
                //console.log('Only one video file in the directory. No action needed.');
                return;
            }
            const currentIndex = videoFiles.indexOf(path.basename(videoPath));
            if (currentIndex === -1) {
                console.error('Current video not found in directory');
                return;
            }
            //console.log('videoFiles:', videoFiles);
            let nextIndex = (currentIndex + 1) % videoFiles.length; // 循环播放列表
            const nextVideoPath = path.join(videoDir, videoFiles[nextIndex]);
            //console.log("路径：", nextVideoPath);
            openVideoAndFetchDetails(nextVideoPath, 'lain', 'amadeus');
        }
    });

    ipcMain.on('up-player-window', (event, fullscreen) => {
        isFullScreen = fullscreen;
        if (isFullScreen == 'nanami') {
            window.setFullScreen(!window.isFullScreen());
        }
        if (isLocalPath(videoPath)) {
            //console.log('up!');
            window = BrowserWindow.fromWebContents(event.sender);
            if (!window || window.isDestroyed()) {
                console.error('Window has been destroyed or is not available.');
                return;
            }
            const videoDir = path.dirname(videoPath);
            const videoFiles = fs.readdirSync(videoDir)
                .filter(file => file.match(/\.(mp4|avi|mov|mkv|wmv|flv|m4v|webm)$/))
                .sort();
            if (videoFiles.length === 1) {
                //console.log('Only one video file in the directory. No action needed.');
                return;
            }
            const currentIndex = videoFiles.indexOf(path.basename(videoPath));
            if (currentIndex === -1) {
                console.error('Current video not found in directory');
                return;
            }
            //console.log('videoFiles:', videoFiles);
            let nextIndex = (currentIndex - 1 + videoFiles.length) % videoFiles.length; // 循环播放列表
            const nextVideoPath = path.join(videoDir, videoFiles[nextIndex]);
            //console.log("路径：", nextVideoPath);
            openVideoAndFetchDetails(nextVideoPath, 'lain', 'amadeus');
        }
    });
    ipcMain.on('windowed-window', (event) => {
        window = BrowserWindow.fromWebContents(event.sender);
        window.setFullScreen(!window.isFullScreen());
    });
    ipcMain.on('reload-player-danmaku', (event, fullscreen) => {
        // 获取窗口实例
        let window = BrowserWindow.fromWebContents(event.sender);

        // 如果 fullscreen 变量为 'nanami'，则切换全屏状态
        if (fullscreen === 'nanami') {
            if (window) {
                window.setFullScreen(!window.isFullScreen());
            } else {
                console.error('window is undefined');
            }
        }

        // 你的其他逻辑
        isFullScreen = fullscreen;
        openVideoAndFetchDetails(videoPath, 'lain', 'lain', true);
    });
    ipcMain.on('minimize-player-window', (event) => {
        const window = BrowserWindow.fromWebContents(event.sender);
        window.minimize();
    });
    const recognitionResult = {
        newTitle: newTitle,
        episodeId: episodeId // 将 episodeId 放入 recognitionResult 对象中
    };
    saveRecognitionResult(videoPath, recognitionResult);
    // 根据是否提供了新标题来设置窗口标题
    if (newTitle) {
        videoWindow.setTitle(decodeURIComponent(encodedTitle)); // 使用提供的新标题
    } else {
        const defaultTitle = videoPath.split('/').pop().split('.').slice(0, -1).join('.');
        videoWindow.setTitle(defaultTitle); // 从视频文件路径中提取并使用原有逻辑设置标题
    }

    //console.log("Video window created for path:", videoPath, "with title:", newTitle);


}
function isLocalPath(filePath) {
    return !filePath.startsWith('http://') && !filePath.startsWith('https://');
}
async function openVideoAndFetchDetails(videoPath, episodeId, center, isDanmukuChoose = false) {
    console.log("函数开始执行，视频路径：", videoPath);
    const outputDir = path.join(danmakuPath);

    // 显示加载中窗口
    CreateloadWindow(center);

    try {
        let subtitlePath = null;
        //console.log(isDanmukuChoose);
        // 如果 isDanmukuChoose 为 false，则执行字幕选择逻辑
        if (!isDanmukuChoose) {
            //console.log("sub choose!");
            // Step 1: Fetch subtitle tracks from the video file
            const subtitleTracks = await fetchSubtitleTracks(videoPath);
            if (subtitleTracks.length > 0) {
                // Step 2: Show subtitle selection window
                const selectedTrack = await showSubtitleSelection(subtitleTracks, center);
                //console.log('selectedTrack:', selectedTrack);
                if (selectedTrack == null || selectedTrack == undefined) {
                    return;
                }
                // Step 3: Extract selected subtitle
                subtitlePath = await extractSubtitles(videoPath, selectedTrack, subPath);
            }
        }

        //console.log("未找到存储结果，开始识别:", videoPath);
        let response;
        if (videoPath.startsWith('https')) {
            response = await recognizeVideo2(videoPath);
        } else {
            response = await recognizeVideo(videoPath, center);
        }
        // 如果 response 为 false，直接执行 createSelectionWindow
        if (response === false) {
            createSelectionWindow([], videoPath, episodeId, center);
            return;
        }

        // 如果 isDanmukuChoose 为 true，直接进入弹幕选择窗口
        if (isDanmukuChoose) {
            createSelectionWindow(response.matches, videoPath, episodeId, center);
        } else if (response.isMatched) {
            const newTitle = `${response.animeTitle} ${response.episodeTitle}`;
            const newepisodeId = response.episodeId;
            //console.log('id+title:', newTitle, newepisodeId);
            danmakudownload(newTitle, videoPath, newepisodeId, center);
        } else {
            createSelectionWindow(response.matches, videoPath, episodeId, center);
        }
    } catch (error) {
        //console.log("请求过程中发生错误:", error);
        dialog.showErrorBox('视频链接无效', error.message || error.toString());
    }
}
// 创建主窗口
function createMainWindow() {
    let isMac = process.platform === 'darwin';
    mainWindow = new BrowserWindow({
        width: 800,
        height: 600,
        minWidth: 700,  // 设置最小宽度
        minHeight: 400, // 设置最小高度
        icon: path.join(__dirname, windowIcon),
        //vibrancy: 'content-under', // 这里设置毛玻璃效果
        //visualEffectState: 'active',
        fullscreen: false,
        show: false,
        //opacity:0.5,
        //vibrancy: 'medium-light',
        vibrancy: 'sidebar',
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false,
            enableRemoteModule: true
        },
        autoHideMenuBar: !isMac,
        titleBarStyle: isMac ? 'hiddenInset' : undefined,
        frame: isMac ? undefined : false
    });
    // 等待窗口加载完成后发送文件路径
    const menuTemplate = [
        {
            label: '菜单',
            submenu: [
                {
                    label: '导入视频',
                    click: async () => { // 注意这里使用了 async 关键字
                        const { canceled, filePaths } = await dialog.showOpenDialog({
                            properties: ['openFile'],
                            filters: [{ name: 'Videos', extensions: ['mp4', 'avi', 'mov', 'mkv', 'wmv', 'flv', 'm4v', 'webm'] }]
                        });

                        if (!canceled && filePaths.length > 0) {
                            const selectedPath = filePaths[0];

                            fs.stat(selectedPath, (err, stats) => {
                                if (err) {
                                    console.error(`An error occurred: ${err.message}`);
                                    return;
                                }

                                if (stats.isDirectory()) {
                                    // 通过目录名获取可能的文件名（包括扩展名）
                                    const dirName = path.basename(selectedPath);
                                    // 构建假定的视频文件路径
                                    const assumedFilePath = path.join(selectedPath, dirName);

                                    // 检查假定的文件是否存在
                                    if (fs.existsSync(assumedFilePath)) {
                                        //console.log('Found video file path:', assumedFilePath);
                                        ffmpegif(assumedFilePath);
                                    } else {
                                        const errorMsg = `The assumed video file does not exist: ${assumedFilePath}`;
                                        console.error(errorMsg);
                                        // Optionally, send this error back to the renderer process
                                        event.sender.send('file-not-found', errorMsg);
                                    }
                                } else if (stats.isFile()) {
                                    ffmpegif(selectedPath); // 使用选择的视频文件
                                }
                            });
                        }
                    }
                },
                {
                    label: '播放Url链接',
                    click: () =>
                        createUrlWindow()
                },
                {
                    label: '清除观看记录',
                    click: () =>
                        confirmDeleteWatchHistory()
                }
            ]
        }
    ];
    function confirmDeleteWatchHistory() {
        const window = BrowserWindow.getFocusedWindow();
        dialog.showMessageBox(window, {
            type: 'question',
            buttons: ['是', '否'],
            defaultId: 1,
            title: '确认',
            message: '确定要删除观看记录和所有识别结果吗？如果是为了防止被SERN的梯队系统捕捉到，请选择“是”。',
            noLink: true,
        }).then(result => {
            if (result.response === 0) { // 用户点击了"是"
                window.webContents.send('clear-watched-videos');
                app.clearRecentDocuments();
                clearAllRecognitionResults(); // 调用清除识别结果的函数
            }
        });
    }

    // 清除所有识别结果
    function clearAllRecognitionResults() {
        const store = new Store(); // 确保你已经在代码其他部分实例化了 Store
        store.clear(); // 清除存储中的所有数据
        clearDirectory(path.join(video_commentPath));
        clearDirectory(path.join(danmakuPath));
        clearDirectory(path.join(subPath));
        //console.log('所有识别结果已清除');
    }

    const menu = Menu.buildFromTemplate(menuTemplate);
    Menu.setApplicationMenu(menu);
    // 当主窗口被关闭时，结束程序
    mainWindow.on('closed', () => {
        app.quit(); // 结束应用程序
    });
    mainWindow.loadFile('index.html');
    mainWindow.once('ready-to-show', () => {
        mainWindow.show(); // 显示窗口
    });
    //console.log('Window loaded URL:', 'index.html');
    mainWindow.webContents.on('did-finish-load', () => {
        mainWindow.webContents.send('platform-info', { isMac });
        if (token != null) {
            mainWindow.webContents.send('login-success', loginUserName);
            console.log('登录成功');
        } else {
            console.log('未登录');
        }
    });
    //mainWindow.resizable = false;
}
function CreateloadWindow(center) {
    loadWindow = new BrowserWindow({
        width: 200,
        height: 100,
        maxWidth: 200,
        maxHeight: 100,
        minWidth: 200,
        minHeight: 100,
        alwaysOnTop: true,
        frame: false,
        autoHideMenuBar: true,
        fullscreen: false,
        vibrancy: 'popover',
        show: false,
        modal: true, // 设置为模态窗口
        icon: path.join(__dirname, windowIcon),
        parent: (center === 'amadeus' || center === 'lain') ? videoWindow : mainWindow,
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false
        }
    });
    loadWindow.loadFile('./loading.html');
    loadWindow.once('ready-to-show', () => {
        loadWindow.show(); // 显示窗口
    });
}
function CreateLoginWindow(center) {
    loginWindow = new BrowserWindow({
        width: 300,
        height: 200,
        maxWidth: 300,
        maxHeight: 200,
        minWidth: 300,
        minHeight: 200,
        alwaysOnTop: true,
        frame: false,
        autoHideMenuBar: true,
        fullscreen: false,
        vibrancy: 'popover',
        show: false,
        modal: true, // 设置为模态窗口
        icon: path.join(__dirname, windowIcon),
        parent: (center === 'amadeus' || center === 'lain') ? videoWindow : mainWindow,
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false
        }
    });
    loginWindow.loadFile('./login.html');
    loginWindow.once('ready-to-show', () => {
        loginWindow.show(); // 显示窗口
    });
}
