# 运行自定义小游戏

## 烧写bin到FPGA上面的Flash

1. 打开串口软件SecureCRT，左上角File选择quick connect，按照chiplab中的说明手册中的[`4`](https://chiplab.readthedocs.io/zh/latest/FPGA_run_linux/linux_run.html)初始化软件，其中波特率要选择230400

2. 按照chiplab说明手册中的[`5`](https://chiplab.readthedocs.io/zh/latest/FPGA_run_linux/flash.html#)，烧写Flash。打开Vivado将官方提供的 programmer_by_uart.bit烧录到FPGA上，烧录过程中串口软件不需要关闭

3. 当串口软件窗口中出现如下代码时，表示串口软件与FPGA上面的FLASH连接完毕，此时可以传送bin到Flash中
```
PMON2000 MIPS Initializing. Standby...
xmodem now
```
4. 点击`transfer->send X modem`,选择要传送的文件