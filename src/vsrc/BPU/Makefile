
all: test

cbp:  *.sv
	verilator -O3 tage_predictor.sv --exe testbench/cbp3.cpp --cc -I../ | true # Ignore errors
	@make -C obj_dir -f Vtage_predictor.mk 2>&1 >/dev/null
	mkdir -p logs
	> logs/mpki.log
	trace_id=0; while [[ $$trace_id -lt 20 ]]; do \
		echo $$(./obj_dir/Vtage_predictor $$trace_id | grep MPKI); \
		echo $$(./obj_dir/Vtage_predictor $$trace_id | grep MPKI) >> logs/mpki.log; \
		(( trace_id = trace_id + 1 )); \
	done
	@echo "Average MPKI:"
	@cat logs/mpki.log | awk '{sum += $$2; cnt+=1} END {print sum / cnt}'


benchmark: verilate
	./benchmark.sh

cbp5: cbp5-verilate
	./cbp5.sh

test: verilate
	./obj_dir/Vtage_predictor
	

VERILATOR_FLAGS = -O3 #+define+DUMP_WAVEFORM=1 --trace-fst

cbp5-verilate: *.sv
	verilator $(VERILATOR_FLAGS) tage_predictor.sv --exe testbench/cbp5.cpp --cc -I../ | true # Ignore errors
	@make -C obj_dir -f Vtage_predictor.mk 2>&1 >/dev/null
verilate: *.sv
	verilator $(VERILATOR_FLAGS) tage_predictor.sv --exe testbench/testbench.cpp --cc -I../ | true # Ignore errors
	@make -C obj_dir -f Vtage_predictor.mk 2>&1 >/dev/null

clean:
	rm -rf obj_dir/
	rm -rf logs/
	rm -rf *.log