# 代码规范

## 缩进

统一使用 VS Code 插件 `bmpenuelas.systemverilog-formatter-vscode` 对代码进行自动格式化

注意使用`--indentation_spaces 4`

还应将`.v`文件关联到`SystemVerilog`以获得自动格式化，具体方法是点击VS Code右下角的`Verilog`，然后在弹出的窗口选择`Configure File Association for '.v'`

## 模块(module)

### 模块命名

使用蛇形命名，形如`aaa_bbb_ccc`

### 模块端口命名

一般来讲分为三个部分，每个部分之间通过下划线连接：
- 连接到的模块简称，如`icache`
- 信号线的含义，如`data`
- 信号的方向，`o`或`i`

全部连起来如`icache_data_o`

### 模块端口类型(SystemVerilog)

如果使用了SystemVerilog，那么尽量把意义相近的信号打包成struct，定义在头文件中，然后作为端口的类型

## 信号

### 信号命名

使用蛇形命名，在模块内部，不添加后缀`o`或`i`

### 状态机(SystemVerilog)

如果使用SystemVerilog，那么状态机的状态要求使用`enum`

如：
```verilog
    enum int unsigned {
        ACCEPT_ADDR = 0,
        IN_TRANSACTION_1 = 1,
        IN_TRANSACTION_2 = 2
    }
```

### 模块间连线信号命名

约定实例化的模块间连接用的信号使用以下三部分命名：
- 起始模块名
- 到达模块名
- 信号含义

例如`frontend_icache_addr`

如果有多输出的信号，使用`multi`代替到达模块名

例如`ctrl_multi_stall`

注意无需`o`或`i`

