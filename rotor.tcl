#/bin/sh
# the next line restarts using tclsh \
exec wish "$0" "$@"

package require dde

proc Restart_Server { } {
  Serial_Close
  Serial_Open
  Server_Close
  Server_Open
  Poll
}

proc Server_Open { } {
  global stuff

  if [catch { socket -server Net_Accept $::setting(ipport) } stuff(ipfid) ] {
    unset stuff(ipfid)
    set ok [ tk_messageBox -icon warning -type okcancel \
      -title "Rotor Module Network Error" -message \
      "Cannot open socket on $::setting(ipport).\nModule already running?\nSelect Ok to continue anyway or Cancel to exit." ]
    if { $ok != "ok" } {
      Serial_Close
      exit
    }
    return
  }

  proc Net_Accept {newSock addr port} {
    fconfigure $newSock -buffering line
    fileevent $newSock readable [list Serve_Request $newSock]
  }
}

proc Server_Close { } {
  global stuff

  if { [ info exists stuff(ipfid) ] } {
    close $stuff(ipfid)
    unset stuff(ipfid)
  }
}

proc Serve_Request { sock } {
  global stuff
  if {[eof $sock] || [catch {gets $sock line}]} {
    close $sock
  } else {
    if { [ string length $line ] == 0 } {
      return
    }
    if {[string compare $line "pos?"] == 0} {
      Debug "Serve_Request" "Received pos get request."
      Debug "Serve_Request" "Replying with $stuff(rotorpos)."
      puts $sock $stuff(rotorpos)
    } elseif {[string compare [ string range $line 0 3 ] "pos!"] == 0} {
      Debug "Serve_Request" "Received pos set request"
      if { [ scan $line "%*s %f" p ] == 1 } {
        Debug "Serve_Request" "Requested pos $p"
        set stuff(rotorset) [ format "%f" $p ]
        Send_Pos
      }
    } elseif {[string compare $line "stop!"] == 0} {
      Debug "Serve_Request" "Received stop rotor request"
      Stop_Rotor
    } elseif {[string compare $line "quit!"] == 0} {
      Debug "Serve_Request" "Received quit request"
      Net_Exit
    } else {
      Debug "Serve_Request" "Received unknown command."
      Dump_Buffer $line
    }
  }
}

# 
# Serial_Read - Accept data from serial port
#

proc Serial_Read { } {
  global stuff
  
  set r [ read $stuff(fid) ]

  switch -exact -- $::setting(rotortype) {
    "RC2800DC-alt" -
    "RC2800DC" {
      set stuff(response) "$stuff(response)$r"
      if { [ string index $r end ] == "\x0d" } {
        Parse_Response
        set stuff(response) ""
      }
      return
    }
    "GHE RT-20" -
    "GHE RT-21" -
    "Hygain DCU-1" {
      set stuff(response) "$stuff(response)$r"
      if { [ string index $r end ] == ";" } {
        Parse_Response
        set stuff(response) ""
      }
      return
    }
    "ProSisTel" {
      set stuff(response) "$stuff(response)$r"
      if { [ string index $r end ] == "\x0d" } {
        Parse_Response
        set stuff(response) ""
      }
      return
    }
    "DDE" {
      return
    }
    default {
      tk_messageBox -icon error -type ok \
        -title "Rotor Type Error" -message "Unknown Rotor Type."      
      return
    }
  }
}

proc Parse_Response { } {
  global stuff

  switch -exact -- $::setting(rotortype) {
    "RC2800DC-alt" -
    "RC2800DC" {
      Debug "Parse_Response" "Parsing RC2800DC/RC2800DC-alt message"
      Dump_Buffer $stuff(response)
      # response format "A=xxx.x S=y M"
      set t1 [ lindex [ split $stuff(response) "=" ] 1 ]
      # t1 format "xxx.x S"
      set t2 [ lindex [ split $t1 " " ] 0 ]
      if { [ scan $t2 "%f" az ] == 1 } {
        set stuff(rotorpos) $az
      }
      return
    }
    "GHE RT-20" -
    "GHE RT-21" {
      Debug "Parse_Response" "Parsing GHE RT-20/21 message $stuff(response)"
      Dump_Buffer $stuff(response)
      # Response format xxx;
      if { [ scan $stuff(response) "%f;" az ] == 1 } {
        set stuff(rotorpos) $az
      }
      return
    }
    "Hygain DCU-1" {
      Debug "Parse_Response" "Parsing Hygain DCU-1 message $stuff(response)"
      Dump_Buffer $stuff(response)
      # Response format xxx;
      if { [ scan $stuff(response) "%d;" az ] == 1 } {
        set stuff(rotorpos) $az
      }
      return
    }
    "ProSisTel" {
      Debug "Parse_Response" "Parsing ProSisTel message"
      Dump_Buffer $stuff(response)
      # Response format "\x02" "A,NNN,x" where x is "R" or "B" for Ready/Busy
      if [ scan [ string range $stuff(response) 4 6 ] "%d" az ] == 1 {
        set stuff(rotorpos) $az
      }
    }
    "DDE" { 
      return
    }
    default {
      return
    }
  }
}

proc Serial_Write { b } {
  global stuff

  if { [ info exists stuff(fid) ] } {
    puts -nonewline $stuff(fid) $b
    flush $stuff(fid)
  }
}

proc Fix_Serial_Port_Name { s } {
  global tcl_platform

  switch -exact -- $tcl_platform(os) {
    "Linux" {
      return $s
    }
    "Darwin" {
      return $s
    }
    default {
      set s [ string map -nocase { c "" o "" m "" "\\" "" "." "" ":" "" } $s ]
      if { $s > 0 && $s < 10 } {
        set s "COM${s}:"
      } else {
        set s "\\\\.\\COM$s"
      }
      return $s
    }
  }
}

proc Serial_Open { } {
  global stuff

  if { $::setting(serport) == "" } {
    return
  }

  set serport [ Fix_Serial_Port_Name $::setting(serport) ]

  Debug "Serial_Open" "Opening $serport."

  if [ catch { set stuff(fid) [ open $serport r+ ] } ] {
    tk_messageBox -icon warning -type ok \
      -title "Rotor Module Serial Port Error" -message \
      "Cannot open $::setting(serport).\nModule already running?"
    return
  }

  Debug "Serial_Open" "Serial port $::setting(serport) open as $stuff(fid)."

  if { $::setting(sermode) != "" } {

    if [ catch { fconfigure $stuff(fid) -blocking 0 -buffering none \
      -encoding binary -translation { binary binary } \
      -mode $::setting(sermode) } ] {

      tk_messageBox -icon warning -type ok \
        -title "Rotor Module Serial Port Error" -message \
        "Cannot configure $::setting(serport)."
    }
  }

  if { $::setting(serttycontrol) != "" } {

    if [ catch { fconfigure $stuff(fid) -handshake none \
      -ttycontrol $::setting(serttycontrol) } ] {

      tk_messageBox -icon warning -type ok \
        -title "Rotor Module Serial Port Warning" -message \
        "Cannot configure $::setting(serport)."
    }
  }

  fileevent $stuff(fid) readable Serial_Read
}

proc Serial_Close { } {
  global stuff

  if { [ info exists stuff(fid) ] } {
    close $stuff(fid)
    unset stuff(fid)
  }
}

proc Build_Debug { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "Debug Log"
  wm protocol $f WM_DELETE_WINDOW { set stuff(debug) 0 ; wm withdraw $windows(debug) }

  set windows(debugtext) [ text $f.st \
   -width 80 -height 24 -yscrollcommand "$f.ssb set" ]
  scrollbar $f.ssb -orient vert -command "$f.st yview"
  pack $f.ssb -side right -fill y
  pack $f.st -side left -fill both -expand true

  return $f
}

proc Popup_Debug { } {
  global windows stuff

  wm deiconify $windows(debug)
  raise $windows(debug)
  focus $windows(debug)

  set stuff(debug) 1

  Debug "Popup_Debug" "Debug log enabled"
}

proc Debug { s m } {
  global windows stuff

  if { $stuff(debug) == 0 } {
    return
  }

  set t [clock seconds]
  set date [clock format $t -format "%Y-%m-%d"]
  set utc [clock format $t -format "%H:%M"]
  set d "$date $utc"

  $windows(debugtext) insert end "$d: $s: $m\n"
  $windows(debugtext) see end
  update idletasks
}

proc Dump_Buffer { b } {
  global windows stuff

  set n [ string length $b ]
  set r "buffer:"

  for { set i 0 } { $i < $n } { incr i } {
    scan [ string index $b $i ] "%c" c
    set r [ format "%s %02.2x" $r $c ]
  }

  Debug "Dump_Buffer" "$r"
}

proc Save_Loc { } {
  global .

  set fid [ open "rotor_loc.ini" w 0666 ]

  set t [clock seconds]
  set date [clock format $t -format "%Y-%m-%d"]
  set utc [clock format $t -format "%H:%M:%S"]
  set d "$date $utc"

  puts $fid "# Saved $d"

  set s [ wm state . ]
  puts $fid "# . $s"
  puts $fid "wm state . $s"
  set g [ wm geometry . ]
  puts $fid "# . $g"
  scan $g "%*dx%*d+%d+%d" x y
  puts $fid "wm geometry . =+$x+$y"

  close $fid
}

proc Save_Settings { } {

  set fid [ open "rotor.ini" w 0666 ]

  for { set handle [ array startsearch ::setting ]
    set index [ array nextelement ::setting $handle ] } \
    { $index != "" } \
    { set index [ array nextelement ::setting $handle ] } {

    Debug "Save_Settings" "$index"
    if { [ llength $::setting($index) ] > 1 } {
      puts $fid "set ::setting($index) \{$::setting($index)\}"
    } else {
      puts $fid "set ::setting($index) \"$::setting($index)\""
    }

  }
  array donesearch ::setting $handle

  close $fid
}

proc Net_Exit { } {

  Server_Close
  Serial_Close
  Save_Loc
  Save_Settings
  exit
}

proc My_Exit { } {
  set ok [ tk_messageBox -icon warning -type okcancel \
    -title "Confirm Rotor Module Exit" -message \
    "Do you really want to exit the Rotor Module?\nSelect Ok to exit or Cancel to abort exit." ]
  if { $ok != "ok" } {
    return
  }

  Net_Exit
}

proc Stop_Rotor { } {
  global stuff

  switch -exact -- $::setting(rotortype) {
    "DDE" {
      # dde execute Project1 SYSTEM "S\r"
      dde execute $::setting(ddeservice) $::setting(ddetopic) "S\r"
      return
    }  
    "RC2800DC-alt" -
    "RC2800DC" {
      set b "S\r"

      # debug
      Debug "Stop_Rotor" "Sending RC2800DC/RC2800DC-alt stop command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      return
    }
    "GHE RT-20" -
    "GHE RT-21" -
    "Hygain DCU-1" {
      set b ";"

      # debug
      Debug "Stop_Rotor" "Sending Hygain DCU-1/GHE RT-20/21 stop command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      return
    }
    "ProSisTel" {
      set b "\x02"
      set b "${b}AG997\x0d"

      # debug
      Debug "Stop_Rotor" "Sending ProSisTel stop command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      return
    }
    default {
      return
    }
  }
}



proc Send_Pos { } {
  global stuff

  switch -exact -- $::setting(rotortype) {
    "DDE" {
      set p [ expr int($stuff(rotorset)) ]
      # dde execute Project1 SYSTEM $stuff(rotorset)\r
      dde execute $::setting(ddeservice) $::setting(ddetopic) \
        "$p\r"
      return
    }
    "RC2800DC" {
      set p [ expr int($stuff(rotorset)) ]

      set b "A\r"
      Debug "Send_Pos" "Sending RC2800DC rotor select command"
      Dump_Buffer $b
      Serial_Write $b

      set b "$p\r"
      Debug "Send_Pos" "Sending RC2800DC position command"
      Dump_Buffer $b
      Serial_Write $b

      return
    }
    "RC2800DC-alt" {
      set p [ expr int($stuff(rotorset)) ]
      set b "A$p\r"

      # debug
      Debug "Send_Pos" "Sending RC2800DC-alt position command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      return
    }
    "GHE RT-20" -
    "GHE RT-21" {
      set n [ expr $stuff(rotorset) + 1000.0 ]
      # W2FU says do not use \r
      # set b "AP$n;\rAM1;\r"
      set b "AP$n;AM1;"

      # debug
      Debug "Send_Pos" "Sending GHE RT-20/21 position command $b"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      return
    }
    "Hygain DCU-1" {
      set n [ expr int($stuff(rotorset)) + 1000 ]
      # W2FU says do not use \r
      # set b "AP$n;\rAM1;\r"
      set b "AP$n;AM1;"

      # debug
      Debug "Send_Pos" "Sending Hygain DCU-1 position command $b"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      return
    }
    "ProSisTel" {
      set p [ expr int($stuff(rotorset)) ]

      # put the number if the format NNN
      set n [ format "%03.3d" $p ]

      # build the command buffer
      set b "\x02"
      set b "${b}AG${n}\x0d"

      # debug
      Debug "Send_Pos" "Sending ProSisTel position command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      return
    }
    default {
      return
    }
  }
}

proc Query_Pos { } {
  global stuff

  switch -exact -- $::setting(rotortype) {
    "RC2800DC-alt" -
    "RC2800DC" {

      # set up the command
      set b "\r"

      # debug
      Debug "Query_Pos" "Sending RC2800DC/RC2800DC-alt query"
      Dump_Buffer $b

      # send query
      Serial_Write $b
      return
    }
    "GHE RT-20" {

      # set up the command
      set b "AI1;"

      # debug
      Debug "Query_Pos" "Sending GHE RT-20 query $b"
      Dump_Buffer $b

      # send query
      Serial_Write $b
      return
    }
    "GHE RT-21" {

      # set up the command
      set b "BI1;"

      # debug
      Debug "Query_Pos" "Sending GHE RT-21 query $b"
      Dump_Buffer $b

      # send query
      Serial_Write $b
      return
    }
    "Hygain DCU-1" {

      # set up the command
      set b "AI1;"

      # debug
      Debug "Query_Pos" "Sending Hygain DCU-1 query $b"
      Dump_Buffer $b

      # send query
      Serial_Write $b
      return
    }
    "ProSisTel" {

      # set up the command
      set b "\x02"
      set b "${b}A?\x0d"

      # debug
      Debug "Query_Pos" "Sending ProSisTel query"
      Dump_Buffer $b

      # send query
      Serial_Write $b
      return
    }
    "DDE" {
      return
    }
    default {
      return
    }
  }
}

proc Bump_CW { } {
  global stuff

  switch -exact -- $::setting(rotortype) {
    "RC2800DC-alt" -
    "RC2800DC" {
      set b "+\r"

      # debug
      Debug "Bump_CW" "Sending bump CW command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      return
    }
    default {

      # Query current position
      Query_Pos

      # Await response - Dangerous?
      vwait stuff(rotorpos)
      set stuff(rotorset) $stuff(rotorpos)

      # Increment position with wrap-around
      set stuff(rotorset) [ expr $stuff(rotorset) + 1.0 ]
      if { $stuff(rotorset) > 360.0 } {
        set stuff(rotorset) [ expr $stuff(rotorset) - 360.0 ]
      }

      # Send new position
      Send_Pos

      return
    }
  }
}

proc Bump_CCW { } {
  global stuff

  switch -exact -- $::setting(rotortype) {
    "RC2800DC-alt" -
    "RC2800DC" {
      set b "-\r"

      # debug
      Debug "Bump_CCW" "Sending bump CCW command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      return
    }
    default {

      # Query current position
      Query_Pos

      # Await response - Dangerous?
      vwait stuff(rotorpos)
      set stuff(rotorset) $stuff(rotorpos)

      # Decrement position with wrap-around
      set stuff(rotorset) [ expr $stuff(rotorset) - 1.0 ]
      if { $stuff(rotorset) < 0.0 } {
        set stuff(rotorset) [ expr $stuff(rotorset) + 360.0 ]
      }

      # Send new position
      Send_Pos

      return
    }
  }
}

proc Poll { } {
  global stuff

  if [ info exists stuff(afterjob) ] {
    after cancel $stuff(afterjob)
    unset stuff(afterjob)
  }

  switch -exact -- $::setting(rotortype) {
    "RC2800DC-alt" -
    "RC2800DC" -
    "GHE RT-20" -
    "GHE RT-21" -
    "Hygain DCU-1" {
      Query_Pos
    }
    default {
      return
    }
  }
  if { $::setting(pollint) > 0 } {
    set stuff(afterjob) [ after [ expr $::setting(pollint) * 1000 ] Poll ]
  }
}

proc Init { } {
  global stuff tcl_platform

  set stuff(debug) 0

  set ::setting(serport) ""

  set ::setting(sermode) "9600,n,8,1"
  set ::setting(serttycontrol) "RTS 1 DTR 1"

  set ::setting(pollint) 0
  set ::setting(rotortype) "RC2800DC"

  set ::setting(ddeservice) "Project1"
  set ::setting(ddetopic)   "SYSTEM"

  set ::setting(ipport) 32125

  set stuff(rotorpos) "0"
  set stuff(rotorset) "0"
  set stuff(response) ""
}

set stuff(rotortypes) { "DDE" "RC2800DC" "RC2800DC-alt" "Hygain DCU-1" "GHE RT-20" "GHE RT-21" "ProSisTel" }

# identify serial ports

  switch -exact -- $tcl_platform(os) {
    "Linux" {
      set stuff(serports) [ list "/dev/ttyS0" "/dev/ttyS1" ]
    }
    "Darwin" {
      set stuff(serports) [ list "/dev/cu.USA19QW11P1.1" "/dev/cu.USA19QW11P2.1" ]
    }
    default {
      package require registry

      set serial_base "HKEY_LOCAL_MACHINE\\HARDWARE\\DEVICEMAP\\SERIALCOMM"
      set values [ registry values $serial_base ]

      set result {}

      foreach valueName $values {
         set t [ registry get $serial_base $valueName ]
         set t "${t}:"
         lappend result $t
      }

      set result [ lsort -dictionary $result ]

      set stuff(serports) $result
    }
  }


# label .lserport -text "Rotor Serial Port"
menubutton .mbserport -text "Rotor Serial Port" -menu .mbserport.m -relief \
  raised
set w [menu .mbserport.m -tearoff 0]
foreach b $stuff(serports) {
  $w add radio -label $b -variable ::setting(serport) -value $b
}
entry .eserport -textvariable ::setting(serport)

label .lsermode -text "Serial Port Mode"
entry .esermode -textvariable ::setting(sermode)

label .lserctrl -text "Serial Port Line Control"
entry .eserctrl -textvariable ::setting(serttycontrol)

label .lddeservice -text "DDE Service"
entry .eddeservice -textvariable ::setting(ddeservice)

label .lddetopic -text "DDE Topic"
entry .eddetopic   -textvariable ::setting(ddetopic)

label .lipport -text "Server IP Port"
entry .eipport -textvariable ::setting(ipport)

button .br -text "Start/Restart Server" -command Restart_Server

label .lpollint -text "Polling Interval (sec)"
entry .epollint -textvariable ::setting(pollint)

menubutton .mbrotortype -text "Rotor Type" -menu .mbrotortype.m -relief \
  raised
entry .erotortype -textvariable ::setting(rotortype)
set w [menu .mbrotortype.m -tearoff 0]
foreach b $stuff(rotortypes) {
  $w add radio -label $b -variable ::setting(rotortype) -value $b
}


label .lrp -text "Rotor Pos (deg)"
entry .erp -textvariable stuff(rotorpos) -state readonly
label .lrs -text "Rotor Setpoint (deg)"
entry .ers -textvariable stuff(rotorset)
button .bcw -text "Bump CW" -command Bump_CW 
button .bccw -text "Bump CCW" -command Bump_CCW 
button .bs -text "Send Pos to Rotor" -command Send_Pos
button .bg -text "Get Pos from Rotor" -command Query_Pos
button .bp -text "Stop Rotor" -command Stop_Rotor 
button .bx -text "Exit" -command My_Exit

grid .mbserport   .eserport    -padx 2 -pady 2 -sticky ew
grid .lsermode    .esermode    -padx 2 -pady 2 -sticky ew
grid .lserctrl    .eserctrl    -padx 2 -pady 2 -sticky ew
grid .lddeservice .eddeservice -padx 2 -pady 2 -sticky ew
grid .lddetopic   .eddetopic   -padx 2 -pady 2 -sticky ew
grid .lipport     .eipport     -padx 2 -pady 2 -sticky ew
grid .br          -            -padx 2 -pady 2 -sticky ew
grid .lpollint    .epollint    -padx 2 -pady 2 -sticky ew
grid .mbrotortype .erotortype  -padx 2 -pady 2 -sticky ew
grid .lrp         .erp         -padx 2 -pady 2 -sticky ew
grid .lrs         .ers         -padx 2 -pady 2 -sticky ew
grid .bcw         .bccw        -padx 2 -pady 2 -sticky news
grid .bs          -            -padx 2 -pady 2 -sticky ew
grid .bg          -            -padx 2 -pady 2 -sticky ew
grid .bp          -            -padx 2 -pady 2 -sticky ew
grid .bx          -            -padx 2 -pady 2 -sticky ew

set windows(debug) [ Build_Debug .debug ]
wm title . "Rotor Module"
if { $tcl_platform(os) != "Linux" && $tcl_platform(os) != "Darwin" } {
  wm iconbitmap . rotor.ico
}
wm protocol . WM_DELETE_WINDOW My_Exit
wm resizable . 0 0

Init

if { [ file readable "rotor.ini" ] } {
  source "rotor.ini"
}

bind all <Alt-Key-u> Popup_Debug

if { [ file readable "rotor_loc.ini" ] } {
  source "rotor_loc.ini"
}

Restart_Server
