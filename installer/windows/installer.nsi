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

  IfFileExists "$LOCALAPPDATA\Zed\*" zed_found zed_missing
  zed_missing:
    IfSilent zed_found 0
    MessageBox MB_OK|MB_ICONEXCLAMATION "Zed was not found under %LOCALAPPDATA%\Zed. The extension will be installed and will activate after Zed is installed."
  zed_found:

  SetOutPath "$LOCALAPPDATA\Zed\extensions\installed\arkts-deveco"
  File /r "${STAGE_DIR}\*"

  SetOutPath "$INSTDIR"
  File "..\..\LICENSE"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "DisplayName" "ArkTS DevEco for Zed"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "Publisher" "liuhui-code"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed" "NoRepair" 1

  IfSilent install_done 0
    MessageBox MB_OK|MB_ICONINFORMATION "ArkTS DevEco was installed. Restart Zed, then open an .ets file. The language server downloads automatically on first use."
  install_done:
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  RMDir /r "$LOCALAPPDATA\Zed\extensions\installed\arkts-deveco"
  RMDir /r "$LOCALAPPDATA\Zed\extensions\work\arkts-deveco"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArkTSDevEcoZed"
SectionEnd
