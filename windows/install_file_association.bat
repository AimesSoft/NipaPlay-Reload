@echo off
setlocal EnableDelayedExpansion

:: 设置脚本为UTF-8编码
chcp 65001 >nul

echo ================================================
echo NipaPlay 文件关联安装工具
echo ================================================
echo.

:: 检查管理员权限
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo 错误: 此脚本需要管理员权限才能运行
    echo 请右键点击此文件，选择"以管理员身份运行"
    echo.
    pause
    exit /b 1
)

:: 获取NipaPlay.exe的路径
set "NIPAPLAY_PATH=%~dp0nipaplay.exe"
if not exist "!NIPAPLAY_PATH!" (
    echo 错误: 找不到NipaPlay.exe文件
    echo 请确保此脚本与NipaPlay.exe在同一目录下
    echo.
    pause
    exit /b 1
)

echo 找到NipaPlay程序: !NIPAPLAY_PATH!
echo.

:: 注册应用程序功能
echo 正在注册应用程序功能...
reg add "HKLM\SOFTWARE\RegisteredApplications" /v "NipaPlay" /t REG_SZ /d "Software\NipaPlay\Capabilities" /f >nul

:: 创建应用程序功能键
reg add "HKLM\SOFTWARE\NipaPlay\Capabilities" /v "ApplicationDescription" /t REG_SZ /d "跨平台本地弹幕视频播放器" /f >nul
reg add "HKLM\SOFTWARE\NipaPlay\Capabilities" /v "ApplicationName" /t REG_SZ /d "NipaPlay" /f >nul

:: 定义支持的文件扩展名
set "extensions=.mp4 .mkv .avi .mov .webm .wmv .m4v .3gp .flv .ts .m2ts"

:: 为每个扩展名创建文件关联
echo 正在配置文件类型关联...
for %%e in (%extensions%) do (
    echo   配置 %%e 文件关联...
    
    :: 添加到应用程序功能
    reg add "HKLM\SOFTWARE\NipaPlay\Capabilities\FileAssociations" /v "%%e" /t REG_SZ /d "NipaPlay.VideoFile" /f >nul
    
    :: 使用assoc和ftype命令设置关联（更兼容的方法）
    ftype NipaPlay.VideoFile="!NIPAPLAY_PATH!" "%%1" >nul 2>&1
)

:: 创建文件类型定义
echo 正在创建文件类型定义...
reg add "HKLM\SOFTWARE\Classes\NipaPlay.VideoFile" /ve /t REG_SZ /d "视频文件" /f >nul
reg add "HKLM\SOFTWARE\Classes\NipaPlay.VideoFile\DefaultIcon" /ve /t REG_SZ /d "\"!NIPAPLAY_PATH!\",0" /f >nul
reg add "HKLM\SOFTWARE\Classes\NipaPlay.VideoFile\shell" /ve /t REG_SZ /d "open" /f >nul
reg add "HKLM\SOFTWARE\Classes\NipaPlay.VideoFile\shell\open" /ve /t REG_SZ /d "使用NipaPlay播放" /f >nul
reg add "HKLM\SOFTWARE\Classes\NipaPlay.VideoFile\shell\open\command" /ve /t REG_SZ /d "\"!NIPAPLAY_PATH!\" \"%%1\"" /f >nul

:: 注册应用程序到"打开方式"菜单
echo 正在注册到打开方式菜单...
reg add "HKLM\SOFTWARE\Classes\Applications\nipaplay.exe" /v "FriendlyAppName" /t REG_SZ /d "NipaPlay" /f >nul

for %%e in (%extensions%) do (
    reg add "HKLM\SOFTWARE\Classes\Applications\nipaplay.exe\SupportedTypes" /v "%%e" /t REG_SZ /d "" /f >nul
)

reg add "HKLM\SOFTWARE\Classes\Applications\nipaplay.exe\shell\open\command" /ve /t REG_SZ /d "\"!NIPAPLAY_PATH!\" \"%%1\"" /f >nul

:: 刷新文件关联缓存
echo 正在刷新系统文件关联缓存...
assoc .mp4 >nul 2>&1
SHChangeNotify >nul 2>&1

echo.
echo ================================================
echo 安装完成！
echo ================================================
echo.
echo NipaPlay已成功注册为以下文件类型的可选打开方式：
for %%e in (%extensions%) do (
    echo   %%e
)
echo.
echo 使用方法：
echo 1. 右键点击任意视频文件
echo 2. 选择"打开方式" ^> "选择其他应用"
echo 3. 选择"NipaPlay"
echo 4. 勾选"始终使用此应用打开此类文件"
echo.
echo 或者在Windows设置中：
echo 设置 ^> 应用 ^> 默认应用 ^> 按文件类型选择默认应用
echo.
pause 