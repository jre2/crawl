#!/bin/sh
if [ -d ../src ]; then cd ../; fi
if [ -d bin ]; then cd bin; fi
odin run ../src/ -out:crawl.exe -debug
