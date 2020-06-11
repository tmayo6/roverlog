#!/bin/sh
# the next line restarts using wish \
exec wish "$0" "$@"

#
# RoverLog Keyer
#
# by Tom Mayo - 04/12/2005
#

#
# Sleep - Wait for a time.
#

proc Sleep { ms } {
  global sleepwait

  after $ms set sleepwait 0
  vwait sleepwait
}

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

  update idletasks
}

#
# Dump_Buffer - procedure to provide a hex dump of a buffer in the Debug Log.
#

proc Dump_Buffer { b } {

  set n [ string length $b ]
  set r "buffer:"

  for { set i 0 } { $i < $n } { incr i } {
    scan [ string index $b $i ] "%c" c
    set r [ format "%s %02.2x" $r $c ]
  }

  Debug "Dump_Buffer" "$r"
}

#
# Server_Open - procedure to open the IP receiving handler to respond to
#               network commands and queries.
#

proc Server_Open { } {
  global stuff

  Debug "Server_Open" "starting server"

  if [catch { socket -server Net_Accept $::setting(keyeripport) } stuff(ipfid) ] {
    unset stuff(ipfid)
    set ok [ tk_messageBox -icon warning -type okcancel \
      -title "Keyer Module Network Error" -message \
      "Cannot open socket on $::setting(keyeripport).\nModule already running?\nSelect Ok to continue anyway or Cancel to exit." ]
    if { $ok != "ok" } {
      Tx_Dekey_CW
      Tx_Dekey_Voice
      exit
    }
    return
  }

  proc Net_Accept {newSock addr port} {
    fconfigure $newSock -buffering line
    fileevent $newSock readable [list Serve_Request $newSock]
  }
}

#
# Server_Close - procedure to shut down the network handler.
#

proc Server_Close { } {
  global stuff

  if { [ info exists stuff(ipfid) ] } {
    Debug "Server_Close" "Stopping server"
    close $stuff(ipfid)
    unset stuff(ipfid)
  }
}

#
# Serve_Request - procedure to take care of network commands and queries.
#

proc Serve_Request { sock } {
  global stuff

  if {[eof $sock] || [catch {gets $sock line}]} {
    close $sock
  } else {
    set l [ split $line ]
    switch -exact -- [ lindex $l 0 ] {
      rignum! {
        set stuff(rignum) [ lindex $l 1 ]
        Debug "Serve_Request" "Received Set Rig Number $stuff(rignum) command."
        return
      }
      setcw! {
        if { [ llength $l ] != 5 } {
          Debug "Serve_Request" "Received incorrect number of arguments for Set CW command."
          return
        }

        Debug "Serve_Request" "Received Set CW $n command."
        set ::setting(mycall) [ lindex $l 1 ]
        set stuff(sent)       [ lindex $l 2 ]
        set stuff(call)       [ lindex $l 3 ]
        set stuff(recd)       [ lindex $l 4 ]
      }
      playcw! {

        set n [ lindex $l 1 ]

        if { $n < 1 || $n > 6 } {
          Debug "Serve_Request" "Received erroneous Play CW $n command."
          return
        }

        Debug "Serve_Request" "Received Play CW $n command."

        if { $n == 6 } {

          if { [ llength $l ] < 7 } {
            Debug "Serve_Request" "Received incorrect number of arguments for Play CW command."
            return
          }

          set ::setting(mycall) [ lindex $l 2 ]
          set stuff(sent)       [ lindex $l 3 ]
          set stuff(call)       [ lindex $l 4 ]
          set stuff(recd)       [ lindex $l 5 ]
          set ::setting(m6)     [ lrange $l 6 end ]
          set ::setting(m6)     [ join $::setting(m6) " " ]

        } else {

          if { [ llength $l ] != 6 } {
            Debug "Serve_Request" "Received incorrect number of arguments for Play CW command."
            return
          }

          set ::setting(mycall) [ lindex $l 2 ]
          set stuff(sent)       [ lindex $l 3 ]
          set stuff(call)       [ lindex $l 4 ]
          set stuff(recd)       [ lindex $l 5 ]
        }

        Play_CW $n
      }
      playv! {
        if { [ llength $l ] != 2 } {
          Debug "Serve_Request" "Received incorrect number of arguments for Play Voice command."
          return
        }
        set n [ lindex $l 1 ]
        if { $n < 6 || $n > 9 } {
          Debug "Serve_Request" "Received erroneous Play Voice $n command."
          return
        }
        Debug "Serve_Request" "Received Play Voice $n command."
        Play_Voice_Number $n
      }
      tx! {
        Tx_Key_Voice nomixer
      }
      stop! {
        Tx_Dekey_CW
        Tx_Dekey_Voice
        Sound_Stop
      }
      qrq! {
        Keyer_CW_Speed +1
      }
      qrs! {
        Keyer_CW_Speed -1
      }
      quit! {
        Net_Exit
      }
      default {
        puts $sock "Received unknown command."
      }
    }
  }
}

#
# Server_Restart - procedure to stop and restart the network handler.
#

proc Server_Restart { } {
  Server_Close
  Server_Open
}

#
# Sound_Init - Load sound library, but only if enabled.
#

proc Sound_Init { } {
  global snd stuff

  if { $::setting(sndenable) == 0 } {
    return
  }

  switch -exact -- $::tcl_platform(os) {
    "Linux" {
      package require snack
    }
    "Darwin" {
      package require snack
    }
    default {
      load libsnack.dll
    }
  }

  Sound_Init_CW
  Sound_Init_Voice

  return
}

#
# Mixer_Key - procedure to run the external mixer program when keying.
#

proc Mixer_Key { } {
  Debug "Mixer_Key" "setting mixer to keyed state."
  # set the mixer to the keyed state
  if { $::setting(sndenable) == 1 } {
    if { $::setting(mixerkeycmd) != "" } {
      catch [ eval $::setting(mixerkeycmd) ]
    }
  }
}

#
# Mixer_Dekey - procedure to run the external mixer program when dekeying.
#

proc Mixer_Dekey { } {
  Debug "Mixer_Dekey" "setting mixer to dekeyed state."
  # set the mixer to the dekeyed state
  if { $::setting(sndenable) == 1 } {
    if { $::setting(mixerdekeycmd) != "" } {
      catch [ eval $::setting(mixerdekeycmd) ]
    }
  }
}

#
# Open_Voice - procedure to open serial port for voice keyer
#

proc Open_Voice { } {
  global stuff

  if { $::setting(vkeyerport) == "" || $::setting(vkeyerport) == "None" } {
    Debug "Open_Voice" "not opening voice keyer serial port, blank"
    return
  }

  set vkeyerport [ Fix_Serial_Port_Name $::setting(vkeyerport) ]

  Debug "Open_Voice" "opening voice keyer serial port"

  if { ! [ info exists stuff(vkeyerportfid) ] } {
    if [catch { set stuff(vkeyerportfid) [open $vkeyerport w 0666] } ] {
      tk_messageBox -icon error -type ok \
        -title "Oops" -message "Cannot open the voice keyer serial port."
      return
    }
  }

  # set the hardware lines to the dekeyed state.
  Tx_Dekey_Voice

# Note: fid stays open.
}

#
# Tx_Key_Voice - procedure to key the transmitter by configuring the serial port hardware lines
#
# The "mixer" parameter indicates the mixer key function should be executed.
# "nomixer" indicates just key the transmitter and don't monkey with the
# mixer settings.
#

proc Tx_Key_Voice { mixer } {
  global stuff

  if { $mixer == "mixer" } {
    Mixer_Key
  }

  if { ! [ info exists stuff(vkeyerportfid) ] } {
    return
  }

  set stuff(voicekeyed) 1

  Debug "Tx_Key_Voice" "Configuring voice keyer serial port for keyed state."
  switch -exact -- $::tcl_platform(os) {
    "Darwin" {
    }
    "Linux" {
      fconfigure $stuff(vkeyerportfid) -handshake none \
        -ttycontrol $::setting(vkeyttycontrol) \
        -buffering line
    }
    default {
      fconfigure $stuff(vkeyerportfid) -handshake none \
        -ttycontrol $::setting(vkeyttycontrol) \
        -buffering line
    }
  }

# Note: fid stays open.
}

#
# Tx_Dekey_Voice - procedure to dekey by setting handshake lines to dekeyed state
#

proc Tx_Dekey_Voice { } {
  global stuff

  Mixer_Dekey

  if { ! [ info exists stuff(vkeyerportfid) ] } {
    return
  }

  # Don't muck with the serial port lines if we're already dekeyed.  It toggles
  # the lines due to the lousy Tcl serial port implementation.
  if { ! $stuff(voicekeyed) } {
    return
  }

  Debug "Tx_Dekey_Voice" "Configuring voice keyer serial port for dekeyed state."

  switch -exact -- $::tcl_platform(os) {
    "Darwin" {
    }
    "Linux" {
      fconfigure $stuff(vkeyerportfid) -handshake none \
        -ttycontrol $::setting(vdkeyttycontrol)
    }
    default {
      fconfigure $stuff(vkeyerportfid) -handshake none \
        -ttycontrol $::setting(vdkeyttycontrol)
    }
  }

  set stuff(voicekeyed) 0

# Note: fid stays open.
}

#
# Close_Voice - procedure to close the voice serial port.
#

proc Close_Voice { } {
  global stuff

  if { [ info exists stuff(vkeyerportfid) ] } {
    Debug "Close_Voice" "closing voice keyer serial port."
    close $stuff(vkeyerportfid)
    unset stuff(vkeyerportfid)
  }
}

proc Cycle_Voice_Serial_Port { } {
  Tx_Dekey_Voice
  Close_Voice
  Open_Voice
}

#
# WinKey_Read - procedure to handle responses from the WinKey.
#

proc WinKey_Read { } {
  global stuff windows

  # read in the message from the WinKey
  if { [ catch { read $stuff(keyerportfid) } r ] } {
    Debug "WinKey_Read" "error reading keyerportfid."
    return
  }

  # debug output
  Debug "WinKey_Read" "received message from WinKey"
  Dump_Buffer $r

  # if this couldn't be the status byte, return
  if { [ string length $r ] != 1 } {
    return
  }

  binary scan $r "c1" c

  # if this isn't the status byte or speed pot byte, it must be a character
  # note: this is f'ing awesome!
  if { ! ( $c & 0x80 ) } {
    $windows(m6entry) insert insert [ string tolower $r ]
    $windows(m6entry) xview insert
    return
  }

  # is this the status byte?
  if { $c & 0x40 } {

    # if still busy, return
    if { $c & 0x04 } {
      Debug "WinKey_Read" "WinKey still busy - waiting"
      return
    }

  # must be a speed pot change
  } else {

    # figure out wpm
    set wpm [ expr ( $c & 0x3f ) + 10 ]
    Debug "WinKey_Read" "speed pot changed to $wpm"

    set ::setting(wpm) $wpm

    # send cw speed to WinKey
    set m [ format "%02.2x" $wpm ]
    set m [ binary format H2 $m ]
    set m "\x02$m"
    Dump_Buffer $m
    puts -nonewline $stuff(keyerportfid) "$m"
    flush $stuff(keyerportfid)

    return
  }

  # if there is nothing left in the current message, return
  if { $stuff(remmsg) == "" } {

    Debug "WinKey_Read" "playback finished"

    if { $::setting(vkeyenable) == 1 } {
      Debug "WinKey_Read" "Dekeying Via Voice Port"
      Tx_Dekey_Voice
    }

    # this will only be set if I should schedule another
    # message to be played.
    if { [ info exists stuff(winkeyloop) ] } {
      Debug "WinKey_Read" "scheduling next message for looped play"
      if { ! [ string is integer -strict $::setting(loopdelay) ] || \
        ! ( $::setting(loopdelay) > 0 ) || \
        ! ( $::setting(loopdelay) < 60 ) } {
        tk_messageBox -icon error -type ok \
          -title "Oops" -message "The loop delay must be between 1 and 60 seconds."
      } else {
        set stuff(loopid) [ after [ expr int( 1000 * $::setting(loopdelay) ) ] Play_CW $stuff(winkeyloop) ]
      }
    }

    return
  }

  Debug "WinKey_Read" "continuing playback"

  # set up the message for now and for later
  set msg [ string range $stuff(remmsg) 0 29 ]
  set msg "$msg"
  set stuff(remmsg) [ string range $stuff(remmsg) 30 end ]

  # output the next chunk
  Debug "WinKey_Read" "sending $msg"
  puts -nonewline $stuff(keyerportfid) "$msg"
  flush $stuff(keyerportfid)
}

#
# Clear_WinKey - procedure to wipe out WinKey message in progress.
#

proc Clear_WinKey { } {
  global stuff

  # clear message
  Debug "Clear_WinKey" "clearing WinKey message"
  set stuff(remmsg) ""
  set m "\x0a"
  Dump_Buffer $m
  if { [ info exists stuff(keyerportfid) ] } {
    puts -nonewline $stuff(keyerportfid) $m
    flush $stuff(keyerportfid)
  }
}

proc Fix_Serial_Port_Name { s } {
  global tcl_platform

  if { $s == "" } {
    return ""
  }

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


#
# Open_CW - procedure to actually open the CW keyer serial port and
#           set it up.  Note: called once at startup.
#

proc Open_CW { } {
  global stuff

  if { $::setting(keyerport) == "" || $::setting(keyerport) == "None" } {
    Debug "Open_CW" "Not opening CW keyer serial port, blank"
    return
  }

  set keyerport [ Fix_Serial_Port_Name $::setting(keyerport) ]

  Debug "Open_CW" "opening CW keyer serial port"
  if { ! [ info exists stuff(keyerportfid) ] } {
    if [catch { set stuff(keyerportfid) [open $keyerport r+ ] } ] {
      tk_messageBox -icon error -type ok \
        -title "Oops" -message "Cannot open the CW keyer serial port."
      return
    }
  }

  # For winkey, set up the hardware lines to the TX state
  if { $::setting(keyerproto) == "winkey" } {

    switch -exact -- $::tcl_platform(os) {
      "Darwin" {
        fconfigure $stuff(keyerportfid) -mode \
          $::setting(keyermode) \
          -buffering none -encoding binary -translation { binary binary } \
          -blocking 0
      }
      "Linux" {
        fconfigure $stuff(keyerportfid) -handshake none -mode \
          $::setting(keyermode) -ttycontrol $::setting(cwkeyttycontrol) \
          -buffering none -encoding binary -translation { binary binary } \
          -blocking 0
      }
      default {
        fconfigure $stuff(keyerportfid) -handshake none -mode \
          $::setting(keyermode) -ttycontrol $::setting(cwkeyttycontrol) \
          -buffering none -encoding binary -translation { binary binary } \
          -blocking 0
      }
    }

  } else {

  	Debug "Open_CW" "Mode $::setting(keyermode) TTY Control $::setting(cwdkeyttycontrol)"

    switch -exact -- $::tcl_platform(os) {
      "Darwin" {
        fconfigure $stuff(keyerportfid) -mode \
          $::setting(keyermode) \
          -buffering none -encoding binary -translation { binary binary } \
          -blocking 0
      }
      "Linux" {
        fconfigure $stuff(keyerportfid) -handshake none -mode \
          $::setting(keyermode) -ttycontrol $::setting(cwdkeyttycontrol) \
          -buffering none -encoding binary -translation { binary binary } \
          -blocking 0
      }
      default {
        fconfigure $stuff(keyerportfid) -handshake none -mode \
          $::setting(keyermode) -ttycontrol $::setting(cwdkeyttycontrol) \
          -buffering none -encoding binary -translation { binary binary } \
          -blocking 0
      }
    }

    # set the hardware lines to the dekeyed state.
    Tx_Dekey_CW

  }

# Note: fid always stays open.
}

#
# Tx_Key_CW - procedure to key the transmitter by configuring the serial port hardware lines
#

proc Tx_Key_CW { } {
  global stuff

  # Nothing to do for Winkey.
  if { $::setting(keyerproto) == "winkey" } {
    return
  }

  Debug "Tx_Key_CW" "not WinKey."

  # Do this in case the user wants to set the mixer some way when using audio for CW
  Mixer_Key

  # Make sure the port is open
  if { [ info exists stuff(keyerportfid) ] } {

    set stuff(cwkeyed) 1

    Debug "Tx_Key_CW" "configuring CW keyer serial port for keyed state."
    switch -exact -- $::tcl_platform(os) {
      "Darwin" {
        fconfigure $stuff(keyerportfid) -mode \
          $::setting(keyermode) -buffering line
      }
      "Linux" {
        fconfigure $stuff(keyerportfid) -handshake none -mode \
          $::setting(keyermode) -ttycontrol $::setting(cwkeyttycontrol) \
          -buffering line
      }
      default {
        fconfigure $stuff(keyerportfid) -handshake none -mode \
          $::setting(keyermode) -ttycontrol $::setting(cwkeyttycontrol) \
          -buffering line
      }
    }
  }

# Note: fid stays open.
}

#
# Tx_Dekey_CW - procedure to dekey CW.
#

proc Tx_Dekey_CW { } {
  global stuff

  if { $::setting(keyerproto) == "winkey" } {

    Debug "Tx_Dekey_CW" "reseting WinKeyer to dekeyed state."
    if { [ info exists stuff(winkeyloop) ] } {
      unset stuff(winkeyloop)
    }
    Clear_WinKey
    return

  } else {

    # This is to recover from a possible mixer setting when sending CW using audio
    Mixer_Dekey

    if { ! [ info exists stuff(keyerportfid) ] } {
      return
    }

    # Don't muck with the serial port lines if we're already dekeyed.  It toggles
    # the lines due to the lousy Tcl serial port implementation.
    if { ! $stuff(cwkeyed) } {
      return
    }

    Debug "Tx_Dekey_CW" "configuring CW keyer serial port for dekeyed state."

    switch -exact -- $::tcl_platform(os) {
      "Darwin" {
        fconfigure $stuff(keyerportfid) -mode \
          $::setting(keyermode) -buffering line
      }
      "Linux" {
        fconfigure $stuff(keyerportfid) -handshake none -mode \
          $::setting(keyermode) -ttycontrol $::setting(cwdkeyttycontrol) -buffering line
      }
      default {
        fconfigure $stuff(keyerportfid) -handshake none -mode \
          $::setting(keyermode) -ttycontrol $::setting(cwdkeyttycontrol) -buffering line
      }
    }

    set stuff(cwkeyed) 0

  }

# Note: fid stays open.
}

#
# Close_CW - procedure to close the serial port used for CW
#            keying.  This happens only at exit.
#

proc Close_CW { } {
  global stuff

  if { [ info exists stuff(keyerportfid) ] } {
    Debug "Close_CW" "closing CW keyer serial port"
    close $stuff(keyerportfid)
    unset stuff(keyerportfid)
  }
}

proc Cycle_CW_Serial_Port { } {
  Tx_Dekey_CW
  Close_CW
  Open_CW
}

#
# Sound_Init_Voice - procedure to initialize all the voice sound segments.
#                    Call this on startup and each time a .rlk file is loaded.
#

proc Sound_Init_Voice { } {
  global snd stuff

  # abort if sound not enabled.
  if { $::setting(sndenable) == 0 } {
    return
  }

  # remove the old scratchpad message if any
  if [ info exists snd(v) ] {
    $snd(v) destroy
  }

  # make the voice keyer scratchpad
  set snd(v) [snack::sound]

  # make the voice keyer registers
  foreach i { 7 8 9 } {

    # remove the old messages if any
    if [ info exists snd($i) ] {
      $snd($i) destroy
    }

    # create the messages
    set snd($i) [snack::sound]

    # read in voice keyer messages if there
    set rn [ file tail [ file rootname $::setting(rlkfile) ] ]
    if { [ file readable "${rn}$i.wav" ] } {
      $snd($i) read "${rn}$i.wav"
    }
  }
}

#
# WinKey_Init - procedure to "open" the WinKey
#

proc WinKey_Init { } {
  global stuff

  if { $::setting(keyerproto) != "winkey" } {
    return
  }

  # clear the message remainder
  set stuff(remmsg) ""

  if { ! [ info exists stuff(keyerportfid) ] } {
    return
  }

  # register readback routine
  fileevent $stuff(keyerportfid) readable WinKey_Read
  
  # sleep for a time
  Sleep 500

  # "open" WinKey
  set m "\x00\x02\x0e\x40\x05\x0a\x14\xff"
  Dump_Buffer $m
  puts -nonewline $stuff(keyerportfid) "$m"
  flush $stuff(keyerportfid)
}

#
# Sound_Init_CW - procedure to initialize all the CW sound segments
#

proc Sound_Init_CW { } {
  global snd morse valid stuff

  if { $::setting(sndenable) == 0 } {
    return
  }

  # remove the old scratchpad message if any
  if [ info exists snd(c) ] {
    $snd(c) destroy
  }

  # make cw keyer scratchpad
  set snd(c) [snack::sound]

  # make morse code table
  set valid "etinamsdrgukwohblzfcpvxqyj56#78/+(94=3210:?\";'-*._),$ "

  # the elements in this list are a special mapping that provides a
  # 1 as the MSB for a dah and a 0 for a dit.  The value is shifted
  # to the right until only a 1 remains.
  set morse [ list 0x02 0x03 0x04 0x05 0x06 0x07 0x08 0x09 \
                   0x0a 0x0b 0x0c 0x0d 0x0e 0x0f 0x10 0x11 \
                   0x12 0x13 0x14 0x15 0x16 0x18 0x19 0x1b \
                   0x1d 0x1e 0x20 0x21 0x22 0x23 0x27 0x29 \
                   0x2a 0x2d 0x2f 0x30 0x31 0x38 0x3c 0x3e \
                   0x3f 0x47 0x4c 0x52 0x55 0x5e 0x61 0x68 \
                   0x6a 0x6c 0x6d 0x73 0xc8 0x00 0xff ]
}

#
# Sound_Make_CW - procedure to make snd(c), a CW version of the msg string
#
# No need to check sndenable---already done in Play_CW.
#

proc Sound_Make_CW { msg } {
  global stuff snd morse valid

  set ditdur [ expr int(8000 * 2.4 / $::setting(wpm)) ]
  set sp1dur [ expr 1 * $ditdur ]
  set sp2dur [ expr 2 * $ditdur ]
  set dahdur [ expr 3 * $ditdur ]

  # make a band pass filter to eliminate key clicks
  set ff [snack::filter formant $::setting(pitch) $::setting(pitch)]

  # make the component tones
  set dah [snack::filter generator $::setting(pitch).0 30000 0.0 sine $dahdur] 
  set dit [snack::filter generator $::setting(pitch).0 30000 0.0 sine $ditdur] 

  # make the component silences
  set sp1 [snack::filter generator 0.0 30000 0.0 sampled $sp1dur] 
  set sp2 [snack::filter generator 0.0 30000 0.0 sampled $sp2dur] 

  # make and fill in the component tones and silences
  set sdah [snack::sound]
  $sdah filter $dah 
  set sdit [snack::sound]
  $sdit filter $dit 
  set ssp1 [snack::sound]
  $ssp1 filter $sp1 
  set ssp2 [snack::sound]
  $ssp2 filter $sp2 

  # wipe out previous cw keyer scratchpad
  $snd(c) flush

  # loop through each character in the message
  for { set i 0 } { $i < [ string length $msg ] } { incr i } {

    # find the current character in the list of valid characters
    set index [ string first [ string range $msg $i $i ] $valid ]

    # if found, proceed
    if { $index != -1 } {

      # set the hexvalue variable to the mapping for this character
      set hexvalue [ lindex $morse $index ]

      if { $hexvalue == 0x00 } {

        # put 2 more dit spaces on for a space (will be 7 total)
        $snd(c) concatenate $ssp2

      } else {

        # continue shifting the mapped value until only a 1 remains
        for { set j $hexvalue } { $j != 1 } { set j [ expr $j >> 1 ] } {

          # if this bit is a one, send a dah
          if { $j & 0x01 } {
            $snd(c) concatenate $sdah

          # otherwise send a dit
          } else {
            $snd(c) concatenate $sdit
          }

          # put 1 dit space on between symbols
          $snd(c) concatenate $ssp1
        }

      }

      # put 2 more dit spaces on after each character
      $snd(c) concatenate $ssp2
    }
  }

  # bandpass filter the result
  $snd(c) filter $ff

  if { $stuff(debug) == 1 } {
    $snd(c) write "temp.wav"
  }
}

#
#  Build_Debug
#

proc Build_Debug { f } {
  global windows stuff

  toplevel $f
  wm withdraw $f
  wm title $f "Debug Log"
  wm protocol $f WM_DELETE_WINDOW { set stuff(debug) 0 ; \
    wm withdraw $windows(debug) }
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    wm iconbitmap $f keyer.ico
  }

  set windows(debugtext) [ text $f.st \
   -width 80 -height 24 -yscrollcommand "$f.ssb set" ]
  scrollbar $f.ssb -orient vert -command "$f.st yview"
  pack $f.ssb -side right -fill y
  pack $f.st -side left -fill both -expand true

  return $f
}

#
# Save - procedure to store all settings to fn.rlk.
#

proc Save { As } {
  global stuff

  if { $As == "As" || ( $As == "File" && $::setting(rlkfile) == "default.rlk" ) } {
    set types {
      {{RoverLog Keyer Files} {.rlk}}
      {{All Files} *}
    }

    set ::setting(rlkfile) [tk_getSaveFile -initialfile $::setting(rlkfile) -defaultextension ".rlk" -filetypes $types ]

    if { $::setting(rlkfile) == "" } {
      return
    } else {
      Set_Title
    }
  }

  set fid [ open $::setting(rlkfile) w 0666 ]

  set ::setting(mygrid) $stuff(sent)

  for { set handle [ array startsearch ::setting ]
    set index [ array nextelement ::setting $handle ] } \
    { $index != "" } \
    { set index [ array nextelement ::setting $handle ] } {

    if { [ llength $::setting($index) ] > 1 || [ string first "$" $::setting($index) ] >= 0 } {
      puts $fid "set ::setting($index) \{$::setting($index)\}"
    } else {
      puts $fid "set ::setting($index) \"$::setting($index)\""
    }

  }
  array donesearch ::setting $handle

  close $fid

  if { $As != "Quiet" } {
    tk_messageBox -icon info -type ok -title "Settings saved" \
      -message "RoverLog Keyer settings saved to $::setting(rlkfile)."
  }
}

#
# Set_Title - Stick junk in the title bar.
#

proc Set_Title { } { 
  global stuff
  set rn [ file tail [ file rootname $::setting(rlkfile) ] ]
  wm title . "Keyer - $rn"
}

#
# Open - Open a .rlk file.
#

proc Open { } {
  global windows stuff

  set types {
    {{RoverLog Keyer Files} {.rlk}}
    {{All Files} *}
  }
  set fn [tk_getOpenFile -initialfile $::setting(rlkfile) -defaultextension ".rlk" -filetypes $types]

  if { $fn == "" } {
    return
  } else {
    set ::setting(rlkfile) $fn
    Set_Title
  }

  if [file readable $fn] {
    source $fn
    Sound_Init_Voice
  } else {
    tk_messageBox -icon error -type ok \
      -title "Oops" -message "Cannot open the requested file."
  }
}

#
# Sound_Stop - procedure to stop a Snack sound from playing or recording.
#

proc Sound_Stop { } {
  global stuff snd

  Debug "Sound_Stop" "cancelling message playback"
  # dequeue existing loop
  if { [ info exists stuff(loopid) ] } {
    Debug "Sound_Stop" "cancelling looped play"
    after cancel $stuff(loopid)
    unset stuff(loopid)
  }

  if { $::setting(sndenable) == 0 } {
    return
  }

  # issue a stop
  $snd(c) stop
  $snd(v) stop
}

#
# Sound_Record - Record a voice keyer message.
#

proc Sound_Record { } {
  global stuff snd

  if { $::setting(sndenable) == 0 } {
    return
  }

  # stop
  Sound_Stop

  # record sound
  $snd(v) record
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
    wm iconbitmap $f keyer.ico
  }

  set windows(shortcutstext) [ text $f.t -font { courier 8 } -width 54 \
    -height 8 -yscrollcommand "$f.s set" ]
  scrollbar $f.s -orient vert -command "$f.t yview"

  grid $f.t $f.s -sticky ns -padx 1 -pady 2

  $windows(shortcutstext) configure -state normal
  $windows(shortcutstext) delete 1.0 end

  $windows(shortcutstext) insert insert "F<n>          Play Message <n>\n"
  $windows(shortcutstext) insert insert "Alt-Key-<n>   Play Keyer Message <n>\n"
  $windows(shortcutstext) insert insert "Return        Play Keyer Message 6\n"
  $windows(shortcutstext) insert insert "Page Down     Decrease CW Speed\n"
  $windows(shortcutstext) insert insert "Page Up       Increase CW Speed\n"
  $windows(shortcutstext) insert insert "Escape        Stop Keyer\n"
  $windows(shortcutstext) insert insert "Alt-Key-v     Save Settings\n"

  $windows(shortcutstext) configure -state disabled

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
# Build_Keyer - procedure to make widgets for the Keyer sending fields.
#

proc Build_Keyer { } {
  global windows stuff

  wm title . "Keyer Server"
  if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
    wm iconbitmap . keyer.ico
  }

  menu .mb
  . config -menu .mb
  set windows(mFile) [menu .mb.mFile -tearoff 0]
  .mb add cascade -label File -menu .mb.mFile
  $windows(mFile) add command -label Open -underline 0 -command Open
  $windows(mFile) add command -label Save -underline 0 -command { Save File }
  $windows(mFile) add command -label "Save As" -underline 5 -command { Save As }
  $windows(mFile) add command -label Exit -underline 1 -command My_Exit
  set windows(mHelp) [menu .mb.mHelp -tearoff 0]
  .mb add cascade -label Help -menu .mb.mHelp
  $windows(mHelp) add command -label Shortcuts -underline 0 -command Shortcuts
  $windows(mHelp) add command -label About -underline 0 -command About

  frame .f -borderwidth 2 -relief raised -pady 2 -padx 2
  label .f.l -text "Server Configuration" -font { systemfont 8 bold }
  label .f.lp -text "IP Port"
  entry .f.ep -textvariable ::setting(keyeripport) -width 12
  button .f.bs -text "Restart Server" -command { Server_Restart }

  grid .f.l  -     -sticky news -padx 1 -pady 1
  grid .f.lp .f.ep -sticky news -padx 1 -pady 1
  grid .f.bs -     -sticky news -padx 1 -pady 1

  grid .f.lp -sticky nes
  grid .f.ep -sticky nws

  frame .vc -borderwidth 2 -relief raised -pady 2 -padx 2

  label .vc.l -text "Voice Keyer Configuration" -font { systemfont 8 bold }

  menubutton .vc.mbserport -text "Serial Port" -menu .vc.mbserport.m -relief raised
  set w [ menu .vc.mbserport.m -tearoff 0 ]
  foreach b $stuff(serports) {
    $w add radio -label $b -variable ::setting(vkeyerport) -value $b -command { Cycle_Voice_Serial_Port }
  }
  entry .vc.evport -textvariable ::setting(vkeyerport) -state readonly -width 12

  label .vc.lvctrl -text "Key Control"
  entry .vc.evctrl -textvariable ::setting(vkeyttycontrol) -width 12
  label .vc.livctrl -text "Idle Control"
  entry .vc.eivctrl -textvariable ::setting(vdkeyttycontrol) -width 12

  grid .vc.l         -           -padx 1 -pady 1 -sticky news
  grid .vc.mbserport .vc.evport  -padx 1 -pady 1 -sticky nes
  grid .vc.lvctrl    .vc.evctrl  -padx 1 -pady 1 -sticky nes
  grid .vc.livctrl   .vc.eivctrl -padx 1 -pady 1 -sticky nes

  frame .v -borderwidth 2 -relief raised -pady 2 -padx 2

  label .v.l -text "Voice Keyer" -font { systemfont 8 bold }
  label .v.llp -text "Loop"

  button .v.brv -text "Record" -background pink -relief raised \
    -command { Sound_Record } -width 12
  button .v.bpv -text "Play" -background "light green" -relief raised \
    -command { Play_Voice_Number 0 } -width 12
  checkbutton .v.cbl0 -variable ::setting(loopenable0) \
    -relief flat
  button .v.bsv -text "Stop" -relief raised \
    -command { Tx_Dekey_CW ; Tx_Dekey_Voice ; Sound_Stop } -width 12
  foreach i { 7 8 9 } {
    button .v.bsv$i -text "Save $i" -background "light blue" \
      -relief raised -command "Save_Voice $i" -width 12
    button .v.bpv$i -text "Play $i" -background "light green" \
      -underline 5 -relief raised -command "Play_Voice_Number $i" -width 12
    checkbutton .v.cbl$i -variable ::setting(loopenable$i) \
      -relief flat
  }

  grid .v.l    -       .v.llp  -sticky news -padx 1 -pady 1
  grid .v.brv  .v.bpv  .v.cbl0 -sticky news -padx 1 -pady 1
  grid .v.bsv  -       x       -sticky news -padx 1 -pady 1
  grid .v.bsv7 .v.bpv7 .v.cbl7 -sticky news -padx 1 -pady 1 
  grid .v.bsv8 .v.bpv8 .v.cbl8 -sticky news -padx 1 -pady 1 
  grid .v.bsv9 .v.bpv9 .v.cbl9 -sticky news -padx 1 -pady 1 

  frame .p -borderwidth 2 -relief raised -pady 2 -padx 2

  label .p.lp -text "Direct PTT Control" -font { systemfont 8 bold }
  set label_background_color [ .p.lp cget -background ]
  label .p.llp -text "Loop" -foreground $label_background_color

  button .p.bt -text "Transmit" -background pink -relief raised \
    -command { Tx_Key_Voice nomixer } -width 12
  button .p.br -text "Receive" -background "light green" -relief raised \
    -command { Tx_Dekey_Voice } -width 12

  grid .p.lp -     .p.llp     -sticky news -padx 1 -pady 1 
  grid .p.bt .p.br x          -sticky news -padx 1 -pady 1 

  frame .x -borderwidth 2 -relief raised -pady 2 -padx 2

  label .x.lc -text "Global Configuration" -font { systemfont 8 bold }

  label .x.le -text "Sound"
  button .x.d0a -text "" -relief flat -state disabled
  checkbutton .x.cbs -text "Enabled" -variable ::setting(sndenable) \
    -relief flat

  label .x.lk -text "Also Key Voice Port for CW"
  button .x.dk -text "" -relief flat -state disabled
  checkbutton .x.cbk -text "Enabled" -variable ::setting(vkeyenable) \
    -relief flat

  label .x.ll -text "Looping"
  button .x.d4 -text "" -relief flat -state disabled
  checkbutton .x.cbl -text "Enabled" -variable ::setting(loopenable) \
    -relief flat

  label .x.lld -text "Loop Delay (sec)"
  entry .x.eld -textvariable ::setting(loopdelay) -width 12
  button .x.d6 -text "" -relief flat -state disabled

  label .x.lmk -text "Key Command"
  entry .x.emk -textvariable ::setting(mixerkeycmd) -width 12
  button .x.d7 -text "" -relief flat -state disabled

  label .x.lmd -text "Dekey Command"
  entry .x.emd -textvariable ::setting(mixerdekeycmd) -width 12
  button .x.d8 -text "" -relief flat -state disabled

  grid .x.lc     -         -      -padx 1 -pady 1 -sticky news
  grid .x.le     .x.cbs    .x.d0a -padx 1 -pady 1 -sticky nes
  grid .x.lk     .x.cbk    .x.dk  -padx 1 -pady 1 -sticky nes
  grid .x.ll     .x.cbl    .x.d4  -padx 1 -pady 1 -sticky nes
  grid .x.lld    .x.eld    .x.d6  -padx 1 -pady 1 -sticky nes
  grid .x.lmk    .x.emk    .x.d7  -padx 1 -pady 1 -sticky nes
  grid .x.lmd    .x.emd    .x.d8  -padx 1 -pady 1 -sticky nes

  grid .x.cbs -sticky w
  grid .x.cbk -sticky w
  grid .x.cbl -sticky w

  frame .y -borderwidth 2 -relief raised -pady 2 -padx 2

  label .y.lc -text "CW Keyer Configuration" -font { systemfont 8 bold }

  menubutton .y.mbserport -text "Serial Port" -menu .y.mbserport.m -relief raised
  set w [ menu .y.mbserport.m -tearoff 0 ]
  foreach b $stuff(serports) {
    $w add radio -label $b -variable ::setting(keyerport) -value $b -command { Cycle_CW_Serial_Port }
  }
  entry .y.ekport -textvariable ::setting(keyerport) -state readonly -width 12
  button .y.d1 -text "" -relief flat -state disabled
  label .y.lkctrl -text "Key Control"
  entry .y.ekctrl -textvariable ::setting(cwkeyttycontrol) -width 12
  label .y.likctrl -text "Idle Control"
  entry .y.eikctrl -textvariable ::setting(cwdkeyttycontrol) -width 12
  button .y.d3 -text "" -relief flat -state disabled
  label .y.lkmode -text "Mode"
  entry .y.ekmode -textvariable ::setting(keyermode) -width 12
  button .y.d2 -text "" -relief flat -state disabled
  label .y.lp -text "Protocol"
  radiobutton .y.rbpw -text "K1EL WinKey" -variable ::setting(keyerproto) \
    -value "winkey" -anchor w -command \
    { Mixer_Dekey ; Sound_Stop ; Cycle_CW_Serial_Port ; WinKey_Init }
  button .y.d7 -text "" -relief flat -state disabled
  radiobutton .y.rbpt -text "Transparent" -variable ::setting(keyerproto) \
    -value "transparent" -anchor w -command \
    { Cycle_CW_Serial_Port }
  button .y.d8 -text "" -relief flat -state disabled
  label .y.lkrig -text "Rig Number"
  entry .y.ekrig -textvariable stuff(rignum) -width 12 -state readonly
  button .y.d9 -text "" -relief flat -state disabled

  grid .y.lc        -         -      -padx 1 -pady 1 -sticky news
  grid .y.mbserport .y.ekport  .y.d1  -padx 1 -pady 1 -sticky nes
  grid .y.lkctrl    .y.ekctrl  .y.d3  -padx 1 -pady 1 -sticky nes
  grid .y.likctrl   .y.eikctrl .y.d3  -padx 1 -pady 1 -sticky nes
  grid .y.lkmode    .y.ekmode  .y.d2  -padx 1 -pady 1 -sticky nes
  grid .y.lp        .y.rbpw    .y.d7  -padx 1 -pady 1 -sticky nes
  grid x            .y.rbpt    .y.d8  -padx 1 -pady 1 -sticky nes
  grid .y.lkrig     .y.ekrig   .y.d9  -padx 1 -pady 1 -sticky nes

  grid .y.ekport -sticky w
  grid .y.ekctrl -sticky w
  grid .y.eikctrl -sticky w
  grid .y.ekmode -sticky w
  grid .y.ekrig -sticky w
  grid .y.rbpw -sticky w
  grid .y.rbpt -sticky w

  frame .c -borderwidth 2 -relief raised -pady 2 -padx 2

  label .c.l -text "CW Keyer" -font { systemfont 8 bold }
  label .c.llp -text "Loop"
  foreach i { 1 2 3 4 5 } {
    button .c.bpc$i -text "Play $i" -background "light green" \
      -underline 5 -relief raised -command "Play_CW $i"
    entry .c.emc$i -textvariable ::setting(m$i) -width 24
    checkbutton .c.cbl$i -variable ::setting(loopenable$i) \
      -relief flat
  }
  button .c.bpc6 -text "Play 6" -background "light green" \
    -underline 5 -relief raised -command { Play_CW 6 }
  set windows(m6entry) [ entry .c.emc6 -textvariable ::setting(m6) -width 24 ]
  checkbutton .c.cbl6 -variable ::setting(loopenable6) \
    -relief flat
  button .c.bstop -text "Stop" -command { Tx_Dekey_CW ; Tx_Dekey_Voice ; Sound_Stop }

  grid .c.l     -       .c.llp  -sticky news -padx 1 -pady 1
  grid .c.bpc1  .c.emc1 .c.cbl1 -sticky news -padx 1 -pady 1
  grid .c.bpc2  .c.emc2 .c.cbl2 -sticky news -padx 1 -pady 1
  grid .c.bpc3  .c.emc3 .c.cbl3 -sticky news -padx 1 -pady 1
  grid .c.bpc4  .c.emc4 .c.cbl4 -sticky news -padx 1 -pady 1
  grid .c.bpc5  .c.emc5 .c.cbl5 -sticky news -padx 1 -pady 1
  grid .c.bpc6  .c.emc6 .c.cbl6 -sticky news -padx 1 -pady 1
  grid .c.bstop x       x       -sticky news -padx 1 -pady 1

  frame .i -borderwidth 2 -relief raised -pady 2 -padx 2

  label .i.linfo -text "CW Keyer Information" -font { systemfont 8 bold }

  label .i.lmycall -text {My Call ($m)}
  entry .i.emycall -textvariable ::setting(mycall) -width 12
  button .i.bd1 -text "" -state disabled -relief flat
  label .i.lsent -text {Sent ($s)}
  entry .i.esent -textvariable stuff(sent) -width 12
  button .i.bd2 -text "" -state disabled -relief flat
  label .i.lcall -text {Call ($c)}
  entry .i.ecall -textvariable stuff(call) -width 12
  button .i.bd3 -text "" -state disabled -relief flat
  label .i.lrecd -text {Received ($r)}
  entry .i.erecd -textvariable stuff(recd) -width 12
  button .i.bd4 -text "" -state disabled -relief flat
  label .i.lwpm -text {WPM ($w)}
  entry .i.ewpm -textvariable ::setting(wpm) -width 12
  button .i.bd5 -text "" -state disabled -relief flat
  label .i.lop -text {Operator ($o)}
  entry .i.eop -textvariable ::setting(op) -width 12
  button .i.bd6 -text "" -state disabled -relief flat
  label .i.lpitch -text {CW Pitch ($p)}
  entry .i.epitch -textvariable ::setting(pitch) -width 12
  button .i.bd7 -text "" -state disabled -relief flat

  grid .i.linfo   -            -        -sticky news -padx 1 -pady 1
  grid .i.lmycall .i.emycall .i.bd1 -sticky nes -padx 1 -pady 1
  grid .i.lsent   .i.esent   .i.bd2 -sticky nes -padx 1 -pady 1
  grid .i.lcall   .i.ecall   .i.bd3 -sticky nes -padx 1 -pady 1
  grid .i.lrecd   .i.erecd   .i.bd4 -sticky nes -padx 1 -pady 1
  grid .i.lwpm    .i.ewpm    .i.bd5 -sticky nes -padx 1 -pady 1
  grid .i.lop     .i.eop     .i.bd6 -sticky nes -padx 1 -pady 1
  grid .i.lpitch  .i.epitch  .i.bd7 -sticky nes -padx 1 -pady 1

  grid .p  .c  .i -sticky news
  grid .v  ^   ^  -sticky news
  grid .vc .x  .y -sticky news
  grid .f  ^   ^  -sticky news
}

#
#  Popup_Debug - procedure to bring the Debug window up.
#

proc Popup_Debug { } {
  global windows stuff

  set stuff(debug) 1
  wm deiconify $windows(debug)
  raise $windows(debug)
  focus $windows(debug)
}

#
# Brag
#

proc About { } {
  global stuff

  tk_messageBox -icon info -type ok -title About \
    -message "RoverLog Keyer
by Tom Mayo

http://roverlog.2ub.org/"
}

#
#  Init - procedure to create and clear all non-option globals.
#

proc Init { } {
  global stuff

  # set these to keyed to force setting to correct state
  # upon startup.
  set stuff(voicekeyed) 1
  set stuff(cwkeyed) 1

  # set defaults
  set stuff(rignum) 1
  set stuff(call) ""
  if { [ info exists ::setting(mygrid) ] } {
    set stuff(sent) [ string range $::setting(mygrid) 0 3 ]
  } else {
    set stuff(sent) ""
  }
  set stuff(recd) ""
}

#
# Save_Loc - procedure to save location info for the next open
#

proc Save_Loc { } {
  global .

  set fid [ open "keyer_loc.ini" w 0666 ]

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

#
# Net_Exit - procedure to quit cleanly with save.
#

proc Net_Exit { } {

  # stop serving network requests
  Server_Close

  # if transparent CW keying, this will close the serial port but not for
  # WinKey.
  # Tx_Dekey_CW

  # make sure the serial port is good and closed in case we are using WinKey.
  Close_CW

  # close the voice keyer serial port
  # Tx_Dekey_Voice
  Close_Voice

  # save window location
  Save_Loc

  # save settings
  Save Quiet

  # bye bye
  exit
}

#
# My_Exit
#
  
proc My_Exit { } {

  set ok [ tk_messageBox -icon warning -type okcancel \
    -title "Confirm Keyer Module Exit" -message \
    "Do you really want to exit the Keyer Module?\nSelect Ok to exit or Cancel to abort exit." ]
  if { $ok != "ok" } {
    return
  }

  Net_Exit

}

#
# Save_Voice - procedure to save a recorded a voice message
#

proc Save_Voice { i } {
  global stuff snd

  if { $::setting(sndenable) == 0 } {
    return
  }

  # Dekey the transmitter (just in case)
  Tx_Dekey_CW
  Tx_Dekey_Voice
  Sound_Stop

  # replace the old sound
  $snd($i) flush
  $snd($i) concatenate $snd(v)

  # wipe out the old file (if any)
  set rn [ file tail [ file rootname $::setting(rlkfile) ] ]
  file delete -force "${rn}$i.wav"

  # write the new sound to disk
  $snd($i) write "${rn}$i.wav"
}

#
# Play_CW - procedure to send a CW message.
#

proc Play_CW { i } {
  global windows stuff snd

  Debug "Play_CW" "starting..."

  Sound_Stop

  # set up replacement macros
  set m $::setting(mycall)
  set s $stuff(sent)
  set c $stuff(call)
  set r $stuff(recd)
  set w $::setting(wpm)
  set o $::setting(op)
  set p $::setting(pitch)

  # get the text message ready
  set msg [ string tolower [ subst $::setting(m$i) ] ]

  if { $::setting(keyerproto) == "winkey" } {

    # if the serial port is not open, there's no point in going on
    if { ! [ info exists stuff(keyerportfid) ] } {
      return
    }

    if { $::setting(vkeyenable) == 1 } {
      Debug "Play_CW" "Also Keying Via Voice Port"
      Tx_Key_Voice nomixer
    }

    Debug "Play_CW" "Playing CW on WinKey"

    # clear old message
    set m "\x0a"
    Dump_Buffer $m
    puts -nonewline $stuff(keyerportfid) $m
    flush $stuff(keyerportfid)

    # set rig number
    if { $stuff(rignum) == 1 } {
      set m "\x09\x07"
    } else {
      set m "\x09\x0b"
    }
    Dump_Buffer $m
    puts -nonewline $stuff(keyerportfid) $m
    flush $stuff(keyerportfid)

    # clamp CW speed
    set wpm $::setting(wpm)
    if { $wpm < 5 } {
      set wpm 5
    }
    if { $wpm > 99 } {
      set wpm 99
    }

    # send cw speed to WinKey
    set m [ format "%02.2x" $wpm ]
    set m [ binary format H2 $m ]
    set m "\x02$m"
    Dump_Buffer $m
    puts -nonewline $stuff(keyerportfid) "$m"
    flush $stuff(keyerportfid)

    # send message to WinKey
    set msg [ string toupper $msg ]
    set stuff(remmsg) [ string range $msg 30 end ]
    set msg [ string range $msg 0 29 ]
    set msg "$msg"
    Debug "Play_CW" "sending $msg"
    puts -nonewline $stuff(keyerportfid) "$msg"
    flush $stuff(keyerportfid)

    # prepare to loop if enabled
    if { $::setting(loopenable) == 1 && $::setting(loopenable$i) == 1 } {
      set stuff(winkeyloop) $i
    } else {
      if { [ info exists stuff(winkeyloop) ] } {
        unset stuff(winkeyloop)
      }
    }

  # transparent CW keying
  } else {

    # Key the transmitter. for transparent this happens every time we send
    Tx_Key_CW

    # Spit the message out the serial port as well
    if { [ info exists stuff(keyerportfid) ] } {
      Debug "Play_CW" "sending to serial port"
      puts $stuff(keyerportfid) "$msg\n"
    }

    # If sound is enabled, do the sound part
    if { $::setting(sndenable) == 1 } {

      # stop
      Sound_Stop

      # create the new sound
      Sound_Make_CW $msg

      # play the message and dekey when done
      Debug "Play_CW" "playing CW message on sound card"
      $snd(c) play -command { Tx_Dekey_CW }

      # loop if enabled
      if { $::setting(loopenable) == 1 && $::setting(loopenable$i) == 1 } {
        set dummy [ $snd(c) length -unit SECONDS ]
        Debug "Play_CW" "scheduling next message for looped play"
        if { ! [ string is integer -strict $::setting(loopdelay) ] || \
          ! ( $::setting(loopdelay) > 0 ) || \
          ! ( $::setting(loopdelay) < 60 ) } {
          tk_messageBox -icon error -type ok \
            -title "Oops" -message "The loop delay must be between 1 and 60 seconds."
        } else {
          set stuff(loopid) [ after [ expr int(1000 * ( $::setting(loopdelay) + $dummy )) ] "Play_CW $i" ]
        }
      }
    } else {
      # if sound is disabled, close the serial port
      Tx_Dekey_CW
    }
  }
}

#
# Play_Voice_Number - procedure to send a voice message.
#

proc Play_Voice_Number { i } {
  global stuff snd

  if { $::setting(sndenable) == 0 } {
    return
  }

  # stop any currently playing sound
  Sound_Stop

  if { $i != 0 } {
    # Create the new sound
    $snd(v) flush
    $snd(v) concatenate $snd($i)
  }

  # Key the transmitter
  Tx_Key_Voice mixer

  # Play the sound
  $snd(v) play -command { Tx_Dekey_Voice }

  # Loop if enabled
  if { $::setting(loopenable) == 1 && $::setting(loopenable$i) == 1 } {
    set dummy [ $snd(v) length -unit SECONDS ]
    Debug "Play_Voice_Number" "scheduling next message for looped play"
    if { ! [ string is integer -strict $::setting(loopdelay) ] || \
      ! ( $::setting(loopdelay) > 0 ) || \
      ! ( $::setting(loopdelay) < 60 ) } {
      tk_messageBox -icon error -type ok \
        -title "Oops" -message "The loop delay must be between 1 and 60 seconds."
    } else {
      set stuff(loopid) [ after [ expr int(1000 * ( $::setting(loopdelay) + $dummy )) ] "Play_Voice_Number $i" ]
    }
  }

}
  
proc Keyer_CW_Speed { i } {

  incr ::setting(wpm) $i

  if { $::setting(wpm) < 5 } {
    set ::setting(wpm) 5
  }

  if { $::setting(wpm) > 100 } {
    set ::setting(wpm) 100
  }
}

# Begin

switch -exact -- $tcl_platform(os) {
  "Linux" {
    set stuff(serports) [ list "/dev/ttyS0" "/dev/ttyS1" "/dev/ttyS2" "/dev/ttyS3" "/dev/ttyS4" "/dev/ttyS5" "/dev/ttyS6" ]
  }
  "Darwin" {
    set stuff(serports) [ list "/dev/cu.USA19QW11P1.1" "/dev/cu.USA19QW11P2.1" "/dev/cu.USA19QW11P3.1" "/dev/cu.USA19QW11P4.1" "/dev/cu.USA19QW11P5.1" "/dev/cu.USA19QW11P6.1" "/dev/cu.USA19QW11P7.1" ]
  }
  default {
    package require registry

    set serial_base "HKEY_LOCAL_MACHINE\\HARDWARE\\DEVICEMAP\\SERIALCOMM"
    set values [ registry values $serial_base ]

    set result { None }

    foreach valueName $values {
      set t [ registry get $serial_base $valueName ]
      set t "${t}:"
      lappend result $t
    }

    set result [ lsort -dictionary $result ]

    set stuff(serports) $result
  }
}

# Make the main window
Build_Keyer
set windows(shortcuts) [ Build_Shortcuts .shortcuts ]
set windows(keyer) .
set windows(.) .

# Make the debug window early to allow debugging
set windows(debug) [Build_Debug .debug]
Popup_Debug

# set default values
set stuff(debug) 1

# station defaults
set ::setting(keyeripport) 32126
set ::setting(mycall)      "N0NE/R"
set ::setting(mygrid)      "FN12FX"
set ::setting(op)          "Nobody"

# set default keyer port
set ::setting(keyerport) "None"
set ::setting(vkeyerport) "None"

set ::setting(vkeyttycontrol) "RTS 1 DTR 0"
set ::setting(vdkeyttycontrol) "RTS 0 DTR 0"
set ::setting(vkeyerportdelay) 0
set ::setting(keyermode)  9600,n,8,1
set ::setting(keyerproto)  "transparent"
# set ::setting(mixerkeycmd) "exec quickmix key"
# set ::setting(mixerdekeycmd) "exec quickmix dekey"
set ::setting(mixerkeycmd) ""
set ::setting(mixerdekeycmd) ""
set ::setting(cwkeyttycontrol) "RTS 1 DTR 0"
set ::setting(cwdkeyttycontrol) "RTS 0 DTR 0"
set ::setting(sndenable)  1
set ::setting(vkeyenable) 0
set ::setting(loopenable) 1
set ::setting(loopenable0) 1
set ::setting(loopenable1) 1
set ::setting(loopenable2) 1
set ::setting(loopenable3) 1
set ::setting(loopenable4) 1
set ::setting(loopenable5) 1
set ::setting(loopenable6) 0
set ::setting(loopenable7) 1
set ::setting(loopenable8) 1
set ::setting(loopenable9) 1
set ::setting(loopdelay)  5
set ::setting(wpm)        20
set ::setting(pitch)      700
set ::setting(m1) {cq cq de $m $m k}
set ::setting(m2) {$c $c de $m $m = $c $c de $m $m}
set ::setting(m3) {$c $c de $m $m $s $s $s $s}
set ::setting(m4) {$c $c de $m $m qsl qsl qsl $s $s $s}
set ::setting(m5) {$c $c de $m $m tnx tnx es 73 73 $c de $m}

# override values if the .rlk file is there

set ::setting(rlkfile) "default.rlk"
if [file readable "default.rlk"] {
  source "default.rlk"
}  

Init

# Bindings
bind all <Alt-Key-u> Popup_Debug
bind all <Alt-Key-U> Popup_Debug
bind all <Alt-Key-w> { set ::setting(m6) "" }
bind all <Alt-Key-W> { set ::setting(m6) "" }
bind all <F12> { focus $windows(m6entry) ; $windows(m6entry) icursor end ; \
  $windows(m6entry) select range 0 end }

# CW keyer bindings
for { set i 1 } { $i < 7 } { incr i } {
  bind all <Alt-Key-$i> "Play_CW $i"
  bind all <F$i> "Play_CW $i"
}

# voice keyer bindings
for { set i 7 } { $i < 10 } { incr i } {
  bind all <Alt-Key-$i> "Play_Voice_Number $i"
  bind all <F$i> "Play_Voice_Number $i"
}

# both keyer bindings
bind all <Escape> { Tx_Dekey_CW ; Tx_Dekey_Voice ; Sound_Stop }
bind all <Alt-Key-V> { Save File }
bind all <Alt-Key-v> { Save File }

# keyer window only
bind $windows(keyer) <Return> { Play_CW 6 }
bind $windows(keyer) <Prior> "Keyer_CW_Speed 1"
bind $windows(keyer) <Next> "Keyer_CW_Speed -1"

# ----- end bindings

if { $::tcl_platform(os) != "Linux" && $::tcl_platform(os) != "Darwin" } {
  wm iconbitmap . keyer.ico
}
wm protocol . WM_DELETE_WINDOW My_Exit
wm resizable . 0 0

raise .
focus .

Sound_Init
Open_CW
WinKey_Init
Open_Voice

Server_Restart
Set_Title

if { [ file readable "keyer_loc.ini" ] } {
  source "keyer_loc.ini"
}
