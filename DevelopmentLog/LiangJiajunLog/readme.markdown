# 开发日志  

***  

### 2022.3.23

1. 更改了流水线的取值阶段，新增pc2_reg模块用于实现pc和inst_o的对齐，删除了if_id模块原有的对齐延迟  

2. 实现转移指令时，使用id阶段得到的branch_flag直接对pc_regpc2_reg,if_id,ram进行清零，清除转移指令后面的无效流水级，转移过程未使ctrl  

3. ram模块新增了branch_flag接口  

4. 对SimTop和cpu_top进行重构以适应上述的修改     
  
5. 代码没有经过测试  

  
### 2022.3.28  
  
  1. 修复了jirl指令PC相对寻址的bug
   
  2. 修改了cpu_top中link_address的bug

  3. 修改了id模块中分支指令操作数1和操作数2搞反的问题，目前`reg1_address=op2,reg2_address=op1`

  4. 转移指令全部测试通过