.PHONY: sim-verilog difftest

sim-verilog:
	@echo "SIM VERILOG"

PROJECT_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.ONESHELL: # For cd
# difftest: export NOOP_HOME=$(PROJECT_ROOT)/
# difftest: export NEMU_HOME=$(PROJECT_ROOT)/
build-difftest: src/SimTop.v
	cd difftest/
		# export EMU_TRACE=1
		make -j emu
	cd ../

run-difftest:
	./test/test.sh

VERILATOR_FLAGS = +define+DUMP_WAVEFORM=1 --trace

verilate: src/
	verilator $(VERILATOR_FLAGS) src/SimTop.v --exe testbench.cpp --cc -Isrc/vsrc -Isrc -Isrc/vsrc/pipeline/1_fetch
	@make -C obj_dir -f VSimTop.mk 2>&1 >/dev/null
	./obj_dir/VSimTop +trace


clean:
	rm -rf src/emu 
	rm -rf src/emu-compile
	rm -rf src/time.log
	rm -rf src/lock-emu
	rm -rf src/*.vcd
	rm -rf obj_dir/