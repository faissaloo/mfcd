;mfcd is free software: you can redistribute it and/or modify
;    it under the terms of the GNU General Public License version 3 as published
;    by the Free Software Foundation.
;
;mfcd is distributed in the hope that it will be useful,
;    but WITHOUT ANY WARRANTY; without even the implied warranty of
;    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;    GNU General Public License for more details.
;
;You should have received a copy of the GNU General Public License version 3
;    along with this program. If not, see <https://www.gnu.org/licenses/gpl-3.0.txt>.
global _start

section .data

  ;USER CONSTANTS, CHANGE ACCORDING TO WHAT YOU NEED
  minTemp     equ 40000 ;20000=20°c
  maxTemp     equ 80000
  maxFanSpeed equ 6500  ;6500 = 6500rpm
  minFanSpeed equ 2000
  fanDelay    equ 10     ;Delay between speed changes in seconds
  ;DON'T CHANGE ANYTHING BELOW THIS UNLESS YOU KNOW WHAT YOU'RE DOING

  fanSpeedDiff equ maxFanSpeed-minFanSpeed
  tempDiff equ maxTemp-minTemp

  ;fanModeFile db "./fan1_manual",0 ;Debug
  fanModeFile db "/sys/devices/platform/applesmc.768/fan1_manual",0 ;We need to set this to 1 so we get control
  fanMode     db "1"
  ;fanFile db "./fan1_output",0 ;Debug
  fanFile db "/sys/devices/platform/applesmc.768/fan1_output",0 ;This is where we write our calculated temperature

  tempFile db "/sys/devices/platform/applesmc.768/temp5_input", 0 ;This is where we get the temperature from

  tempFileLen equ 7 ;Max length of the string to read, made 6+1 (for the '\0')
                    ;because if your CPU temp is higher than 999.99°C the computer
                    ;would have already died

  ;Our lovely system calls
  sys_nanosleep equ 162
  sys_close     equ 6
  sys_open      equ 5
  sys_write     equ 4
  sys_read      equ 3
  sys_fork      equ 2
  sys_exit      equ 1


  O_RDWR        equ 2
  O_WRONLY      equ 1
  O_RDONLY      equ 0

  timeval:
    tv_sec  dd 0    ;Time in seconds to delay the program after every check
    tv_usec dd 0    ;Time in milliseconds

section .bss

tempFileBuff: resb 7 ;Max length of the string to store, this is used both for the string we'll write and the string we'll read because we won't need to use both at once


section .text

_start:
  ;Fork to orphan the process from a shell to daemonise it
  mov eax, sys_fork
  push _firstFork
  lea ebp, [esp-12]
  sysenter        ; Kernel interrupt
  _firstFork:
  test eax, eax ;If the return value is 0, we are in the child process therefore
              ;we may continue on to fork again
  jnz _exit  ;otherwise jump to _exit
  ;d-d-d-double fork!
  mov eax, sys_fork
  push _secondFork
  lea ebp, [esp-12]
  sysenter        ; Kernel interrupt
  _secondFork:
  test eax, eax ;If the return value is 0, we are in the grandchild process therefore
              ;we may continue onto _main
  jnz _exit  ;otherwise jump to _exit
  ;Turn on manual control mode
  mov ebx, fanModeFile
  mov eax, sys_open
  mov ecx, O_WRONLY
  push _fanModeOpened
  lea ebp, [esp-12]
  sysenter        ; Kernel interrupt
  _fanModeOpened:
  inc edx            ;set edx to one
  mov ebx, eax       ;Put the file descripter/'pointer' in ebx
  mov eax, sys_write
  mov ecx, fanMode
  push _fanModeSet
  lea ebp, [esp-12]
  sysenter        ; Kernel interrupt
  _fanModeSet:
  mov eax, sys_close
  push _main
  lea ebp, [esp-12]
  sysenter        ; Kernel interrupt
  _main:
      mov ebx, tempFile
      mov eax, sys_open
      xor ecx, ecx
      push _tempOpened
      lea ebp, [esp-12]
      sysenter        ; Kernel interrupt
      _tempOpened:
      mov ebx, eax ;Put the file descripter/'pointer' in ebx
      mov eax, sys_read
      mov ecx, tempFileBuff
      mov edx, tempFileLen
      push _tempRead
      lea ebp, [esp-12]
      sysenter        ; Kernel interrupt
      _tempRead:
      mov eax, sys_close
      push _strToInt
      lea ebp, [esp-12]
      sysenter        ; Kernel interrupt
      ;Changes the string we get from .../temp to an int
      ;No need to check that it's a valid number because we already know it is
      _strToInt:
          xor eax, eax      ;set eax to zero to prepare it
          xor ecx, ecx
          mov esi, tempFileBuff ;Copy the pointer to tempFileBuff to ebx
      _strToInt_main:
          lodsb
          cmp al, 10
          lea ecx, [ecx+ecx*4]
          lea ecx, [eax-48+ecx*2]
          jz _strToInt_end ;Newline signifies end of the string
          ;(eax*10)+(ecx-48)
          jmp _strToInt_main
      _strToInt_end:
      mov eax,ecx
      ;Cap the temps to the limits we've set
      mov ebx, maxTemp
      cmp eax, ebx
      cmovg eax, ebx
      mov ebx, minTemp
      cmp eax, ebx
      cmovl eax, ebx
      
      ;currTemp is in eax from our strToInt
      ;Here we do our fancy math
      ;Thanks to @sheepytweety for helping me improve this
      ;fanSpeed=(((currTemp - minTemp)*(maxFanSpeed-minFanSpeed))//(maxTemp-minTemp))+minFanSpeed
      sub eax, minTemp           ;  (currTemp - minTemp)
      imul eax, fanSpeedDiff     ;  (currTemp - minTemp)*(maxFanSpeed-minFanSpeed)
      mov ebx, tempDiff          ;                                                 (maxTemp-minTemp)

      xor edx, edx      ;We have to clear EDX because idiv uses EDX:EAX
      idiv ebx          ;(((currTemp - minTemp)*(maxFanSpeed-minFanSpeed))//(maxTemp-minTemp))
      ;Result is in eax, add the minFanSpeed
      add ecx, minFanSpeed;(((currTemp - minTemp)*(maxFanSpeed-minFanSpeed))//(maxTemp-minTemp))+minFanSpeed

      ;Turn the int we've calculated back into a str
      _intToStr:
        mov ebx, tempFileBuff+tempFileLen  ;This is the string we'll write to
        mov ecx, 10 ;For idiv
      _intToStr_main:
        test eax, eax ;Result is saved in eax, which is why we're checking if it's 0
                    ;first
        jz _intToStr_end ;because if eax is 0 that means there's not more characters
                          ; to add.
        xor edx, edx ;Clear edx since edx:eax is taken as the numerator for idiv
        idiv ecx ;Using this as a modulo, remainder is in edx, that's what we'll
                 ;use to calculate the character and append it
        
        add edx, 48 ;int+48='int'
        mov byte [ebx], dl
        dec ebx
        jmp _intToStr_main
        _intToStr_end:
        mov edx, tempFileBuff+tempFileLen-1
        sub edx, ebx     ;Figure out the length of the new string        
                        ;modify ebx to put the fanFile pointer in it, sys_write
                        ;also uses edx to store the length anyways
         lea esi, [ebx+1] ;Grab the start of the string and stick it in ecx for use later

      ;Time to write the result :D
      mov ebx, fanFile
      mov eax, sys_open
      mov ecx, O_WRONLY
      push _fanOpened
      push ecx
      push edx
      push ebp
      mov ebp, esp
      sysenter        ; Kernel interrupt
      _fanOpened:
        mov ebx, eax       ;Put the file descripter/'pointer' in ebx
        mov eax, sys_write
	mov ecx, esi
        push _fanSet
        lea ebp, [esp-12]
        sysenter        ; Kernel interrupt
        ;Error codes that will be put in eax should an error occur for reference:
        ;http://www-numi.fnal.gov/offline_software/srt_public_context/WebDocs/Errors/unix_system_errors.html
        _fanSet:
          mov eax, sys_close
          push _fanClosed
          lea ebp, [esp-12]
          sysenter        ; Kernel interrupt
          _fanClosed:
            ;Delay before looping again to prevent pegging
            mov dword [tv_sec], fanDelay
            ;No need to set milliseconds, that just takes up storage space and CPU time
            mov eax, sys_nanosleep
            mov ebx, timeval  ;sys_nanosleep
            xor ecx, ecx
            push _main ;Jumps to _main after the delay
            lea ebp, [esp-12]
            sysenter        ; Kernel interrupt
_exit:
  ;Clean exit
  mov eax, sys_exit
  xor ebx, ebx
  mov ebp, esp
  sysenter        ; Kernel interrupt
