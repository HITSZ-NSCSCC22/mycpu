#!/bin/bash

traces=$(find data/ -type f -not -name "*.cnt" | sort)

for t in ${traces}
do

rate=$(obj_dir/Vtage_predictor $t | tee -a cbp5-raw.log | grep "MPKI")

echo "${t} ${rate}" | tee -a cbp5.log
done