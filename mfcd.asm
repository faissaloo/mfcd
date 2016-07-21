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

  tempFile db "/sys/class/thermal/thermal_zone1/temp", 0 ;This is where we get the temperature from

  tempFileLen equ 7 ;Max length of the string to read, made 6+1 (for the '\0')
                    ;because if your CPU temp is higher than 999.99°C the computer
                    ;would have already died
  fanSpeedToSet db 0;The string that holds the fan speed to be written

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
    tv_sec  db 0    ;Time in seconds to delay the program after every check
    tv_usec db 0    ;Time in milliseconds

section .bss

tempFileBuff: resb 7 ;Max length of the string to store


section .text

_start:
  ;Fork to orphan the process from a shell to daemonise it
  mov eax, sys_fork
  push _firstFork
  push ecx
  push edx
  push ebp
  mov ebp, esp
  sysenter        ; Kernel interrupt
  pop ebp
  pop edx
  pop ecx
  _firstFork:
  test eax, eax ;If the return value is 0, we are in the child process therefore
              ;we may continue on to fork again
  jnz _exit  ;otherwise jump to _exit
  ;d-d-d-double fork!
  mov eax, sys_fork
  push _secondFork
  push ecx
  push edx
  push ebp
  mov ebp, esp
  sysenter        ; Kernel interrupt
  pop ebp
  pop edx
  pop ecx
  _secondFork:
  test eax, eax ;If the return value is 0, we are in the grandchild process therefore
              ;we may continue onto _main
  jnz _exit  ;otherwise jump to _exit
  ;Turn on manual control mode
  mov ebx, fanModeFile
  mov eax, sys_open
  mov ecx, O_WRONLY
  push _fanModeOpened
  push ecx
  push edx
  push ebp
  mov ebp, esp
  sysenter        ; Kernel interrupt
  pop ebp
  pop edx
  pop ecx
  _fanModeOpened:
  inc edx
  mov ebx, eax       ;Put the file descripter/'pointer' in ebx
  mov eax, sys_write
  mov ecx, fanMode
  push _fanModeSet
  push ecx
  push edx
  push ebp
  mov ebp, esp
  sysenter        ; Kernel interrupt
  pop ebp
  pop edx
  pop ecx
  _fanModeSet:
  mov eax, sys_close
  push _main
  push ecx
  push edx
  push ebp
  mov ebp, esp
  sysenter        ; Kernel interrupt
  pop ebp
  pop edx
  pop ecx
  _main:
      mov ebx, tempFile
      mov eax, sys_open
      xor ecx, ecx
      push _tempOpened
      push ecx
      push edx
      push ebp
      mov ebp, esp
      sysenter        ; Kernel interrupt
      pop ebp
      pop edx
      pop ecx
      _tempOpened:
      mov ebx, eax ;Put the file descripter/'pointer' in ebx
      mov eax, sys_read
      mov ecx, tempFileBuff
      mov edx, tempFileLen
      push _tempRead
      push ecx
      push edx
      push ebp
      mov ebp, esp
      sysenter        ; Kernel interrupt
      pop ebp
      pop edx
      pop ecx
      _tempRead:
      mov eax, sys_close
      push _strToInt
      push ecx
      push edx
      push ebp
      mov ebp, esp
      sysenter        ; Kernel interrupt
      pop ebp
      pop edx
      pop ecx
      ;Changes the string we get from .../temp to an int
      ;No need to check that it's a valid number because we already know it is
      _strToInt:
          xor eax, eax      ;set eax to zero to prepare it
          xor ecx, ecx
          mov ebx, tempFileBuff ;Copy the pointer to tempFileBuff to ebx
      _strToInt_main:
          mov cl,[ebx]
          cmp cl, 10
          jz _strToInt_end ;Newline signifies end of the string
          imul eax, 10     ;Int multiply eax by 10 to leave space for the next number e.g:
                            ; 20 <- 2
          sub cl, 48      ;Subtract ecx by 48 because 0-9 are 48-57 in ASCII
          add eax, ecx     ;Add ecx to eax.
                            ;  9
                            ;  V
                            ; 29 <- 20 <- 2
          inc ebx          ;incriment ebx to prepare the next loop
          jmp _strToInt_main
      _strToInt_end:

      ;Cap the temps to the limits we've set
      cmp eax, maxTemp
      jg _tempTooHigh
      cmp eax, minTemp
      jl _tempTooLow
      jmp _tempOk
      _tempTooHigh:
        mov eax, maxTemp
        jmp _tempOk
      _tempTooLow:
        mov eax, minTemp
      _tempOk:
      ;currTemp is in eax from our strToInt
      ;Here we do our fancy math
      ;Thanks to @sheepytweety for helping me improve this
      ;fanSpeed=(((currTemp - minTemp)*(maxFanSpeed-minFanSpeed))//(maxTemp-minTemp))+minFanSpeed
      sub eax, minTemp           ;  (currTemp - minTemp)
      imul eax, fanSpeedDiff     ;  (currTemp - minTemp)*(maxFanSpeed-minFanSpeed)
      mov ebx, tempDiff;                                                    (maxTemp-minTemp)

      xor edx, edx      ;We have to clear EDX because idiv uses EDX:EAX
      idiv ebx          ;(((currTemp - minTemp)*(maxFanSpeed-minFanSpeed))//(maxTemp-minTemp))
      ;Result is in eax, add the minFanSpeed
      add eax, minFanSpeed;(((currTemp - minTemp)*(maxFanSpeed-minFanSpeed))//(maxTemp-minTemp))+minFanSpeed

      ;Turn the int we've calculated back into a str
      _intToStr:
        mov ebx, fanSpeedToSet  ;Put the pointer to fanSpeedToSet (str) in ebx
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
        inc ebx
        jmp _intToStr_main
      _intToStr_end:
        ;String is backwards, so we have to reverse it
        _revStr:
          mov esi, fanSpeedToSet ;Start of string
          mov edi, ebx           ;End of string
          sub ebx, fanSpeedToSet ;Length of string
          ;Now the string has to be reversed
          dec edi
        _revStr_main:
          mov al,[esi]
          mov ah,[edi]
          ;Do swapsies
          mov [esi],ah
          mov [edi],al
          inc esi
          dec edi
          cmp esi,edi
          jnge _revStr_main ;If the pointers have gone past each other stop, it means we're done
        _revStr_end:
      mov edx, ebx     ;Length was in ebx, move it to edx before we have to
                        ;modify ebx to put the fanFile pointer in it, sys_write
                        ;also uses edx to store the length anyways
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
      pop ebp
      pop edx
      pop ecx
      _fanOpened:
        mov ebx, eax       ;Put the file descripter/'pointer' in ebx
        mov eax, sys_write
        mov ecx, fanSpeedToSet
        push _fanSet
        push ecx
        push edx
        push ebp
        mov ebp, esp
        sysenter        ; Kernel interrupt
        pop ebp
        pop edx
        pop ecx
        ;Error codes that will be put in eax should an error occur for reference:
        ;http://www-numi.fnal.gov/offline_software/srt_public_context/WebDocs/Errors/unix_system_errors.html
        _fanSet:
          mov eax, sys_close
          push _fanClosed
          push ecx
          push edx
          push ebp
          mov ebp, esp
          sysenter        ; Kernel interrupt
          pop ebp
          pop edx
          pop ecx
          _fanClosed:
            ;Delay before looping again to prevent pegging
            mov dword [tv_sec], fanDelay
            ;No need to set milliseconds, that just takes up storage space and CPU time
            mov eax, sys_nanosleep
            mov ebx, timeval  ;sys_nanosleep
            xor ecx, ecx
            push _main ;Jumps to _main after the delay
            push ecx
            push edx
            push ebp
            mov ebp, esp
            sysenter        ; Kernel interrupt
            pop ebp
            pop edx
            pop ecx
_exit:
  ;Clean exit
  mov eax, sys_exit
  xor ebx, ebx
  mov ebp, esp
  sysenter        ; Kernel interrupt
