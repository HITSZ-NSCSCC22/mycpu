# Cache不同的情况

## valid 无效，读请求

直接进入rreq状态等待，直到取回数据

## valid 无效，写请求

直接写入cacheline,并标记脏位

## valid 有效，tag不同，读请求，无脏位

直接进入rreq状态等待，直到取回数据

## valid 有效，tag不同，读请求，有脏位

把对应的cacheline放入fifo,然后进入rreq状态等待，直到取回数据

## valid 有效，tag相同，读请求，无脏位

直接返回，不暂停
