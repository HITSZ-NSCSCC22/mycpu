# myCPU


## 目录结构

```
src/                    CPU Verilog 源代码
    SimTop.v            顶层Soc，用于连接核心和其他模块
    SimTop_tb.v         Vivado仿真testbench
    ram.v               用于在仿真时读取inst_rom.data
    inst_rom.data       存放内存初始内容

    vsrc/               CPU 核心部分源码
        pipeline/       流水线部分
        AXI/            AXI 控制器
        BPU/            分支预测部件
        frontend/       流水线前端，负责取指并塞入Instruction Buffer

        cpu_top.sv      CPU 内核顶层模块，目前含有ICache，Frontend，IB和流水线各级
                        同时是chiplab测试的入口，仅有AXI端口和外部中断端口

        ...             其他模块

Makefile                用于自动化测试和Verilator仿真，无需关心
README.md               本文件
testbench.cpp           用于Verilator仿真，如果使用Vivado仿真，无需关心    


```

## 设计文档

- [前端设计](doc/frontend.md)
- [译码器设计](doc/instr_decode.md)
- [差分测试](doc/difftest.md)
- [AXI控制器](src/vsrc/AXI/README.md)
- [分支预测器](src/vsrc/BPU/README.md)
- [Chiplab对接](doc/chiplab.md)
- [Instruction Buffer设计](doc/instr_buffer.md)
- [每日一个 Verilog 小技巧](doc/verilog_tips.md)

## 代码规范

[代码规范](doc/coding_conventions.md)

## 开发流程

### Clone项目

使用以下命令将项目clone到本地

```
git clone https://github.com/HITSZ-NSCSCC22/mycpu
或
git clone https://hub.fastgit.xyz/HITSZ-NSCSCC22/mycpu
```

此时项目处于main分支，请使用以下命令创建一个自己的分支
```
git checkout -b <branch_name>
```

### 修改源码

此阶段在本地使用Vivado/VSCode等工具调试，认为完成了某个功能就可以commit了

### Commit & Push

使用`git status`可以查看工作区状态，除了正常的源码意外，注意查看有无类似Vivado log或Vivado project这样的仅在本地使用的文件或目录。

如果想要排除某些文件或目录，编辑`.gitignore`文件，语法可以参考已有的条目。

使用`git add .`之类的命令添加文件以后，建议再使用`git status`查看具体添加了哪些文件，避免commit巨大的二进制文件。

接下来就可以正常commit了，你的commit message对其他人来说是了解你做的工作的重要信息，务必要认真填写。

在`git push`先要`git pull`，否则如果线上版本有更新，GitHub会拒绝你的push。

`git pull`如果出现merge冲突，无需着急，执行`git reset --hard HEAD`将状态恢复到`git pull`之前，然后在群里大喊！


## Credit

> 引用和致谢

[cva5](https://github.com/openhwgroup/cva5) 项目和 Eric Matthews

- [乘除法器](https://github.com/risclite/rv32m-multiplier-and-divider)
- [参数化的LFSR](https://github.com/openhwgroup/cva5/blob/master/core/lfsr.sv)