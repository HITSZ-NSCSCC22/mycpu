# 回滚方式

## map_table

map_table有两个映射表，对目的寄存器的映射会在rename阶段和commit阶段分别写
rename_table和commit_table，要回滚的时候就把commit的值赋给rename

## free_list

直接清空
