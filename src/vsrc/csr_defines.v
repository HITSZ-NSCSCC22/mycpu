//CRMD
`define PLV       1:0
`define IE        2
`define DA        3
`define PG        4
`define DATF      6:5
`define DATM      8:7

//PRMD
`define PPLV      1:0
`define PIE       2

//ECTL
`define LIE       12:0

//ESTAT
`define IS        12:0
`define ECODE     21:16
`define ESUBCODE  30:22

//TLBIDX
`define INDEX     4:0
`define PS        29:24
`define NE        31

//TLBEHI
`define VPPN      31:13

//TLBELO
`define TLB_V      0
`define TLB_D      1
`define TLB_PLV    3:2
`define TLB_MAT    5:4
`define TLB_G      6
`define TLB_PPN    31:8
`define TLB_PPN_EN 27:8   

//ASID
`define TLB_ASID  9:0

//CPUID
`define COREID    8:0

//LLBCTL
`define ROLLB     0
`define WCLLB     1
`define KLO       2

//TCFG
`define EN        0
`define PERIODIC  1
`define INITVAL   31:2

//TICLR
`define CLR       0

//TLBRENTRY
`define TLBRENTRY_PA 31:6

//DMW
`define PLV0      0
`define PLV3      3 
`define DMW_MAT   5:4
`define PSEG      27:25
`define VSEG      31:29

//PGDL PGDH PGD
`define BASE      31:12

`define CRMD   14'h0
`define PRMD   14'h1
`define ECTL   14'h4
`define ESTAT  14'h5
`define ERA    14'h6
`define BADV   14'h7
`define EENTRY  14'hc
`define TLBIDX 14'h10
`define TLBEHI 14'h11
`define TLBELO014'h12
`define TLBELO114'h13
`define ASID   14'h18
`define PGDL   14'h19
`define PGDH   14'h1a
`define PGD    14'h1b
`define CPUID  14'h20
`define SAVE0  14'h30
`define SAVE1  14'h31
`define SAVE2  14'h32
`define SAVE3  14'h33
`define TID    14'h40
`define TCFG   14'h41
`define TVAL   14'h42
`define CNTC   14'h43
`define TICLR  14'h44
`define LLBCTL 14'h60
`define TLBRENTRY  14'h88
`define DMW0   14'h180
`define DMW1   14'h181
`define BRK  14'h100
`define DISABLE_CACHE  14'h101