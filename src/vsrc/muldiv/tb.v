/////////////////////////////////////////////////////////////////////////////////////
//
//Copyright 2020  Li Xinbing
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
//
/////////////////////////////////////////////////////////////////////////////////////

//`include "define.v"

`define N(n)        [(n)-1:0]
`define FFx(signal,bits)           always @ ( posedge clk or posedge  rst ) if (   rst   )  signal <= bits;  else

`define XLEN                   32

`define PERIOD 10
`define DEL     2

module tb;

    reg clk = 0;
    always clk = #(`PERIOD/2) ~clk;
    
    reg rst = 1'b1;
    initial #(`PERIOD) rst = 1'b0;
	

//-------------------------------------------------------------------------------
// To generate test data
//-------------------------------------------------------------------------------
	
	localparam NUM = 10000;
	
	reg `N(3)        para `N(NUM);
	reg `N(`XLEN)    dividend `N(NUM), divisor `N(NUM), result `N(NUM);

    //the mul/div function
	function `N(`XLEN) riscv_muldiv (input `N(3) para, input `N(`XLEN) rs0,rs1 );
	reg `N(`XLEN*2) md_out;
	begin
	    case(para)
	    3'h0 : md_out =    $signed(rs0) *   $signed(rs1);
	    3'h1 : md_out = (  $signed(rs0) *   $signed(rs1))>>`XLEN;
	    3'h2 : md_out =      signed_mul_unsigned(rs0,rs1)>>`XLEN;//(  $signed(rs0) * $unsigned(rs1))>>32;
	    3'h3 : md_out = ($unsigned(rs0) * $unsigned(rs1))>>`XLEN;
	    3'h4 : md_out =    $signed(rs0) /   $signed(rs1);
	    3'h5 : md_out =  $unsigned(rs0) / $unsigned(rs1);
	    3'h6 : md_out =    $signed(rs0) %   $signed(rs1);
	    3'h7 : md_out =  $unsigned(rs0) % $unsigned(rs1);
	    endcase	
		riscv_muldiv  = md_out;
	end
	endfunction
	
	function `N(`XLEN*2) signed_mul_unsigned(input `N(`XLEN) rs0,rs1);
	reg `N(`XLEN) x,y;
	reg `N(`XLEN*2) z;
	reg           m;
	begin
	    m = rs0>>(`XLEN-1);
		x = m ? ( ~rs0 + 1) : rs0;
	    y = rs1;
		z = x * y;
	    signed_mul_unsigned = m ? ( ~z + 1'b1 ) : z;
	end
	endfunction
	
	
	initial begin:init_gen_data
	    integer i;
		for (i=0;i<NUM;i=i+1) begin
		    para[i]     = $random;
			dividend[i] = $random;
			divisor[i]  = $random;
			result[i]   = riscv_muldiv(para[i],dividend[i],divisor[i]);
		end
	end
	
//-------------------------------------------------------------------------------
// To instantiate DUT
//-------------------------------------------------------------------------------	
	reg              clear_pipeline = 1'b0;

	reg              mul_initial = 1'b0;
	reg `N(3)        mul_para = 0;
	reg `N(`XLEN)    mul_rs0 = 0;
	reg `N(`XLEN)    mul_rs1 = 0;
	wire             mul_ready;
	
    wire             mul_finished;
	wire `N(`XLEN)   mul_data;
	reg              mul_ack = 1'b0;
	
	
	
        mul  dut(
	    .clk                        (    clk                      ),
	    .rst                        (    rst                      ),

	    .clear_pipeline             (    clear_pipeline           ),	 
	 
	    .mul_initial                (    mul_initial              ),
	    .mul_para                   (    mul_para                 ),
	    .mul_rs0                    (    mul_rs0                  ),
	    .mul_rs1                    (    mul_rs1                  ),
	    .mul_ready                  (    mul_ready                ),
	    
	    .mul_finished               (    mul_finished             ),
	    .mul_data                   (    mul_data                 ),
	    .mul_ack                    (    mul_ack                  )
	    
        );		
	
//-------------------------------------------------------------------------------
// To place stimulus
//-------------------------------------------------------------------------------		
	
    initial begin:init_place
        integer i;
		@( negedge rst );
		repeat (100) @ ( posedge clk);
		for (i=0;i<NUM;i=i+1) 
            place_stimulus(para[i],dividend[i],divisor[i]);
    end	
	
	task after_one_cycle;
	begin
	    @(posedge clk);
		#`DEL ;
	end
	endtask

    task place_stimulus(input `N(3) para, input `N(`XLEN) rs0,rs1);
	begin

		while( mul_ready==1'b0 ) after_one_cycle;
		mul_initial = 1'b1;
		mul_para    = para;
		mul_rs0     = rs0;
		mul_rs1     = rs1;
        after_one_cycle;
		mul_initial = 1'b0;		
	end
    endtask

	
//-------------------------------------------------------------------------------
// To collect response
//-------------------------------------------------------------------------------		

    task delay_random;
	reg `N(4) delay_num;
	begin
	    delay_num = $random;
		repeat(delay_num) @(posedge clk);
	end
	endtask

	reg `N(`XLEN)  response `N(NUM);

	initial begin:init_collect
	    integer i;
	    reg `N(`XLEN) resp;
		@( negedge rst );
        delay_random;
        for (i=0;i<NUM;i=i+1) begin
		    collect_response(resp);
			response[i] = resp;
			if ( response[i]!=result[i] ) begin
			    $display($time," ns --%d--: %8h != %8h, %1h %8h %8h ",i,response[i],result[i],para[i],dividend[i],divisor[i]);
				$stop(1);
			end
			delay_random;
		end
		$display($time," ns %d cases Verified OK",NUM);
		$stop(1);
	end
	
	
	task collect_response(output `N(`XLEN) n);
	begin
		while( mul_finished==1'b0) after_one_cycle;
		n = mul_data;
		mul_ack = 1'b1;
	    after_one_cycle;
		mul_ack  = 1'b0;		
	end
	endtask
	


endmodule


