@echo off
setlocal EnableDelayedExpansion

:: 设置脚本为UTF-8编码
chcp 65001 >nul

echo ================================================
echo NipaPlay 文件关联卸载工具
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

echo 正在移除NipaPlay文件关联...
echo.

:: 移除注册的应用程序
echo 正在移除应用程序注册...
reg delete "HKLM\SOFTWARE\RegisteredApplications" /v "NipaPlay" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\NipaPlay" /f >nul 2>&1

:: 移除文件类型定义
echo 正在移除文件类型定义...
reg delete "HKLM\SOFTWARE\Classes\NipaPlay.VideoFile" /f >nul 2>&1

:: 移除应用程序信息
echo 正在移除应用程序信息...
reg delete "HKLM\SOFTWARE\Classes\Applications\nipaplay.exe" /f >nul 2>&1

:: 移除文件类型关联
echo 正在清理文件类型关联...
ftype NipaPlay.VideoFile= >nul 2>&1

:: 刷新文件关联缓存
echo 正在刷新系统文件关联缓存...
assoc .mp4 >nul 2>&1

echo.
echo ================================================
echo 卸载完成！
echo ================================================
echo.
echo NipaPlay的文件关联已成功移除。
echo 如果之前设置了NipaPlay为默认播放器，
echo 请在Windows设置中重新选择其他播放器。
echo.
pause 