`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/04/21 17:24:48
// Design Name: 
// Module Name: cache
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

//cache��2�飬ÿ��4k��
//V��D��Tag��Data=1+1+20+128=150


module cache(
    input wire clk,
    input wire rst,
    //cache��CPU��ˮ�ߵĽ�����
    input wire           valid,              //����������Ч
    input wire           op,                  // 1:write 0: read
    input wire           uncache,             //��־uncacheָ���λ��Ч
    input wire[7:0]      index,               // ��ַ��index��(addr[11:4])
    input wire[19:0]     tag,                 //��TLB�鵽��pfn�γɵ�tag
    input wire[3:0]      offset,              //��ַ��offset��addr[3:0]
    input wire[3:0]      wstrb,               //д�ֽ�ʹ���ź�
    input wire[31:0]     wdata,               //д����
    output reg           addr_ok,             //�ô�����ĵ�ַ����OK��������ַ�����գ�д����ַ�����ݱ����
    output reg           data_ok,             //�ô���������ݴ���Ok���������ݷ��أ�д������д�����
    output reg[31:0]     rdata,               //��Cache�Ľ��

    //cache��AXI���ߵĽ����ӿ�
    output reg         rd_req,               //��������Ч�źš��ߵ�ƽ��Ч
    output reg[3:0]    rd_type,              //���������ͣ�3'b000: �ֽڣ�3'b001: ���֣�3'b010: �֣�3'b100��Cache��
    output reg[31:0]   rd_addr,              //��������ʼ��ַ
    input wire          rd_rdy,               //�������ܷ񱻽��յ������źš��ߵ�ƽ��Ч
    input wire          ret_valid,            //����������Ч���ߵ�ƽ��Ч��
    input wire          ret_last,             //����������һ�ζ������Ӧ�����һ����������
    input wire[31:0]    ret_data,             //����������
    output reg         wr_req,               //д������Ч�źš��ߵ�ƽ��Ч
    output reg[2:0]    wr_type,              //д�������ͣ�3'b000: �ֽڣ�3'b001: ���֣�3'b010: �֣�3'b100��Cache��
    output reg[31:0]   wr_addr,              //д������ʼ��ַ
    output reg[3:0]    wr_wstrb,             //д�������ֽ����롣����д��������Ϊ��3'b000: �ֽڣ�3'b001: ���֣�3'b010���ֵ�����²�������
    output reg[127:0]  wr_data,              //д����
    input wire          wr_rdy               //д�����ܷ񱻽��ܵ������źš������p2234.
     

     //�������SRAM-AXIת����ģ����е��������ȷ��ʵ��
 );

//��״̬���������״̬��
//IDLE��Cacheģ�鵱ǰû���κβ���
//LOOKUP��Cacheģ�鵱ǰ����ִ��һ���������ҵõ������Ĳ�ѯ���
//MISS��Cacheģ�鵱ǰ����Ĳ���Cacheȱʧ�������ڵȴ�AXI���ߵ�wr_rdy�ź�
//REPLACE�����滻��Cache���Ѿ���Cache�ж����������ڵȴ�AXI���ߵ�rd_rdy�ź�
//REFILL��Cacheȱʧ�ķô������ѷ�����׼��/���ڽ�ȱʧ��Cache������д��Cache��
parameter IDLE=0;
parameter LOOKUP=1;
parameter MISS=2;
parameter REPLACE=3;
parameter REFILL=4;
parameter WRITE = 5;
//Write Buffer״̬����������״̬
//IDLE: Write Buffer״̬����ǰû�д�д������
//WRITE: ����д������д��Cache�С�����״̬������LOOKUP״̬�ҷ���Store��������Cache�ǣ�����Write Buffer״̬������Write״̬
//ͬʱWrite Buffer��Ĵ�StoreҪд���Index��·�š�offset��дʹ��(д32λ���������Щ�ֽ�)��д���ݡ�


parameter V=149;
parameter D=148;
parameter TagMSB=147;
parameter TagLSB=128;
parameter BlockMSB=127;
parameter BlockLSB=0;

reg [149:0] cache_data [0:511];
reg [2:0] state,next_state;
reg [2:0] wr_state,wr_next_state;
reg hit;
reg hit1;
reg hit2;
reg way;                               //��hit����way�����壬��miss����way��ʾ�������һ·
reg write_op;                   //hit write ִ�б�־���ߵ�ƽ��Ч
reg miss_way_r;                 //ȱʧ·��дʹ��

//���ַ��32λ��[31:12]ΪTag��[11:4]ΪCache������index, [3:0]:offset,Cache����ƫ��
wire [7:0]cpu_req_index;
wire [19:0]cpu_req_tag;
wire [3:0]cpu_req_offset;

//wire cpu_req_uncache;
wire cpu_req_valid;
wire cpu_req_op;
wire[3:0] cpu_req_wstrb;
wire[31:0] cpu_req_wdata;

wire cpu_rd_rdy;
wire cpu_wr_rdy;
wire cpu_ret_valid;
wire  cpu_ret_last;
wire[31:0] cpu_ret_data;

////���ַ��32λ��[31:12]ΪTag��[11:4]ΪCache������index, [3:0]:offset,Cache����ƫ��
//reg [7:0]cpu_req_index;
//reg [19:0]cpu_req_tag;
//reg [3:0]cpu_req_offset;

////wire cpu_req_uncache;
//reg cpu_req_valid;
//reg cpu_req_op;
//reg[3:0] cpu_req_wstrb;
//reg[31:0] cpu_req_wdata;

//reg cpu_rd_rdy;
//reg cpu_wr_rdy;
//reg cpu_ret_valid;
//reg[1:0] cpu_ret_last;
//reg[31:0] cpu_ret_data;

//hit write ��ͻ ��λ��Ч
reg hit_conflict = 0;

assign   cpu_req_valid = valid;
assign   cpu_req_op =  op;
assign   cpu_req_uncache  = uncache;
assign   cpu_req_offset  = offset;
assign   cpu_req_index  = index;
assign   cpu_req_tag   = tag;
assign   cpu_req_wstrb   = wstrb;
assign   cpu_req_wdata   = wdata;
assign   cpu_rd_rdy  = rd_rdy;
assign   cpu_wr_rdy  = wr_rdy;
assign   cpu_ret_valid  = ret_valid;
assign   cpu_ret_last  = ret_last;
assign   cpu_ret_data  = ret_data;


//��д����Cache��ִ�й���
integer i;
//��ʼ��cache
initial
begin
    for(i=0;i<512;i=i+1)
        cache_data[i]=150'd0;
end


always@(posedge clk,posedge rst)begin
    if(!rst)
        state<=IDLE;
    else
        state<=next_state;
end

//state change
always@(*)begin
    case(state)
        IDLE:if(!cpu_req_valid ||( cpu_req_valid  && hit_conflict ))
               next_state=IDLE;
             else
               next_state=LOOKUP;
        LOOKUP: if( (hit && !cpu_req_valid) || (hit && ( cpu_req_valid && hit_conflict)) )                     //��hit
                     next_state=IDLE;
                else if( hit && cpu_req_valid ) 
                    next_state=LOOKUP;
                else if(!hit)begin
                    next_state=MISS;
                    
                end
        MISS:if(cpu_wr_rdy == 0)
                next_state=MISS;
             else if(cpu_wr_rdy == 1)
                next_state=REPLACE;
        REPLACE:if(cpu_rd_rdy == 0)
                   next_state=REPLACE;
                 else
                   next_state=REFILL;
        REFILL:if(cpu_ret_valid == 1 && cpu_ret_last == 1)
                    next_state = IDLE;
                else
                    next_state = REFILL;

        default:next_state=IDLE;
    endcase
end
reg wr_buffer;
//Write BUffer state change
always@(*)begin
    case(wr_state)
        IDLE:if(hit && cpu_req_op && cpu_req_valid)begin
               wr_next_state=WRITE;
             end
             else begin
               wr_next_state=IDLE;
             end
        WRITE:  if( (hit) && (cpu_req_op) )                     //��hit
                     wr_next_state=WRITE;
                else 
                    wr_next_state=IDLE;

        default:wr_next_state=IDLE;
    endcase
end


//Tag compare
//hit1
always@(*)begin
    if(state==LOOKUP)
        if(cache_data[2*cpu_req_index][V]==1'b1&&cache_data[2*cpu_req_index][TagMSB:TagLSB]==cpu_req_tag)begin
            hit1=1'b1;
            if(cpu_req_op == 1)begin
                if( index == cpu_req_index &&  tag == cpu_req_tag)begin
                    hit_conflict = 1;
                end
            end
        end
        else
            hit1=1'b0;
    else
        hit1=1'b0;
end
//hit2
always@(*)begin
    if(state==LOOKUP)
        if(cache_data[2*cpu_req_index+1][V]==1'b1&&cache_data[2*cpu_req_index+1][TagMSB:TagLSB]==cpu_req_tag)begin
            hit2=1'b1;
            if( cpu_req_op == 1)begin
                if( index == cpu_req_index &&  tag == cpu_req_tag)begin
                    hit_conflict = 1;
                end
            end
        end
        else
            hit2=1'b0;
    else
        hit2=1'b0;
end
//hit
always@(*)begin
    if(state==LOOKUP)begin
        hit=hit1||hit2;
        if(hit && cpu_req_op)begin
            wr_state = WRITE;
        end
    end
    else
        hit=1'b0;
end


//LOOKUPģ��: Cache���к�Ķ�д����---Data Select
always@(posedge clk)begin
    if(state==LOOKUP && hit)
        if( op==1'b0)                        //read hit
        begin
             addr_ok<=1'b1;
            if(hit1)begin
                 rdata =cache_data[2*cpu_req_index][8*cpu_req_offset +:32];
            end
            else begin
                 rdata =cache_data[2*cpu_req_index+1][8*cpu_req_offset +:32];
            end
        end

        else if(wr_state==WRITE && hit)                                     //write hit
        begin
             addr_ok <= 1'b1;
             data_ok <= 1'b1;
            if(hit1) 
            begin                                
                 cache_data[2*cpu_req_index][8*cpu_req_offset +:32] = wdata;
                 cache_data[2*cpu_req_index][D] =1'b1;
            end
            else
            begin
                cache_data[2*cpu_req_index+1][8*cpu_req_offset +:32] = wdata;
                cache_data[2*cpu_req_index+1][D] = 1'b1;
            end
            if(cpu_req_op == 0)begin
                if(cpu_req_offset[3:2] ==  offset[3:2])begin
                    hit_conflict  = 1;
                end
            end
       end
end

//way      LFSB --Miss Buffer 
always@(*)begin
    if( state==MISS )begin   //δ����
        case({cache_data[2*cpu_req_index][V],cache_data[2*cpu_req_index+1][V]})
            2'b01:way=1'b0;                    //��0·����
            2'b10:way=1'b1;                    //��1·����
            2'b00:way=1'b0;                    //��0��1·������
            2'b11:way=1'b0;                    //��0��1·�������ã�Ĭ���滻��0·
            default:way=1'b0;
        endcase
        miss_way_r = 1;
    end
end

reg[1:0] rt_offset;
//��AXI�ӿڵ�д����
always @ (*)begin
		if (state == MISS)begin		// �洢Ҫд�����ݻ��е�ַ����Ϣ		     
//			if(cpu_req_op == 1)begin
//			     if(cache_data[2*cpu_req_index + way][D])begin
			         
//			     end
			     
//			end
			rd_addr = {cpu_req_tag[19:0],cpu_req_index[7:0],cpu_req_offset};
			rd_type  = 3'b000;
			addr_ok = 1'b1;
		    data_ok <= 1'b1;
		end
		else if (state == REPLACE)begin	
		      //�����滻�е�Cache����д��������
		    if(wr_rdy) begin
		         if(cache_data[2*cpu_req_index+way][V:D] == 2'b11 )begin
			          wr_req	 =	1'b1;
		              wr_addr    = {cache_data[2*cpu_req_index+way][TagMSB:TagLSB], cpu_req_index, 4'b0000};
			          wr_wstrb   =  wstrb;
			          wr_data	 =	cache_data[2*cpu_req_index+way][BlockMSB:BlockLSB];
			     end
			end
			else begin
			      wr_req =	1'b0;
			end
		    rd_req  = 1'b1;    
		end
		else begin
			wr_req	 =	1'b0;
			rd_req   =  1'b0;
        end
end
//Miss Buffer
always@(*)begin
    if(state == REFILL)begin
        if(cpu_req_op == 0)begin
            cache_data[2*cpu_req_index+way][149:128]  = {2'b10,cpu_req_tag};
            cache_data[2*cpu_req_index+way][rt_offset*32 +:32]  = ret_data;
            if(ret_last)begin
                rt_offset = 0;
                rd_req   =  1'b0;
                rdata = cache_data[2*cpu_req_index+way][cpu_req_index*8 +:32];
            end
        end
         if(cpu_req_op == 1 )begin
            cache_data[2*cpu_req_index+way][149:128]  = {2'b11,cpu_req_tag};
            cache_data[2*cpu_req_index+way][rt_offset * 8 +:32]  = ret_data;
            if(ret_last)begin
                rt_offset = 0;
                cache_data[2*cpu_req_index+way][cpu_req_index*8 +:32] = cpu_req_wdata;
            end
        end
        rt_offset = rt_offset+ 1;
    end
end

endmodule



