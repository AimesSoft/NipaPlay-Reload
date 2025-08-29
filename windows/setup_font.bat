@echo off
echo Setting up Chinese font for Windows build...

REM 复制字体到 assets 目录
if not exist "..\assets\fonts" mkdir "..\assets\fonts"
copy "SourceHanSansCN-Normal.ttf" "..\assets\fonts\SourceHanSansCN-Normal.ttf"
if %errorlevel% neq 0 (
    echo Failed to copy font file
    exit /b 1
)
echo Font file copied to assets/fonts/

REM 备份原始 pubspec.yaml
copy "..\pubspec.yaml" "..\pubspec.yaml.backup"

REM 检查是否已经包含字体配置
findstr /c:"SourceHanSansCN-Normal" "..\pubspec.yaml" >nul
if %errorlevel% equ 0 (
    echo Font already configured in pubspec.yaml
    goto :end
)

REM 使用简单的PowerShell命令添加字体到assets列表
powershell -Command "& {$content = Get-Content '..\pubspec.yaml' -Raw; $newAsset = '    - assets/fonts/SourceHanSansCN-Normal.ttf'; if ($content -match '(?m)^(\s*assets:\s*)$') { $content = $content -replace '(?m)^(\s*assets:\s*)$', ('$1' + \"`n\" + $newAsset); Set-Content '..\pubspec.yaml' -Value $content -Encoding UTF8 -NoNewline; echo 'Font asset added to pubspec.yaml' } else { echo 'Could not find assets section in pubspec.yaml' } }"

if %errorlevel% neq 0 (
    echo Failed to modify pubspec.yaml
    copy "..\pubspec.yaml.backup" "..\pubspec.yaml"
    exit /b 1
)

echo pubspec.yaml updated with font configuration

:end
echo Font setup completed successfully!