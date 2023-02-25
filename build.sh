#!/bin/bash

if [ $# -ne 1 ]; then
	echo "Usage: $0 <file>"
	exit 1
fi

nasm -f elf64 -o tmp.o $1
ld tmp.o -o bin
rm tmp.o
