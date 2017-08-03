Tom Mayo, N1MU
9/7/2005

I built this little iopwr.exe utility to allow command line access to write
to the PC's parallel port.  It is confirmed to work under Windows 2000 and XP
providing you CHECK THE BASE ADDRESS OF YOUR PRINTER PORT (see below).

You need inpout32.dll for this to work!

References:
http://www.logix4u.net/inpout32.htm
http://www.hytherion.com/beattidp/comput/pport.htm

For example, on the DB-25 connector

Pin 2 = D0
Pin 7 = D5
Pin 8 = D6
Pin 9 = D7
Pin 15 = GND

To find your parallel port base address, consult
My Computer->Properties->Hardware->Device Manager->Ports (COM & LPT)

LPT1: is typically at address 378, so for example

iopwr 378 0  (all outputs off)
iopwr 378 1  (D0 on)
iopwr 378 20 (D5 on)
iopwr 378 40 (D6 on)
iopwr 378 80 (D7 on)
iopwr 378 e1 (all outputs on)

Replace 378 with the address of the parallel port you are using.
On my laptop, it's 3bc, for example.  Check this BEFORE trying it.

Here's some other info that might help with N3FTI's Pack Rats interface
board:

Band   A  B  C  D  Binary    Hex
                   DCB     A

50     0  0  0  0  0000 0000  0
144    1  0  0  0  0000 0001  1
222    0  1  0  0  0010 0000 20
432    1  1  0  0  0010 0001 21
902    0  0  1  0  0100 0000 40
1296   1  0  1  0  0100 0001 41
2304   0  1  1  0  0110 0000 60
3456   1  1  1  0  0110 0001 61
5760   0  0  0  1  1000 0000 80
10368  1  0  0  1  1000 0001 81
24G    0  1  0  1  1010 0000 a0
47G    1  1  0  1  1010 0001 a1

A   LPT pin 2
B   LPT pin 7
C   LPT pin 8
D   LPT pin 9
GND LPT pin 19-22

Also, there is a rumor that XP's autodetect feature will turn off the outputs
periodically.  There is information on how to stop this here:
http://www.lvr.com/jansfaq.htm
