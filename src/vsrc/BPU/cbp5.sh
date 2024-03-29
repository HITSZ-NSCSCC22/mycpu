#!/bin/bash
set -Eeuo pipefail

PARALLEL_NUM=8


# Create a file FIFO to control parallel process number
FIFO_FILE=/tmp/cbp.fifo
rm -f ${FIFO_FILE}
mkfifo ${FIFO_FILE}
exec 1000<>${FIFO_FILE}

for id in $(seq ${PARALLEL_NUM}); do
    echo ${id} >&1000
done

work() {
    rate=$(obj_dir/Vtage_predictor $1 | tee -a cbp5-raw.log | grep "MPKI")
    echo "$1 ${rate}" | tee -a cbp5.log
}

rm -rf cbp5.log
rm -rf cbp5-raw.log

traces=$(find data/ -type f -not -name "*.cnt" | sort)

for t in ${traces}; do
    read -u1000
    {
        work ${t} 
        echo "new" > ${FIFO_FILE}
    }&

done

wait

rm -f /tmp/extract.fifo
cat cbp5.log | awk '{sum += $3; cnt+=1;} END {print sum / cnt}'
echo "Done"