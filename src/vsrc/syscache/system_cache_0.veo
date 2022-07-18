// (c) Copyright 1995-2022 Xilinx, Inc. All rights reserved.
// 
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.
// 
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) Xilinx shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or Xilinx had been advised of the
// possibility of the same.
// 
// CRITICAL APPLICATIONS
// Xilinx products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of Xilinx products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
// 
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
// 
// DO NOT MODIFY THIS FILE.

// IP VLNV: xilinx.com:ip:system_cache:5.0
// IP Revision: 0

// The following must be inserted into your Verilog file for this
// core to be instantiated. Change the instance name and port connections
// (in parentheses) to your own signal names.

//----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
system_cache_0 your_instance_name (
  .ACLK(ACLK),                      // input wire ACLK
  .ARESETN(ARESETN),                // input wire ARESETN
  .Initializing(Initializing),      // output wire Initializing
  .S0_AXI_AWID(S0_AXI_AWID),        // input wire [0 : 0] S0_AXI_AWID
  .S0_AXI_AWADDR(S0_AXI_AWADDR),    // input wire [31 : 0] S0_AXI_AWADDR
  .S0_AXI_AWLEN(S0_AXI_AWLEN),      // input wire [7 : 0] S0_AXI_AWLEN
  .S0_AXI_AWSIZE(S0_AXI_AWSIZE),    // input wire [2 : 0] S0_AXI_AWSIZE
  .S0_AXI_AWBURST(S0_AXI_AWBURST),  // input wire [1 : 0] S0_AXI_AWBURST
  .S0_AXI_AWLOCK(S0_AXI_AWLOCK),    // input wire S0_AXI_AWLOCK
  .S0_AXI_AWCACHE(S0_AXI_AWCACHE),  // input wire [3 : 0] S0_AXI_AWCACHE
  .S0_AXI_AWPROT(S0_AXI_AWPROT),    // input wire [2 : 0] S0_AXI_AWPROT
  .S0_AXI_AWQOS(S0_AXI_AWQOS),      // input wire [3 : 0] S0_AXI_AWQOS
  .S0_AXI_AWVALID(S0_AXI_AWVALID),  // input wire S0_AXI_AWVALID
  .S0_AXI_AWREADY(S0_AXI_AWREADY),  // output wire S0_AXI_AWREADY
  .S0_AXI_AWUSER(S0_AXI_AWUSER),    // input wire [0 : 0] S0_AXI_AWUSER
  .S0_AXI_WDATA(S0_AXI_WDATA),      // input wire [127 : 0] S0_AXI_WDATA
  .S0_AXI_WSTRB(S0_AXI_WSTRB),      // input wire [15 : 0] S0_AXI_WSTRB
  .S0_AXI_WLAST(S0_AXI_WLAST),      // input wire S0_AXI_WLAST
  .S0_AXI_WVALID(S0_AXI_WVALID),    // input wire S0_AXI_WVALID
  .S0_AXI_WREADY(S0_AXI_WREADY),    // output wire S0_AXI_WREADY
  .S0_AXI_BRESP(S0_AXI_BRESP),      // output wire [1 : 0] S0_AXI_BRESP
  .S0_AXI_BID(S0_AXI_BID),          // output wire [0 : 0] S0_AXI_BID
  .S0_AXI_BVALID(S0_AXI_BVALID),    // output wire S0_AXI_BVALID
  .S0_AXI_BREADY(S0_AXI_BREADY),    // input wire S0_AXI_BREADY
  .S0_AXI_ARID(S0_AXI_ARID),        // input wire [0 : 0] S0_AXI_ARID
  .S0_AXI_ARADDR(S0_AXI_ARADDR),    // input wire [31 : 0] S0_AXI_ARADDR
  .S0_AXI_ARLEN(S0_AXI_ARLEN),      // input wire [7 : 0] S0_AXI_ARLEN
  .S0_AXI_ARSIZE(S0_AXI_ARSIZE),    // input wire [2 : 0] S0_AXI_ARSIZE
  .S0_AXI_ARBURST(S0_AXI_ARBURST),  // input wire [1 : 0] S0_AXI_ARBURST
  .S0_AXI_ARLOCK(S0_AXI_ARLOCK),    // input wire S0_AXI_ARLOCK
  .S0_AXI_ARCACHE(S0_AXI_ARCACHE),  // input wire [3 : 0] S0_AXI_ARCACHE
  .S0_AXI_ARPROT(S0_AXI_ARPROT),    // input wire [2 : 0] S0_AXI_ARPROT
  .S0_AXI_ARQOS(S0_AXI_ARQOS),      // input wire [3 : 0] S0_AXI_ARQOS
  .S0_AXI_ARVALID(S0_AXI_ARVALID),  // input wire S0_AXI_ARVALID
  .S0_AXI_ARREADY(S0_AXI_ARREADY),  // output wire S0_AXI_ARREADY
  .S0_AXI_ARUSER(S0_AXI_ARUSER),    // input wire [0 : 0] S0_AXI_ARUSER
  .S0_AXI_RID(S0_AXI_RID),          // output wire [0 : 0] S0_AXI_RID
  .S0_AXI_RDATA(S0_AXI_RDATA),      // output wire [127 : 0] S0_AXI_RDATA
  .S0_AXI_RRESP(S0_AXI_RRESP),      // output wire [1 : 0] S0_AXI_RRESP
  .S0_AXI_RLAST(S0_AXI_RLAST),      // output wire S0_AXI_RLAST
  .S0_AXI_RVALID(S0_AXI_RVALID),    // output wire S0_AXI_RVALID
  .S0_AXI_RREADY(S0_AXI_RREADY),    // input wire S0_AXI_RREADY
  .M0_AXI_AWID(M0_AXI_AWID),        // output wire [3 : 0] M0_AXI_AWID
  .M0_AXI_AWADDR(M0_AXI_AWADDR),    // output wire [31 : 0] M0_AXI_AWADDR
  .M0_AXI_AWLEN(M0_AXI_AWLEN),      // output wire [7 : 0] M0_AXI_AWLEN
  .M0_AXI_AWSIZE(M0_AXI_AWSIZE),    // output wire [2 : 0] M0_AXI_AWSIZE
  .M0_AXI_AWBURST(M0_AXI_AWBURST),  // output wire [1 : 0] M0_AXI_AWBURST
  .M0_AXI_AWLOCK(M0_AXI_AWLOCK),    // output wire M0_AXI_AWLOCK
  .M0_AXI_AWCACHE(M0_AXI_AWCACHE),  // output wire [3 : 0] M0_AXI_AWCACHE
  .M0_AXI_AWPROT(M0_AXI_AWPROT),    // output wire [2 : 0] M0_AXI_AWPROT
  .M0_AXI_AWQOS(M0_AXI_AWQOS),      // output wire [3 : 0] M0_AXI_AWQOS
  .M0_AXI_AWVALID(M0_AXI_AWVALID),  // output wire M0_AXI_AWVALID
  .M0_AXI_AWREADY(M0_AXI_AWREADY),  // input wire M0_AXI_AWREADY
  .M0_AXI_WDATA(M0_AXI_WDATA),      // output wire [127 : 0] M0_AXI_WDATA
  .M0_AXI_WSTRB(M0_AXI_WSTRB),      // output wire [15 : 0] M0_AXI_WSTRB
  .M0_AXI_WLAST(M0_AXI_WLAST),      // output wire M0_AXI_WLAST
  .M0_AXI_WVALID(M0_AXI_WVALID),    // output wire M0_AXI_WVALID
  .M0_AXI_WREADY(M0_AXI_WREADY),    // input wire M0_AXI_WREADY
  .M0_AXI_BRESP(M0_AXI_BRESP),      // input wire [1 : 0] M0_AXI_BRESP
  .M0_AXI_BID(M0_AXI_BID),          // input wire [3 : 0] M0_AXI_BID
  .M0_AXI_BVALID(M0_AXI_BVALID),    // input wire M0_AXI_BVALID
  .M0_AXI_BREADY(M0_AXI_BREADY),    // output wire M0_AXI_BREADY
  .M0_AXI_ARID(M0_AXI_ARID),        // output wire [3 : 0] M0_AXI_ARID
  .M0_AXI_ARADDR(M0_AXI_ARADDR),    // output wire [31 : 0] M0_AXI_ARADDR
  .M0_AXI_ARLEN(M0_AXI_ARLEN),      // output wire [7 : 0] M0_AXI_ARLEN
  .M0_AXI_ARSIZE(M0_AXI_ARSIZE),    // output wire [2 : 0] M0_AXI_ARSIZE
  .M0_AXI_ARBURST(M0_AXI_ARBURST),  // output wire [1 : 0] M0_AXI_ARBURST
  .M0_AXI_ARLOCK(M0_AXI_ARLOCK),    // output wire M0_AXI_ARLOCK
  .M0_AXI_ARCACHE(M0_AXI_ARCACHE),  // output wire [3 : 0] M0_AXI_ARCACHE
  .M0_AXI_ARPROT(M0_AXI_ARPROT),    // output wire [2 : 0] M0_AXI_ARPROT
  .M0_AXI_ARQOS(M0_AXI_ARQOS),      // output wire [3 : 0] M0_AXI_ARQOS
  .M0_AXI_ARVALID(M0_AXI_ARVALID),  // output wire M0_AXI_ARVALID
  .M0_AXI_ARREADY(M0_AXI_ARREADY),  // input wire M0_AXI_ARREADY
  .M0_AXI_RID(M0_AXI_RID),          // input wire [3 : 0] M0_AXI_RID
  .M0_AXI_RDATA(M0_AXI_RDATA),      // input wire [127 : 0] M0_AXI_RDATA
  .M0_AXI_RRESP(M0_AXI_RRESP),      // input wire [1 : 0] M0_AXI_RRESP
  .M0_AXI_RLAST(M0_AXI_RLAST),      // input wire M0_AXI_RLAST
  .M0_AXI_RVALID(M0_AXI_RVALID),    // input wire M0_AXI_RVALID
  .M0_AXI_RREADY(M0_AXI_RREADY)    // output wire M0_AXI_RREADY
);
// INST_TAG_END ------ End INSTANTIATION Template ---------

// You must compile the wrapper file system_cache_0.v when simulating
// the core, system_cache_0. When compiling the wrapper file, be sure to
// reference the Verilog simulation library.

