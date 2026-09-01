Unicode true

!ifndef VERSION
  !define VERSION "dev"
!endif
!ifndef STAGE_DIR
  !error "STAGE_DIR is required"
!endif
!ifndef OUTFILE
  !define OUTFILE "zed-arkts-deveco-setup.exe"
!endif

Name "ArkTS DevEco for Zed"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\ArkTSDevEco"
RequestExecutionLevel user
SetCompressor /SOLID lzma
ShowInstDetails show
ShowUninstDetails show

Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

Section "Install"
  SetShellVarContext current

  SetOutPath "$LOCALAPPDATA\Zed\extensions\installed\arkts-deveco"
  File /r "${STAGE_DIR}\*"

  SetOutPath "$INSTDIR"
  File "..\..\LICENSE"
  File "environment-check.ps1"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "DisplayName" "ArkTS DevEco for Zed"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "Publisher" "liuhui-code"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "NoRepair" 1

  IfSilent environment_done 0
    ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\environment-check.ps1" -Mode Check -StatusFile "$INSTDIR\environment-status.ini"' $0
    StrCmp $0 0 environment_done

    ReadINIStr $1 "$INSTDIR\environment-status.ini" "environment" "summary"
    StrCmp $1 "" 0 +2
      StrCpy $1 "无法确认开发环境是否完整。"
    MessageBox MB_YESNO|MB_ICONQUESTION "$1$\r$\n$\r$\n是否现在修复可自动处理的项目？安装器会通过 winget 安装 Zed/Node.js，通过 npm 安装 DevEco CLI；缺少 DevEco Studio/Command Line Tools 时会打开官方下载页。" IDNO environment_declined

    ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\environment-check.ps1" -Mode Repair -StatusFile "$INSTDIR\environment-status.ini"' $2
    StrCmp $2 0 environment_repaired
    ReadINIStr $3 "$INSTDIR\environment-status.ini" "environment" "summary"
    MessageBox MB_OK|MB_ICONEXCLAMATION "已完成可自动处理的更新，但仍需手动完成以下项目：$\r$\n$3"
    Goto environment_done

  environment_repaired:
    MessageBox MB_OK|MB_ICONINFORMATION "开发环境已就绪。"
    Goto environment_done

  environment_declined:
    MessageBox MB_OK|MB_ICONINFORMATION "已跳过环境更新。ArkTS 编辑功能仍可使用；构建和运行任务需在环境就绪后使用。"

  environment_done:
    Delete "$INSTDIR\environment-status.ini"
    MessageBox MB_OK|MB_ICONINFORMATION "ArkTS DevEco 已安装。请重启 Zed，然后打开 .ets 文件。"
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  RMDir /r "$LOCALAPPDATA\Zed\extensions\installed\arkts-deveco"
  RMDir /r "$LOCALAPPDATA\Zed\extensions\work\arkts-deveco"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\environment-check.ps1"
  Delete "$INSTDIR\environment-status.ini"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed"
SectionEnd
