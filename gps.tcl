#/bin/sh
# the next line restarts using tclsh \
exec wish "$0" "$@"

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
}

proc To_Grid { latlon } {

  Debug "To_Grid" "lat lon = $latlon"

  scan $latlon "%f %f" lat lon
  set mylat [ expr 90 + $lat ]
  set mylon [ expr 180 + $lon ]

  set grid [ format "%c"    [ expr 65 + int( ( $mylon ) / 20 ) ] ]
  append grid [ format "%c" [ expr 65 + int( ( $mylat ) / 10 ) ] ]

  append grid [ format "%c" [ expr 48 + int( ( $mylon ) / 2 ) % 10 ] ]
  append grid [ format "%c" [ expr 48 + int( $mylat ) % 10 ] ]

  append grid [ format "%c" \
    [ expr 97 + ( int( $mylon ) % 2 ) * 12 + \
      int( ( $mylon - int( $mylon ) ) * 12 ) ] ]
  append grid [ format "%c" \
    [ expr 97 + int( ( $mylat - int( $mylat ) ) * 24 ) ] ]

  return $grid
}

proc Read_GPS { } {
  global stuff

  # read the line---do nothing if error reading.
  if { [ catch { gets $stuff(fid) } rdln ] } {
    Debug "Read_GPS" "Read error"
    return
  }

  if { [ string length $rdln ] < 7 } {
    return
  }

  # initialize such that this is not a sentence of interest
  set goodsentence 0

  # if RMC sentence received, parse it
  if { [ string range $rdln 0 6 ] == "\$GPRMC," } {

    Debug "Read_GPS" "Got a \$GPRMC line"

    set stuff(gps_str) $rdln

    # parse out elements
    set parsed [ split $stuff(gps_str) "," ]
    if { [ llength $parsed ] < 12 } {
      Debug "Read_GPS" "Parsed \$GPRMC sentence has fewer than 12 fields, ignoring. ($stuff(gps_str))"
      return
    }

    set utc [ lindex $parsed 1 ]
    # remove any trailing fraction
    set utc [ string range $utc 0 5 ]
    set lat [ lindex $parsed 3 ]
    set lath [ lindex $parsed 4 ]
    set lon [ lindex $parsed 5 ]
    set lonh [ lindex $parsed 6 ]
    set knots [ lindex $parsed 7 ]
    set course [ lindex $parsed 8 ]
    set date [ lindex $parsed 9 ]
    set dec [ lindex $parsed 10 ]
    set dech [ lindex $parsed 11 ]

    if { ! [ string is integer "1$utc" ] } {
      Debug "Read_GPS" "Parsed \$GPRMC sentence has erroneous UTC, ignoring. ($utc)"
      Init_Data
      return
    }

    if { ! [ string is double $lat ] } {
      Debug "Read_GPS" "Parsed \$GPRMC sentence has erroneous Lat, ignoring. ($lat)"
      Init_Data
      return
    }

    if { ! [ string is double $lon ] } {
      Debug "Read_GPS" "Parsed \$GPRMC sentence has erroneous Lon, ignoring. ($lon)"
      Init_Data
      return
    }

    if { ! [ string is integer "1$date" ] } {
      Debug "Read_GPS" "Parsed \$GPRMC sentence has erroneous Date, ignoring. ($date)"
      Init_Data
      return
    }

    if { ! [ string is double $dech ] } {
      Debug "Read_GPS" "Parsed \$GPRMC sentence has erroneous Dec, ignoring. ($dech)"
      Init_Data
      return
    }

    # we found a sentence with data in it, continue to process below
    set goodsentence 1

    # set permanent flag for the more favorable RMC sentence
    set stuff(hasrmc) 1
  }

  # if we have ever had the RMC sentence, don't bother looking for GGA
  if { ! $stuff(hasrmc) } {

    # if GGA sentence received, parse it
    if { [ string range $rdln 0 6 ] == "\$GPGGA," } {

      Debug "Read_GPS" "Got a \$GPGGA line"

      set stuff(gps_str) $rdln

      # parse out elements
      set parsed [ split $stuff(gps_str) "," ]
      if { [ llength $parsed ] < 6 } {
        Debug "Read_GPS" "Parsed \$GPGGA sentence has fewer than 6 fields, ignoring. ($stuff(gps_str))"
        return
      }

      set utc [ lindex $parsed 1 ]
      # remove any trailing fraction
      set utc [ string range $utc 0 5 ]
      set lat [ lindex $parsed 2 ]
      set lath [ lindex $parsed 3 ]
      set lon [ lindex $parsed 4 ]
      set lonh [ lindex $parsed 5 ]

      if { ! [ string is integer "1$utc" ] } {
        Debug "Read_GPS" "Parsed \$GPGGA sentence has erroneous UTC, ignoring. ($utc)"
        Init_Data
        return
      }

      if { ! [ string is double $lat ] } {
        Debug "Read_GPS" "Parsed \$GPGGA sentence has erroneous Lat, ignoring. ($lat)"
        Init_Data
        return
      }

      if { ! [ string is double $lon ] } {
        Debug "Read_GPS" "Parsed \$GPGGA sentence has erroneous Lon, ignoring. ($lon)"
        Init_Data
        return
      }

      # GGA sentence does not contain these items.
      set knots ""
      set course ""
      set date ""
      set dec ""
      set dech ""

      set goodsentence 1
    }
  }

  # if the data we found was not a useful sentence, return
  if { ! $goodsentence } {
    return
  }

  # if we have a nice date and time, continue setting stuff
  if { [ string length $date ] >= 6 && \
    [ string length $utc ] >= 6 } {

    # parse UTC date and time
    set month [ string range $date 2 3 ]
    set day [ string range $date 0 1 ]
    set year [ string range $date 4 5 ]
    set hour [ string range $utc 0 1 ]
    set min [ string range $utc 2 3 ]
    set sec [ string range $utc 4 5 ]

    # adjust to local time
    set tgps [ clock scan "$year-$month-$day $hour:$min:$sec" ]
    set tgps [ expr $tgps - $stuff(utcoffset) * 3600 ]
    set tpc [ clock seconds ]

    # Check the difference between the GPS time and PC time
    set td [ expr abs( $tgps - $tpc ) ]
    Debug "Read_GPS" "Time difference abs(tgps-tpc) = $td"
    if { $td > 10 } {
      Debug "Read_GPS" "Machine time and GPS time disagree!"
      $::windows(tsetbutton) configure -fg red
    } else {
      Debug "Read_GPS" "Machine time and GPS time agree."
      $::windows(tsetbutton) configure -fg black
    }


    # do time/date setting stuff if prompted to do so
    if { $stuff(tset) == 1 } {

      # parse local date and time
      set month [ clock format $tgps -format "%m" ]
      set day [ clock format $tgps -format "%d" ]
      set year [ clock format $tgps -format "%Y" ]
      set hour [ clock format $tgps -format "%H" ]
      set min [ clock format $tgps -format "%M" ]
      set sec [ clock format $tgps -format "%S" ]

      switch -exact -- $::tcl_platform(os) {
        "Linux" {
          Debug "Read_GPS" "Setting Linux date and time $month$day$hour$min$year.$sec"
	        catch "exec date $month$day$hour$min$year.$sec"
        }
        "Darwin" {
          Debug "Read_GPS" "Setting OSX date and time $month$day$hour$min$year.$sec"
	        catch "exec date $month$day$hour$min$year.$sec"
        }
        default {
          # sorry, this is the best I could do for setting the date and time.
	        # yuck.
          Debug "Read_GPS" "Setting Windows date and time $month-$day-$year $hour:$min:$sec"
          set runcmd [list exec datetime $month-$day-$year $hour:$min:$sec]
	        catch $runcmd r
          Debug "Read_GPS" "Result for datetime was $r"
        }
      }

      # unset the time set flag to prevent repeatedly monkeying with the clock.
      set stuff(tset) 0
    }
  }

  # If we don't have core information, something is screwed up.  Reset
  # all fields so we don't mislead the client into thinking they are somewhere
  # (some time) they are not.
  if { $utc == "" }  { Init_Data ; return }
  if { $lat == "" }  { Init_Data ; return }
  if { $lath == "" } { Init_Data ; return }
  if { $lon == "" }  { Init_Data ; return }
  if { $lonh == "" } { Init_Data ; return }

  # These fields may not be read or may be screwed up.  If so, it's non-fatal,
  # but fix it to return a reasonable respnonse.
  if { $knots == "" } { set knots 0 }
  if { $course == "" } { set course 0 }
  if { $date == "" } {
    set s [ clock seconds ]
    set y [ clock format $s -format %y ]
    set m [ clock format $s -format %m ]
    set d [ clock format $s -format %d ]
    set date "$d$m$y"
  }
  if { $dec == "" } { set dec 0 }
  if { $dech == "" || [ string range $dech 0 0 ] == "*" } { set dech "W" }

  # Adjust the hemispheres.
  if { $lonh == "W" } { set lon -$lon }
  if { $lath == "S" } { set lat -$lat }

  # set globals
  set latd [ expr int ( $lat / 100 ) ]
  set latm [ expr $lat - $latd * 100 ]
  set lond [ expr int ( $lon / 100 ) ]
  set lonm [ expr $lon - $lond * 100 ]
  set lat  [ expr $latd + $latm / 60 ]
  set lon  [ expr $lond + $lonm / 60 ]
  set stuff(latlon) [ format "%f %f" $lat $lon ]
  set stuff(grid) [ To_Grid $stuff(latlon) ]

  set stuff(utc) [ string range $utc 0 3 ]
  set stuff(sec) [ string range $utc 4 5 ]
  set day [ string range $date 0 1 ]
  set month [ string range $date 2 3 ]
  set year [ string range $date 4 5 ]
  set stuff(date) "20$year-$month-$day"
  scan $dec "%f" dec
  set dech [ string range $dech 0 0 ]
  set stuff(dec) "$dec $dech"
  set stuff(speed) [ expr $knots * 1.15077945 ]
  set stuff(course) $course

  # If we made it here, we had a good refresh of the data.  Schedule a check
  # for the future to clear things out if our connection is severed.
  if { [ info exists stuff(afterjob) ] } {
    Debug "Read_GPS" "Cancelling after job."
    after cancel $stuff(afterjob)
  }
  Debug "Read_GPS" "Scheduling after job."
  set stuff(afterjob) [ after 10000 Init_Data ]
}

proc Fix_GPS_Port_Name { s } {
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

proc GPS_Open { } {
  global stuff

  if { $::setting(gpsport) == "" } {
    return
  }

  if { $::setting(gpsport) == "GPSD" } {

    # open the connection to the peer.
    if [ catch { socket $::setting(gpsipaddr) $::setting(gpsipport) } stuff(fid) ] {
      unset stuff(fid)
      return
    }

    # set up the descriptor
    if [ catch { fconfigure $stuff(fid) -buffering line -blocking 0 } ] {
      unset stuff(fid)
      return
    }

    # command GPSD to start sending NMEA data
    puts $stuff(fid) "?WATCH={\"enable\":true,\"nmea\":true}"

  } else {

    set gpsport [ Fix_GPS_Port_Name $::setting(gpsport) ]

    if [ catch { set stuff(fid) [ open $gpsport r+ ] } ] {
      tk_messageBox -icon warning -type ok \
        -title "GPS Module Serial Port Error" -message \
        "Cannot open $::setting(gpsport).\nModule already running?"
      return
    }

    Debug "GPS_Open" "Serial port $::setting(gpsport) open as $stuff(fid)."

    if [ catch { fconfigure $stuff(fid) -blocking false -buffering line \
      -mode $::setting(sermode) } ] {
      Debug "GPS_Open" "Serial port $::setting(gpsport) configuration failed."
    } else {
      Debug "GPS_Open" "Serial port $::setting(gpsport) configuration complete."
    }
  }

  fileevent $stuff(fid) readable { Read_GPS }
}

proc GPS_Close { } {
  global stuff

  if { [ info exists stuff(fid) ] } {
    close $stuff(fid)
    unset stuff(fid)
  }
}

proc Save_Settings { } {

  set fid [ open "gps.ini" w 0666 ]

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
  GPS_Close
  Save_Loc
  Save_Settings
  exit
}

proc My_Exit { } {

  set ok [ tk_messageBox -icon warning -type okcancel \
    -title "Confirm GPS Module Exit" -message \
    "Do you really want to exit the GPS Module?\nSelect Ok to exit or Cancel to abort exit." ]
  if { $ok != "ok" } {
    return
  }

  Net_Exit
}

proc Restart_Serial { } {
  GPS_Close
  GPS_Open
}

proc Restart_Server { } {
  Server_Close
  Server_Open
}

proc Server_Open { } {
  global stuff

  if [catch { socket -server Net_Accept $::setting(ipport) } stuff(ipfid) ] {
    unset stuff(ipfid)
    set ok [ tk_messageBox -icon warning -type okcancel \
        -title "GPS Module Network Error" -message \
        "Cannot open socket on $::setting(ipport).\nModule already running?\nSelect Ok to continue anyway or Cancel to exit." ]
    if { $ok != "ok" } {
      GPS_Close
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

proc Restart { } {
  Restart_Server
  Restart_Serial
}

proc Serve_Request { sock } {
  global stuff
  if {[eof $sock] || [catch {gets $sock line}]} {
    close $sock
  } else {
    if {[string compare $line "grid?"] == 0} {
      Debug "Serve_Request" "Received grid request."
      Debug "Serve_Request" "Replying with $stuff(grid)."
      puts $sock $stuff(grid)
    } elseif {[string compare $line "date?"] == 0} {
      Debug "Serve_Request" "Received date request."
      Debug "Serve_Request" "Replying with $stuff(date)."
      puts $sock $stuff(date)
    } elseif {[string compare $line "utc?"] == 0} {
      Debug "Serve_Request" "Received time request."
      Debug "Serve_Request" "Replying with $stuff(utc)."
      puts $sock $stuff(utc)
    } elseif {[string compare $line "dec?"] == 0} {
      Debug "Serve_Request" "Received declination request."
      Debug "Serve_Request" "Replying with $stuff(dec)."
      puts $sock $stuff(dec)
    } elseif {[string compare $line "course?"] == 0} {
      Debug "Serve_Request" "Received course request."
      Debug "Serve_Request" "Replying with $stuff(course)."
      puts $sock $stuff(course)
    } elseif {[string compare $line "speed?"] == 0} {
      Debug "Serve_Request" "Received speed request."
      Debug "Serve_Request" "Replying with $stuff(speed)."
      puts $sock $stuff(speed)
    } elseif {[string compare $line "quit!"] == 0} {
      Net_Exit
    } else {
      puts $sock "Received unknown command."
    }
  }
}

#
# Init_Data - Do this to wipe out data on startup or if we lose our GPS
#             connection/integrity.
#

proc Init_Data { } {
  global stuff

  Debug "Init_Data" "Clearing variables"

  set stuff(utc)    ""
  set stuff(sec)    ""
  set stuff(date)   ""
  set stuff(lat)    ""
  set stuff(lath)   ""
  set stuff(lon)    ""
  set stuff(lonh)   ""
  set stuff(latlon) ""
  set stuff(dec)    ""
  set stuff(dech)   ""
  set stuff(lonh)   ""
  set stuff(lath)   ""
  set stuff(grid)   ""
  set stuff(knots)  ""
  set stuff(speed)  ""
  set stuff(course) ""
}

proc Guess_UTC_Offset { } {

  set t [ clock seconds ]
  set s1 [ clock format $t -format "%a %b %d %H:%M:%S" -gmt true ]
  set s2 [ clock format $t -format "%a %b %d %H:%M:%S" -gmt false ]
  set t1 [ clock scan $s1 ]
  set t2 [ clock scan $s2 ]
  return [ expr ( $t1 - $t2 ) / 3600 ]
}

proc Init { } {
  global stuff

  set stuff(debug) 0

  set ::setting(gpsport) ""

  set ::setting(gpsipaddr) 127.0.0.1

  set ::setting(gpsipport) 2947

  set ::setting(sermode) "4800,n,8,1"

  set ::setting(ipport) 32123

  set stuff(utcoffset) [ Guess_UTC_Offset ]

  set stuff(tset) 0

  set stuff(toff) 4

  set stuff(gps_str) ""

  set stuff(hasrmc) 0

  Init_Data
}

proc Save_Loc { } {
  global .

  set fid [ open "gps_loc.ini" w 0666 ]

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

switch -exact -- $tcl_platform(os) {
  "Linux" {
    set stuff(gpsports) [ list "/dev/ttyS0" "/dev/ttyS1" "/dev/ttyS2" "/dev/ttyS3" "/dev/ttyS4" "/dev/ttyS5" "/dev/ttyS6" "GPSD" ]
  }
  "Darwin" {
    set stuff(gpsports) [ list "/dev/cu.USA19QW11P1.1" "/dev/cu.USA19QW11P2.1" "/dev/cu.USA19QW11P3.1" "/dev/cu.USA19QW11P4.1" "/dev/cu.USA19QW11P5.1" "/dev/cu.USA19QW11P6.1" "/dev/cu.USA19QW11P7.1" "GPSD" ]
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
    lappend result "GPSD"

    set result [ lsort -dictionary $result ]

    set stuff(gpsports) $result
  }
}

menubutton .mbgpsport -text "GPS Port" -menu .mbgpsport.m -relief raised
set w [ menu .mbgpsport.m -tearoff 0 ]
foreach b $stuff(gpsports) {
  $w add radio -label $b -variable ::setting(gpsport) -value $b
}
entry .egpsport -textvariable ::setting(gpsport)

label .lgpsipaddr -text "GPSD IP Address"
entry .egpsipaddr -textvariable ::setting(gpsipaddr)

label .lgpsipport -text "GPSD IP Port"
entry .egpsipport -textvariable ::setting(gpsipport)

label .lsermode -text "Serial Port Mode"
entry .esermode -textvariable ::setting(sermode)

label .lipport -text "Server IP Port"
entry .eipport -textvariable ::setting(ipport)

label .ltoff -text "UTC Offset (hrs)"
entry .etoff -textvariable stuff(utcoffset) -state readonly

label .ltset -text "Set Computer Time on Next Reading"
set windows(tsetbutton) [ radiobutton .rbtseten -text "Enable" -variable \
  stuff(tset) -value 1 ]
radiobutton .rbtsetdi -text "Disable" -variable stuff(tset) -value 0

button .br -text "Restart" -command Restart

label .lll -text "Lat Lon (deg)"
entry .ell -textvariable stuff(latlon)

label .lde -text "Declination (deg)"
entry .ede -textvariable stuff(dec)

label .lsp -text "Speed (mph)"
entry .esp -textvariable stuff(speed)

label .lco -text "Course (deg)"
entry .eco -textvariable stuff(course)

label .lgr -text "Grid"
entry .egr -textvariable stuff(grid)

label .lda -text "Date"
entry .eda -textvariable stuff(date)

label .lut -text "UTC"
entry .eut -textvariable stuff(utc)

label .lse -text "Seconds"
entry .ese -textvariable stuff(sec)

button .bd -text "Exit" -command My_Exit

grid .mbgpsport .egpsport -pady 2 -padx 2 -sticky news
grid .lgpsipaddr   .egpsipaddr   -pady 2 -padx 2 -sticky news
grid .lgpsipport   .egpsipport   -pady 2 -padx 2 -sticky news
grid .lsermode  .esermode -pady 2 -padx 2 -sticky news
grid .lipport   .eipport   -pady 2 -padx 2 -sticky news
grid .ltoff     .etoff     -pady 2 -padx 2 -sticky news
grid .ltset     -         -pady 2 -padx 2 -sticky news
grid .rbtseten  -         -pady 2 -padx 2 -sticky news
grid .rbtsetdi  -         -pady 2 -padx 2 -sticky news
grid .br        -         -pady 2 -padx 2 -sticky news
grid .lll       .ell      -pady 2 -padx 2 -sticky news
grid .lde       .ede      -pady 2 -padx 2 -sticky news
grid .lsp       .esp      -pady 2 -padx 2 -sticky news
grid .lco       .eco      -pady 2 -padx 2 -sticky news
grid .lgr       .egr      -pady 2 -padx 2 -sticky news
grid .lda       .eda      -pady 2 -padx 2 -sticky news
grid .lut       .eut      -pady 2 -padx 2 -sticky news
grid .lse       .ese      -pady 2 -padx 2 -sticky news
grid .bd        -         -pady 2 -padx 2 -sticky news

grid .lgpsipaddr  -sticky nes
grid .lgpsipport  -sticky nes
grid .lsermode -sticky nes
grid .lipport  -sticky nes
grid .ltoff    -sticky nes
grid .lll      -sticky nes
grid .lde      -sticky nes
grid .lsp      -sticky nes
grid .lco      -sticky nes
grid .lgr      -sticky nes
grid .lda      -sticky nes
grid .lut      -sticky nes
grid .lse      -sticky nes

set windows(debug) [ Build_Debug .debug ]
wm title . "GPS Module"
if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
  catch { wm iconbitmap . -default gps.ico }
}
wm protocol . WM_DELETE_WINDOW My_Exit
wm resizable . 0 0

Init

if { [ file readable "gps.ini" ] } {
  source "gps.ini"
}

GPS_Open
Server_Open

bind all <Alt-Key-u> Popup_Debug

if { [ file readable "gps_loc.ini" ] } {
  source "gps_loc.ini"
}
