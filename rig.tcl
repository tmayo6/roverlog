#/bin/sh
# the next line restarts using tclsh \
exec wish "$0" "$@"

#
# Sleep - Wait for a time.
#

proc Sleep { ms } {
  global sleepwait

  after $ms set sleepwait 0
  vwait sleepwait
}

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
      -title "Rig Module Network Error" -message \
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
    if {[string compare $line "freq?"] == 0} {
      Debug "Serve_Request" "Received freq get request."
      Debug "Serve_Request" "Replying with $stuff(rigfreq)."
      puts $sock $stuff(rigfreq)
    } elseif {[string compare $line "mode?"] == 0} {
      Debug "Serve_Request" "Received mode get request."
      Debug "Serve_Request" "Replying with $stuff(rigmode)."
      puts $sock $stuff(rigmode)
    } elseif {[string compare [ string range $line 0 4 ] "freq!"] == 0} {
      Debug "Serve_Request" "Received freq set request"
      if { [ scan $line "%*s %f" f ] == 1 } {
        Debug "Serve_Request" "Requested freq $f"
        set stuff(rigfreq) [ format "%6.4f" $f ]
        Send_Freq $stuff(rigfreq)
      }
    } elseif {[string compare [ string range $line 0 4 ] "mode!"] == 0} {
      Debug "Serve_Request" "Received mode set request"
      if { [ scan $line "%*s %s" m ] == 1 } {
        Debug "Serve_Request" "Requested mode $m"
        set stuff(rigmode) [ format "%2.2s" $m ]
        Send_Mode $stuff(rigmode)
      }
    } elseif {[string compare [ string range $line 0 5 ] "playv!"] == 0} {
      Debug "Serve_Request" "Received DVR Play request"
      if { [ scan $line "%*s %d" msg ] == 1 } {
        set msg [ expr $msg - 6 ]
        Debug "Serve_Request" "Play DVR Message $msg"
        Send_DVR_Play $msg
      }
    } elseif {[string compare $line "quit!"] == 0} {
      Net_Exit
    } elseif {[string compare $line ""] != 0} {
      Debug "Serve_Request" "Received unknown command \"$line\"."
    }
  }
}

# 
# Serial_Read - Accept data from serial port
#

proc Serial_Read { } {
  global stuff
  
  if { [ catch { read $stuff(fid) } r ] } {
    Debug "Serial_Read" "Caught an exception on reading"
    return
  }

  switch -exact -- $::setting(rigtype) {
    "Icom" -
    "TenTec Omni VI" {
      Debug "Serial_Read" "Got response"
      Dump_Buffer $r
      set stuff(response) "$stuff(response)$r"
      Debug "Serial_Read" "New agglomeration"
      Dump_Buffer $stuff(response)

      # TODO - test this

      # look for the end of message delimiter
      set i [ string first "\xfd" $stuff(response) ]

      # if found, parse the response
      while { $i >= 0 } {

        # set the string to parse to the string from the first character up to
        # and including the delimiter.
        set response [ string range $stuff(response) 0 $i ]

        # do the work
        Parse_Response $response

        # set the remainder to the rest of the string.
        # Tcl fact: setting the new string to a range after the end of the
        # string sets the string to "".
        set stuff(response) [ string range $stuff(response) [ expr $i + 1 ] end ]
        Debug "Serial_Read" "new remainder"
        Dump_Buffer $stuff(response)

        # search again to catch any more complete responses
        set i [ string first "\xfd" $stuff(response) ]
      }

      return
    }
    "Yaesu FT-817" {
      set stuff(response) "$stuff(response)$r"
      if { [ string length $stuff(response) ] == 5 } {
        Parse_Response $stuff(response)
        set stuff(response) ""
      }
      return
    }
    "Yaesu FT-100" {
      set stuff(response) "$stuff(response)$r"
      if { [ string length $stuff(response) ] == 15 } {
        Parse_Response $stuff(response)
        set stuff(response) ""
      }
      return
    }
    "Yaesu FT-847" {
      set stuff(response) "$stuff(response)$r"
      if { [ string length $stuff(response) ] == 5 } {
        Parse_Response $stuff(response)
        set stuff(response) ""
      }
      return
    }
    "Yaesu FT-897" {
      set stuff(response) "$stuff(response)$r"
      if { [ string length $stuff(response) ] == 5 } {
        Parse_Response $stuff(response)
        set stuff(response) ""
      } elseif { [ string length $stuff(response) ] == 1 } {
        Debug "Serial Read" "Dumping FT-897 ACK byte"
        set stuff(response) ""  
      }
      return
    }
    "Yaesu FT-1000" {
      set stuff(response) "$stuff(response)$r"
      if { [ string length $stuff(response) ] == 16 } {
        Parse_Response $stuff(response)
        set stuff(response) ""
      }
      return
    }
    "Yaesu FT-2000" {
      set stuff(response) "$stuff(response)$r"
      if { [ string index $r end ] == ";" } {
        Parse_Response $stuff(response)
        set stuff(response) ""
      }
      return
    }
    "Kenwood" -
    "Elecraft K3" -
    "Elecraft K2" {
      set stuff(response) "$stuff(response)$r"
      if { [ string index $r end ] == ";" } {
        Parse_Response $stuff(response)
        set stuff(response) ""
      }
      return
    }
    "Simulated" {
      return
    }
    default {
      tk_messageBox -icon error -type ok \
        -title "Rig Type Error" -message "Unknown Rig Type."      
      return
    }
  }
}

proc Parse_Response { response } {
  global stuff

  switch -exact -- $::setting(rigtype) {
    "Icom" -
    "TenTec Omni VI" {
      Debug "Parse_Response" "Parsing Icom message"
      Dump_Buffer $response

      set n [ string length $response ]
      if { $n == 8 } {

        binary scan $response "x4c1c1c1c1" command f0 f1 f2 f3

        # format command
        set command [ format "%02.2x" $command ]

        if { $command == "01" || $command == "06" || $command == "04" } {

          Debug "Parse_Response" "Icom mode byte = $f0"

          switch -exact -- "$f0" {
            "3" {
              set stuff(rigmode) "CW"
            }
            "4" {
              set stuff(rigmode) "RY"
            }
            "5" {
              set stuff(rigmode) "FM"
            }
            default {
              set stuff(rigmode) "PH"
            }
          }
        }

      } else {

        if { $n == 11 } {
          binary scan $response "x4c1c1c1c1c1c1" command f0 f1 f2 f3 f4
        } elseif { $n == 17 } {
          binary scan $response "x6x4c1c1c1c1c1c1" command f0 f1 f2 f3 f4
        } else {
          return
        }

        # format command
        set command [ format "%02.2x" $command ]

        # set frequency if this was a query command
        if { $command == "03" || $command == "00" } {

          # convert signed to unsigned
          set f0 [ expr ( $f0 + 0x100 ) % 0x100 ]
          set f1 [ expr ( $f1 + 0x100 ) % 0x100 ]
          set f2 [ expr ( $f2 + 0x100 ) % 0x100 ]
          set f3 [ expr ( $f3 + 0x100 ) % 0x100 ]
          set f4 [ expr ( $f4 + 0x100 ) % 0x100 ]

          # convert to a text representation
          set f0 [ format "%02.2x" $f0 ]
          set f1 [ format "%02.2x" $f1 ]
          set f2 [ format "%02.2x" $f2 ]
          set f3 [ format "%02.2x" $f3 ]
          set f4 [ format "%02.2x" $f4 ]

          # set the frequency
          set rf "$f4${f3}.$f2$f1$f0"
          Debug "Parse_Response" "Rig frequency $rf"
          scan $rf "%f" rf
          set stuff(rigfreq) [ format "%6.4f" $rf ]
        }
      }

      return
    }
    "Kenwood" -
    "Elecraft K3" -
    "Elecraft K2" {
      Debug "Parse_Response" "Parsing Kenwood/Elecraft K2/Elecraft K3 message $response"
      if { [ binary scan $response "x2a11x16a1" rf mo ] == 2 } { 
        if { [ scan $rf "%d" rf ] == 1 } {
          set rf [ expr $rf / 1000000.0 ]
          Debug "Parse_Response" "Rig frequency $rf"
          set stuff(rigfreq) [ format "%6.4f" $rf ]
        }
        if { [ scan $mo "%d" mo ] == 1 } {
          Debug "Parse_Response" "Rig mode $mo"
          switch -exact -- $mo {
            3 -
            7 {
              set stuff(rigmode) "CW"
            }
            4 {
              set stuff(rigmode) "FM"
            }
            6 -
            9 {
              set stuff(rigmode) "RY"
            }
            default {
              set stuff(rigmode) "PH"
            }
          }
        }
      }
      return
    }
    "Yaesu FT-817" {
      Debug "Parse_Response" "Parsing Yaesu FT-817 message"
      Dump_Buffer $response

      if { [ binary scan $response "c1c1c1c1c1" f0 f1 f2 f3 mode ] == 5 } {
        # convert signed to unsigned
        set f0 [ expr ( $f0 + 0x100 ) % 0x100 ]
        set f1a [ expr ( $f1 + 0x100 ) % 0x100 / 16 ]
        set f1b [ expr ( $f1 + 0x100 ) % 0x100 - 16 * $f1a]
        set f2 [ expr ( $f2 + 0x100 ) % 0x100 ]
        set f3 [ expr ( $f3 + 0x100 ) % 0x100 ]

        # convert to a text representation
        set f0 [ format "%02.2x" $f0 ]
        set f1a [ format "%01.1x" $f1a ]
        set f1b [ format "%01.1x" $f1b ]
        set f2 [ format "%02.2x" $f2 ]
        set f3 [ format "%02.2x" $f3 ]

        set rf "$f0${f1a}.$f1b$f2$f3"
        Debug "Parse_Response" "Rig frequency $rf"
        scan $rf "%f" rf
        set stuff(rigfreq) [ format "%6.4f" $rf ]

        switch -exact -- $mode {
          "\x02" -
          "\x03" {
            set stuff(rigmode) "CW"
          }
          "\x06" -
          "\x08" {
            set stuff(rigmode) "PH"
          }
          "\x0a" -
          "\x0c" {
            set stuff(rigmode) "RY"
          }
          default {
            set stuff(rigmode) "PH"
          }
        }
      }
      return
    }
    "Yaesu FT-100" {
      Debug "Parse_Response" "Parsing Yaesu FT-100 message"
      Dump_Buffer $response

      if { [ binary scan $response "c1c1c1c1c1c1" \
        bandno f0 f1 f2 f3 mode ] == 6 } {
        # convert signed to unsigned
        set f0 [ expr ( $f0 + 0x100 ) % 0x100 ]
        set f1 [ expr ( $f1 + 0x100 ) % 0x100 ]
        set f2 [ expr ( $f2 + 0x100 ) % 0x100 ]
        set f3 [ expr ( $f3 + 0x100 ) % 0x100 ]

        set rf [ expr 1.25 * ( ($f0 << 24) + ($f1 << 16) + ($f2 << 8) + $f3 ) ]
        Debug "Parse_Response" "Rig frequency $rf"
        set stuff(rigfreq) [ format "%6.4f" $rf ]

        set mode [ expr $mode & 0x0f ]
        switch -exact -- $mode {
          "\x02" -
          "\x03" {
            set stuff(rigmode) "CW"
          }
          "\x05" {
            set stuff(rigmode) "RY"
          }
          default {
            set stuff(rigmode) "PH"
          }
        }
      }
      return
    }
    "Yaesu FT-847" {
      Debug "Parse_Response" "Parsing Yaesu FT-847 message"
      Dump_Buffer $response

      if { [ binary scan $response "c1c1c1c1c1" f0 f1 f2 f3 mode ] == 5 } {
        # convert signed to unsigned
        set f0 [ expr ( $f0 + 0x100 ) % 0x100 ]
        set f1a [ expr ( $f1 + 0x100 ) % 0x100 / 16 ]
        set f1b [ expr ( $f1 + 0x100 ) % 0x100 - 16 * $f1a]
        set f2 [ expr ( $f2 + 0x100 ) % 0x100 ]
        set f3 [ expr ( $f3 + 0x100 ) % 0x100 ]

        # convert to a text representation
        set f0 [ format "%02.2x" $f0 ]
        set f1a [ format "%01.1x" $f1a ]
        set f1b [ format "%01.1x" $f1b ]
        set f2 [ format "%02.2x" $f2 ]
        set f3 [ format "%02.2x" $f3 ]

        set rf "$f0${f1a}.$f1b$f2$f3"
        Debug "Parse_Response" "Rig frequency $rf"
        scan $rf "%f" rf
        set stuff(rigfreq) [ format "%6.4f" $rf ]

        switch -exact -- $mode {
          "\x02" -
          "\x03" {
            set stuff(rigmode) "CW"
          }
          "\x06" -
          "\x08" {
            set stuff(rigmode) "PH"
          }
          "\x0a" -
          "\x0c" {
            set stuff(rigmode) "RY"
          }
          default {
            set stuff(rigmode) "PH"
          }
        }
      }
      return
    }
    "Yaesu FT-897" {
      Debug "Parse_Response" "Parsing Yaesu FT-897 message"
      Dump_Buffer $response

      if { [ binary scan $response "c1c1c1c1c1" f0 f1 f2 f3 mode ] == 5 } {
        # convert signed to unsigned
        set f0 [ expr ( $f0 + 0x100 ) % 0x100 ]
        set f1a [ expr ( $f1 + 0x100 ) % 0x100 / 16 ]
        set f1b [ expr ( $f1 + 0x100 ) % 0x100 - 16 * $f1a]
        set f2 [ expr ( $f2 + 0x100 ) % 0x100 ]
        set f3 [ expr ( $f3 + 0x100 ) % 0x100 ]

        # convert to a text representation
        set f0 [ format "%02.2x" $f0 ]
        set f1a [ format "%01.1x" $f1a ]
        set f1b [ format "%01.1x" $f1b ]
        set f2 [ format "%02.2x" $f2 ]
        set f3 [ format "%02.2x" $f3 ]

        set rf "$f0${f1a}.$f1b$f2$f3"
        Debug "Parse_Response" "Rig frequency $rf"
        scan $rf "%f" rf
        set stuff(rigfreq) [ format "%6.4f" $rf ]

        switch -exact -- $mode {
          2 -
          3 {
            set stuff(rigmode) "CW"
          }
          0 -
          1 {
            set stuff(rigmode) "PH"
          }
          6 -
          8 {
            set stuff(rigmode) "FM"
          }
          10 -
          12 {
            set stuff(rigmode) "RY"
          }
          default {
            set stuff(rigmode) "PH"
          }
        }
        Debug "Parse_Response" "Rig mode $stuff(rigmode)"
      }
      return
    }
    "Yaesu FT-1000" {

      # debug
      Debug "Parse_Response" "Parsing Yaesu FT-1000 message"
      Dump_Buffer $response

      # Parse
      if { [ binary scan $response "x1I1x2c1x8" f m ] == 2 } {
        set rf [ expr $f * 0.625 / 1000000.0 ]
        Debug "Parse_Response" "Rig frequency $rf"
        set stuff(rigfreq) [ format "%6.4f" $rf ]

        set m [ expr $m & 0x07 ]
        switch -exact -- $m {
          2 {
            set stuff(rigmode) "CW"
          }
          4 {
            set stuff(rigmode) "FM"
          }
          5 -
          6 {
            set stuff(rigmode) "RY"
          }
          default {
            set stuff(rigmode) "PH"
          }
        }
      }
      return
    }
    "Yaesu FT-2000" {
      Debug "Parse_Response" "Parsing Yaesu FT-2000 $response"
      if { [ binary scan $response "x5a8x7a1" rf mo ] == 2 } { 
        if { [ scan $rf "%d" rf ] == 1 } {
          set rf [ expr $rf / 1000000.0 ]
          Debug "Parse_Response" "Rig frequency $rf"
          set stuff(rigfreq) [ format "%6.4f" $rf ]
        }
        if { [ scan $mo "%d" mo ] == 1 } {
          Debug "Parse_Response" "Rig mode $mo"
          switch -exact -- $mo {
            3 -
            7 {
              set stuff(rigmode) "CW"
            }
            4 -
            B {
              set stuff(rigmode) "FM"
            }
            6 -
            8 -
            9 -
            A -
            C {
              set stuff(rigmode) "RY"
            }
            default {
              set stuff(rigmode) "PH"
            }
          }
        }
      }
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

  if [ catch { set stuff(fid) [ open $serport r+ ] } ] {
    tk_messageBox -icon warning -type ok \
      -title "Rig Module Serial Port Error" -message \
      "Cannot open $::setting(serport).\nModule already running?"
    return
  }

  Debug "Serial_Open" "Serial port $::setting(serport) open as $stuff(fid)."

  if [ catch { fconfigure $stuff(fid) -blocking 0 -buffering none -encoding binary \
    -translation { binary binary } -mode $::setting(sermode) -handshake none \
    -ttycontrol $::setting(serttycontrol) } ] {
    Debug "Serial_Open" "Serial port $::setting(serport) configuration failed."
  } else {
    Debug "Serial_Open" "Serial port $::setting(serport) configuration complete."
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

  set fid [ open "rig_loc.ini" w 0666 ]

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

  set fid [ open "rig.ini" w 0666 ]

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
    -title "Confirm Rig Module Exit" -message \
    "Do you really want to exit the Rig Module?\nSelect Ok to exit or Cancel to abort exit." ]
  if { $ok != "ok" } {
    return
  }

  Net_Exit
}

proc Set_USB_CW_Split_On { } {
  global stuff

  switch -exact -- $::setting(rigtype) {
    "Icom" {

      # Set A=B
      set b [ binary format H4H2H8 fefe $::setting(rigid) e007a0fd ]
  
      # debug
      Debug "Set_USB_CW_Split_On" "Sending Icom VFO A=B command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      Sleep 50

      # ------

      # Set to VFOA, so we have a known starting place.

      set b [ binary format H4H2H8 fefe $::setting(rigid) e00700fd ]
  
      # debug
      Debug "Set_USB_CW_Split_On" "Sending Icom Set to VFOA command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      Sleep 50

      # ------

      # Set Split On
      set b [ binary format H4H2H8 fefe $::setting(rigid) e00f01fd ]
  
      # debug
      Debug "Set_USB_CW_Split_On" "Sending Icom Split On command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      Sleep 50

      # ------

      # Set to VFOB
      set b [ binary format H4H2H8 fefe $::setting(rigid) e00701fd ]
  
      # debug
      Debug "Set_USB_CW_Split_On" "Sending Icom Set to VFOB command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      Sleep 50

      # ------

      # Set to CW
      set b [ binary format H4H2H8 fefe $::setting(rigid) e00603fd ]
  
      # debug
      Debug "Set_USB_CW_Split_On" "Sending Icom Set CW command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      Sleep 50

      # ------

      # Set operating frequency
      set bfreq [ expr $stuff(rigfreq) + 0.0006 ]
      Send_Freq $bfreq

      Sleep 50

      # ------

      # Set to VFOA
      set b [ binary format H4H2H8 fefe $::setting(rigid) e00700fd ]
  
      # debug
      Debug "Set_USB_CW_Split_On" "Sending Icom Set to VFOA command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

    }
  }

  return
}

proc Set_Split_Off { } {
  global stuff

  switch -exact -- $::setting(rigtype) {
    "Icom" {

      # Set Split Off
      set b [ binary format H4H2H8 fefe $::setting(rigid) e00f00fd ]
  
      # debug
      Debug "Set_Split_Off" "Sending Icom Split Off command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b
    }
  }

  return
}

proc Send_DVR_Play { msg } {
  global stuff

  switch -exact -- $::setting(rigtype) {

    "Elecraft K3" {

      switch -exact -- $msg {
        "1" {
          set b "K31;SWT21;"
        }
        "2" {
          set b "K31;SWT31;"
        }
        "3" {
          set b "K31;SWT35;"
        }
        default {
          set b "K31;SWT39;"
        }
      }

      # send the buffer
      Serial_Write $b

      return
    }

    default {
      return
    }
  }
}

proc Send_Mode { rigmode } {
  global stuff

  switch -exact -- $::setting(rigtype) {
    "Simulated" {
      return
    }
    "TenTec Omni VI" -
    "Icom" {

      switch -exact -- $rigmode {
        "CW" {
          set mc "03"
        }
        "RY" {
          set mc "04"
        }
        "FM" {
          set mc "05"
        }
        default {
          set mc "01"
        }
      }

      # set up the command buffer
      set b [ binary format H4H2H4H2H2 fefe $::setting(rigid) e006 $mc fd ]
  
      # debug
      Debug "Send_Mode" "Sending Icom/TenTec Omni VI command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      return
    }
    "Kenwood" -
    "Elecraft K2" -
    "Elecraft K3" {

      switch -exact -- $rigmode {
        "CW" {
          set m "3"
        }
        "RY" {
          set m "6"
        }
        "FM" {
          set m "4"
        }
        default {
          set m "2"
        }
      }

      # set up the command
      set b [ format "MD%s;" $m ]

      # debug
      Debug "Send_Mode" "Sending Kenwood/Elecraft K2/Elecraft K3 command $b"

      # send the command
      Serial_Write $b

      return
    }
    "Yaesu FT-817" {
      switch -exact -- $rigmode {
        "CW" {
          set mc "02"
        }
        "RY" {
          set mc "0a"
        }
        "FM" {
          set mc "08"
        }
        default {
          set mc "01"
        }
      }
      set b [ binary format H2H2 $mc 07 ]
  
      # debug
      Debug "Send_Mode" "Sending Yaesu FT-817 command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      return
    }
    "Yaesu FT-100" {

      switch -exact -- $rigmode {
        "CW" {
          set mc "02"
        }
        "RY" {
          set mc "05"
        }
        "FM" {
          set mc "06"
        }
        default {
          set mc "01"
        }
      }
      # set up mode command
      set b [ binary format H2H2H2H2H2 00 00 00 $mc 0c ]

      # set up CAT on command
      set n [ binary format H10 0000000000 ]

      # set up CAT off command
      set f [ binary format H10 0000000080 ]

      # Debug
      Debug "Send_Mode" "Sending Yaesu FT-100 command"

      Dump_Buffer $n
      Dump_Buffer $b
      # Dump_Buffer $f

      # Turn on CAT
      Serial_Write $n
      # Send Mode
      Serial_Write $b
      # Turn off CAT
      # Serial_Write $f

      return
    }
    "Yaesu FT-847" {

      switch -exact -- $rigmode {
        "CW" {
          set mc "02"
        }
        "RY" {
          set mc "0a"
        }
        "FM" {
          set mc "08"
        }
        default {
          set mc "01"
        }
      }
      # set up mode command
      set b [ binary format H2H2 $mc 07 ]

      # set up CAT on command
      set n [ binary format H10 0000000000 ]

      # set up CAT off command
      set f [ binary format H10 0000000080 ]

      # Debug
      Debug "Send_Mode" "Sending Yaesu FT-847 command"

      Dump_Buffer $n
      Dump_Buffer $b
      # Dump_Buffer $f

      # Turn on CAT
      Serial_Write $n
      # Send Mode
      Serial_Write $b
      # Turn off CAT
      # Serial_Write $f

      return
    }
    "Yaesu FT-897" {
      switch -exact -- $rigmode {
        "CW" {
          set mc "02"
        }
        "RY" {
          set mc "0a"
        }
        "FM" {
          set mc "08"
        }
        default {
          set mc "01"
        }
      }
      # Only the first byte is meaningful.  Bytes 2, 3, and 4 are
      # don't cares.
      set b [ binary format H2H2H2H2H2 $mc $mc $mc $mc 07 ]
  
      # debug
      Debug "Send_Mode" "Sending Yaesu FT-897 command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      return
    }
    "Yaesu FT-1000" {

      switch -exact -- $rigmode {
        "CW" {
          set mc "02"
        }
        "RY" {
          set mc "09"
        }
        "FM" {
          set mc "06"
        }
        default {
          set mc "01"
        }
      }
      # set up mode command
      set b [ binary format H2H2 $mc 0c ]

      # Debug
      Debug "Send_Mode" "Sending Yaesu FT-1000 command"

      Dump_Buffer $b

      # Send Mode
      Serial_Write $b

      return
    }
    "Yaesu FT-2000" {

      switch -exact -- $rigmode {
        "CW" {
          set m "03"
        }
        "RY" {
          set m "09"
        }
        "FM" {
          set m "0B"
        }
        default {
          set m "02"
        }
      }

      # set up the command
      set b [ format "MD%s;" $m ]

      # debug
      Debug "Send_Mode" "Sending Yaesu FT-2000 mode command $b"

      # send the command
      Serial_Write $b

      return
    }
  }

}

proc Send_Freq { rigfreq } {
  global stuff

  switch -exact -- $::setting(rigtype) {
    "TenTec Omni VI" -
    "Icom" {

      # 123.456789 -> 89 67 45 23 01
      # get the 1 GHz and 100 MHz digits
      set f [ expr $rigfreq * 1000000.0 ]
      set f0 [ expr int($f/100000000.0) ]
      set f0c [ format "%02.2d" $f0 ]

      # get the 10 and 1 MHz digits
      set f [ expr $f - $f0 * 100000000.0 ]
      set f1 [ expr int($f/1000000.0) ]
      set f1c [ format "%02.2d" $f1 ]

      # get the 100 and 10 kHz digits
      set f [ expr $f - $f1 * 1000000.0 ]
      set f2 [ expr int($f/10000.0) ]
      set f2c [ format "%02.2d" $f2 ]

      # get the 1 kHz and 100 Hz digits
      set f [ expr $f - $f2 * 10000.0 ]
      set f3 [ expr int($f/100.0) ]
      set f3c [ format "%02.2d" $f3 ]

      # get the 10 and 1 Hz digits
      set f4 [ expr int($f - $f3 * 100.0) ]
      set f4c [ format "%02.2d" $f4 ]

      # set up the command buffer
      set b [ binary format H4H2H4H2H2H2H2H2H2 fefe $::setting(rigid) e005 \
        $f4c $f3c $f2c $f1c $f0c fd ]
  
      # debug
      Debug "Send_Freq" "Sending Icom/TenTec Omni VI command"
      Dump_Buffer $b

      # send the buffer
      Serial_Write $b

      return
    }
    "Kenwood" -
    "Elecraft K3" -
    "Elecraft K2" {

      # get frequency in Hz
      set irf [ expr int($rigfreq) ]
      set drf [ expr $rigfreq - $irf ]
      set rrf [ expr round(1000000 * $drf) ]
      set rf [ expr $irf$rrf ]

      set nz [ expr 11 - [ string length $rf ] ]
      set z [ string repeat "0" $nz ]
      set b "FA$z$rf;"

      # set up the command
      # 12 345 678 901
      #  2 304 100 000
      # debug
      Debug "Send_Freq" "Sending Kenwood/Elecraft K2/Elecraft K3 command $b"

      # send the command
      Serial_Write $b

      return
    }
    "Yaesu FT-817" {

      # set up commands
      set b [ binary format H10 0000000000 ]

      # get the 100 and 10 MHz digits
      set f [ expr $rigfreq * 1000000.0 ]
      set f0 [ expr int($f/10000000.0) ]
      set f0c [ format "%02.2d" $f0 ]

      # get the 1 MHz and 100 kHz digits
      set f [ expr $f - $f0 * 10000000.0 ]
      set f1 [ expr int($f/100000.0) ]
      set f1c [ format "%02.2d" $f1 ]

      # get the 10 and 1 kHz digits
      set f [ expr $f - $f1 * 100000.0 ]
      set f2 [ expr int($f/1000.0) ]
      set f2c [ format "%02.2d" $f2 ]

      # get the 100 and 10 Hz digits
      set f [ expr $f - $f2 * 1000.0 ]
      set f3 [ expr int($f/10.0) ]
      set f3c [ format "%02.2d" $f3 ]

      set l [ binary format H2H2H2H2H2 $f0c $f1c $f2c $f3c 01 ]
      set t [ binary format H10 0000000080 ]

      # Debug
      Debug "Send_Freq" "Sending Yaesu FT-817 command"
      # Dump_Buffer $b
      Dump_Buffer $l
      # Dump_Buffer $t

      # Turn on CAT
      # Serial_Write $b
      # Send Freq
      Serial_Write $l
      # Turn off CAT
      # Serial_Write $t

      return
    }
    "Yaesu FT-100" {

      # set up commands
      set b [ binary format H10 0000000000 ]

      # get the 100 and 10 MHz digits
      set f [ expr $rigfreq * 1000000.0 ]
      set f0 [ expr int($f/10000000.0) ]
      set f0c [ format "%02.2d" $f0 ]

      # get the 1 MHz and 100 kHz digits
      set f [ expr $f - $f0 * 10000000.0 ]
      set f1 [ expr int($f/100000.0) ]
      set f1c [ format "%02.2d" $f1 ]

      # get the 10 and 1 kHz digits
      set f [ expr $f - $f1 * 100000.0 ]
      set f2 [ expr int($f/1000.0) ]
      set f2c [ format "%02.2d" $f2 ]

      # get the 100 and 10 Hz digits
      set f [ expr $f - $f2 * 1000.0 ]
      set f3 [ expr int($f/10.0) ]
      set f3c [ format "%02.2d" $f3 ]

      set l [ binary format H2H2H2H2H2 $f3c $f2c $f1c $f0c 0a ]
      set t [ binary format H10 0000000080 ]

      # Debug
      Debug "Send_Freq" "Sending Yaesu FT-100 command"
      Dump_Buffer $b
      Dump_Buffer $l
      # Dump_Buffer $t

      # Turn on CAT
      Serial_Write $b
      # Send Freq
      Serial_Write $l
      # Turn off CAT
      # Serial_Write $t

      return
    }
    "Yaesu FT-847" {

      # set up commands
      set b [ binary format H10 0000000000 ]

      # get the 100 and 10 MHz digits
      set f [ expr $rigfreq * 1000000.0 ]
      set f0 [ expr int($f/10000000.0) ]
      set f0c [ format "%02.2d" $f0 ]

      # get the 1 MHz and 100 kHz digits
      set f [ expr $f - $f0 * 10000000.0 ]
      set f1 [ expr int($f/100000.0) ]
      set f1c [ format "%02.2d" $f1 ]

      # get the 10 and 1 kHz digits
      set f [ expr $f - $f1 * 100000.0 ]
      set f2 [ expr int($f/1000.0) ]
      set f2c [ format "%02.2d" $f2 ]

      # get the 100 and 10 Hz digits
      set f [ expr $f - $f2 * 1000.0 ]
      set f3 [ expr int($f/10.0) ]
      set f3c [ format "%02.2d" $f3 ]

      set l [ binary format H2H2H2H2H2 $f0c $f1c $f2c $f3c 01 ]
      set t [ binary format H10 0000000080 ]

      # Debug
      Debug "Send_Freq" "Sending Yaesu FT-847 command"
      Dump_Buffer $b
      Dump_Buffer $l
      # Dump_Buffer $t

      # Turn on CAT
      Serial_Write $b
      # Send Freq
      Serial_Write $l
      # Turn off CAT
      # Serial_Write $t

      return
    }
    "Yaesu FT-897" {

      # set up commands
      set b [ binary format H10 0000000000 ]

      # get the 100 and 10 MHz digits
      set f [ expr $rigfreq * 1000000.0 ]
      set f0 [ expr int($f/10000000.0) ]
      set f0c [ format "%02.2d" $f0 ]

      # get the 1 MHz and 100 kHz digits
      set f [ expr $f - $f0 * 10000000.0 ]
      set f1 [ expr int($f/100000.0) ]
      set f1c [ format "%02.2d" $f1 ]

      # get the 10 and 1 kHz digits
      set f [ expr $f - $f1 * 100000.0 ]
      set f2 [ expr int($f/1000.0) ]
      set f2c [ format "%02.2d" $f2 ]

      # get the 100 and 10 Hz digits
      set f [ expr $f - $f2 * 1000.0 ]
      set f3 [ expr int($f/10.0) ]
      set f3c [ format "%02.2d" $f3 ]

      set l [ binary format H2H2H2H2H2 $f0c $f1c $f2c $f3c 01 ]
      set t [ binary format H10 0000000080 ]

      # Debug
      Debug "Send_Freq" "Sending Yaesu FT-897 command"
      # Dump_Buffer $b
      Dump_Buffer $l
      # Dump_Buffer $t

      # Turn on CAT
      # Serial_Write $b
      # Send Freq
      Serial_Write $l
      # Turn off CAT
      # Serial_Write $t

      return
    }
    "Yaesu FT-1000" {

      # get the 100 and 10 MHz digits
      set f [ expr $rigfreq * 1000000.0 ]
      set f0 [ expr int($f/10000000.0) ]
      set f0c [ format "%02.2d" $f0 ]

      # get the 1 MHz and 100 kHz digits
      set f [ expr $f - $f0 * 10000000.0 ]
      set f1 [ expr int($f/100000.0) ]
      set f1c [ format "%02.2d" $f1 ]

      # get the 10 and 1 kHz digits
      set f [ expr $f - $f1 * 100000.0 ]
      set f2 [ expr int($f/1000.0) ]
      set f2c [ format "%02.2d" $f2 ]

      # get the 100 and 10 Hz digits
      set f [ expr $f - $f2 * 1000.0 ]
      set f3 [ expr int($f/10.0) ]
      set f3c [ format "%02.2d" $f3 ]

      set l [ binary format H2H2H2H2H2 $f0c $f1c $f2c $f3c 0A ]

      # Debug
      Debug "Send_Freq" "Sending Yaesu FT-1000 command"
      Dump_Buffer $l

      # Send Freq
      Serial_Write $l

      return
    }
    "Yaesu FT-2000" {

      # get frequency in Hz
      set rf [ expr int(1000000 * $rigfreq) ]

      # set up the command
      set b [ format "FA%08.8d;" $rf ]

      # debug
      Debug "Send_Mode" "Sending Yaesu FT-2000 command $b"

      # send the command
      Serial_Write $b

      return
    }
    "simulated" {
      return
    }
    default {
    }
  }
}

proc Query_Freq { } {
  global stuff

  switch -exact -- $::setting(rigtype) {
    "Icom" -
    "TenTec Omni VI" {

      # set up the command
      set b [ binary format H4H2H6 fefe $::setting(rigid) e003fd ]
      set stuff(querystate) "freq"

      # debug
      Debug "Query_Freq" "Sending Icom/TenTec Omni VI freq query"
      Dump_Buffer $b

      # send query
      Serial_Write $b

      Sleep 10

      # set up the command
      set b [ binary format H4H2H6 fefe $::setting(rigid) e004fd ]
      set stuff(querystate) "mode"

      # debug
      Debug "Query_Freq" "Sending Icom/TenTec Omni VI mode query"
      Dump_Buffer $b

      # send query
      Serial_Write $b
    }
    "Kenwood" -
    "Elecraft K3" -
    "Elecraft K2" {

      # command needs no setup, jump right in
      set stuff(querystate) "freq"

      # debug
      Debug "Query_Freq" "Sending Kenwood/Elecraft K2/Elecraft K3 query IF;"

      # send query
      Serial_Write "IF;"
    }
    "Yaesu FT-817" {
      
      # set up the commands
      set b [ binary format H10 0000000000 ]
      set l [ binary format H10 0000000003 ]
      set t [ binary format H10 0000000080 ]
      set stuff(querystate) "freq"

      # debug
      Debug "Query_Freq" "Sending Yaesu FT-817 query"
      # Dump_Buffer $b
      Dump_Buffer $l

      # Turn on CAT
      # Serial_Write $b
      # Query Freq
      Serial_Write $l
      # Turn off CAT
      # This does not seem to be necessary
      # Serial_Write $t
    }
    "Yaesu FT-100" {
      
      # set up the commands
      set b [ binary format H10 0000000000 ]
      set l [ binary format H10 0000000010 ]
      set stuff(querystate) "freq"

      # debug
      Debug "Query_Freq" "Sending Yaesu FT-100 query"
      Dump_Buffer $b
      Dump_Buffer $l

      # Turn on CAT
      Serial_Write $b
      # Query Freq
      Serial_Write $l
    }
    "Yaesu FT-847" {
      
      # set up the commands
      set b [ binary format H10 0000000000 ]
      set l [ binary format H10 0000000003 ]
      set t [ binary format H10 0000000080 ]
      set stuff(querystate) "freq"

      # debug
      Debug "Query_Freq" "Sending Yaesu FT-847 query"
      Dump_Buffer $b
      Dump_Buffer $l

      # Turn on CAT
      Serial_Write $b
      # Query Freq
      Serial_Write $l
      # Turn off CAT
      # This does not seem to be necessary
      # Serial_Write $t
    }
    "Yaesu FT-897" {
      
      # set up the commands
      set b [ binary format H10 0000000000 ]
      set l [ binary format H10 0000000003 ]
      set t [ binary format H10 0000000080 ]
      set stuff(querystate) "freq"

      # debug
      Debug "Query_Freq" "Sending Yaesu FT-897 query"
      # Dump_Buffer $b
      Dump_Buffer $l

      # Turn on CAT
      # Serial_Write $b
      # Query Freq
      Serial_Write $l
      # Turn off CAT
      # This does not seem to be necessary
      # Serial_Write $t
    }
    "Yaesu FT-1000" {

      # set up the freq query command
      set l [ binary format H10 0000000210 ]
      set stuff(querystate) "freq"

      # debug
      Debug "Query_Freq" "Sending Yaesu FT-1000 frequency query"
      Dump_Buffer $l

      # Query Freq
      Serial_Write $l
    }
    "Yaesu FT-2000" {

      # command needs no setup, jump right in
      set stuff(querystate) "freq"

      # debug
      Debug "Query_Freq" "Sending Yaesu FT-2000 query IF;"

      # send query
      Serial_Write "IF;"
    }
    "Simulated" {
      return
    }
    default {
    }
  }
}

proc Poll { } {
  global stuff

  if [ info exists stuff(afterjob) ] {
    after cancel $stuff(afterjob)
    unset stuff(afterjob)
  }

  switch -exact -- $::setting(rigtype) {
    "Icom" -
    "TenTec Omni VI" {
      Query_Freq
    }
    "Yaesu FT-817" {
      Query_Freq
    }
    "Yaesu FT-100" {
      Query_Freq
    }
    "Yaesu FT-847" {
      Query_Freq
    }
    "Yaesu FT-897" {
      Query_Freq
    }
    "Yaesu FT-1000" {
      Query_Freq
    }
    "Yaesu FT-2000" {
      Query_Freq
    }
    "Kenwood" -
    "Elecraft K2" -
    "Elecraft K3" {
      Query_Freq
    }
    "Simulated" {
      return
    }
    default {
    }
  }
  if { $::setting(pollint) > 0 } {
    set stuff(afterjob) [ after [ expr $::setting(pollint) * 1000 ] Poll ]
  }
}

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

proc Init { } {
  global stuff tcl_platform

  set stuff(debug) 0

  set ::setting(serport) ""

  set ::setting(sermode) "9600,n,8,1"
  set ::setting(serttycontrol) "RTS 1 DTR 1"

  set ::setting(pollint) 0
  set ::setting(rigtype) "Icom"
  set ::setting(rigid) "56"

  set ::setting(ipport) 32124

  set stuff(rigfreq) "0.0000"
  set stuff(rigmode) "PH"
  set stuff(response) ""
}

set stuff(rigtypes) { "Simulated" "Icom" "TenTec Omni VI" "Kenwood" "Elecraft K2" "Elecraft K3" "Yaesu FT-817" "Yaesu FT-100" "Yaesu FT-847" "Yaesu FT-897" "Yaesu FT-1000" "Yaesu FT-2000" }

menubutton .mbserport -text "Rig Serial Port" -menu .mbserport.m -relief raised
set w [ menu .mbserport.m -tearoff 0 ]
foreach b $stuff(serports) {
  $w add radio -label $b -variable ::setting(serport) -value $b
}
entry .eserport -textvariable ::setting(serport)

label .lsermode -text "Serial Port Mode"
entry .esermode -textvariable ::setting(sermode)

label .lserctrl -text "Serial Port Line Control"
entry .eserctrl -textvariable ::setting(serttycontrol)

label .lipport -text "Server IP Port"
entry .eipport -textvariable ::setting(ipport)

button .br -text "Start/Restart Server" -command Restart_Server

label .lpollint -text "Polling Interval (sec)"
entry .epollint -textvariable ::setting(pollint)

menubutton .mbrigman -text "Rig Type" -menu .mbrigman.m -relief \
  raised
entry .erigman -textvariable ::setting(rigtype)
set w [menu .mbrigman.m -tearoff 0]
foreach b $stuff(rigtypes) {
  $w add radio -label $b -variable ::setting(rigtype) -value $b
}

label .lrigid -text "Rig ID (hex)"
entry .erigid -textvariable ::setting(rigid)

label .lrf -text "Rig Freq (MHz)"
entry .erf -textvariable stuff(rigfreq)

label .lrm -text "Rig Mode"
entry .erm -textvariable stuff(rigmode)

button .bs -text "Send Freq to Rig" -command {Send_Freq $stuff(rigfreq)} -background pink
button .bg -text "Get Freq from Rig" -command Query_Freq -background lightgreen
button .bucso -text "Set Split USB/CW Mode" -command Set_USB_CW_Split_On -background lightyellow
button .bso   -text "Set Non-Split Mode" -command Set_Split_Off -background lightblue
button .bx -text "Exit" -command My_Exit

grid .mbserport .eserport -padx 2 -pady 2 -sticky ew
grid .lsermode  .esermode -padx 2 -pady 2 -sticky ew
grid .lserctrl  .eserctrl -padx 2 -pady 2 -sticky ew
grid .lipport   .eipport  -padx 2 -pady 2 -sticky ew
grid .br        -         -padx 2 -pady 2 -sticky ew
grid .lpollint  .epollint -padx 2 -pady 2 -sticky ew
grid .mbrigman  .erigman  -padx 2 -pady 2 -sticky ew
grid .lrigid    .erigid   -padx 2 -pady 2 -sticky ew
grid .lrf       .erf      -padx 2 -pady 2 -sticky ew
grid .lrm       .erm      -padx 2 -pady 2 -sticky ew
grid .bs        -         -padx 2 -pady 2 -sticky ew
grid .bg        -         -padx 2 -pady 2 -sticky ew
grid .bucso     -         -padx 2 -pady 2 -sticky ew
grid .bso       -         -padx 2 -pady 2 -sticky ew
grid .bx        -         -padx 2 -pady 2 -sticky ew

set windows(debug) [ Build_Debug .debug ]
wm title . "Rig Module"
if { $tcl_platform(os) != "Linux" && $tcl_platform(os) != "Darwin" } {
  wm iconbitmap . rig.ico
}
wm protocol . WM_DELETE_WINDOW My_Exit
wm resizable . 0 0

Init

if { [ file readable "rig.ini" ] } {
  source "rig.ini"
}

bind all <Alt-Key-u> Popup_Debug

if { [ file readable "rig_loc.ini" ] } {
  source "rig_loc.ini"
}

Restart_Server
