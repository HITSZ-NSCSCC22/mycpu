# 图片显示到LCD上面

1. 用格式工厂或是window自带的画图将图片转为BMP（24bit）格式
2. 使用正点原子的转化软件将图片转为rgb565格式的coe（16bit）
3. 设置扫描方向为3600  0000（从左到右，从上到下）
4. 设置坐标的范围，坐标的范围一定要和图片的像素完全对齐，不允许出现任何的误差，否则图片的显示会有较大的偏移。比如200 * 199的图片不能因为图方便把LCD的坐标设置为200 * 200
5. 把coe存入bram，然后正常的绘图即可

# IP核设置

gt9147_init  触摸屏初始化BRAM

+ 选择bram IP
+ Basic 选择Byte Write Enable，同时字节数选择8
+ Port A 字宽为8，深度为256，选择Primitives Output Register
+ Other Options 从peripheral initial code中导入tp.coe

char_library  字库

+ 选择bram IP
+ Basic 无需改动
+ Port A 字宽为24，深度为4096，取消Primitives Output Register
+ Other Options 从peripheral initial code中导入char_lib.coe

lcd_init  显示屏初始化和开机Logo

+ 选择bram IP
+ Basic 无需改动
+ Port A 字宽为16，深度为170000，取消Primitives Output Register
+ Other Options 从peripheral initial code中导入HIT.coe

lcd_init_bram 显示屏初始化和开机Logo

+ 选择bram IP
+ Basic 无需改动
+ Port A 字宽为16，深度为170000，取消Primitives Output Register
+ Other Options 从peripheral initial code中导入HIT.coe

lcd_clear_bram 显示屏初始化和开机Logo

+ 选择bram IP
+ Basic 无需改动
+ Port A 字宽为16，深度为1024，取消Primitives Output Register
+ Other Options 从peripheral initial code中导入lcd_clear_bram.coe

refresh1_bram 刷白屏 

+ 选择bram IP
+ Basic 无需改动
+ Port A 字宽为16，深度为32，取消Primitives Output Register
+ Other Options 从peripheral initial code中导入refresh1.coe
  
