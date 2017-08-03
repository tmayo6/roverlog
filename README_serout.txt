Tom Mayo, N1MU
5/14/2009

Here is a simple batch file (serout.bat) to allow you to send serial commands
when you switch bands.

To use it, put (for example) the following line in one of the Rig configuration
lines in the Rig Setup tab in the Ini Editor:

1.2 0 1296.1000 exec serout COM1: 9600 go to 1296

where COM1: can be replaced with your serial port, 9600 is the baud rate
(N,8,1 is assumed for the mode), and go to 1296 is replaced with the message
appropriate to get your band switching aid in the mood for the desired band.

Make sure you have a colon after the serial port, i.e. COM1: instead of COM1.

May the force be with you.
