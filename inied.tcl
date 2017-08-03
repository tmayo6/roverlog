#!/bin/sh
# the next line restarts using wish \
exec wish "$0" "$@"

proc About { } {
  global stuff

  tk_messageBox -icon info -type ok -title About \
    -message "RoverLog Ini File Editor version $::setting(iniversion)
by Tom Mayo

It's not just for rovers!

http://roverlog.2ub.org/"
}

proc Setup_Options_Table { } {
  global title table

  set title(0) "Station Information"
  set table(0,0) [ list "mycall"     "Callsign" "entry" "\"" "\"" ]
  set table(0,1) [ list "mygrid"     "Default Grid" "entry" "\"" "\"" ]
  set table(0,2) [ list "allowstationchanges" "Allow My Call and Sent Changes" "menu" [ list 0 1 ] " " " " ]
  set table(0,3) [ list "myband"     "Default Band" "menu" [ list NONE 50 144 222 432 902 1.2G 2.3G 3.4G 5.7G 10G 24G 47G 76G 119G 142G 241G 300G ] "\"" "\"" ]
  set table(0,4) [ list "bandlock"   "Band Lock" "menu" [ list 0 1 ] " " " " ]
  set table(0,5) [ list "mymode"     "Default Mode" "menu" [ list NO PH CW FM RY] "\"" "\"" ]
  set table(0,6) [ list "buds"       "Buddy Calls" "entry" "\"" "\"" ]
  set table(0,7) [ list "declination" "Declination (deg): + = East, - = West" "entry" "\"" "\"" ]
  set table(0,8) [ list "antoffset"  "Default Ant Offset (deg): + = CW, - = CCW" "entry" "\"" "\"" ]

  set title(1) "Files"
  set table(1,0) [ list "logfile"    "Log File Name" "entry" "\"" "\"" ]
  set table(1,1) [ list "lookupfile" "Lookup File Name" "entry" "\"" "\"" ]
  set table(1,2) [ list "weblookup" "Web Lookup Service" "menu" [ list Buckmaster AE7Q Hamdata QRZ ] "\"" "\"" ]
  set table(1,3) [ list "contestini" "Contest .ini File" "menu" [ list janvhf.ini janvhfbasic.ini junvhf.ini junvhfbasic.ini auguhf-dist.ini auguhf.ini auguhfbasic.ini sepvhf.ini sepvhfbasic.ini cqvhf.ini sprint50.ini sprint144.ini sprint222.ini sprint432.ini sprintmicro.ini 10g.ini ] "\"" "\"" ]
  set table(1,4) [ list "autosave"   "Auto Save Interval (QSOs)" "menu" [ list 0 1 2 5 10 ] " " " " ]

  set title(2) "Display"
  set table(2,0) [ list "font"          "Default Font: <Font> <Size> {<Face>}" "entry" "{" "}" ]
  set table(2,1) [ list "entryfont"     "Entry Font: <Font> <Size> {<Face>}" "entry" "{" "}" ]
  set table(2,2) [ list "bigfont"       "Main Entry Font: <Font> <Size> {<Face>}" "entry" "{" "}" ]
  set table(2,3) [ list "maintop"       "Main Window Stays on Top" "menu" [ list 0 1 ] " " " " ]
  set table(2,4) [ list "listheight"    "Log List Height (lines)" "rangemenu" 1 21 1 " " " " ]
  set table(2,5) [ list "clearentry"    "Clear Entry After Logging" "menu" [ list 0 1 ] " " " " ]
  set table(2,6) [ list "lookupgrid"    "Allow Grid Lookup For Unworked Stations" "menu" [ list 0 1 ] " " " " ]
  set table(2,7) [ list "callcheck"     "Check Callsign Before Logging" "menu" [ list none lax strict ] " " " " ]
  set table(2,8) [ list "allowcompass"  "Allow Compass Display" "menu" [ list 0 1 ] " " " " ]
  set table(2,9) [ list "allowsort"     "Allow Log Sorting" "menu" [ list 0 1 ] " " " " ]
  set table(2,10) [ list "warnrealtime"  "Warn When Logging Manual Times" "menu" [ list 0 1 ] " " " " ]
  set table(2,11) [ list "quicklookup"  "Return To Call Entry After Lookup Copy" "menu" [ list 0 1 ] " " " " ]
  set table(2,12) [ list "annbell"      "Sound Bell For Annunciator Messages" "menu" [ list 0 1 ] " " " " ]
  set table(2,13) [ list "lookupquiet"  "Supress response for Super Lookup" "menu" [ list 0 1 ] " " " " ]
  set table(2,14) [ list "mapwidth"     "Map Width" "menu" [ list 11 13 15 17 19 ] " " " " ]
  set table(2,15) [ list "mapheight"    "Map Height" "menu" [ list 7 9 11 13 15 17 19 21 23 ] " " " " ]

  set title(3) "Colors"
  set table(3,0) [ list "logfg"          "Log Foreground" "entry" "\"" "\"" ]
  set table(3,1) [ list "logbg"          "Log Background" "entry" "\"" "\"" ]
  set table(3,2) [ list "lognewfg"       "Log Foreground for New Mults" "entry" "\"" "\"" ]
  set table(3,3) [ list "lognewbg"       "Log Background for New Mults" "entry" "\"" "\"" ]
  set table(3,4) [ list "lognetfg"       "Log Foreground for Net" "entry" "\"" "\"" ]
  set table(3,5) [ list "lognetbg"       "Log Background for Net" "entry" "\"" "\"" ]
  set table(3,6) [ list "lognetnewfg"    "Log Foreground for Net New Mults" "entry" "\"" "\"" ]
  set table(3,7) [ list "lognetnewbg"    "Log Background for Net New Mults" "entry" "\"" "\"" ]
  set table(3,8) [ list "mapcoldbg"      "Map Cold Background" "entry" "\"" "\"" ]
  set table(3,9) [ list "mapcoldfg"      "Map Cold Foreground" "entry" "\"" "\"" ]
  set table(3,10) [ list "mapwarmbg"     "Map Warm Background" "entry" "\"" "\"" ]
  set table(3,11) [ list "mapwarmfg"     "Map Warm Foreground" "entry" "\"" "\"" ]
  set table(3,12) [ list "maphotbg"      "Map Hot Background" "entry" "\"" "\"" ]
  set table(3,13) [ list "maphotfg"      "Map Hot Foreground" "entry" "\"" "\"" ]
  set table(3,14) [ list "mapunwkbg"     "Map Unworked Background" "entry" "\"" "\"" ]
  set table(3,15) [ list "mapunwkfg"     "Map Unworked Foreground" "entry" "\"" "\"" ]
  set table(3,16) [ list "madeskedcolor" "Color for Made Skeds" "entry" "\"" "\"" ]
  set table(3,17) [ list "txcolor"       "Clock Transmit Background" "entry" "\"" "\"" ]
  set table(3,18) [ list "txfgcolor"     "Clock Transmit Foreground" "entry" "\"" "\"" ]
  set table(3,19) [ list "rxcolor"       "Clock Receive Background" "entry" "\"" "\"" ]
  set table(3,20) [ list "rxfgcolor"     "Clock Receive Foreground" "entry" "\"" "\"" ]

  set title(4) "Modules to Start"
  set table(4,0) [ list "Start_Keyer"    "Keyer"        "menu" [ list 0 1 ] " " " " ]
  set table(4,1) [ list "Start_Super"    "Super Lookup" "menu" [ list 0 1 ] " " " " ]
  set table(4,2) [ list "Start_Rotor"    "Rotor"        "menu" [ list 0 1 ] " " " " ]
  set table(4,3) [ list "Start_Rig"      "Rig"          "menu" [ list 0 1 ] " " " " ]
  set table(4,4) [ list "Start_GPS"      "GPS"          "menu" [ list 0 1 ] " " " " ]
  set table(4,5) [ list "Start_Clock"    "Clock"        "menu" [ list 0 1 ] " " " " ]

  set title(5) "Rig Setup"
  set table(5,0)  [ list "RoverLog_Rig"  "RoverLog or Rig Controls Changes" "menu" [ list RoverLog Rig ] " " " " ]
  set table(5,1)  [ list "r1"            "Rig Band 1: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>"  "entry" "{" "}" ]
  set table(5,2)  [ list "r2"            "Rig Band 2: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>"  "entry" "{" "}" ]
  set table(5,3)  [ list "r3"            "Rig Band 3: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>"  "entry" "{" "}" ]
  set table(5,4)  [ list "r4"            "Rig Band 4: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>"  "entry" "{" "}" ]
  set table(5,5)  [ list "r5"            "Rig Band 5: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>"  "entry" "{" "}" ]
  set table(5,6)  [ list "r6"            "Rig Band 6: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>"  "entry" "{" "}" ]
  set table(5,7)  [ list "r7"            "Rig Band 7: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>"  "entry" "{" "}" ]
  set table(5,8)  [ list "r8"            "Rig Band 8: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>"  "entry" "{" "}" ]
  set table(5,9)  [ list "r9"            "Rig Band 9: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>"  "entry" "{" "}" ]
  set table(5,10)  [ list "r10"           "Rig Band 10: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>" "entry" "{" "}" ]
  set table(5,11) [ list "r11"           "Rig Band 11: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>" "entry" "{" "}" ]
  set table(5,12) [ list "r12"           "Rig Band 12: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>" "entry" "{" "}" ]
  set table(5,13) [ list "r13"           "Rig Band 13: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>" "entry" "{" "}" ]
  set table(5,14) [ list "r14"           "Rig Band 14: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>" "entry" "{" "}" ]
  set table(5,15) [ list "r15"           "Rig Band 15: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>" "entry" "{" "}" ]
  set table(5,16) [ list "r16"           "Rig Band 16: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>" "entry" "{" "}" ]
  set table(5,17) [ list "r17"           "Rig Band 17: <Band> <Rig 1/2> <Rig Server IP Port> <LO Freq> <QSY Command>" "entry" "{" "}" ]

  set title(6) "Keyer/Super/GPS/Rotor Setup"
  set table(6,0) [ list "fkeys"        "Fn Key 1 to 11 Operation" "menu" [ list "Keyer" "QSY" ] " " " " ]
  set table(6,1) [ list "rigdvr"       "F7-F9 Trigger Rig DVR Play 1-3" "menu" [ list "0" "1" ] " " " " ]
  set table(6,2) [ list "keyeripaddr"  "Keyer IP Address" "entry" "{" "}" ]
  set table(6,3) [ list "keyeripport"  "Keyer IP Port" "entry" "{" "}" ]
  set table(6,4) [ list "superipaddr"  "Super Lookup IP Address" "entry" "{" "}" ]
  set table(6,5) [ list "superipport"  "Super Lookup IP Port" "entry" "{" "}" ]
  set table(6,6) [ list "gps"          "Get Info from GPS Server" "menu" [ list 0 1 ] " " " " ]
  set table(6,7) [ list "gpsipaddr"    "GPS Server IP Address" "entry" "{" "}" ]
  set table(6,8) [ list "gpsipport"    "GPS Server IP Port" "entry" "{" "}" ]
  set table(6,9) [ list "rotoripaddr"  "Rotor Server IP Address" "entry" "{" "}" ]
  set table(6,10) [ list "rotoripport"  "Rotor Server IP Port" "entry" "{" "}" ]

  set title(7) "Sked Setup"
  set table(7,0) [ list "skedqsy"    "Default Post-Sked QSY Action" "rangemenu" -1 2 1 " " " " ]
  set table(7,1) [ list "quicksked"  "Return to Call Entry After Making Sked or Pass" "menu" [ list 0 1 ] " " " " ]
  set table(7,2) [ list "skedtinc"   "Default Time Increment (minutes)" "rangemenu" 5 65 5 " " " " ]
  set table(7,3) [ list "wiplimit"   "Limit of queued stations to work" "rangemenu" 1 11 1 " " " " ]
  set table(7,4) [ list "wipbusy"    "Minutes to Mark Me Busy After Accepting WIP" "menu" [ list 0 1 2 3 4 5 10 15 20 30 ] " " " " ]
  set table(7,5) [ list "txminute"   "Transmit on Minute" "menu" [ list "odd" "even" ] " " " " ]
  set table(7,6) [ list "earlywarn"  "Advance warning for skeds (min)" "menu" [ list 0 1 2 3 4 5 10 15 20 ] " " " " ]
  set table(7,7) [ list "autoreap"  "Automatically reap skeds when QSO made" "menu" [ list 0 1 ] " " " " ]

  set title(8) "Networking"
  set table(8,0)  [ list "netenable"  "Net Enable" "menu" [ list 0 1 ] " " " " ]
  set table(8,1)  [ list "netpopup"   "Message Popup" "menu" [ list 0 1 ] " " " " ]
  set table(8,2)  [ list "passprompt" "Pass Prompt" "menu" [ list 0 1 ] " " " " ]
  set table(8,3)  [ list "verbnetlog" "Verbose Logging" "menu" [ list 0 1 ] " " " " ]
  set table(8,4)  [ list "quicknet"   "Return to Call Entry After Net Message" "menu" [ list 0 1 ] " " " " ]
  set table(8,5)  [ list "netlogheight" "Network Log Height" "rangemenu" 1 21 1 " " " " ]
  set table(8,6)  [ list "mypeername" "My Peer Name" "entry" "\"" "\"" ]
  set table(8,7)  [ list "p1"         "Peer 1: <Peer Name> <Host Name or IP Addr> <IP Port> <Bands...>"  "entry" "{" "}" ]
  set table(8,8)  [ list "p2"         "Peer 2: <Peer Name> <Host Name or IP Addr> <IP Port> <Bands...>"  "entry" "{" "}" ]
  set table(8,9)  [ list "p3"         "Peer 3: <Peer Name> <Host Name or IP Addr> <IP Port> <Bands...>"  "entry" "{" "}" ]
  set table(8,10)  [ list "p4"         "Peer 4: <Peer Name> <Host Name or IP Addr> <IP Port> <Bands...>"  "entry" "{" "}" ]
  set table(8,11)  [ list "p5"         "Peer 5: <Peer Name> <Host Name or IP Addr> <IP Port> <Bands...>"  "entry" "{" "}" ]
  set table(8,12)  [ list "p6"         "Peer 6: <Peer Name> <Host Name or IP Addr> <IP Port> <Bands...>"  "entry" "{" "}" ]
  set table(8,13) [ list "p7"         "Peer 7: <Peer Name> <Host Name or IP Addr> <IP Port> <Bands...>"  "entry" "{" "}" ]
  set table(8,14) [ list "p8"         "Peer 8: <Peer Name> <Host Name or IP Addr> <IP Port> <Bands...>"  "entry" "{" "}" ]
  set table(8,15) [ list "p9"         "Peer 9: <Peer Name> <Host Name or IP Addr> <IP Port> <Bands...>"  "entry" "{" "}" ]
  set table(8,16) [ list "p10"        "Peer 10: <Peer Name> <Host Name or IP Addr> <IP Port> <Bands...>" "entry" "{" "}" ]
  set table(8,17) [ list "p11"        "Peer 11: <Peer Name> <Host Name or IP Addr> <IP Port> <Bands...>" "entry" "{" "}" ]
  set table(8,18) [ list "p12"        "Peer 12: <Peer Name> <Host Name or IP Addr> <IP Port> <Bands...>" "entry" "{" "}" ]
}

Setup_Options_Table

proc My_Exit { } {
  set yesno [ tk_messageBox -icon question -type yesno \
    -title "Save Settings?" -message "Click \"Yes\" to save before exiting, or \"No\" to exit without saving." ]
  if { $yesno == "yes" } {
    Save_File
  }
  exit
}

proc Build_Frame { i } {
  global title table

  destroy .f.f
  frame .f.f

  for { set j 0 } { [ info exists table($i,$j) ] } { incr j } {
    set t [ lindex $table($i,$j) 2 ]
    if { $t == "entry" } {
      label .f.f.l$j -text [ lindex $table($i,$j) 1 ]
      entry .f.f.e$j -width 32 -textvariable ::setting([ lindex $table($i,$j) 0 ])
      grid .f.f.l$j .f.f.e$j
      grid .f.f.l$j -sticky e -padx 3 -pady 3
      grid .f.f.e$j -sticky w -padx 3 -pady 3
    } elseif { $t == "menu" } {
      menubutton .f.f.mb$j -text [ lindex $table($i,$j) 1 ] -menu .f.f.mb$j.menu -relief raised
      menu .f.f.mb$j.menu -tearoff 0
      foreach b [ lindex $table($i,$j) 3 ] {
        .f.f.mb$j.menu add radiobutton -label $b -variable ::setting([ lindex $table($i,$j) 0 ])
      }
      entry .f.f.e$j -width 32 -textvariable ::setting([ lindex $table($i,$j) 0 ])
      grid .f.f.mb$j .f.f.e$j
      grid .f.f.mb$j -sticky e -padx 3 -pady 3
      grid .f.f.e$j -sticky w -padx 3 -pady 3
    } elseif { $t == "rangemenu" } {
      menubutton .f.f.mb$j -text [ lindex $table($i,$j) 1 ] -menu .f.f.mb$j.menu -relief raised
      menu .f.f.mb$j.menu -tearoff 0
      for { set b [ lindex $table($i,$j) 3 ] } { $b != [ lindex $table($i,$j) 4 ] } { incr b [ lindex $table($i,$j) 5 ] } {
        .f.f.mb$j.menu add radiobutton -label $b -variable ::setting([ lindex $table($i,$j) 0 ])
      }
      entry .f.f.e$j -width 32 -textvariable ::setting([ lindex $table($i,$j) 0 ])
      grid .f.f.mb$j .f.f.e$j
      grid .f.f.mb$j -sticky e -padx 3 -pady 3
      grid .f.f.e$j -sticky w -padx 3 -pady 3
    }
  }
  pack .f.f
  pack .f
}

proc Save_File { } {
  global stuff title table

  set fid [ open "roverlog.ini" w 0666 ]
  puts $fid "set ::setting(iniversion) \"$::setting(iniversion)\""

  for { set i 0 } { [ info exists title($i) ] } { incr i } {
    for { set j 0 } { [ info exists table($i,$j) ] } { incr j } {
      set v [ lindex $table($i,$j) 0 ]
      set t [ lindex $table($i,$j) 2 ]
      set ls1 [ expr [ llength $table($i,$j) ] - 2 ]
      set ls2 [ expr [ llength $table($i,$j) ] - 1 ]
      set s1 [ lindex $table($i,$j) $ls1 ]
      set s2 [ lindex $table($i,$j) $ls2 ]
      if { $t == "expandolist" } {
        set names "[ lindex $table($i,$j) 0 ]_*"
        foreach b [ array names stuff $names ] {
          puts $fid "set ::setting(${b}) $s1$::setting($b)$s2"
        }
      } else {
        puts $fid "set ::setting($v) $s1$::setting($v)$s2"
      }  
    }
  }

  close $fid

  tk_messageBox -icon info -type ok -title "roverlog.ini Saved" \
    -message "The RoverLog Ini File \"roverlog.ini\" has been saved."
}

frame .e
for { set i 0 } { [ info exists title($i) ] } { incr i } {
  button .e.b$i -text $title($i) -command "Build_Frame $i"
  pack .e.b$i -side left
}
pack .e

frame .f
Build_Frame 0

# set up default values to prevent errors when saving if they
# weren't defined in the .ini file to begin with.

proc Init { } {

  # contest defaults
  set ::setting(bands)      [ list 50 144 222 432 902 1.2G 2.3G 3.4G 5.7G 10G ]
  set ::setting(bandpts)    [ list  1   1   2   2   4   4   8   8   8  8 ]
  set ::setting(modes)      [ list CW PH FM RY ]
  set ::setting(rules)      "new"
  
  # station defaults
  set ::setting(logfile)    "n0ne.log"
  set ::setting(lookupfile) "n0ne.lup"
  set ::setting(weblookup)  "Buckmaster"
  set ::setting(contestini) "junvhfbasic.ini"
  set ::setting(mycall)     "N0NE"
  set ::setting(mygrid)     "FN12FX"
  set ::setting(allowstationchanges) 1
  set ::setting(declination) -12
  set ::setting(antoffset)   0.0
  set ::setting(myband)     [lindex $::setting(bands) 1]
  set ::setting(mymode)     [lindex $::setting(modes) 1]
  set ::setting(bandlock)   0
  set ::setting(buds)       "N0ONE N0PE"
  set ::setting(mypeername) "station1"
  # (other net stuff done later)
  set ::setting(netenable)  0
  set ::setting(netpopup)   0
  set ::setting(font)       {courier 8}
  set ::setting(entryfont)  {courier 8}
  set ::setting(bigfont)    {courier 8 bold}
  set ::setting(maintop)    0
  set ::setting(quicklookup) 0
  set ::setting(annbell) 0
  set ::setting(lookupquiet) 0
  set ::setting(mapwidth) 11
  set ::setting(mapheight) 15
  set ::setting(fkeys) "QSY"
  set ::setting(rigdvr) 0
  set ::setting(keyeripport) 0
  set ::setting(keyeripaddr) 127.0.0.1
  set ::setting(superipport) 0
  set ::setting(superipaddr) 127.0.0.1
  set ::setting(autosave)   1
  set ::setting(listheight) 8
  set ::setting(logfg) "black"
  set ::setting(logbg) "white"
  set ::setting(lognewfg) "red"
  set ::setting(lognewbg) "white"
  set ::setting(lognetfg) "dark grey"
  set ::setting(lognetbg) "white"
  set ::setting(lognetnewfg) "pink"
  set ::setting(lognetnewbg) "white"
  set ::setting(callcheck)  "none"
  set ::setting(allowcompass) 1
  set ::setting(allowsort) 1
  set ::setting(warnrealtime) 0
  set ::setting(clearentry) 0
  set ::setting(lookupgrid) 1
  set ::setting(rigfreq)    0
  set ::setting(RoverLog_Rig) "RoverLog"
  set ::setting(r1) {50 1 0 50.1250}
  set ::setting(r2) {144 1 0 144.2000}
  set ::setting(r3) {222 1 0 222.1000}
  set ::setting(r4) {432 1 0 432.1000}
  set ::setting(r5) {902 1 0 903.1000}
  set ::setting(r6) {1.2G 1 0 1296.1000}
  set ::setting(r7) {2.3G 1 0 2304.1000}
  set ::setting(r8) {3.4G 1 0 3456.1000}
  set ::setting(r9) {5.7G 1 0 5760.1000}
  set ::setting(r10) {10G 1 0 10368.1000}
  set ::setting(r11) {24G 1 0 24}
  set ::setting(r12) {47G 1 0 47}
  set ::setting(r13) {76G 1 0 76}
  set ::setting(r14) {119G 1 0 119}
  set ::setting(r15) {142G 1 0 142}
  set ::setting(r16) {241G 1 0 241}
  set ::setting(r17) {300G 1 0 300}
  set ::setting(gps)        0
  set ::setting(gpsipaddr)  127.0.0.1
  set ::setting(gpsipport)  0
  set ::setting(rotoripaddr) 127.0.0.1
  set ::setting(rotoripport) 0
  set ::setting(wiplimit)   3
  set ::setting(wipbusy)    10
  set ::setting(txminute)   even
  set ::setting(earlywarn)  0
  set ::setting(autoreap)   1
  set ::setting(skedqsy)    0
  set ::setting(quicksked)  1
  set ::setting(skedtinc)   10
  set ::setting(mapcoldbg)  green
  set ::setting(mapcoldfg)  black
  set ::setting(mapwarmbg)  yellow
  set ::setting(mapwarmfg)  black
  set ::setting(maphotbg)   red
  set ::setting(maphotfg)   black
  set ::setting(mapunwkbg)  black
  set ::setting(mapunwkfg)  white
  set ::setting(madeskedcolor) green
  set ::setting(passprompt) 0
  set ::setting(verbnetlog) 0
  set ::setting(quicknet)   1
  set ::setting(netlogheight) 8
  set ::setting(p1) {station1 127.0.0.1 0}
  set ::setting(p2) {station2 127.0.0.1 0}
  set ::setting(p3) {station3 127.0.0.1 0}
  set ::setting(p4) {station4 127.0.0.1 0}
  set ::setting(p5) {station5 127.0.0.1 0}
  set ::setting(p6) {station6 127.0.0.1 0}
  set ::setting(p7) {station7 127.0.0.1 0}
  set ::setting(p8) {station8 127.0.0.1 0}
  set ::setting(p9) {station9 127.0.0.1 0}
  set ::setting(p10) {station10 127.0.0.1 0}
  set ::setting(p11) {station11 127.0.0.1 0}
  set ::setting(p12) {station12 127.0.0.1 0}
  set ::setting(Start_Keyer)  0
  set ::setting(Start_Super)  0
  set ::setting(Start_Rotor)  0
  set ::setting(Start_Rig)    0
  set ::setting(Start_GPS)    0
  set ::setting(Start_Clock)  0

  # non-roverlog defaults
  set ::setting(txcolor)      "black"
  set ::setting(txfgcolor)    "red"
  set ::setting(rxcolor)      "black"
  set ::setting(rxfgcolor)    "green"
}

proc Clean_Up_Ini { } {

  # this cleans up the rig settings from
  # <Band> <Rig Server IP Port> <LO Freq> <QSY Command...> 
  # to
  # <Band> <Rig Number: 1/2> <Rig Server IP Port> <LO Freq> <QSY Command...>
  for { set i 1 } { $i < 18 } { incr i } {

    # if this rig setup uses the old format (port number first)
    # insert the rig number and shift all other list elements over
    if { [ lindex $::setting(r$i) 1 ] < 1 || [ lindex $::setting(r$i) 1 ] > 2 } {
      set ::setting(r$i) [ concat [ lindex $::setting(r$i) 0 ] 1 [ lrange $::setting(r$i) 1 end ] ]
    }
  }

}

Init

if { [ file readable "roverlog.ini" ] } {
  source "roverlog.ini"

  Clean_Up_Ini
}

wm title . "Ini File Editor - roverlog.ini"

set ::setting(iniversion) "2_7_4"

menu .m -relief raised -borderwidth 2
. config -menu .m

set windows(mFile) [ menu .m.mFile -tearoff 0 ]
.m add cascade -label File -menu .m.mFile
$windows(mFile) add command -underline 0 -label Save -command {Save_File}
$windows(mFile) add command -underline 1 -label Exit -command My_Exit

set windows(mHelp) [ menu .m.mHelp -tearoff 0 ]
.m add cascade -label Help -menu .m.mHelp
$windows(mHelp) add command -underline 0 -label About -command About

raise .
focus .

if { $tcl_platform(os) != "Linux" && $tcl_platform(os) != "Darwin" } {
  catch { wm iconbitmap . inied.ico }
}
wm protocol . WM_DELETE_WINDOW My_Exit
