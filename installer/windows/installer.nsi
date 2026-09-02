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

  CreateDirectory "$INSTDIR"
  SetOutPath "$PLUGINSDIR"
  File /oname=extension-registration.ps1 "extension-registration.ps1"
  ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\extension-registration.ps1" -Mode Prepare -StateDir "$INSTDIR" -Version "${VERSION}"' $5
  StrCmp $5 0 extension_prepared
    Abort "无法备份和注册 ArkTS 扩展，安装已停止。"
  extension_prepared:

  RMDir /r "$LOCALAPPDATA\Zed\extensions\installed\arkts"
  SetOutPath "$LOCALAPPDATA\Zed\extensions\installed\arkts"
  File /r "${STAGE_DIR}\*"
  RMDir /r "$LOCALAPPDATA\Zed\extensions\installed\arkts-deveco"
  RMDir /r "$LOCALAPPDATA\Zed\extensions\work\arkts-deveco"

  SetOutPath "$INSTDIR"
  File "..\..\LICENSE"
  File "..\..\THIRD_PARTY_NOTICES.md"
  File "environment-check.ps1"
  File "task-registration.ps1"
  File "extension-registration.ps1"
  File "deveco-command.ps1"
  File "deveco-command.cmd"
  File "collect-diagnostics.ps1"
  File "collect-diagnostics.cmd"
  File /oname=arkts-tasks.json "..\..\languages\arkts\tasks.json"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\ArkTS DevEco"
  CreateShortCut "$SMPROGRAMS\ArkTS DevEco\Export Diagnostics.lnk" "$INSTDIR\collect-diagnostics.cmd"

  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "DisplayName" "ArkTS DevEco for Zed"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "Publisher" "liuhui-code"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "NoRepair" 1

  ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\extension-registration.ps1" -Mode Install -StateDir "$INSTDIR" -Version "${VERSION}"' $5
  StrCmp $5 0 extension_registered
    Abort "ArkTS 扩展文件已复制，但 Zed 扩展索引注册失败；安装已停止。"
  extension_registered:

  ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\task-registration.ps1" -Mode Install -StateDir "$INSTDIR" -SourceTasks "$INSTDIR\arkts-tasks.json" -CommandWrapper "$INSTDIR\deveco-command.cmd"' $4
  StrCmp $4 0 tasks_registered
    IfSilent tasks_registered 0
    MessageBox MB_OK|MB_ICONEXCLAMATION "无法把 ArkTS 构建任务注册到 Zed 全局任务文件；为保护已有配置，安装器没有覆盖该文件。打开 .ets 文件后仍可使用扩展自带的语言任务。"
  tasks_registered:

  IfSilent install_done 0
    ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\environment-check.ps1" -Mode Check -StatusFile "$INSTDIR\environment-status.ini"' $0
    StrCmp $0 0 environment_done

    ReadINIStr $1 "$INSTDIR\environment-status.ini" "environment" "summary"
    StrCmp $1 "" 0 +2
      StrCpy $1 "无法确认开发环境是否完整。"
    MessageBox MB_YESNO|MB_ICONQUESTION "$1$\r$\n$\r$\n是否现在修复可自动处理的项目？安装器会通过 winget 安装缺少的 Node.js，并通过 npm 安装缺少的 DevEco CLI。" IDNO environment_declined

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
  install_done:
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  IfFileExists "$INSTDIR\task-registration.ps1" 0 tasks_unregistered
    ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\task-registration.ps1" -Mode Uninstall -StateDir "$INSTDIR"' $4
  tasks_unregistered:
  IfFileExists "$INSTDIR\extension-registration.ps1" 0 extension_unregistered
    ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\extension-registration.ps1" -Mode Uninstall -StateDir "$INSTDIR"' $5
  extension_unregistered:
  RMDir /r "$LOCALAPPDATA\Zed\extensions\installed\arkts-deveco"
  RMDir /r "$LOCALAPPDATA\Zed\extensions\work\arkts-deveco"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\THIRD_PARTY_NOTICES.md"
  Delete "$INSTDIR\environment-check.ps1"
  Delete "$INSTDIR\task-registration.ps1"
  Delete "$INSTDIR\extension-registration.ps1"
  Delete "$INSTDIR\deveco-command.ps1"
  Delete "$INSTDIR\deveco-command.cmd"
  Delete "$INSTDIR\collect-diagnostics.ps1"
  Delete "$INSTDIR\collect-diagnostics.cmd"
  Delete "$INSTDIR\arkts-tasks.json"
  Delete "$INSTDIR\tasks.before-arkts-deveco.json"
  Delete "$INSTDIR\tasks.created-by-arkts-deveco"
  Delete "$INSTDIR\tasks.arkts-deveco.sha256"
  Delete "$INSTDIR\environment-status.ini"
  Delete "$INSTDIR\extension-registration-state.json"
  RMDir /r "$INSTDIR\extension-before-arkts-deveco"
  Delete "$INSTDIR\Uninstall.exe"
  Delete "$SMPROGRAMS\ArkTS DevEco\Export Diagnostics.lnk"
  RMDir "$SMPROGRAMS\ArkTS DevEco"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed"
SectionEnd
