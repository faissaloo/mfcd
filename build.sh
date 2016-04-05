#!/bin/bash
##################################MIT LICENCE###################################
#Permission is hereby granted, free of charge, to any person obtaining a copy of
#build.sh and associated documentation files (the "Software"), to deal in
#build.sh without restriction, including without limitation the rights to
#use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
#the Software, and to permit persons to whom build.sh is furnished to do so,
#subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
#FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
#COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
#IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
#CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
################################################################################
nasm -f elf mfcd.asm
ld -o mfcd mfcd.o -melf_i386
rm mfcd.o
strip -v mfcd -R .bss #Remove .bss because we won't need it in the main executable, this saves more space
echo
echo " Done building, the file 'mfcd' is your executable"
echo " $(ls -l  ./mfcd | cut -d ' ' -f5)" bytes
