// Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2019.2 (win64) Build 2708876 Wed Nov  6 21:40:23 MST 2019
// Date        : Mon Jul 18 18:56:31 2022
// Host        : DESKTOP-ORKPELR running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               c:/Users/Lenovo/Desktop/UltraMIPS_SOC/run_vivado/mycpu_prj1/mycpu.srcs/sources_1/ip/system_cache_0_2/system_cache_0_stub.v
// Design      : system_cache_0
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a200tfbg676-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "system_cache,Vivado 2019.2" *)
module system_cache_0(ACLK, ARESETN, Initializing, S0_AXI_AWID, 
  S0_AXI_AWADDR, S0_AXI_AWLEN, S0_AXI_AWSIZE, S0_AXI_AWBURST, S0_AXI_AWLOCK, S0_AXI_AWCACHE, 
  S0_AXI_AWPROT, S0_AXI_AWQOS, S0_AXI_AWVALID, S0_AXI_AWREADY, S0_AXI_AWUSER, S0_AXI_WDATA, 
  S0_AXI_WSTRB, S0_AXI_WLAST, S0_AXI_WVALID, S0_AXI_WREADY, S0_AXI_BRESP, S0_AXI_BID, 
  S0_AXI_BVALID, S0_AXI_BREADY, S0_AXI_ARID, S0_AXI_ARADDR, S0_AXI_ARLEN, S0_AXI_ARSIZE, 
  S0_AXI_ARBURST, S0_AXI_ARLOCK, S0_AXI_ARCACHE, S0_AXI_ARPROT, S0_AXI_ARQOS, S0_AXI_ARVALID, 
  S0_AXI_ARREADY, S0_AXI_ARUSER, S0_AXI_RID, S0_AXI_RDATA, S0_AXI_RRESP, S0_AXI_RLAST, 
  S0_AXI_RVALID, S0_AXI_RREADY, M0_AXI_AWID, M0_AXI_AWADDR, M0_AXI_AWLEN, M0_AXI_AWSIZE, 
  M0_AXI_AWBURST, M0_AXI_AWLOCK, M0_AXI_AWCACHE, M0_AXI_AWPROT, M0_AXI_AWQOS, M0_AXI_AWVALID, 
  M0_AXI_AWREADY, M0_AXI_WDATA, M0_AXI_WSTRB, M0_AXI_WLAST, M0_AXI_WVALID, M0_AXI_WREADY, 
  M0_AXI_BRESP, M0_AXI_BID, M0_AXI_BVALID, M0_AXI_BREADY, M0_AXI_ARID, M0_AXI_ARADDR, 
  M0_AXI_ARLEN, M0_AXI_ARSIZE, M0_AXI_ARBURST, M0_AXI_ARLOCK, M0_AXI_ARCACHE, M0_AXI_ARPROT, 
  M0_AXI_ARQOS, M0_AXI_ARVALID, M0_AXI_ARREADY, M0_AXI_RID, M0_AXI_RDATA, M0_AXI_RRESP, 
  M0_AXI_RLAST, M0_AXI_RVALID, M0_AXI_RREADY)
/* synthesis syn_black_box black_box_pad_pin="ACLK,ARESETN,Initializing,S0_AXI_AWID[0:0],S0_AXI_AWADDR[31:0],S0_AXI_AWLEN[7:0],S0_AXI_AWSIZE[2:0],S0_AXI_AWBURST[1:0],S0_AXI_AWLOCK,S0_AXI_AWCACHE[3:0],S0_AXI_AWPROT[2:0],S0_AXI_AWQOS[3:0],S0_AXI_AWVALID,S0_AXI_AWREADY,S0_AXI_AWUSER[0:0],S0_AXI_WDATA[127:0],S0_AXI_WSTRB[15:0],S0_AXI_WLAST,S0_AXI_WVALID,S0_AXI_WREADY,S0_AXI_BRESP[1:0],S0_AXI_BID[0:0],S0_AXI_BVALID,S0_AXI_BREADY,S0_AXI_ARID[0:0],S0_AXI_ARADDR[31:0],S0_AXI_ARLEN[7:0],S0_AXI_ARSIZE[2:0],S0_AXI_ARBURST[1:0],S0_AXI_ARLOCK,S0_AXI_ARCACHE[3:0],S0_AXI_ARPROT[2:0],S0_AXI_ARQOS[3:0],S0_AXI_ARVALID,S0_AXI_ARREADY,S0_AXI_ARUSER[0:0],S0_AXI_RID[0:0],S0_AXI_RDATA[127:0],S0_AXI_RRESP[1:0],S0_AXI_RLAST,S0_AXI_RVALID,S0_AXI_RREADY,M0_AXI_AWID[3:0],M0_AXI_AWADDR[31:0],M0_AXI_AWLEN[7:0],M0_AXI_AWSIZE[2:0],M0_AXI_AWBURST[1:0],M0_AXI_AWLOCK,M0_AXI_AWCACHE[3:0],M0_AXI_AWPROT[2:0],M0_AXI_AWQOS[3:0],M0_AXI_AWVALID,M0_AXI_AWREADY,M0_AXI_WDATA[127:0],M0_AXI_WSTRB[15:0],M0_AXI_WLAST,M0_AXI_WVALID,M0_AXI_WREADY,M0_AXI_BRESP[1:0],M0_AXI_BID[3:0],M0_AXI_BVALID,M0_AXI_BREADY,M0_AXI_ARID[3:0],M0_AXI_ARADDR[31:0],M0_AXI_ARLEN[7:0],M0_AXI_ARSIZE[2:0],M0_AXI_ARBURST[1:0],M0_AXI_ARLOCK,M0_AXI_ARCACHE[3:0],M0_AXI_ARPROT[2:0],M0_AXI_ARQOS[3:0],M0_AXI_ARVALID,M0_AXI_ARREADY,M0_AXI_RID[3:0],M0_AXI_RDATA[127:0],M0_AXI_RRESP[1:0],M0_AXI_RLAST,M0_AXI_RVALID,M0_AXI_RREADY" */;
  input ACLK;
  input ARESETN;
  output Initializing;
  input [0:0]S0_AXI_AWID;
  input [31:0]S0_AXI_AWADDR;
  input [7:0]S0_AXI_AWLEN;
  input [2:0]S0_AXI_AWSIZE;
  input [1:0]S0_AXI_AWBURST;
  input S0_AXI_AWLOCK;
  input [3:0]S0_AXI_AWCACHE;
  input [2:0]S0_AXI_AWPROT;
  input [3:0]S0_AXI_AWQOS;
  input S0_AXI_AWVALID;
  output S0_AXI_AWREADY;
  input [0:0]S0_AXI_AWUSER;
  input [127:0]S0_AXI_WDATA;
  input [15:0]S0_AXI_WSTRB;
  input S0_AXI_WLAST;
  input S0_AXI_WVALID;
  output S0_AXI_WREADY;
  output [1:0]S0_AXI_BRESP;
  output [0:0]S0_AXI_BID;
  output S0_AXI_BVALID;
  input S0_AXI_BREADY;
  input [0:0]S0_AXI_ARID;
  input [31:0]S0_AXI_ARADDR;
  input [7:0]S0_AXI_ARLEN;
  input [2:0]S0_AXI_ARSIZE;
  input [1:0]S0_AXI_ARBURST;
  input S0_AXI_ARLOCK;
  input [3:0]S0_AXI_ARCACHE;
  input [2:0]S0_AXI_ARPROT;
  input [3:0]S0_AXI_ARQOS;
  input S0_AXI_ARVALID;
  output S0_AXI_ARREADY;
  input [0:0]S0_AXI_ARUSER;
  output [0:0]S0_AXI_RID;
  output [127:0]S0_AXI_RDATA;
  output [1:0]S0_AXI_RRESP;
  output S0_AXI_RLAST;
  output S0_AXI_RVALID;
  input S0_AXI_RREADY;
  output [3:0]M0_AXI_AWID;
  output [31:0]M0_AXI_AWADDR;
  output [7:0]M0_AXI_AWLEN;
  output [2:0]M0_AXI_AWSIZE;
  output [1:0]M0_AXI_AWBURST;
  output M0_AXI_AWLOCK;
  output [3:0]M0_AXI_AWCACHE;
  output [2:0]M0_AXI_AWPROT;
  output [3:0]M0_AXI_AWQOS;
  output M0_AXI_AWVALID;
  input M0_AXI_AWREADY;
  output [127:0]M0_AXI_WDATA;
  output [15:0]M0_AXI_WSTRB;
  output M0_AXI_WLAST;
  output M0_AXI_WVALID;
  input M0_AXI_WREADY;
  input [1:0]M0_AXI_BRESP;
  input [3:0]M0_AXI_BID;
  input M0_AXI_BVALID;
  output M0_AXI_BREADY;
  output [3:0]M0_AXI_ARID;
  output [31:0]M0_AXI_ARADDR;
  output [7:0]M0_AXI_ARLEN;
  output [2:0]M0_AXI_ARSIZE;
  output [1:0]M0_AXI_ARBURST;
  output M0_AXI_ARLOCK;
  output [3:0]M0_AXI_ARCACHE;
  output [2:0]M0_AXI_ARPROT;
  output [3:0]M0_AXI_ARQOS;
  output M0_AXI_ARVALID;
  input M0_AXI_ARREADY;
  input [3:0]M0_AXI_RID;
  input [127:0]M0_AXI_RDATA;
  input [1:0]M0_AXI_RRESP;
  input M0_AXI_RLAST;
  input M0_AXI_RVALID;
  output M0_AXI_RREADY;
endmodule
