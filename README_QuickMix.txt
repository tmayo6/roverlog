QuickMix Version 1.05 by Product Technology Partners

Copyright (C) 2002 Product Technology Partners Ltd
http://www.msaxon.com/quickmix/
mailto:quickmix@msaxon.com

QuickMix is freeware. To get a better product,
please send your suggestions and report any 
problems to quickmix@msaxon.com
=================================================

Are you fed up with carefully setting the audio mixer
on your Windows 95/98/NT4/2000/XP computer only to have the
settings changed by another application or when you
reboot?

Do you need to store and recall different sets of
mixer settings quickly and easily?

Then QuickMix is for you.

QuickMix is a simple applet that allows you to store
all or part of the current state of your audio mixer
in a settings file, and to restore the mixer to that
state whenever you want.

The QuickMix installation puts a QuickMix icon in a
Martin Saxon Systems folder in the Programs section of
the Start menu. You can use this icon to run QuickMix.

QuickMix has two modes of operation: 'Interactive'
and 'Command Line'.


INTERACTIVE QUICKMIX - SAVING THE MIXER STATE
=============================================
Once you have the mixer in the state you want, run
QuickMix from the Start menu.

If you have more than one mixer device, you can choose
the one you want to work with from the drop-down box.

The checkboxes on the QuickMix panel allow
you to select which mixer channels you want to save.
There is usually at least a 'play' channel and a
'record' channel - the exact names vary from driver
to driver - but there may be others.

Having selected the channels you want to save,
click the 'Save...' button to display a file dialog.
Choose a file name (the default extension is .qmx) 
then click 'Save' to save the settings in that file.

Note that a .qmx settings file is in plain text format;
in fact, it is in Windows .INI file format. So if you
are adventurous you can edit this file manually using
a plain text editor such as Windows NOTEPAD.


INTERACTIVE QUICKMIX - RESTORING THE MIXER STATE
================================================
To restore a saved mixer state, you can just double-
click on a .qmx file and QuickMix will restore that
state.

Why not put a shortcut to a .qmx file in the Startup
folder of your start menu? Then, the mixer will be
set to those settings every time you boot up and
log in! 

Alternatively, you can run QuickMix from the Start menu,
and use the checkboxes to select which mixer, and which
mixer channels, you want to restore. Then click the
'Load..' button to display a file dialog. Choose a
QuickMix settings file, then click 'Open' to apply
these settings to the mixer.


COMMAND LINE QUICKMIX
=====================
You can run QuickMix as a command line utility, either
at an MS-DOS command prompt or from the Start|Run...
dialog. To save the current mixer settings in a file,
use the command:

	<path>\QuickMix /s <filename>

Where <path> is the drive and directory where QuickMix
is installed, and <filename> is the name of the file
you want to save to (the .qmx extension will be added
if it is not there). Note that, if you have more than
one mixer, one file for each mixer will be created. For
example, if you have two mixers called 'Soundblaster 16'
and 'USB Audio Device', and you try to save to filename
'snaphot', then the files

	snapshot - Soundblaster 16.qmx
	snapshot - USB Audio Device.qmx

will be created.	

To restore the mixer settings from a file, use the
command:

	<path>\QuickMix <filename>

In this case, if you have more than one mixer,
QuickMix will automatically find the right mixer to set.
It's as simple as that!


RESTRICTIONS
============

1. You can only restore mixer settings if you have exactly
the same soundcard and driver software installed as when
the settings were saved. 

2. QuickMix can only handle mixers with up to 10 channels
and 300 individual controls.

----------------
REVISION HISTORY
================
1.05    27/06/02    Bugfix to improve robustness of mixer queries
1.04	14/12/01    Bugfix to allow restore of record controls only
1.03	23/05/01    Support for more than one mixer device added
1.02.2515 15/01/01  Bugfix release
1.02a   12/01/01    Added diagnostics for mixer changes
1.02    28/05/99    Increased max channels to 10, max controls to 300
1.01    27/05/99    Added error diagnostics
1.00    21/05/99    First release
