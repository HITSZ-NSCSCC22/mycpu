#!/bin/bash
CASES=$(find test -name "*.bin")

for casename in ${CASES}
do
    echo "${casename}"
    instr_cnt=$(stat ${casename} -c"%b")
    echo ${instr_cnt}
	./src/emu -b 0 -e 0 -i ${casename}  --diff=./la32-nemu-interpreter-so -I ${instr_cnt} --dump-wave
done