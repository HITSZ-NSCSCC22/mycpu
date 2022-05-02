
cbp:  *.sv
	verilator -O3 tage_predictor.sv --exe cbp3.cpp --cc -I../ | true # Ignore errors
	@make -C obj_dir -f Vtage_predictor.mk 2>&1 >/dev/null
	trace_id=0; while [[ $$trace_id -lt 20 ]]; do \
		echo $$(./obj_dir/Vtage_predictor $$trace_id | grep MPKI); \
		(( trace_id = trace_id + 1 )); \
	done

benchmark: verilate
	./benchmark.sh

test: verilate
	./obj_dir/Vtage_predictor
	

VERILATOR_FLAGS = -O3 #+define+DUMP_WAVEFORM=1 --trace

verilate: *.sv
	verilator $(VERILATOR_FLAGS) tage_predictor.sv --exe testbench.cpp --cc -I../ | true # Ignore errors
	@make -C obj_dir -f Vtage_predictor.mk 2>&1 >/dev/null

clean:
	rm -rf obj_dir/