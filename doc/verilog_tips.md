# 每日一个 Verilog 小技巧

## $clog2() 是可综合的

`$clog2()`是 ceil(log2(x)) 的意思，2 的对数的向上取整，常用于已知寻址范围，确定索引信号的位宽。

虽然看起来是一个系统调用，但是由于实在是过于好用，大部分的仿真和综合工具都支持处理这个函数。

## always 块中最后一个赋值覆盖前面的

这很有用，如果想要实现带有优先级的组合逻辑，可以避免使用超级长的 if-else 判断，而是利用越后面的赋值优先级越高来代替 if-else

当然，这可能带来高的延迟。


## 有符号乘除
```{verilog}
`EXE_MUL_OP: arithout = $signed(reg1_i) * $signed(reg2_i);
`EXE_MULH_OP: arithout = ($signed(reg1_i) * $signed(reg2_i)) >> 32;
`EXE_MULHU_OP: arithout = ($unsigned(reg1_i) * $unsigned(reg2_i)) >> 32;
`EXE_DIV_OP: arithout = ($signed(reg1_i) / $signed(reg2_i));
`EXE_DIVU_OP: arithout = ($unsigned(reg1_i) / $unsigned(reg2_i));
`EXE_MODU_OP: arithout = ($unsigned(reg1_i) % $unsigned(reg2_i));
`EXE_MOD_OP: arithout = ($signed(reg1_i) % $signed(reg2_i));
```