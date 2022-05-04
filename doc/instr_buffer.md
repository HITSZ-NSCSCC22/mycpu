# Instruction Buffer 设计

## 整体设计

使用类似状态机的写法，使用一个长度为`BUFFER_SIZE`的寄存器`buffer_queue`保存当前状态。
使用`read_ptr`和`write_ptr`记录后端和前端的读写位置。

更新逻辑：

根据后端当拍返回的可接受的指令，确定`read_ptr`的更新和`buffer_queue`对应位置的重置。

根据前端给出的指令更新`write_ptr`和对应位置的更新。

根据当前的两个ptr给出前端停顿的指令


## 前端信号

```verilog
    // <-> Frontend
    input instr_buffer_info_t frontend_instr_i[IF_WIDTH],
    output logic frontend_stallreq_o,  // Require frontend to stop
```
接受前端的两条指令，当拍给出`frontend_stallreq_o`

要求前端停顿时完全保持输入的两条指令不变

如果前端给出的两条指令不是都有效，那么要求有效的必须都在低位，而且保证指令的顺序关系，即低位对应指令流中靠前的指令。

## 后端信号

```verilog
    // <-> Backend
    input logic [ID_WIDTH-1:0] backend_accept_i,  // Backend can accept 0 or more instructions, must return in current cycle!
    input logic backend_flush_i,  // Backend require flush, maybe branch miss
    output instr_buffer_info_t backend_instr_o[ID_WIDTH]
```

将`buffer_queue`的对应位置直接接到`backend_instr_o`，不保证两条指令都有效，甚至可能都无效（如初始时）

要求当拍返回`backend_accept_i`信号，如果接受指令，意思即这条指令会进入下一级，如果接受，返回的接受信号必须都在低位。

下一周期接受的指令将会被重置，然后顺序移动指令，即如果接受接受指令1，拒绝指令2，下一周期指令2将变为指令1，指令2为新的指令。

后端或ctrl 输入`backend_flush_i`的下一周期将全部`buffer_queue`刷空，因为`backend_instr_o`是直接接在`buffer_queue`上的，因此下一周期也变为空。

