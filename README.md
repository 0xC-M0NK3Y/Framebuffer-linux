# Framebuffer-linux
Example of using assembly and linux framebuffer in to print pixels on tty (with only syscalls).

## Overview

Its x86-64 linux assembly (intel syntax)  
It may not work if you don't have a packed screen type   

Its basically changing terminal mode to "raw" to have a non blocking read  
then it open "/dev/fb0" the linux framebuffer  
it map its into the RAM (with mmap)  
then display a square at the center of the screen  
then you can start to draw  
  
It use NASM and ld to make an ELF-64 executable (look at build.sh)  
  
you need to switch to a tty to see (Ctrl-Alt-F1-9)

#### Keyboard

| Key              | Action                                                    |
|------------------|-----------------------------------------------------------|
| <kbd>z</kbd>     | draw up                                                   |
| <kbd>s</kbd>     | draw down                                                 |
| <kbd>d</kbd>     | draw right                                                |
| <kbd>q</kbd>     | draw left                                                 |
| <kbd>e</kbd>     | exit                                                      |
