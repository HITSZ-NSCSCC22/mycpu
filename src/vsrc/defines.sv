`ifndef DEFINES_SV
`define DEFINES_SV

// Global define
`define RstEnable 1'b1
`define RstDisable 1'b0
`define ZeroWord 32'h00000000
`define WriteEnable 1'b1
`define WriteDisable 1'b0
`define ReadEnable 1'b1
`define ReadDisable 1'b0
`define AluOpBus 7:0
`define AluSelBus 2:0
`define InstValid 1'b1
`define InstInvalid 1'b0
`define Stop 1'b1
`define NoStop 1'b0
`define Branch 1'b1
`define NotBranch 1'b0
`define InterruptAssert 1'b1
`define InterruptNotAssert 1'b0
`define TrapAssert 1'b1
`define TrapNotAssert 1'b0
`define True_v 1'b1
`define False_v 1'b0
`define ChipEnable 1'b1
`define ChipDisable 1'b0


// Instruction Encode


`define EXE_LU12I_W 6'b000101 // 7'b0001010
`define EXE_PCADDU12I 6'b000111 // 7'b0001110

`define EXE_B 6'b010100
`define EXE_BL 6'b010101

// 6-12 bit opcode, decoded in opcode_2
`define EXE_ATOMIC_MEM 6'b001000
`define EXE_LL_W 6'b00????
`define EXE_SC_W 6'b01????


`define EXE_SPECIAL 6'b000001
`define EXE_CSR_RELATED 6'b00????
`define EXE_OTHER 6'b100100
`define EXE_CSRRD 5'b00000
`define EXE_CSRWR 5'b00001
`define EXE_CSRXCHG 5'b00011
`define EXE_TLB_RELATED 5'b10000

// 2R-type
`define EXE_TLBSRCH 22'b0000011001001000001010
`define EXE_TLBRD 22'b0000011001001000001011
`define EXE_TLBWR 22'b0000011001001000001100
`define EXE_TLBFILL 22'b0000011001001000001101
`define EXE_ERTN 22'b0000011001001000001110

// 3R-type
`define EXE_ADD_W 17'b00000000000100000
`define EXE_SUB_W 17'b00000000000100010
`define EXE_SLT 17'b00000000000100101
`define EXE_SLTU 17'b00000000000100101
`define EXE_NOR 17'b00000000000101000
`define EXE_AND 17'b00000000000101001
`define EXE_OR 17'b00000000000101010
`define EXE_XOR 17'b00000000000101011
`define EXE_SLL_W 17'b00000000000101110
`define EXE_SRL_W 17'b00000000000101111
`define EXE_SRA_W 17'b00000000000110000
`define EXE_MUL_W 17'b00000000000111000
`define EXE_MULH_W 17'b00000000000110001
`define EXE_MULH_WU 17'b00000000000110010
`define EXE_DIV_W 17'b00000000001000000
`define EXE_MOD_W 17'b00000000001000001
`define EXE_DIV_WU 17'b00000000001000010
`define EXE_MOD_WU 17'b00000000001000011
`define EXE_BREAK 17'b00000000001010100
`define EXE_SYSCALL 17'b00000000001010110
// 
`define EXE_IDLE 17'b00000110010010001
`define EXE_INVTLB 17'b00000110010010011
// 顺序核无需实现
`define EXE_DBAR 17'b00111000011100100
`define EXE_IBAR 17'b00111000011100101

// 2RI12-type
`define EXE_SLTI 10'b0000001000
`define EXE_SLTUI 10'b0000001001
`define EXE_ADDI_W 10'b0000001010
`define EXE_ANDI 10'b0000001101
`define EXE_ORI 10'b0000001110
`define EXE_XORI 10'b0000001111
`define EXE_LD_B 10'b0010100000
`define EXE_LD_H 10'b0010100001
`define EXE_LD_W 10'b0010100010
`define EXE_ST_B 10'b0010100100
`define EXE_ST_H 10'b0010100101
`define EXE_ST_W 10'b0010100110
`define EXE_LD_BU 10'b0010101000
`define EXE_LD_HU 10'b0010101001
`define EXE_PRELD 10'b0010101011

// 2RI16-type
`define EXE_JIRL 6'b010011
`define EXE_BEQ 6'b010110
`define EXE_BNE 6'b010111
`define EXE_BLT 6'b011000
`define EXE_BGE 6'b011001
`define EXE_BLTU 6'b011010
`define EXE_BGEU 6'b011011



`define EXE_SLLI_W 5'b00??? // EXE_SHIFT_ARITH
`define EXE_SRLI_W 5'b01???
`define EXE_SRAI_W 5'b10???


`define EXE_NOP 22'b0



// AluOp
`define EXE_NOP_OP 8'b00000000
`define EXE_OR_OP 8'b00000001
`define EXE_AND_OP 8'b00000010
`define EXE_XOR_OP 8'b00000011
`define EXE_NOR_OP 8'b00000100
`define EXE_LUI_OP 8'b00000101
`define EXE_SLL_OP 8'b00000101
`define EXE_SRL_OP 8'b00000110
`define EXE_SRA_OP 8'b00000111
`define EXE_ADD_OP 8'b00001000
`define EXE_SUB_OP 8'b00001001
`define EXE_MUL_OP 8'b00001010
`define EXE_MULH_OP 8'b00001011
`define EXE_MULHU_OP 8'b00001100
`define EXE_DIV_OP 8'b00001101
`define EXE_MOD_OP 8'b00001110
`define EXE_SLT_OP 8'b00001111
`define EXE_SLTU_OP 8'b00010000
`define EXE_B_OP 8'b00010001
`define EXE_BL_OP 8'b00010010
`define EXE_BEQ_OP 8'b00010011
`define EXE_BNE_OP 8'b00010100
`define EXE_BLT_OP 8'b00010101
`define EXE_BGE_OP 8'b00010110
`define EXE_BLTU_OP 8'b00010111
`define EXE_BGEU_OP 8'b00011000
`define EXE_JIRL_OP 8'b00011001
`define EXE_LD_B_OP 8'b00011010
`define EXE_LD_H_OP 8'b00011011
`define EXE_LD_W_OP 8'b00011100
`define EXE_ST_B_OP 8'b00011101
`define EXE_ST_H_OP 8'b00011110
`define EXE_ST_W_OP 8'b00011111
`define EXE_LD_BU_OP 8'b00100000
`define EXE_LD_HU_OP 8'b00100001
`define EXE_LL_OP 8'b00100010
`define EXE_SC_OP 8'b00100011
`define EXE_PCADD_OP 8'b00100100
`define EXE_SYSCALL_OP 8'b00100101
`define EXE_BREAK_OP 8'b00100110
`define EXE_CSRRD_OP 8'b00100111
`define EXE_CSRWR_OP 8'b00101000
`define EXE_CSRXCHG_OP 8'b00101001
`define EXE_TLBFILL_OP 8'b00101010
`define EXE_TLBRD_OP 8'b00101011
`define EXE_TLBWR_OP 8'b00101100
`define EXE_TLBSRCH_OP 8'b00101101
`define EXE_ERTN_OP 8'b00101110
`define EXE_IDLE_OP 8'b00101111
`define EXE_INVTLB_OP 8'b00110000


//AluSel
`define EXE_RES_NOP 3'b000
`define EXE_RES_LOGIC 3'b001
`define EXE_RES_SHIFT 3'b010
`define EXE_RES_MOVE 3'b011
`define EXE_RES_ARITH 3'b100
`define EXE_RES_JUMP 3'b101
`define EXE_RES_LOAD_STORE 3'b110


// Rom related
`define InstAddrBus 31:0
`define InstBus 31:0
`define InstMemNum 131071
`define InstMemNumLog2 17

// Registers
`define RegAddrBus 4:0
`define RegBus 31:0
`define RegWidth 32
`define RegNum 32
`define RegNumLog2 5
`define NOPRegAddr 5'b00000
`define DoubleRegBus 63:0

//data_ram
`define DataAddrBus 31:0
`define DataBus 31:0
`define DataMemNum 128
`define DataMemNumLog2 17
`define ByteWidth 7:0


// SRAM latency
`define CacheLatency 0

typedef struct packed {
    logic we;
    logic [`RegAddrBus] addr;
    logic [`RegBus] data;
} reg_write_signal;
//tlb-compare-part
//typedef struct packed {

//} tlb_com_part;

`endif
