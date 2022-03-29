#!/bin/bash
CASES=$(find test -name "*.bin")
export NOOP_HOME=$(pwd)

for casename in ${CASES}
do
    echo "${casename}"
    file_size=$(stat ${casename} -c"%s")
    instr_cnt=$((${file_size} / 4))
    echo ${instr_cnt}
	./src/emu -b 0 -e 10000 -i ${casename}  --diff=./la32-nemu-interpreter-so -I ${instr_cnt} --dump-wave
    if [ $? -ne 0 ]; then
        echo "Case ${casename} Error"
        exit -1
    fi
done