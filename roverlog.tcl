#!/bin/sh
# the next line restarts using wish \
exec wish "$0" "$@"

#
# RoverLog
#
# by Tom Mayo, N1MU
#

set stuff(rlversion) "2_7_5"

#
# Debug - Insert a message into the debug log
#

proc Debug { s m } {
  global windows stuff

  if { $stuff(debug) == 0 } {
    return
  }

  set t [clock seconds]
  set date [clock format $t -format "%Y-%m-%d"]
  set utc [clock format $t -format "%H:%M:%S"]
  set d "$date $utc"

  $windows(debugtext) insert end "$d: $s: $m\n"
  $windows(debugtext) see end

#  puts "$d: $s: $m"

  update idletasks
}

#
# Peer_By_Name - procedure to return the number of the named peer
#                or zero if not found.
#

proc Peer_By_Name { n } {
  global stuff

  for { set i 1 } { $i < 13 } { incr i } {
    if { $n == [ lindex $::setting(p$i) 0 ] } {
      return $i
    }
  }

  return 0
}

#
# Net_Start - procedure to begin accepting network connections on the
#             specified port.
#

proc Net_Start { } {
  global windows stuff

  if { [ info exists stuff(netservid) ] } {
    close $stuff(netservid)
    unset stuff(netservid)
  }

  if { $::setting(netenable) == 0 } { 
    Debug "Net_Start" "Peer networking disabled. Not starting."
    return
  }

  set mypeerno [ Peer_By_Name $::setting(mypeername) ]

  if { $mypeerno == 0 } {
    Debug "Net_Start" "My peer name is invalid. Not starting."
    return
  }

  set mypeerpt [ lindex $::setting(p$mypeerno) 2 ]

  if { $mypeerpt == 0 } {
    Debug "Net_Start" "My peer port is zero. Not starting."
    return
  }

  if [ catch { socket -server Net_Accept $mypeerpt } stuff(netservid) ] {

    tk_messageBox -icon error -type ok \
      -title "Network Server Socket Error" \
      -message "You are probably attempting to start\nRoverLog a second time.  Don't do that."

    exit

  }
  Debug "Net_Start" "Listening socket opened."

  fconfigure $stuff(netservid) -buffering line
  Debug "Net_Start" "Listening socket configured."

  # This is where we need to form TCP socket connections with
  # the other peer nodes.
  
  for { set i 1 } { $i < 13 } { incr i } {

    # If this is me, don't open a socket.
    if { $i == $mypeerno } {
      continue
    }

    Open_Peer $i
  }

  Debug "Net_Start" "Networking startup complete."
}

#
# Open_Peer - procedure to open a socket to a given peer
#

proc Open_Peer { peerno } {
  global stuff

  # Check to see if there is even an entry for this peer number
  if { [ llength $::setting(p$peerno) ] < 3 } {
    return -1
  }

  # Get IP address and port from array
  set peername [ lindex $::setting(p$peerno) 0 ]
  set peerip   [ lindex $::setting(p$peerno) 1 ]
  set peerpt   [ lindex $::setting(p$peerno) 2 ]

  # If the peer is not set up, go on to next.
  if { $peerpt == 0 } {
    return -1
  }

  # open the connection to the peer.
  if [ catch { socket -async $peerip $peerpt } stuff(peersid,$peerno) ] {
    Blacklist p$peerno "connection failed"
    unset stuff(peersid,$peerno)
    return
  }

  # set up the descriptor
  if [ catch { fconfigure $stuff(peersid,$peerno) -buffering line -blocking 0 } ] {
    Blacklist p$peerno "configuration failed"
    return
  }

  set stuff(peerstatus$peerno) "Open"
  set stuff(peertime$peerno) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
}

#
# Net_Accept - procedure to register the serving procedure upon a connection
#              to the networking port.
#

proc Net_Accept { newsock addr port } {
  fconfigure $newsock -buffering line
  fileevent $newsock readable [list Net_Serve $newsock]
}

#
# Net_Serve - procedure to service commands/data coming in via the network.
#

proc Net_Serve { s } {
  global windows stuff lookupband

  if {[eof $s] || [catch {gets $s line}]} {
    close $s
  } else {

    # check to make sure there's an actual line to work on
    if { [ string length [ string trim $line ] ] != 0 } {

      set mypeerno [ Peer_By_Name $::setting(mypeername) ]

      # if this is a QSO coming in, handle that
      if { [ string equal -length 5 "$line" "QSO: " ] == 1 } {

        # this will do dupe checking, etc.
        Add_To_Log "quiet" "net" $line

      # The incoming message is not a QSO, is it a deletion?
      } elseif { [ string equal -length 5 "$line" "DEL: " ] == 1 } {

        # search for the exact same line in the log, if there, delete
        set line [ string range $line 5 end ]

        set bunch [$windows(loglist) get 0 end]
        set lineno [ lsearch -exact $bunch $line ]

        # we found the line, wipe it out and update the databases
        if { $lineno >= 0 } {

          Debug "Net_Serve" "Found QSO to delete on line $lineno"
          # parse out the line
          binary scan $line "x5a5x1a2x1a10x1a4x1a13x5a6x1a13x5a6" \
            band mode date utc mycall sent call recd
          set band [ string trim $band ]
          set sent [ string toupper $sent ]
          set recd [ string toupper $recd ]

          # depending on rules type, make a 4- or 6-digit match pattern
          if { $::setting(rules) == "dist" || $::setting(rules) == "grid6" } {

            if { [ string length $sent ] < 6 } {
              set sent [ string range $sent 0 3 ]
              set sent "${sent}MM"
            }
            if { [ string length $recd ] < 6 } {
              set recd [ string range $recd 0 3 ]
              set recd "${recd}MM"
            }
            set m [ format "QSO: %-5.5s %s %-6.6s %-13.13s     %-6.6s" \
              $band ".. \[0-9\]\[0-9\]\[0-9\]\[0-9\]-\[0-1\]\[0-9\]-\[0-3\]\[0-9\] \[0-2\]\[0-9\]\[0-5\]\[0-9\] \[ 0-9A-Z/\]{17}" \
              $sent $call $recd ]

          } else {

            set sent [ string range $sent 0 3 ]
            set recd [ string range $recd 0 3 ]
            set m [ format "QSO: %-5.5s %s %-4.4s%s %-13.13s     %-4.4s%s" \
              $band ".. \[0-9\]\[0-9\]\[0-9\]\[0-9\]-\[0-1\]\[0-9\]-\[0-3\]\[0-9\] \[0-2\]\[0-9\]\[0-5\]\[0-9\] \[ 0-9A-Z/\]{17}" \
              $sent ".." $call $recd ".." ]

          }

          Debug "Net_Serve" "Looking for other lines matching $m."

          set mfound 0
          set bunch [$windows(loglist) get 0 end]
          set mi [ lsearch -regexp $bunch $m ]
          Debug "Net_Serve" "First match result: $mi."

          if { $mi >= 0 } {
            incr mfound
            incr mi
            set mi [ lsearch -regexp [ lrange $bunch $mi end ] $m]
            Debug "Net_Serve" "Second match result: $mi."
            if { $mi >= 0 } {
              incr mfound
            }
          }

          if { $mfound <= 1 } {
            Debug "Net_Serve" "Only found 1 match. Calling Decrement_Worked or Lookup_Delete."
            Decrement_Worked $band $sent $recd
            Lookup_Delete $band $call $sent $recd
          } else {
            Debug "Net_Serve" "Found more than 1 match. Not calling Decrement_Worked or Lookup_Delete."
          }
          $windows(loglist) delete $lineno

          # redraw stuff each time.  it's unlikely we're getting
          # many of these at once, so performance should be ok.

          set stuff(entries) [$windows(loglist) index end]
          Redraw_Map $stuff(mapcenter)
          Redraw_Score
          Auto_Save
        }

      # this is a refresh command (sent after a whole log is sent).
      } elseif { [ string equal -length 5 "$line" "REF: " ] == 1 } {

        # Net_Log_RX $peername $::setting(mypeername) "<refresh log>"

        # refresh everything
        set stuff(entries) [$windows(loglist) index end]
        Redraw_Map $stuff(mapcenter)
        Redraw_Score
        Auto_Save

      } elseif { [ string equal -length 5 "$line" "RWP: " ] == 1 } {

        scan $line "RWP: %s" peername
        Net_Send "wip" $peername ""

      } elseif { [ string equal -length 5 "$line" "WIP: " ] == 1 } {

        scan $line "WIP: %s busy %d wip %d wiplimit %d" \
          peername busy wip wiplimit
        set peerno [ Peer_By_Name $peername ]
        set stuff($peername,busy) $busy

        # Color pass button
        if { $busy } {
          $windows(peerbutton$peerno) configure -bg yellow
        } else {
          $windows(peerbutton$peerno) configure -bg green
        }

        set stuff($peername,wip) $wip
        set stuff($peername,wiplimit) $wiplimit

      } elseif { [ string equal -length 5 "$line" "SKD: " ] == 1 } {

        Add_Sked_Kernel [ string range $line 5 end ]
        # Only refresh if I'm looking at the peer that the sked is for
        set dummy [ lindex [ split [ string range $line 5 end ] , ] 0 ]
        if { $dummy == $stuff(skedpeer) } {
          Redraw_Skeds "entry"
        }
        Save_Skeds

      } elseif { [ string equal -length 5 "$line" "NOW: " ] == 1 } {

        set t [expr $stuff(utcoffset) * 3600 + [clock seconds]]
        set date [ clock format $t -format "%Y-%m-%d" ]
        set utc  [ clock format $t -format "%H%M" ]

        set peername [ lindex [ split $line ] 1 ]

        set s [ expr 6 + [ string length $peername ] ]
        set t [ string range $line $s end ]
        Add_WIP "$date $utc $t"

        set r [ binary scan $t "a6x1a10x1a13x1a6x1a*" \
          skedband skedfreq skedcall skedrecd skednote ]

        set skedband [ string trim $skedband ]
        set skedfreq [ string trim $skedfreq ]
        set skedcall [ string trim $skedcall ]
        set skedrecd [ string trim $skedrecd ]
        set skednote [ string trim $skednote ]

        Net_Log_RX $peername $::setting(mypeername) "Work $skedcall in $skedrecd on $skedband ($skedfreq)"

      } elseif { [ string equal -length 5 "$line" "DSK: " ] == 1 } {

        Del_Sked_Kernel "deleted" [ string range $line 5 end ]
        # Only refresh if I'm looking at the peer that the sked is for
        set dummy [ lindex [ split [ string range $line 5 end ] , ] 0 ]
        if { $dummy == $stuff(skedpeer) } {
          Redraw_Skeds "entry"
        }
        Save_Skeds

      } elseif { [ string equal -length 5 "$line" "MSK: " ] == 1 } {

        Del_Sked_Kernel "made" [ string range $line 5 end ]
        # Only refresh if I'm looking at the peer that the sked is for
        set dummy [ lindex [ split [ string range $line 5 end ] , ] 0 ]
        if { $dummy == $stuff(skedpeer) } {
          Redraw_Skeds "entry"
        }
        Save_Skeds

      } elseif { [ string equal -length 5 "$line" "FRQ: " ] == 1 } {

        set peername [ lindex [ split $line ] 1 ]
        set freq [ lindex [ split $line ] 2 ]
        set stat [ join [ lrange [ split $line ] 3 end ] ]

        set peerno [ Peer_By_Name $peername ]
        set stuff(peerfreq$peerno) $freq
        set stuff(peerstat$peerno) $stat

        # Set this to allow lookup when changing bands on Sked or Pass win.
        # Note - if there's no skedfrequency for a given band, we use our
        # very own concept of the last operating frequency for the band.
        set b [ Band_By_Freq $freq ]
        set stuff(skedfrequency,$b) $freq

      } elseif { [ string equal -length 5 "$line" "RFQ: " ] == 1 } {

        scan $line "RFQ: %s" peername
        Net_Send "frq" $peername ""

      } elseif { [ string equal -length 5 "$line" "PGR: " ] == 1 } {

        scan $line "PGR: %s" peername
        Debug "Net_Serve" "Got ping response from $peername"

      # TODO - test the following:

      } elseif { [ string equal -length 5 "$line" "LUP: " ] == 1 } {

        # Overwrite lookupgrid, lookupband, and lookupnotes databases.
        # while this is somewhat scary, we need to have the latest
        # information during a contest of what bands a guy has so we
        # don't waste time trying to work "broken" bands.
        Process_LUP_Line "overwrite" "$line"
        set stuff(unsaved) 1

      } elseif { [ string equal -length 5 "$line" "MSG: " ] == 1 } {

        set dummy [ split $line " " ]
        set peername [ lindex $dummy 1 ]
        set msg \
          [ string range $line [ expr 6 + [ string length $peername ] ] end ]

        # put message in network log.
        Net_Log_RX $peername $::setting(mypeername) "$msg"

        # annunciate.
        Annunciate "Msg from $peername:$msg"

        # if the user has configured "noisy" mode, put up a popup.
        if { $::setting(netpopup) == 1 } {
          tk_messageBox -icon info -type ok \
            -title "Incoming Networking Message" \
            -message "$peername:$msg"
        }

      } elseif { [ string equal -length 5 "$line" "ALL: " ] == 1 } {

        set dummy [ split $line " " ]
        set peername [ lindex $dummy 1 ]
        set msg \
          [ string range $line [ expr 6 + [ string length $peername ] ] end ]

        # put message in network log.
        Net_Log_RX $peername all "$msg"

        # annunciate.
        Annunciate "Broadcast from $peername:$msg"

        # if the user has configured "noisy" mode, put up a popup.
        if { $::setting(netpopup) == 1 } {
          tk_messageBox -icon info -type ok \
            -title "Incoming Networking Broadcast" \
            -message "$peername:$msg"
        }
      }
    }
  }
}

#
# Open_Rig - procedure to open a socket to a given rig
#

proc Open_Rig { bandno } {
  global stuff

  # If the configuration is invalid, skip
  if { [ llength $::setting(r$bandno) ] < 4 } {
    Debug "Open_Rig" "Config for band $band ($bandno), port is invalid: $::setting(r$bandno)"
    return
  }

  # Get the port number from array
  set band [ lindex $::setting(r$bandno) 0 ]
  set bandpt [ lindex $::setting(r$bandno) 2 ]

  # If the peer is not set up, skip
  if { $bandpt == 0 } {
    Debug "Open_Rig" "Not starting rig for band $band ($bandno), port is zero"
    return
  }

  if [ catch { socket -async localhost $bandpt } stuff(rigsid,$bandno) ] {
    Blacklist r$bandno "connection failed"
    unset stuff(rigsid,$bandno)
    return
  }

  # set up the connection
  if { [ catch { fconfigure $stuff(rigsid,$bandno) -buffering line } ] } {
    Blacklist r$bandno "configuration failed"
    return
  }

  set stuff(rigstatus$bandno) "Open"
  set stuff(rigtime$bandno) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
}

proc Rig_Puts { bandno m } {
  global stuff

  # skip if not configured
  set bandpt [ lindex $::setting(r$bandno) 2 ]
  if { $bandpt == 0 } {
    return
  }

  # skip if blacklisted
  if { $stuff(blacklist,r$bandno) == 1 } {
    return
  }

  Debug "Rig_Puts" "Sending $m to rig $bandno"

  if { [ catch { puts $stuff(rigsid,$bandno) $m } r ] } {
    Blacklist r$bandno "puts failed: $r"
    return
  }

  # flush $stuff(rigsid,$bandno)

  set stuff(bandstatus$bandno) "$m"
  set stuff(bandtime$bandno) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
}

proc Rig_Gets { bandno } {
  global stuff

  # skip if not configured
  set bandpt [ lindex $::setting(r$bandno) 2 ]
  if { $bandpt == 0 } {
    return
  }

  # skip if blacklisted
  if { $stuff(blacklist,r$bandno) == 1 } {
    return
  }

  if { [ catch { gets $stuff(rigsid,$bandno) } m ] } {
    Blacklist r$bandno "gets failed: $r"
    set m ""
  }

  Debug "Rig_Gets" "Received $m"

  set stuff(bandstatus$bandno) "$m"
  set stuff(bandtime$bandno) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]

  return $m
}

proc Close_Rig { quit bandno } {
  global stuff

  if { [ info exist stuff(rigsid,$bandno) ] } {
    catch { fconfigure $stuff(rigsid,$bandno) -blocking 1 }
    if { $quit == "quit" } {
      catch { puts $stuff(rigsid,$bandno) "quit!" }
    }
    catch { close $stuff(rigsid,$bandno) }
    catch { unset stuff(rigsid,$bandno) }
  }

  set stuff(rigstatus$bandno) "Closed"
  set stuff(rigtime$bandno) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
}

#
# New stuff - handle checkbutton clicks on Pass Window band buttons
#

proc Update_Pass_Band { band } {
  global windows stuff lookupband lookupgrid lookupnotes

  set call [ Drop_Slash "first" [ string toupper [ string trim $stuff(skedcall) ] ] ]
  if { $call == "" } {
    return
  }
  set grid [ string toupper [ string trim $stuff(skedrecd) ] ]

  Debug "Update_Pass_Band" "Updating info for $call"

  # If newly added, make sure the lookupband database includes this band.
  if { $stuff(passhas$band) == 1 } {

    set line [ format "LUP: %-6.6s %s %s" $call $stuff(skedrecd) $band ]
    Process_LUP_Line "append" "$line"
    set stuff(unsaved) 1

  # If deleted, take this band out of the lookupband database.
  } else {

    Debug "Update_Pass_Band" "Taking out $band for $call."
    if { [ info exist lookupband($call) ] } {
      set r [ lsearch $lookupband($call) "$band" ]
      if { $r >= 0 } {
        set lookupband($call) [ lreplace $lookupband($call) $r $r ]
        set stuff(unsaved) 1
      }
    }
  }

  if { [ info exist lookupnotes($call) ] } {
    set t " $lookupnotes($call)"
  } else {
    set t ""
  }

  set line [ format "LUP: %-6.6s %s %s%s" \
    $call $lookupgrid($call) $lookupband($call) $t ]
  Net_Send "zzz" "all" $line

  # update pass window checkbutton display
  What_Bands

  # update lookupwindow if necessary
  if { $stuff(lookuptype) == "partial" } {
    Do_Lookup "partial" $stuff(call) $stuff(recd) $stuff(sent)
  }
}

#
# Build_Standard_Pass
#

proc Build_Standard_Pass { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "Pass"
  wm protocol $f WM_DELETE_WINDOW { wm withdraw $windows(pass) }
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    catch { wm iconbitmap $f log.ico }
  }

  frame $f.f0 -borderwidth 2 -relief raised

  menubutton $f.f0.mBand -text Band -menu $f.f0.mBand.menu -relief raised \
    -underline 0
  entry $f.f0.eBand -state readonly -font $::setting(bigfont) \
  -textvariable stuff(skedband) -width 6 -readonlybackground lightyellow

  set passbandmenu [ menu $f.f0.mBand.menu -tearoff 0 ]
  foreach b $::setting(bands) {
    $passbandmenu add radio -label $b -variable stuff(skedband) -value $b \
      -command { Set_Sked_Freq_From_Band }
  }

  label $f.f0.lf -text "Freq"
  set windows(passfreqentry) [ entry $f.f0.ef -textvariable \
    stuff(skedfreq) -width 10 -font $::setting(bigfont) -background yellow ]

  label $f.f0.lc -text "Call"
  set windows(passcallentry) [ entry $f.f0.ec -textvariable stuff(skedcall) \
    -width 14 -font $::setting(bigfont) -background yellow ]

  label $f.f0.lr -text "Recd"
  set windows(passrecdentry) [ entry $f.f0.er -textvariable stuff(skedrecd) \
    -width 10 -font $::setting(bigfont) -background yellow ]

  label $f.f0.ln -text "Note"
  entry $f.f0.en -textvariable stuff(skednote) -width 20 -font \
    $::setting(entryfont) -background yellow

  grid $f.f0.mBand $f.f0.lf $f.f0.lc $f.f0.lr $f.f0.ln \
    -sticky news -padx 1 -pady 1
  grid $f.f0.eBand $f.f0.ef $f.f0.ec $f.f0.er $f.f0.en \
    -sticky news -padx 1 -pady 1

  # New stuff - Make checkbuttons to indicate what bands this guy has.
  frame $f.f2 -borderwidth 2 -relief raised
  set i 0
  foreach b $::setting(bands) {
    set windows(passhascb$i) [ checkbutton $f.f2.cb$i -text $b \
      -variable stuff(passhas$b) -command "Update_Pass_Band $b" ]
    pack $f.f2.cb$i -side left
    incr i
  }

  frame $f.f3 -borderwidth 2 -relief raised

  label $f.f3.ld -text "Next Available Date"
  entry $f.f3.ed -textvariable stuff(nextskeddate) \
    -width 11 -font $::setting(entryfont)
  label $f.f3.lu -text "UTC"
  entry $f.f3.eu -textvariable stuff(nextskedutc) \
    -width 6 -font $::setting(entryfont)
  label $f.f3.ll -text "Local Time"
  entry $f.f3.el -textvariable stuff(nextskedlocal) \
    -width 6 -font $::setting(entryfont)

  grid $f.f3.ld $f.f3.ed $f.f3.lu $f.f3.eu $f.f3.ll $f.f3.el \
    -sticky nws -padx 1 -pady 1

  frame $f.f1 -borderwidth 2 -relief raised

  button $f.f1.bp -text "Pass" -command Make_Pass -width 6 -background pink
  label $f.f1.ls -text "to"
  menubutton $f.f1.mPeer -text "Peer..." -menu $f.f1.mPeer.menu -relief \
    raised
  set skedpeermenu [menu $f.f1.mPeer.menu -tearoff 0]
  for { set i 1 } { $i < 13 } { incr i } {
    set a [ lindex $::setting(p$i) 0 ]
    $skedpeermenu add radio -label $a -variable stuff(skedpeer) -value $a \
      -command { Sked_Peer "current" }
  }
  entry $f.f1.ePeer -textvariable stuff(skedpeer) -width 16 \
    -state readonly -font $::setting(bigfont) -readonlybackground lightyellow

  label $f.f1.lw -text "His WIP"
  set windows(passwipentry) [ entry $f.f1.ew -textvariable stuff(wip) \
    -width 4 -font $::setting(entryfont) -state readonly ]
  label $f.f1.ll -text "Limit"
  set windows(passwiplimitentry) [ entry $f.f1.el -textvariable \
    ::setting(wiplimit) -width 4 \
    -font $::setting(entryfont) -state readonly ]
  label $f.f1.lb -text "Busy"
  set windows(passbusyentry) [ entry $f.f1.eb -textvariable stuff(busy) \
    -width 4 -font $::setting(entryfont) -state readonly ]

  grid $f.f1.bp $f.f1.ls $f.f1.mPeer $f.f1.ePeer $f.f1.lw $f.f1.ew $f.f1.ll \
    $f.f1.el $f.f1.lb $f.f1.eb -sticky news -padx 1 -pady 1

  grid $f.f0 -sticky news
  grid $f.f2 -sticky news
  grid $f.f3 -sticky news
  grid $f.f1 -sticky news

  wm resizable $f 0 0
  update idletasks

  return $f
}

#
# Build_Pass
#

proc Build_Pass { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "Pass"
  wm protocol $f WM_DELETE_WINDOW { wm withdraw $windows(pass) }
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    catch { wm iconbitmap $f log.ico }
  }

  frame $f.f0 -borderwidth 2 -relief raised

  # first row
  label $f.f0.lc -text "Call"
  label $f.f0.lr -text "Recd"
  menubutton $f.f0.mPeer -text "Peer..." -menu $f.f0.mPeer.menu -relief \
    raised
  set skedpeermenu [menu $f.f0.mPeer.menu -tearoff 0]
  for { set i 1 } { $i < 13 } { incr i } {
    set a [ lindex $::setting(p$i) 0 ]
    $skedpeermenu add radio -label $a -variable stuff(skedpeer) -value $a \
      -command { Sked_Peer "current" }
  }
  menubutton $f.f0.mBand -text Band -menu $f.f0.mBand.menu -relief raised \
    -underline 0
  set passbandmenu [ menu $f.f0.mBand.menu -tearoff 0 ]
  foreach b $::setting(bands) {
    $passbandmenu add radio -label $b -variable stuff(skedband) -value $b \
      -command { Set_Sked_Freq_From_Band }
  }
  label $f.f0.lf -text "Freq"

  grid x $f.f0.lc x $f.f0.lr x $f.f0.mPeer x $f.f0.mBand x $f.f0.lf \
    -sticky news -padx 1 -pady 1

  label $f.f0.lPass -text "Pass"
  set windows(passcallentry) [ entry $f.f0.ec -textvariable stuff(skedcall) \
    -width 14 -font $::setting(bigfont) -background yellow ]
  label $f.f0.lin -text "in"
  set windows(passrecdentry) [ entry $f.f0.er -textvariable stuff(skedrecd) \
    -width 10 -font $::setting(bigfont) -background yellow ]
  label $f.f0.lto -text "to"
  entry $f.f0.ePeer -textvariable stuff(skedpeer) -width 16 \
    -state readonly -font $::setting(bigfont) -readonlybackground lightyellow
  label $f.f0.lon -text "on"
  entry $f.f0.eBand -state readonly -font $::setting(bigfont) \
  -textvariable stuff(skedband) -width 6 -readonlybackground lightyellow
  label $f.f0.lcolon -text ":"
  set windows(passfreqentry) [ entry $f.f0.ef -textvariable \
    stuff(skedfreq) -width 10 -font $::setting(bigfont) -background yellow ]

  # label $f.f0.ln -text "Note"
  # entry $f.f0.en -textvariable stuff(skednote) -width 20 -font \
  #   $::setting(entryfont) -background yellow

  grid $f.f0.lPass $f.f0.ec $f.f0.lin $f.f0.er $f.f0.lto $f.f0.ePeer \
    $f.f0.lon $f.f0.eBand $f.f0.lcolon $f.f0.ef \
    -sticky news -padx 1 -pady 1

  # New stuff - Make checkbuttons to indicate what bands this guy has.
  frame $f.f2 -borderwidth 2 -relief raised
  label $f.f2.lhehas -text "He has"
  pack $f.f2.lhehas -side left
  set i 0
  foreach b $::setting(bands) {
    set windows(passhascb$i) [ checkbutton $f.f2.cb$i -text $b \
      -variable stuff(passhas$b) -command "Update_Pass_Band $b" ]
    pack $f.f2.cb$i -side left
    incr i
  }

  frame $f.f3 -borderwidth 2 -relief raised
  label $f.f3.fdate  -text "Date"
  label $f.f3.futc   -text "UTC"
  label $f.f3.flocal -text "Local"
  label $f.f3.lw -text "WIP"
  label $f.f3.ll -text "Limit"
  label $f.f3.lb -text "Busy"

  label $f.f3.lon -text "on"
  entry $f.f3.ed -textvariable stuff(nextskeddate) \
    -width 11 -font $::setting(entryfont)
  label $f.f3.lat -text "at"
  entry $f.f3.eu -textvariable stuff(nextskedutc) \
    -width 6 -font $::setting(entryfont)
  label $f.f3.lparenl -text "("
  entry $f.f3.eloc -textvariable stuff(nextskedlocal) \
    -width 6 -font $::setting(entryfont)
  label $f.f3.lparenr -text ")"
  button $f.f3.bfirst -text "First Available" -command First_Available_Sked

  label $f.f3.lpi -text "Peer Info"
  set windows(passwipentry) [ entry $f.f3.ew -textvariable stuff(wip) \
    -width 4 -font $::setting(entryfont) -state readonly ]
  set windows(passwiplimitentry) [ entry $f.f3.el -textvariable \
    ::setting(wiplimit) -width 4 \
    -font $::setting(entryfont) -state readonly ]
  set windows(passbusyentry) [ entry $f.f3.eb -textvariable stuff(busy) \
    -width 4 -font $::setting(entryfont) -state readonly ]

  grid x         $f.f3.fdate x         $f.f3.futc x             $f.f3.flocal x             x            x         $f.f3.lw $f.f3.ll $f.f3.lb -sticky news -padx 1 -pady 1
  grid $f.f3.lon $f.f3.ed    $f.f3.lat $f.f3.eu   $f.f3.lparenl $f.f3.eloc   $f.f3.lparenr $f.f3.bfirst $f.f3.lpi $f.f3.ew $f.f3.el $f.f3.eb -sticky news -padx 1 -pady 1

  button $f.bpass -text "Pass" -background pink -command Make_Pass

  grid $f.f0 $f.bpass -sticky news
  grid $f.f2 ^        -sticky news
  grid $f.f3 ^        -sticky news

  wm resizable $f 0 0
  update idletasks

  return $f
}

proc First_Available_Sked { } {
  global sked stuff

  if { $stuff(skedpeer) == $::setting(mypeername) } {
    Debug "First_Available_Sked" "Prepping a pass to myself."
    set hiswip $stuff(wip)
    set hiswiplimit $::setting(wiplimit)
    set hisbusy $stuff(busy)
  } else {
    Debug "First_Available_Sked" "Prepping a pass to $stuff(skedpeer)."
    set hiswip $stuff($stuff(skedpeer),wip)
    set hiswiplimit $stuff($stuff(skedpeer),wiplimit)
    set hisbusy $stuff($stuff(skedpeer),busy)
  }

  if { $hisbusy == "" || $hiswip == "" } {
    set stuff(nextskeddate) "NOW"
    set stuff(nextskedutc) "NOW"
    set stuff(nextskedlocal) "NOW"
    return
  }

  # check the currrent time to see if the station is free

  # figure out what the UTC time is right now
  set tnow [ clock seconds ]
  set tnow [ expr $stuff(utcoffset) * 3600 + $tnow ]

  # figure out when the next sked interval begins (UTC).
  set t [ expr $tnow - $tnow % ( $::setting(skedtinc) * 60 ) + ( $::setting(skedtinc) * 60 ) ]
  set date [ clock format $t -format "%Y-%m-%d" ]
  set utc [ clock format $t -format "%H%M" ]
  set dateutc "$date:$utc"

  # calculate the next free time for the peer.
  set nextfreetime [ expr $tnow + $hisbusy * 60 ]
  set nextfreedate [ clock format $nextfreetime -format "%Y-%m-%d" ]
  set nextfreeutc  [ clock format $nextfreetime -format "%H%M" ]

  Debug "First_Available_Sked" \
    "Checking WIP $hiswip vs. $hiswiplimit and busy $nextfreedate $nextfreeutc vs. $date $utc"

  # Check to make sure the peer is not busy and has time before the next sked interval.
  if { ( $hiswip < $hiswiplimit && $nextfreetime <= $t ) } {
    Debug "First_Available_Sked" "$stuff(skedpeer) is not busy.  Passing right away."
    set stuff(nextskeddate) "NOW"
    set stuff(nextskedutc) "NOW"
    set stuff(nextskedlocal) "NOW"
    return
  }

  # Looks like he's busy right now. look for a free time.

  # If we don't have something in the next 12 hours, never mind.
  set tstop [ expr $t + 3600 * 12 ]

  # Start right now.  look through skeds until we find a spot that doesn't
  # have a sked in it.
  for { incr t [ expr $::setting(skedtinc) * 60 ] } { $t < $tstop } \
    { incr t [ expr $::setting(skedtinc) * 60 ] } {
    set date [ clock format $t -format "%Y-%m-%d" ]
    set utc [ clock format $t -format "%H%M" ]
    Debug "First_Available_Sked" "Checking $stuff(skedpeer) on $date at $utc."
    set dateutc "$date:$utc"
    if { ! [ info exists sked($stuff(skedpeer),$dateutc) ] } {
      Debug "First_Available_Sked" "$stuff(skedpeer) is not busy on $date at $utc."
      set stuff(nextskeddate) $date
      set stuff(nextskedutc) $utc
      set tlocal [ clock format [ expr $t - $stuff(utcoffset) * 3600 ] -format "%H:%M" ]
      set stuff(nextskedlocal) $tlocal
      return
    }
  }

  set ok [ tk_messageBox -icon warning -type ok -parent $windows(pass) \
    -title "Station Booked Solid for 12 Hours" -message \
    "Amazingly, the station you are passing to is busy for the next 12 hours.\nPlease contact the operator directly for more information." ]
  return
}

#
# Set_Sked_Freq_From_Band
#

proc Set_Sked_Freq_From_Band { } {
  global stuff
 
  # The goal here is to see what station has the new sked band and
  # get his last frequency for that band.  Tricky!  The update is
  # done when a frequency update is received over the net.
  if { [ info exists stuff(skedfrequency,$stuff(skedband)) ] } {
    set stuff(skedfreq) $stuff(skedfrequency,$stuff(skedband))
  # If we haven't received an update for the skedband over the net,
  # use our own last operating frequency for this band.
  } else {
    set stuff(skedfreq) "0.0000"
    for { set i 1 } { $i < 18 } { incr i } {
      if { [ lindex $::setting(r$i) 0 ] == $stuff(skedband) } {
        # set stuff(skedfreq) [ lindex $::setting(r$i) 2 ]
        set stuff(skedfreq) \
          [ format "%6.4f" $stuff(lastopfreq,$stuff(skedband)) ]
      }
    }
  }
}

#
#  Build_Skeds - procedure to set up the sked window.
#

proc Build_Skeds { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "Skeds"
  wm protocol $f WM_DELETE_WINDOW { wm withdraw $windows(skeds) }
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    catch { wm iconbitmap $f log.ico }
  }

  frame $f.f1 -borderwidth 2 -relief raised

  frame $f.f1.c
  label $f.f1.c.ls -text "Skeds for"
  menubutton $f.f1.c.mPeer -text "Peer..." -menu $f.f1.c.mPeer.menu -relief \
    raised
  set skedpeermenu [menu $f.f1.c.mPeer.menu -tearoff 0]
  for { set i 1 } { $i < 13 } { incr i } {
    set a [ lindex $::setting(p$i) 0 ]
    $skedpeermenu add radio -label $a -variable stuff(skedpeer) -value $a \
      -command { Sked_Peer "current" }
  }
  entry $f.f1.c.ePeer -textvariable stuff(skedpeer) -width 16 \
    -state readonly -font $::setting(bigfont) -readonlybackground lightyellow
  label $f.f1.c.lsd -text "Start Date"
  entry $f.f1.c.esd -textvariable stuff(skedstartdate) -width 11 \
    -font $::setting(entryfont)
  label $f.f1.c.lsu -text "UTC"
  entry $f.f1.c.esu -textvariable stuff(skedstartutc) -width 5 \
    -font $::setting(entryfont)
  button $f.f1.c.brt -text "Redraw" -command { Redraw_Skeds "entry" }
  button $f.f1.c.brn -text "Now" -command { Redraw_Skeds "now" }
  button $f.f1.c.bra -text "Earlier" -command { Redraw_Skeds "earlier" }
  button $f.f1.c.brl -text "Later" -command { Redraw_Skeds "later" }
  grid $f.f1.c.ls $f.f1.c.mPeer $f.f1.c.ePeer $f.f1.c.lsd $f.f1.c.esd \
    $f.f1.c.lsu $f.f1.c.esu $f.f1.c.brt $f.f1.c.brn $f.f1.c.bra $f.f1.c.brl \
    -padx 1 -pady 1 -sticky news

  grid $f.f1.c

  frame $f.f0 -borderwidth 2 -relief raised

  label $f.f0.ld -text "Date"
  entry $f.f0.ed -textvariable stuff(skeddate) -width 11 -font \
    $::setting(entryfont) -state readonly -readonlybackground lightyellow
  label $f.f0.lu -text "UTC"
  entry $f.f0.eu -textvariable stuff(skedutc) -width 5 -font \
    $::setting(entryfont) -state readonly -readonlybackground lightyellow

  menubutton $f.f0.mBand -text Band -menu $f.f0.mBand.menu -relief raised \
    -underline 0
  entry $f.f0.eBand -state readonly -font \
    $::setting(bigfont) -textvariable stuff(skedband) -width 6 \
    -readonlybackground lightyellow

  set skedbandmenu [ menu $f.f0.mBand.menu -tearoff 0 ]
  foreach b $::setting(bands) {
    $skedbandmenu add radio -label $b -variable stuff(skedband) -value $b \
      -command { Set_Sked_Freq_From_Band }
  }
  label $f.f0.lf -text "Freq"
  set windows(skedfreqentry) [ entry $f.f0.ef -textvariable \
    stuff(skedfreq) -width 10 -font $::setting(bigfont) \
    -background yellow ]
  label $f.f0.lc -text "Call"
  set windows(skedcall) [ entry $f.f0.ec -textvariable stuff(skedcall) \
    -width 14 -font $::setting(bigfont) -background yellow ]
  label $f.f0.lr -text "Recd"
  set windows(skedrecd) [ entry $f.f0.er -textvariable stuff(skedrecd) \
    -width 10 -font $::setting(bigfont) -background yellow ]
  label $f.f0.ln -text "Note"
  entry $f.f0.en -textvariable stuff(skednote) -width 20 -font \
    $::setting(entryfont) -background yellow

  grid $f.f0.ld $f.f0.lu $f.f0.mBand $f.f0.lf $f.f0.lc $f.f0.lr $f.f0.ln \
    -padx 1 -pady 1 -sticky news
  grid $f.f0.ed $f.f0.eu $f.f0.eBand $f.f0.ef $f.f0.ec $f.f0.er $f.f0.en \
    -padx 1 -pady 1 -sticky news

  frame $f.f3 -borderwidth 2 -relief raised

  frame $f.f3.a
  
  # Start out with our defaults.
  label $f.f3.a.lw -text "His WIP"
  set windows(skedwipentry) [ entry $f.f3.a.ew -textvariable stuff(wip) \
    -width 4 -font $::setting(entryfont) -state readonly ]
  label $f.f3.a.ll -text "Limit"
  set windows(skedwiplimitentry) [ entry $f.f3.a.el -textvariable \
    ::setting(wiplimit) -width 4 \
    -font $::setting(entryfont) -state readonly ]
  label $f.f3.a.lb -text "Busy"
  set windows(skedbusyentry) [ entry $f.f3.a.eb -textvariable stuff(busy) \
    -width 4 -font $::setting(entryfont) -state readonly ]

  label $f.f3.a.ls -text "Skeds"
  button $f.f3.a.bds -text "Delete" -underline 0 -command { Delete_Sked "deleted" }
  button $f.f3.a.bes -text "Copy" -underline 0 -command { Copy_Sked }
  button $f.f3.a.bmm -text "Mark Made" -underline 0 -command { Delete_Sked "made" }
  label $f.f3.a.lt -text "Time Increment (min)"
  entry $f.f3.a.et -textvariable ::setting(skedtinc) -width 4 \
    -font $::setting(entryfont) -state readonly
  button $f.f3.a.bas -text "Add Sked" -command { Add_Sked } -background pink

  grid $f.f3.a.lw $f.f3.a.ew $f.f3.a.ll $f.f3.a.el $f.f3.a.lb $f.f3.a.eb \
    $f.f3.a.ls $f.f3.a.bds $f.f3.a.bes $f.f3.a.bmm $f.f3.a.lt $f.f3.a.et \
    $f.f3.a.bas -padx 1 -pady 1 -sticky news

  frame $f.f3.b
  set windows(skedlist) [ listbox $f.f3.b.list -background white \
    -foreground black -font $::setting(entryfont) -width 80 -height 13 ]
  button $f.f3.b.bearlier -text "^" -command { Redraw_Skeds "earlier" }
  button $f.f3.b.blater -text "v" -command { Redraw_Skeds "later" }
  grid $f.f3.b.list $f.f3.b.bearlier -padx 2 -pady 2 -sticky news
  grid ^            $f.f3.b.blater   -padx 2 -pady 2 -sticky news

  grid $f.f3.b.bearlier -sticky news
  grid $f.f3.b.blater   -sticky news

  grid $f.f3.a -sticky news
  grid $f.f3.b -sticky news

  frame $f.f4 -borderwidth 2 -relief raised

  frame $f.f4.d
  label $f.f4.d.lw -text "My Work In Progress"
  set windows(skedwipentry) [ entry $f.f4.d.ew -textvariable stuff(wip) -width 4 \
    -font $::setting(entryfont) -state readonly ]
  label $f.f4.d.lwl -text "Limit"
  entry $f.f4.d.ewl -textvariable ::setting(wiplimit) -width 4 \
    -font $::setting(entryfont)
  set windows(acceptbutton) [ button $f.f4.d.bas -text "Accept" -command { Accept_WIP active } ]
  button $f.f4.d.bds -text "Delete" -command { Delete_WIP active }
  button $f.f4.d.brs -text "Resked" -command { Resked_WIP }
  label $f.f4.d.lb -text "Busy"
  entry $f.f4.d.eb -textvariable stuff(busy) -width 4 \
    -font $::setting(entryfont) -state readonly
  button $f.f4.d.bb0 -text "0 Min" -command { Busy 0 }
  button $f.f4.d.bb1 -text "1 Min" -command { Busy 1 }
  button $f.f4.d.bb5 -text "5 Min" -command { Busy 5 }
  button $f.f4.d.bb10 -text "10 Min" -command { Busy 10 }

  grid $f.f4.d.lw $f.f4.d.ew $f.f4.d.lwl $f.f4.d.ewl $f.f4.d.bas $f.f4.d.bds \
    $f.f4.d.brs $f.f4.d.lb $f.f4.d.eb $f.f4.d.bb0 $f.f4.d.bb1 $f.f4.d.bb5 \
    $f.f4.d.bb10 -padx 1 -pady 1 -sticky news

  grid $f.f4.d

  frame $f.f4.e
  set windows(wiplist) [ listbox $f.f4.e.list -background white \
    -foreground black -font $::setting(entryfont) -width 80 -height 5 \
    -yscrollcommand [list $f.f4.e.yscroll set] ]
  scrollbar $f.f4.e.yscroll -orient vertical -command [list $f.f4.e.list yview]
  grid $f.f4.e.list $f.f4.e.yscroll -padx 3 -pady 3 -sticky news

  set line [ format "%-10.10s %-4.4s %-6.6s %-10.10s %-13.13s %-6.6s Note" \
    "Date" "UTC" "Band" "Freq" "Call" "Recd" ]
  $windows(wiplist) insert end $line

  grid $f.f4.e

  grid $f.f1 -sticky news
  grid $f.f0 -sticky news
  grid $f.f3 -sticky news
  grid $f.f4 -sticky news

  wm resizable $f 0 0
  update idletasks

  return $f
}

#
# Make_Pass - Don't tell my wife.
#

proc Make_Pass { } {
  global windows stuff

  if { ! [ Check_Sked "pass" ] } {
    Popup_Pass "keep"
    return
  }

  # If this is really a sked, handle it that way.
  if { $stuff(nextskeddate) != "NOW" || $stuff(nextskedutc) != "NOW" } {
    set stuff(skeddate) $stuff(nextskeddate)
    set stuff(skedutc) $stuff(nextskedutc)
    Add_Sked
    return
  }

  # Set line to pass
  set line [ format "%-6.6s %-10.10s %-13.13s %-6.6s %s" \
    $stuff(skedband) $stuff(skedfreq) $stuff(skedcall) $stuff(skedrecd) \
    "$stuff(skednote)" ]

  if { $stuff(skedpeer) == $::setting(mypeername) } {
    set t [expr $stuff(utcoffset) * 3600 + [clock seconds]]
    set date [ clock format $t -format "%Y-%m-%d" ]
    set utc  [ clock format $t -format "%H%M" ]

    Add_WIP "$date $utc $line"

    if { $::setting(quicksked) == 1 } {
      wm withdraw $windows(pass)
      focus $windows(callentry)
      $windows(callentry) icursor end
      $windows(callentry) select range 0 end
    }

    return
  }

  # get peer number from name
  set peerno [ Peer_By_Name $stuff(skedpeer) ]

  # get IP address and port from array
  set peerpt   [ lindex $::setting(p$peerno) 2 ]

  # set initial value for ok to indicate we should go on if nothing else
  # happens.
  set ok "continue"

  # check for station out of touch
  if { $peerpt == 0 } {
    return
  }

  set hiswip $stuff($stuff(skedpeer),wip)
  set hiswiplimit $stuff($stuff(skedpeer),wiplimit)
  set hisbusy $stuff($stuff(skedpeer),busy)

  if { $hiswip == "" } {
    set hiswip 0
  }

  if { $hiswiplimit == "" } {
    set hiswiplimit 3
  }

  if { $hisbusy == "" } {
    set hisbusy 0
  }

  # check station's WIP.
  if { $hiswip >= $hiswiplimit } {
    set ok [ tk_messageBox -icon warning -type okcancel -parent $windows(pass) \
      -title "Station Busy" -message \
      "The station you are passing to is too busy at this time\n($hiswip stations waiting).\nDo you wish to make a sked instead?" ]
    if { $ok == "ok" } {
      set stuff(skedpeer) $stuff(skedpeer)
      Popup_Skeds "keep"
      return
    # cancel
    } else {
      if { $::setting(quicksked) == 1 } {
        wm withdraw $windows(pass)
        focus $windows(callentry)
        $windows(callentry) icursor end
        $windows(callentry) select range 0 end
      }
      return
    }
  }

  # check station's busy.
  if { $hisbusy != 0 } {
    set ok [ tk_messageBox -icon warning -type okcancel -parent $windows(pass) \
      -title "Station Busy" -message \
      "The station you are passing to is too busy at this time\n(busy for $hisbusy more minutes).\nDo you wish to make a sked instead?" ]
    if { $ok == "ok" } {
      Popup_Skeds "keep"
      return
    # cancel
    } else {
      if { $::setting(quicksked) == 1 } {
        wm withdraw $windows(pass)
        focus $windows(callentry)
        $windows(callentry) icursor end
        $windows(callentry) select range 0 end
      }
      return
    }
  }

  Net_Send "zzz" $stuff(skedpeer) "NOW: $::setting(mypeername) $line"
  Annunciate "Pass Made"

  Debug "Make_Pass" "Done making pass."

  if { $::setting(quicksked) == 1 } {
    Debug "Make_Pass" "Minimizing Pass Window."
    wm withdraw $windows(pass)
    focus $windows(callentry)
    $windows(callentry) icursor end
    $windows(callentry) select range 0 end
  }

  return
}

#
# Peerbutton - procedure to handle a click on the button for a net peer
#

proc Peerbutton { keep } {
  global windows stuff

  # Lookup peer number
  set peerno [ Peer_By_Name $stuff(skedpeer) ]

  # Check if blacklisted
  if { $stuff(blacklist,p$peerno) == 1 } {
    Unblacklist "p$peerno"
  } else {
    # Do normal action for the button - pass
    Popup_Pass $keep
  }
}

#
# Popup_Pass - procedure to bring up the pass window.
#

proc Popup_Pass { keep } {
  global windows stuff call_stack

  if { $keep != "keep" } {

    # If we wiped out the call, dig into the call stack for the last one.
    if { $stuff(call) == "" && $stuff(recd) == "" } {
      set stuff(skedcall) [ lindex $call_stack(0) 0 ]
      set stuff(skedrecd) [ lindex $call_stack(0) 1 ]
    # Use the current call
    } else {
      set stuff(skedcall) [string toupper [string trim $stuff(call)]]
      set stuff(skedrecd) [string toupper [string trim $stuff(recd)]]
    }
    Bear_Calc_Kernel $stuff(sent) $stuff(skedrecd)
    # set stuff(skednote) "Az $stuff(brng) By $::setting(mypeername)"
    set stuff(skednote) "by $::setting(mypeername)"

    # If it's me, look up my stuff
    if { $stuff(skedpeer) == $::setting(mypeername) } {
      set stuff(skedfreq) $stuff(opfreq)
      set stuff(skedband) $stuff(band)
    # Look up the peer's stuff
    } else {
      set p [ Peer_By_Name $stuff(skedpeer) ]
      Debug "Popup_Pass" "Peer $stuff(skedpeer) is peer number $p."
      if { $p != "0" && $stuff(peerfreq$p) != "" } {
        set stuff(skedfreq) $stuff(peerfreq$p)
        Debug "Popup_Pass" "The frequency for $stuff(skedpeer) is $stuff(skedfreq)."
        set stuff(skedband) [ Band_By_Freq $stuff(skedfreq) ]
      } else {
        # TODO: set the freq/band to something more interesting if
        #       we don't know what the frequency is for this guy.
        if { [ llength $::setting(p$p) ] > 3 } {
          set stuff(skedfreq) "?"
          set stuff(skedband) [ lindex $::setting(p$p) 3 ]
          Debug "Popup_Pass" "The band for $stuff(skedpeer) is $stuff(skedband)."
        }
      }
    }

    First_Available_Sked

    What_Bands
  }

  wm deiconify $windows(pass)
  raise $windows(pass)
}

#
# Popup_Old_Pass - procedure to bring up the pass window.
#

proc Popup_Old_Pass { keep } {
  global windows stuff call_stack

  if { $keep != "keep" } {

    # If we wiped out the call, dig into the call stack for the last one.
    if { $stuff(call) == "" && $stuff(recd) == "" } {
      set stuff(skedcall) [ lindex $call_stack(0) 0 ]
      set stuff(skedrecd) [ lindex $call_stack(0) 1 ]
    # Use the current call
    } else {
      set stuff(skedcall) [string toupper [string trim $stuff(call)]]
      set stuff(skedrecd) [string toupper [string trim $stuff(recd)]]
    }
    Bear_Calc_Kernel $stuff(sent) $stuff(skedrecd)
    # set stuff(skednote) "Az $stuff(brng) By $::setting(mypeername)"
    set stuff(skednote) "by $::setting(mypeername)"

    # If it's me, look up my stuff
    if { $stuff(skedpeer) == $::setting(mypeername) } {
      set stuff(skedfreq) $stuff(opfreq)
      set stuff(skedband) $stuff(band)
    # Look up the peer's stuff
    } else {
      set p [ Peer_By_Name $stuff(skedpeer) ]
      if { $p != "0" && $stuff(peerfreq$p) != "" } {
        set stuff(skedfreq) $stuff(peerfreq$p)
        set stuff(skedband) [ Band_By_Freq $stuff(skedfreq) ]
      }
    }

    What_Bands
  }

  wm deiconify $windows(pass)
  raise $windows(pass)
}

#
# Popup_Skeds - procedure to bring up the skeds window.
#

proc Popup_Skeds { keep } {
  global windows stuff call_stack

  set t [ clock seconds ]
  set t [ expr $stuff(utcoffset) * 3600 + \
    ( $t - $t % ( $::setting(skedtinc) * 60 ) ) ]
  set stuff(skeddate) [ clock format $t -format "%Y-%m-%d" ]
  set stuff(skedutc)  [ clock format $t -format "%H%M" ]

  # If we wiped out the call, dig into the call stack for the last one.
  if { $stuff(call) == "" && $stuff(recd) == "" } {
    set stuff(skedcall) [ lindex $call_stack(0) 0 ]
    set stuff(skedrecd) [ lindex $call_stack(0) 1 ]
  } else {
    set stuff(skedcall) [string toupper [string trim $stuff(call)]]
    set stuff(skedrecd) [string toupper [string trim $stuff(recd)]]
  }
  Bear_Calc_Kernel $stuff(sent) $stuff(skedrecd)
  # set stuff(skednote) "Az $stuff(brng) By $::setting(mypeername)"
  set stuff(skednote) "by $::setting(mypeername)"

  if { $keep != "keep" } {
    if { $stuff(skedpeer) == $::setting(mypeername) } {
      set stuff(skedfreq) $stuff(opfreq)
      set stuff(skedband) $stuff(band)
    } else {
      set p [ Peer_By_Name $stuff(skedpeer) ]
      if { $p != "0" && $stuff(peerfreq$p) != "" } {
        set stuff(skedfreq) $stuff(peerfreq$p)
        set stuff(skedband) [ Band_By_Freq $stuff(skedfreq) ]
      }
    }
  }

  Redraw_Skeds "now"

  wm deiconify $windows(skeds)
  raise $windows(skeds)
  focus $windows(skedlist)
}

#
# Redraw_Skeds - Refresh the list of skeds.
#

proc Redraw_Skeds { when } {
  global windows stuff sked

  # if redraw now, set time to the next time increment in the future.  Making a sked
  # for the current interval is not valid, that's a pass.
  if { $when == "now" } {

    set t [ clock seconds ]
    set t [ expr $stuff(utcoffset) * 3600 + \
      ( $t + $::setting(skedtinc) * 60 - $t % ( $::setting(skedtinc) * 60 ) ) ]

    set lineno 1

  # if not now, use the start date and utc
  } else {

    set h [ string range $stuff(skedstartutc) 0 1 ]
    set m [ string range $stuff(skedstartutc) 2 3 ]
    set t [ clock scan "$stuff(skedstartdate) $h:$m" ]
    set t [ expr $t - $t % ( $::setting(skedtinc) * 60 ) ]

    # adjust start date and utc if scrolling.  1/2 screen.
    if { $when == "earlier" } {
      set t [ expr $t - ( $::setting(skedtinc) * 360 ) ]
    } elseif { $when == "later" } {
      set t [ expr $t + ( $::setting(skedtinc) * 360 ) ]
    }

    set lineno [$windows(skedlist) index active] 
  } 

  # set up the start date and utc fields
  set date [ clock format $t -format "%Y-%m-%d" ]
  set utc [ clock format $t -format "%H%M" ]
  set stuff(skedstartdate) $date
  set stuff(skedstartutc) $utc

  # wipe out old list contents
  $windows(skedlist) delete 0 end

  # put in the header
  set line [ format "%-10.10s %-4.4s %-6.6s %-10.10s %-13.13s %-6.6s Note" \
    "Date" "UTC" "Band" "Freq" "Call" "Recd" ]
  $windows(skedlist) insert end $line

  # step through each line in the list
  for { set i 0 } { $i < 12 } { incr i } {

    set made 0
    # look for a sked for this display position in the window
    set dateutc "$date:$utc"
    if { $stuff(skedpeer) != "" && \
      [ info exists sked($stuff(skedpeer),$dateutc) ] } {

      # if found, format the line using the sked data
      set line [ format "%-10.10s %-4.4s %s" \
        $date $utc $sked($stuff(skedpeer),$dateutc) ]

    } else {
    
      # look for a made sked for this display position in the window
      set dateutc "$date:-$utc"
      if { $stuff(skedpeer) != "" && \
        [ info exists sked($stuff(skedpeer),$dateutc) ] } {

        # if found, format the line using the sked data
        set line [ format "%-10.10s %-4.4s %s" \
          $date $utc $sked($stuff(skedpeer),$dateutc) ]
        # set line [ format "%-10.10s %-4.4s" \
        #   $date $utc ]

        set made 1

      } else {

        # if not found, format an empty line
        set line [ format "%-10.10s %-4.4s" \
          $date $utc ]

      }
    }

    # put the line into the display list

    # colorize the line if the sked was made.
    if { $made == 1 } {
      $windows(skedlist) insert end $line
      $windows(skedlist) itemconfigure end -fg $::setting(madeskedcolor) -bg white
    } else {
      $windows(skedlist) insert end $line
      $windows(skedlist) itemconfigure end -fg black -bg white
    }

    # increment the date and time
    set dummy [ string range $utc 0 1 ]
    set stupid [ string range $utc 2 3 ]
    set dummy [ clock scan "$date $dummy:$stupid" ]
    set date [ clock format [ clock scan "$::setting(skedtinc) minutes" \
      -base $dummy ] -format "%Y-%m-%d" ]
    set utc [ clock format [ clock scan "$::setting(skedtinc) minutes" \
      -base $dummy ] -format "%H%M" ]
  }

  # Activate the line that was previously activated.
  $windows(skedlist) activate $lineno
  $windows(skedlist) selection clear 0 end
  $windows(skedlist) selection set $lineno
  $windows(skedlist) see $lineno

  Set_Sked_Time_From_Row "active"
}

#
# sked array format:
#
# index: band,YYYY-MM-DD:HHMM
# text: band freq call grid note
#

proc CompareSkedbyTime { a b } {

  # Debug "CompareSkedbyTime" "$a vs. $b"

  set aii [ split $a , ]
  set bii [ split $b , ]
  
  set aiii [ split [ lindex $aii 1 ] : ] 
  set biii [ split [ lindex $bii 1 ] : ] 

  set adate [ lindex $aiii 0 ]
  set autc [ lindex $aiii 1 ]
  if { [ string index $autc 0 ] == "-" } {
    set autc [ string range $autc 1 end ]
  }
  set ah [ string range $autc 0 1 ]
  set am [ string range $autc 2 3 ]

  set bdate [ lindex $biii 0 ]
  set butc [ lindex $biii 1 ]
  if { [ string index $butc 0 ] == "-" } {
    set butc [ string range $butc 1 end ]
  }
  set bh [ string range $butc 0 1 ]
  set bm [ string range $butc 2 3 ]

  set at [ clock scan "$adate ${ah}:${am}" ]
  set bt [ clock scan "$bdate ${bh}:${bm}" ]

  # Debug "CompareSkedbyTime" "$at vs. $bt"

  if { $at > $bt } {
    return 1
  } else {
    return -1
  }

}

#
# Save_Skeds - procedure to save sked text from window to file.
#              The file name is the same as the log file except
#              with a .skd extension instead of .log.
#

proc Save_Skeds { } {
  global windows stuff sked

  # do not save if the log has not been named.
  if { $::setting(logfile) != "untitled.log" && \
    [ info exists sked ] } {

    # open file
    set rn [ file rootname $::setting(logfile) ]
    set fn "$rn.skd"
    set fid [open $fn w 0666]

    # extract sked array into a list: index text index text index text ...
    set skedlist [ array get sked ]

    # make a new list: { index text } { index text } { index text } ...
    set skedlist2 { }
    foreach { i j } $skedlist {
      lappend skedlist2 [ list $i $j ]
    }

    # sort the sucker
    set skedlist2 [ lsort -command CompareSkedbyTime -index 0 $skedlist2 ]

    # save each line
    foreach l $skedlist2 {
      set index [ lindex $l 0 ]
      set line [ lindex $l 1 ]
      # add 2 extra spaces in case there was no note and the grid was only
      # 4 digits, otherwise skedrecd will not scan properly and an error
      # will come up.
      puts $fid "$index $line  "
    }

    # close file
    close $fid
  }
}

#
# Load_Skeds - procedure to load sked text from file to window.
#

proc Load_Skeds { } {
  global windows stuff sked

  set rn [ file rootname $::setting(logfile) ]
  set fn "$rn.skd"
  if { [ file readable $fn ] } {
    set fid [open $fn r ]
    while { [gets $fid line] >= 0 } {
      set line [ string trim $line ]
      if { $line != "" } {
        Add_Sked_Kernel $line
      }
    }
    close $fid
  }

  set t [ clock seconds ]
  set t [ expr $stuff(utcoffset) * 3600 + \
    ( $t - $t % ( $::setting(skedtinc) * 60 ) ) ]
  set stuff(skeddate) [ clock format $t -format "%Y-%m-%d" ]
  set stuff(skedutc)  [ clock format $t -format "%H%M" ]

  set stuff(skedband) [string trim $stuff(band)]
  set stuff(skedcall) [string toupper [string trim $stuff(call)]]
  set stuff(skedrecd) [string toupper [string trim $stuff(recd)]]
  # Bear_Calc_Kernel $stuff(sent) $stuff(skedrecd)
  # set stuff(skednote) "Az $stuff(brng) By $::setting(mypeername)"
  set stuff(skednote) "by $::setting(mypeername)"

  Redraw_Skeds "now"
}

#
# Add_Sked_Kernel - procedure to insert a new sked into the list
#

proc Add_Sked_Kernel { line } {
  global windows sked

  set index [ lindex [ split $line ] 0 ]
  set rest [ string range $line [ expr [ string length $index ] + 1 ] end ]
  Debug "Add_Sked_Kernel" "set sked($index) \"$rest\""
  set sked($index) "$rest"
}

#
# Set_Sked_Time_From_Row - procedure to take the 
# date and time from the selected sked in the
# listbox and use them for the sked entry fields.
#

proc Set_Sked_Time_From_Row { row } {
  global windows stuff

  Debug "Set_Sked_Time_From_Row" "Working."

  if { $row == "anchor" } {
    set lineno [$windows(skedlist) index anchor] 
    if { $lineno == 0 } { return }
    Debug "Set_Sked_Time_From_Row" "anchor = $lineno"
  } elseif { $row == "active" } {
    set lineno [$windows(skedlist) index active] 
    if { $lineno == 0 } { return }
    Debug "Set_Sked_Time_From_Row" "active = $lineno"
  }

  $windows(skedlist) activate $lineno
  $windows(skedlist) selection clear 0 end
  $windows(skedlist) selection set $lineno
  $windows(skedlist) see $lineno
  
  set skedtext [$windows(skedlist) get active]

  binary scan $skedtext "a10x1a4x*" \
    skeddate skedutc

  set stuff(skeddate) [ string trim $skeddate ]
  set stuff(skedutc)  [ string trim $skedutc ]
}

#
#  Copy_Sked - procedure to copy the selected sked into the sked
#              information entry fields for editing.
#

proc Copy_Sked { } {
  global windows stuff

  # Check to make sure we're not trying to edit the header line.
  set lineno [$windows(skedlist) index active] 
  if { $lineno == 0 } { return }

  # Grab and parse the active line.
  set skedtext [$windows(skedlist) get active]
  set r [ binary scan $skedtext "a10x1a4x1a6x1a10x1a13x1a6x1a*" \
    skeddate skedutc skedband skedfreq skedcall skedrecd skednote ]

  # If this line is empty, just grab date and utc.
  if { $r == 2 } {
    set stuff(skeddate) [ string trim $skeddate ]
    set stuff(skedutc)  [ string trim $skedutc ]
    set stuff(skedcall) ""
    set stuff(skedrecd) ""
    set stuff(skednote) ""
  # If this line is NOT empty, grab everything.
  } elseif { $r == 7 } {
    set stuff(skeddate) [ string trim $skeddate ]
    set stuff(skedutc)  [ string trim $skedutc ]
    set stuff(skedband) [ string trim $skedband ]
    set stuff(skedfreq) [ string trim $skedfreq ]
    set stuff(skedcall) [ string trim $skedcall ]
    set stuff(skedrecd) [ string trim $skedrecd ]
    set stuff(skednote) [ string trim $skednote ]
  }
}

proc Decrement_WIP { } {
  global stuff windows

  if { $stuff(wip) > 0 } {
    incr stuff(wip) -1
  } else {
    set stuff(wip) 0
  }

  if { $stuff(wip) == 0 } {
    $windows(wipentry) configure -fg $stuff(wipentryfg) -readonlybackground $stuff(wipentrybg)
    $windows(skedsbutton) configure -fg black
    $windows(acceptbutton) configure -fg black
  } else {
    $windows(wipentry) configure -fg yellow -readonlybackground red
    $windows(skedsbutton) configure -fg red
    $windows(acceptbutton) configure -fg red
  }

}

proc Increment_WIP { } {
  global stuff windows

  incr stuff(wip)

  if { $stuff(wip) == 0 } {
    $windows(wipentry) configure -fg $stuff(wipentryfg) -readonlybackground $stuff(wipentrybg)
    $windows(skedsbutton) configure -fg black
    $windows(acceptbutton) configure -fg black
  } else {
    $windows(wipentry) configure -fg yellow -readonlybackground red
    $windows(skedsbutton) configure -fg red
    $windows(acceptbutton) configure -fg red
  }
}

#
#  Resked_WIP - Procedure to reschedule the selected WIP.
#

proc Resked_WIP { } {
  global windows stuff

  # Check to make sure we're not trying to resked the header line.
  set lineno [$windows(wiplist) index active] 
  if { $lineno == 0 } { return }

  # Get the active line from the WIP list.
  set skedtext [$windows(wiplist) get active]

  # Remove the line from the list.
  $windows(wiplist) delete $lineno $lineno
  Decrement_WIP

  # Update the other stations
  Net_Send "wip" "all" ""

  # Parse the line.
  binary scan $skedtext "a10x1a4x1a6x1a10x1a13x1a6x1a*" \
    skeddate skedutc skedband skedfreq skedcall skedrecd skednote

  # Fix up the fields.
  set stuff(skeddate) [ string trim $skeddate ]
  set stuff(skedutc)  [ string trim $skedutc ]
  set stuff(skedband) [ string trim $skedband ]
  set stuff(skedfreq) [ string trim $skedfreq ]
  set stuff(skedcall) [ string trim $skedcall ]
  set stuff(skedrecd) [ string trim $skedrecd ]
  set stuff(skednote) [ string trim $skednote ]
}

#
#  Accept_WIP - Procedure to accept the selected WIP.
#

proc Accept_WIP { what } {
  global windows stuff

  if { $what == "next" } {
    set lineno 1
  } else {
    # Assume we're accepting the first WIP if nothing is selected
    set lineno [$windows(wiplist) index active] 
    if { $lineno == 0 } { 
      set lineno 1
    }
  }

  # Get the selected line from the WIP list.
  set skedtext [$windows(wiplist) get $lineno]

  # Make sure the line is not blank.
  if { $skedtext == "" } {
    return
  }

  # Parse the WIP line.
  binary scan $skedtext "a10x1a4x1a6x1a10x1a13x1a6x1a*" \
    skeddate skedutc skedband skedfreq skedcall skedrecd skednote

  # Fix up the fields.
  set skedband [ string trim $skedband ]
  set skedfreq [ string trim $skedfreq ]
  set skedcall [ string trim $skedcall ]
  set skedrecd [ string trim $skedrecd ]
  set skednote [ string trim $skednote ]

  # Only proceed if call, recd, and band check.
  if { [ Valid_Call $skedcall ] == 1 &&
       [ Valid_Grid $skedrecd ] == 1 &&
       [ Valid_Band $skedband ] == 1 } {

    # Wipe out this line in the WIP list.
    # Note: the way to wipe out crazy data is with
    # Delete_WIP or Resked_WIP.
    $windows(wiplist) delete $lineno
    Decrement_WIP

    # Set busy timer
    Busy $::setting(wipbusy)

    # Update the other stations
    Net_Send "wip" "all" ""

    # Set main entry fields with the sked data.
    if { $::setting(bandlock) == 0 } {
      set stuff(band) [ string trim $skedband ]
      Recall_Op_Freq
      Set_Freq exec
    }
    set stuff(call) [ string trim $skedcall ]
    set stuff(recd) [ string trim $skedrecd ]

    # Update bearing.
    Bear_Calc $stuff(sent) $stuff(recd)
    HCO_Light "on"

    # This seems convenient.
    Call_Stack_Push $skedcall $skedrecd

    # Select the call field.
    focus $windows(callentry)
    $windows(callentry) icursor end
    $windows(callentry) select range 0 end

    Annunciate "Work $skedcall in $skedrecd on $skedband ($skedfreq)"
  }
}

#
#  Delete_WIP - procedure to delete the selected WIP.
#

proc Delete_WIP { lineno } {
  global windows stuff sked

  # if not asking to delete a specific line, delete the active line.
  if { $lineno == "active" } {
    set lineno [$windows(wiplist) index active] 
  }

  # Check to make sure we're not trying to delete the header line.
  if { $lineno == 0 } { return }

  # Delete the line in the WIP list.
  $windows(wiplist) delete $lineno
  Decrement_WIP

  # Update the other stations
  Net_Send "wip" "all" ""
}

#
#  Delete_Sked - procedure to delete the selected sked.
#

proc Delete_Sked { made } {
  global windows stuff sked

  # Check to make sure we're not trying to delete the header line.
  set lineno [$windows(skedlist) index active] 
  if { $lineno == 0 } { return }

  # Set line number for new cursor position after delete.
  incr lineno
  # TODO: make this number based upon the listbox size.
  if { $lineno > 12 } { set lineno 12 }

  # Get the line to work on.
  set skedtext [$windows(skedlist) get active]
  binary scan $skedtext "a10x1a4x1a6x1a10x1a13x1a6x1a*" \
    skeddate skedutc skedband skedfreq skedcall skedrecd skednote

  # Fix date and utc and build index into sked array.
  set skeddate [ string trim $skeddate ]
  set skedutc  [ string trim $skedutc ]
  set dateutc "$skeddate:$skedutc"
  set dateutc2 "$skeddate:-$skedutc"
  set index "$stuff(skedpeer),$dateutc"
  set index2 "$stuff(skedpeer),$dateutc2"

  Debug "Delete_Sked" "Deleting $index"

  # Check sked array.
  if { [ info exists sked($index) ] } {
    Del_Sked_Kernel "$made" "$index"
    Redraw_Skeds "entry"
    Save_Skeds
    if { $made == "made" } {
      Annunciate "Marked Sked Made"
      Net_Send "zzz" "all" "MSK: $index"
    } else {
      Annunciate "Deleted Sked"
      Net_Send "zzz" "all" "DSK: $index"
    }
  }

  Debug "Delete_Sked" "Deleting $index2"

  # Check sked array.
  if { [ info exists sked($index2) ] } {
    Del_Sked_Kernel "delete" "$index2"
    Redraw_Skeds "entry"
    Save_Skeds
    Annunciate "Deleted Sked"
    Net_Send "zzz" "all" "DSK: $index2"
  }

  # Select the next row
  $windows(skedlist) activate $lineno
  $windows(skedlist) selection clear 0 end
  $windows(skedlist) selection set $lineno
  $windows(skedlist) see $lineno

  # Set the date and utc fields from the new active row.
  Set_Sked_Time_From_Row "active"
}

#
# Del_Sked_Kernel - mark or remove the sked with the given index.
#

proc Del_Sked_Kernel { action index } {
  global sked

  if { ! [ info exist sked($index) ] } {
    return
  }

  set indexlist [ split $index : ]
  set banddate [ lindex $indexlist 0 ]
  set utc [ lindex $indexlist 1 ]

  if { $action == "made" } {
    # if this sked was not previously made, add a new copy with a dash
    if { [ string index $utc 0 ] != "-" } {
      set sked($banddate:-$utc) $sked($index)
      unset sked($index)
    }
  } else {
    # delete it
    unset sked($index)
  }
}

proc Reap_Sked { band call sent recd } {
  global sked windows

  # traverse array of skeds

  if { ! [ info exist sked ] } {
    return
  }

  set found 0

  for { set handle [ array startsearch sked ]
    set index [ array nextelement sked $handle ] } \
    { $index != "" } \
    { set index [ array nextelement sked $handle ] } {

    set ss ""
    foreach s [ split $sked($index) ] {
      if { $s != "" } {
        lappend ss $s
      }
    }

    set sband [ lindex $ss 0 ]
    set scall [ lindex $ss 2 ]
    set srecd [ lindex $ss 3 ]

    if { $sband == $band && $scall == $call && $srecd == $recd } {
      set found 1
      break
    }
  }

  # finish traversal
  array donesearch sked $handle

  if { $found == 1 } {

    Debug "Reap_Sked" "Marking sked made: $sband $scall $srecd"

    set conf "ok"

    if { $::setting(autoreap) == 0 } {
      # ask if it's ok to reap this sked.
      set conf [ tk_messageBox -icon warning -type okcancel \
        -title "Confirm Sked Made" -message \
"A sked with $call on $band in $recd is about to be marked made.  Is this ok?" ]
    }

    if { $conf == "ok" } {
      Del_Sked_Kernel "made" "$index"
      Redraw_Skeds "entry"
      Save_Skeds

      Annunciate "Marked Sked Made: $sband $scall $srecd"
      Net_Send "zzz" "all" "MSK: $index"
    }
  }

  # remove this guy from WIP if there.

  set n [ $windows(wiplist) size ]

  for { set i 0 } { $i < $n } { incr i } {
    set wip [ $windows(wiplist) get $i ]
  
    set r [ binary scan $wip "a10x1a4x1a6x1a10x1a13x1a6x1a*" \
      sdate sutc sband sfreq scall srecd snote ]
  
    if { $r == 7 } {

      set sband [ string trim $sband ]
      set scall [ string trim $scall ]
      set srecd [ string trim $srecd ]

      if { $sband == $band && $scall == $call && $srecd == $recd } {

        # wipe out this wip entry
        set conf "ok"

        if { $::setting(autoreap) == 0 } {
          # ask if it's ok to reap this sked.
          set conf [ tk_messageBox -icon warning -type okcancel \
            -title "Confirm Sked Made" -message \
"A WIP entry with $call on $band in $recd is about to be deleted.  Is this ok?" ]
        }

        if { $conf == "ok" } {
          Delete_WIP $i
        }
      }
    }
  }
}

#
# Check_Sked
#

proc Check_Sked { context } {
  global windows stuff

  # Fix entry fields.
  set stuff(skedpeer) [ string trim $stuff(skedpeer) ]
  set stuff(skeddate) [ string trim $stuff(skeddate) ]
  set stuff(skedutc)  [ string trim $stuff(skedutc) ]
  set stuff(skedband) [ string trim [ string toupper $stuff(skedband) ] ]
  set stuff(skedfreq) [ string trim [ string toupper $stuff(skedfreq) ] ]
  set stuff(skedcall) [ string trim [ string toupper $stuff(skedcall) ] ]
  set stuff(skedrecd) [ string trim [ string toupper $stuff(skedrecd) ] ]

  # Check time.
  if { $context == "sked" } {

    set skedh [ string range $stuff(skedutc) 0 1 ]
    set skedm [ string range $stuff(skedutc) 2 3 ]
    set skedt [ clock scan "$stuff(skeddate) ${skedh}:${skedm}" ]
    set nowt [expr $stuff(utcoffset) * 3600 + [clock seconds]]

    if { $skedt < $nowt } {
      set ok [ tk_messageBox -icon error -type okcancel \
        -title "Sked Error" -parent $windows(skeds) -message \
        "The sked time is in the past.  Is this ok?" ]
      if { $ok == "cancel" } {
        focus $windows(skedlist)
        return 0
      } else {
        return 1
      }
    }
  }

  # Check band.
  if { [ Valid_Band $stuff(skedband) ] == 0 } {
    tk_messageBox -icon error -type ok \
        -title "Pass/Sked Error" -parent $windows(skeds) -message \
      "Please correct the $context band \"$stuff(skedband)\"."
    return 0
  }

  # Check call.
  if { [ Valid_Call $stuff(skedcall) ] == 0 } {
    tk_messageBox -icon error -type ok \
      -title "Pass/Sked Error" -parent $windows(skeds) -message \
      "Please correct the $context callsign \"$stuff(skedcall)\"."
    focus $windows(skedcall)
    return 0
  }

  # Check grid.
  if { [ Valid_Grid $stuff(skedrecd) ] == 0 } {
    tk_messageBox -icon error -type ok \
      -title "Pass/Sked Error" -parent $windows(skeds) -message \
      "Please correct the $context received grid \"$stuff(skedrecd)\"."
    focus $windows(skedrecd)
    return 0
  }

  return 1
}

#
#  Add_Sked - procedure to take Information from the window and
#              make a sked out of it.
#

proc Add_Sked { } {
  global windows stuff sked

  # Check data
  if { ! [ Check_Sked "sked" ] } {
    focus $windows(skeds)
    return
  }

  # Set index for sked.
  set dateutc "$stuff(skeddate):$stuff(skedutc)"

  # Set line to add to sked array.
  set line [ format "%s,%s %-6.6s %-10.10s %-13.13s %-6.6s %s" \
    $stuff(skedpeer) $dateutc $stuff(skedband) $stuff(skedfreq) \
    $stuff(skedcall) $stuff(skedrecd) "$stuff(skednote)" ]

  # Get current line number for selecting the next line automatically.
  set lineno [$windows(skedlist) index active] 
  set skedtext [$windows(skedlist) get active]

  # If this is not OUR schedule, popup an "Are you sure?" dialog.
  if { $stuff(skedpeer) != $::setting(mypeername) } {

    # get peer number from name
    set peerno [ Peer_By_Name $stuff(skedpeer) ]

    # get IP address and port from array
    set peerpt   [ lindex $::setting(p$peerno) 2 ]

    # check for station out of touch
    if { $peerpt == 0 || \
      $stuff($stuff(skedpeer),wip) == "" || \
      $stuff($stuff(skedpeer),wiplimit) == "" || \
      $stuff($stuff(skedpeer),busy) == "" } {
      set ok [ tk_messageBox -icon error -type okcancel -parent $windows(skeds) \
        -title "Station Unreachable" -message \
        "The station you are making a sked for\nis not reachable at this time.\nThe station will not receive this sked.\nAre you sure you wish to continue?" ]
      if { $ok != "ok" } {
        return
      }
    }

    set t [ clock seconds ]
    set t [ expr $stuff(utcoffset) * 3600 + \
      ( $t - $t % ( $::setting(skedtinc) * 60 ) ) ]
    set datenow [ clock format $t -format "%Y-%m-%d" ]
    set utcnow [ clock format $t -format "%H%M" ]
    set dateutcnow "$datenow:$utcnow"

    # If passing right now, check the other station's WIP and busy.
    Debug "Add_Sked" "Sked dateutc = $dateutc, Now dateutc = $dateutcnow"
    if { $dateutc == $dateutcnow &&
      ( $stuff($stuff(skedpeer),wip) >= $stuff($stuff(skedpeer),wiplimit) || \
      $stuff($stuff(skedpeer),busy) != 0 ) } {
      tk_messageBox -icon warning -type ok -parent $windows(skeds) \
        -title "Station Busy" -message \
        "The station you are passing to is too busy at this time.\nPlease sked later."
      return
    }

    # Check to see if there is already something in this slot.
    if { [ string length $skedtext ] > 15 } {
      set conf "ok"
      set conf [ tk_messageBox -icon warning -type okcancel -parent $windows(skeds) \
        -title "Confirm Sked Overwrite" -message \
"You are overwriting a sked for another station.  Is this ok?" ]
      if { $conf != "ok" } {
        return
      }
    }
  }
  # Set the new line number to activate.
  incr lineno
  if { $lineno > 12 } { set lineno 12 }

  # Do the sked-adding guts part.
  Add_Sked_Kernel $line
  Redraw_Skeds "entry"
  Save_Skeds
  Net_Send "zzz" "all" "SKD: $line"
  Annunciate "Sked Added"

  # Set up for the next sked.
  set stuff(skedband) [ QSY $stuff(skedband) $::setting(skedqsy) ]

  # Select the next row
  $windows(skedlist) activate $lineno
  $windows(skedlist) selection clear 0 end
  $windows(skedlist) selection set $lineno
  $windows(skedlist) see $lineno

  # Need to set the sked time to the currently active row's time.
  Set_Sked_Time_From_Row "active"

  return
}

# 
# Annunciate - procedure to place a message in the annunciator
#              entry field.
#

proc Annunciate { m } {
  global windows stuff

  if { [ info exist stuff(ann_after_id) ] } {
    after cancel $stuff(ann_after_id)
    unset stuff(ann_after_id)
  }

  set stuff(annunciator) "$m"

  $windows(annentry) configure -readonlybackground red -fg yellow

  Debug "Annunciate" "$m"
  if { $::setting(annbell) == 1 } {
    bell
  }
  set stuff(ann_after_id) [ after 10000 { set stuff(annunciator) "" ; $windows(annentry) configure -readonlybackground $stuff(annbg) -fg $stuff(annfg) } ]

  set t [clock seconds]
  set date [clock format $t -format "%Y-%m-%d"]
  set utc [clock format $t -format "%H:%M:%S"]
  set d "$date $utc"

  $windows(infotext) insert end "$d: $m\n"
  $windows(infotext) see end

  update idletasks
}

#
# Net_Log
#

proc Net_Log { peername s } {
  global windows stuff

  if { $::setting(verbnetlog) == 0 && [ string range $s 0 0 ] == "<" } {
    return
  }

  # Get date and time.
  set t [expr $stuff(utcoffset) * 3600 + [clock seconds]]
  set utc [clock format $t -format "%H%M"]

  $windows(netmessages) insert end "\n$utc $::setting(mypeername)>$peername:$s"
  $windows(netmessages) see end
}

# 
# Net_Log_RX
#

proc Net_Log_RX { srcpeername dstpeername s } {
  global windows stuff

  # TODO: Log network messages to a file here.

  if { $::setting(verbnetlog) == 0 && [ string range $s 0 0 ] == "<" } {
    return
  }

  # Get date and time.
  set t [expr $stuff(utcoffset) * 3600 + [clock seconds]]
  set utc [clock format $t -format "%H%M"]

  $windows(netmessages) insert end "\n"
  if { $dstpeername != "all" } {
    $windows(netmessages) insert end "$utc $srcpeername>$dstpeername:$s" { intag }
  } else {
    $windows(netmessages) insert end "$utc $srcpeername>$dstpeername:$s"
  }
  $windows(netmessages) see end
}

#
# Unblacklist
#

proc Unblacklist { who } {
  global windows stuff


  if { $stuff(blacklist,$who) == 1 } {
    Debug "Unblacklist" "Unblacklisting $who."
  }
  set stuff(blacklist,$who) 0

  switch -regexp -- $who {
    ^rotor$
      {
        $windows(rotorbutton) configure -fg black
        $windows(calcbutton) configure -fg black
	# try to reconnect
	Open_Rotor
      }
    ^keyer$
      {
        $windows(mainkeyerbutton) configure -fg black
        $windows(keyerbutton) configure -fg black
	Open_Keyer
      }
    ^super$
      {
        $windows(mainsuperbutton) configure -fg black
	Open_Super
      }
    ^gps$
      {
        $windows(fromgpsbutton) configure -fg black
	Open_GPS
      }
    ^r.*$
      {
        set bandno [ string range $who 1 end ]
        $windows(rigfreqbutton) configure -fg black

	# Only clear info button to black color if
	# no rigs or peers are blacklisted.
        set a 0
        for { set i 1 } { $i < 18 } { incr i } {
          set a [ expr $a | $stuff(blacklist,r$i) ]
        }
        for { set i 1 } { $i < 13 } { incr i } {
          set a [ expr $a | $stuff(blacklist,p$i) ]
        }
        if { ! $a } {
          $windows(infobutton) configure -fg black
        }

	# Try to reconnect
	Open_Rig $bandno

      }
    ^p.*$
      {
        set peerno [ string range $who 1 end ]
        $windows(peerbutton$peerno) configure -fg black

	# Only clear info button to black color if
	# no rigs or peers are blacklisted.
        set a 0
        for { set i 1 } { $i < 18 } { incr i } {
          set a [ expr $a | $stuff(blacklist,r$i) ]
        }
        for { set i 1 } { $i < 13 } { incr i } {
          set a [ expr $a | $stuff(blacklist,p$i) ]
        }
        if { ! $a } {
          $windows(infobutton) configure -fg black
        }

	# Try to reconnect
	Open_Peer $peerno
        set peername [ lindex $::setting(p$peerno) 0 ]
        Net_Send "rwp" $peername ""
        Net_Send "rfq" $peername ""
      }
    default
      {
        # Do nothing
      }
  }
}

#
# Blacklist
#
# Limitation - Do not try to blacklist my own peer number.
#

proc Blacklist { who why } {
  global windows stuff

  if { $stuff(blacklist,$who) == 0 } {
    Debug "Blacklist" "Blacklisting $who: $why."
  }

  switch -regexp -- $who {
    ^rotor$
      {
        $windows(calcbutton) configure -fg red
        $windows(rotorbutton) configure -fg red
        set stuff(rotorstatus) Blacklisted 
        set stuff(rotortime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
      }
    ^keyer$
      {
        $windows(mainkeyerbutton) configure -fg red
        $windows(keyerbutton) configure -fg red
        set stuff(keyerstatus) Blacklisted 
        set stuff(keyertime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
      }
    ^super$
      {
        $windows(mainsuperbutton) configure -fg red
        set stuff(superstatus) Blacklisted 
        set stuff(supertime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
      }
    ^gps$
      {
        $windows(fromgpsbutton) configure -fg red
        set ::setting(gps) 0
        set stuff(gpsstatus) Blacklisted 
        set stuff(gpstime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
      }
    ^r.*$
      {
        set bandno [ string range $who 1 end ]
        $windows(infobutton) configure -fg red
        $windows(rigfreqbutton) configure -fg red

        set stuff(rigstatus$bandno) Blacklisted 
        set stuff(rigtime$bandno) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]

      }
    ^p.*$
      {
        $windows(infobutton) configure -fg red
        set peerno [ string range $who 1 end ]
        $windows(peerbutton$peerno) configure -fg red

        set stuff(peerstatus$peerno) Blacklisted 
        set stuff(peertime$peerno) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
      }
    default
      {
        # Do nothing
      }
  }
  set stuff(blacklist,$who) 1
  
}

#
# Peer_Puts - Replacement puts for sending to a peer with
# error detection and blacklisting if merited.
#

proc Peer_Puts { peerno m } {
  global stuff

  set s $stuff(peersid,$peerno)

  if { [ fblocked $s ] } {
    Debug "Peer_Puts" "Peer $peerno is blocked. Skipping."
    return -1
  }

  Debug "Peer_Puts" "Sending $m to peer number $peerno"

  if { [ catch { puts $stuff(peersid,$peerno) $m } r ] } {
    Blacklist p$peerno "puts failed: $r"
    return
  }

  # flush $stuff(peersid,$peerno)

  set stuff(peerstatus$peerno) "$m"
  set stuff(peertime$peerno) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
}

#
# Net_Send_Kernel - procedure to perform the actual net message sending
#
# "log" - Send the whole log.
# "skd" - Send all skeds.
# "rwp" - Request WIP info.
# "wip" - Send WIP info.
# "rfq" - Request frequency info.
# "frq" - Send frequency info.
# "msg" - Send chat message.
# "png" - Send ping.
# "all" - Send broadcast message.
# "zzz" - Other message that needs no special handling.
#

proc Net_Send_Kernel { what peerno msg } {
  global stuff

  # Check to see if there is even an entry for this peer number
  if { [ llength $::setting(p$peerno) ] < 3 } {
    # Debug "Net_Send_Kernel" "Peer $peerno is not configured. Skipping."
    return
  }
  
  # Get IP address and port from array
  set peername [ lindex $::setting(p$peerno) 0 ]
  set peerip   [ lindex $::setting(p$peerno) 1 ]
  set peerpt   [ lindex $::setting(p$peerno) 2 ]

  if { $peerpt == 0 } {
    # Debug "Net_Send_Kernel" "Peer $peerno is disabled. Skipping."
    return
  }

  # Check to see if this guy is blacklisted
  if { $stuff(blacklist,p$peerno) == 1 } {
    # Debug "Net_Send_Kernel" "Peer $peerno is blacklisted. Skipping."
    return
  }

  # send whatever message was indicated

  # send the whole log
  if { $what == "log" } {

    Debug "Net_Send_Kernel" "sending log to $peername."

    set bunch [$windows(loglist) get 0 end]
    foreach b $bunch { Peer_Puts $peerno $b }
    Peer_Puts $peerno "REF: "

    # Net_Log $peername "<log>"

  # send all the skeds
  } elseif { $what == "skd" } {

    Debug "Net_Send_Kernel" "sending skeds to $peername."

    if { [ info exists sked ] } {
      for { set handle [ array startsearch sked ]
        set index [ array nextelement sked $handle ] } \
        { $index != "" } \
        { set index [ array nextelement sked $handle ] } {
          Peer_Puts $peerno "SKD: $index $sked($index)"
      }
    }

    # Net_Log $peername "<skeds>"

  # send WIP request
  } elseif { $what == "rwp" } {

    Debug "Net_Send_Kernel" \
      "sending WIP request to $peername."

    Peer_Puts $peerno "RWP: $::setting(mypeername)"
    
    # Net_Log $peername "<WIP Request>"

  # send WIP
  } elseif { $what == "wip" } {

    Debug "Net_Send_Kernel" \
      "sending WIP to $peername."

    if { ! [ string is integer -strict $stuff(busy) ] } {
      set stuff(busy) 0
    }

    if { ! [ string is integer -strict $stuff(wip) ] } {
      set stuff(wip) 0
    }

    if { ! [ string is integer -strict $::setting(wiplimit) ] } {
      set ::setting(wiplimit) 0
    }

    set r [ format "WIP: %s busy %d wip %d wiplimit %d" \
      $::setting(mypeername) $stuff(busy) $stuff(wip) $::setting(wiplimit) ]
    Peer_Puts $peerno $r

    # Net_Log $peername "<WIP>"

  # send operating frequency
  } elseif { $what == "frq" } {

    set r [ format "FRQ: %s %s %s" $::setting(mypeername) $stuff(opfreq) $stuff(stat) ]

    Debug "Net_Send_Kernel" \
      "sending freq to $peername."

    Peer_Puts $peerno $r

    # Net_Log $peername "<freq>"

  # send operating frequency request
  } elseif { $what == "rfq" } {

    Debug "Net_Send_Kernel" \
      "sending freq request to $peername."

    Peer_Puts $peerno "RFQ: $::setting(mypeername)"

    # Net_Log $peername "<freq request>"

  # send chat message
  } elseif { $what == "msg" } {

    Debug "Net_Send_Kernel" "sending chat message to $peername."
    Peer_Puts $peerno "MSG: $::setting(mypeername) $msg"

  # send broadcast message
  } elseif { $what == "all" } {

    Debug "Net_Send_Kernel" "sending broadcast message to $peername."
    Peer_Puts $peerno "ALL: $::setting(mypeername) $msg"

  # send something else
  } else {

    Debug "Net_Send_Kernel" \
      "sending other message to $peername."

    # send the message, but don't report it in the log.
    Peer_Puts $peerno $msg
  }

  # flush the descriptor
  # if { [ catch { flush $s } ] } {
  #   Blacklist p$peerno "flush failed"
  # }
}

#
# Net_Send - procedure to send the given message to the given peer.
#

proc Net_Send { what peername msg } {
  global stuff windows

  # Debug "Net_Send" "what=$what peername=$peername msg=$msg"

  # Do nothing if networking is disabled.
  if { $::setting(netenable) == 0 } {
    # Debug "Net_Send" "Networking disabled."
    return
  }

  # Warn for really goofy actions

  set t ""

  if { $what == "log" } {
    set t "the whole log"
  } elseif { $what == "skd" } {
    set t "all skeds"
  }

  if { $t != "" } {
    set ok [ tk_messageBox -icon warning -type okcancel -parent $windows(net) \
      -title "Performance Degradation Warning" -message \
      "It is very likely this action will cause lag for the stations on your network.\nDo you really wish to send ${t}?" ]

    if { $ok != "ok" } {
      Debug "Peer_Write_Handler" "not sending."
      return
    }

  }

  set mypeerno [ Peer_By_Name $::setting(mypeername) ]

  # This is a broadcast
  if { $peername == "all" } {

    # Debug "Net_Send" "Sending to all peers."

    # Loop through all peers
    for { set i 1 } { $i < 13 } { incr i } {
      if { $i == $mypeerno } {
        continue
      }
      # Debug "Net_Send" "Sending to peer $i."
      if { $what == "msg" } {
        Net_Send_Kernel "all" $i $msg
      } else {
        Net_Send_Kernel $what $i $msg
      }
    }

    # Log this only once.
    if { $what == "msg" } {
      Net_Log $peername $msg
    }

  # This is a directed message
  } else {

    set peerno [ Peer_By_Name $peername ]
    if { $peerno != 0 && $peerno != $mypeerno } {
      # Debug "Net_Send" "Sending to peer $peerno."
      Net_Send_Kernel $what $peerno $msg
    }

    if { $what == "msg" } {
      Net_Log $peername $msg
    }
  }

  return
}  

#
# Drop_Slash - procedure to cut off a trailing "/xxx" from the callsign.
#
# New: add "/R" back on if the original call had "/R" in it.
#

proc Drop_Slash { w c } {
  if { $w == "first" || $w == "rover" } {
    set i [ string first "/" $c ]
  } else {
    set i [ string last "/" $c ]
  }
  if { $i != -1 } {
    set r [ string range $c 0 [ expr $i - 1 ] ]
    if { $w == "rover" && [ string first "/R" $c ] != -1 } {
      set r "${r}/R"
    }
  } else { 
    set r $c
  }
  return $r
}

#
# Lookup Database:
#
# index by call-recd,sent
#

#
# Lookup_Add - procedure to add the given QSO data to the lookup database.
#

proc Lookup_Add { band call sent recd } {
  global stat

  incr stat(Lookup_Add,t) [ lindex [ time { Lookup_Add_Stub $band $call $sent $recd } ] 0 ]
  incr stat(Lookup_Add,n)

  return
}

proc Lookup_Add_Stub { band call sent recd } {
  global lookup lookupgrid lookupband lookuprecd

  # clean up parameters
  set band [ string trim $band ]
  set call [ string toupper [ string trim $call ] ]
  set call [ Drop_Slash "rover" $call ]

  if { $::setting(rules) == "dist" || $::setting(rules) == "grid6" } {
    set gridend 5
    if { [ string length $sent ] < 6 } {
      set sent [ string range $sent 0 3 ]
      set sent "${sent}MM"
    }
    if { [ string length $recd ] < 6 } {
      set recd [ string range $recd 0 3 ]
      set recd "${recd}MM"
    }
  } else {
    set gridend 3
  }

  set s [ string toupper [ string range $sent 0 $gridend ] ]
  set recd [ string trim $recd ]
  set r [ string toupper [ string range $recd 0 $gridend ] ]
  set icall "$call-$r,$s"

  # add this to the lookup database
  if { [ info exist lookup($icall) ] } {
    if { [ string first $band $lookup($icall) ] == -1 } {
      set lookup($icall) [ concat $lookup($icall) $band ]
    }
  } else {
    set lookup($icall) $band
  }

  # Add the received grid to the lookupgrid database.

  # If this call is already there, look for the current grid.
  if { [ info exist lookupgrid($call) ] } {
    # If we find this element in the list already, move it to the end.
    # Debug "Lookup_Add" "searching for old entry $call ${r}*"
    set i [ lsearch -glob $lookupgrid($call) "${r}*" ]
    # Debug "Lookup_Add" "search result: $i"
    if { $i >= 0 } {
      # Save the old entry.
      set t [ lindex $lookupgrid($call) $i ]
      # Delete the old entry.
      # Debug "Lookup_Add" "deleting old entry $call $t"
      set lookupgrid($call) [ lreplace $lookupgrid($call) $i $i ]
    }  
    # If the recd grid currently logged is six digits,
    # add the new entry to the end of the list.
    # It could be new.
    if { [ string length $recd ] == 6 } {
      # Debug "Lookup_Add" "appending $call $recd"
      lappend lookupgrid($call) $recd
    # Otherwise just move the old entry (if any) to the end.
    # It might be six digits known from earlier.
    } else {
      if { [ info exist t ] } {
        # Debug "Lookup_Add" "appending $call $t"
        lappend lookupgrid($call) $t
      } else {
        # Debug "Lookup_Add" "appending $call $recd"
        lappend lookupgrid($call) $recd
      }
    }
  # This is the first time we've heard of this callsign.
  # Create a new list with the current received grid.
  } else {
    # Debug "Lookup_Add" "creating $call $recd"
    set lookupgrid($call) [ list $recd ]
  }

  if { [ info exist lookupgrid($call) ] } {
    # Debug "Lookup_Add" "lookupgrid($call)"
    foreach b $lookupgrid($call) {
      # Debug "Lookup_Add" "$b"
    }
  }

  # This one is for filling in the last known grid for a worked station.
  lappend lookuprecd($call) $recd

  # If needed, add this band for this call
  if { [ info exist lookupband($call) ] } {
    if { [ lsearch $lookupband($call) "$band" ] < 0 } {
      lappend lookupband($call) $band
    }
  } else {
    set lookupband($call) [ list $band ]
  }
  return
}

#
# Lookup_Delete - procedure to delete the given QSO data from
#                 the lookup database.
#

proc Lookup_Delete { band call sent recd } {
  global lookup

  # clean up parameters
  set band [ string trim $band ]
  set call [ string toupper [ string trim $call ] ]

  if { $::setting(rules) == "dist" || $::setting(rules) == "grid6" } {
    set gridend 5
    if { [ string length $sent ] < 6 } {
      set sent [ string range $sent 0 3 ]
      set sent "${sent}MM"
    }
    if { [ string length $recd ] < 6 } {
      set recd [ string range $recd 0 3 ]
      set recd "${recd}MM"
    }
  } else {
    set gridend 3
  }

  set s [ string toupper [ string range $sent 0 $gridend ] ]
  set r [ string toupper [ string range $recd 0 $gridend ] ]

  set call [ Drop_Slash "rover" $call ]
  set icall "$call-$r,$s"

  if { [ info exist lookup($icall) ] } {
    set start [ string first $band $lookup($icall) ]
    set lookup($icall) [ string replace $lookup($icall) $start \
      [ expr $start + [ string length $band ] ] ]
    if { [ string length $lookup($icall) ] == 0 } {
      unset lookup($icall)
    }
  }
}

#
# Worked Database:
#
# old rover rules:
#   index by band,sent_recd
#   (each new spot you work someone from counts as a mult)
# new rover rules:
#   index by band,recd
#   (doesn't matter where you worked a station from)
#

#
#  Increment_Worked - procedure to create or increment a count
#                     of stations worked for the given band and grid.
#                     This shouldn't be called until the fields are
#                     confirmed to be valid and non-dupe.
#

proc Increment_Worked { band sent recd quiet } {
  global stat

  incr stat(Increment_Worked,t) [ lindex [ time { set r [ Increment_Worked_Stub $band $sent $recd $quiet ] } ] 0 ]
  incr stat(Increment_Worked,n)

  return $r
}

proc Increment_Worked_Stub { band sent recd quiet } {
  global stuff worked activated windows

  set new_mult 0

  # clean up parameters
  set band [ string trim $band ]

  if { $::setting(rules) == "dist" || $::setting(rules) == "grid6" } {
    set gridend 5
    if { [ string length $sent ] < 6 } {
      set sent [ string range $sent 0 3 ]
      set sent "${sent}MM"
    }
    if { [ string length $recd ] < 6 } {
      set recd [ string range $recd 0 3 ]
      set recd "${recd}MM"
    }
  } else {
    set gridend 3
  }

  set s [ string toupper [ string range $sent 0 $gridend ] ]
  set r [ string toupper [ string range $recd 0 $gridend ] ]

  if { $::setting(rules) == "old" } {
    set sr [ concat $s "_" $r ]
  } else {
    set sr $r
  }

  if { [ info exist worked($band,$sr) ] } {
    set worked($band,$sr) [ expr $worked($band,$sr) + 1 ]
  } else {
    set worked($band,$sr) 1
    if { $quiet != "quiet" } {
      Annunciate "Multiplier Added"
    }
    set new_mult 1
  }

  if { [ info exist activated($s) ] } {
    set activated($s) [ expr $activated($s) + 1 ]
  } else {
    set activated($s) 1
  }

  return $new_mult
}

#
#  Decrement_Worked - procedure to decrement the number of stations
#                     worked for the given band and grid.
#

proc Decrement_Worked { band sent recd } {
  global stuff worked activated

  if { $::setting(rules) == "dist" || $::setting(rules) == "grid6" } {
    set gridend 5
    if { [ string length $sent ] < 6 } {
      set sent [ string range $sent 0 3 ]
      set sent "${sent}MM"
    }
    if { [ string length $recd ] < 6 } {
      set recd [ string range $recd 0 3 ]
      set recd "${recd}MM"
    }
  } else {
    set gridend 3
  }

  set s [ string toupper [ string range $sent 0 $gridend ] ]
  set r [ string toupper [ string range $recd 0 $gridend ] ]

  if { $::setting(rules) == "old" } {
    set sr [ concat $s "_" $r ]
  } else {
    set sr $r
  }

  if { [ info exist worked($band,$sr) ] } {
    set worked($band,$sr) [ expr $worked($band,$sr) - 1 ]
    if { $worked($band,$sr) <= 0 } {
      unset worked($band,$sr)
    }
  }

  if { [ info exist activated($s) ] } {
    set activated($s) [ expr $activated($s) - 1 ]
  } else {
    set activated($s) 0
  }

  Redraw_Map $stuff(mapcenter)
  Redraw_Score
}

#
#  Valid_Date - procedure to determine if the variable contains
#               two numbers a slash, two numbers, a slash and
#               four numbers.
#

proc Valid_Date { x } {
  return [regexp {^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$} $x]
}

#
#  Valid_UTC - procedure to determine if the variable contains
#              four numbers.
#

proc Valid_UTC { x } {
  return [regexp {^[0-9][0-9][0-9][0-9]$} $x]
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
#  Valid_Mode - procedure to determine if the given mode is an
#               element in the list of modes.
#

proc Valid_Mode { x } {
  global stuff

  if { [ lsearch -exact $::setting(modes) $x ] != -1 } {
    return 1
  } else {
    return 0 
  }
}

#
#  Valid_Band - procedure to determine if the given band is an
#               element in the list of bands.
#

proc Valid_Band { x } {
  global stuff

  if { [ lsearch -exact $::setting(bands) $x ] != -1 } {
    return 1
  } else {
    return 0 
  }
}

#
#  Valid_Call - procedure to determine if the given callsign is valid
#               for the US, Canada, or Mexico.
#

proc Valid_Call { x } {
  global stuff

  if { $x == "" } {
    return 0
  }

  if { $::setting(callcheck) == 0 || $::setting(callcheck) == "none" } {
    return 1
  } else {

    # Strip off / and suffix of digit or rover
    set x [ Drop_Slash "first" $x ]
    set x [ Drop_Slash "first" $x ]

    if { $::setting(callcheck) == "lax" } {
      return [ string is alnum $x ]
    } else {
      #  check valid 1x1 1x2 1x3 2x1 2x2 and 2x3 calls
      if {[string length $x] == 6 && [ regexp {^[A,K,N,W][A-Z][0-9][A-Z][A-Z][A-Z]} $x]} {return 1}
      if {[string length $x] == 5 && [ regexp {^[A,K,N,W][0-9][A-Z][A-Z][A-Z]} $x]} {return 1}
      if {[string length $x] == 5 && [ regexp {^[A,K,N,W][A-Z][0-9][A-Z][A-Z]} $x]} {return 1}
      if {[string length $x] == 4 && [ regexp {^[A,K,N,W][0-9][A-Z][A-Z]} $x]} {return 1}
      if {[string length $x] == 4 && [ regexp {^[A,K,N,W][A-Z][0-9][A-Z]} $x]} {return 1}
      if {[string length $x] == 3 && [ regexp {^[A,K,N,W][0-9][A-Z]} $x]} {return 1}
      if {[string length $x] == 4 && [ regexp {^VE[0-9][A-Z]} $x]} {return 1}
      if {[string length $x] == 5 && [ regexp {^VE[0-9][A-Z][A-Z]} $x]} {return 1}
      if {[string length $x] == 6 && [ regexp {^VE[0-9][A-Z][A-Z][A-Z]} $x]} {return 1}
      if {[string length $x] == 4 && [ regexp {^VA[1-7][A-Z]} $x]} {return 1}
      if {[string length $x] == 5 && [ regexp {^VA[1-7][A-Z][A-Z]} $x]} {return 1}
      if {[string length $x] == 6 && [ regexp {^VA[1-7][A-Z][A-Z][A-Z]} $x]} {return 1}
      if {[string length $x] == 4 && [ regexp {^VO[1-2][A-Z]} $x]} {return 1}
      if {[string length $x] == 5 && [ regexp {^VO[1-2][A-Z][A-Z]} $x]} {return 1}
      if {[string length $x] == 6 && [ regexp {^VO[1-2][A-Z][A-Z][A-Z]} $x]} {return 1}
      if {[string length $x] == 4 && [ regexp {^VY[0-2][A-Z]} $x]} {return 1}
      if {[string length $x] == 5 && [ regexp {^VY[0-2][A-Z][A-Z]} $x]} {return 1}
      if {[string length $x] == 6 && [ regexp {^VY[0-2][A-Z][A-Z][A-Z]} $x]} {return 1}
      if {[string length $x] == 4 && [ regexp {^XE[1-3][A-Z]} $x]} {return 1}
      if {[string length $x] == 5 && [ regexp {^XE[1-3][A-Z][A-Z]} $x]} {return 1}
      if {[string length $x] == 6 && [ regexp {^XE[1-3][A-Z][A-Z][A-Z]} $x]} {return 1}
      if {[string length $x] == 4 && [ regexp {^XF[1-4][A-Z]} $x]} {return 1}
      if {[string length $x] == 5 && [ regexp {^XF[1-4][A-Z][A-Z]} $x]} {return 1}
      if {[string length $x] == 6 && [ regexp {^XF[1-4][A-Z][A-Z][A-Z]} $x]} {return 1}

      return 0
    }
  }
}
#
#  To_Grid - procedure to convert a variable containing two
#            floating point numbers into a six-digit grid
#            square.
#

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

  return $grid
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

#
# Dist_Calc_Km - procedure to compute the distance between two stations.
#

proc Dist_Calc_Km { gridl gridr } {

  set sentll [ To_LatLon $gridl ]
  set recdll [ To_LatLon $gridr ]

  if { [ Valid_Grid $gridl ] && [ Valid_Grid $gridr ] &&
    $sentll != $recdll } {

    set latlonl $sentll
    set latlonr $recdll

    set pi [ expr 2 * asin( 1.0 ) ]

    scan $latlonl "%f %f" latl lonl
    scan $latlonr "%f %f" latr lonr

    set dlon [ expr ( $lonl - $lonr ) / 180.0 * $pi ]
    set mylatl [ expr ( $latl / 180.0 * $pi ) ]
    set mylatr [ expr ( $latr / 180.0 * $pi ) ]

    set temp [ expr sin( $mylatl ) * sin( $mylatr ) + \
                    cos( $mylatl ) * cos( $mylatr ) * cos( $dlon ) ]

    if { $temp > 1 } { set temp 1.0 }

    set distkm [ expr 6378.1 * acos( $temp ) ]

    return $distkm

  } else {

    return 0
  }
}

#
#  Bear_Calc - procedure to compute the bearing and distance between
#              two points given by latitude and longitude.
#

proc Bear_Calc { gridl gridr } {
  global windows

  if { [ wm state $windows(calc) ] == "withdrawn" } { return }
  Bear_Calc_Kernel $gridl $gridr
}

proc Bear_Calc_Kernel { gridl gridr } {
  global stuff windows

  set stuff(calcrecd) $gridr

  Debug "Bear_Calc_Kernel" "$gridl $gridr"

  set gridl [ string toupper [ string trim $gridl ] ]
  set gridr [ string toupper [ string trim $gridr ] ]

  if { [ scan $::setting(antoffset) "%f" dummy ] != 1 } {
    set ::setting(antoffset) 0.0
  }

  set sentll [ To_LatLon $gridl ]
  set recdll [ To_LatLon $gridr ]

  if { ! [ Valid_Grid $gridl ] || ! [ Valid_Grid $gridr ] ||
    $sentll == $recdll } {

    return
  }

  set latlonl $sentll
  set latlonr $recdll

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

  if { $dist != 0 } {

    # Miles
    set stuff(rang) [ expr round(10.0 * ($dist * 3963.1676)) / 10.0 ]
    set stuff(rangkm) [ expr round(10.0 * ($dist * 3963.1676 * 1.609344)) / 10.0 ]

    set temp [ expr ( sin( $mylatr ) - sin( $mylatl ) * cos( $dist ) ) / \
      ( sin( $dist ) * cos( $mylatl ) ) ]

    if { $temp > 1 } { set temp 1.0 }
    if { $temp < -1 } { set temp -1.0 }

    set stuff(brng) [ expr round((acos( $temp ) * 180.0 / $pi) * 10.0) / 10.0 ]
    if { $dlon > 0.0 } then {
      set stuff(brng) [ expr 360.0 - $stuff(brng) ]
    }

    set stuff(rotorbrng) [ expr $stuff(brng) - $::setting(antoffset) ]
    if { $stuff(rotorbrng) < 0 } {
      set stuff(rotorbrng) [ expr $stuff(rotorbrng) + 360.0 ]
    }

    set stuff(mbrng) [ expr $stuff(brng) - $::setting(declination) ]
    if { $stuff(mbrng) < 0 } {
      set stuff(mbrng) [ expr $stuff(mbrng) + 360.0 ]
    }

    set temp [ expr ( sin( $mylatl ) - sin( $mylatr ) * cos( $dist ) ) / \
      ( sin( $dist ) * cos( $mylatr ) ) ]

    if { $temp > 1 } { set temp 1.0 }
    if { $temp < -1 } { set temp -1.0 }

    set stuff(rbrng) [ expr round((acos( $temp ) * 180.0 / $pi) * 10.0) / 10.0 ]
    if { $dlon < 0.0 } then {
      set stuff(rbrng) [ expr 360.0 - $stuff(rbrng) ]
    }
    # set stuff(rbrng) [ expr $stuff(rbrng) - $::setting(antoffset) ]
    if { $stuff(rbrng) < 0 } {
      set stuff(rbrng) [ expr $stuff(rbrng) + 360.0 ]
    }

    set stuff(mrbrng) [ expr $stuff(rbrng) - $::setting(declination) ]
    if { $stuff(mrbrng) < 0 } {
      set stuff(mrbrng) [ expr $stuff(mrbrng) + 360.0 ]
    }

  } else {

    set stuff(brng) 0.0

    set stuff(rotorbrng) [ expr $stuff(brng) - $::setting(antoffset) ]
    if { $stuff(rotorbrng) < 0 } {
      set stuff(rotorbrng) [ expr $stuff(rotorbrng) + 360.0 ]
    }

    set stuff(mbrng) [ expr $stuff(brng) - $::setting(declination) ]
    if { $stuff(mbrng) < 0.0 } {
      set stuff(mbrng) [ expr $stuff(mbrng) + 360.0 ]
    }

    set stuff(rbrng) 180.0
    set stuff(rbrng) [ expr $stuff(rbrng) - $::setting(antoffset) ]
    if { $stuff(rbrng) < 0 } {
      set stuff(rbrng) [ expr $stuff(rbrng) + 360.0 ]
    }

    set stuff(mrbrng) [ expr $stuff(rbrng) - $::setting(declination) ]
    if { $stuff(mrbrng) < 0.0 } {
      set stuff(mrbrng) [ expr $stuff(mrbrng) + 360.0 ]
    }

    set stuff(rang) 0.0
    set stuff(rangkm) 0.0
  }

  Set_Compass $stuff(brng)

  return
}

#
#  Lookup_Dupe - procedure to search the dynamic database for
#                the remote station by callsign/grid.
#

proc Lookup_Dupe { band sent call recd } {
  global stat

  incr stat(Lookup_Dupe,t) [ lindex [ time { set r [ Lookup_Dupe_Stub $band $sent $call $recd ] } ] 0 ]
  incr stat(Lookup_Dupe,n)

  return $r
}

proc Lookup_Dupe_Stub { band sent call recd } {
  global windows stuff lookup

  set call [ string toupper $call ]

  # the database entry will be filed by the raw callsign
  set call [ Drop_Slash "rover" $call ]

  if { $::setting(rules) == "dist" || $::setting(rules) == "grid6" } {
    set gridend 5
    if { [ string length $sent ] < 6 } {
      set sent [ string range $sent 0 3 ]
      set sent "${sent}MM"
    }
    if { [ string length $recd ] < 6 } {
      set recd [ string range $recd 0 3 ]
      set recd "${recd}MM"
    }
  } else {
    set gridend 3
  }

  # the database entry will be filed by either four- or six-digit grids
  set s [ string toupper [ string range $sent 0 $gridend ] ]
  set r [ string toupper [ string range $recd 0 $gridend ] ]

  # set the string to look for
  set call "$call-$r,$s"
  Debug "Lookup_Dupe" "Looking for $call"
  set found 0

  # smarter way to do this instead of using the "handle" method.
  if { [ info exists lookup($call) ] } {
    set found 1
    set index $call
  }

  # We are just checking to see if there's been a QSO with this
  # guy from here to there on the current band.

  if { $found == 1 } {
    if { [ string first $band $lookup($index) ] < 0 } {
      # got the guy, but not on this band
      Debug "Lookup_Dupe" "Got the guy, but not on this band"
      return 0
    } else {
      # got the guy on this band
      Debug "Lookup_Dupe" "Got the guy on this band"
      return 1
    }
  } else {
    # haven't worked this combination at all
    Debug "Lookup_Dupe" "haven't worked this combination at all"
    return 0
  }
}

#
# Lookup_Recd - procedure to search the lookup recd database for the
#               remote station's last known grid.
# 
# Note        - if ::setting(lookupgrid) is zero, this only looks for
#               stations WE'VE worked instead of ones from the lookupgrid
#               database.
#

proc Lookup_Recd { action } {
  global windows stuff lookupgrid lookuprecd

  set call [ string trim [ string toupper $stuff(call) ] ]
  set call [ Drop_Slash "first" $call ]

  switch -exact -- $action {
  "lock" {
    set stuff(lookup_recd_state) "locked"
    return
  }
  "unlock" {
    set stuff(lookup_recd_state) "unlocked"
    return
  }
  "query" {
    if { $stuff(lookup_recd_state) == "locked" } {
      return
    }
  }
  default {
  }
  }

  set found 0

  if { $::setting(lookupgrid) == 1 } {
    if { [ info exists lookupgrid($call) ] } {
      set stuff(recd) [ lindex $lookupgrid($call) end ]
      set found 1
    }
  } else {
    if { [ info exists lookuprecd($call) ] } {
      set stuff(recd) [ lindex $lookuprecd($call) end ]
      set found 1
    }
  }

  if { $found == 1 } {
    Bear_Calc $stuff(sent) $stuff(recd)
    Annunciate "Grid Found"
  }
}

#
#  Rover_Call - procedure to look up a callsign in the lookup database and see
#               if it already appears in a different grid.
#

proc Rover_Call { } {
  global stuff windows lookup lookuprecd

  set stuff(call) [ string toupper $stuff(call) ]

  # if the call is already a Rover call, do not worry about it
  if { [ string last "/R" $stuff(call) ] > 0 } {
    return 0
  }

  Debug "Rover_Call" "no /R in $stuff(call), proceeding"

  set found 0

  set recd $stuff(recd)

  if { $::setting(rules) == "dist" || $::setting(rules) == "grid6" } {
    set gridend 5
    if { [ string length $recd ] < 6 } {
      set recd [ string range $recd 0 3 ]
      set recd "${recd}MM"
    }
  } else {
    set gridend 3
  }

  set recd [ string range [ string toupper $recd ] 0 $gridend ]

  set call [ Drop_Slash "first" $stuff(call) ]

  Debug "Rover_Call" "Checking $stuff(call) in $recd"

  if { [ info exists lookuprecd($call) ] } {
    Debug "Rover_Call" "Worked this guy before."
    set foundrecd [ lindex $lookuprecd($call) end ]

    if { [ string range $foundrecd 0 $gridend ] != [ string range $recd 0 $gridend ] } {
      Debug "Rover_Call" "Not in this grid!"
      set found 1
    }

  } else {
    Debug "Rover_Call" "Don't have a record of working this guy before."
  }

  if { $found == 1 } {
    set conf [ tk_dialog .rcd "Confirm Rover" \
"$stuff(call) has previously been logged in a different grid. Please select an option below." \
warning 0 "Log as Rover in $recd" "Log as is in $recd" "Log as non-rover in $foundrecd" "Do Not Log" ]
    if { $conf == 3 } {
      return 1
    }
    if { $conf == 0 } {
      set stuff(call) "$stuff(call)/R"
    }
    if { $conf == 2 } {
      set stuff(recd) $foundrecd
    }
  }
  return 0
}

#
# Edit_Notes - procedure to copy the selected notes to the note edit entry.
#

proc Edit_Notes { } {
  global windows stuff lookupnotes

  set lineno [$windows(lookuplist) index active] 
  set line [$windows(lookuplist) get $lineno]
  if { [ binary scan $line "a6" call ] == 1 } {
    set call [ string trim $call ]
    if { [ info exists lookupnotes($call) ] } {
      set stuff(editnotes) $lookupnotes($call)
    } else {
      set stuff(editnotes) ""
    }
  }
}

#
# Save_Notes - procedure to copy the note edit entry to the selected notes.
#

proc Save_Notes { } {
  global windows stuff lookupnotes

  set lineno [$windows(lookuplist) index active] 
  set line [$windows(lookuplist) get $lineno]
  if { [ binary scan $line "a6" call ] == 1 } {
    set call [ string trim $call ]
    set lookupnotes($call) $stuff(editnotes)
    Do_Lookup "partial" $stuff(call) $stuff(recd) $stuff(sent)
    Save_Lookup
  }
}


#
# Copy_Lookup - Procedure to copy the selected call and grid to the
#                entry fields.
#

proc Copy_Lookup { rover } {
  global windows stuff lookupgrid

  set lineno [$windows(lookuplist) index active] 
  set line [$windows(lookuplist) get $lineno]
  set found 0
  if { [ binary scan $line "a6x1a4" call recd ] == 2 } {

    # fix up
    set recd [ string trim $recd ]
    set call [ string trim $call ]

    # set received grid
    if { [ info exist lookupgrid($call) ] } {
      set i [ lsearch -glob $lookupgrid($call) "${recd}*" ]
      if { $i >= 0 } {
        set stuff(recd) [ lindex $lookupgrid($call) $i ]
        set found 1
      }
    }
    if { $found == 0 } {
      set stuff(recd) $recd
    }

    # set callsign
    if { $rover == "rover" } {
      set stuff(call) "${call}/R"
    } else {
      set stuff(call) $call
    }
  }

  focus $windows(callentry)
  $windows(callentry) icursor end
  $windows(callentry) select range 0 end

  if { $::setting(quicklookup) == 1 } {
    wm withdraw $windows(lookup)
  }
}

#
# Build_Comms
#

proc Build_Comms { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "Communications Status"
  wm protocol $f WM_DELETE_WINDOW { wm withdraw $windows(comms) }
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    catch { wm iconbitmap $f log.ico }
  }

  frame $f.f0 -relief raised -borderwidth 2

  label $f.f0.lservice -text "Module"
  label $f.f0.lstatus -text "Status"
  label $f.f0.ltime -text "Last Update"
  label $f.f0.lactions -text "Actions"
  grid $f.f0.lservice $f.f0.lstatus $f.f0.ltime $f.f0.lactions - - - -padx 2 -pady 2
  grid $f.f0.lservice -sticky nes

  label $f.f0.lkeyer  -text "Keyer"
  entry $f.f0.ekeyers -textvariable stuff(keyerstatus) -state readonly -width 10
  entry $f.f0.ekeyert -textvariable stuff(keyertime) -state readonly -width 20
  button $f.f0.bokeyer -text "O" -command "Open_Keyer"
  button $f.f0.bckeyer -text "C" -command "Close_Keyer noquit"
  button $f.f0.bbkeyer -text "B" -command "Blacklist keyer forced"
  button $f.f0.bukeyer -text "U" -command "Unblacklist keyer"
  grid $f.f0.lkeyer $f.f0.ekeyers $f.f0.ekeyert $f.f0.bokeyer $f.f0.bckeyer $f.f0.bbkeyer $f.f0.bukeyer -padx 2 -pady 2
  grid $f.f0.lkeyer -sticky nes

  label $f.f0.lsuper  -text "Super"
  entry $f.f0.esupers -textvariable stuff(superstatus) -state readonly -width 10
  entry $f.f0.esupert -textvariable stuff(supertime) -state readonly -width 20
  button $f.f0.bosuper -text "O" -command "Open_Super"
  button $f.f0.bcsuper -text "C" -command "Close_Super noquit"
  button $f.f0.bbsuper -text "B" -command "Blacklist super forced"
  button $f.f0.busuper -text "U" -command "Unblacklist super"
  grid $f.f0.lsuper $f.f0.esupers $f.f0.esupert $f.f0.bosuper $f.f0.bcsuper $f.f0.bbsuper $f.f0.busuper -padx 2 -pady 2
  grid $f.f0.lsuper -sticky nes

  label $f.f0.lrotor  -text "Rotor"
  entry $f.f0.erotors -textvariable stuff(rotorstatus) -state readonly -width 10
  entry $f.f0.erotort -textvariable stuff(rotortime) -state readonly -width 20
  button $f.f0.borotor -text "O" -command "Open_Rotor"
  button $f.f0.bcrotor -text "C" -command "Close_Rotor noquit"
  button $f.f0.bbrotor -text "B" -command "Blacklist rotor forced"
  button $f.f0.burotor -text "U" -command "Unblacklist rotor"
  grid $f.f0.lrotor $f.f0.erotors $f.f0.erotort $f.f0.borotor $f.f0.bcrotor $f.f0.bbrotor $f.f0.burotor -padx 2 -pady 2
  grid $f.f0.lrotor -sticky nes

  label $f.f0.lgps    -text "GPS"
  entry $f.f0.egpss   -textvariable stuff(gpsstatus) -state readonly -width 10
  entry $f.f0.egpst   -textvariable stuff(gpstime) -state readonly -width 20
  button $f.f0.bogps -text "O" -command "Open_GPS"
  button $f.f0.bcgps -text "C" -command "Close_GPS noquit"
  button $f.f0.bbgps -text "B" -command "Blacklist gps forced"
  button $f.f0.bugps -text "U" -command "Unblacklist gps"
  grid $f.f0.lgps $f.f0.egpss $f.f0.egpst $f.f0.bogps $f.f0.bcgps $f.f0.bbgps $f.f0.bugps -padx 2 -pady 2
  grid $f.f0.lgps -sticky nes

  for { set i 1 } { $i < 13 } { incr i } {
    set peername [ lindex $::setting(p$i) 0 ]
    label $f.f0.lp$i -text "Peer $peername"
    entry $f.f0.eps$i -textvariable stuff(peerstatus$i) -state readonly -width 10
    entry $f.f0.ept$i -textvariable stuff(peertime$i) -state readonly -width 20
    button $f.f0.bop$i -text "O" -command "Open_Peer $i"
    button $f.f0.bcp$i -text "C" -command "Close_Peer noquit $i"
    button $f.f0.bbp$i -text "B" -command "Blacklist p$i forced"
    button $f.f0.bup$i -text "U" -command "Unblacklist p$i"
    grid $f.f0.lp$i $f.f0.eps$i $f.f0.ept$i $f.f0.bop$i $f.f0.bcp$i $f.f0.bbp$i $f.f0.bup$i -padx 2 -pady 2
    grid $f.f0.lp$i -sticky nes
  }

  frame $f.f2 -relief raised -borderwidth 2
  label $f.f2.lservice -text "Module"
  label $f.f2.lstatus -text "Status"
  label $f.f2.ltime -text "Last Update"
  label $f.f2.lactions -text "Actions"
  grid $f.f2.lservice $f.f2.lstatus $f.f2.ltime $f.f2.lactions - - -
  grid $f.f2.lservice -sticky nes

  for { set i 1 } { $i < 18 } { incr i } {
    set band [ lindex $::setting(r$i) 0 ]
    label $f.f2.lr$i -text "Band $band"
    entry $f.f2.ers$i -textvariable stuff(bandstatus$i) -state readonly -width 10
    entry $f.f2.ert$i -textvariable stuff(bandtime$i) -state readonly -width 20
    button $f.f2.bor$i -text "O" -command "Open_Rig $i"
    button $f.f2.bcr$i -text "C" -command "Close_Rig noquit $i"
    button $f.f2.bbr$i -text "B" -command "Blacklist r$i forced"
    button $f.f2.bur$i -text "U" -command "Unblacklist r$i"
    grid $f.f2.lr$i $f.f2.ers$i $f.f2.ert$i $f.f2.bor$i $f.f2.bcr$i $f.f2.bbr$i $f.f2.bur$i -padx 2 -pady 2
    grid $f.f2.lr$i -sticky nes
  }

  grid $f.f0 $f.f2 -sticky news

  wm resizable $f 0 0
  update idletasks

  return $f
}

#
# Popup_Comms - procedure to bring up the comms window.
#

proc Popup_Comms { } {
  global windows stuff
  
  wm deiconify $windows(comms)
  raise $windows(comms)
}

#
# Build_Info
#

proc Build_Info { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "Station Info"
  wm protocol $f WM_DELETE_WINDOW { wm withdraw $windows(info) }
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    catch { wm iconbitmap $f log.ico }
  }

  frame $f.f0 -relief raised -borderwidth 2
  label $f.f0.lmi -text "My Information" -font { systemfont 8 bold }

  set windows(stabandmenubut) [ menubutton $f.f0.mb -text Band -menu \
    $f.f0.mb.menu -relief raised ]
  if { $::setting(bandlock) == 1 } { $windows(stabandmenubut) configure \
    -state disabled }
  set windows(stabandentry) [ entry $f.f0.eb -state readonly -font \
    $::setting(bigfont) -textvariable stuff(band) -width 6 \
    -readonlybackground lightyellow ]

  set windows(stabandmenu) [menu $f.f0.mb.menu -tearoff 0]
  foreach b $::setting(bands) {
    $windows(stabandmenu) add radio -label $b -variable stuff(band) -value $b \
      -command { Redraw_Map_Band ; Recall_Op_Freq ; Set_Freq exec }
  }

  label $f.f0.lr -text "Op Frequency"
  radiobutton $f.f0.rbre -text "From Rig Server" -variable stuff(rigctrl) \
    -value 1 -state disabled
  radiobutton $f.f0.rbrd -text "Manual" -variable stuff(rigctrl) -value 0 \
    -state disabled

  label $f.f0.llo -text "LO Freq (MHz)"
  set windows(lofreqentry) [ entry $f.f0.elo -textvariable stuff(lofreq) \
    -width 12 -background yellow -font $::setting(entryfont) ]

  set windows(rigfreqbutton) [ button $f.f0.brf -text "Rig Freq (MHz)" \
    -command { if { $stuff(rigctrl) } { \
      Unblacklist "r[Band_Number $stuff(band)]" } } ]
  set windows(rigfreqentry) [ entry $f.f0.erf -textvariable stuff(rigfreq) \
    -state readonly -width 12 -font $::setting(entryfont) ]

  label $f.f0.lmf -text "Op Freq (MHz)"
  set windows(opfreqentry) [ entry $f.f0.emf -textvariable stuff(opfreq) \
    -width 12 -background yellow -font $::setting(entryfont) ]

  # If we are using rig control for this band...
  if { $stuff(rigctrl) != 0 } {

    # Set the frequency display field attributes.
    $windows(lofreqentry) configure -state normal
    $windows(rigfreqentry) configure -state readonly
    $windows(opfreqentry) configure -state readonly

  # Otherwise we are using manual entry.
  } else {

    # Set the frequency display field attributes.
    $windows(lofreqentry) configure -state disabled
    $windows(rigfreqentry) configure -state disabled
    $windows(opfreqentry) configure -state normal
  }

  grid $f.f0.lmi   -          -padx 2 -pady 2 -sticky news
  grid $f.f0.mb    $f.f0.eb   -padx 2 -pady 2 -sticky news
  grid $f.f0.lr    $f.f0.rbre -padx 2 -pady 2 -sticky news
  grid x           $f.f0.rbrd -padx 2 -pady 2 -sticky news
  grid $f.f0.llo   $f.f0.elo  -padx 2 -pady 2 -sticky news
  grid $f.f0.brf   $f.f0.erf  -padx 2 -pady 2 -sticky news
  grid $f.f0.lmf   $f.f0.emf  -padx 2 -pady 2 -sticky news

  grid $f.f0.mb -sticky e
  grid $f.f0.eb -sticky w
  grid $f.f0.lr -sticky e
  grid $f.f0.rbre -sticky w
  grid $f.f0.rbrd -sticky w
  grid $f.f0.llo -sticky e
  grid $f.f0.elo -sticky w
  grid $f.f0.erf -sticky w
  grid $f.f0.lmf -sticky e
  grid $f.f0.emf -sticky w

  frame $f.f1 -relief raised -borderwidth 2

  label $f.f1.lpi -text "Peer Information" -font { systemfont 8 bold }
  label $f.f1.lpa -text "Pass"
  label $f.f1.lf  -text "Freq"
  label $f.f1.ls  -text "Stat"
  label $f.f1.lw  -text "WIP"
  label $f.f1.ll  -text "Limit"
  label $f.f1.lb  -text "Busy"

  grid $f.f1.lpi -        -        -        -        \
    -padx 2 -pady 2 -sticky news
  grid $f.f1.lpa $f.f1.lf $f.f1.ls $f.f1.lw $f.f1.ll $f.f1.lb \
    -padx 2 -pady 2 -sticky news

  for { set i 1 } { $i < 13 } { incr i } {
    set peername [ lindex $::setting(p$i) 0 ]
    if { $peername == $::setting(mypeername) } { 
      label $f.f1.lp$i -text $peername
      set windows(myopfreqentry) [ entry $f.f1.ef$i -textvariable \
        stuff(opfreq) -width 12 -font $::setting(entryfont) ]
      entry $f.f1.es$i -textvariable stuff(stat) -width 14 -state readonly \
        -font $::setting(entryfont)
      entry $f.f1.ew$i -textvariable stuff(wip) -width 4 -state readonly \
        -font $::setting(entryfont)
      entry $f.f1.el$i -textvariable ::setting(wiplimit) -width 4 \
        -font $::setting(entryfont)
      entry $f.f1.eb$i -textvariable stuff(busy) -width 4 -state readonly \
        -font $::setting(entryfont)

    grid $f.f1.lp$i $f.f1.ef$i $f.f1.es$i $f.f1.ew$i $f.f1.el$i $f.f1.eb$i \
      -padx 2 -pady 2 -sticky news

    grid $f.f1.ef$i -sticky w
    grid $f.f1.es$i -sticky w
    grid $f.f1.ew$i -sticky w
    grid $f.f1.el$i -sticky w
    grid $f.f1.eb$i -sticky w
    } else {
      set windows(peerbutton$i) [ button $f.f1.bpass$i -text $peername -command \
        "set stuff(skedpeer) $peername ; Peerbutton nokeep" ]
      entry $f.f1.ef$i -textvariable stuff(peerfreq$i) -width 12 \
        -state readonly -font $::setting(entryfont)
      entry $f.f1.es$i -textvariable stuff(peerstat$i) -width 14 \
        -state readonly -font $::setting(entryfont)
      entry $f.f1.ew$i -textvariable stuff($peername,wip) -width 4 \
        -state readonly -font $::setting(entryfont)
      entry $f.f1.el$i -textvariable stuff($peername,wiplimit) -width 4 \
        -state readonly -font $::setting(entryfont)
      entry $f.f1.eb$i -textvariable stuff($peername,busy) -width 4 \
        -state readonly -font $::setting(entryfont)

    grid $f.f1.bpass$i $f.f1.ef$i $f.f1.es$i $f.f1.ew$i $f.f1.el$i $f.f1.eb$i \
      -padx 2 -pady 2 -sticky news

    grid $f.f1.ef$i -sticky w
    grid $f.f1.es$i -sticky w
    grid $f.f1.ew$i -sticky w
    grid $f.f1.el$i -sticky w
    grid $f.f1.eb$i -sticky w
    }
  }

  grid $f.f0 -sticky news
  grid $f.f1 -sticky news

  wm resizable $f 0 0
  update idletasks

  return $f
}

#
# Popup_Info - procedure to bring up the freq window.
#

proc Popup_Info { } {
  global windows stuff
  
  wm deiconify $windows(info)
  raise $windows(info)
}

#
# Build_Lookup
#

proc Build_Lookup { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "Callsign Lookup"
  wm protocol $f WM_DELETE_WINDOW { wm withdraw $windows(lookup) }
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    catch { wm iconbitmap $f log.ico }
  }

  frame $f.f0

  set width [ expr [ llength $::setting(bands) ] * 2 + 19 + 16 ]

  set windows(lookupkey) [ \
    listbox $f.k -font $::setting(font) -width $width -height 3 \
      -fg black -bg white ]

  set linetoadd "X = Wkd, ! = Pass!"
  foreach b $::setting(bands) {
    if { [ string length $b ] < 3 } {
      set linetoadd "$linetoadd  "
    } else {
      set t [ string index $b 0 ]
      set linetoadd "$linetoadd $t"
    }
  }
  $f.k insert end $linetoadd
  set linetoadd ". = No Data       "
  foreach b $::setting(bands) {
    if { [ string length $b ] < 3 } {
      set t [ string index $b 0 ]
    } else {
      set t [ string index $b 1 ]
    }
    set linetoadd "$linetoadd $t"
  }
  $f.k insert end $linetoadd
  set linetoadd "CALL   RECD (SENT)"
  foreach b $::setting(bands) {
    if { [ string length $b ] < 3 } {
      set t [ string index $b 1 ]
    } else {
      set t [ string index $b 2 ]
    }
    set linetoadd "$linetoadd $t"
  }
  set linetoadd "$linetoadd Notes"
  $f.k insert end $linetoadd
    
  set windows(lookuplist) [ \
    listbox $f.l -font $::setting(font) -width $width -height 6 \
      -fg black -bg white \
      -yscrollcommand [list $f.yscroll set]]
  scrollbar $f.yscroll -orient vertical -command [list $f.l yview]

  grid $f.k x          -sticky news -padx 2 -pady 2
  grid $f.l $f.yscroll -sticky news -padx 2 -pady 2

  grid rowconfigure $f 0 -weight 0
  grid rowconfigure $f 1 -weight 1

  frame $f.f1

  button $f.f1.bcopy -text "Copy to Entry" -relief raised \
    -command { Copy_Lookup "non-rover" } -background pink
  button $f.f1.bcopyr -text "Copy to Entry as Rover" -relief raised \
    -underline 17 -command { Copy_Lookup "rover" }
  button $f.f1.bedit -text "Edit Notes" -relief raised \
    -underline 0 -command { Edit_Notes }
  entry $f.f1.enotes -textvariable stuff(editnotes) -background yellow
  button $f.f1.bsave -text "Save Notes" -relief raised \
    -underline 0 -command { Save_Notes }

  grid $f.f1.bcopy $f.f1.bcopyr $f.f1.bedit $f.f1.enotes $f.f1.bsave \
    -sticky news -padx 2 -pady 2

  grid $f.f0 -sticky news
  grid $f.f1 -sticky news

  wm resizable $f 0 1
  update idletasks

  return $f
}

#
# Popup_Lookup
#

proc Popup_Lookup { m } {
  global windows stuff

  # do windows stuff
  wm deiconify $windows(lookup)
  raise $windows(lookup)

  # decide what type of lookup to do
  if { $m == "buds" } {
    Do_Buds_Lookup
  } else {
    Do_Lookup $m $stuff(call) $stuff(recd) $stuff(sent)
  }

  focus $windows(lookuplist)
  $windows(lookuplist) activate 0
  $windows(lookuplist) selection clear 0 end
  $windows(lookuplist) selection set 0
}

#
# Do_Buds_Lookup
#

proc Do_Buds_Lookup { } {
  global stuff windows

  $windows(lookuplist) delete 0 end
  foreach b $::setting(buds) {
    Do_Lookup "buds" $b "" $stuff(sent)
  }
}

proc Web_Lookup { } {
  global stuff

  set call [ Drop_Slash "first" [ string toupper [ string trim $stuff(call) ] ] ]

  switch -exact -- $::setting(weblookup) {
  "Buckmaster" {
    eval exec [auto_execok start] [list "http://hamcall.net/call?callsign=$call"] &
  }
  "AE7Q" {
    eval exec [auto_execok start] [list "http://www.ae7q.com/query/data/CallHistory.php?CALL=$call"] &
  }
  "Hamdata" {
    eval exec [auto_execok start] [list "http://hamdata.com/getcall.html?callsign=$call"] &
  }
  default {
    eval exec [auto_execok start] [list "http://www.qrz.com/db/$call"] &
  }
  }
}

#
# Open_Super
#

proc Open_Super { } {
  global stuff

  # open connection to super lookup server
  if [catch {socket -async $::setting(superipaddr) $::setting(superipport)} stuff(supersid) ] {
    Blacklist "super" "connection failed"
    return
  }

  # set up the descriptor
  if [ catch { fconfigure $stuff(supersid) -buffering line -blocking 0 } ] {
    Blacklist "super" "configuration failed"
    return
  }

  set stuff(superstatus) "Open"
  set stuff(supertime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]

}

proc Close_Super { quit } {
  global stuff

  if { [ info exist stuff(supersid) ] } {
    catch { fconfigure $stuff(supersid) -blocking 1 }
    if { $quit == "quit" } {
      catch { puts $stuff(supersid) "quit!" }
    }
    catch { close $stuff(supersid) }
    catch { unset stuff(supersid) }
  }

  set stuff(superstatus) "Closed"
  set stuff(supertime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
}

#
# Super_Puts - Replacement puts for sending to the Super Lookup server with
# error detection and blacklisting if merited.
#

proc Super_Puts { m } {
  global stuff

  # skip if not configured
  if { $::setting(superipport) == 0 } {
    return
  }

  # skip if blacklisted
  if { $stuff(blacklist,super) == 1 } {
    return
  }

  Debug "Super_Puts" "Sending $m"

  if { [ catch { puts $stuff(supersid) $m } r ] } {
    Blacklist "super" "puts failed: $r"
  }

  # flush $stuff(supersid)

  set stuff(superstatus) "Sent Ok"
  set stuff(supertime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
}

#
# Super_Gets - Replacement gets for getting from the Super Lookup server with
# error detection and blacklisting if merited.
#

proc Super_Gets { } {
  global stuff

  # skip if not configured
  if { $::setting(superipport) == 0 } {
    return "error"
  }

  # skip if blacklisted
  if { $stuff(blacklist,super) == 1 } {
    return "error"
  }

  if { [ catch { gets $stuff(supersid) } m ] } {
    Blacklist "super" "gets failed"
    return "error"
  }
  Debug "Super_Gets" "Received $m"

  set stuff(superstatus) "$m"
  set stuff(supertime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]

  return $m
}

proc Super_Lookup { } {
  global windows stuff

  Debug "Super_Lookup" ""

  # This is how the Super Lookup server is unblacklisted.
  Unblacklist "super"

  set call [ Drop_Slash "first" $stuff(call) ]
  
  # send query
  if { $::setting(lookupquiet) == 1 } {
    Super_Puts "lookup $call"
  } else {
    Super_Puts "lookup! $call"
  }

  # get response and continue
  if { $::setting(lookupquiet) != 1 } {

    $windows(lookuplist) delete 0 end
    wm title $windows(lookup) "Super Lookup Results"

    set error 0
    while { [ set mt [ Super_Gets ] ] != "done" } {
      Debug "Super_Lookup" "response $mt"

      if { $mt == "" } {
        # This delay was recommended by Bob Fries to prevent a race condition
        after 100
        continue
      }

      if { $mt == "error" } {
        tk_messageBox -icon error -type ok \
          -title "Super Lookup Error" -message \
          "Cannot contact Super Lookup server.\nDid you start it?"
        set error 1
	break
      }

      if { $mt == "none" } {
        tk_messageBox -icon info -type ok \
          -title "Super Lookup Response" -message \
          "$stuff(call) not found in database."
	set error 1
        break
      }

      binary scan $mt "a8x1a20x1a6x1a9x1a10x1" index call grid lat lon

      set p [ expr 56 + 10 * 2 ]
      set bands [ string range $mt 58 $p ]

      incr p 2
      set notes [ string range $mt $p end ]

      set sent ""

      set linetoadd [ format "%-6.6s %-4.4s (%-4.4s) %s %s" \
        $call $grid $sent $bands $notes ]

      $windows(lookuplist) insert end $linetoadd
    }

    if { $error == 0 } {
      wm deiconify $windows(lookup)
      raise $windows(lookup)
      $windows(lookuplist) see 0
    }
  }

  return
}

#
# What_Bands - paint the Pass windows based upon what bands we know this guy has
#

proc What_Bands { } {
  global stuff lookup lookupband windows

  set call [ Drop_Slash "rover" [ string toupper [ string trim $stuff(skedcall) ] ] ]

  set recd [ string toupper $stuff(skedrecd) ]
  set sent [ string toupper $stuff(sent) ]

  if { $::setting(rules) == "dist" || $::setting(rules) == "grid6" } {
    set gridend 5
    if { [ string length $sent ] < 6 } {
      set sent [ string range $sent 0 3 ]
      set sent "${sent}MM"
    }
    if { [ string length $recd ] < 6 } {
      set recd [ string range $recd 0 3 ]
      set recd "${recd}MM"
    }
  } else {
    set gridend 3
  }

  set i 0
  foreach b $::setting(bands) {
    if { [ info exists lookup(${call}-${recd},${sent}) ] &&
      [ lsearch -exact $lookup(${call}-${recd},${sent}) $b ] >= 0 } {
      # worked
      Debug "What_Bands" "Worked $call on $b"
      set stuff(passhas$b) 1
      $windows(passhascb$i) configure -foreground black
    } else {
      # not worked
      if { [ info exists lookupband($call) ] &&
        [ lsearch -exact $lookupband($call) $b ] >= 0 } {
        Debug "What_Bands" "Need $call on $b"
        set stuff(passhas$b) 1
        # light up the band label
        $windows(passhascb$i) configure -foreground red
      } else {
        Debug "What_Bands" "$call doesn't have $b"
        set stuff(passhas$b) 0
        # band label deemphasized
        $windows(passhascb$i) configure -foreground grey
      }
    }
    incr i
  }
}

#
# Do_Lookup
#

proc Do_Lookup { m call recd sent } {
  global windows stuff lookup lookupgrid lookupband lookupnotes

  if { [ wm state $windows(lookup) ] == "withdrawn" } { return }

  set stuff(lookuptype) $m

  # what call or fragment are we looking up?
  set call [ Drop_Slash "first" [ string toupper [ string trim $call ] ] ]

  set recd [ string toupper $recd ]
  set sent [ string toupper $sent ]

  if { $::setting(rules) == "dist" || $::setting(rules) == "grid6" } {
    set gridend 5
    if { [ string length $sent ] < 6 } {
      set sent [ string range $sent 0 3 ]
      set sent "${sent}MM"
    }
    if { [ string length $recd ] < 6 } {
      set recd [ string range $recd 0 3 ]
      set recd "${recd}MM"
    }
  } else {
    set gridend 3
  }

  # do not change the lookup if the call is empty or is too short
  if { [ string length "$call" ] < 2 } {
    Debug "Do_Lookup" "Runt call, not doing lookup."
    return
  }

  # wipe out the old contents unless we are doing multiple lookups (buds).
  if { $m != "buds" } {
    $windows(lookuplist) delete 0 end
  }

  # set wildcard fragment to search for
  if { $m == "lookup" } {
    # "lookup" mode - be strict about call, sent and recd.
    wm title $windows(lookup) "Callsign Lookup - Exact Call, Grid to Grid"
    set searchcall "${call}-${recd},${sent}"
  } elseif { $m == "buds" } {
    # "buds" mode - be strict about call and sent, but not recd.
    wm title $windows(lookup) "Buds Lookup - Exact Call, From This Grid"
    set searchcall "${call}-*,${sent}"
  } else {
    # "partial" mode - be lax about everything.
    wm title $windows(lookup) "Callsign Lookup - Partial Call, Any Grid"
    set searchcall "*$call*-*,*"
  }

  Debug "Do_Lookup" "Looking for $searchcall"

  set found 0

  if { [ info exists lookup ] } {

    Debug "Do_Lookup" "Starting lookup array search."

    # look through the lookup database
    for { set handle [ array startsearch lookup ]
      set index [ array nextelement lookup $handle ] } \
      { $index != "" } \
      { set index [ array nextelement lookup $handle ] } {

      # Debug "Do_Lookup" "Checking $searchcall vs. $index"

      # we have found a match
      if { [ string match $searchcall $index ] } {

        incr found

        # parse out callsign and grid
        set i [ string last "-" $index ]
        set j [ string last "," $index ]

        set foundcall [ string range $index 0 [ expr $i - 1 ] ]
        set foundrecd [ string range $index [ expr $i + 1 ] [ expr $j - 1 ] ]
        set foundsent [ string range $index [ expr $j + 1 ] end ]

        # temporary variable to block adding matches from the lookupgrid
        # database if already found.
        set foundpair($foundcall,$foundrecd) 1

        # make the band annunciator
        set bands ""
        foreach b $::setting(bands) {
          if { [ lsearch -exact $lookup($index) $b ] >= 0 } {
            # worked
            set t "X"
          } else {
            # not worked
            if { [ info exists lookupband($foundcall) ] &&
              [ lsearch -exact $lookupband($foundcall) $b ] >= 0 } {
              set t "!"
            } else {
              set t "."
            }
          }

          # append to running string
          set bands "$bands $t"
        }

        # add the line to the window
        if { [ info exists lookupnotes($foundcall) ] } {
          set linetoadd [format "%-6.6s %-4.4s (%-4.4s)%s %s" \
            $foundcall $foundrecd $foundsent $bands $lookupnotes($foundcall)]
        } else {
          set linetoadd [format "%-6.6s %-4.4s (%-4.4s)%s" \
            $foundcall $foundrecd $foundsent $bands]
        }

        # If this is an exact match, add a "@" to the beginning for sorting.
        # It will be removed after the sort.
        if { $foundcall == $call && $foundrecd == $recd && \
          $foundsent == $sent } {
          Debug "Do_Lookup" "Exact match $foundcall, $foundrecd, $foundsent."
          $windows(lookuplist) insert end "@$linetoadd"
        } else {
          Debug "Do_Lookup" "Partial match."
          $windows(lookuplist) insert end $linetoadd
        }
      }
    }
  }

  # Put in entries from the lookupgrid database as well.
  if { $m != "lookup" && [ info exists lookupgrid ] } {

    set searchcall "*$call*"

    Debug "Do_Lookup" "Starting lookupgrid array search."

    # look through the lookupgrid database
    for { set handle [ array startsearch lookupgrid ]
      set index [ array nextelement lookupgrid $handle ] } \
      { $index != "" } \
      { set index [ array nextelement lookupgrid $handle ] } {

      # Debug "Do_Lookup" "Checking $searchcall vs. $index"

      # we have found a match
      if { [ string match $searchcall $index ] } {

        # step through each grid for the call
        foreach c $lookupgrid($index) {
          
          # do not add to the list if already found in the lookup database.

          # TODO - Not sure we want to do allow full 6-digit grids here, but we'll
          # do it for now.
          if { $::setting(rules) == "dist" || $::setting(rules) == "grid6" } {
            set gridend 5
            if { [ string length $c ] < 6 } {
              set c [ string range $c 0 3 ]
              set c "${c}MM"
            }
          } else {
            set gridend 3
          }

          set shortrecd [ string range $c 0 $gridend ]
          Debug "Do_Lookup" "Checking for foundpair($index,$shortrecd)"
          if [ info exists foundpair($index,$shortrecd) ] {
            continue
          }

          Debug "Do_Lookup" \
            "Building band list for non-worked call $index"

          # make the band annunciator
          set bands ""

          foreach b $::setting(bands) {

            if { [ info exists lookupband($index) ] && \
              [ lsearch -exact $lookupband($index) $b ] >= 0 } {
              # reportedly has this band
              set t "!"
            } else {
              # reportedly does not have this band
              set t "."
            }

            # append to running string
            set bands "$bands $t"
          }

          # add the line to the window
          if { [ info exists lookupnotes($index) ] } {
            set linetoadd [ format "%-6.6s %-4.4s (%-4.4s)%s %s" \
              $index $c "    " $bands $lookupnotes($index) ]
          } else {
            set linetoadd [ format "%-6.6s %-4.4s (%-4.4s)%s" \
              $index $c "    " $bands ]
          }

          # We will not add a "@" to the beginning for sorting,
          # because this is the database of stuff not necessarily worked.
          Debug "Do_Lookup" "Lookup: partial match."
          $windows(lookuplist) insert end $linetoadd
        }
      }
    }
  }

  # sort the list
  set bunch [$windows(lookuplist) get 0 end]

  # An assumption in the actual sort is that "@" will bubble to the top.
  # This is to flag exact matches vs. non-matches for top list display.
  set newbunch [lsort $bunch]
  $windows(lookuplist) delete 0 end
  foreach line $newbunch {

    # check to see if this was an exact match, if so, remove the "@".
    if { [ string range $line 0 0 ] == "@" } {
      $windows(lookuplist) insert end [ string range $line 1 end ]
    } else {
      $windows(lookuplist) insert end $line
    }

  }

  # view the top of the list
  $windows(lookuplist) see 0
}

#
#  Build_Net - procedure to set up the Net window.
#

proc Build_Net { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "Net"
  wm protocol $f WM_DELETE_WINDOW { wm withdraw $windows(net) }
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    catch { wm iconbitmap $f log.ico }
  }

  frame $f.f0 -borderwidth 2 -relief raised
  label $f.f0.ln -text "Networking" -font { systemfont 8 bold }
  radiobutton $f.f0.rbne -text "Enabled" -variable ::setting(netenable) \
    -value 1 -command { set ::setting(netenable) 1 ; Net_Start }
  radiobutton $f.f0.rbnd -text "Disabled" -variable ::setting(netenable) \
    -value 0 -command { set ::setting(netenable) 0 ; Net_Start }

  grid $f.f0.ln   -          -sticky news -padx 1 -pady 1
  grid $f.f0.rbne $f.f0.rbnd -sticky news -padx 1 -pady 1

  frame $f.f1 -borderwidth 2 -relief raised
  label $f.f1.lwhere -text "Send To" -font { systemfont 8 bold }
  menubutton $f.f1.mPeer -text "Select Peer..." -menu $f.f1.mPeer.menu \
    -relief raised
  entry $f.f1.ePeer -textvariable stuff(peername) -width 16 -state readonly \
    -font $::setting(bigfont) -readonlybackground lightyellow
  set windows(netpeermenu) [menu $f.f1.mPeer.menu -tearoff 0]
  $windows(netpeermenu) add radio -label "all" -variable stuff(peername) \
    -value "all"
  for { set i 1 } { $i < 13 } { incr i } {
    set a [ lindex $::setting(p$i) 0 ]
    $windows(netpeermenu) add radio -label $a -variable stuff(peername) \
      -value $a
  }

  grid x           $f.f1.lwhere -sticky news -padx 1 -pady 1
  grid $f.f1.mPeer $f.f1.ePeer  -sticky news -padx 1 -pady 1

  # What to send
  frame $f.f4 -borderwidth 2 -relief raised
  label $f.f4.lwhat -text "Message" -font { systemfont 8 bold }
  set windows(netmsgentry) [ entry $f.f4.enetmsg -textvariable stuff(netmsg) \
    -width 44 -font $::setting(entryfont) -background yellow ]
  button $f.f4.bmsg -text "Send" -command { Net_Send "msg" \
    $stuff(peername) "$stuff(netmsg)" ; set stuff(netmsg) "" } \
    -background "pink"

  grid $f.f4.lwhat $f.f4.enetmsg $f.f4.bmsg \
    -sticky news -padx 2 -pady 2

  # build log area

  frame $f.f5 -borderwidth 2 -relief raised

  frame $f.f5.f0
  label $f.f5.f0.ll -text "Network Communication Log" -font \
    { systemfont 8 bold }
  label $f.f5.f0.lu -text "UTC Now"
  entry $f.f5.f0.eu -textvariable stuff(utc) -state readonly -width 6 \
    -font $::setting(bigfont)

  set windows(netmessages) [ text $f.f5.t -font $::setting(entryfont) \
    -width 48 -height $::setting(netlogheight) -yscrollcommand "$f.f5.sb set" ]
  $windows(netmessages) tag configure intag -font $::setting(bigfont)
  scrollbar $f.f5.sb -orient vert -command "$f.f5.t yview"
  grid $f.f5.f0.ll $f.f5.f0.lu $f.f5.f0.eu -padx 1 -pady 1 -sticky news
  pack $f.f5.f0
  pack $f.f5.sb -side right -fill y
  pack $f.f5.t -side left -fill both -expand true

  # TODO why don't the Net_Sends work?
  frame $f.f6
  button $f.f6.blog -text "Send Log" -command { Net_Send "log" \
    $stuff(peername) "" } -width 10
  button $f.f6.bskd -text "Send Skeds" -command { Net_Send "skd" \
    $stuff(peername) "" } -width 10
  grid $f.f6.blog $f.f6.bskd -padx 2 -pady 2
  
  grid $f.f0 $f.f1 -sticky news
  grid $f.f4 -     -sticky news
  grid $f.f5 -     -sticky news
  grid $f.f6 -     -sticky news

  grid rowconfigure $f 2 -weight 1

  wm resizable $f 0 1
  update idletasks

  return $f
}

#
#  Build_Debug
#

proc Build_Debug { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "Debug Log"
  wm protocol $f WM_DELETE_WINDOW { set stuff(debug) 0 ; Set_Title ; \
    wm withdraw $windows(debug) }
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    catch { wm iconbitmap $f log.ico }
  }

  set windows(debugtext) [ text $f.st \
   -width 80 -height 24 -yscrollcommand "$f.ssb set" ]
  scrollbar $f.ssb -orient vert -command "$f.st yview"
  pack $f.ssb -side right -fill y
  pack $f.st -side left -fill both -expand true

  wm resizable $f 0 0
  update idletasks

  return $f
}

#
#  Build_Hist
#

proc Build_Hist { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "History"
  wm protocol $f WM_DELETE_WINDOW { wm withdraw $windows(hist) }
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    catch { wm iconbitmap $f log.ico }
  }

  set windows(infotext) [ text $f.st \
   -width 80 -height 24 -yscrollcommand "$f.ssb set" ]
  scrollbar $f.ssb -orient vert -command "$f.st yview"
  pack $f.ssb -side right -fill y
  pack $f.st -side left -fill both -expand true

  wm resizable $f 0 0
  update idletasks

  return $f
}

proc Save_Settings { } {

  set fid [ open "roverlog.ini" w 0666 ]

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

  tk_messageBox -icon info -type ok -title "Settings saved" \
    -message "RoverLog settings saved to roverlog.ini."
}

#
#  Build_Loghead - procedure to set up the Cabrillo Log Header window.
#

proc Build_Loghead { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "Log Header"
  wm protocol $f WM_DELETE_WINDOW { Save File ; wm withdraw $windows(loghead) }
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    catch { wm iconbitmap $f log.ico }
  }

  frame $f.f1
  set windows(logheadtext) [ text $f.f1.st -font $::setting(font) \
   -width 50 -height 16 -yscrollcommand "$f.f1.ssb set" ]
  scrollbar $f.f1.ssb -orient vert -command "$f.f1.st yview"
  pack $f.f1.ssb -side right -fill y
  pack $f.f1.st -side left -fill both -expand true

  frame $f.f2
  button $f.f2.bc -text "Commit" -command { Save File ; wm withdraw $windows(loghead) }
  pack $f.f2.bc

  pack $f.f1
  pack $f.f2

  wm resizable $f 0 0
  update idletasks

  return $f
}

#
# Save_Lookup - procedure to dump the lookupgrid database to a file.
#

proc Save_Lookup { } {
  global lookupgrid stuff lookupband lookupnotes

  if { [ info exist lookupgrid ] } {
    set fid [ open $::setting(lookupfile) w 0666 ]
    for { set handle [ array startsearch lookupgrid ]
      set index [ array nextelement lookupgrid $handle ] } \
        { $index != "" } \
        { set index [ array nextelement lookupgrid $handle ] } {

      # Debug "Save_Lookup" "Checking for lookupband($index)"
      if { [ info exists lookupband($index) ] } {
        set t " $lookupband($index)"
        # Debug "Save_Lookup" "Found lookupband($index):$t"
      } else {
        # Debug "Save_Lookup" "Did not find lookupband($index)"
        set t ""
      }
      # Debug "Save_Lookup" "Checking for lookupnotes($index)"
      if { [ info exists lookupnotes($index) ] } {
        set u " $lookupnotes($index)"
        # Debug "Save_Lookup" "Found lookupnotes($index):$u"
      } else {
        set u ""
        # Debug "Save_Lookup" "Did not find lookupnotes($index)"
      }
      set line [ format "LUP: %-6.6s %s%s%s" $index $lookupgrid($index) $t $u]
      puts $fid "$line"
    }
    close $fid
  }
}

proc Process_LUP_Line { overwrite line } {
  global lookupgrid lookupband lookupnotes

  # If this is a valid lookup line...
  if { [ string equal -length 5 $line "LUP: " ] == 1 } {

    # Parse out the line.
    set call [ string toupper [ string trim [ string range $line 5 10 ] ] ]
    Debug "Process_LUP_Line" "Call $call"
    set rest [ string range $line 12 end ]

    # Every time we get a new line for this call, we overwrite. Scary.
    if { $overwrite == "overwrite" } {
      set lookupgrid($call) {}
      set lookupband($call) {}
      set lookupnotes($call) {}
    }

    # step through each of the remaining fields
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

        Debug "Process_LUP_Line" "$call Grid $b"
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

        Debug "Process_LUP_Line" "$call Band $b"
        continue
      }

      # otherwise, this must be notes
      if { [ info exists lookupnotes($call) ] } {
        if { [ lsearch -exact $lookupnotes($call) $b ] < 0 } {
          lappend lookupnotes($call) $b
        }
      } else {
        set lookupnotes($call) "$b"
      }

    }
  }
}

#
# Load_Lookup - procedure to load in the lookupgrid database.
#

proc Load_Lookup { } {

  # open the file and step through each line
  if { [file readable $::setting(lookupfile)] } {
    set fid [open $::setting(lookupfile) r]
    while { [gets $fid line] >= 0 } {
      Process_LUP_Line "append" "$line"
    }
    close $fid
  }
}

#
# Create_Compass - makes a compass that can display a direction.
#

proc Create_Compass { w { width 145 } { height 110 } { radius 30 } } {

  set xcenter [ expr $width / 2 ]
  set ycenter [ expr $height / 2 + 10 ]

  canvas $w -width $width -height $height

  $w create line $xcenter [ expr $ycenter - $radius ] \
    $xcenter [ expr $ycenter - $radius - 20 ] -arrow last \
    -arrowshape { 10 10 5 } -width 9 -fill "red"

  set xmin [ expr $xcenter - $radius ]
  set ymin [ expr $ycenter - $radius ]
  set xmax [ expr $xcenter + $radius ]
  set ymax [ expr $ycenter + $radius ]
  $w create oval $xmin $ymin $xmax $ymax -fill white -width 1

  set merid [ $w create line $xcenter [ expr $ycenter + $radius - 2 ] \
    $xcenter [ expr $ycenter - $radius + 2 ] -width 1 -fill black ]
  set npointer [ $w create line $xcenter $ycenter \
    $xcenter [ expr $ycenter - $radius + 5 ] -arrow last -arrowshape \
    { 10 10 5 } -width 9 -fill "red" ]
  set spointer [ $w create line $xcenter $ycenter \
    $xcenter [ expr $ycenter + $radius - 5 ] -width 9 -fill "black" ]
  $w create oval [ expr $xcenter - 2 ] [ expr $ycenter - 2 ] \
    [ expr $xcenter + 2 ] [ expr $ycenter + 2 ] -fill white

  set north [ $w create text $xcenter [ expr $ycenter - $radius - 10 ] -text N ]
  set east  [ $w create text [ expr $xcenter - $radius - 10 ] $ycenter -text E ]
  set west  [ $w create text [ expr $xcenter + $radius + 10 ] $ycenter -text W ]
  set south [ $w create text $xcenter [ expr $ycenter + $radius + 10 ] -text S ]

  # save compass information in a state variable
  global Compass
  set Compass(xcenter) $xcenter
  set Compass(ycenter) $ycenter
  set Compass(npointer) $npointer
  set Compass(spointer) $spointer
  set Compass(radius)  $radius
  set Compass(north)   $north
  set Compass(east)    $east
  set Compass(west)    $west
  set Compass(south)   $south
  set Compass(merid)   $merid

  return $w
}

#
# Set_Compass - Procedure to set the compass to a given direction.
#

proc Set_Compass { degrees } {
  global Compass stuff

  if { $::setting(allowcompass) != 1 } {
    return
  }
  set r $Compass(radius)
  set xc $Compass(xcenter)
  set yc $Compass(ycenter)
  set nptr $Compass(npointer)
  set sptr $Compass(spointer)
  set n $Compass(north)
  set e $Compass(east)
  set w $Compass(west)
  set s $Compass(south)
  set merid $Compass(merid)

  set pi 3.141592654

  set ang [expr (90 + $degrees - $::setting(declination)) * $pi / 180]
  set x2 [expr $xc + ($r - 5) * cos($ang)]
  set y2 [expr $yc - ($r - 5) * sin($ang)]
  $stuff(compass) coords $nptr $xc $yc $x2 $y2
  set x2 [expr $xc - ($r - 5) * cos($ang)]
  set y2 [expr $yc + ($r - 5) * sin($ang)]
  $stuff(compass) coords $sptr $xc $yc $x2 $y2

  set ang [expr (90 + $degrees) * $pi / 180]
  set x1 [expr $xc + $r * cos($ang)]
  set y1 [expr $yc - $r * sin($ang)]
  set x2 [expr $xc - $r * cos($ang)]
  set y2 [expr $yc + $r * sin($ang)]
  $stuff(compass) coords $merid $x1 $y1 $x2 $y2

  set xn [expr $xc + ($r + 10) * cos($ang)]
  set yn [expr $yc - ($r + 10) * sin($ang)]
  $stuff(compass) coords $n $xn $yn
  set xe [expr $xc + ($r + 10) * cos($ang - $pi / 2.0)]
  set ye [expr $yc - ($r + 10) * sin($ang - $pi / 2.0)]
  $stuff(compass) coords $e $xe $ye
  set xw [expr $xc + ($r + 10) * cos($ang + $pi / 2.0)]
  set yw [expr $yc - ($r + 10) * sin($ang + $pi / 2.0)]
  $stuff(compass) coords $w $xw $yw
  set xs [expr $xc + ($r + 10) * cos($ang + $pi)]
  set ys [expr $yc - ($r + 10) * sin($ang + $pi)]
  $stuff(compass) coords $s $xs $ys

  return
}

#
#  Build_Calc - procedure to set up the grid and bearing calculator
#               window.
#

proc Build_Calc { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "Calc"
  wm protocol $f WM_DELETE_WINDOW { wm withdraw $windows(calc) }
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    catch { wm iconbitmap $f log.ico }
  }

  label $f.lrg -text "Remote Grid"
  set windows(calcgridentry) [ entry $f.erg -textvariable stuff(calcrecd) \
    -width 7 -font $::setting(bigfont) -background yellow ]

  label $f.lrawb -text "Raw Bearing (deg)"
  entry $f.erawb -textvariable stuff(brng) -width 7 -state readonly \
    -font $::setting(entryfont) 

  label $f.lao -text "Ant Offset (deg)"
  entry $f.eao -textvariable ::setting(antoffset) -width 7 \
    -font $::setting(entryfont) -background yellow

  label $f.lb -text "Rotor Bearing (deg)" -font { systemfont 8 bold }
  entry $f.eb -textvariable stuff(rotorbrng) -width 7 -state readonly \
    -font $::setting(entryfont) 

  set windows(rotorbutton) [ button $f.bmr -text "Move Rotor" \
    -command Move_Rotor -background pink ]

  label $f.lcb -text "Rotor Position (deg)" -font { systemfont 8 bold }
  entry $f.ecb -textvariable stuff(rotorpos) -width 7 -state readonly \
    -font $::setting(entryfont) 

  label $f.lrb -text "Reverse (deg)"
  entry $f.erb -textvariable stuff(rbrng) -width 7 -state readonly \
    -font $::setting(entryfont) 

  label $f.lr -text "Range (miles)"
  entry $f.er -textvariable stuff(rang) -width 7 -state readonly \
    -font $::setting(entryfont) 

  label $f.lrk -text "Range (km)"
  entry $f.erk -textvariable stuff(rangkm) -width 7 -state readonly \
    -font $::setting(entryfont) 

  label $f.lmb -text "Mag Bearing (deg)"
  entry $f.emb -textvariable stuff(mbrng) -width 7 -state readonly \
    -font $::setting(entryfont) 

  label $f.lrm -text "Mag Reverse (deg)"
  entry $f.erm -textvariable stuff(mrbrng) -width 7 -state readonly \
    -font $::setting(entryfont) 

  if { $::setting(allowcompass) == 1 } {
    set stuff(compass) [ Create_Compass $f.c ]
  }

  label $f.ld -text "Declination (deg)"
  entry $f.ed -textvariable ::setting(declination) -width 7 \
    -font $::setting(entryfont) -background yellow
  
  label $f.ls -text "Speed (mph)"
  entry $f.es -textvariable stuff(speed) -width 7 -state readonly \
    -font $::setting(entryfont)

  label $f.lc -text "True Course (deg)"
  entry $f.ec -textvariable stuff(course) -width 7 -state readonly \
    -font $::setting(entryfont)


  grid $f.lrg $f.erg -padx 2 -pady 2
  grid $f.lrawb  $f.erawb  -padx 2 -pady 2
  grid $f.lao $f.eao -padx 2 -pady 2
  grid $f.lb  $f.eb  -padx 2 -pady 2
  grid $f.bmr -      -padx 2 -pady 2 -sticky news
  grid $f.lcb $f.ecb -padx 2 -pady 2
  grid $f.lrb $f.erb -padx 2 -pady 2
  grid $f.lr  $f.er  -padx 2 -pady 2
  grid $f.lrk $f.erk -padx 2 -pady 2
  grid $f.lmb $f.emb -padx 2 -pady 2
  grid $f.lrm $f.erm -padx 2 -pady 2
  if { $::setting(allowcompass) == 1 } {
    grid $f.c   -      -padx 2 -pady 2
  }
  grid $f.ld  $f.ed  -padx 2 -pady 2
  grid $f.ls  $f.es  -padx 2 -pady 2
  grid $f.lc  $f.ec  -padx 2 -pady 2

  grid $f.lrg -sticky nes
  grid $f.lrawb -sticky nes
  grid $f.lao -sticky nes
  grid $f.lb  -sticky nes
  grid $f.lrb -sticky nes
  grid $f.lr  -sticky nes
  grid $f.lrk  -sticky nes
  grid $f.lmb -sticky nes
  grid $f.lrm -sticky nes
  grid $f.ld  -sticky nes
  grid $f.ls  -sticky nes
  grid $f.lc  -sticky nes

  wm resizable $f 0 0
  update idletasks

  return $f
}

#
# Popup_Net - procedure to bring up the net window.
#

proc Popup_Net { } {
  global windows stuff
  
  wm deiconify $windows(net)
  raise $windows(net)
  focus $windows(netmsgentry)
  $windows(netmsgentry) select range 0 end
  $windows(netmsgentry) icursor end
}

#
# Popup_Calc - procedure to bring up the calc window.
#

proc Popup_Calc { } {
  global windows stuff
  
  wm deiconify $windows(calc)
  raise $windows(calc)
  focus $windows(calc)
  Bear_Calc $stuff(sent) $stuff(recd)
}

#
#  Build_Shortcuts - procedure to set up the score window.
#

proc Build_Shortcuts { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "Shortcuts"
  wm protocol $f WM_DELETE_WINDOW { wm withdraw $windows(shortcuts) }
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    catch { wm iconbitmap $f log.ico }
  }

  set windows(shortcutstext) [ text $f.t -font $::setting(font) -width 54 \
    -height 24 -yscrollcommand "$f.s set" ]
  scrollbar $f.s -orient vert -command "$f.t yview"

  grid $f.t $f.s -sticky ns -padx 1 -pady 2

  grid rowconfigure $f 0 -weight 1

  $windows(shortcutstext) configure -state normal
  $windows(shortcutstext) delete 1.0 end

  $windows(shortcutstext) insert insert "F<n>          Play Message <n> or QSY to band <n>\n"
  $windows(shortcutstext) insert insert "F12           Focus to Main Window Call Entry\n"
  $windows(shortcutstext) insert insert "Control-F<n>  Net Message to Peer <n>\n"
  $windows(shortcutstext) insert insert "Alt-Key-F4    Hide Current Sub-Window\n"
  $windows(shortcutstext) insert insert "Page Down     Decrease CW Speed\n"
  $windows(shortcutstext) insert insert "Page Up       Increase CW Speed\n"
  $windows(shortcutstext) insert insert "Escape        Stop Keyer\n"
  $windows(shortcutstext) insert insert "Alt-Key-<n>   Play Keyer Message <n>\n"
  $windows(shortcutstext) insert insert "Alt-Key-+     QSY Up\n"
  $windows(shortcutstext) insert insert "Alt-Key-=     QSY Up\n"
  $windows(shortcutstext) insert insert "Alt-Key--     QSY Down\n"
  $windows(shortcutstext) insert insert "Alt-Key-\[     Previous Station\n"
  $windows(shortcutstext) insert insert "Alt-Key-\]     Next Station\n"
  $windows(shortcutstext) insert insert "Alt-Key-a     Accept Next WIP\n"
  $windows(shortcutstext) insert insert "Alt-Key-b     QSY Up\n"
  $windows(shortcutstext) insert insert "Alt-Key-B     QSY Down\n"
  $windows(shortcutstext) insert insert "Alt-Key-c     Popup Calc\n"
  $windows(shortcutstext) insert insert "Alt-Key-d     Delete Entry from Log\n"
  $windows(shortcutstext) insert insert "Alt-Key-e     Edit Entry from Log\n"
  $windows(shortcutstext) insert insert "Alt-Key-f     Popup Station List\n"
#  $windows(shortcutstext) insert insert "Alt-Key-g     Toggle GPS/Manual\n"
  $windows(shortcutstext) insert insert "Alt-Key-h     Help Menu\n"
  $windows(shortcutstext) insert insert "Alt-Key-i     Direct PTT Key\n"
  $windows(shortcutstext) insert insert "Alt-Key-j     Move Rotor\n"
  $windows(shortcutstext) insert insert "Alt-Key-k     Popup Skeds\n"
  $windows(shortcutstext) insert insert "Alt-Key-l     Lookup Callsign\n"
  $windows(shortcutstext) insert insert "Alt-Key-L     Lookup Buds\n"
  $windows(shortcutstext) insert insert "Alt-Key-m     Popup Map\n"
  $windows(shortcutstext) insert insert "Alt-Key-n     Popup Net\n"
  $windows(shortcutstext) insert insert "Alt-Key-o     Change to Next Mode\n"
  $windows(shortcutstext) insert insert "Alt-Key-p     Pass Station\n"
#  $windows(shortcutstext) insert insert "Alt-Key-r     Toggle Realtime/Manual\n"
  $windows(shortcutstext) insert insert "Alt-Key-s     Popup Score\n"
  $windows(shortcutstext) insert insert "Alt-Key-t     Cancel Edit\n"
  $windows(shortcutstext) insert insert "Alt-Key-v     Save Settings\n"
  $windows(shortcutstext) insert insert "Alt-Key-w     Clear Entry\n"
  $windows(shortcutstext) insert insert "Alt-Key-y     Popup Keyer\n"
  $windows(shortcutstext) insert insert "Alt-Key-z     Pop Callsign Off Stack\n"
  $windows(shortcutstext) insert insert "Return        Log QSO\n"
  $windows(shortcutstext) insert insert "Spacebar      Toggle between Call and Recd Fields\n"

  $windows(shortcutstext) configure -state disabled

  wm resizable $f 0 1
  update idletasks

  return $f
}

#
# Shortcuts - procedure to bring up the shortcuts window.
#

proc Shortcuts { } {
  global windows stuff
  
  wm deiconify $windows(shortcuts)
  raise $windows(shortcuts)
}

#
#  Build_Score - procedure to set up the score window.
#

proc Build_Score { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "Score"
  wm protocol $f WM_DELETE_WINDOW { wm withdraw $windows(score) }
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    catch { wm iconbitmap $f log.ico }
  }

  set windows(scoretext) [ text $f.t -font $::setting(font) \
    -width 48 -height 1 ]

  pack $f.t -pady 1 -padx 1

  wm resizable $f 0 0
  update idletasks

  return $f
}

#
# Open_Keyer
#

proc Open_Keyer { } {
  global stuff

  if { $::setting(keyeripport) == 0 } {
    return
  }

  # open connection to keyer server
  if [catch {socket -async $::setting(keyeripaddr) $::setting(keyeripport)} stuff(keyersid) ] {
    Blacklist "keyer" "connection failed"
    unset stuff(keyersid)
    return
  }

  # set up the descriptor
  if [ catch { fconfigure $stuff(keyersid) -buffering line -blocking 0 } ] {
    Blacklist "keyer" "configuration failed"
    return
  }

  set stuff(keyerstatus) "Open"
  set stuff(keyertime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
}

proc Close_Keyer { quit } {
  global stuff

  if { [ info exist stuff(keyersid) ] } {
    catch { fconfigure $stuff(keyersid) -blocking 1 }
    if { $quit == "quit" } {
      catch { puts $stuff(keyersid) "quit!" }
    }
    catch { close $stuff(keyersid) }
    catch { unset stuff(keyersid) }
  }

  set stuff(keyerstatus) "Closed"
  set stuff(keyertime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
}

proc Keyer_Puts { m } {
  global stuff

  # skip if not configured
  if { $::setting(keyeripport) == 0 } {
    return
  }

  # skip if blacklisted
  if { $stuff(blacklist,keyer) == 1 } {
    return
  }

  Debug "Keyer_Puts" "sending $m"

  if { [ catch { puts $stuff(keyersid) $m } r ] } {
    Blacklist "keyer" "puts failed: $r"
    return
  }

  # flush $stuff(keyersid)

  set stuff(keyerstatus) "$m"
  set stuff(keyertime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
}

#
# Build_Keyer - procedure to make window for interfacing to Keyer server.
#

proc Build_Keyer { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "Keyer"
  wm protocol $f WM_DELETE_WINDOW { wm withdraw $windows(keyer) }
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    catch { wm iconbitmap $f log.ico }
  }

  frame $f.f0 -borderwidth 2 -relief raised

  set windows(keyerbutton) \
    [ button $f.f0.bk -text "Keyer" -command { Unblacklist "keyer" } ]

  grid $f.f0.bk - -sticky news -padx 1 -pady 1

  label $f.f0.lcw -text "CW" -font { systemfont 8 bold }
  label $f.f0.lv -text "Voice" -font { systemfont 8 bold }

  grid $f.f0.lcw $f.f0.lv -sticky news -padx 1 -pady 1

  # CW keyer bindings
  for { set i 1 } { $i < 7 } { incr i } {

    button $f.f0.b$i -text "Play $i" -command "Play_CW $i" \
      -background "light green" -underline 5 -width 10

    set j [expr $i + 6]

    if { $j < 10 } {
      button $f.f0.b$j -text "Play $j" -command "Play_Voice $j" \
        -background "light green" -underline 5 -width 10
      grid $f.f0.b$i $f.f0.b$j -sticky news -padx 1 -pady 1
    } else {
      grid $f.f0.b$i -sticky news -padx 1 -pady 1
    }

  }
 
  set windows(m6entry) [ entry $f.f0.e6 -textvariable stuff(m6) -width 32 ]
  grid $f.f0.e6 - -sticky news -padx 1 -pady 1

  button $f.f0.bstop -text "Stop" -command { Keyer_Puts "stop!" } -width 10
  grid $f.f0.bstop - -sticky news -padx 1 -pady 1

  pack $f.f0

  wm resizable $f 0 0
  update idletasks

  return $f
}

#
# Draw_Map_Key - procedure to fill in map key area.
#

proc Draw_Map_Key { } {
  global windows stuff

  if { $::setting(rules) == "old" } {
    $windows(mapintro) insert insert "Using old rover rules. QSOs for current sent grid.\n" { unworkedtag }
  } else {
    $windows(mapintro) insert insert "Using new rover rules. QSOs for all sent grids.\n" { unworkedtag }
  }
  $windows(mapintro) insert insert "Key: 0 QSOs " { unworkedtag }
  $windows(mapintro) insert insert ">= 1 QSO" { coldworkedtag }
  $windows(mapintro) insert insert " " { unworkedtag }
  $windows(mapintro) insert insert ">= 2 QSOs" { warmworkedtag }
  $windows(mapintro) insert insert " " { unworkedtag }
  $windows(mapintro) insert insert ">= 5 QSOs" { hotworkedtag }
  $windows(mapintro) insert insert "\n" { unworkedtag }
  $windows(mapintro) insert insert "Work non-highlighted grids!\n" { unworkedtag }
}

#
#  Build_Map - procedure to set up the map window.
#

proc Build_Map { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "Map"
  wm protocol $f WM_DELETE_WINDOW { wm withdraw $windows(map) ; \
    set stuff(mapopen) 0 }
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    catch { wm iconbitmap $f log.ico }
  }

  set windows(mapintro) [ text $f.i -font $::setting(font) -width 55 -height 3 ]
  $f.i tag configure coldworkedtag -foreground $::setting(mapcoldfg) -background $::setting(mapcoldbg)
  $f.i tag configure warmworkedtag -foreground $::setting(mapwarmfg) -background $::setting(mapwarmbg)
  $f.i tag configure hotworkedtag -foreground $::setting(maphotfg) -background $::setting(maphotbg)
  $f.i tag configure unworkedtag -foreground $::setting(mapunwkfg) -background $::setting(mapunwkbg)

  set windows(maptext) [ text $f.t -font $::setting(font) -width [ expr 5 * $::setting(mapwidth) ] \
    -height $::setting(mapheight) -wrap none]
  $f.t tag configure coldworkedtag -foreground $::setting(mapcoldfg) -background $::setting(mapcoldbg)
  $f.t tag configure warmworkedtag -foreground $::setting(mapwarmfg) -background $::setting(mapwarmbg)
  $f.t tag configure hotworkedtag -foreground $::setting(maphotfg) -background $::setting(maphotbg)
  $f.t tag configure unworkedtag -foreground $::setting(mapunwkfg) -background $::setting(mapunwkbg)

  button $f.bn -text "^" -command { Map_Move "n" }
  button $f.bw -text "<" -command { Map_Move "w" }
  button $f.be -text ">" -command { Map_Move "e" }
  button $f.bs -text "v" -command { Map_Move "s" }

  label $f.lcg -text "Center"
  entry $f.ecg -width 6 -textvariable stuff(mapcenter) \
    -font $::setting(font) -background yellow

  menubutton $f.mBand -text "Map Band" -menu $f.mBand.menu -relief raised
  menu $f.mBand.menu -tearoff 0
  foreach b $::setting(bands) {
    $f.mBand.menu add radio -label $b -variable stuff(mapband) -value $b \
      -command { Redraw_Map $stuff(mapcenter) }
  }
  entry $f.eb -width 6 -textvariable stuff(mapband) -state readonly \
    -font $::setting(font) -readonlybackground lightyellow

  button $f.bmc -text "Redraw" -command { Redraw_Map $stuff(mapcenter) } \
    -background pink
  button $f.br  -text "Sent" -command { Redraw_Map $stuff(sent) }
  button $f.brr -text "Recd" -command { Redraw_Map $stuff(recd) }

  grid x      $f.i   -        -      -     -      x
  grid x      $f.bn  -        -      -     -      x
  grid $f.bw  $f.t   -        -      -     -      $f.be
  grid x      $f.bs  -        -      -     -      x
  grid x      $f.lcg $f.mBand x      x     x      x
  grid x      $f.ecg $f.eb    $f.bmc $f.br $f.brr x

  grid $f.bw     -sticky news -padx 1 -pady 1
  grid $f.be     -sticky news -padx 1 -pady 1
  grid $f.bn     -sticky news -padx 1 -pady 1
  grid $f.bs     -sticky news -padx 1 -pady 1
  grid $f.i      -sticky news -padx 1 -pady 1
  grid $f.t      -sticky news -padx 1 -pady 1
  grid $f.lcg    -sticky news -padx 1 -pady 1
  grid $f.ecg    -sticky news -padx 1 -pady 1
  grid $f.mBand  -sticky news -padx 1 -pady 1
  grid $f.eb     -sticky news -padx 1 -pady 1
  grid $f.bmc    -sticky news -padx 1 -pady 1
  grid $f.br     -sticky news -padx 1 -pady 1
  grid $f.brr    -sticky news -padx 1 -pady 1
  
  $windows(maptext) configure -state disabled
  wm resizable $f 0 0

  update idletasks

  return $f
}

#
# Save_Summary - procedure to write a summary file (score summary).
#

proc Save_Summary { } {
  global stuff qsos mults numactivated

  set basename [ file rootname $::setting(logfile) ]
  set fn "$basename.sum"

  set fid [open $fn w 0666]
  puts $fid " "
  puts $fid "ROVERLOG CONTEST SUMMARY SHEET"
  puts $fid " "
  puts $fid "CONTEST NAME ______________________________________________________ "
  puts $fid " "
  puts $fid "CALL USED ___ $::setting(mycall) ___"
  puts $fid " "
  puts $fid "HOME GRID SQUARE _______________"
  puts $fid " "
  puts $fid "SECTION ________________________"
  puts $fid " "
  puts $fid "CALL OF OPERATOR IF DIFFERENT FROM CALL USED ______________________ "
  puts $fid " "
  puts $fid "OPERATOR CATEGORY \[SINGLE-OP\] \[SINGLE-OP-PORTABLE\] \[ROVER\]"
  puts $fid "                  \[MULTI\] \[CHECKLOG\]"
  puts $fid "BAND CATEGORY     \[ALL\] \[LIMITED\] "
  puts $fid "POWER CATEGORY    \[HIGH\] \[LOW\]"
  puts $fid " "
  puts $fid "IF MULTIOPERATOR, LIST CALLS OF OPERATORS AND LOGGERS"
  puts $fid " "
  puts $fid "____________________________________________________________________"
  puts $fid " "
  puts $fid "+-----------Valid QSOs-----QSO Points-Multipliers+"
  set j 0
  set sltotalqsos 0
  set sltotalqsopts 0
  set sltotalmults 0
  foreach slband $::setting(bands) {
    set slworth [ lindex $::setting(bandpts) $j ]
    if { [ info exists qsos($slband) ] } {
      set slqsos $qsos($slband)
      set sltotalqsos [ expr $sltotalqsos + $slqsos ]
      set slqsopts [ expr $slworth * $slqsos ]
      set sltotalqsopts [ expr $sltotalqsopts + $slqsopts ]
    } else {
      set slqsos 0
      set slqsopts 0
    }
    if { [ info exists mults($slband) ] } {
      set slmults $mults($slband)
      set sltotalmults [ expr $sltotalmults + $slmults ]
    } else {
      set slmults 0
    }
    puts $fid [format "|%4s     | %9d |x%1d| %9d | %9d |" $slband $slqsos $slworth $slqsopts $slmults]
    puts $fid "|---------|-----------|--|-----------|-----------|"
    incr j
  }
  set slactivated 0
  if { [ info exists numactivated ] } {
    if { $numactivated > 1 } {
      set slactivated $numactivated
    }
  }
  set dummy [format "%9d" $slactivated]
  puts $fid "|  Grids Activated - Rovers Only     | $dummy | Claimed Score"
  puts $fid "|==================================================================+"
  if { $::setting(rules) == "old" } {
    set dummy [expr $sltotalqsopts * $sltotalmults ]
  } else {
    set dummy [expr $sltotalqsopts * ( $sltotalmults + $slactivated ) ]
  }
  set dummy [ format "|   Total | %9d | %12d | %9d | %15d |" \
    $sltotalqsos $sltotalqsopts $sltotalmults $dummy ]
  puts $fid $dummy
  puts $fid "+------------------------------------------------------------------+"
  puts $fid "| HOURS OPERATING:          |"
  puts $fid "+----------------+----------+"
  puts $fid " "
  puts $fid "--------------------------------------------------------------------"
  puts $fid "| Club Participation?   ___ Yes  ___ No  If yes, print the name of |"
  puts $fid "|                                                                  |"
  puts $fid "| your Active Affiliated Club: ___________________________________ |"
  puts $fid "--------------------------------------------------------------------"
  puts $fid " "
  puts $fid "\"I have observed all competition rules as well as all regulations"
  puts $fid "for Amateur Radio in my country. My report is correct and true to"
  puts $fid "the best of my knowledge. I agree to be bound by the decisions of"
  puts $fid "the Awards Committee.\""
  puts $fid " "
  puts $fid "DATE __________ SIGNATURE ________________________ CALL ____________"
  puts $fid " "
  puts $fid "NAME _____________________________________________ CALL ____________"
  puts $fid " "
  puts $fid "ADDRESS ____________________________________________________________"
  puts $fid " "
  puts $fid "____________________________________________________________________"
  puts $fid " "
  puts $fid "EMAIL ADDRESS ______________________________________________________"
  puts $fid " "
  close $fid
}

#
#  Redraw_Score - procedure to update the score window.
#

proc Redraw_Score { } {
  global windows stuff worked activated qsos mults numactivated

  if { [ wm state $windows(score) ] == "withdrawn" } { return 0 }

  # Clear existing text contents
  $windows(scoretext) delete 1.0 end

  # Clear existing tallies
  set claimedscore 0

  if { $::setting(rules) != "grid6" && $::setting(rules) != "dist" && $::setting(rules) != "distmult" } {
  
    if { [ info exists qsos ] } {
      for { set handle [ array startsearch qsos ]
        set qsosindex [ array nextelement qsos $handle ] } \
        { $qsosindex != "" } \
        { set qsosindex [ array nextelement qsos $handle ] } {
        set qsos($qsosindex) 0
      }
    }
  
    if { [ info exists mults ] } {
      for { set handle [ array startsearch mults ]
        set multsindex [ array nextelement mults $handle ] } \
        { $multsindex != "" } \
        { set multsindex [ array nextelement mults $handle ] } {
        set mults($multsindex) 0
      }
    }
  
    # Put some stuff in the textbox
    if { [ info exists worked ] } {
  
      for { set handle [ array startsearch worked ]
        set bandgrid [ array nextelement worked $handle ] } \
        { $bandgrid != "" } \
        { set bandgrid [ array nextelement worked $handle ] } {
  
        set band [ split $bandgrid , ]
        set band [ lindex $band 0 ]
  
        if { [ info exist qsos($band) ] } {
          set qsos($band) [ expr $qsos($band) + $worked($bandgrid) ]
        } else {
          set qsos($band) $worked($bandgrid)
        }
  
  
        if { $worked($bandgrid) != 0 } {
          if { [ info exist mults($band) ] } {
            set mults($band) [ expr $mults($band) + 1 ]
          } else {
            set mults($band) 1
          }
        }
      }
      array donesearch worked $handle
  
      $windows(scoretext) insert insert "RoverLog QSOs by Activated Grid:\n"
      $windows(scoretext) insert insert "Grid\tQSOs\tGrid\tQSOs\tGrid\tQSOs\n"
      set numactivated 0
      for { set handle [ array startsearch activated ]
        set curactivated [ array nextelement activated $handle ] } \
        { $curactivated != "" } \
        { set curactivated [ array nextelement activated $handle ] } {
  
        if { $activated($curactivated) != 0 } {
          incr numactivated
          $windows(scoretext) insert insert \
            "$curactivated\t$activated($curactivated)"
          if { [ expr $numactivated % 3 ] == 0 } {
            $windows(scoretext) insert insert "\n"
          } else {
            $windows(scoretext) insert insert "\t"
          }
        }
      }
  
      if { [ expr $numactivated % 3 ] != 0 } {
        $windows(scoretext) insert insert "\n"
      }
  
      array donesearch activated $handle
  
      set j 0
      set totalqsos 0
      set totalqsopts 0
      set totalmults 0
      $windows(scoretext) insert insert "\nRoverLog Score Summary, Using $::setting(rules) rules:\n"
      $windows(scoretext) insert insert "Band\tQSOs\tValue\tQSOPts\tMults\n"
      foreach i $::setting(bands) {
        $windows(scoretext) insert insert $i
        $windows(scoretext) insert insert "\t"
        if { [ info exists qsos($i) ] } {
          set totalqsos [ expr $totalqsos + $qsos($i) ]
          $windows(scoretext) insert insert $qsos($i)
          $windows(scoretext) insert insert "\t"
          $windows(scoretext) insert insert [ lindex $::setting(bandpts) $j ]
          $windows(scoretext) insert insert "\t"
          set qsopts [ expr [ lindex $::setting(bandpts) $j ] * $qsos($i) ]
          $windows(scoretext) insert insert $qsopts
          set totalqsopts [ expr $totalqsopts + $qsopts ]
        } else {
          $windows(scoretext) insert insert "0"
          $windows(scoretext) insert insert "\t"
          $windows(scoretext) insert insert [ lindex $::setting(bandpts) $j ]
          $windows(scoretext) insert insert "\t"
          $windows(scoretext) insert insert "0"
        }
        $windows(scoretext) insert insert "\t"
        if { [ info exists mults($i) ] } {
          $windows(scoretext) insert insert $mults($i)
          set totalmults [ expr $totalmults + $mults($i) ]
        } else {
          $windows(scoretext) insert insert "0"
        }
        $windows(scoretext) insert insert "\n"
        incr j
      }
  
      if { $::setting(rules) != "old" } {
        $windows(scoretext) insert insert \
          "\nGrids activated: \t\t"
        $windows(scoretext) insert insert $numactivated
        $windows(scoretext) insert insert "\n"
      }
      $windows(scoretext) insert insert "\nTotals:"
      $windows(scoretext) insert insert "\t"
      $windows(scoretext) insert insert $totalqsos
      $windows(scoretext) insert insert "\t\t"
      $windows(scoretext) insert insert $totalqsopts
      $windows(scoretext) insert insert "\t"
      if { $numactivated == 1 || $::setting(rules) == "old" } {
        $windows(scoretext) insert insert $totalmults
        $windows(scoretext) insert insert "\t"
        set stuff(claimedscore) [ expr $totalmults * $totalqsopts ]
      } else {
        $windows(scoretext) insert insert [ expr $totalmults + $numactivated ]
        $windows(scoretext) insert insert "\t"
        set stuff(claimedscore) [ expr ( $totalmults + $numactivated ) * \
          $totalqsopts ]
      }
      $windows(scoretext) insert insert \
        "\n\nClaimed Score: $stuff(claimedscore)"
    } else {
      $windows(scoretext) insert insert "No score yet."
      set stuff(claimedscore) 0
    }
  } else {

    # Set up the distance-based points by band.
    set j 0
    foreach b $::setting(bands) {
      set distbased_pts($b) [ lindex $::setting(bandpts) $j ]
      Debug "Redraw_Score" "distbase_pts($b) = $distbased_pts($b)"
      incr j
    }

    # Clear out old data
    if { [ info exist distbased ] } {
      unset distbased
    }
    if { [ info exist distbased_dist ] } {
      unset distbased_dist
    }
    if { [ info exist distbased_qsos ] } {
      unset distbased_qsos
    }

    Debug "Redraw_Score" "Starting."
    # Do distance-based scoring calculations
    foreach b $stuff(loglist) {

      Debug "Redraw_Score" "Processing \"$b\"."
  
      # If we do not have a 6-digit grid, do not count the QSO.
      if { [ string length $b ] != 79 } {
        Debug "Redraw_Score" "Do not have 6-digit received grid. Skipping."
        continue
      }
  
      # parse desired variables from log record
      binary scan $b "x5a5x1a2x1a10x1a4x1a13x5a6x1a13x5a6" \
        band mode date utc mycall sent call recd
  
      # clean up parsed variables
      set band [ string toupper [ string trim $band ] ]
      set sent [ string toupper [ string trim $sent ] ]
      set call [ string toupper [ string trim $call ] ]
      set recd [ string toupper [ string trim $recd ] ]
  
      # If we do not have a 6-digit sent grid, do not count the QSO.
      if { [ string length $sent ] != 6 } {
        Debug "Redraw_Score" "Do not have 6-digit sent grid. Skipping."
        continue
      }
  
      # Calculate the distance for this QSO
      set distkm [ expr round( [ Dist_Calc_Km $sent $recd ] ) ]
      Debug "Redraw_Score" "Distance $distkm km."
  
      # Do not count runty QSOs
      if { $distkm < 1 } {
        set distkm 1
      }
  
      # Get rid of "/" stuff. Rules say you can't work a guy again
      # with different slash stuff.
      set call [ Drop_Slash "first" $call ]
  
      # If we already counted a QSO like this, do not count another.
      if { [ info exists distbased($call,$band,$sent,$recd) ] } {
        Debug "Redraw_Score" "Dupe.  Skipping."
        continue
      }
  
      # Accumulate distance by band.
      if { [ info exists distbased_dist($band) ] } {
        incr distbased_dist($band) $distkm
      } else {
        set distbased_dist($band) $distkm
      }
      Debug "Redraw_Score" "Distance based score for this band is now $distbased_dist($band)."
  
      # Accumulate QSOs by band.
      set r [ array get distbased "$call,$band,*" ]
      Debug "Redraw_Score" "Search for $call on $band returned \"$r\"."
      if { [ llength $r ] == 0 } {
        Debug "Redraw_Score" "Don't have this call on this band yet.  Incrementing QSO score."
        if { [ info exists distbased_qsos($band) ] } {
          incr distbased_qsos($band) $distbased_pts($band)
        } else {
          set distbased_qsos($band) $distbased_pts($band)
        }
      } else {
        Debug "Redraw_Score" "Already have this call on this band.  Not incrementing QSO score."
      }
  
      # Set the unique database entry to the distance for this QSO.
      set distbased($call,$band,$sent,$recd) $distkm
  
    }
  
    # Add distance-based scoring info to window.
    $windows(scoretext) insert insert "6-Digit Distance-Based Contest Scoring:"
  
    set totaldistscore 0
    set totaldistmultscore 0
  
    foreach band $::setting(bands) {
  
      if { [ info exists distbased_qsos($band) ] && [ info exists distbased_dist($band) ] } {
        if { $::setting(rules) == "dist" } {
          set distscore [ expr $distbased_qsos($band) + $distbased_dist($band) ]
          incr totaldistscore $distscore
          $windows(scoretext) insert insert "\n$band: $distbased_qsos($band) QSO Pts + $distbased_dist($band) km = $distscore"
        } elseif { $::setting(rules) == "distmult" } {
          set distmultscore [ expr $distbased_pts($band) * $distbased_dist($band) ]
          incr totaldistmultscore $distmultscore
          $windows(scoretext) insert insert "\n$band: $distbased_pts($band) QSO Pts * $distbased_dist($band) km = $distmultscore"
	} else {
          $windows(scoretext) insert insert "\n$band: $distbased_qsos($band) QSO Pts, $distbased_dist($band) km"
	}
      }
    }

    if { $::setting(rules) == "dist" } {
      $windows(scoretext) insert insert "\nTotal 6-Digit Distance and Band Adder-Based Score: $totaldistscore"
      set stuff(claimedscore) $totaldistscore
    } elseif { $::setting(rules) == "distmult" } {
      $windows(scoretext) insert insert "\nTotal 6-Digit Distance and Band Multiplier-Based Score: $totaldistmultscore"
      set stuff(claimedscore) $totaldistmultscore
    } else {
      $windows(scoretext) insert insert "\nTotal Score for Unknown Rules Type: 0"
      set stuff(claimedscore) 0
    }
  }

  $windows(scoretext) configure -height [ $windows(scoretext) index end ]

  # Update Claimed Score in Log Header
  set csline [ $windows(logheadtext) search -forward \
    "CLAIMED-SCORE:" 1.0 end ]
  if { $csline >= 0 } {
    $windows(logheadtext) delete "$csline linestart" "$csline lineend"
    $windows(logheadtext) insert $csline "CLAIMED-SCORE: $stuff(claimedscore)"
  }
}

#
#  Map_Move - procedure to move the map center 1/2 screen
#

proc Map_Move { dir } {
  global windows stuff
  
  set centerlatlon [ To_LatLon [ string range $stuff(mapcenter) 0 3 ] ]
  scan $centerlatlon "%f %f" centerlat centerlon

  if { $dir == "n" } {
    set centerlat [expr $centerlat + ( int( $::setting(mapheight) / 2 ) ) ]
  }
  if { $dir == "w" } {
    set centerlon [expr $centerlon - int( $::setting(mapwidth) ) ]
  }
  if { $dir == "e" } {
    set centerlon [expr $centerlon + int( $::setting(mapwidth) ) - 1 ]
  }
  if { $dir == "s" } {
    set centerlat [expr $centerlat - ( int( $::setting(mapheight) / 2 ) ) ]
  }

  set centerlatlon [ format "%f %f" $centerlat $centerlon ]
  set stuff(mapcenter) [ string range [ To_Grid $centerlatlon ] 0 3 ]

  Redraw_Map $stuff(mapcenter)
}

#
#  Redraw_Map_Band - procedure to redraw the map including a band change.
#

proc Redraw_Map_Band { } {
  global stuff

  set stuff(mapband) $stuff(band)
  Redraw_Map $stuff(sent)
}

#
#  Redraw_Map - procedure to update the map of worked stations.
#

proc Redraw_Map { center } {
  global windows stuff worked

  if { [ wm state $windows(map) ] == "withdrawn" } { return 0 }

  if { $center == "" } {
    if { $stuff(mapcenter) == "" } {
      set center $stuff(sent)
    } else {
      set center $stuff(mapcenter)
    }
  }

  # Clear existing text contents
  $windows(mapintro) configure -state normal
  $windows(mapintro) delete 1.0 end
  $windows(maptext) configure -state normal
  $windows(maptext) delete 1.0 end

  # Draw map key
  Draw_Map_Key

  set stuff(mapcenter) [string toupper $center]

  if { $stuff(mapband) == "" } {
    set stuff(mapband) [string toupper $stuff(band)]
  }

  if { $stuff(mapcenter) != "" } {

    # Set map center
    set centerlatlon [ To_LatLon [ string range $stuff(mapcenter) 0 3 ] ]
    scan $centerlatlon "%f %f" centerlat centerlon

    set mhw [ expr int($::setting(mapwidth) / 2) ]
    set mhh [ expr int($::setting(mapheight) / 2) ]

    # Fix Map Center Limits:
    #   AR09 RR99
    #   AA00 RA90
    if { $centerlat > [ expr 89.0 - $mhh ] } {
      set centerlat [ expr 89.0 - $mhh ]
    }
    if { $centerlon < [ expr -180.0 + 2 * $mhw ] } {
      set centerlon [ expr -180.0 + 2 * $mhw ]
    }
    if { $centerlon > [ expr 178.0 - 2 * $mhw ] } {
      set centerlon [ expr 178.0 - 2 * $mhw ]
    }
    if { $centerlat < [ expr -90 + $mhh ] } {
      set centerlat [ expr -90 + $mhh ]
    }

    set centerlatlon [ format "%f %f" $centerlat $centerlon ]
    set stuff(mapcenter) [ string range [ To_Grid $centerlatlon ] 0 3 ]

    # Draw map
    set startlat [ expr $centerlat + $mhh ]
    set stoplat  [ expr $centerlat - ( 1 + $mhh ) ]
    set startlon [ expr $centerlon - ( 2 * $mhw ) ]
    set stoplon  [ expr $centerlon + ( 2 * $mhw + 1 ) ]

    Debug "Redraw_Map" "start $startlat, $startlon"
    Debug "Redraw_Map" "stop $stoplat, $stoplon"

    for { set lat $startlat } \
      { $lat > $stoplat } \
      { set lat [ expr $lat - 1 ] } {
  
      for { set lon $startlon } \
        { $lon < $stoplon } \
        { set lon [ expr $lon + 2 ] } {
  
        set latlon [ format "%f %f" $lat $lon ]
        set grid [ string range [ To_Grid $latlon ] 0 3 ]

        # TODO - make this work for 6-digit grids
        # perhaps the worked database does NOT need to retain 6 digits.

        set found 0

        if { $::setting(rules) == "old" } {

          set s [ string toupper [ string range $stuff(sent) 0 3 ] ]
          set sr [ concat $s "_" $grid ]

          if { [ info exists worked($stuff(mapband),$sr) ] } {
            set found $worked($stuff(mapband),$sr)
          }

        } else {

          if { [ info exist worked ] } {

            for { set handle [ array startsearch worked ]
              set index [ array nextelement worked $handle ] } \
              { $index != "" } \
              { set index [ array nextelement worked $handle ] } {

              set iband [ lindex [ split $index , ] 0 ]
              set igrid [ string range [ lindex [ split $index , ] 1 ] 0 3 ]

              if { $stuff(mapband) == $iband && $grid == $igrid } {
                incr found $worked($index)
              }
            }

            # finish traversal
            array donesearch worked $handle
          }
        }

        if { $found } {
          if { $found >= 5 } {
            $windows(maptext) insert insert $grid { hotworkedtag }
          } elseif { $found >= 2 } {
            $windows(maptext) insert insert $grid { warmworkedtag }
          } elseif { $found >= 1 } {
            $windows(maptext) insert insert $grid { coldworkedtag }
          } else {
            $windows(maptext) insert insert $grid { unworkedtag }
          }
        } else {
          $windows(maptext) insert insert $grid { unworkedtag }
        }

        $windows(maptext) insert insert " " { unworkedtag }
      }
      $windows(maptext) insert insert "\n"
    }
  }

  $windows(maptext) configure -state disabled
  # $windows(maptext) xview moveto 0.13333
  # $windows(maptext) yview moveto 0.13333
}

#
#  Popup_Keyer - procedure to bring the Keyer window up.
#

proc Popup_Keyer { } {
  global windows stuff

  wm deiconify $windows(keyer)
  raise $windows(keyer)
  focus $windows(m6entry)
  $windows(m6entry) icursor end
  $windows(m6entry) select range 0 end
}

#
#  Popup_Map - procedure to bring the map window up.
#

proc Popup_Map { center } {
  global windows stuff

  wm deiconify $windows(map)
  raise $windows(map)
  focus $windows(map)

  Redraw_Map $center
}

#
#  Popup_Debug - procedure to bring the Debug window up.
#

proc Popup_Debug { } {
  global windows stuff stat

  set stuff(debug) 1
  Set_Title
  wm deiconify $windows(debug)
  raise $windows(debug)
  focus $windows(debug)

  foreach b { Lookup_Add Lookup_Dupe Log_QSO Increment_Worked Log_Insert Add_To_Log Check_QSO Dupe_Check Save } {
    Debug "Stat" "$b,t = $stat($b,t)"
    Debug "Stat" "$b,n = $stat($b,n)"
  }

  Init_Stats
}

#
#  Popup_Hist - procedure to bring the Hist window up.
#

proc Popup_Hist { } {
  global windows stuff

  wm deiconify $windows(hist)
  raise $windows(hist)
  focus $windows(hist)
}

#
#  Popup_Loghead - procedure to bring the Log Header window up.
#

proc Popup_Loghead { } {
  global windows stuff

  wm deiconify $windows(loghead)
  raise $windows(loghead)
  focus $windows(loghead)
  Redraw_Score
}

#
#  Popup_Score - procedure to bring the score window up.
#

proc Popup_Score { } {
  global windows stuff

  wm deiconify $windows(score)
  raise $windows(score)
  focus $windows(score)
  Redraw_Score
}

#
# Brag
#

proc About { } {
  global stuff

  tk_messageBox -icon info -type ok -title About \
    -message "RoverLog version $stuff(rlversion)
by Tom Mayo

It's not just for rovers!

http://roverlog.2ub.org/"
}

proc Log_Insert { line } {
  global stat

  incr stat(Log_Insert,t) [ lindex [ time { Log_Insert_Stub $line } ] 0 ]
  incr stat(Log_Insert,n)
  
  return
}
        
proc Log_Insert_Stub { line } {
  global windows stuff

  lappend stuff(loglist) $line

  # $windows(loglist) insert end $line
  # $windows(loglist) itemconfigure end \
  #   -fg $::setting(logfg) -bg $::setting(logbg)
}

proc Update_ReadFile_Progress { } {
  global windows stuff

  set pct [ expr 100 * $stuff(readsize) / $stuff(filesize) ]
  if { [ expr $pct % 10 ] == 0 } {
    Annunciate "Loading Log: $pct %"
    $windows(loglist) see end
    update idletasks
  } 

}

#
# ReadFile - procedure to read in records from a file.
#

proc ReadFile { merge fid } {
  global windows stuff

  set got_a_qso 0
  while { [gets $fid line] >= 0 } {
    incr stuff(readsize) [ string length $line ]
    Update_ReadFile_Progress
    if { [ string equal -length 5 $line "QSO: " ] == 1 } {
      set got_a_qso 1
      if { [ string length $line ] == 79 } {
        binary scan $line "x5a5x1a2x1a10x1a4x1a13x5a6x1a13x5a6" \
          band mode date utc mycall sent call recd
      } else {
        binary scan $line "x5a5x1a2x1a10x1a4x1a13x5a6x1a13x5a4" \
          band mode date utc mycall sent call recd
      }

      set band [ string toupper [ string trim $band ] ]
      set mode [ string toupper [ string trim $mode ] ]
      set date [ string toupper [ string trim $date ] ]
      set utc [ string toupper [ string trim $utc ] ]
      set mycall [ string toupper [ string trim $mycall ] ]
      set sent [ string toupper [ string trim $sent ] ]
      set call [ string toupper [ string trim $call ] ]
      set recd [ string toupper [ string trim $recd ] ]

      # fix date
      if { [ string first "/" $date ] != -1 } {
        binary scan $date "a2x1a2x1a4" month day year
        set date "$year-$month-$day"
      }

      # fix band
      if { $band == "1.2" } { set band "1.2G" }
      if { $band == "2.3" } { set band "2.3G" }
      if { $band == "3.4" } { set band "3.4G" }
      if { $band == "5.7" } { set band "5.7G" }
      if { $band == "10"  } { set band "10G" }
      if { $band == "24"  } { set band "24G" }
      if { $band == "47"  } { set band "47G" }
      if { $band == "76"  } { set band "76G" }
      if { $band == "119" } { set band "119G" }
      if { $band == "142" } { set band "142G" }
      if { $band == "241" } { set band "241G" }
      if { $band == "300" } { set band "300G" }

      # rewrite fixed line
      set line [format "QSO: %-5.5s %-2.2s %-10.10s %-4.4s %-13.13s     %-6.6s %-13.13s     %-6.6s" \
          $band $mode $date $utc $mycall $sent $call $recd]

      # Dupes are allowed in the log, but not in the worked or lookup databases
      if { [ Check_QSO "quiet" $band $date $utc $sent $call $recd ] == 0 } {
        if { [ Dupe_Check "strict" "quiet" $band $date \
          $utc $sent $call $recd ] == 0 } {
          Increment_Worked $band $sent $recd "quiet"
        }
        Lookup_Add $band $call $sent $recd

        Log_Insert $line
      }
    } else {
      # Only jam non-QSO lines into the header if we are not merging.
      if { $merge != "merge" } {
        if { [ string equal -length 11 $line "END-OF-LOG:" ] != 1 } {
          $windows(logheadtext) insert end $line
          $windows(logheadtext) insert end "\n"
        }
      }
    }
  }

  # ditch crap line
  if { $merge != "merge" } {
    $windows(logheadtext) delete "end -1 line" end
    $windows(loglist) see end
  }

  # it turns out this is useful for restarting
  if { $got_a_qso == 1 } {
    if { [ string toupper $::setting(myband) ] == "NONE" } {
      set stuff(band) $band
      # If done prior to comms readiness with Keyer, it gets blacklisted.
      # Set_Freq noexec
    }
    if { [ string toupper $::setting(mymode) ] == "NO" } {
      set stuff(mode) $mode
    }
    set stuff(lastbandqsy) $stuff(band)
    set ::setting(mycall) $mycall
    set stuff(sent) $sent
    set stuff(call) $call
    set stuff(lastcall) $call
    set stuff(recd) $recd
    set stuff(lastrecd) $recd
  }

  set stuff(readsize) $stuff(filesize)
  Update_ReadFile_Progress

  # Update the call stack

  set lend [ llength $stuff(loglist) ]
  incr lend -1
  set lstart [ expr $lend - 6 ]

  foreach b [ lrange $stuff(loglist) $lstart $lend ] {
    if { [ string length $b ] == 79 } {
      binary scan $b "x55a13x5a6" call recd
    } else {
      binary scan $b "x55a13x5a4" call recd
    }

    set call [ string toupper [ string trim $call ] ]
    set recd [ string toupper [ string trim $recd ] ]

    Call_Stack_Push $call $recd
  }


  return [$windows(loglist) index end]
}

#
# Open - procedure to open a file and read in the records.  Clear the
#        current log first.  Allow the user to confirm blowing away the
#        current log.
#

proc Open { merge } {
  global windows stuff

  set conf "ok"

  if { $stuff(unsaved) == 1 } {
    if { $merge == "merge" } {
      set conf [ tk_messageBox -icon warning -type okcancel \
        -title "Confirm Open" -message \
"If you open a new file now, you will lose unsaved information." ]
    }
  }

  if { $conf == "ok" } {

    set types {
      {{Cabrillo Files} {.log}}
      {{All Files} *}
    }
    set fn [tk_getOpenFile -initialfile $::setting(logfile) -defaultextension ".log" -filetypes $types]

    if { $fn == "" } {
      return
    } else {
      # Only take the new file name if we are not merging.
      if { $merge != "merge" } {
        set ::setting(logfile) $fn
        Set_Title
      }
    }

    if [file readable $fn] {
      set stuff(filesize) [ file size $fn ]
      set fid [open $fn r]
      if { $merge == "open" } { Init }
      set stuff(entries) [ ReadFile $merge $fid ]
      close $fid
      if { $merge == "merge" } { set stuff(unsaved) 1 }
    } else {
      tk_messageBox -icon error -type ok \
        -title "Oops" -message "Cannot open the requested file."
    }
  }
}

#
# Busy - Procedure to set the busy timer to an integer number of minutes
#        to be counted down.
#

proc Busy { min } {
  global stuff

  if { [ info exists stuff(busyafterjob) ] } {
    after cancel $stuff(busyafterjob)
  }

  Debug "Busy" "min=$min"
  set stuff(busy) $min

  # Update the other stations
  Net_Send "wip" "all" ""
  
  if { $min == 0 } { return }
  incr min -1
  if { $min >= 0 } {
    set stuff(busyafterjob) [ after 60000 Busy $min ]
  }
}

#
# Set_Time_From_PC - procedure to get the time of day from the PC
#                    and set RoverLog's date and UTC fields.
#

proc Set_Time_From_PC { } {
  global windows stuff

  set t [expr $stuff(utcoffset) * 3600 + [clock seconds]]
  set stuff(date) [clock format $t -format "%Y-%m-%d"]
  set stuff(utc) [clock format $t -format "%H%M"]
}

#
# Band_Number - figure out what index into ::setting(rn) goes with the
#               the given band.
#

proc Band_Number { b } {

  for { set i 1 } { $i < 18 } { incr i } {
    if { $b == [ lindex $::setting(r$i) 0 ] } {
      return $i
    }
  }
  return 1
}

#
# Set_Freq - Based on the band and settings for that band, update the
#            frequency display.
#
# exec_or_noexec - if != "noexec" go ahead and send the IF frequency
#                  to the rig and do the band change command that is
#                  configured.
#

proc Set_Freq { exec_or_noexec } {
  global windows stuff .

  # Set status for Station Info window from focus
  set w [ focus -displayof . ]
  if { $w != "" } {
    set w [ winfo toplevel $w ]
  }
  if { $w == "" || $w == "." } {
    if { $stuff(call) == "" } {
      set stuff(stat) "IDLE"
    } else {
      set stuff(stat) "$stuff(call) $stuff(recd)"
    }
  } else {
    set stuff(stat) "\[[string toupper [ string index $w 1]][ string range $w 2 end ]\]"
  }
  
  # Figure out which band this is
  set bandno [ Band_Number $stuff(band) ]

  # Send rig number to keyer
  Send_Rig_Num_To_Keyer [ lindex $::setting(r$bandno) 1 ]

  # Do stuff if we just changed bands.
  if { $stuff(lastbandset) != $stuff(band) } {

    # Do not execute the command if we are instructed not to or if we are 
    # changing the band due to editing a QSO.

    if { $exec_or_noexec != "noexec" && $stuff(editing) == 0 } {

      # Execute the external command (if any) based upon the band.
      set cmd [ lrange $::setting(r$bandno) 4 end ]

      # Execute the command
      catch [ eval $cmd ]
    }

    set stuff(lastbandset) $stuff(band)
  }

  # Set which port (if any) to connect to. 0 means manual entry.
  set rigport [ lindex $::setting(r$bandno) 2 ]
  
  # if this band has a non-zero port number, we need to get the rig freq.
  if { $rigport != 0 } {

    if { $stuff(blacklist,r$bandno) == 1 } {

      # I wish we didn't have to do this here, but we may have just
      # QSY'd from a non-blacklisted band, and we don't want to blindly
      # unblacklist bands every time we QSY.  This could lead to net delays.
      $windows(rigfreqbutton) configure -fg red

      set stuff(rigfreq) "0.0000"
      set stuff(opfreq)  "0.0000"

      Debug "Set_Freq" "Rig $bandno is blacklisted. Skipping."
      return
    }

    # query freq
    Rig_Puts $bandno "freq?"
    set freq [ Rig_Gets $bandno ]

    # query mode
    Rig_Puts $bandno "mode?"
    set mode [ Rig_Gets $bandno ]

    # check the frequency
    if { [ scan $freq "%f" rigfreq ] == 1 } {

      # set the rig frequency
      set rigfreq [ format "%6.4f" $rigfreq ]
      set stuff(rigfreq) $rigfreq

      # set the operating frequency
      set lofreq [ lindex $::setting(r$bandno) 3 ]
      set lofreq [ format "%6.4f" $lofreq ]
      set opfreq [ expr abs($lofreq + $rigfreq) ]
      set stuff(opfreq) [ format "%6.4f" $opfreq ]
    }

    # check the mode
    Debug "Set_Freq" "mode = $mode"
    if { [ lsearch -exact $::setting(modes) $mode ] >= 0 } {
      Debug "Set_Freq" "Setting mode"
      set stuff(mode) $mode
    }
  }

  # Tell the net what the frequency is.
  Net_Send "frq" "all" ""
}

#
# Open_Rotor
#

proc Open_Rotor { } {
  global stuff

  if { $::setting(rotoripport) == 0 } {
    return
  }

  # open connection to rotor server
  if [catch {socket -async $::setting(rotoripaddr) $::setting(rotoripport)} stuff(rotorsid) ] {
    Blacklist "rotor" "connection failed"
    unset stuff(rotorsid)
    return
  }

  # set up the descriptor
  if [ catch { fconfigure $stuff(rotorsid) -buffering line -blocking 0 } ] {
    Blacklist "rotor" "configuration failed"
    return
  }

  set stuff(rotorstatus) "Open"
  set stuff(rotortime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
}

proc Close_Rotor { quit } {
  global stuff

  if { [ info exist stuff(rotorsid) ] } {
    catch { fconfigure $stuff(rotorsid) -blocking 1 }
    if { $quit == "quit" } {
      catch { puts $stuff(rotorsid) "quit!" }
    }
    catch { close $stuff(rotorsid) }
    catch { unset stuff(rotorsid) }
  }

  set stuff(rotorstatus) "Closed"
  set stuff(rotortime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
}

#
# Rotor_Puts - Replacement puts for sending to a Rotor with
# error detection and blacklisting if merited.
#

proc Rotor_Puts { m } {
  global stuff

  # skip if not configured
  if { $::setting(rotoripport) == 0 } {
    return
  }

  # skip if blacklisted
  if { $stuff(blacklist,rotor) == 1 } {
    return
  }

  Debug "Rotor_Puts" "Sending $m"

  if { [ catch { puts $stuff(rotorsid) $m } r ] } {
    Blacklist "rotor" "puts failed: $r"
    return
  }

  # flush $stuff(rotorsid)

  set stuff(rotorstatus) "$m"
  set stuff(rotortime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
}

#
# Rotor_Gets - Replacement gets for getting from a Rotor with
# error detection and blacklisting if merited.
#

proc Rotor_Gets { } {
  global stuff

  # skip if not configured
  if { $::setting(rotoripport) == 0 } {
    return
  }

  # skip if blacklisted
  if { $stuff(blacklist,rotor) == 1 } {
    return
  }

  if { [ catch { gets $stuff(rotorsid) } m ] } {
    Blacklist "rotor" "gets failed"
    set m "0.0"
  }

  Debug "Rotor_Gets" "Received $m"

  set stuff(rotorstatus) "$m"
  set stuff(rotortime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]

  return $m
}

#
# Query_Rotor - procedure to get rotor position from rotor server.
#

proc Query_Rotor { } {
  global stuff

  # send position query
  Rotor_Puts "pos?"

  set stuff(rotorpos) [ Rotor_Gets ]

  return
}

#
# Move_Rotor - procedure to send rotor position to rotor server.
#

proc Move_Rotor { } {
  global stuff

  # This is how we Unblacklist the rotor
  Unblacklist "rotor"

  # send position
  Rotor_Puts "pos! $stuff(rotorbrng)"

  return
}

#
# Open_GPS
#

proc Open_GPS { } {
  global stuff

  if { $::setting(gpsipport) == 0 } {
    return
  }

  # open connection to gps server
  if [catch {socket -async $::setting(gpsipaddr) $::setting(gpsipport)} stuff(gpssid) ] {
    Blacklist "gps" "connection failed"
    return
  }

  # set up the descriptor
  if [ catch { fconfigure $stuff(gpssid) -buffering line -blocking 1 } ] {
    Blacklist "gps" "configuration failed"
    return
  }

  set stuff(gpsstatus) "Open"
  set stuff(gpstime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
}

proc Close_GPS { quit } {
  global stuff

  if { [ info exist stuff(gpssid) ] } {
    catch { fconfigure $stuff(gpssid) -blocking 1 }
    if { $quit == "quit" } {
      catch { puts $stuff(gpssid) "quit!" }
    }
    catch { close $stuff(gpssid) }
    catch { unset stuff(gpssid) }
  }

  set stuff(gpsstatus) "Closed"
  set stuff(gpstime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
}

#
# GPS_Puts - Replacement puts for sending to a GPS with
# error detection and blacklisting if merited.
#

proc GPS_Puts { m } {
  global stuff

  # skip if not configured
  if { $::setting(gpsipport) == 0 } {
    return
  }

  # skip if blacklisted
  if { $stuff(blacklist,gps) == 1 } {
    return
  }
  Debug "GPS_Puts" "Sending $m"

  if { [ catch { puts $stuff(gpssid) $m } r ] } {
    Blacklist "gps" "puts failed: $r"
    return
  }

  # flush $stuff(gpssid)

  set stuff(gpsstatus) "$m"
  set stuff(gpstime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]
}

#
# GPS_Gets - Replacement gets for getting from a GPS with
# error detection and blacklisting if merited.
#

proc GPS_Gets { } {
  global stuff

  # skip if not configured
  if { $::setting(gpsipport) == 0 } {
    return
  }

  # skip if blacklisted
  if { $stuff(blacklist,gps) == 1 } {
    return
  }

  if { [ catch { gets $stuff(gpssid) } m ] } {
    Blacklist "gps" "gets failed"
    set m ""
  }

  Debug "GPS_Gets" "Received $m"

  set stuff(gpsstatus) "$m"
  set stuff(gpstime) [ clock format [ clock seconds ] -format {%Y-%m-%d %H:%M:%S} ]

  return $m
}

#
# Set_Grid - procedure to set stuff from GPS data.
#

# note: Set_Grid is only to be called if ::setting(gps) == 1.

proc Set_Grid { } {
  global windows stuff

  # ask for grid 
  GPS_Puts "grid?"

  # get response and continue
  set r [ GPS_Gets ]
  set r [ string toupper $r ]
  if { [ Valid_Grid $r ] } {
    set stuff(sent) $r
    Bear_Calc $stuff(sent) $stuff(recd)
  } else {
    Annunciate "Invalid/Missing GPS Data"
    Blacklist "gps" "grid syntax error"
  }

  # set declination
  GPS_Puts "dec?"
  set r [ GPS_Gets ]
  if { [ scan $r "%f %s" fdec hdec ] == 2 } {
    if { $hdec == "W" } {
      set ::setting(declination) [ expr -$fdec ]
    } else {
      set ::setting(declination) $fdec
    }
  }

  GPS_Puts "speed?"
  set r [ GPS_Gets ]
  if { [ scan $r "%f" stuff(speed) ] != 1 } {
    set stuff(speed) 0
  }

  GPS_Puts "course?"
  set r [ GPS_Gets ]
  if { [ scan $r "%f" stuff(course) ] != 1 } {
    set stuff(course) 0
  }
 
  return
}

proc Init_Stats { } {
  global stat

  # clear stats
  set stat(Lookup_Add,t) 0
  set stat(Lookup_Add,n) 0
  set stat(Lookup_Dupe,t) 0
  set stat(Lookup_Dupe,n) 0
  set stat(Log_QSO,t) 0
  set stat(Log_QSO,n) 0
  set stat(Increment_Worked,t) 0
  set stat(Increment_Worked,n) 0
  set stat(Log_Insert,t) 0
  set stat(Log_Insert,n) 0
  set stat(Add_To_Log,t) 0
  set stat(Add_To_Log,n) 0
  set stat(Check_QSO,t) 0
  set stat(Check_QSO,n) 0
  set stat(Dupe_Check,t) 0
  set stat(Dupe_Check,n) 0
  set stat(Save,t) 0
  set stat(Save,n) 0
}

#
#  Init - procedure to create and clear all non-option globals.
#

proc Init { } {
  global windows stuff worked activated lookup call_stack

  Init_Stats

  # set defaults
  set stuff(lastrignum) 0
  set stuff(readsize) 0
  set stuff(lineno) -1
  set stuff(mapcenter) ""
  set stuff(entries) 0
  set stuff(call) ""
  set stuff(lastcall) ""
  set stuff(peername) "all"
  set stuff(skedpeer) $::setting(mypeername)
  set stuff(wip) 0
  set stuff(lastwip) 0
  set stuff(lastwiplimit) 0
  set stuff(skedwip) 0
  set stuff(busy) 0
  set stuff(lastbusy) 0
  set stuff(skedbusy) 0
  set stuff(skedwiplimit) 0
  set stuff(lastlookuprecdcall) ""
  set stuff(lookup_recd_state) "unlocked"
  set stuff(lookuptype) ""
  if { [ info exists ::setting(wiplimit) ] } {
    set stuff(skedwiplimt) $::setting(wiplimit)
  } else {
    set stuff(skedwiplimit) 0
  }
  # check for default home grid
  if { [ info exists ::setting(mygrid) ] } {
    set stuff(sent) $::setting(mygrid)
  } else {
    set stuff(sent) ""
  }

  set stuff(course) 0
  set stuff(speed) 0

  # set default band
  if { [ Valid_Band $::setting(myband) ] == 1 } {
    set stuff(band) $::setting(myband)
  } else {
    set stuff(band) [lindex $::setting(bands) 0]
  }
  set stuff(lastbandqsy) $stuff(band)
  set stuff(lastbandset) 0

  set stuff(delaycounter) 5
  # Set default frequencies.
  set stuff(rigctrl) 0
  set stuff(lofreq) "0.0000"
  set stuff(rigfreq) "0.0000"
  set stuff(opfreq) "0.0000"

  # Find this band in the ::setting(rn) array.
  for { set i 1 } { $i < 18 } { incr i } {
    if { [ lindex $::setting(r$i) 0 ] == $stuff(band) } {

      # If this band uses the rig server...
      if { [ lindex $::setting(r$i) 2 ] != 0 } {

        set stuff(rigctrl) 1

        # Set the display frequencies.
        set lofreq [ lindex $::setting(r$i) 3 ]
        set lofreq [ format "%6.4f" $lofreq ]
        set stuff(lofreq) $lofreq
        set stuff(rigfreq) "0.0000"
        set stuff(opfreq) $lofreq
        set stuff(skedfreq) $lofreq

      # Otherwise this band uses manual entry.
      } else {

        set stuff(rigctrl) 0

        # Set the display frequencies.
        set stuff(lofreq) "0.0000"
        set stuff(rigfreq) "0.0000"
        set opfreq [ lindex $::setting(r$i) 3 ]
        set opfreq [ format "%6.4f" $opfreq ]
        set stuff(opfreq) $opfreq
        set stuff(skedfreq) $opfreq

      }
    }
  }

  # set default mode
  if { [ info exists ::setting(mymode) ] && $::setting(mymode) != "NO" \
    && [ Valid_Mode $::setting(mymode) ] == 1 } {
    set stuff(mode) $::setting(mymode)
  } else {
    set stuff(mode) [lindex $::setting(modes) 0]
  }

  # set more defaults
  set stuff(recd) ""
  set stuff(lastrecd) ""
  set stuff(leavingcallentry) 0
  set stuff(realtime) 1
  $windows(dateentry) configure -state readonly
  $windows(utcentry) configure -state readonly
  set stuff(editing) 0
  set stuff(unsaved) 0
  set stuff(logcount) 0
  Set_Time_From_PC
  $windows(loglist) delete 0 end

  # Unblacklist everything to start
  # Nasty to not use the official method, but
  # actually we don't want to reconnect to
  # everything, so this is a good compromise.

  # Keyer
  set stuff(blacklist,keyer) 0
  # GPS
  set stuff(blacklist,gps) 0
  # Rotor
  set stuff(blacklist,rotor) 0
  # Lookup
  set stuff(blacklist,super) 0
  # Rigs
  for { set i 1 } { $i < 18 } { incr i } {
    set stuff(blacklist,r$i) 0
  }
  for { set i 1 } { $i < 13 } { incr i } {
    set stuff(blacklist,p$i) 0
  }

  # clear worked database
  if { [ info exists worked ] } {
    unset worked
  }

  # clear activated database
  if { [ info exists activated ] } {
    unset activated
  }

  # clear lookup database
  if { [ info exists lookup ] } {
    unset lookup
  }

  # clear call stack
  for { set i 0 } { $i < 5 } { incr i } {
    set call_stack($i) [ list "" "" ]
  }

  foreach band $::setting(bands) {
    set bandno [ Band_Number $band ]
    if { [ lindex $::setting(r$bandno) 2 ] == 0 } {
      set stuff(lastopfreq,$band) [ lindex $::setting(r$bandno) 3 ]
    } else {
      set stuff(lastopfreq,$band) 0.0
    }
    set stuff(lastopmode,$band) "PH"
  }
}

#
# New_Loghead - procedure to fill in header information.
#

proc New_Loghead { } {
  global windows stuff

    $windows(logheadtext) insert end "START-OF-LOG: 3.0\n"
    $windows(logheadtext) insert end "CREATED-BY: ROVERLOG $stuff(rlversion)\n"
    $windows(logheadtext) insert end "LOCATION: WMA\n"
    $windows(logheadtext) insert end "CONTEST: ARRL-VHF-JAN\n"
    $windows(logheadtext) insert end "CALLSIGN: N0NE\n"
    $windows(logheadtext) insert end "CATEGORY-ASSISTED: NON-ASSISTED\n"
    $windows(logheadtext) insert end "CATEGORY-BAND: 2M\n"
    $windows(logheadtext) insert end "CATEGORY-MODE: MIXED\n"
    $windows(logheadtext) insert end "CATEGORY-OPERATOR: MULTI-OP\n"
    $windows(logheadtext) insert end "CATEGORY-POWER: HIGH\n"
    $windows(logheadtext) insert end "CATEGORY-STATION: FIXED\n"
    $windows(logheadtext) insert end "CATEGORY-TIME: 24-HOURS\n"
    $windows(logheadtext) insert end "CATEGORY-TRANSMITTER: UNLIMITED\n"
    $windows(logheadtext) insert end "CATEGORY-OVERLAY: ROOKIE\n"
    $windows(logheadtext) insert end "CLAIMED-SCORE: 0\n"
    $windows(logheadtext) insert end "OPERATORS: N0OP N0ONE\n"
    $windows(logheadtext) insert end "CLUB: RoverLog Amateur Radio Club\n"
    $windows(logheadtext) insert end "NAME: Nobody\n"
    $windows(logheadtext) insert end "EMAIL: n0ne@nowhere.com\n"
    $windows(logheadtext) insert end "ADDRESS: 123 Nowhere St.\n"
    $windows(logheadtext) insert end "ADDRESS: Noplace, NO  00000\n"
    $windows(logheadtext) insert end "ADDRESS: USA\n"
    $windows(logheadtext) insert end "SOAPBOX: RoverLog is terrific!\n"
    $windows(logheadtext) insert end "SOAPBOX: \n"
    $windows(logheadtext) insert end "SOAPBOX: \n"
}

#
# New - procedure to wipe out log and all fields to start fresh.
#

proc New { } {
  global windows stuff worked

  set conf "ok"

  set conf [ tk_messageBox -icon warning -type okcancel \
    -title "Confirm New Log" -message \
    "Are you sure you wish to start a new log?" ]

  if { $conf == "ok" } {
    Init

    # Generate the header
    $windows(logheadtext) delete 0.0 end
    New_Loghead
    set ::setting(logfile) "untitled.log"
    Set_Title
  }
}

#
# Dupe_Check - Goes through the log looking for an entry with the same
#              band, call, sent grid, and received grid.  If a duplicate
#              is found, prompts to confirm logging it.  Returns 0 if
#              it is ok to log the contact, either because there is no
#              dupe or because the operator still wants to log it.
#
# strict returns that there is a dupe if we just found the info in the
#   lookup database without checking the log.
#
# quiet does not prompt the user at all.
#

proc Dupe_Check { strict quiet band date utc sent call recd } {
  global stat

  incr stat(Dupe_Check,t) [ lindex [ time { set r [ Dupe_Check_Stub $strict $quiet $band $date $utc $sent $call $recd ] } ] 0 ]
  incr stat(Dupe_Check,n)

  return $r
}

proc Dupe_Check_Stub { strict quiet band date utc sent call recd } {
  global windows

  # Step 1 - Find out if it's even worth going in the log to get all
  #          the QSO information by looking in the lookup database.
  if { [ Lookup_Dupe $band $sent $call $recd ] == 0 } {
    Debug "Dupe_Check" "No dupe in lookup database"
    return 0
  }

  # strict means do not allow the user to override and log a dupe.
  if { $strict == "strict" } {
    Debug "Dupe_Check" "Found dupe in lookup database"
    return 1
  }

  # Step 2 - Ok, we did work this guy from here to there on this band,
  #          now parse the whole log for the exact QSO to prompt the user.
  
  set stuff(lineno) 0
  set bunch [$windows(loglist) get 0 end]

  # sift through the log
  # TODO - try using lsearch here!
  foreach b $bunch {

    # parse out the line
    binary scan $b "x5a5x1x2x1a10x1a4x1x13x5a6x1a13x5a6" \
      lband ldate lutc lsent lcall lrecd
    set lband [ string toupper [ string trim $lband ] ]
    set lcall [ string toupper [ string trim $lcall ] ]
    set lsent [ string toupper [ string trim $lsent ] ]
    set lrecd [ string toupper [ string trim $lrecd ] ]

    # Drop /X from calls for purposes of checking.
    set lcall [ Drop_Slash "rover" $lcall ]
    set ccall [ Drop_Slash "rover" $call ]

    if { $::setting(rules) == "dist" || $::setting(rules) == "grid6" } {
      set gridend 5
      if { [ string length $sent ] < 6 } {
        set sent [ string range $sent 0 3 ]
        set sent "${sent}MM"
      }
      if { [ string length $recd ] < 6 } {
        set recd [ string range $recd 0 3 ]
        set recd "${recd}MM"
      }
      if { [ string length $lsent ] < 6 } {
        set lsent [ string range $lsent 0 3 ]
        set lsent "${lsent}MM"
      }
      if { [ string length $lrecd ] < 6 } {
        set lrecd [ string range $lrecd 0 3 ]
        set lrecd "${lrecd}MM"
      }
    } else {
      set gridend 3
    }

    # check the QSOs to see if they match
    # Debug "Dupe_Check" "Comparing $band vs. $lband, $ccall vs. $lcall, $sent vs. $lsent, and $recd vs. $lrecd"
    if { $band == $lband && $ccall == $lcall && \
      [ string range $sent 0 $gridend ] == [ string range $lsent 0 $gridend ] && \
      [ string range $recd 0 $gridend ] == [ string range $lrecd 0 $gridend ] } {

      # highlight the dupe
      if { $quiet != "quiet" } {
        focus $windows(loglist)
        $windows(loglist) activate $stuff(lineno)
        $windows(loglist) selection clear 0 end
        $windows(loglist) selection set $stuff(lineno)
        $windows(loglist) see $stuff(lineno)
        Debug "Dupe_Check" "Dupe on line number $stuff(lineno)"
        set msg [ format "Duplicate entry on %s at %s, log anyway?" \
          $ldate $lutc ]
        set conf [ tk_messageBox -icon warning -type okcancel \
          -title "Dupe" -default "ok" -message $msg ]
        if { $conf == "ok" } {
          set stuff(lineno) -1
          return 0
        }
      }
      # don't forget to end the loop
      break
    }
    incr stuff(lineno)
  }
  set stuff(lineno) -1
  return 1
}

# 
# Save - procedure to store the current log.  Allows the user to confirm
#        overwriting an existing file.
#

proc Save { As } {
  global stat

  incr stat(Save,t) [ lindex [ time { Save_Stub $As } ] 0 ]
  incr stat(Save,n)
}

proc Save_Stub { As } {
  global windows stuff

  # Update Claimed Score in Log Header
  set rlvline [ $windows(logheadtext) search -forward \
    "CREATED-BY:" 1.0 end ]
  if { $rlvline >= 0 } {
    $windows(logheadtext) delete \
      "$rlvline linestart" "$rlvline lineend"
    $windows(logheadtext) insert $rlvline \
      "CREATED-BY: ROVERLOG $stuff(rlversion)"
  }

  set logfile $::setting(logfile)

  if { $As == "As" || $::setting(logfile) == "untitled.log" } {
    set types {
      {{Cabrillo Files} {.log}}
      {{All Files} *}
    }

    set ::setting(logfile) [tk_getSaveFile -initialfile $::setting(logfile) -defaultextension ".log" -filetypes $types ]

    if { $::setting(logfile) == "" } {
      set ::setting(logfile) $logfile
      return
    }
  }

  Save_Cabrillo
  Set_Title

  if { $As == "As" } {
    Annunciate "Log Saved"
  }
  set stuff(unsaved) 0
  Save_Skeds
  Save_Lookup
  if { $::setting(rules) == "old" } {
    # save summary if using old rules
    Save_Summary
  }
  return
}

proc Export { } {
  global windows stuff

  # Update Claimed Score in Log Header
  set rlvline [ $windows(logheadtext) search -forward \
    "CREATED-BY:" 1.0 end ]
  if { $rlvline >= 0 } {
    $windows(logheadtext) delete \
      "$rlvline linestart" "$rlvline lineend"
    $windows(logheadtext) insert $rlvline \
      "CREATED-BY: ROVERLOG $stuff(rlversion)"
  }

  set types {
    {{ADIF Files} {.adf}}
    {{10 GHz Log Files} {.10g}}
    {{All Files} *}
  }

  set logfile [tk_getSaveFile -initialfile [ file rootname \
    $::setting(logfile) ] -defaultextension ".adf" -filetypes $types ]

  if { $logfile == "" } {
    return
  }

  set x [ file extension $logfile ]

  if { $x == ".adf" } {
    Export_ADIF $logfile
    Annunciate "ADIF Log Exported"
  } elseif { $x == ".10g" } {
    Export_10G $logfile
    Annunciate "10 GHz Log Exported"
  } else {
    tk_messageBox -icon error -type ok \
      -title "Oops" -message "RoverLog does not know how to export to the $x format."
  }
    
  return
}

proc Save_Cabrillo { } {
  global windows stuff

  set fid [open $::setting(logfile) w 0666]

  set bunch [$windows(logheadtext) get 1.0 end ]
  puts -nonewline $fid $bunch

  set bunch [$windows(loglist) get 0 end]
  foreach b $bunch {

    # binary scan $b "x5a5x1a2x1a10x1a4x1a13x5a6x1a13x5a6" \
    #   band mode date utc mycall sent call recd

    # set recd [ string range $recd 0 3 ][ string tolower [ string range $recd 4 5 ] ]
    # set sent [ string range $sent 0 3 ][ string tolower [ string range $sent 4 5 ] ]

    # set bb [ format "QSO: %-5.5s %-2.2s %-10.10s %-4.4s %-13.13s     %-6.6s %-13.13s     %-6.6s" \
    #       $band $mode $date $utc $mycall $sent $call $recd ]

    if { $::setting(rules) == "old" } {
      # TODO - need to print new multipliers here
      # puts $fid "$bb"
      puts $fid "$b"
    } else {
      # puts $fid "$bb"
      puts $fid "$b"
    }
  }

  puts $fid "END-OF-LOG:"
  close $fid
}

proc Export_ADIF { fn } {
  global windows stuff

  set fid [open $fn w 0666]

  # TODO - Need to figure out what to do with the header.
  # set bunch [$windows(logheadtext) get 1.0 end ]
  # puts -nonewline $fid $bunch

  set bunch [$windows(loglist) get 0 end]
  foreach b $bunch {

    # parse Cabrillo line into ADIF line.
    binary scan $b "x5a5x1a2x1a10x1a4x1a13x5a6x1a13x5a6" \
      band mode date utc mycall sent call recd

    # fix band
    set band [ string toupper [ string trim $band ] ]
    switch -exact -- $band {
      "50" {
        set band "6m"
      }
      "144" {
        set band "2m"
      }
      "222" {
        set band "1.25m"
      }
      "432" {
        set band "70cm"
      }
      "902" {
        set band "33cm"
      }
      "1.2G" {
        set band "23cm"
      }
      "2.3G" {
        set band "13cm"
      }
      "3.4G" {
        set band "9cm"
      }
      "5.7G" {
        set band "6cm"
      }
      "10G" {
        set band "3cm"
      }
      "24G" {
        set band "1.25cm"
      }
      "47G" {
        set band "6mm"
      }
      "76G" {
        set band "4mm"
      }
      "119G" {
        set band "2.5mm"
      }
      "142G" {
        set band "2mm"
      }
      "241G" {
        set band "1.25mm"
      }
      "300G" {
        set band "1mm"
      }
      default {
        set band "UNKNOWN"
      }
    }
    set bandl [ string length $band ]

    # fix mode
    set mode [ string toupper [ string trim $mode ] ]
    switch -exact -- $mode {
      "PH" {
        set mode "SSB"
      }
      "RY" { 
        set mode "RTTY"
      }
      default {
      }
    }
    set model [ string length $mode ]

    set date [ string toupper [ string trim $date ] ]
    set date "[ string range $date 0 3 ][ string range $date 5 6 ][ string range $date 8 9 ]"
    set datel [ string length $date ]

    set utc [ string toupper [ string trim $utc ] ]
    set utc "${utc}00"
    set utcl [ string length $utc ]

    set mycall [ string toupper [ string trim $mycall ] ]
    set mycalll [ string length $mycall ]

    set sent [ string toupper [ string trim $sent ] ]
    set sentl [ string length $sent ]

    set call [ string toupper [ string trim $call ] ]
    set calll [ string length $call ]

    set recd [ string toupper [ string trim $recd ] ]
    set recdl [ string length $recd ]

    set line "<CALL:$calll>$call <BAND:$bandl>$band <MODE:$model>$mode <QSO_DATE:$datel>$date <TIME_ON:$utcl>$utc <RST_SENT:$sentl>$sent <RST_RCVD:$recdl>$recd <GRIDSQUARE:$recdl>$recd <EOR>"

    puts $fid "$line"
  }

  close $fid
}

proc Export_10G { fn } {
  global windows stuff

  catch { unset distbased }

  set fid [open $fn w 0666]

  puts $fid "   Date    UTC      Call       Sent   Recd   Band  Dist (km)  QSO Points"
  puts $fid "---------- ---- ------------- ------ ------ ------ --------- -----------"

  set bunch [$windows(loglist) get 0 end]

  foreach b $bunch {

    binary scan $b "x5a5x1a2x1a10x1a4x1a13x5a6x1a13x5a6" \
      band mode date utc mycall sent call recd

    set call [ string trim $call ]
    set band [ string trim $band ]
    set sent [ string toupper $sent ]
    set recd [ string toupper $recd ]

    set distkm [ Dist_Calc_Km $sent $recd ]
    set distkm [ expr int($distkm) ]

    if { $distkm >= 1 } {

      # Get rid of "/" stuff. Rules say you can't work a guy again
      # with different slash stuff.
      set qsocall [ Drop_Slash "first" $call ]

      # Set up the distance-based points by band.
      set j 0
      foreach b $::setting(bands) {
        set distbased_pts($b) [ lindex $::setting(bandpts) $j ]
        incr j
      }
  
      # Accumulate QSOs by band.
      set r [ array get distbased "$qsocall,$band,*" ]
      Debug "Export_10G" "Search for $qsocall on $band returned \"$r\"."
      if { [ llength $r ] == 0 } {
        Debug "Export_10G" "Don't have this call on this band yet.  Adding QSO points."
        set qsopts $distbased_pts($band)
        set distbased($qsocall,$band,$sent,$recd) $distkm
      } else {
        Debug "Export_10G" "Already have this call on this band.  Not adding QSO points."
        set qsopts 0
      }
    } else {
      set qsopts 0
    }

    set line [ format "%-10.10s %-4.4s %-13.13s %-6.6s %-6.6s %-5.5s %10d %11d" \
      $date $utc $call $sent $recd $band $distkm $qsopts ]

    puts $fid "$line"
  }

  close $fid
}

#
# Compares - procedure to compare two entries for sorting the log.
#

proc ComparebyTime { a b } {

  binary scan $a "x5x5x1x2x1a15" adate
  binary scan $b "x5x5x1x2x1a15" bdate

  set res [string compare $adate $bdate]
  if {$res != 0} {
    return $res
  } else {
    return [string compare $adate $bdate]
  }
}

proc ComparebySent { a b } {

  binary scan $a "x48a6" asent
  binary scan $b "x48a6" bsent

  set res [string compare $asent $bsent]
  if {$res != 0} {
    return $res
  } else {
    return [string compare $asent $bsent]
  }
}

proc ComparebyRecd { a b } {

  binary scan $a "x73a6" arecd
  binary scan $b "x73a6" brecd

  set res [string compare $arecd $brecd]
  if {$res != 0} {
    return $res
  } else {
    return [string compare $arecd $brecd]
  }
}

proc ComparebyCall { a b } {

  binary scan $a "x55a13" acall
  binary scan $b "x55a13" bcall

  set acall [ string trim [ Drop_Slash "first" $acall ] ]
  set bcall [ string trim [ Drop_Slash "first" $bcall ] ]
  Debug "ComparebyCall" "$acall vs. $bcall"

  return [string compare $acall $bcall]
}

proc ComparebyBand { a b } {
  global stuff

  binary scan $a "x5a3" aband
  set aband [string trim $aband]
  set ai [lsearch -exact $::setting(bands) $aband]

  binary scan $b "x5a3" bband
  set bband [string trim $bband]
  set bi [lsearch -exact $::setting(bands) $bband]

  if { $ai > $bi } { return +1 } else { return -1 }
}

#
# Sort - procedure to sort log by name and date.
#

proc Sort { method } {
  global windows stuff

  set bunch [$windows(loglist) get 0 end]
  if { $method == "band" } {
    set newbunch [lsort -command ComparebyBand $bunch]
  } elseif { $method == "time" } {
    set newbunch [lsort -command ComparebyTime $bunch]
  } elseif { $method == "sent" } {
    set newbunch [lsort -command ComparebySent $bunch]
  } elseif { $method == "call" } {
    set newbunch [lsort -command ComparebyCall $bunch]
  } elseif { $method == "recd" } {
    set newbunch [lsort -command ComparebyRecd $bunch]
  }
  $windows(loglist) delete 0 end
  foreach line $newbunch {
    $windows(loglist) insert end $line
  }
  $windows(loglist) see end
  set stuff(unsaved) 1
  Auto_Save
}

#
# My_Exit - procedure to quit, but allow the user to confirm if log has not
#          been saved.
#
  
proc My_Exit { } {
  global windows stuff

  set conf "ok"

  if { $stuff(unsaved) == 1 } {

    set conf [ tk_messageBox -icon warning -type okcancel \
        -title "Confirm Exit" -message \
"If you exit now, you will lose unsaved information." ]
  }

  if { $conf == "ok" } {
    Store_Loc
    if { [ info exists stuff(updatebothafterjob) ] } {
      after cancel $stuff(updatebothafterjob)
    }
    Stop_Modules
    exit
  }
}

#
# Build_Main - procedure to create the top-level window.
#
  
proc Build_Main { } {
  global . windows stuff

  # Build the Menu Bar

  menu .m -relief raised -borderwidth 2
  . config -menu .m

  set windows(mFile) [menu .m.mFile -tearoff 0]
  .m add cascade -label File -menu .m.mFile
  $windows(mFile) add command -underline 0 -label New -command New
  $windows(mFile) add command -underline 0 -label Open -command {Open "open"}
  $windows(mFile) add command -underline 0 -label Merge -command {Open "merge"}
  $windows(mFile) add command -underline 0 -label Save -command {Save File}
  $windows(mFile) add command -underline 5 -label "Save As" -command {Save As}
  $windows(mFile) add command -underline 0 -label Export -command {Export}
  $windows(mFile) add command -underline 1 -label Exit -command My_Exit

  set windows(mTools) [menu .m.mTools -tearoff 0]
  .m add cascade -label Tools -menu .m.mTools
  $windows(mTools) add command -underline 2 -label "Keyer..." -command Popup_Keyer
  $windows(mTools) add command -underline 1 -label "Skeds..." -command { Popup_Skeds "nokeep" }
  $windows(mTools) add command -underline 0 -label "Net..." -command Popup_Net
  $windows(mTools) add command -underline 10 -label "Station Info..." -command Popup_Info
  $windows(mTools) add command -underline 0 -label "Lookup..." -command { Popup_Lookup "partial" }
  $windows(mTools) add command -label "Super Lookup..." -command { Super_Lookup }
  $windows(mTools) add command -label "Buds..." -command { Popup_Lookup "buds" }
  $windows(mTools) add command -underline 0 -label "Calc..." -command Popup_Calc
  $windows(mTools) add command -underline 0 -label "Map..." -command { Popup_Map $stuff(sent) }
  $windows(mTools) add command -underline 0 -label "Score..." -command Popup_Score
  $windows(mTools) add command -label "Log Header..." -command Popup_Loghead
  $windows(mTools) add command -underline 2 -label "Save Settings" -command Save_Settings

  set windows(mHelp) [menu .m.mHelp -tearoff 0]
  .m add cascade -label Help -underline 0 -menu .m.mHelp
  $windows(mHelp) add command -underline 0 -label Shortcuts -command Shortcuts
  $windows(mHelp) add command -underline 0 -label About -command About

  # Build the QSO part of the Entry Area

  frame .q -borderwidth 2 -relief raised

  set windows(bandmenubut) [ menubutton .q.mBand -text Band -menu \
    .q.mBand.menu -relief raised -underline 0 ]
  if { $::setting(bandlock) == 1 } { $windows(bandmenubut) configure -state \
    disabled }
  set windows(bandentry) [ entry .q.eBand -state readonly -font \
    $::setting(bigfont) -textvariable stuff(band) -width 6 \
    -readonlybackground lightyellow ]

  set windows(bandmenu) [menu .q.mBand.menu -tearoff 0]
  foreach b $::setting(bands) {
    $windows(bandmenu) add radio -label $b -variable stuff(band) -value $b \
      -command { Redraw_Map_Band ; Recall_Op_Freq ; Set_Freq exec ; HCO_Light "on" }
  }
  menubutton .q.mMode -text Mode -menu .q.mMode.menu -relief raised \
    -underline 1
  set windows(modeentry) [ entry .q.eMode -state readonly -font \
    $::setting(entryfont) -textvariable stuff(mode) -width 6 \
    -readonlybackground lightyellow ]

  label .q.lDate -text Date
  set windows(dateentry) [ entry .q.eDate -font $::setting(entryfont) \
    -textvariable stuff(date) -width 11 -state readonly -background yellow ]

  label .q.lUTC -text "UTC"
  set windows(utcentry) [ entry .q.eUTC -font $::setting(entryfont) \
    -textvariable stuff(utc) -width 5 -state readonly -background yellow ]

  label .q.bMyCall -text "My Call"
  set windows(mycallentry) [ entry .q.eMyCall -font $::setting(entryfont) \
    -textvariable ::setting(mycall) -width 14 -background yellow \
    -readonlybackground lightyellow ]

  label .q.bSent -text "Sent"
  set windows(sententry) [ entry .q.eSent -font $::setting(entryfont) \
    -textvariable stuff(sent) -width 10 -background yellow \
    -readonlybackground lightyellow ]

  label .q.lCall -text "Call"
  set windows(callentry) [ entry .q.eCall -font $::setting(bigfont) \
    -textvariable stuff(call) -width 14 -background yellow ]

  label .q.lRecd -text "Recd"
  set windows(recdentry) [ entry .q.eRecd -font $::setting(bigfont) \
    -textvariable stuff(recd) -width 10 -background yellow ]

  radiobutton .q.rbBLock -text "Lock" -variable ::setting(bandlock) -value 1 \
    -anchor w -command { $windows(bandmenubut) configure -state disabled ; \
    $windows(stabandmenubut) configure -state disabled }

  radiobutton .q.rbBUlck -text "Unlock" -variable ::setting(bandlock) -value 0 \
    -anchor w -command { $windows(bandmenubut) configure -state normal ; \
    $windows(stabandmenubut) configure -state normal }

  set windows(modemenu) [menu .q.mMode.menu -tearoff 0 ]
  foreach b $::setting(modes) {
    $windows(modemenu) add radio -label $b -variable stuff(mode) -value $b \
      -command { Send_Mode_To_Rig }
  }

  set windows(mainkeyerbutton) [ button .q.bKeyer -text "Keyer..." -underline 2 \
    -command { $windows(mainkeyerbutton) configure -fg black ; Popup_Keyer } ]
  button .q.bStop -text "Stop" -command { Keyer_Puts "stop!" }

  radiobutton .q.rbrt1 -text "Real time" -variable stuff(realtime) -value 1 \
    -anchor w -command { Time_Mode "realtime" } 
  radiobutton .q.rbrt0 -text "Manual" -variable stuff(realtime) -value 0 \
    -anchor w -command { Time_Mode "manual" }

  set windows(skedsbutton) [ button .q.bMakeSked -text "Skeds..." \
    -underline 1 -command { Popup_Skeds "nokeep" } ]

  set windows(wipentry) [ entry .q.eWIP -font $::setting(entryfont) \
    -textvariable stuff(wip) -width 5 -state readonly ]
  set stuff(wipentrybg) [ $windows(wipentry) cget -readonlybackground ]
  set stuff(wipentryfg) [ $windows(wipentry) cget -fg ]

  button .q.bNet -text "Net..." -underline 0 -command { Popup_Net }
  set windows(infobutton) [ button .q.bFreq -text "Station Info..." -underline 10 \
    -command { $windows(infobutton) configure -fg black ; Popup_Info } ]

  set windows(fromgpsbutton) [ radiobutton .q.rbgp1 -text "From GPS" -variable ::setting(gps) \
    -value 1 -anchor w -command { Unblacklist "gps" } ]
  radiobutton .q.rbgp0 -text "Manual" -variable ::setting(gps) -value 0 \
    -anchor w

  set windows(mainsuperbutton) [ button .q.bSuper -text "Super" -command { Super_Lookup } ]
  button .q.bLookup -text "Lookup..." -underline 0 -command { Popup_Lookup "partial" }
  button .q.bWeb  -text "Web..." -command { Web_Lookup }
  button .q.bBuds -text "Buds..." -command { Popup_Lookup "buds" }

  set windows(calcbutton) [ button .q.bCalc -text "Calc..." -command \
    { $windows(calcbutton) configure -fg black ; Popup_Calc } -underline 0 ]
  button .q.bMap -text "Map..." -command { Popup_Map $stuff(sent) } -underline 0

  grid .q.mBand   .q.mMode  .q.lDate .q.lUTC      .q.bMyCall .q.bSent  .q.lCall    -          .q.lRecd \
    -sticky news -padx 1 -pady 1
  grid .q.eBand   .q.eMode  .q.eDate .q.eUTC      .q.eMyCall .q.eSent  .q.eCall    -          .q.eRecd \
    -sticky news -padx 1 -pady 1
  grid .q.rbBLock .q.bKeyer .q.rbrt1 .q.bMakeSked .q.bNet    .q.rbgp1  .q.bSuper   .q.bLookup .q.bCalc \
    -sticky news -padx 1 -pady 1
  grid .q.rbBUlck .q.bStop  .q.rbrt0 .q.eWIP      .q.bFreq   .q.rbgp0  .q.bWeb     .q.bBuds   .q.bMap \
    -sticky news -padx 1 -pady 1

  grid rowconfigure .q 0 -weight 0
  grid rowconfigure .q 1 -weight 0
  grid rowconfigure .q 2 -weight 0
  grid rowconfigure .q 3 -weight 0
  grid columnconfigure .q 0 -weight 0

  # Build the Log part of the Entry Area

  frame .l -borderwidth 2 -relief raised
    
  frame .l.header
  set windows(DeleteButton) [button .l.header.bDelete -text "Delete QSO" \
    -command { Delete_Entry } -underline 0]
  set windows(EditButton) [button .l.header.bEdit -text "Edit QSO" -command \
    { Edit_Entry } -underline 0]
  set windows(CopyButton) [button .l.header.bCopy -text "Copy QSO" -command \
    { Copy_Entry }]
  set windows(CancelButton) [button .l.header.bCancel -text "Cancel Edit" \
    -state disabled -command { Cancel_Edit } -underline 10 ]
  button .l.header.lAnnunciator -text "Hist" -command Popup_Hist

  set windows(annentry) [entry .l.header.eAnnunciator \
    -textvariable stuff(annunciator) -width 40 -state readonly ]

  set stuff(annbg) [ $windows(annentry) cget -readonlybackground ]
  set stuff(annfg) [ $windows(annentry) cget -fg ]

  set windows(LogQSOButton) [button .l.header.bLogQSO -text "Log QSO" \
    -command { Log_QSO } -background pink ]

  pack .l.header.bDelete -side left -padx 1 -pady 1
  pack .l.header.bEdit -side left -padx 1 -pady 1
  pack .l.header.bCopy -side left -padx 1 -pady 1
  pack .l.header.bCancel -side left -padx 1 -pady 1
  pack .l.header.lAnnunciator -side left -padx 1 -pady 1
  pack .l.header.eAnnunciator -side left -padx 1 -pady 1 -fill x -expand true
  pack .l.header.bLogQSO -side right -padx 1 -pady 1

  frame .l.body
  set windows(loglist) [ \
    listbox .l.body.list -listvariable stuff(loglist) -font $::setting(font) -width 82 \
      -height $::setting(listheight) \
      -fg black -bg white \
      -yscrollcommand [list .l.body.yscroll set]]
  scrollbar .l.body.yscroll -orient vertical -command [list .l.body.list yview]
  pack .l.body.yscroll -side right -fill y
  pack .l.body.list -fill both -expand true

  frame .l.footer
  button .l.footer.bScore -text "Score..." -command Popup_Score -underline 0
  button .l.footer.bLoghead -text "Log Header..." -command Popup_Loghead
  label .l.footer.lPrelabel -text "The log currently contains"
  entry .l.footer.eEntries -width 4 -state readonly -textvariable \
    stuff(entries)
  label .l.footer.lPostlabel -text "entries."
  if { ! $::setting(allowsort) } {

    label .l.footer.lb -text "Busy"
    entry .l.footer.eb -textvariable stuff(busy) -width 4 \
      -font $::setting(entryfont) -state readonly
    button .l.footer.bb0 -text "0 Min" -command { Busy 0 }
    button .l.footer.bb1 -text "1 Min" -command { Busy 1 }
    button .l.footer.bb5 -text "5 Min" -command { Busy 5 }
    button .l.footer.bb10 -text "10 Min" -command { Busy 10 }

    grid .l.footer.bScore .l.footer.bLoghead \
      .l.footer.lPrelabel .l.footer.eEntries .l.footer.lPostlabel \
      .l.footer.lb .l.footer.eb .l.footer.bb0 .l.footer.bb1 \
      .l.footer.bb5 .l.footer.bb10 \
       -sticky news -padx 1 -pady 1

  } else {

    label .l.footer.lSortBy -text "Sort By"
    button .l.footer.bSortb -text "Band" -command { Sort band }
    button .l.footer.bSortt -text "Time" -command { Sort time }
    button .l.footer.bSorts -text "Sent" -command { Sort sent }
    button .l.footer.bSortc -text "Call" -command { Sort call }
    button .l.footer.bSortr -text "Recd" -command { Sort recd }

    grid .l.footer.bScore .l.footer.bLoghead \
      .l.footer.lPrelabel .l.footer.eEntries .l.footer.lPostlabel \
      .l.footer.lSortBy .l.footer.bSortb .l.footer.bSortt .l.footer.bSorts \
      .l.footer.bSortc .l.footer.bSortr  -sticky news -padx 1 -pady 1
  }

  grid .l.header -sticky news -padx 1 -pady 1
  grid .l.body   -sticky news -padx 1 -pady 1
  grid .l.footer -sticky news -padx 1 -pady 1

  grid rowconfigure .l 0 -weight 0
  grid rowconfigure .l 1 -weight 1
  grid rowconfigure .l 2 -weight 0
  grid columnconfigure .l 0 -weight 0

  grid .q -sticky news
  grid .l -sticky news

  grid rowconfigure . 0 -weight 0
  grid rowconfigure . 1 -weight 1

  # TODO - why doesn't this work?
  grid columnconfigure . 0 -weight 0

  # this FINALLY fixes the location restoration of the main window.
  update idletasks

  return
}

#
# Edit_Mode - procedure to colorize widgets to indicate edit mode.
#

proc Edit_Mode { } {
  global windows stuff
  set stuff(editing) 1
  set stuff(realtimesave) $stuff(realtime)
  Time_Mode "manual"
  $windows(dateentry) configure -state normal
  $windows(utcentry) configure -state normal
  set stuff(gpssave) $::setting(gps)
  set ::setting(gps) 0

  $windows(EditButton) configure -state disabled
  $windows(DeleteButton) configure -state disabled
  $windows(CopyButton) configure -state disabled
  $windows(CancelButton) configure -state normal

  set stuff(editband) $stuff(band)
  set stuff(editmode) $stuff(mode)
  set stuff(editdate) $stuff(date)
  set stuff(editutc) $stuff(utc)
  set stuff(editmycall) $::setting(mycall)
  set stuff(editsent) $stuff(sent)
  set stuff(editcall) $stuff(call)
  set stuff(editrecd) $stuff(recd)

  $windows(bandentry) configure -fg red
  $windows(stabandentry) configure -fg red
  $windows(modeentry) configure -fg red
  $windows(dateentry) configure -fg red
  $windows(utcentry) configure -fg red
  $windows(mycallentry) configure -fg red
  $windows(sententry) configure -fg red
  $windows(callentry) configure -fg red
  $windows(recdentry) configure -fg red

  focus $windows(callentry)
}

#
# Non_Edit_Mode - procedure to de-colorize widgets to indicate non-edit mode.
#

proc Non_Edit_Mode { } {
  global windows stuff
  set stuff(editing) 0
  set ::setting(gps) $stuff(gpssave)
  set stuff(realtime) $stuff(realtimesave)
  if { $stuff(realtimesave) == 1 } {
    Time_Mode "realtime"
  } else {
    Time_Mode "manual"
  }

  $windows(EditButton) configure -state normal
  $windows(DeleteButton) configure -state normal
  $windows(CopyButton) configure -state normal
  $windows(CancelButton) configure -state disabled

  set stuff(band) $stuff(editband)
  Set_Freq noexec
  set stuff(mode) $stuff(editmode)
  set ::setting(mycall) $stuff(editmycall)
  set stuff(sent) $stuff(editsent)
  set stuff(call) $stuff(editcall)
  set stuff(recd) $stuff(editrecd)

  $windows(bandentry) configure -fg black
  $windows(stabandentry) configure -fg black
  $windows(modeentry) configure -fg black
  $windows(dateentry) configure -fg black
  $windows(utcentry) configure -fg black
  $windows(mycallentry) configure -fg black
  $windows(sententry) configure -fg black
  $windows(callentry) configure -fg black
  $windows(recdentry) configure -fg black
}

#
# Delete_Entry - procedure to delete the active log entry
#

proc Delete_Entry { } {
  global stuff windows

  # if already editing, we can't allow this action
  if { $stuff(editing) != 0 } {
    return
  }

  # get the line from the log
  set lineno [$windows(loglist) index active]
  set line [$windows(loglist) get $lineno]

  # parse out the line, abort if crazy
  if { [ binary scan $line "x5a5x1a2x1a10x1a4x1a13x5a6x1a13x5a6" \
    band mode date utc mycall sent call recd ] != 8 } {
    return
  }

  # make sure the user really wants to delete the QSO
  set conf "ok"
  set conf [ tk_messageBox -icon warning -type okcancel \
    -title "Confirm Delete" -message \
      "If you delete this QSO, it will be permanently removed from the log." ]

  # if the user aborted, return
  if { $conf != "ok" } {
    return
  }

  # mark to save log
  set stuff(unsaved) 1

  # fix up the fields
  set band [ string trim $band ]
  set sent [ string toupper $sent ]
  set recd [ string toupper $recd ]

  # depending on rules type, make a 4- or 6-digit match pattern
  if { $::setting(rules) == "dist" || $::setting(rules) == "grid6" } {

    if { [ string length $sent ] < 6 } {
      set sent [ string range $sent 0 3 ]
      set sent "${sent}MM"
    }
    if { [ string length $recd ] < 6 } {
      set recd [ string range $recd 0 3 ]
      set recd "${recd}MM"
    }
    set m [ format "QSO: %-5.5s %s %-6.6s %-13.13s     %-6.6s" \
      $band ".. \[0-9\]\[0-9\]\[0-9\]\[0-9\]-\[0-1\]\[0-9\]-\[0-3\]\[0-9\] \[0-2\]\[0-9\]\[0-5\]\[0-9\] \[ 0-9A-Z/\]{17}" \
      $sent $call $recd ]

  } else {

    set sent [ string range $sent 0 3 ]
    set recd [ string range $recd 0 3 ]
    set m [ format "QSO: %-5.5s %s %-4.4s%s %-13.13s     %-4.4s%s" \
      $band ".. \[0-9\]\[0-9\]\[0-9\]\[0-9\]-\[0-1\]\[0-9\]-\[0-3\]\[0-9\] \[0-2\]\[0-9\]\[0-5\]\[0-9\] \[ 0-9A-Z/\]{17}" \
      $sent ".." $call $recd ".." ]

  }

  # Reap the QSO from the databases
  Debug "Delete_Entry" "Looking for other lines matching $m."

  set mfound 0
  set bunch [$windows(loglist) get 0 end]
  # print out the whole log
  # foreach b $bunch {
  #   Debug "Delete_Entry" "$b"
  # }
  set mi [ lsearch -regexp $bunch $m ]
  Debug "Delete_Entry" "First match result: $mi."

  if { $mi >= 0 } {
    incr mfound
    incr mi
    set mi [ lsearch -regexp [ lrange $bunch $mi end ] $m]
    Debug "Delete_Entry" "Second match result: $mi."
    if { $mi >= 0 } {
      incr mfound
    }
  }

  if { $mfound <= 1 } {
    Debug "Delete_Entry" "Only found 1 match. Calling Decrement_Worked or Lookup_Delete."
    Decrement_Worked $band $sent $recd
    Lookup_Delete $band $call $sent $recd
  } else {
    Debug "Delete_Entry" "Found more than 1 match. Not calling Decrement_Worked or Lookup_Delete."
  }

  # and the net
  Net_Send "zzz" "all" "DEL: $line"

  # reap the old line from the log
  $windows(loglist) delete active

  # refresh everything
  set stuff(entries) [$windows(loglist) index end] 
  Redraw_Map $stuff(mapcenter)
  Redraw_Score
  Auto_Save

  return
}

#
# Edit_Entry - procedure to move the active log entry into the editing
#              fields.
#

proc Edit_Entry { } {
  global stuff windows

  # if already editing, we can't allow this action
  if { $stuff(editing) != 0 } {
    return
  }

  # get the old line from the log
  set lineno [$windows(loglist) index active] 
  set stuff(editline) [$windows(loglist) get $lineno]

  # parse out the line, abort if crazy
  if { [ binary scan $stuff(editline) "x5a5x1a2x1a10x1a4x1a13x5a6x1a13x5a6" \
    band mode date utc mycall sent call recd ] != 8 } {
    return
  }

  # save state variable for where to insert new line
  set stuff(lineno) $lineno
    
  # set indication of edit mode for user
  Edit_Mode

  # mark to save log
  set stuff(unsaved) 1

  # fix up the fields
  set stuff(band) [ string toupper [ string trim $band] ]
  Set_Freq noexec
  set stuff(mode) [ string toupper [ string trim $mode] ]
  set stuff(date) $date
  set stuff(utc) $utc
  set ::setting(mycall) [ string toupper [ string trim $mycall] ]
  set stuff(sent) [ string toupper [ string trim $sent] ]
  set stuff(call) [ string toupper [ string trim $call] ]
  set stuff(recd) [ string toupper [ string trim $recd] ]

  # reap the QSO from the databases
  # set up the line we are looking to match
  set m [ format "QSO: %-5.5s %s %-4.4s%s %-13.13s     %-4.4s%s" \
    $band ".. \[0-9\]\[0-9\]\[0-9\]\[0-9\]-\[0-1\]\[0-9\]-\[0-3\]\[0-9\] \[0-2\]\[0-9\]\[0-5\]\[0-9\] \[ 0-9A-Z/\]{17}" \
    $sent ".." $call $recd ".." ]

  Debug "Edit_Entry" "Looking for other lines matching $m."

  set mfound 0
  set bunch [$windows(loglist) get 0 end]
  # print out the whole log
  # foreach b $bunch {
  #   Debug "Edit_Entry" "$b"
  # }
  set mi [ lsearch -regexp $bunch $m ]
  Debug "Edit_Entry" "First match result: $mi."

  if { $mi >= 0 } {
    incr mfound
    incr mi
    set mi [ lsearch -regexp [ lrange $bunch $mi end ] $m]
    Debug "Edit_Entry" "Second match result: $mi."
    if { $mi >= 0 } {
      incr mfound
    }
  }

  if { $mfound <= 1 } {
    Debug "Edit_Entry" "Only found 1 match. Calling Decrement_Worked or Lookup_Delete."
    Decrement_Worked $stuff(band) $stuff(sent) $stuff(recd)
    Lookup_Delete $stuff(band) $stuff(call) $stuff(sent) $stuff(recd)
  } else {
    Debug "Edit_Entry" "Found more than 1 match. Not calling Decrement_Worked or Lookup_Delete."
  }

  # and the net
  Net_Send "zzz" "all" "DEL: $stuff(editline)"

  # reap the old line from the log
  Debug "Edit_Entry" "Deleting line $stuff(lineno)"
  $windows(loglist) delete $stuff(lineno)

  # Now the user has all the old QSO information in the
  # entry fields and can go to town. We keep track of
  # the lineno and editmode as state variables.

  # refresh everything to be accurate until editing is done
  set stuff(entries) [$windows(loglist) index end] 
  Redraw_Map $stuff(sent)
  Redraw_Score
  Auto_Save

  return
}

#
# Cancel_Edit - procedure to replace the original entry back into the log.
#

proc Cancel_Edit { } {
  global stuff windows

  # if not editing, we can't allow this action
  if { $stuff(editing) == 0 } {
    return
  }

  # set indication of edit mode for user
  Non_Edit_Mode

  # parse out the line, abort if crazy
  if { [ binary scan $stuff(editline) "x5a5x1a2x1a10x1a4x1a13x5a6x1a13x5a6" \
    band mode date utc mycall sent call recd ] != 8 } {
    return
  }

  # mark to save log
  set stuff(unsaved) 1

  # fix up the fields
  set stuff(band) $stuff(editband)
  Set_Freq noexec
  set stuff(mode) $stuff(editmode)
  set ::setting(mycall) $stuff(editmycall)
  set stuff(sent) $stuff(editsent)
  set stuff(call) $stuff(editcall)
  set stuff(recd) $stuff(editrecd)

  # add the QSO back into the databases
  Increment_Worked $stuff(band) $stuff(sent) $stuff(recd) "quiet"
  Lookup_Add $stuff(band) $stuff(call) $stuff(sent) $stuff(recd)

  # and the net
  Net_Send "zzz" "all" "$stuff(editline)"

  # re-insert the line into the log
  $windows(loglist) insert $stuff(lineno) $stuff(editline)

  # refresh everything to be accurate
  set stuff(entries) [$windows(loglist) index end] 
  Redraw_Map $stuff(sent)
  Redraw_Score
  Auto_Save

  return
}

#
# Copy_Entry - procedure to copy the active log entry into the editing
#              fields.
#

proc Copy_Entry { } {
  global stuff windows

  if { $stuff(editing) != 0 } {
    return
  }

  # get the line from the log
  set lineno [$windows(loglist) index active] 
  set line [$windows(loglist) get $lineno]

  # parse out the line
  if { [ binary scan $line "x5a5x1a2x1a10x1a4x1a13x5a6x1a13x5a6" \
    band mode date utc mycall sent call recd ] != 8 } {
    return
  }

  # fix up the fields
  if { $::setting(bandlock) == 0 } {
    set stuff(band) [ string toupper [ string trim $band] ]
    Set_Freq noexec
  }
  set stuff(mode) [ string toupper [ string trim $mode] ]
  set ::setting(mycall) [ string toupper [ string trim $mycall] ]
  set stuff(sent) [ string toupper [ string trim $sent] ]
  set stuff(call) [ string toupper [ string trim $call] ]
  set stuff(recd) [ string toupper [ string trim $recd] ]

  # Now the user has all the old QSO information in the
  # entry fields and can go to town.
  focus $windows(callentry)
  $windows(callentry) icursor end
  $windows(callentry) select range 0 end
}

#
# Auto_Save - procedure to check whether or not it is time to auto save
#             and do that if so.
#

proc Auto_Save { } {
  global stuff windows

  if { $::setting(autosave) == 0 } {
    return
  } else {
    incr stuff(logcount)
    if { $stuff(logcount) >= $::setting(autosave) } {
      set stuff(logcount) 0
      Save File
    }
  }
}

#
# Check_QSO - procedure to see if the QSO is loggable.  Return 0 if the QSO
#   should be logged or 1 if not.
#

proc Check_QSO { quiet band date utc sent call recd } {
  global stat

  incr stat(Check_QSO,t) [ lindex [ time { set r [ Check_QSO_Stub $quiet $band $date $utc $sent $call $recd ] } ] 0 ]
  incr stat(Check_QSO,n)

  return $r
}

proc Check_QSO_Stub { quiet band date utc sent call recd } {

  if { [ Valid_Date $date ] != 1 } {
    tk_messageBox -icon error -type ok \
      -title "Oops" -message "The date is not valid."
    return 1
  }

  if { [ Valid_UTC $utc ] != 1 } {
    tk_messageBox -icon error -type ok \
      -title "Oops" -message "The time is not valid."
    return 1
  }

  if { $call == "" } {
    tk_messageBox -icon error -type ok \
      -title "Oops" -message "Please specify the remote station's call first."
    return 1
  }

  if { $sent == "" } {
    tk_messageBox -icon error -type ok \
      -title "Oops" -message "Please specify your station's grid first."
    return 1
  }

  if { $recd == "" } {
    tk_messageBox -icon error -type ok \
      -title "Oops" -message "Please specify the remote station's grid first."
    return 1
  }

  set call [ string toupper $call ]
  set sent [ string toupper $sent ]
  set recd [ string toupper $recd ]

  if { $quiet != "quiet" } {
    if { [ Valid_Call $call ] != 1 } {
      set conf [ tk_messageBox -icon warning -type okcancel \
          -title "Confirm Callsign" -message \
"The remote station's callsign $call appears invalid, log anyway?" ]
      if { $conf != "ok" } {
        return 1
      }
    }
  }

  if { [ Valid_Grid $sent ] != 1 } {
    tk_messageBox -icon error -type ok \
      -title "Oops" -message "The sent grid is not valid."
    return 1
  }

  if { [ Valid_Grid $recd ] != 1 } {
    tk_messageBox -icon error -type ok \
      -title "Oops" -message "The received grid is not valid."
    return 1
  }

  return 0
}

#
# Add_To_Log - procedure that can be used by local RoverLog or a peer
#              to add stuff to the log.  This procedure will not send
#              anything to the network if $net is "net".
#

proc Add_To_Log { quiet net line } {
  global stat

  incr stat(Add_To_Log,t) [ lindex [ time { set r [ Add_To_Log_Stub $quiet $net $line ] } ] 0 ]
  incr stat(Add_To_Log,n)

  return $r
}

proc Add_To_Log_Stub { quiet net line } {
  global stuff windows

  set new_mult 0

  binary scan $line "x5a5x1a2x1a10x1a4x1a13x5a6x1a13x5a6" \
    band mode date utc mycall sent call recd

  set band [ string trim [ string toupper $band ] ]
  set mode [ string trim [ string toupper $mode ] ]
  set date [ string trim [ string toupper $date ] ]
  set utc [ string trim [ string toupper $utc ] ]
  set mycall [ string trim [ string toupper $mycall ] ]
  set sent [ string trim [ string toupper $sent ] ]
  set call [ string trim [ string toupper $call ] ]
  set recd [ string trim [ string toupper $recd ] ]

  # do not allow silent logging of a dupe if getting it over the net.
  if { $net == "net" } {
    set strict "strict"
  } else {
    set strict "lax"
  }

  # allow logging if QSO is valid and if there is no dupe
  # (or if we are being quiet).
  if { [ Check_QSO $quiet $band $date $utc $sent $call $recd ] == 0 &&
    [ Dupe_Check $strict $quiet $band $date $utc $sent $call $recd ] == 0 } {

    # must protect the Worked database to keep the score straight even
    # if we're forcing a dupe log.
    if { [ Dupe_Check "strict" $quiet $band $date $utc $sent $call $recd ] == 0 } {
      set new_mult [ Increment_Worked $band $sent $recd $quiet ]
    }

    # mark for automatic file saving
    set stuff(unsaved) 1

    # if we're logging a local interactive QSO,
    # set a flag to "see end" after the insertion.
    if { $quiet != "quiet" || ( $net == "net" && 
      [ lindex [ $windows(loglist) yview ] 1 ] == 1 ) } {
      set see_end 1
    } else {
      set see_end 0
    }

    # add this QSO to the log

    # this is a replacement insertion
    if { $stuff(lineno) >= 0 } {

      # $windows(loglist) insert $stuff(lineno) $line
      set stuff(loglist) [ linsert $stuff(loglist) $stuff(lineno) $line ]

      if { $net == "net" } {
        if { $new_mult == 0 } {
          $windows(loglist) itemconfigure $stuff(lineno) \
            -fg $::setting(lognetfg) -bg $::setting(lognetbg)
        } else {
          $windows(loglist) itemconfigure $stuff(lineno) \
            -fg $::setting(lognetnewfg) -bg $::setting(lognetnewbg)
        }
      } else {
        if { $new_mult == 1 } {
          $windows(loglist) itemconfigure $stuff(lineno) \
            -fg $::setting(lognewfg) -bg $::setting(lognewbg)
        } else {
          $windows(loglist) itemconfigure $stuff(lineno) \
            -fg $::setting(logfg) -bg $::setting(logbg)
        }
      }

      $windows(loglist) see $stuff(lineno)
      set stuff(lineno) -1

    } else {

      # $windows(loglist) insert end $line
      lappend stuff(loglist) $line

      if { $net == "net" } {
        if { $new_mult == 0 } {
          $windows(loglist) itemconfigure end \
            -fg $::setting(lognetfg) -bg $::setting(lognetbg)
        } else {
          $windows(loglist) itemconfigure end \
            -fg $::setting(lognetnewfg) -bg $::setting(lognetnewbg)
        }
      } else {
        if { $new_mult == 1 } {
          $windows(loglist) itemconfigure end \
            -fg $::setting(lognewfg) -bg $::setting(lognewbg)
        } else {
          $windows(loglist) itemconfigure end \
            -fg $::setting(logfg) -bg $::setting(logbg)
        }
      }

      if { $see_end == 1 } {
        $windows(loglist) see end
      }
    }

    # update entries counter
    set stuff(entries) [$windows(loglist) index end] 

    # add this guy to the lookup database
    Lookup_Add $band $call $sent $recd

    # only update the calc and send to the network
    # if we're getting this from user entry.
    if { $net != "net" } {
      Do_Lookup "partial" $call $recd $sent
      Bear_Calc $stuff(sent) $stuff(recd)
      Net_Send "zzz" "all" $line
    }

    set stuff(entries) [$windows(loglist) index end] 
    Redraw_Map ""
    Redraw_Score
    Auto_Save

  } else {
    return 1
  }

  # remove any WIP or skeds for this guy on this band in this spot.

  Reap_Sked $band $call $sent $recd

  return 0
}

#
# Call_Stack_Push - procedure to push a callsign and grid onto the stack.
#                   0 is the most recent stack entry and 4 is the oldest.
#

proc Call_Stack_Push { c r } {
  global call_stack

  # move 0-3 (j) to 1-4 (i)
  for { set i 4 } { $i > 0 } { incr i -1 } {
    set j [ expr $i - 1 ]
    set call_stack($i) $call_stack($j)
  }

  # set 0 to most recent
  set call_stack(0) [ list $c $r ]

  # print array
  for { set i 0 } { $i < 5 } { incr i } {
    Debug "Call_Stack_Push" "$i $call_stack($i)"
  }
}

#
# Call_Stack_Pop - procedure to pop a callsign and grid off the stack.
#                  0 is the most recent stack entry and 4 is the oldest.
#

proc Call_Stack_Pop { } {
  global stuff call_stack windows

  # save the most recent entry to put it on the bottom
  # set t $call_stack(0)
  set t [ list $stuff(call) $stuff(recd) ]

  # get the most recent entry
  set stuff(call) [ lindex $call_stack(0) 0 ]
  set stuff(recd) [ lindex $call_stack(0) 1 ]
  focus $windows(callentry)

  # select the whole call field.
  $windows(callentry) icursor end
  $windows(callentry) select range 0 end

  # move 1-4 (j) to 0-3 (i)
  for { set i 0 } { $i < 4 } { incr i 1 } {
    set j [ expr $i + 1 ]
    set call_stack($i) $call_stack($j)
  }

  # put the old most recent entry on the bottom
  set call_stack(4) $t

  # print array
  for { set i 0 } { $i < 5 } { incr i } {
    Debug "Call_Stack_Pop" "$i $call_stack($i)"
  }
}

#
# Log_QSO - procedure to store information from the entry fields into
#                the log.
#

proc Log_QSO { } {
  global stat

  incr stat(Log_QSO,t) [ lindex [ time { Log_QSO_Stub } ] 0 ]
  incr stat(Log_QSO,n)

  return
}

proc Log_QSO_Stub { } {
  global stuff windows

  set stuff(annunciator) ""

  set ::setting(mycall) [ string trim [ string toupper $::setting(mycall) ] ]
  set stuff(sent) [ string trim [ string toupper $stuff(sent) ] ]
  set stuff(call) [ string trim [ string toupper $stuff(call) ] ]
  set stuff(recd) [ string trim [ string toupper $stuff(recd) ] ]

  if { [ Rover_Call ] == 1 } {
    return
  }

  # This prevents the time from freezing in the log if the update task for
  # the date/utc fields dies somehow.  The display would still be wrong until
  # a QSO is logged.

  if { $stuff(realtime) == 1 } {
    Set_Time_From_PC
  }

  set line [ format "QSO: %-5.5s %-2.2s %-10.10s %-4.4s %-13.13s     %-6.6s %-13.13s     %-6.6s" \
    $stuff(band) $stuff(mode) $stuff(date) $stuff(utc) \
    $::setting(mycall) $stuff(sent) $stuff(call) $stuff(recd) ]

  set dupe [ Add_To_Log "loud" "local" $line ]

  if { $dupe == 0 } {

    if { $stuff(editing) == 1 } {
      Non_Edit_Mode
    } else {
      if { $::setting(passprompt) == 1 } {
        Popup_Pass "nokeep"
      }
    }  

    Call_Stack_Push $stuff(call) $stuff(recd)
    Clear_Entry nonforce
    HCO_Light "off"
    Lookup_Recd "unlock"

    if { $stuff(realtime) == 0 && $::setting(warnrealtime) == 1 } {
      tk_messageBox -icon warning -type ok \
        -title "Manual Time Entry" -message \
"Please note that you are entering QSO times manually."
    }
  }

  Busy 0
}

#
# Play_CW - procedure to send a play CW command to the keyer server.
#

proc Play_CW { i } {
  global windows stuff

  # check blacklist
  if { $stuff(blacklist,keyer) == 1 } {
    Debug "Play_CW" "Keyer is blacklisted. Skipping."
    return
  }

  # set up replacement macros
  set m $::setting(mycall)
  set c $stuff(call)

  # depending on rules type, make a 4- or 6-digit match pattern
  if { $::setting(rules) == "dist" || $::setting(rules) == "grid6" } {

    if { [ string length $stuff(sent) ] < 6 } {
      set s [ string range $stuff(sent) 0 3 ]
      set s "${s}MM"
    } else {
      set s $stuff(sent)
    }
    if { [ string length $stuff(recd) ] < 6 } {
      set r [ string range $stuff(recd) 0 3 ]
      set r "${r}MM"
    } else {
      set r $stuff(recd)
    }

  } else {

    set s [ string range $stuff(sent) 0 3 ]
    set r [ string range $stuff(recd) 0 3 ]

  }

  # send command
  if { $i == 6 } {
    Keyer_Puts "playcw! $i $m $s $c $r $stuff(m6)"
  } else {
    Keyer_Puts "playcw! $i $m $s $c $r"
  }

  return
}

#
# Play_Voice - procedure to send a play voice command
#              to the keyer or rig server.
#

proc Play_Voice { i } {
  global windows stuff

  if { $::setting(rigdvr) == 1 } {
    set bandno [ Band_Number $stuff(band) ]
    Rig_Puts $bandno "playv$ $i"
  } else {
    Keyer_Puts "playv! $i"
  }
  return
}

#
# Time_Mode - procedure to provide a standard way of switching time modes.
#

proc Time_Mode { r } {
  global windows stuff

  if { $r == "realtime" } {
    set stuff(realtime) 1
    $windows(dateentry) configure -state readonly
    $windows(utcentry) configure -state readonly
    Set_Time_From_PC
    focus $windows(callentry)
  } else {
    set stuff(realtime) 0
    $windows(dateentry) configure -state normal
    $windows(utcentry) configure -state normal
    focus $windows(dateentry)
  }
}

#
# Toggle_realtime - procedure to invert the sense of "realtime", i.e.
#                   1 => use current date and time, 0 => user enters.
#

proc Toggle_realtime { } {
  global windows stuff

  # if time mode is manual now, go to realtime
  if { $stuff(realtime) == 0 } {
    Time_Mode "realtime"
  # if time mode is realtime now, go to manual
  } else {
    Time_Mode "manual"
  }
}

#
# Toggle_bandlock - procedure to invert the sense of "bandlock", i.e.
#                   1 => no band changes allowed in main window,
#                   0 => band changes allowed.
#

proc Toggle_bandlock { } {
  global windows stuff

  if { $::setting(bandlock) == 0 } {
    set ::setting(bandlock) 1
    $windows(bandmenubut) configure -state disabled
    $windows(stabandmenubut) configure -state disabled
  } else {
    set ::setting(bandlock) 0
    $windows(bandmenubut) configure -state normal
    $windows(stabandmenubut) configure -state normal
  }
}

#
# Toggle_gps - procedure to invert the sense of "realtime", i.e.
#              1 => use gps position, 0 => user enters.
#

proc Toggle_gps { } {
  global stuff

  if { $::setting(gps) == 0 } {
    set ::setting(gps) 1
  } else {
    set ::setting(gps) 0
  }
}

#
#  QSY - procedure to calculate the next band value.
#

proc QSY { band ud } {
  global windows stuff

  set i [expr $ud + [lsearch -exact $::setting(bands) $band]]
  set n [llength $::setting(bands)]

  if {$i > $n - 1} {
    set i 0
  } else {
    if {$i < 0} {
      set i [expr $n - 1]
    }
  }

  return [lindex $::setting(bands) $i]
}

#
# LO_Freq - procedure to return the LO frequency for the current band.
#
# Note: could be Local Oscillator OR Last Operating Freq!
#

proc LO_Freq { band } {
  global stuff

  for { set i 1 } { $i < 18 } { incr i } {
    if { $band == [ lindex $::setting(r$i) 0 ] } {
      set lofreq [ lindex $::setting(r$i) 3 ]
      set lofreq [ format "%6.4f" $lofreq ]
      return $lofreq
    }
  }
  return 0
}

#
# Store_Op_Freq - Called before changing stuff(band), this procedure
#                 saves the Last Operated Frequency for the current band.
#

proc Store_Op_Freq { } {
  global stuff

  # Debug "Store_Op_Freq" "Saving $stuff(opfreq)"
  set stuff(lastopfreq,$stuff(band)) $stuff(opfreq)
  set stuff(lastopmode,$stuff(band)) $stuff(mode)
}

#
# Recall_Op_Freq - Called when we've just changed to a new band,
#                  this procedure sends the desired operating or IF
#                  frequency to the rig.
#
# We assume we've already set stuff(band).
#

proc Recall_Op_Freq { } {
  global stuff windows

  # Figure out what band number this is by what band we're changing to.
  set bandno [ Band_Number $stuff(band) ]

  # Get the IP Port number to talk to.  If there's no port to connect
  # to, our job is done.
  set rigport [ lindex $::setting(r$bandno) 2 ]

  if { $rigport == 0 } {

    # We are allowing manual entry of frequencies.
    set stuff(rigctrl) 0

    # I wish this step could be done in the unblacklist function,
    # but we may have just QSY'd from a blacklisted band, and we don't
    # want to blindly unblacklist every time we QSY. This could cause
    # net delays.
    $windows(rigfreqbutton) configure -fg black

    # Set the frequencies
    set stuff(lofreq)  "0.0000"
    set stuff(rigfreq) "0.0000"
    set stuff(opfreq) $stuff(lastopfreq,$stuff(band))
    set stuff(mode) $stuff(lastopmode,$stuff(band))

    # Set the frequency display field attributes.
    $windows(lofreqentry) configure -state readonly
    $windows(rigfreqentry) configure -state readonly
    $windows(opfreqentry) configure -state normal

    return
  }

  # We are displaying frequencies as per the rig server.
  set stuff(rigctrl) 1

  # Set the LO Frequency.
  set lofreq [ lindex $::setting(r$bandno) 3 ]

  # Set the LO frequency display field value.
  if { [ scan $lofreq "%f" dummy ] == 1 } {
    set lofreq [ format "%6.4f" $dummy ]
  } else {
    set lofreq "0.0000"
  }
  set stuff(lofreq) $lofreq

  # Set the frequency display field attributes.
  $windows(lofreqentry) configure -state normal
  $windows(rigfreqentry) configure -state readonly
  $windows(opfreqentry) configure -state readonly

  # Recall the last operating frequency.
  set opfreq $stuff(lastopfreq,$stuff(band))
  set rigmode $stuff(lastopmode,$stuff(band))

  # If there was no previous frequency, don't send anything.
  if { $opfreq } {

    # Calculate the rig frequency.
    set rigfreq [ expr abs( $opfreq - $lofreq ) ]

    # Send the frequency to the rig.
    Debug "Recall_Op_Freq" "Sending frequency $rigfreq and mode $rigmode to Rig Server."

    Rig_Puts $bandno "freq! $rigfreq"
    Rig_Puts $bandno "mode! $rigmode"
  }
}

proc Send_Mode_To_Rig { } {
  global stuff

  # Figure out what band number this is by what band we're changing to.
  set bandno [ Band_Number $stuff(band) ]

  # Get the IP Port number to talk to.  If there's no port to connect
  # to, our job is done.
  set rigport [ lindex $::setting(r$bandno) 2 ]

  if { $rigport == 0 } {
    return
  }

  Debug "Send_Mode_To_Rig" "Sending mode $stuff(mode) to Rig Server."
  Rig_Puts $bandno "mode! $stuff(mode)"
}

proc Send_Rig_Num_To_Keyer { rignum } {
  global stuff

  if { $rignum == $stuff(lastrignum) } {
    return
  }

  if { $rignum == 0 } {
    return
  }

  if { $::setting(keyeripport) == 0 } {
    return
  }

  Debug "Send_Rig_Num_To_Keyer" "Opening connection to Keyer Module at $::setting(keyeripaddr) on port $::setting(keyeripport)."

  Keyer_Puts "rignum! $rignum"
  set stuff(lastrignum) $rignum
}

#
# Main_QSY - QSY only if bandlock is off.
#

proc Main_QSY { ud } {
  global stuff

  if { $::setting(bandlock) == 0 } {
    Store_Op_Freq
    set stuff(band) [ QSY $stuff(band) $ud ]
    if { $stuff(band) != $stuff(lastbandqsy) } {
      HCO_Light "on"
      set stuff(lastbandqsy) $stuff(band)
    }
    Redraw_Map_Band
    Recall_Op_Freq
    Set_Freq exec
  }
}

#
# FKey_QSY - QSY only if bandlock is off.
#

proc FKey_QSY { i } {
  global stuff

  if { $::setting(bandlock) == 0 } {
    Store_Op_Freq
    set stuff(band) [ lindex $::setting(bands) $i ]
    if { $stuff(band) != $stuff(lastbandqsy) } {
      HCO_Light "on"
      set stuff(lastbandqsy) $stuff(band)
    }
    Redraw_Map_Band
    Recall_Op_Freq
    Set_Freq exec
  }
}

#
# Next_Mode - procedure to change the Mode entry field to the next value.
#

proc Next_Mode { } {
  global windows stuff

  set i [expr 1 + [lsearch -exact $::setting(modes) $stuff(mode)]]
  set n [llength $::setting(modes)]

  if {$i > $n - 1} {
    set i 0
  } else {
    if {$i < 0} {
      set i [expr $n - 1]
    }
  }

  set stuff(mode) [lindex $::setting(modes) $i]
  Send_Mode_To_Rig
}

# 
# Clear_Entry - procedure to clear out the entry fields.
#

proc Clear_Entry { force } {
  global windows stuff
  
  if { $stuff(realtime) == 1 } {
    if { $::setting(clearentry) == 1 || $force == "force" } {
      set stuff(call) ""
      set stuff(recd) ""
    } else {
      $windows(callentry) icursor end
      $windows(callentry) select range 0 end
    }
    if { $::setting(passprompt) != 1 } {
      focus $windows(callentry)
    }
  } else {
    if { $::setting(clearentry) == 1 || $force == "force" } {
      set stuff(date) ""
      set stuff(utc) ""
      set stuff(call) ""
      set stuff(recd) ""
    } else {
      $windows(dateentry) icursor end
      $windows(dateentry) select range 0 end
    }
    focus $windows(dateentry)
  }
}

#
# Set_Title - Stick junk in the title bar.
#

proc Set_Title { } { 
  global stuff
  set logfile [ file tail $::setting(logfile) ]
  if { $stuff(debug) == 1 } {
    wm title . \
      "RoverLog (DEBUG ON) - $logfile - $::setting(mypeername)"
  } else {
    wm title . "RoverLog - $logfile - $::setting(mypeername)"
  }
}

proc Add_WIP { skedtext } {
  global windows

  # parse the sked information out
  set r [ binary scan $skedtext "a10x1a4x1a6x1a10x1a13x1a6" \
    skeddate skedutc skedband skedfreq skedcall skedrecd ]

  # if the line ended early (no note plus we don't have a full 6-digit grid)
  # pick up the pieces and assume a 4-digit grid.
  if { $r == 5 } {
    set r [ binary scan $skedtext "a10x1a4x1a6x1a10x1a13x1a4" \
      skeddate skedutc skedband skedfreq skedcall skedrecd ]
  }

  set skeddate [ string trim $skeddate ]
  set skedutc  [ string trim $skedutc  ]
  set skedband [ string trim $skedband ]
  set skedfreq [ string trim $skedfreq ]
  set skedcall [ string trim $skedcall ]
  set skedrecd [ string trim $skedrecd ]

  # must check call, recd, and band
  if { [ Valid_Call $skedcall ] == 1 &&
       [ Valid_Grid $skedrecd ] == 1 &&
       [ Valid_Band $skedband ] == 1 } {

    $windows(wiplist) insert end "$skedtext"
    Increment_WIP

    # Update the other stations
    Net_Send "wip" "all" ""

    Annunciate "Work $skedcall in $skedrecd on $skedband ($skedfreq)"
  }
}

#
# Update_Both - procedure to fill in the current UTC date and time and sent
#               grid and check for skeds.
#

proc Update_Both { } {
  global windows stuff sked

  if { [ info exists stuff(updatebothafterjob) ] } {
    after cancel $stuff(updatebothafterjob)
  }

  set stuff(updatebothafterjob) [ after 1000 Update_Both ]

  if { [ info exists stuff(delaycounter) ] } {
    if { $stuff(delaycounter) != 0 } {
      Debug "Update_Both" "Starting in $stuff(delaycounter) seconds..."
      incr stuff(delaycounter) -1
      return
    }
  }

  if { $stuff(realtime) == 1 } {
    Set_Time_From_PC
  }

  if { $::setting(gps) == 1 } {
    Set_Grid
  }

  Query_Rotor

  # Make sure to save any user entry so we don't wipe it out
  Store_Op_Freq

  # Now we are safe to call this based on the saved entry.
  Set_Freq exec

  # set variables for THIS sked
  # calculate the current time but add the early warning
  # offset so that it appears later than it really is.
  set t [expr $stuff(utcoffset) * 3600 + [clock seconds] + \
    $::setting(earlywarn) * 60 ]
  # back off to previous time interval
  set t [expr $t - $t % ( $::setting(skedtinc) * 60 ) ]
  set skeddate [clock format $t -format "%Y-%m-%d"]
  set skedutc  [clock format $t -format "%H%M"]
  set index "$::setting(mypeername),$skeddate:$skedutc"

  # check for a sked coming active
  if { [ info exists sked($index) ] } {

    # print the sked information for debug
    Debug "Update_Both" "sked($index) \"$sked($index)\""
    set skedtext $sked($index)

    # remove THIS sked from the list (we'll recreate it if
    # we need to later.
    Del_Sked_Kernel "made" "$index"
    Redraw_Skeds "entry"
    Save_Skeds
    Net_Send "zzz" "all" "MSK: $index"

    Add_WIP "$skeddate $skedutc $skedtext"
  }

  # Update the other stations concept of WIP and Busy every 10 seconds.
  if { $stuff(wip) != $stuff(lastwip) || \
    $::setting(wiplimit) != $stuff(lastwiplimit) || \
    $stuff(busy) != $stuff(lastbusy) } {

    Net_Send "wip" "all" ""

    set stuff(lastwip) $stuff(wip)
    set stuff(lastwiplimit) $::setting(wiplimit)
    set stuff(lastbusy) $stuff(busy)
  }

  return
}

#
# Store_Loc - procedure to save all window geometries
#

proc Store_Loc { } {
  global windows .

  set fid [ open "roverlog_loc.ini" w 0666 ]

  set t [clock seconds]
  set date [clock format $t -format "%Y-%m-%d"]
  set utc [clock format $t -format "%H:%M:%S"]
  set d "$date $utc"

  puts $fid "# Saved $d"

  set windowslist [ list net loghead skeds calc map score shortcuts keyer lookup info pass comms ]

  update idletasks

  foreach w $windowslist {
    set s [ wm state $windows($w) ]
    puts $fid "# $w $s"
    puts $fid "wm state \$windows($w) $s"
    set g [ wm geometry $windows($w) ]
    puts $fid "# $w $g"
    scan $g "%*dx%*d+%d+%d" x y
    puts $fid "wm geometry \$windows($w) =+$x+$y"
  }
  set g [ wm geometry . ]
  puts $fid "# . $g"
  scan $g "%*dx%*d+%d+%d" x y
  puts $fid "wm geometry . =+$x+$y"

  close $fid
}

# Modules List

set modules {
  { Keyer keyer.tcl }
  { Super super.tcl }
  { Rotor rotor.tcl }
  { Rig rig.tcl }
  { GPS gps.tcl }
  { Clock roverclk.tcl }
}

proc Sleep {time} {
  global Sleep_End
  after $time set Sleep_End 1
  vwait Sleep_End
}
  

# Start_Modules - procedure to start up selected modules.

proc Start_Modules { } {
  global modules stuff

  foreach module $modules {

    set m [ lindex $module 0 ]
    set x [ lindex $module 1 ]

    if { $::setting(Start_$m) == 1 } {
      Debug "Start_Modules" "Starting $m..."
      # windows OS
      if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
        exec wishexec $x &
      # non-windows OS
      } else {
        exec wish $x &
      }
    }
  }

  Sleep 5

  # Now open comms with each module started
  foreach module $modules {

    set m [ lindex $module 0 ]
    set x [ lindex $module 1 ]

    if { $::setting(Start_$m) == 1 } {

      Debug "Start_Modules" "Opening communications with $m..."

      switch -exact -- $m {
      "Keyer" {
	Open_Keyer
      }
      "Super" {
	Open_Super
      }
      "Rotor" {
	Open_Rotor
      }
      "Rig" {
        for { set i 1 } { $i < 18 } { incr i } {
          Debug "Start_Modules" "Rig $i"
	  Open_Rig $i
        }
      }
      "GPS" {
	Open_GPS
      }
      default {
      }
      }
    }
  }

}

proc Stop_Modules { } {
  global modules stuff

  foreach module $modules {
    set m [ lindex $module 0 ]
    set x [ lindex $module 1 ]
    if { $::setting(Start_$m) == 1 } {
      Debug "Stop_Modules" "Stopping $m..."
      # send "quit!" to each one.
      switch -exact -- $m {
      "Keyer" {
	Close_Keyer "quit"
      }
      "Super" {
	Close_Super "quit"
      }
      "Rotor" {
	Close_Rotor "quit"
      }
      "Rig" {
        for { set i 1 } { $i < 18 } { incr i } {
	  Close_Rig "quit" $i
        }
      }
      "GPS" {
	Close_GPS "quit"
      }
      "Clock" {
        file delete "roverclk.txt"
      }
      default {
      }
      }
    }
  }
}

proc Guess_UTC_Offset { } {

  set t [ clock seconds ]
  set s1 [ clock format $t -format "%a %b %d %H:%M:%S" -gmt true ]
  set s2 [ clock format $t -format "%a %b %d %H:%M:%S" -gmt false ]
  set t1 [ clock scan $s1 ]
  set t2 [ clock scan $s2 ]
  set r [ expr ( $t1 - $t2 ) / 3600 ]
  Debug "Guess_UTC_Offset" "UTC Offset $r"
  return $r
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

# Begin

# make the debug window early to allow debugging
set windows(debug) [Build_Debug .debug]
set windows(hist) [Build_Hist .hist]

# set default values
set stuff(debug) 0
set stuff(utcoffset) [ Guess_UTC_Offset ]

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

# override values if the .ini file is there

set inifound 0
set contestinifound 0
if [ file readable "roverlog.ini" ] {
  source "roverlog.ini"
  if { [ info exists ::setting(contestini) ] } {
    if [ file readable $::setting(contestini) ] {
      source $::setting(contestini)
      set contestinifound 1
    } else {
      set contestinifound 0
    }
  }
  Clean_Up_Ini
  set inifound 1
} else {
  set inifound 0
}  

Build_Main
Init

# set windows(.) .
set windows(net) [Build_Net .net]
Net_Start
set windows(loghead) [Build_Loghead .loghead]
set windows(skeds) [Build_Skeds .skeds]
set windows(pass) [Build_Pass .pass]
set windows(calc) [Build_Calc .calc]
set windows(map) [Build_Map .map]
set windows(score) [Build_Score .score]
set windows(shortcuts) [Build_Shortcuts .shortcuts]
set windows(keyer) [Build_Keyer .keyer]
set windows(lookup) [Build_Lookup .lookup]
set windows(info) [Build_Info .info]
set windows(comms) [Build_Comms .comms]

# bindings

# windows include: . keyer map skeds net lookup loghead calc score shortcuts
#                  freq

# all windows (window switching)
bind all <Alt-Key-A> { Accept_WIP next }
bind all <Alt-Key-a> { Accept_WIP next }
bind all <Alt-Key-C> Popup_Calc
bind all <Alt-Key-c> Popup_Calc
bind all <Alt-Key-F> Popup_Info
bind all <Alt-Key-f> Popup_Info
bind all <Alt-Key-H> { Shortcuts }
bind all <Alt-Key-h> { Shortcuts }
bind all <Alt-Key-I> { Keyer_Puts "tx!" }
bind all <Alt-Key-i> { Keyer_Puts "tx!" }
bind all <Alt-Key-J> Move_Rotor
bind all <Alt-Key-j> Move_Rotor
bind all <Alt-Key-K> { Popup_Skeds "nokeep" }
bind all <Alt-Key-k> { Popup_Skeds "nokeep" }
bind all <Alt-Key-L> { Popup_Lookup "buds" }
bind all <Alt-Key-l> { Popup_Lookup "partial" }
bind all <Alt-Key-M> { Popup_Map $stuff(sent) }
bind all <Alt-Key-m> { Popup_Map $stuff(sent) }
bind all <Alt-Key-N> Popup_Net
bind all <Alt-Key-n> Popup_Net
bind all <Alt-Key-P> { Popup_Pass "nokeep" }
bind all <Alt-Key-p> { Popup_Pass "nokeep" }
bind all <Alt-Key-Q> Popup_Comms
bind all <Alt-Key-q> Popup_Comms
bind all <Alt-Key-S> Popup_Score
bind all <Alt-Key-s> Popup_Score
bind all <Alt-Key-T> Cancel_Edit
bind all <Alt-Key-t> Cancel_Edit
bind all <Alt-Key-X> { Popup_Map $stuff(recd) }
bind all <Alt-Key-x> { Popup_Map $stuff(recd) }
bind all <Alt-Key-Y> Popup_Keyer
bind all <Alt-Key-y> Popup_Keyer
bind all <Alt-Key-F4> { wm withdraw [ winfo toplevel [ focus ] ] }
bind all <F12> { wm deiconify . ; raise . ; $windows(loglist) see end ; \
  focus $windows(callentry) ; $windows(callentry) icursor end ; \
  $windows(callentry) select range 0 end }

# network bindings
for { set i 1 } { $i < 13 } { incr i } {
  bind all <Control-Key-F$i> \
    "set stuff(peername) [lindex $::setting(p$i) 0] ; Popup_Net"
}

# CW keyer bindings
for { set i 1 } { $i < 7 } { incr i } {
  bind all <Alt-Key-$i> "Play_CW $i"
  if { $::setting(fkeys) == "Keyer" } {
      bind all <F$i> "Play_CW $i"
  }
}

bind $windows(m6entry) <Return> "Play_CW 6"
bind $windows(keyer) <Alt-Key-W> { set stuff(m6) "" }
bind $windows(keyer) <Alt-Key-w> { set stuff(m6) "" }
bind $windows(keyer) <Prior> { Keyer_Puts "qrq!" }
bind $windows(keyer) <Next> { Keyer_Puts "qrs!" }

# voice keyer bindings
for { set i 7 } { $i < 10 } { incr i } {
  bind all <Alt-Key-$i> "Play_Voice $i"
  if { $::setting(fkeys) == "Keyer" } {
    bind all <F$i> "Play_Voice $i"
  }
}

# both keyer bindings
bind all <Escape> { Keyer_Puts "stop!" ; wm deiconify . ; raise . ; focus $windows(callentry) ; \
  $windows(callentry) icursor end ; $windows(callentry) select range 0 end }
    
# QSY bindings
if { $::setting(fkeys) == "QSY" } {
  for { set i 0 } { $i < 11 } { incr i } {
    set j [ expr $i + 1 ]
    bind all <F$j> "FKey_QSY $i"
  }
}

# main window only
bind . <Alt-Key-B> { Main_QSY -1 }
bind . <Alt-Key-b> { Main_QSY 1 }
bind . <Alt-Key-D> Delete_Entry
bind . <Alt-Key-d> Delete_Entry
bind . <Alt-Key-E> Edit_Entry
bind . <Alt-Key-e> Edit_Entry
# bind . <Alt-Key-G> Toggle_gps
# bind . <Alt-Key-g> Toggle_gps
bind . <Alt-Key-O> Next_Mode
bind . <Alt-Key-o> Next_Mode
# bind . <Alt-Key-R> Toggle_realtime
# bind . <Alt-Key-r> Toggle_realtime
bind . <Alt-Key-u> Popup_Debug
bind . <Alt-Key-V> { Save_Settings }
bind . <Alt-Key-v> { Save_Settings }
bind . <Alt-Key-W> { Clear_Entry force ; Lookup_Recd "unlock" }
bind . <Alt-Key-w> { Clear_Entry force ; Lookup_Recd "unlock" }
bind . <Alt-Key-Z> Call_Stack_Pop
bind . <Alt-Key-z> Call_Stack_Pop
bind . <Alt-Key-equal> { Main_QSY 1 }
bind . <Alt-Key-plus>  { Main_QSY 1 }
bind . <Alt-Key-minus> { Main_QSY -1 }
bind . <Return> Log_QSO

bind $windows(sententry) <KeyRelease> {+Bear_Calc $stuff(sent) $stuff(recd) ; \
  Do_Lookup "partial" $stuff(call) $stuff(recd) $stuff(sent) }

proc HCO_Light { state } {
  global windows

  Debug "HCO_Light" "HCO Light $state"

  if { $state == "on" } {
    $windows(callentry) configure -fg red
    $windows(recdentry) configure -fg red
  } else {
    $windows(callentry) configure -fg black
    $windows(recdentry) configure -fg black
  }
}

proc Pre_Call_Entry_Key { key } {
  global stuff windows
  
  Debug "Pre_Call_Entry_Key" "$key"

  set stuff(callentryinsert) [ $windows(callentry) index insert ]

  if { $key == " " } {
    Lookup_Recd "query"
    focus $windows(recdentry)
    set r [ string first "?" $stuff(recd) ]  
    if { $r != -1 } {
      $windows(recdentry) icursor $r
      $windows(recdentry) select range $r [ expr $r + 1 ]
    } else {
      # put the cursor back where it was
      if { [ info exists stuff(recdentryinsert) ] } {
        if { $stuff(recdentryinsert) == "all" } {
          $windows(recdentry) icursor end
          $windows(recdentry) select range 0 end
        } else {
          $windows(recdentry) icursor $stuff(recdentryinsert)
          $windows(recdentry) select range $stuff(recdentryinsert) \
            $stuff(recdentryinsert)
        }
      } else {
        $windows(recdentry) icursor end
        $windows(recdentry) select range end end
      }
    }

    if { [ Dupe_Check "strict" "quiet" $stuff(band) "" "" $stuff(sent) \
      $stuff(call) $stuff(recd) ] == 1 } {
      Annunciate "Possible Dupe Found"
    }
    return 0
  } elseif { $key == "\t" } {
    Lookup_Recd "query"
    if { [ Dupe_Check "strict" "quiet" $stuff(band) "" "" $stuff(sent) \
      $stuff(call) $stuff(recd) ] == 1 } {
      Annunciate "Possible Dupe Found"
    }
    return 1
  } else {
    return 1
  }
}  

proc Post_Call_Entry_Key { key } {
  global stuff windows

  # Convert to upper string only if necessary.
  if { [ string is alnum "$key" ] } {
    set stuff(call) [ string trim $stuff(call) ]
    set stuff(call) [ string toupper $stuff(call) ]
  }

  # In case we hit backspace or something - is the call different
  if { [ Drop_Slash "rover" $stuff(call) ] != [ Drop_Slash "rover" $stuff(lastcall) ] } {
    HCO_Light "on"
    Do_Lookup "partial" $stuff(call) $stuff(recd) $stuff(sent)
#    if { [ string first $stuff(lastcall) $stuff(call) ] == -1 } {
#      set stuff(recdentryinsert) all
#    }
    set stuff(lastcall) $stuff(call)
    set stuff(recdentryinsert) all
  }
}

bindtags $windows(callentry) \
  {PreCallEntry $windows(callentry) Entry PostCallEntry . all}
bind PreCallEntry <KeyPress> {if { [ Pre_Call_Entry_Key %A ] == 0 } { break }}
bind PostCallEntry <KeyPress> {Post_Call_Entry_Key %A}

proc Pre_Recd_Entry_Key { key } {
  global stuff windows

  Debug "Pre_Recd_Entry_Key" "$key"

  set stuff(recdentryinsert) [ $windows(recdentry) index insert ]

  if { $key == " " } {
    focus $windows(callentry)
    set r [ string first "?" $stuff(call) ]  
    if { $r != -1 } {
      $windows(callentry) icursor $r
      $windows(callentry) select range $r [ expr $r + 1 ]
    } else {
      if { [ info exists stuff(callentryinsert) ] } {
        # put the cursor back where it was
        $windows(callentry) icursor $stuff(callentryinsert)
        $windows(callentry) select range $stuff(callentryinsert) \
          $stuff(callentryinsert)
      } else {
        $windows(callentry) icursor end
        $windows(callentry) select range end end
      }
    }

    if { [ Dupe_Check "strict" "quiet" $stuff(band) "" "" $stuff(sent) \
      $stuff(call) $stuff(recd) ] == 1 } {
      Annunciate "Possible Dupe Found"
    }
    return 0
  } elseif { $key == "\t" } {
    if { [ Dupe_Check "strict" "quiet" $stuff(band) "" "" $stuff(sent) \
      $stuff(call) $stuff(recd) ] == 1 } {
      Annunciate "Possible Dupe Found"
    }
    # allow Tk to do the normal Tab stuff
    return 1
  } else {
    return 1
  }
}

proc Post_Recd_Entry_Key { key } {
  global windows stuff

  if { [ string is alnum "$key" ] } {
    Lookup_Recd "lock"
    set stuff(recd) [ string trim $stuff(recd) ]
    set stuff(recd) [ string toupper $stuff(recd) ]
  }

  # In case we hit backspace or something
  if { $stuff(recd) != $stuff(lastrecd) } {
    HCO_Light "on"
    Bear_Calc $stuff(sent) $stuff(recd)
    set stuff(lastrecd) $stuff(recd)
  }
} 

bindtags $windows(recdentry) \
  {PreRecdEntry $windows(recdentry) Entry PostRecdEntry . all}
bind PreRecdEntry <KeyPress> {if { [ Pre_Recd_Entry_Key %A ] == 0 } { break }}
bind PostRecdEntry <KeyPress> {Post_Recd_Entry_Key %A}

bind $windows(bandmenubut) <ButtonPress> {+Store_Op_Freq}

# map window only
bind $windows(map) <Return> { Redraw_Map $stuff(mapcenter) }
bind $windows(map) <Alt-Key-equal> { set stuff(mapband) \
  [ QSY $stuff(mapband) 1 ] ; Redraw_Map $stuff(mapcenter) }
bind $windows(map) <Alt-Key-plus>  { set stuff(mapband) \
  [ QSY $stuff(mapband) 1 ] ; Redraw_Map $stuff(mapcenter) }
bind $windows(map) <Alt-Key-minus> { set stuff(mapband) \
  [ QSY $stuff(mapband) -1 ] ; Redraw_Map $stuff(mapcenter) }

# skeds window only

proc Post_Sked_List_Arrow { } {
  Set_Sked_Time_From_Row "active"
}

bindtags $windows(skedlist) \
  {Pre_Sked_List_Tag $windows(skedlist) Listbox Post_Sked_List_Tag all}
bind Pre_Sked_List_Tag <Next> {Redraw_Skeds "later" ; break}
bind Pre_Sked_List_Tag <Prior> {Redraw_Skeds "earlier" ; break}
bind Pre_Sked_List_Tag <Alt-Key-B> { set stuff(skedband) \
  [ QSY $stuff(skedband) -1 ] ; Set_Sked_Freq_From_Band }
bind Pre_Sked_List_Tag <Alt-Key-b> { set stuff(skedband) \
  [ QSY $stuff(skedband) 1 ] ; Set_Sked_Freq_From_Band }
bind Pre_Sked_List_Tag <Alt-Key-plus> { set stuff(skedband) \
  [ QSY $stuff(skedband) 1 ] ; Set_Sked_Freq_From_Band }
bind Pre_Sked_List_Tag <Alt-Key-equal> { set stuff(skedband) \
  [ QSY $stuff(skedband) 1 ] ; Set_Sked_Freq_From_Band }
bind Pre_Sked_List_Tag <Alt-Key-minus> { set stuff(skedband) \
  [ QSY $stuff(skedband) -1 ] ; Set_Sked_Freq_From_Band }
bind Pre_Sked_List_Tag <Alt-Key-bracketright> { Sked_Peer "next" }
bind Pre_Sked_List_Tag <Alt-Key-bracketleft> { Sked_Peer "prev" }
bind Post_Sked_List_Tag <Up> {Post_Sked_List_Arrow}
bind Post_Sked_List_Tag <Down> {Post_Sked_List_Arrow}
bind Post_Sked_List_Tag <ButtonRelease> {+Set_Sked_Time_From_Row "anchor"} 
bind Post_Sked_List_Tag <Return> { Add_Sked }

bind $windows(skeds) <Alt-Key-D> { Delete_Sked "deleted" }
bind $windows(skeds) <Alt-Key-d> { Delete_Sked "deleted" }
bind $windows(skeds) <Alt-Key-E> Copy_Sked
bind $windows(skeds) <Alt-Key-e> Copy_Sked
bind $windows(skeds) <Alt-Key-W> { set stuff(skedfreq) "" ; set stuff(skedcall) "" ; \
  set stuff(skedrecd) "" ; set stuff(skednote) "" ; focus $windows(skedfreqentry) }
bind $windows(skeds) <Alt-Key-w> { set stuff(skedfreq) "" ; set stuff(skedcall) "" ; \
  set stuff(skedrecd) "" ; set stuff(skednote) "" ; focus $windows(skedfreqentry) }
bind $windows(skeds) <Return> { Add_Sked }

bind $windows(skeds) <Alt-Key-B> { set stuff(skedband) \
  [ QSY $stuff(skedband) -1 ] ; Set_Sked_Freq_From_Band }
bind $windows(skeds) <Alt-Key-b> { set stuff(skedband) \
  [ QSY $stuff(skedband) 1 ] ; Set_Sked_Freq_From_Band }
bind $windows(skeds) <Alt-Key-plus> { set stuff(skedband) \
  [ QSY $stuff(skedband) 1 ] ; Set_Sked_Freq_From_Band }
bind $windows(skeds) <Alt-Key-equal> { set stuff(skedband) \
  [ QSY $stuff(skedband) 1 ] ; Set_Sked_Freq_From_Band }
bind $windows(skeds) <Alt-Key-minus> { set stuff(skedband) \
  [ QSY $stuff(skedband) -1 ] ; Set_Sked_Freq_From_Band }

proc Sked_Peer { dir } {
  global windows stuff

  if { $dir != "current" } {
    if { $dir == "next" } {
      set i [ expr [ Peer_By_Name $stuff(skedpeer) ] + 1 ]
      if { $i > 12 } { set i 1 }
    } elseif { $dir == "prev" } {
      set i [ expr [ Peer_By_Name $stuff(skedpeer) ] - 1 ]
      if { $i < 1 } { set i 12 }
    }
    set stuff(skedpeer) [ lindex $::setting(p$i) 0 ]
  } else {
    set i [ Peer_By_Name $stuff(skedpeer) ]
  }

  if { $stuff(skedpeer) == $::setting(mypeername) } {
    set stuff(skedfreq) $stuff(opfreq)
    set stuff(skedband) $stuff(band)
    $windows(skedwipentry) configure -textvariable stuff(wip)
    $windows(skedwiplimitentry) configure -textvariable ::setting(wiplimit)
    $windows(skedbusyentry) configure -textvariable stuff(busy)
    $windows(passwipentry) configure -textvariable stuff(wip)
    $windows(passwiplimitentry) configure -textvariable ::setting(wiplimit)
    $windows(passbusyentry) configure -textvariable stuff(busy)
  } else {
    # Do something more interesting if we don't know the Freq for this guy.
    if { $stuff(peerfreq$i) == "" } {
      if { [ llength $::setting(p$i) ] > 3 } {
        set stuff(skedfreq) "?"
        set stuff(skedband) [ lindex $::setting(p$i) 3 ]
      }
    } else {
      set stuff(skedfreq) $stuff(peerfreq$i)
      set band [ Band_By_Freq $stuff(skedfreq) ]
      if { $band != 0 } {
        set stuff(skedband) $band
      }
    }

    $windows(skedwipentry) configure -textvariable stuff($stuff(skedpeer),wip)
    $windows(skedwiplimitentry) configure -textvariable \
      stuff($stuff(skedpeer),wiplimit)
    $windows(skedbusyentry) configure -textvariable stuff($stuff(skedpeer),busy)
    $windows(passwipentry) configure -textvariable stuff($stuff(skedpeer),wip)
    $windows(passwiplimitentry) configure -textvariable \
      stuff($stuff(skedpeer),wiplimit)
    $windows(passbusyentry) configure -textvariable stuff($stuff(skedpeer),busy)
  }
  Redraw_Skeds "entry"
  First_Available_Sked
}

#
# Band_By_Freq - Return the band given a frequency.
#                Note, this is not perfect.
#

proc Band_By_Freq { f } {

  if { $f == "" } { return 0 }
  if { $f >= 50  && $f < 54 }     { return 50 }
  if { $f >= 144 && $f < 148 }    { return 144 }
  if { $f >= 222 && $f < 225 }    { return 222 }
  if { $f >= 420 && $f < 450 }    { return 432 }
  if { $f >= 902 && $f < 928 }    { return 902 }
  if { $f >= 1240 && $f < 1300 }  { return 1.2G }
  if { $f >= 2300 && $f < 2310 }  { return 2.3G }
  if { $f >= 2390 && $f < 2450 }  { return 2.3G }
  if { $f >= 3300 && $f < 3500 }  { return 3.4G }
  if { $f >= 5650 && $f < 5925 }  { return 5.7G }
  if { $f >= 10000 && $f < 10500 }  { return 10G }
  if { $f >= 24000 && $f < 24250 } { return 24G }
  if { $f >= 47000 && $f < 47200 }  { return 47G }
  if { $f >= 75500 && $f < 76000 }  { return 76G }
  if { $f >= 77000 && $f < 81000 }  { return 76G }
  if { $f >= 119980 && $f < 120020 } { return 119G }
  if { $f >= 142000 && $f < 149000 } { return 142G }
  if { $f >= 241000 && $f < 250000 } { return 241G }
  if { $f >= 300000 } { return 300G }
  return 0
}

bind $windows(skeds) <Alt-Key-bracketright> { Sked_Peer "next" }
bind $windows(skeds) <Alt-Key-bracketleft> { Sked_Peer "prev" }

# pass window only

bind $windows(pass) <Alt-Key-W> { set stuff(skedcall) "" ; \
  set stuff(skedrecd) "" }
bind $windows(pass) <Alt-Key-w> { set stuff(skedcall) "" ; \
  set stuff(skedrecd) "" }

bind $windows(pass) <Alt-Key-B> { set stuff(skedband) \
  [ QSY $stuff(skedband) -1 ] ; Set_Sked_Freq_From_Band }
bind $windows(pass) <Alt-Key-b> { set stuff(skedband) \
  [ QSY $stuff(skedband) 1 ] ; Set_Sked_Freq_From_Band }
bind $windows(pass) <Alt-Key-plus> { set stuff(skedband) \
  [ QSY $stuff(skedband) 1 ] ; Set_Sked_Freq_From_Band }
bind $windows(pass) <Alt-Key-equal> { set stuff(skedband) \
  [ QSY $stuff(skedband) 1 ] ; Set_Sked_Freq_From_Band }
bind $windows(pass) <Alt-Key-minus> { set stuff(skedband) \
  [ QSY $stuff(skedband) -1 ] ; Set_Sked_Freq_From_Band }

bind $windows(pass) <Alt-Key-bracketright> { Sked_Peer "next" }
bind $windows(pass) <Alt-Key-bracketleft> { Sked_Peer "prev" }

# if Call or Recd changes, update the "What_Bands" fields.

bind $windows(passcallentry)

proc Post_Pass_Call_Entry_Key { k } {
  global stuff

  if { $k == "Return" } {
    Make_Pass
    return 0
  }

  What_Bands
  return 1
} 

bindtags $windows(passcallentry) \
  {$windows(passcallentry) Entry PostPassCallEntry $windows(pass) all}
bind PostPassCallEntry <KeyPress> {if { [ Post_Pass_Call_Entry_Key %K ] == 0 } { break }}

# ---

bind $windows(passrecdentry)

proc Post_Pass_Recd_Entry_Key { k } {
  global stuff

  if { $k == "Return" } {
    Make_Pass
    return 0
  }

  # TODO - fix for grid6
  set recd [ string toupper [ string range $stuff(skedrecd) 0 3 ] ]
  if { [ Valid_Grid $recd ] } {
    What_Bands
  }

  return 1
} 

bindtags $windows(passrecdentry) \
  {$windows(passrecdentry) Entry PostPassRecdEntry $windows(pass) all}
bind PostPassRecdEntry <KeyPress> {if { [ Post_Pass_Recd_Entry_Key %K ] == 0 } { break }}

bind $windows(pass) <Return> { Make_Pass }

# net window only
bind $windows(net)       <Return> { Net_Send "msg" $stuff(peername) \
  "$stuff(netmsg)" ; set stuff(netmsg) "" ; if { $::setting(quicknet) == 1 } \
  { focus $windows(callentry) ; $windows(callentry) icursor end ; \
  $windows(callentry) select range 0 end } }

proc Net_Peer { dir } {
  global windows stuff

  if { $dir == "next" } {
    set i [ expr [ Peer_By_Name $stuff(peername) ] + 1 ]
    if { $i > 12 } { set i 0 }
  } else {
    set i [ expr [ Peer_By_Name $stuff(peername) ] - 1 ]
    if { $i < 0 } { set i 12 }
  }
  if { $i == 0 } {
    set stuff(peername) "all"
  } else {
    set stuff(peername) [ lindex $::setting(p$i) 0 ]
  }
}

bind $windows(net) <Alt-Key-bracketright> { Net_Peer "next" }
bind $windows(net) <Alt-Key-bracketleft> { Net_Peer "prev" }

# lookup window only
bind $windows(lookup)   <Return>    { Copy_Lookup "non-rover" }
bind $windows(lookup)   <Alt-Key-R> { Copy_Lookup "rover" }
bind $windows(lookup)   <Alt-Key-r> { Copy_Lookup "rover" }
bind $windows(lookup)   <Alt-Key-N> { Edit_Notes }
bind $windows(lookup)   <Alt-Key-n> { Edit_Notes }
bind $windows(lookup)   <Alt-Key-S> { Save_Notes }
bind $windows(lookup)   <Alt-Key-s> { Save_Notes }

# loghead window only
# nothing specific defined

# calc window only

bind $windows(calcgridentry)

proc Post_Calc_Entry_Key { k } {
  global stuff

  if { $k == "Return" } {
    Move_Rotor
    return 0
  }

  Bear_Calc $stuff(sent) $stuff(calcrecd)
  return 1
} 

bindtags $windows(calcgridentry) \
  {$windows(calcgridentry) Entry PostCalcEntry $windows(calc) all}
bind PostCalcEntry <KeyPress> {if { [ Post_Calc_Entry_Key %K ] == 0 } { break }}

bind $windows(calc) <Return> { Bear_Calc $stuff(sent) $stuff(calcrecd) }

# score window only
# nothing specific defined

# shortcuts window only
# nothing specific defined

# Info window only
bind $windows(stabandmenubut) <ButtonPress> {+Store_Op_Freq}
bind $windows(info) <Alt-Key-equal> { Main_QSY 1 }
bind $windows(info) <Alt-Key-plus>  { Main_QSY 1 }
bind $windows(info) <Alt-Key-minus> { Main_QSY -1 }
bind $windows(info) <Alt-Key-B>     { Main_QSY -1 }
bind $windows(info) <Alt-Key-b>     { Main_QSY 1 }

bind $windows(loglist) <Double-Button-1> {+Edit_Entry ; break}

# ----- end bindings

if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
  catch { wm iconbitmap . log.ico }
}
wm protocol . WM_DELETE_WINDOW My_Exit
# TODO - why doesn't this work?  The window still resizes in the horizontal
#        direction.  ARGH!
wm resizable . 0 1

#
# New - If selected, the main window stays on top.
#

if { $tcl_platform(os) != "Linux" && $tcl_platform(os) != "Darwin" } {
  if { $::setting(maintop) } {
    wm attributes . -topmost yes
  }
}


# Load in the lookupgrid database.
Load_Lookup

# if the log is readable, load it in
if [file readable $::setting(logfile)] {
  set stuff(filesize) [ file size $::setting(logfile) ]
  set fid [open $::setting(logfile) r]
  set stuff(entries) [ ReadFile "open" $fid ]
  close $fid
# otherwise make a dummy header
} else {
  New_Loghead
}  

# Save updated lookupgrid database.
Save_Lookup

Redraw_Map $stuff(sent)
Load_Skeds
Set_Title
Update_Both

if { $inifound == 0 } {
  tk_messageBox -icon warning -type ok \
    -title "Ini File Not Found" -message "roverlog.ini was not found in the current directory.  Using defaults.\nIt is strongly recommended that you run inied.tcl."
} else {
  if { $::setting(iniversion) != $stuff(rlversion) } {
    tk_messageBox -icon warning -type ok \
      -title "Version Mismatch" -message "Ini file version does not match RoverLog version.  Run inied.tcl."
  }

  if { $contestinifound == 0 } {
    tk_messageBox -icon warning -type ok \
      -title "Contest Ini File Not Found" -message "$::setting(contestini) was not found in the current directory.  Using defaults.\nIt is strongly recommended that you set the contest ini file setting to a\nreal file name.  This setting is found on the files tab in inied.tcl."
  }
}

switch -exact -- $::tcl_platform(os) {
  "Darwin" {
  }
  default {
    if { $::setting(allowstationchanges) == 0 } {
      $windows(mycallentry) configure -state readonly
      $windows(sententry) configure -state readonly
      focus $windows(callentry)
      $windows(callentry) icursor end
      $windows(callentry) select range 0 end
    } else {
      $windows(mycallentry) configure -state normal
      $windows(sententry) configure -state normal
      focus $windows(mycallentry)
      $windows(mycallentry) icursor end
      $windows(mycallentry) select range 0 end
    }
  }
}


if { [ file readable "roverlog_loc.ini" ] } {
  source "roverlog_loc.ini"
  update idletasks
}

# console show

Recall_Op_Freq
# This causes us to blacklist the keyer due to an attempt to set the rig number.
# Set_Freq exec
Redraw_Score
Redraw_Map_Band
Bear_Calc $stuff(sent) $stuff(recd)
Net_Send "rfq" all ""
Net_Send "rwp" all ""
Do_Lookup "partial" $stuff(call) $stuff(recd) $stuff(sent)

Start_Modules

# tk_messageBox -icon warning -type ok \
#   -title "Development Release" \
#   -message "Warning: this version of RoverLog is a Development Release and may have major issues.  Be especially careful with existing logs, databases, etc.  Use at your own risk."
