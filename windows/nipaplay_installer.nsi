; NipaPlay NSIS 安装器脚本
; 支持中文界面和现代化UI

; 包含必要的头文件
!include "MUI2.nsh"
!include "FileAssociation.nsh"
!include "x64.nsh"

; 安装器基本信息
Name "NipaPlay"
OutFile "NipaPlay_Setup.exe"
InstallDir "$PROGRAMFILES\NipaPlay"
InstallDirRegKey HKCU "Software\NipaPlay" "InstallDir"
RequestExecutionLevel admin

; 版本信息
VIProductVersion "1.0.0.0"
VIAddVersionKey "ProductName" "NipaPlay"
VIAddVersionKey "CompanyName" "MCDFSteve"
VIAddVersionKey "FileDescription" "NipaPlay 视频播放器安装程序"
VIAddVersionKey "FileVersion" "1.0.0.0"
VIAddVersionKey "ProductVersion" "1.0.0.0"
VIAddVersionKey "LegalCopyright" "© MCDFSteve"

; 现代UI配置
!define MUI_ABORTWARNING
!define MUI_ICON "nipaplay_icon.ico"
!define MUI_UNICON "nipaplay_icon.ico"

; 欢迎页面配置
!define MUI_WELCOMEPAGE_TITLE "欢迎使用 NipaPlay 安装向导"
!define MUI_WELCOMEPAGE_TEXT "此向导将引导您完成 NipaPlay 的安装过程。$\r$\n$\r$\nNipaPlay 是一款功能强大的视频播放器，支持多种视频格式和弹幕功能。$\r$\n$\r$\n点击下一步继续安装。"

; 许可协议页面
!define MUI_LICENSEPAGE_TEXT_TOP "请仔细阅读下列许可协议。"
!define MUI_LICENSEPAGE_TEXT_BOTTOM "如果您接受协议中的条款，请点击我同意继续安装。只有接受协议才能安装 NipaPlay。"
!define MUI_LICENSEPAGE_BUTTON "我同意(&A)"

; 组件选择页面
!define MUI_COMPONENTSPAGE_TEXT_TOP "选择您要安装的组件。"
!define MUI_COMPONENTSPAGE_TEXT_COMPLIST "选择要安装的组件："

; 安装目录页面
!define MUI_DIRECTORYPAGE_TEXT_TOP "安装程序将把 NipaPlay 安装到下列文件夹中。"
!define MUI_DIRECTORYPAGE_TEXT_DESTINATION "安装文件夹"

; 安装进度页面
!define MUI_INSTFILESPAGE_FINISHHEADER_TEXT "安装完成"
!define MUI_INSTFILESPAGE_FINISHHEADER_SUBTEXT "NipaPlay 已成功安装到您的计算机。"
!define MUI_INSTFILESPAGE_ABORTHEADER_TEXT "安装中止"
!define MUI_INSTFILESPAGE_ABORTHEADER_SUBTEXT "安装程序未能完成安装。"

; 完成页面
!define MUI_FINISHPAGE_TITLE "NipaPlay 安装完成"
!define MUI_FINISHPAGE_TEXT "NipaPlay 已成功安装到您的计算机。$\r$\n$\r$\n点击完成关闭此向导。"
!define MUI_FINISHPAGE_RUN "$INSTDIR\NipaPlay.exe"
!define MUI_FINISHPAGE_RUN_TEXT "启动 NipaPlay"

; 卸载确认页面
!define MUI_UNCONFIRMPAGE_TEXT_TOP "您即将从系统中卸载 NipaPlay。"

; 界面背景图片和视觉配置
!define MUI_WELCOMEFINISHPAGE_BITMAP "installer_banner.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "uninstaller_banner.bmp"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP "installer_small.bmp"
!define MUI_HEADERIMAGE_RIGHT

; 许可页面配置
!define MUI_LICENSEPAGE_BGCOLOR FFFFFF

; 界面颜色和外观优化  
!define MUI_BGCOLOR FFFFFF
!define MUI_TEXTCOLOR 000000
!define MUI_INSTFILESPAGE_COLORS "FFFFFF 000000"

; 欢迎页面文字位置调整 (为了配合海报)
!define MUI_WELCOMEPAGE_TITLE_3LINES
!define MUI_WELCOMEPAGE_TEXT_LARGE

; 完成页面文字调整
!define MUI_FINISHPAGE_TITLE_3LINES
!define MUI_FINISHPAGE_TEXT_LARGE

; 自定义GUI初始化函数
!define MUI_CUSTOMFUNCTION_GUIINIT myGUIInit

; 安装器页面配置 (每个页面都会显示配图)
; 欢迎页面 - 显示大海报 (installer_banner.bmp)
!insertmacro MUI_PAGE_WELCOME

; 许可协议页面 - 显示小横幅 (installer_small.bmp)
!insertmacro MUI_PAGE_LICENSE "LICENSE"

; 组件选择页面 - 显示小横幅 (installer_small.bmp)
!insertmacro MUI_PAGE_COMPONENTS

; 安装目录页面 - 显示小横幅 (installer_small.bmp)
!insertmacro MUI_PAGE_DIRECTORY

; 安装进度页面 - 显示小横幅 (installer_small.bmp)
!insertmacro MUI_PAGE_INSTFILES

; 完成页面 - 显示大海报 (installer_banner.bmp)
!insertmacro MUI_PAGE_FINISH

; 卸载器页面配置 (每个页面都会显示配图)
; 卸载欢迎页面 - 显示卸载海报 (uninstaller_banner.bmp)
!insertmacro MUI_UNPAGE_WELCOME

; 卸载确认页面 - 显示小横幅 (installer_small.bmp)
!insertmacro MUI_UNPAGE_CONFIRM

; 卸载进度页面 - 显示小横幅 (installer_small.bmp)
!insertmacro MUI_UNPAGE_INSTFILES

; 卸载完成页面 - 显示卸载海报 (uninstaller_banner.bmp)
!insertmacro MUI_UNPAGE_FINISH

; 语言设置 (必须在页面定义之后)
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"

; 自定义GUI初始化函数实现
Function myGUIInit
  ; 优化窗口显示位置（居中显示）
  System::Call "user32::GetSystemMetrics(i 0) i .r0" ; 获取屏幕宽度
  System::Call "user32::GetSystemMetrics(i 1) i .r1" ; 获取屏幕高度
  IntOp $0 $0 - 500  ; 窗口宽度约500
  IntOp $0 $0 / 2    ; 居中计算
  IntOp $1 $1 - 400  ; 窗口高度约400
  IntOp $1 $1 / 2    ; 居中计算
  
  ; 设置窗口位置居中
  System::Call "user32::SetWindowPos(i $HWNDPARENT, i 0, i r0, i r1, i 0, i 0, i 0x0001)"
FunctionEnd

; 欢迎页面预处理函数
Function WelcomePagePre
  ; 设置窗口为固定大小以确保海报完整显示
  System::Call "user32::SetWindowPos(i $HWNDPARENT, i 0, i 0, i 0, i 512, i 400, i 0x0002)"
FunctionEnd

; 安装器初始化函数
Function .onInit
  ; 检查架构兼容性
  ${If} ${RunningX64}
    ; 64位系统，允许安装
  ${Else}
    ; 32位系统，显示警告
    MessageBox MB_YESNO|MB_ICONQUESTION "检测到您的系统是 32 位，NipaPlay 针对 64 位系统优化。是否继续安装" /SD IDYES IDNO abort
    abort:
      Abort
  ${EndIf}
  
  ; 设置默认语言为中文
  !insertmacro MUI_LANGDLL_DISPLAY
FunctionEnd

; ARM64版本的初始化函数（将在工作流中替换）
Function .onInitARM64
  ; ARM64架构检查
  System::Call "kernel32::GetNativeSystemInfo(p r0)"
  System::Call "*$0(&i2.r1)"
  ${If} $1 = 12  ; PROCESSOR_ARCHITECTURE_ARM64
    ; ARM64系统，允许安装
  ${Else}
    ; 非ARM64系统
    MessageBox MB_OK|MB_ICONSTOP "此安装程序仅适用于 ARM64 架构的设备。$\r$\n请下载 x64 版本的安装程序"
    Abort
  ${EndIf}
  
  ; 设置默认语言为中文
  !insertmacro MUI_LANGDLL_DISPLAY
FunctionEnd

; 安装部分
Section "NipaPlay 主程序" SecMain
  SectionIn RO  ; 必须安装
  
  SetOutPath "$INSTDIR"
  
  ; 安装主程序文件
  File "NipaPlay.exe"
  File /r "data"
  File "*.dll"
  
  ; 创建卸载器
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  
  ; 写入注册表
  WriteRegStr HKCU "Software\NipaPlay" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NipaPlay" "DisplayName" "NipaPlay"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NipaPlay" "UninstallString" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NipaPlay" "Publisher" "MCDFSteve"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NipaPlay" "DisplayIcon" "$INSTDIR\NipaPlay.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NipaPlay" "URLInfoAbout" "https://github.com/MCDFsteve/NipaPlay-Reload"
  
SectionEnd

Section "桌面快捷方式" SecDesktop
  CreateShortcut "$DESKTOP\NipaPlay.lnk" "$INSTDIR\NipaPlay.exe"
SectionEnd

Section "开始菜单快捷方式" SecStartMenu
  CreateDirectory "$SMPROGRAMS\NipaPlay"
  CreateShortcut "$SMPROGRAMS\NipaPlay\NipaPlay.lnk" "$INSTDIR\NipaPlay.exe"
  CreateShortcut "$SMPROGRAMS\NipaPlay\卸载 NipaPlay.lnk" "$INSTDIR\Uninstall.exe"
SectionEnd

Section "文件关联" SecFileAssoc
  ; 注册视频文件关联
  ${RegisterExtension} "$INSTDIR\NipaPlay.exe" ".mp4" "NipaPlay.VideoFile"
  ${RegisterExtension} "$INSTDIR\NipaPlay.exe" ".mkv" "NipaPlay.VideoFile"
  ${RegisterExtension} "$INSTDIR\NipaPlay.exe" ".avi" "NipaPlay.VideoFile"
  ${RegisterExtension} "$INSTDIR\NipaPlay.exe" ".mov" "NipaPlay.VideoFile"
  ${RegisterExtension} "$INSTDIR\NipaPlay.exe" ".wmv" "NipaPlay.VideoFile"
  ${RegisterExtension} "$INSTDIR\NipaPlay.exe" ".flv" "NipaPlay.VideoFile"
  ${RegisterExtension} "$INSTDIR\NipaPlay.exe" ".webm" "NipaPlay.VideoFile"
  ${RegisterExtension} "$INSTDIR\NipaPlay.exe" ".m4v" "NipaPlay.VideoFile"
  ${RegisterExtension} "$INSTDIR\NipaPlay.exe" ".3gp" "NipaPlay.VideoFile"
  ${RegisterExtension} "$INSTDIR\NipaPlay.exe" ".rmvb" "NipaPlay.VideoFile"
  
  ; 刷新文件关联
  System::Call 'shell32.dll::SHChangeNotify(i, i, i, i) v (0x08000000, 0, 0, 0)'
SectionEnd

; 组件描述
LangString DESC_SecMain ${LANG_SIMPCHINESE} "NipaPlay 主程序文件（必需）"
LangString DESC_SecDesktop ${LANG_SIMPCHINESE} "在桌面创建 NipaPlay 快捷方式"
LangString DESC_SecStartMenu ${LANG_SIMPCHINESE} "在开始菜单创建 NipaPlay 程序组"
LangString DESC_SecFileAssoc ${LANG_SIMPCHINESE} "将常见视频格式与 NipaPlay 关联"

LangString DESC_SecMain ${LANG_ENGLISH} "NipaPlay main program files (required)"
LangString DESC_SecDesktop ${LANG_ENGLISH} "Create desktop shortcut for NipaPlay"
LangString DESC_SecStartMenu ${LANG_ENGLISH} "Create start menu group for NipaPlay"
LangString DESC_SecFileAssoc ${LANG_ENGLISH} "Associate video file formats with NipaPlay"

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecMain} $(DESC_SecMain)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} $(DESC_SecDesktop)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecStartMenu} $(DESC_SecStartMenu)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecFileAssoc} $(DESC_SecFileAssoc)
!insertmacro MUI_FUNCTION_DESCRIPTION_END

; 卸载部分
Section "Uninstall"
  
  ; 删除文件
  Delete "$INSTDIR\NipaPlay.exe"
  Delete "$INSTDIR\*.dll"
  RMDir /r "$INSTDIR\data"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  
  ; 删除快捷方式
  Delete "$DESKTOP\NipaPlay.lnk"
  Delete "$SMPROGRAMS\NipaPlay\NipaPlay.lnk"
  Delete "$SMPROGRAMS\NipaPlay\卸载 NipaPlay.lnk"
  RMDir "$SMPROGRAMS\NipaPlay"
  
  ; 删除文件关联
  ${UnRegisterExtension} ".mp4" "NipaPlay.VideoFile"
  ${UnRegisterExtension} ".mkv" "NipaPlay.VideoFile"
  ${UnRegisterExtension} ".avi" "NipaPlay.VideoFile"
  ${UnRegisterExtension} ".mov" "NipaPlay.VideoFile"
  ${UnRegisterExtension} ".wmv" "NipaPlay.VideoFile"
  ${UnRegisterExtension} ".flv" "NipaPlay.VideoFile"
  ${UnRegisterExtension} ".webm" "NipaPlay.VideoFile"
  ${UnRegisterExtension} ".m4v" "NipaPlay.VideoFile"
  ${UnRegisterExtension} ".3gp" "NipaPlay.VideoFile"
  ${UnRegisterExtension} ".rmvb" "NipaPlay.VideoFile"
  
  ; 删除注册表项
  DeleteRegKey HKCU "Software\NipaPlay"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NipaPlay"
  
  ; 刷新文件关联
  System::Call 'shell32.dll::SHChangeNotify(i, i, i, i) v (0x08000000, 0, 0, 0)'
  
SectionEnd 