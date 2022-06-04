# 地址翻译文档

## inst_addr_tran

还未实现

## data_addr_tran

在`mem`阶段,核心向dcache发出访问内存的请求,在同一周期内,`wb`阶段判断是否要进行地址翻译

在下一个周期,地址翻译信号传入tlb,tlb根据是否要进行翻译给出对应的tag,传入dcache

