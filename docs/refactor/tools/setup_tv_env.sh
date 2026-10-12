#!/usr/bin/env bash
# setup_tv_env.sh — 一次性搭建 TV 模拟器验收环境: JDK17 + emulator + android-tv 系统镜像
set -x
SDK=/d/AndroidSDK
cd "$SDK"

# 1) JDK 17 (huaweicloud mirror)
if [ ! -x "$SDK/jdk-17.0.2/bin/java.exe" ]; then
  curl -L -o jdk17.zip --max-time 1800 https://mirrors.huaweicloud.com/openjdk/17.0.2/openjdk-17.0.2_windows-x64_bin.zip
  unzip -q jdk17.zip -d "$SDK"
  rm jdk17.zip
fi
export JAVA_HOME="D:\\AndroidSDK\\jdk-17.0.2"
export PATH="$SDK/jdk-17.0.2/bin:$PATH"
"$SDK/jdk-17.0.2/bin/java.exe" -version

# 2) 接受许可
yes | "$SDK/cmdline-tools/latest/bin/sdkmanager.bat" --sdk_root="D:\\AndroidSDK" --licenses > /dev/null 2>&1

# 3) emulator + android-tv 系统镜像
"$SDK/cmdline-tools/latest/bin/sdkmanager.bat" --sdk_root="D:\\AndroidSDK" "emulator" "platform-tools" "system-images;android-34;android-tv;x86_64"

echo "SETUP-DONE"
ls "$SDK/emulator/emulator.exe" && find "$SDK/system-images" -maxdepth 3 -type d | head -5
