
all: test

cbp:  *.sv
	verilator -O3 tage_predictor.sv --exe testbench/cbp3.cpp --cc -I../ | true # Ignore errors
	@make -C obj_dir -f Vtage_predictor.mk 2>&1 >/dev/null
	trace_id=0; while [[ $$trace_id -lt 20 ]]; do \
		echo $$(./obj_dir/Vtage_predictor $$trace_id | grep MPKI); \
		> logs/mpki.log \
		echo $$(./obj_dir/Vtage_predictor $$trace_id | grep MPKI) >> logs/mpki.log; \
		(( trace_id = trace_id + 1 )); \
	done
	@echo "Average MPKI:"
	cat logs/mpki.log | awk '{sum += $2; cnt+=1} END {print sum / cnt}'


benchmark: verilate
	./benchmark.sh

test: verilate
	./obj_dir/Vtage_predictor
	

VERILATOR_FLAGS = -O3 #+define+DUMP_WAVEFORM=1 --trace-fst

verilate: *.sv
	verilator $(VERILATOR_FLAGS) tage_predictor.sv --exe testbench/testbench.cpp --cc -I../ | true # Ignore errors
	@make -C obj_dir -f Vtage_predictor.mk 2>&1 >/dev/null

clean:
	rm -rf obj_dir/