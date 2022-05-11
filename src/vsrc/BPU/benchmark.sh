#!/bin/bash

traces=$(find data/traces -type f | sort)

for t in ${traces}
do

rate=$(obj_dir/Vtage_predictor $t | grep "Rate")

echo "${t} ${rate}"
done