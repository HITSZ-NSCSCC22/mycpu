

VERILATOR_FLAGS = +define+DUMP_WAVEFORM=1 
#--trace

verilate: *.v
	verilator $(VERILATOR_FLAGS) tage_predictor.v --exe testbench.cpp --cc -I../ | true # Ignore errors
	@make -C obj_dir -f Vtage_predictor.mk 2>&1 >/dev/null
	./obj_dir/Vtage_predictor +trace

clean:
	rm -rf obj_dir/