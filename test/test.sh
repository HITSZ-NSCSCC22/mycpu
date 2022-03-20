#!/bin/bash
CASES=$(find test -name "*.bin")

for casename in ${CASES}
do
    echo "${casename}"
	./src/emu -b 0 -e 0 -i ${casename}  --diff=./la32-nemu-interpreter-so -I 6 --dump-wave
done