; rl.nsi
;
; This script remembers the directory, has uninstall support and
; (optionally) installs start menu shortcuts.
;
; It will install RoverLog into a directory that the user selects,

;--------------------------------

; The name of the installer
Name "RoverLog"

; The file to write
OutFile "rl.exe"

; The default installation directory
InstallDir C:\RoverLog

; Registry key to check for directory (so if you install again, it will 
; overwrite the old one automatically)
InstallDirRegKey HKLM "Software\RoverLog" "Install_Dir"

;--------------------------------

; Pages

Page components
Page directory
Page instfiles

UninstPage uninstConfirm
UninstPage instfiles

;--------------------------------

; The stuff to install
Section "Tcl/Tk Executable (required)"

  SectionIn RO
  
  ; Set output path to the installation directory.
  SetOutPath $INSTDIR
  
  ; Put files there
  File wishexec.exe
  File log.ico
  
  ; Write the installation path into the registry
  WriteRegStr HKLM SOFTWARE\RoverLog "Install_Dir" "$INSTDIR"

  ; back up old value of .tcl
!define Index "Line${__LINE__}"
  ReadRegStr $1 HKCR ".tcl" ""
  StrCmp $1 "" "${Index}-NoBackup"
    StrCmp $1 "WishScript" "${Index}-NoBackup"
    WriteRegStr HKCR ".tcl" "backup_val" $1
"${Index}-NoBackup:"
  WriteRegStr HKCR ".tcl" "" "WishScript"
  ReadRegStr $0 HKCR "WishScript" ""
  StrCmp $0 "" 0 "${Index}-Skip"
	WriteRegStr HKCR "WishScript" "" "Wish Script"
	WriteRegStr HKCR "WishScript\shell" "" "open"
	WriteRegStr HKCR "WishScript\DefaultIcon" "" "$INSTDIR\log.ico,0"
"${Index}-Skip:"
  WriteRegStr HKCR "WishScript\shell\open\command" "" \
    '$INSTDIR\wishexec.exe "%1"'
!undef Index
  
  ; Write the uninstall keys for Windows
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RoverLog" "DisplayName" "RoverLog"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RoverLog" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RoverLog" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RoverLog" "NoRepair" 1
  WriteUninstaller "uninstall.exe"
  
SectionEnd

Section "Main RoverLog Files"
  
  ; Set output path to the installation directory.
  SetOutPath $INSTDIR
  
  ; Put files there
  File datetime.bat
  File gps.tcl
  File gps.ico
  File inied.tcl
  File inied.ico
  File logheaded2-OBSOLETE.tcl
  File logheaded3.tcl
  File logheaded.ico
  File README.TXT
  File HISTORY.TXT
  File rig.tcl
  File rig.ico
  File rotor.tcl
  File rotor.ico
  File roverclk.tcl
  File roverclk.ico
  File roverlog.tcl
  ; File udp109.dll

SectionEnd

Section "RoverLog Keyer"

  ; Put files there
  File keyer.tcl
  File keyer.ico
  File libsnack.dll
  File QuickMix.exe
  File README_QuickMix.txt

  CreateDirectory "$SMPROGRAMS\RoverLog"
  CreateShortCut "$SMPROGRAMS\RoverLog\RoverLog Keyer.lnk" "$INSTDIR\wishexec.exe" "keyer.tcl" "$INSTDIR\keyer.ico" 0
  CreateShortCut "$DESKTOP\RoverLog Keyer.lnk" "$INSTDIR\wishexec.exe" "keyer.tcl" "$INSTDIR\keyer.ico" 0

SectionEnd

Section "RoverLog Super Lookup"

  ; Put files there
  File super.tcl
  File super.ico
  File pij.mk 
  File Mk4tcl.dll

  CreateDirectory "$SMPROGRAMS\RoverLog"
  CreateShortCut "$SMPROGRAMS\RoverLog\RoverLog Super Lookup.lnk" "$INSTDIR\wishexec.exe" "super.tcl" "$INSTDIR\super.ico" 0
  CreateShortCut "$DESKTOP\RoverLog Super Lookup.lnk" "$INSTDIR\wishexec.exe" "super.tcl" "$INSTDIR\super.ico" 0

SectionEnd

Section "Contest .ini Files (overwrites any old files)"

  ; Put files there
  File auguhf.ini
  File auguhfbasic.ini
  File auguhf-dist.ini
  File cqvhf.ini
  File janvhf.ini
  File janvhfbasic.ini
  File junvhf.ini
  File junvhfbasic.ini
  File sepvhf.ini
  File sepvhfbasic.ini
  File sprint50.ini
  File sprint144.ini
  File sprint222.ini
  File sprint432.ini
  File sprintmicro.ini
  File 10g.ini

SectionEnd

Section "Distance-based Sprint Contest .ini Files (overwrites any old files)"

  ; Put files there
  File sprint50dx.ini
  File sprint144dx.ini
  File sprint222dx.ini
  File sprint432dx.ini
  File sprintmicrodx.ini

SectionEnd

Section "Module .ini Files (overwrites any old files)"

  ; Put files there
  File gps.ini
  File rig.ini
  File rotor.ini

SectionEnd

Section "Example roverlog.ini Files (roverlog_xxx.ini)"

  ; Put files there
  File roverlog_rover.ini
  File roverlog_multiop-144.ini
  File roverlog_multiop-other.ini
  File roverlog_singleop.ini

SectionEnd

Section "Iopwr parallel port band switching aid"

  ; Put files there
  File iopwr.exe
  File README_iopwr.txt
  File inpout32.dll
  File iopwr.c

SectionEnd

Section "Generic serial port band switching aid"

  ; Put files there
  File serout.bat
  File README_serout.txt

SectionEnd

Section "VE2PIJ RoverLog Lookup Database (pij.lup)"

  ; Put files there
  File pij.lup

SectionEnd

; Optional section (can be disabled by the user)
Section "Start Menu Shortcuts"

  CreateDirectory "$SMPROGRAMS\RoverLog"
  CreateShortCut "$SMPROGRAMS\RoverLog\Uninstall.lnk" "$INSTDIR\uninstall.exe" "" "$INSTDIR\uninstall.exe" 0
  CreateShortCut "$SMPROGRAMS\RoverLog\Rotor Server.lnk" "$INSTDIR\wishexec.exe" "rotor.tcl" "$INSTDIR\rotor.ico" 0
  CreateShortCut "$SMPROGRAMS\RoverLog\GPS Server.lnk" "$INSTDIR\wishexec.exe" "gps.tcl" "$INSTDIR\gps.ico" 0
  CreateShortCut "$SMPROGRAMS\RoverLog\Rig Server.lnk" "$INSTDIR\wishexec.exe" "rig.tcl" "$INSTDIR\rig.ico" 0
  CreateShortCut "$SMPROGRAMS\RoverLog\Clock.lnk" "$INSTDIR\wishexec.exe" "roverclk.tcl" "$INSTDIR\roverclk.ico" 0
  CreateShortCut "$SMPROGRAMS\RoverLog\RoverLog.lnk" "$INSTDIR\wishexec.exe" "roverlog.tcl" "$INSTDIR\log.ico" 0
  CreateShortCut "$SMPROGRAMS\RoverLog\Ini Editor.lnk" "$INSTDIR\wishexec.exe" "inied.tcl" "$INSTDIR\inied.ico" 0
  CreateShortCut "$SMPROGRAMS\RoverLog\Log Header Editor - Version 3.lnk" "$INSTDIR\wishexec.exe" "logheaded3.tcl" "$INSTDIR\logheaded.ico" 0
  
SectionEnd

Section "Desktop Shortcuts"

  CreateShortCut "$DESKTOP\RoverLog.lnk" "$INSTDIR\wishexec.exe" "roverlog.tcl" "$INSTDIR\log.ico" 0
  CreateShortCut "$DESKTOP\IniEd.lnk" "$INSTDIR\wishexec.exe" "inied.tcl" "$INSTDIR\inied.ico" 0
  CreateShortCut "$DESKTOP\RoverLog Folder.lnk" "$INSTDIR"

SectionEnd

;--------------------------------

; Uninstaller

Section "Uninstall"
  
  ; Remove registry keys
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RoverLog"
  DeleteRegKey HKLM SOFTWARE\RoverLog

  ;start of restore script
!define Index "Line${__LINE__}"
  ReadRegStr $1 HKCR ".tcl" ""
  StrCmp $1 "WishScript" 0 "${Index}-NoOwn" ; only do this if we own it
    ReadRegStr $1 HKCR ".tcl" "backup_val"
    StrCmp $1 "" 0 "${Index}-Restore" ; if backup="" then delete the whole key
      DeleteRegKey HKCR ".tcl"
    Goto "${Index}-NoOwn"
"${Index}-Restore:"
      WriteRegStr HKCR ".tcl" "" $1
      DeleteRegValue HKCR ".tcl" "backup_val"
   
    DeleteRegKey HKCR "WishScript" ;Delete key with association settings

"${Index}-NoOwn:"
!undef Index

  ; Remove files and uninstaller
  Delete $INSTDIR\auguhf.ini
  Delete $INSTDIR\auguhfbasic.ini
  Delete $INSTDIR\auguhf-dist.ini
  Delete $INSTDIR\cqvhf.ini
  Delete $INSTDIR\datetime.bat
  Delete $INSTDIR\gps.ini
  Delete $INSTDIR\gps.tcl
  Delete $INSTDIR\inied.tcl
  Delete $INSTDIR\janvhf.ini
  Delete $INSTDIR\janvhfbasic.ini
  Delete $INSTDIR\junvhf.ini
  Delete $INSTDIR\junvhfbasic.ini
  Delete $INSTDIR\keyer.tcl
  Delete $INSTDIR\libsnack.dll
  Delete $INSTDIR\log.ico
  Delete $INSTDIR\gps.ico
  Delete $INSTDIR\inied.ico
  Delete $INSTDIR\logheaded.ico
  Delete $INSTDIR\rig.ico
  Delete $INSTDIR\keyer.ico
  Delete $INSTDIR\rotor.ico
  Delete $INSTDIR\roverclk.ico
  Delete $INSTDIR\logheaded.tcl
  Delete $INSTDIR\logheaded2-OBSOLETE.tcl
  Delete $INSTDIR\logheaded3.tcl
  Delete $INSTDIR\makensisw.exe
  Delete $INSTDIR\pij.lup
  Delete $INSTDIR\QuickMix.exe
  Delete $INSTDIR\README.TXT
  Delete $INSTDIR\HISTORY.TXT
  Delete $INSTDIR\README_QuickMix.txt
  Delete $INSTDIR\rig.ini
  Delete $INSTDIR\rig.tcl
  Delete $INSTDIR\rotor.ini
  Delete $INSTDIR\rotor.tcl
  Delete $INSTDIR\roverclk.tcl
  Delete $INSTDIR\roverlog.tcl
  Delete $INSTDIR\roverlog_rover.ini
  Delete $INSTDIR\roverlog_multiop-144.ini
  Delete $INSTDIR\roverlog_multiop-other.ini
  Delete $INSTDIR\roverlog_singleop.ini
  Delete $INSTDIR\sepvhf.ini
  Delete $INSTDIR\sepvhfbasic.ini
  Delete $INSTDIR\sprint50.ini
  Delete $INSTDIR\sprint50dx.ini
  Delete $INSTDIR\sprint144.ini
  Delete $INSTDIR\sprint144dx.ini
  Delete $INSTDIR\sprint222.ini
  Delete $INSTDIR\sprint222dx.ini
  Delete $INSTDIR\sprint432.ini
  Delete $INSTDIR\sprint432dx.ini
  Delete $INSTDIR\sprintmicro.ini
  Delete $INSTDIR\sprintmicrodx.ini
  Delete $INSTDIR\10g.ini
  Delete $INSTDIR\uninstall.exe
  Delete $INSTDIR\wishexec.exe
  Delete $INSTDIR\iopwr.exe
  Delete $INSTDIR\README_iopwr.txt
  Delete $INSTDIR\inpout32.dll
  Delete $INSTDIR\iopwr.c
  Delete $INSTDIR\serout.bat
  Delete $INSTDIR\README_serout.txt
  Delete $INSTDIR\Mk4tcl.dll
  Delete $INSTDIR\udp109.dll
  Delete $INSTDIR\super.tcl
  Delete $INSTDIR\super.ico
  Delete $INSTDIR\pij.mk

  ; Remove shortcuts, if any
  Delete "$DESKTOP\IniEd.lnk"
  Delete "$DESKTOP\RoverLog.lnk"
  Delete "$DESKTOP\RoverLog Folder.lnk"
  Delete "$DESKTOP\RoverLog Keyer.lnk"
  Delete "$DESKTOP\RoverLog Super Lookup.lnk"
  Delete "$SMPROGRAMS\RoverLog\*.*"

  ; Remove directories used
  RMDir "$SMPROGRAMS\RoverLog"
  RMDir "$INSTDIR"

SectionEnd
