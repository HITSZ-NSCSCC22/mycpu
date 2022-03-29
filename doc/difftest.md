# 差分测试

## 环境准备

### 依赖安装
测试框架需要的依赖：
- verilator: 仿真器，[安装说明](https://veripool.org/guide/latest/install.html)
- ccache: 编译缓存
- libsdl2-dev: 外设模拟
- sqlite3: 数据记录

在ubuntu下，可用以下命令安装
```
sudo apt-get install -y verilator ccache libsdl2-dev sqlite3 libsqlite3-dev
```

### 框架下载
在本地仓库的目录下执行
```
git clone https://github.com/HITSZ-NSCSCC22/difftest
或
git clone https://hub.fastgit.xyz/HITSZ-NSCSCC22/difftest
```

### 下载预编译的黄金模型
呃，到群里下载，然后放到当前目录

### 目录情况
最终，当前目录结构如下
```
$> tree -L 1
.
├── DevelopmentLog
├── difftest
├── doc
├── la32-nemu-interpreter-so
├── Makefile
├── README.md
├── src
├── test
└── testbench.cpp
```

### 测试用例准备
测试需要**仅含指令的二进制文件**

可以通过以下指令从可执行文件的`.text`段获得

```
loongarch32-unknown-elf-objcopy -O binary -j .text xxx.elf xxx.bin
```

然后将`xxx.bin`放入`test/`文件夹中


## 运行测试
运行以下指令开始测试
```
make run-difftest
```
因为差分测试框架没有配置好makefile的依赖项，因此如果修改了verilog源码，需要从头来过，先运行`make clean`以清除编译产生的文件
```
make clean
make run-difftest
```
未来可能可以解决这个问题

## 测试逻辑
框架会首先在`src/`产生一大堆的文件，最终运行的文件是`src/emu`

`test/test.sh`会在`test/`寻找`*.bin`的文件，然后逐个运行测试，目前指定的测试指令数是根据`.bin`文件的大小确定的，所以如果要测试转移指令等实际执行指令数量大于`.bin`文件大小的，需要手动运行测试，例如

```
	./src/emu -b 0 -e 0 -i test/xxx.bin  --diff=./la32-nemu-interpreter-so -I <instr_count>
```

将来为了支持结束测试，需要实现自陷指令