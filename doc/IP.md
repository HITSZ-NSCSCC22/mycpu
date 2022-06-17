# Xilinx IP 核生成要求

如果提示找不到到模块，可能需要手动调整编译顺序，将 IP 核的编译顺序提前

## ICache BRAM

Enable Port Type: Always Enabled

no primitive output register

Tag BRAM:
- module name: bram_icache_tag_ram
- width: 21
- depth: 256

Data BRAM:
- module name: bram_icache_data_ram
- width: 128
- depth: 256