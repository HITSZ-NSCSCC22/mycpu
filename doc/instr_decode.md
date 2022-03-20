# 译码阶段

现行设计分为四级译码，6+6+5+5

- 9条转移指令
- LU12I.W
- PCADDU12I
- 原子访存指令
    - LL.W
    - SC.W
- 访存指令
    - 9条访存指令，包括一条预取
- 特殊指令（和特权架构相关）
    - CSR相关指令
    - TLB相关指令
    - 系统调用相关指令
- 算术指令
    - SLTI
    - SLTUI 
    - ADDI.W
    - ANDI
    - ORI
    - XORI
    - 其他算术指令
        - 14条
    - 除法相关指令
        - 4条除法、取余
        - BREAK
        - SYSCALL
    - 移位指令
        - SLLI.W 
        - SRLI.W
        - SRAI.W