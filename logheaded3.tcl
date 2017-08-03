#!/bin/sh
# the next line restarts using wish \
exec wish "$0" "$@"

proc Setup_Options_Table { } {
  global title table

  set table(0,0) [ list "location"  "LOCATION:" "menu" [ list \
AB \
AK \
AL \
AR \
AZ \
BC \
CO \
CT \
DE \
EB \
EMA \
ENY \
EPA \
EWA \
GA \
IA \
ID \
IL \
IN \
KS \
KY \
LA \
LAX \
MAR \
MB \
MDC \
ME \
MI \
MN \
MO \
MS \
MT \
NC \
ND \
NE \
NFL \
NH \
NL \
NLI \
NM \
NNJ \
NNY \
NT \
NTX \
NV \
OH \
OK \
ON \
OR \
ORG \
PAC \
PR \
QC \
RI \
SB \
SC \
SCV \
SD \
SDG \
SF \
SFL \
SJV \
SK \
SNJ \
STX \
SV \
TN \
UT \
VA \
VI \
VT \
WCF \
WI \
WMA \
WNY \
WPA \
WTX \
WV \
WWA \
WY \
 ] ]
  set table(0,1) [ list "contest"               "CONTEST:" "menu" [ list ARRL-VHF-JAN ARRL-VHF-JUN ARRL-UHF-AUG ARRL-VHF-SEP CQ-VHF ] ]
  set table(0,2) [ list "mycall"                "CALLSIGN:" "entry" "\"" "\"" ]
  set table(0,3) [ list "category-assisted"     "CATEGORY-ASSISTED:" "menu" [ list "ASSISTED" "NON-ASSISTED" ] ]
  set table(0,4) [ list "category-band"         "CATEGORY-BAND:" "menu" [ list ALL 160M 80M 40M 20M 15M 10M 6M 2M 222 432 902 1.2G 2.3G 3.4G 5.7G 10G  ] ]
  set table(0,5) [ list "category-mode"         "CATEGORY-MODE:" "menu" [ list SSB CW MIXED  ] ]
  set table(0,6) [ list "category-operator"     "CATEGORY-OPERATOR:" "menu" [ list SINGLE-OP MULTI-OP CHECKLOG ] ]
  set table(0,7) [ list "category-power"        "CATEGORY-POWER:" "menu" [ list HIGH LOW QRP ] ]
  set table(0,8) [ list "category-station"      "CATEGORY-STATION:" "menu" [ list FIXED PORTABLE ROVER ROVER-LIMITED ROVER-UNLIMITED ] ]
  set table(0,9) [ list "category-time"         "CATEGORY-TIME:" "menu" [ list 6-HOURS 12-HOURS 24-HOURS ] ]
  set table(0,10) [ list "category-transmitter" "CATEGORY-TRANSMITTER:" "menu" [ list ONE LIMITED UNLIMITED ] ]
  set table(0,11) [ list "category-overlay"     "CATEGORY-OVERLAY:" "menu" [ list ROOKIE TB-WIRES NOVICE-TECH OVER-50 ] ]
  set table(0,12) [ list "claimed-score"        "CLAIMED-SCORE:" "entry" "\"" "\"" ]
  set table(0,13) [ list "operators"            "OPERATORS:" "entry" "\"" "\"" ]
  set table(0,14) [ list "club"                 "CLUB:" "entry" "\"" "\"" ]
  set table(0,15) [ list "name"                 "NAME:" "entry" "\"" "\"" ]
  set table(0,16) [ list "email"                "EMAIL:" "entry" "\"" "\"" ]
  set table(0,17) [ list "address1"             "ADDRESS:" "entry" "\"" "\"" ]
  set table(0,18) [ list "address2"             "ADDRESS:" "entry" "\"" "\"" ]
  set table(0,19) [ list "address3"             "ADDRESS:" "entry" "\"" "\"" ]
  set table(0,20) [ list "soapbox1"             "SOAPBOX:" "entry" "\"" "\"" ]
  set table(0,21) [ list "soapbox2"             "SOAPBOX:" "entry" "\"" "\"" ]
  set table(0,22) [ list "soapbox3"             "SOAPBOX:" "entry" "\"" "\"" ]
}

Setup_Options_Table

proc My_Exit { } {
  exit
}

proc Build_Frame { i } {
  global table

  destroy .f.f
  frame .f.f

  for { set j 0 } { [ info exists table($i,$j) ] } { incr j } {
    set t [ lindex $table($i,$j) 2 ]
    if { $t == "entry" } {
      label .f.f.l$j -text [ lindex $table($i,$j) 1 ]
      entry .f.f.e$j -textvariable ::setting([ lindex $table($i,$j) 0 ]) -width 32
      grid .f.f.l$j .f.f.e$j
      grid .f.f.l$j -sticky e -padx 3 -pady 3
      grid .f.f.e$j -sticky w -padx 3 -pady 3
    } elseif { $t == "menu" } {
      menubutton .f.f.mb$j -text [ lindex $table($i,$j) 1 ] -menu .f.f.mb$j.menu -relief raised
      menu .f.f.mb$j.menu -tearoff 0
      foreach b [ lindex $table($i,$j) 3 ] {
        .f.f.mb$j.menu add radiobutton -label $b -variable ::setting([ lindex $table($i,$j) 0 ])
      }
      entry .f.f.e$j -textvariable ::setting([ lindex $table($i,$j) 0 ]) -width 32
      grid .f.f.mb$j .f.f.e$j
      grid .f.f.mb$j -sticky e -padx 3 -pady 3
      grid .f.f.e$j -sticky w -padx 3 -pady 3
    } elseif { $t == "rangemenu" } {
      menubutton .f.f.mb$j -text [ lindex $table($i,$j) 1 ] -menu .f.f.mb$j.menu -relief raised
      menu .f.f.mb$j.menu -tearoff 0
      for { set b [ lindex $table($i,$j) 3 ] } { $b != [ lindex $table($i,$j) 4 ] } { incr b [ lindex $table($i,$j) 5 ] } {
        .f.f.mb$j.menu add radiobutton -label $b -variable ::setting([ lindex $table($i,$j) 0 ])
      }
      entry .f.f.e$j -textvariable ::setting([ lindex $table($i,$j) 0 ]) -width 32
      grid .f.f.mb$j .f.f.e$j
      grid .f.f.mb$j -sticky e -padx 3 -pady 3
      grid .f.f.e$j -sticky w -padx 3 -pady 3
    }
  }
  pack .f.f
  pack .f
}

proc Save { as } {
  global fn table

  if { $as == "as" } {
    set types {
      {{Log Files} {.log}}
      {{All Files} *}
    }

    set fn [tk_getSaveFile -initialfile $fn -defaultextension ".log" -filetypes $types ]
  }

  if { $fn != "" } {

    if { [ file readable $fn ] } {
      set r [ tk_messageBox -icon warning -type yesno \
          -title "Are you sure?" -message \
        "The log file $fn already exists.  Are you SURE you wish to overwrite it?" ]
      if { $r == "no" } {
        return
      }
    }

    set fid [ open $fn w 0666 ]

    puts $fid "START-OF-LOG: 3.0"
    puts $fid "CREATED-BY: ROVERLOG"

    for { set i 0 } { [ info exists table($i,0) ] } { incr i } {
      for { set j 0 } { [ info exists table($i,$j) ] } { incr j } {
        set b [ lindex $table($i,$j) 0 ]
        set v [ lindex $table($i,$j) 1 ]
        set t [ lindex $table($i,$j) 2 ]
        puts $fid "$v $::setting($b)"
      }
    }

    puts $fid "END-OF-LOG:"

    close $fid
  }
}

menu .mb -relief raised
. config -menu .mb
menu .mb.mf -tearoff 0
.mb add cascade -label File -underline 0 -menu .mb.mf

.mb.mf add command -underline 5 -label "Save As" -command {Save as}
.mb.mf add command -underline 1 -label Exit -command My_Exit

frame .f
Build_Frame 0

# defaults
set ::setting(mycall) "N0NE"
set ::setting(category-assisted) "NON-ASSISTED"
set ::setting(category-band) "2M"
set ::setting(category-mode) "MIXED"
set ::setting(category-operator) "MULTI-OP"
set ::setting(category-power) "HIGH"
set ::setting(category-station) "FIXED"
set ::setting(category-time) "24-HOURS"
set ::setting(category-transmitter) "UNLIMITED"
set ::setting(category-overlay) "ROOKIE"
set ::setting(claimed-score) "0"
set ::setting(club) "RoverLog Amateur Radio Club"
set ::setting(contest) "ARRL-VHF-JAN"
set ::setting(email) "n0ne@nowhere.com"
set ::setting(location) "WMA"
set ::setting(name) "Nobody"
set ::setting(address1) "123 Nowhere St."
set ::setting(address2) "Noplace, NO  00000"
set ::setting(address3) "USA"
set ::setting(operators) "N0OP N0ONE"
set ::setting(soapbox1) "RoverLog is terrific!"
set ::setting(soapbox2) ""
set ::setting(soapbox3) ""

set fn "n0ne.log"

raise .
focus .
wm title . "Log Header Editor"
if { $tcl_platform(os) != "Linux" && $tcl_platform(os) != "Darwin" } {
  wm iconbitmap . logheaded.ico
}
wm protocol . WM_DELETE_WINDOW My_Exit
wm resizable . 0 0
