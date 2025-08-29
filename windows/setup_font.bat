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

REM 创建临时文件来修改 pubspec.yaml
powershell -Command "$content = Get-Content '..\pubspec.yaml' -Raw; $fontSection = \"`r`n`r`n  fonts:`r`n    - family: SourceHanSansCN`r`n      fonts:`r`n        - asset: assets/fonts/SourceHanSansCN-Normal.ttf`r`n\"; $assetSection = '    - assets/fonts/SourceHanSansCN-Normal.ttf'; if ($content -match 'assets:\s*\r?\n(.*?)\r?\n\s*#') { $beforeAssets = $content.Substring(0, $matches.Index + $matches[0].IndexOf(\"`n\") + 1); $afterMatch = $content.Substring($matches.Index + $matches[0].Length); $afterAssets = \"`n\" + $afterMatch; $newContent = $beforeAssets + $assetSection + $afterAssets; } else { $newContent = $content; } if ($newContent -match '# see https://flutter\.dev/to/font-from-package\s*\r?\n') { $insertPoint = $matches.Index; $newContent = $newContent.Substring(0, $insertPoint) + $fontSection + \"`r`n\" + $newContent.Substring($insertPoint); } $newContent | Set-Content '..\pubspec.yaml' -Encoding UTF8"

if %errorlevel% neq 0 (
    echo Failed to modify pubspec.yaml
    copy "..\pubspec.yaml.backup" "..\pubspec.yaml"
    exit /b 1
)

echo pubspec.yaml updated with font configuration

:end
echo Font setup completed successfully!