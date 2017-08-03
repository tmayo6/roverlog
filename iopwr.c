/*****************************************************/
/***                                               ***/
/*** iopwr.c  -- interface to inpout32.dll         ***/
/***  ( http://www.logix4u.net/inpout32.htm )      ***/
/***                                               ***/
/*** Tom Mayo, 9/7/05                              ***/
/***                                               ***/
/*** Modified from test.c, originally by Douglas   ***/
/***  Beattie Jr.                                  ***/
/***                                               ***/
/*** Copyright (C) 2003, Douglas Beattie Jr.       ***/
/***                                               ***/
/***    <beattidp@ieee.org>                        ***/
/***    http://www.hytherion.com/beattidp/         ***/
/***                                               ***/
/*****************************************************/


/*******************************************************/
/*                                                     */
/*  Builds with Borland's Command-line C Compiler      */
/*    (free for public download from Borland.com, at   */
/*  http://www.borland.com/bcppbuilder/freecompiler )  */
/*                                                     */
/*   Compile with:                                     */
/*                                                     */
/*   BCC32 -IC:\BORLAND\BCC55\INCLUDE  iopwr.c         */
/*                                                     */
/*******************************************************/




#include <stdio.h>
#include <conio.h>
#include <windows.h>


/* Definitions in the build of inpout32.dll are:            */
/*   short _stdcall Inp32(short PortAddress);               */
/*   void _stdcall Out32(short PortAddress, short data);    */


/* prototype (function typedef) for DLL function Inp32: */

     typedef short _stdcall (*inpfuncPtr)(short portaddr);
     typedef void _stdcall (*oupfuncPtr)(short portaddr, short datum);

void usage(void)
{
  printf("usage: iopwr <hexaddress> <hexvalue>\n");
}


int main(int argc, char *argv[])
{
     HINSTANCE hLib;
     inpfuncPtr inp32;
     oupfuncPtr oup32;

     short x, y;
     int i;

     /* Check arguments */
     if ( argc != 3 ) {
       usage();
       return -1;
     }

     if ( sscanf( argv[1], "%x", &i ) != 1 ) {
       usage();
       return -1;
     }

     if ( sscanf( argv[2], "%x", &x ) != 1 ) {
       usage();
       return -1;
     }

     /* Load the library */
     hLib = LoadLibrary("inpout32.dll");

     if (hLib == NULL) {
          printf("LoadLibrary Failed.\n");
          return -1;
     }

     /* get the address of the function */

     inp32 = (inpfuncPtr) GetProcAddress(hLib, "Inp32");

     if (inp32 == NULL) {
          printf("GetProcAddress for Inp32 Failed.\n");
          return -1;
     }


     oup32 = (oupfuncPtr) GetProcAddress(hLib, "Out32");

     if (oup32 == NULL) {
          printf("GetProcAddress for Oup32 Failed.\n");
          return -1;
     }

     /***** Write out the requested value */
     (oup32)(i,x);

     /***** And read back to verify  */
     y = (inp32)(i);
     if ( x != y ) {
       printf("read returned %x not %x as requested.",y,x);
     }


     FreeLibrary(hLib);
     return 0;
}
