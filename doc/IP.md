# Xilinx IP 核生成要求

如果提示找不到到模块，可能需要手动调整编译顺序，将 IP 核的编译顺序提前

## ICache BRAM

Enable Port Type: use Enable PIN

no primitive output register

Tag BRAM:
- module name: bram_icache_tag_ram
- width: 21
- depth: 1024
- operating mode: Write First

Data BRAM:
- module name: bram_icache_data_ram
- width: 128
- depth: 1024
- operating mode: Write First

## BPU BRAM

FTB BRAM:
- module name: bram_ftb
- width: 88
- depth: 1024
- operating mode: Read First

TAGE base predictor BRAM:
- module name: bram_bpu_base_predictor
- width: 2
- depth: 16384 
- operating mode: Write First

TAGE tagged predictor BRAM:
- module name: bram_bpu_tagged_predictor
- width: 18
- depth: 1024
- operating mode: Write First