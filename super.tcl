#/bin/sh
# the next line restarts using tclsh \
exec wish "$0" "$@"

# for database functions
switch -exact -- $::tcl_platform(os) {
  "Linux" {
    package require Mk4tcl
  }
  "Darwin" {
    package require Mk4tcl
  }
  default {
    load Mk4tcl.dll
  }
}

# merge two lists

proc mymerge { old new } {

  foreach n $new {
    if { [ lsearch $old $n ] < 0 } {
      Debug "mymerge" "Did not find $n in $old, adding"
      set old [ lappend old $n ]
      Debug "mymerge" "new list $old"
    }
  }

  return $old
}

proc Bear_Calc { } {
  global stuff windows

  set latlonl "$::setting(mylat) $::setting(mylon)"
  set latlonr "$stuff(lat) $stuff(lon)"

  if { $latlonl != $latlonr } {

    set pi [ expr 2 * asin( 1.0 ) ]

    scan $latlonl "%f %f" latl lonl
    scan $latlonr "%f %f" latr lonr

    set dlon [ expr ( $lonl - $lonr ) / 180.0 * $pi ]
    set mylatl [ expr ( $latl / 180.0 * $pi ) ]
    set mylatr [ expr ( $latr / 180.0 * $pi ) ]

    set temp [ expr sin( $mylatl ) * sin( $mylatr ) + \
                    cos( $mylatl ) * cos( $mylatr ) * cos( $dlon ) ]

    if { $temp > 1 } { set temp 1.0 }

    set dist [ expr acos( $temp ) ]
    set stuff(rang) [ expr round(10.0 * ($dist * 3960.0)) / 10.0 ]

    set temp [ expr ( sin( $dist ) * cos ( $mylatl ) ) ]
    if { $temp == 0 } {
      set stuff(brng) 0.0
    } else {
      set temp [ expr ( sin( $mylatr ) - sin( $mylatl ) * cos( $dist ) ) / \
        $temp ]

      if { $temp > 1 } { set temp 1.0 }
      if { $temp < -1 } { set temp -1.0 }

      set stuff(brng) [ expr round((acos( $temp ) * 180.0 / $pi) * 10.0) / 10.0 ]
      if { $dlon > 0.0 } then {
        set stuff(brng) [ expr 360.0 - $stuff(brng) ]
      }
    }

    set temp [ expr ( sin( $dist ) * cos( $mylatr ) ) ]
    if { $temp == 0 } {
      set stuff(rbrng) 0.0
    } else {
      set temp [ expr ( sin( $mylatl ) - sin( $mylatr ) * cos( $dist ) ) / \
         $temp ]

      if { $temp > 1 } { set temp 1.0 }
      if { $temp < -1 } { set temp -1.0 }

      set stuff(rbrng) [ expr round((acos( $temp ) * 180.0 / $pi) * 10.0) / 10.0 ]
      if { $dlon < 0.0 } then {
        set stuff(rbrng) [ expr 360.0 - $stuff(rbrng) ]
      }
    }

  } else {

    set stuff(brng) 0.0

    set stuff(rbrng) 180.0

    set stuff(rang) 0.0
  }

  return
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
}

proc To_Grid { latlon } {

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

  return [ string toupper $grid ]
}

proc Save_Settings { } {

  set fid [ open "super.ini" w 0666 ]

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
  Save_Loc
  Save_Settings
  exit
}

proc Commit_Exit { } {

  set ok [ tk_messageBox -icon warning -type okcancel \
    -title "Confirm Super Lookup Module Commit and Exit" -message \
    "On exit, the database will be committed, saving all changes.\n\nDo you really want to exit the Super Lookup Module?\nSelect Ok to exit or Cancel to abort exit.\n" ]
  if { $ok != "ok" } {
    return
  }

  mk::file commit db
  mk::file close db
  Net_Exit
}

proc My_Exit { } {

  set ok [ tk_messageBox -icon warning -type okcancel \
    -title "Confirm Super Lookup Module Exit without Commit" -message \
    "On exit, the database will NOT be committed, and any changes will be lost.\nNote: to commit and then exit, see the File menu.\n\nDo you really want to exit the Super Lookup Module?\nSelect Ok to exit or Cancel to abort exit.\n" ]
  if { $ok != "ok" } {
    return
  }

  # This does NOT save the database because -nocommit was used on open.
  mk::file close db
  Net_Exit
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
        -title "Super Lookup Module Network Error" -message \
        "Cannot open socket on $::setting(ipport).\nModule already running?\nSelect Ok to continue anyway or Cancel to exit." ]
    if { $ok != "ok" } {
      Net_Exit
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
}

proc Serve_Request { sock } {
  global stuff
  if {[eof $sock] || [catch {gets $sock line}]} {
    close $sock
  } else {
    if { $line == "hello?" } {
      Debug "Serve_Request" "Received hello request, replying with hello"
      puts $sock "hello."
      flush $sock
    } elseif { [ string range $line 0 6 ] == "lookup!" } {
      set l [ lindex [ split $line ] 1 ]
      set l [ string trim [ string toupper $l ] ]
      Debug "Serve_Request" "Received look up request for $l"
      set stuff(call) $l

      if { [ Lookup ] } {

        foreach mt $stuff(matchlist) {
          puts $sock "$mt"
        }

      } else {
        puts $sock ""
      }
      puts $sock "done"

      flush $sock

    } elseif { [ string range $line 0 5 ] == "lookup" } {
      set l [ lindex [ split $line ] 1 ]
      set l [ string trim [ string toupper $l ] ]
      Debug "Serve_Request" "Received quiet look up request for $l"
      set stuff(call) $l
      Lookup
    } elseif { [ string range $line 0 4 ] == "quit!" } {
      Debug "Serve_Request" "Received network exit request"
      Net_Exit
    } else {
      puts $sock "Received unknown command"
      flush $sock
    }
  }
}

#
# Brag
#

proc About { } {
  global stuff

  tk_messageBox -icon info -type ok -title About \
    -message "RoverLog Super Lookup
by Tom Mayo

http://roverlog.2ub.org/"
}

proc Init_Settings { } {
  set ::setting(bands) {50 144 222 432 902 1.2G 2.3G 3.4G 5.7G 10G}
  set ::setting(mkfile) "pij.mk"
  set ::setting(mycall) "N0NE"
  set ::setting(mygrid) ""
  set ::setting(mylat) ""
  set ::setting(mylon) ""
  set ::setting(ipport) 32128
  set ::setting(entryfont) {courier 8}
  set ::setting(lookupastype) 1
}

proc Init { } {
  global stuff

  set stuff(debug) 0
  set stuff(lastcall) ""
  set stuff(entries) 0
  set stuff(matches) 0

  Draw_Matches_Key
}

proc Save_Loc { } {
  global .

  set fid [ open "super_loc.ini" w 0666 ]

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

proc Grab_Match { mode } {
  global windows stuff

  set stuff(grabcall) ""

  if { $mode == "click" } {
    set lineno [ $windows(matchlist) index anchor ]
  } else {
    set lineno 0
  }

  $windows(matchlist) activate $lineno
  $windows(matchlist) selection clear 0 end
  $windows(matchlist) selection set $lineno
  $windows(matchlist) see $lineno

  set mt [$windows(matchlist) get active]
  if { $mt == "" } {
    return 0
  }
  binary scan $mt "a8x1a20x1a6x1a9x1a10x1" index call grid lat lon
  set p [ expr 57 + [ llength $::setting(bands) ] * 2 ]
  set bands [ string range $mt 58 $p ]
  incr p
  set notes [ string range $mt $p end ]

  set stuff(grabcall)   [ string toupper [ string trim $call ] ]
  if { $mode == "click" } {
    set stuff(call)     $stuff(grabcall)
  }
  set stuff(index)    $index
  set stuff(lat)      [ string toupper [ string trim $lat ] ]
  set stuff(grablat)  [ string toupper [ string trim $lat ] ]
  set stuff(lon)      [ string toupper [ string trim $lon ] ]
  set stuff(grablon)  [ string toupper [ string trim $lon ] ]
  set stuff(grid)     [ string toupper [ string trim $grid ] ]

  set i 0
  set j 0
  set stuff(hisbands) ""
  foreach b $::setting(bands) {
    set c [ string range $bands $i $i ]
    if { $c == "!" } {
      if { $j > 0 } {
        set stuff(hisbands) "$stuff(hisbands) $b"
      } else {
        set stuff(hisbands) "$b"
        incr j 
      }
    }
    incr i 2
  }
  set stuff(notes) [ string trim $notes ]

  # update bearing
  Bear_Calc

  if { $stuff(grabcall) != "" && $stuff(grid) != "" } {
    return 1
  } else {
    return 0
  }
}

proc Lookup { } {
  global stuff

  set stuff(entries) [ $::hash_map size ]
  set stuff(matches) 0

  if { $::setting(mylat) == "" || $::setting(mylon) == "" } {
    set ::setting(mygrid) [ string toupper $::setting(mygrid) ]
    if { [ Valid_Grid $::setting(mygrid) ] } {
      # convert grid to lat/lon for database
      set latlon [ split [ To_LatLon $::setting(mygrid) ] ]
      set ::setting(mylat) [ lindex $latlon 0 ]
      set ::setting(mylon) [ lindex $latlon 1 ]
    } else {
      # complain
      tk_messageBox -icon error -type ok \
        -title "Invalid My Grid Specified" \
        -message "Before you can perform lookups, you must specify your Grid or Lat/Lon."
      return 0
    }
  } else {
    if { $::setting(mylat) < -90 || $::setting(mylat) > 90 || $::setting(mylon) < -180 || $::setting(mylon) > 180 } {
      # complain
      tk_messageBox -icon error -type ok \
        -title "Invalid My Location Specified" \
        -message "Please specify a valid Lat/Lon or Grid for My Location."
      return 0
    }
    set ::setting(mygrid) [ To_Grid "$::setting(mylat) $::setting(mylon)" ]
  }

  set call [ string toupper [ string trim $stuff(call) ] ]

  set stuff(lat) ""
  set stuff(lon) ""
  set stuff(grid) ""
  set stuff(hisbands) ""
  set stuff(notes) ""

  if { [ string length $call ] < 3 } {
    return 0
  }

  if { [ string first "," $call ] >= 0 } {

    set s [ split $call " ," ]
    set state [ lindex $s end ]
    set s [ lreplace $s end end ]

    set city ""

    foreach n $s {
      if { $n != "" } {
        if { $city == "" } {
          set city "$n"
        } else {
          set city "${city}_${n}"
        }
      }
    }

    set call "${state}-${city}"
  }

  set stuff(matchlist) {}

  if { [ string first "*" $call ] >= 0 || [ string first "?" $call ] >= 0 } {
    set rv [ $::hash_map select -glob call_location "$call" ]
  } else {
    set rv [ $::hash_map select -glob call_location "*${call}*" ]
  }

  set stuff(matches) [ $rv size ]

  if { $stuff(matches) == 0 } {
    return 0
  }

  for { set i 0 } { $i < $stuff(matches) } { incr i } {

    set index [ lindex [ $rv get $i ] 1 ]

    set call     [ $::hash_map get $index call_location ]
    set lat      [ $::hash_map get $index lat ]
    set lon      [ $::hash_map get $index lon ]
    set bandlist [ $::hash_map get $index bands ]
    set notes    [ $::hash_map get $index notes ]

    set grid [ To_Grid "$lat $lon" ]

    # make the band annunciator
    set bands ""
    foreach b $::setting(bands) {
      if { [ lsearch -exact $bandlist $b ] >= 0 } {
        # worked
        set t "!"
      } else {
        set t "."
      }

      # append to running string
      set bands "$bands $t"
    }

    set line [ format "%8.8d %-20.20s %-6.6s %+09.5f %+010.5f" $index $call $grid $lat $lon ]
    set line "${line}$bands $notes"
    lappend stuff(matchlist) $line
 }

 rename $rv ""

 return [ Grab_Match first ]
}

# Delete_Record - wipes out the first record found with the given call/location.

proc Delete_Record { } {
  global stuff

  scan $stuff(index) "%d" index

  set ok [ tk_messageBox -icon warning -type okcancel \
    -title "Confirm record deletion" -message \
    "Do you really want to delete record $index?\nSelect Ok to delete or Cancel to abort." ]
 
  if { $ok != "ok" } {
    return
  }

  $::hash_map delete $index

  Lookup
}
#
#  Valid_Band - procedure to determine if the given band is an
#               element in the list of bands.
#

proc Valid_Band { x } {
  global stuff
  
  # This allows bands > 10 GHz to be accepted, although they are ditched later.
  set bands [ list 50 144 222 432 902 1.2G 2.3G 3.4G 5.7G 10G 24G 47G 76G 119G 142G 241G 300G ]

  if { [ lsearch -exact $bands $x ] != -1 } {
    return 1
  } else {
    return 0 
  }
}

#
#  Valid_Grid - procedure to determine if the variable contains
#               two capital letters followed by two numbers and
#               finally optionally followed by two lower case
#               letters.
#

proc Valid_Grid { x } {
  set y [ string toupper $x ]
  return [regexp {^[A-Z][A-Z][0-9][0-9]([A-Z][A-Z])?$} $y]
}

#
#  To_LatLon - procedure to convert a four- or six-digit grid square
#              into latitude and longitude.
#

proc To_LatLon { grid } {

  set temp [ string toupper $grid ]

  if { [ Valid_Grid $grid ] } {

  if { [ scan $temp "%c%c%c%c%c%c" lon1 lat1 lon2 lat2 lon3 lat3 ] < 6 } {
    set lon3 77.0
    set lat3 77.0
  }

  set lat [ expr ( $lat1 - 65.0) * 10.0 ]
  set lon [ expr ( $lon1 - 65.0) * 20.0 ]

  set lat [ expr $lat + $lat2 - 48.0 ]
  set lon [ expr $lon + ($lon2 - 48.0) * 2.0 ]

  set lat [ expr $lat + 1.25 / 60.0 + \
    ( $lat3 - 65.0 ) / 24.0 ]
  set lon [ expr $lon + 2.5 / 60.0 + \
    ( $lon3 - 65.0 - 12.0 * (int($lon) % 2)) / 12.0 ]

  set lat [ expr $lat - 90.0 ]
  set lon [ expr $lon - 180.0 ]

  return [ format "%f %f" $lat $lon ]

  } else {

  return "0 0"

  }
}

proc Valid_Location { } {
  global stuff

  if { $stuff(lat) == "" || $stuff(lon) == "" } {
    set stuff(grid) [ string toupper $stuff(grid) ]
    if { [ Valid_Grid $stuff(grid) ] } {
      # convert grid to lat/lon for database
      set latlon [ split [ To_LatLon $stuff(grid) ] ]
      set stuff(lat) [ lindex $latlon 0 ]
      set stuff(lon) [ lindex $latlon 1 ]
    } else {
      # complain
      tk_messageBox -icon error -type ok \
        -title "Invalid Grid Specified" \
        -message "Please specify a valid Lat/Lon or Grid."
      return 0
    }
  } else {
    if { $stuff(lat) < -90 || $stuff(lat) > 90 || $stuff(lon) < -180 || $stuff(lon) > 180 } {
      # complain
      tk_messageBox -icon error -type ok \
        -title "Invalid Location Specified" \
        -message "Please specify a valid Lat/Lon or Grid."
      return 0
    }
  }

  return 1
}

# Add_Record - inserts a new record, calculating the lat/lon if necessary. 

proc Add_Record { } {
  global stuff

  if { ! [ Valid_Location ] } {
    return
  }

  # TODO: see if we need an iterator here.
  $::hash_map insert end call_location $stuff(call) lat $stuff(lat) lon $stuff(lon) bands $stuff(hisbands) notes $stuff(notes)

  Lookup
}

# Update_Record - re-finds the record based upon the call/location and replaces it.

proc Update_Record { } {
  global stuff

  # save the information to that record
  $::hash_map set $stuff(index) call_location $stuff(call) lat $stuff(lat) lon $stuff(lon) bands $stuff(hisbands) notes $stuff(notes)

  Lookup
}

proc New { } {
  global stuff

  set types {
    {{Metakit Database Files} {.mk}}
  }

  set ::setting(mkfile) [tk_getSaveFile -initialfile "untitled.mk" -defaultextension ".mk" -filetypes $types]

  if { $::setting(mkfile) == "" } {
    return
  }

  set ok [ tk_messageBox -icon warning -type yesnocancel \
    -title "Commit Database?" -message \
    "Do you want to commit the active database before creating the new one?\nSelect Yes to save any changes, No to abandon changes, or Cancel to abort." ]
  if { $ok == "cancel" } {
    return
  }
  if { $ok == "yes" } {
    mk::file commit db
  }

  mk::file close db
  rename $::hash_map ""

  mk::file open db $::setting(mkfile) -nocommit

  mk::view layout db.super { call_location lat:F lon:F bands notes }
  mk::view open db.super db::_data
  mk::view layout db.super_map {_H:I _R:I}
  mk::view open db.super_map map
  set ::hash_map [ db::_data view hash map 1 ]

  Lookup
  Set_Title
}

proc Open { } {
  global stuff

  set types {
    {{Metakit Database Files} {.mk}}
  }

  set ::setting(mkfile) [tk_getOpenFile -initialfile "" -defaultextension ".mk" -filetypes $types]

  if { $::setting(mkfile) == "" } {
    return
  }

  set ok [ tk_messageBox -icon warning -type yesnocancel \
    -title "Commit Database?" -message \
    "Do you want to commit the active database before opening the new one?\nSelect Yes to save any changes, No to abandon changes, or Cancel to abort." ]
  if { $ok == "cancel" } {
    return
  }
  if { $ok == "yes" } {
    mk::file commit db
  }

  mk::file close db
  mk::file open db $::setting(mkfile) -nocommit

  mk::view layout db.super { call_location lat:F lon:F bands notes }
  mk::view open db.super db::_data
  mk::view layout db.super_map {_H:I _R:I}
  mk::view open db.super_map map
  set ::hash_map [ db::_data view hash map 1 ]

  Lookup
  Set_Title
}

# For "N1MU" or "N1MU.1", return "N1MU".

proc Call_Base { call } {
  set i [ string last "\." $call ] 
  if { $i > 0 } {
    incr i -1
    return [ string range $call 0 $i ]
  } else {
    return $call
  }
}

proc Call_Iterator { call } {
  set i [ string last "\." $call ] 
  if { $i > 0 } {
    incr i
    return [ string range $call $i end ]
  } else {
    return 0
  }
}

proc Import { } {
  global stuff

  set types {
    {{RoverLog Lookup Files} {.lup}}
  }

  set fn [tk_getOpenFile -initialfile "" -defaultextension ".lup" -filetypes $types]

  if { $fn == "" } {
    return
  }

  set fid [open $fn r]

  set calls {}

  while { [gets $fid line] >= 0 } {

    set call [string toupper [string trim [string range $line 5 10]]]
    lappend calls $call
    set rest [string range $line 12 end]

    foreach b $rest {

      # if this field is a valid grid, put it in the grid list
      if { [ Valid_Grid $b ] == 1 } {

        set b [ string toupper $b ]

        # check to see if we already have any grids for this call
        if { [ info exists lookupgrid($call) ] } {

          # check to see if we already have this grid
          set i [ lsearch -glob $lookupgrid($call) "${b}*" ]

          # if not, add this on the end
          if { $i < 0 } {

            lappend lookupgrid($call) $b

            # we have this grid for this call, but is the new one better?
          } else {

            # here's the existing one
            set ex [ lindex $lookupgrid($call) $i ]

            # compare lengths.  if new one is longer, use it.
            if { [ string length $b ] >= [ string length $ex ] } {

              # remove the existing one.
              set lookupgrid($call) [ lreplace $lookupgrid($call) $i $i ]

              # add the new one.
              lappend lookupgrid($call) $b
            }
          }

        # this is the first we've heard of this call.  start a new list.
        } else {

          set lookupgrid($call) [ list $b ]

        }

        continue
      }

      # otherwise, if this field is a valid band, put it there
      if { [ Valid_Band $b ] == 1 } {

        if { [ info exists lookupband($call) ] } {
          if { [ lsearch -exact $lookupband($call) $b ] < 0 } {
            lappend lookupband($call) $b
          }
        } else {
          set lookupband($call) [ list $b ]
        }

        continue
      }

      # otherwise, this must be notes
      if { [ info exists lookupnotes($call) ] } {
        set lookupnotes($call) "$lookupnotes($call) $b"
      } else {
        set lookupnotes($call) "$b"
      }

    }

    if { ! [ info exists lookupgrid($call) ] } {
      set lookupgrid($call) ""
    }

    if { ! [ info exists lookupband($call) ] } {
      set lookupband($call) ""
    }

    if { ! [ info exists lookupnotes($call) ] } {
      set lookupnotes($call) ""
    }
  }

  foreach c $calls {
    
    Debug "Import" "Processing $c ($lookupgrid($c))"

    foreach g $lookupgrid($c) {

      # identify the new data
      set newgrid4 [ string range $g 0 3 ]
      set lat_lon [ split [ To_LatLon $g ] ]
      set lat [ lindex $lat_lon 0 ]
      set lon [ lindex $lat_lon 1 ]
      set grid [ To_Grid "$lat $lon" ]

      # TODO: do we need this?
      # format these in the standard way. otherwise extra crap will be stored, throwing off matching
      # in normal operation.
      # set lat [ format "%+09.5f" $lat ]
      # set lon [ format "%+010.5f" $lon ]

      # if we have a match for this call, check for grid matches

      # The strategy here is to check for this call already.  If we find the call 
      # look through each match, then see if we have a match for this location already.
      # If we have a match, replace the entry with the new location and merge everything else.

      set rv [ $::hash_map select -glob call_location "${c}*" ]

      set stuff(matches) [ $rv size ]
      Debug "Import" "$stuff(matches) possible matches for this call"

      set maxiterator -1

      set needtoadd 1

      if { $stuff(matches) > 0 } {
        # go through call matches
        for { set i 0 } { $i < $stuff(matches) } { incr i } {

          set index [ lindex [ $rv get $i ] 1 ]

          set excall     [ $::hash_map get $index call_location ]
          set exlat      [ $::hash_map get $index lat ]
          set exlon      [ $::hash_map get $index lon ]
          set exgrid     [ To_Grid "$exlat $exlon" ]
          set exgrid4    [ string range $exgrid 0 3 ]
          set exbands    [ $::hash_map get $index bands ]
          set exnotes    [ $::hash_map get $index notes ]

          Debug "Import" "Checking [ Call_Base $excall ] vs. $c and $exgrid4 vs. $newgrid4"

          # check for an exact match for the call
          if { [ Call_Base $excall ] == $c } {

            # if this is a new grid, we're going to add a new iterator.
            if { $exgrid4 != $newgrid4 } {

              # get call or location iterator (i.e. N1MU.n)
              set iterator [ Call_Iterator $excall ]
              if { $iterator > $maxiterator } {
                set maxiterator $iterator
              }
            
            # if grids match
            } else {

              Debug "Import" "Updating record..."
              Debug "Import" "Existing bands for $c = $exbands"
              Debug "Import" "Existing notes for $c = $exnotes"

              set newbands [ mymerge "$exbands" "$lookupband($c)" ]
              set newnotes [ mymerge "$exnotes" "$lookupnotes($c)" ]

              Debug "Import" "New bands for $c = $newbands"
              Debug "Import" "New notes for $c = $newnotes"

              # replace this entry, with merged bands and notes
              $::hash_map set $index call_location $excall lat $lat lon $lon bands $newbands notes $newnotes

              # clear flag, i.e. no need to add this record, it's updated
              set needtoadd 0
            }
          }
        }

        if { $needtoadd == 1 } {
          incr maxiterator
          if { $maxiterator } {
            Debug "Import" "Adding new record for ${c}.${maxiterator} with $lookupband($c) $lookupnotes($c)"
            $::hash_map insert end call_location ${c}.${maxiterator} lat $lat lon $lon bands "$lookupband($c)" notes "$lookupnotes($c)"
          } else {
            Debug "Import" "Adding new record for $c with $lookupband($c) $lookupnotes($c)"
            $::hash_map insert end call_location $c lat $lat lon $lon bands "$lookupband($c)" notes "$lookupnotes($c)"
          }
        }

      } else {
        Debug "Import" "Adding new record for $c with $lookupband($c) $lookupnotes($c)"
        $::hash_map insert end call_location $c lat $lat lon $lon bands "$lookupband($c)" notes "$lookupnotes($c)"
      }
    }
  }

  Lookup
}

proc Build_Main { } {
  global . windows stuff

  menu .m -relief raised -borderwidth 2
  . config -menu .m
  menu .m.mFile -tearoff 0
  .m add cascade -label File -menu .m.mFile
  .m.mFile add command -underline 0 -label "New" -command New
  .m.mFile add command -underline 0 -label "Open..." -command Open
  .m.mFile add command -underline 0 -label "Import..." -command Import
  .m.mFile add command -label "Exit - Commit" -command Commit_Exit
  .m.mFile add command -underline 1 -label "Exit - No Commit" -command My_Exit
  menu .m.mHelp -tearoff 0
  .m add cascade -label Help -menu .m.mHelp
  .m.mHelp add command -label "About" -command About

  frame .bar -borderwidth 2 -relief raised
  label .bar.lipport -text "Server IP Port"
  entry .bar.eipport -textvariable ::setting(ipport) -width 10 \
    -font $::setting(entryfont)

  button .bar.br -text "Restart Server" -command Restart

  label .bar.lmycall -text "My Location"
  set windows(callentry) [ entry .bar.emycall -textvariable ::setting(mycall) \
    -width 10 -font $::setting(entryfont) ]
  label .bar.lmygrid -text "Grid"
  entry .bar.emygrid -textvariable ::setting(mygrid) \
    -font $::setting(entryfont) -width 6
  label .bar.lmylat -text "Latitude"
  entry .bar.emylat -textvariable ::setting(mylat) \
    -font $::setting(entryfont) -width 9
  label .bar.lmylon -text "Longitude"
  entry .bar.emylon -textvariable ::setting(mylon) \
    -font $::setting(entryfont) -width 10
  label .bar.lbear -text "Bearing"
  entry .bar.ebear -textvariable stuff(brng) \
    -font $::setting(entryfont) -width 5
  label .bar.lrang -text "Range"
  entry .bar.erang -textvariable stuff(rang) \
    -font $::setting(entryfont) -width 5

  label .bar.lindex -text "Index"
  entry .bar.eindex -textvariable stuff(index) \
    -font $::setting(entryfont) -width 8 -state readonly
  label .bar.lcall -text "Call/Location"
  set windows(callentry) [ entry .bar.ecall -textvariable stuff(call) \
    -width 10 -font $::setting(entryfont) -bg yellow ]
  label .bar.lgrid -text "Grid"
  entry .bar.egrid -textvariable stuff(grid) \
    -font $::setting(entryfont) -width 6 -bg lightyellow
  label .bar.llat -text "Latitude"
  entry .bar.elat -textvariable stuff(lat) \
    -font $::setting(entryfont) -width 9 -bg lightyellow
  label .bar.llon -text "Longitude"
  entry .bar.elon -textvariable stuff(lon) \
    -font $::setting(entryfont) -width 10 -bg lightyellow
  label .bar.lbands -text "Bands"
  entry .bar.ebands -textvariable stuff(hisbands) \
    -font $::setting(entryfont) -width 20 -bg lightyellow
  label .bar.lnotes -text "Notes"
  entry .bar.enotes -textvariable stuff(notes) \
    -font $::setting(entryfont) -width 20 -bg lightyellow

  grid x           .bar.lmycall .bar.lmygrid .bar.lmylat  .bar.lmylon .bar.lbear  .bar.lrang .bar.lipport x       -pady 2 -padx 2 -sticky news
  grid x           .bar.emycall .bar.emygrid .bar.emylat  .bar.emylon .bar.ebear  .bar.erang .bar.eipport .bar.br -pady 2 -padx 2 -sticky news
  grid .bar.lindex .bar.lcall   .bar.lgrid   .bar.llat    .bar.llon   .bar.lbands -          .bar.lnotes  -       -pady 2 -padx 2 -sticky news
  grid .bar.eindex .bar.ecall   .bar.egrid   .bar.elat    .bar.elon   .bar.ebands -          .bar.enotes  -       -pady 2 -padx 2 -sticky news

  frame  .fm -borderwidth 2 -relief raised
  label  .fm.le -text "Total Database Entries"
  entry  .fm.ee -textvariable stuff(entries) -width 10
  label  .fm.lm -text "Matches"
  entry  .fm.em -textvariable stuff(matches) -width 10
  button .fm.bu -text "Lookup" -command Lookup -background pink
  button .fm.bd -text "Delete Record" -command Delete_Record
  button .fm.ba -text "Add Record"    -command Add_Record
  button .fm.bc -text "Update Record" -command Update_Record

  listbox .fm.key -width 72 -height 3 -listvariable stuff(keylist) \
    -font $::setting(entryfont)

  set windows(matchlist) [ listbox .fm.list -width 72 \
    -height 10 -yscrollcommand [ list .fm.scroll set ] \
    -listvariable stuff(matchlist) -font $::setting(entryfont) ]
  scrollbar .fm.scroll -orient vertical -command \
    [ list .fm.list yview ]

  grid .fm.le   .fm.ee .fm.lm .fm.em .fm.bu .fm.bd .fm.ba .fm.bc x          -sticky news -padx 2 -pady 2
  grid .fm.key  -      -      -      -      -      -      -      x          -sticky news -padx 2 -pady 2
  grid .fm.list -      -      -      -      -      -      -      .fm.scroll -sticky news -padx 2 -pady 2

  grid columnconfigure .fm 0 -weight 1
  grid columnconfigure .fm 1 -weight 1
  grid columnconfigure .fm 2 -weight 1
  grid columnconfigure .fm 3 -weight 1
  grid columnconfigure .fm 4 -weight 1
  grid columnconfigure .fm 5 -weight 1
  grid columnconfigure .fm 6 -weight 1
  grid columnconfigure .fm 7 -weight 1
  grid columnconfigure .fm 8 -weight 1
  grid columnconfigure .fm 9 -weight 0

  grid .bar -sticky news
  grid .fm  -sticky news

}

proc Set_Title { } {
  global stuff

  set mkfile [ file tail $::setting(mkfile) ]
  wm title . "Super Lookup - $mkfile"
}

proc Draw_Matches_Key { } {
  global stuff

  set l1 "                                                         "
  foreach b $::setting(bands) {
    if { [ string length $b ] < 3 } {
      set l1 "$l1  "
    } else {
      set t [ string index $b 0 ]
      set l1 "$l1 $t"
    }
  }
  set l1 "$l1      "

  set l2 "                                                         "
  foreach b $::setting(bands) {
    if { [ string length $b ] < 3 } {
      set t [ string index $b 0 ]
    } else {
      set t [ string index $b 1 ]
    }
    set l2 "$l2 $t"
  }
  set l2 "$l2      "

  set l3 "Index    Call/Location        Grid   Latitude  Longitude "
  foreach b $::setting(bands) {
    if { [ string length $b ] < 3 } {
      set t [ string index $b 1 ]
    } else {
      set t [ string index $b 2 ]
    }
    set l3 "$l3 $t"
  }
  set l3 "$l3 Notes"

  set stuff(keylist) [ list "$l1" "$l2" "$l3" ]
}

Init_Settings

if { [ file readable "super.ini" ] } {
  source "super.ini"
}

set windows(debug) [ Build_Debug .debug ]

Build_Main
wm title . "Super Lookup Module"

if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
  wm iconbitmap . super.ico
}
wm protocol . WM_DELETE_WINDOW My_Exit
wm resizable . 0 0

Init

Server_Open

bind all <Alt-Key-u> Popup_Debug

proc Post_Call_Entry_Key { key } {
  global stuff windows

  # Convert to upper string only if necessary.
  if { [ string is alnum "$key" ] } {
    set stuff(call) [ string trim [ string toupper $stuff(call) ] ]
  }

  if { $key == "\r" || \
    ( $::setting(lookupastype) == 1 && \
    [ string length $stuff(call) ] >= 3 ) } {
    Lookup
  } elseif { $key == 65481 } {
    focus $windows(matchlist)
    $windows(matchlist) activate 0
    $windows(matchlist) selection clear 0 end
    $windows(matchlist) selection set 0
    $windows(matchlist) see 0
  }
}

bindtags $windows(callentry) \
  {$windows(callentry) Entry PostCallEntry . all}
bind PostCallEntry <KeyPress> {Post_Call_Entry_Key %A}

bind $windows(matchlist) <ButtonRelease> {+Grab_Match click}

bind $windows(matchlist) <F12> { focus $windows(callentry) }
bind all <Return> {Lookup}

if { [ file readable "super_loc.ini" ] } {
  source "super_loc.ini"
}
puts "opening $::setting(mkfile)"

mk::file open db $::setting(mkfile) -nocommit
mk::view layout db.super { call_location lat:F lon:F bands notes }
mk::view open db.super db::_data
mk::view layout db.super_map {_H:I _R:I}
mk::view open db.super_map map
set ::hash_map [ db::_data view hash map 1 ]
set stuff(entries) [ $::hash_map size ]

Set_Title
