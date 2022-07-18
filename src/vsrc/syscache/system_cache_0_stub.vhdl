-- Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2019.2 (win64) Build 2708876 Wed Nov  6 21:40:23 MST 2019
-- Date        : Mon Jul 18 18:56:31 2022
-- Host        : DESKTOP-ORKPELR running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub
--               c:/Users/Lenovo/Desktop/UltraMIPS_SOC/run_vivado/mycpu_prj1/mycpu.srcs/sources_1/ip/system_cache_0_2/system_cache_0_stub.vhdl
-- Design      : system_cache_0
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7a200tfbg676-2
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity system_cache_0 is
  Port ( 
    ACLK : in STD_LOGIC;
    ARESETN : in STD_LOGIC;
    Initializing : out STD_LOGIC;
    S0_AXI_AWID : in STD_LOGIC_VECTOR ( 0 to 0 );
    S0_AXI_AWADDR : in STD_LOGIC_VECTOR ( 31 downto 0 );
    S0_AXI_AWLEN : in STD_LOGIC_VECTOR ( 7 downto 0 );
    S0_AXI_AWSIZE : in STD_LOGIC_VECTOR ( 2 downto 0 );
    S0_AXI_AWBURST : in STD_LOGIC_VECTOR ( 1 downto 0 );
    S0_AXI_AWLOCK : in STD_LOGIC;
    S0_AXI_AWCACHE : in STD_LOGIC_VECTOR ( 3 downto 0 );
    S0_AXI_AWPROT : in STD_LOGIC_VECTOR ( 2 downto 0 );
    S0_AXI_AWQOS : in STD_LOGIC_VECTOR ( 3 downto 0 );
    S0_AXI_AWVALID : in STD_LOGIC;
    S0_AXI_AWREADY : out STD_LOGIC;
    S0_AXI_AWUSER : in STD_LOGIC_VECTOR ( 0 to 0 );
    S0_AXI_WDATA : in STD_LOGIC_VECTOR ( 127 downto 0 );
    S0_AXI_WSTRB : in STD_LOGIC_VECTOR ( 15 downto 0 );
    S0_AXI_WLAST : in STD_LOGIC;
    S0_AXI_WVALID : in STD_LOGIC;
    S0_AXI_WREADY : out STD_LOGIC;
    S0_AXI_BRESP : out STD_LOGIC_VECTOR ( 1 downto 0 );
    S0_AXI_BID : out STD_LOGIC_VECTOR ( 0 to 0 );
    S0_AXI_BVALID : out STD_LOGIC;
    S0_AXI_BREADY : in STD_LOGIC;
    S0_AXI_ARID : in STD_LOGIC_VECTOR ( 0 to 0 );
    S0_AXI_ARADDR : in STD_LOGIC_VECTOR ( 31 downto 0 );
    S0_AXI_ARLEN : in STD_LOGIC_VECTOR ( 7 downto 0 );
    S0_AXI_ARSIZE : in STD_LOGIC_VECTOR ( 2 downto 0 );
    S0_AXI_ARBURST : in STD_LOGIC_VECTOR ( 1 downto 0 );
    S0_AXI_ARLOCK : in STD_LOGIC;
    S0_AXI_ARCACHE : in STD_LOGIC_VECTOR ( 3 downto 0 );
    S0_AXI_ARPROT : in STD_LOGIC_VECTOR ( 2 downto 0 );
    S0_AXI_ARQOS : in STD_LOGIC_VECTOR ( 3 downto 0 );
    S0_AXI_ARVALID : in STD_LOGIC;
    S0_AXI_ARREADY : out STD_LOGIC;
    S0_AXI_ARUSER : in STD_LOGIC_VECTOR ( 0 to 0 );
    S0_AXI_RID : out STD_LOGIC_VECTOR ( 0 to 0 );
    S0_AXI_RDATA : out STD_LOGIC_VECTOR ( 127 downto 0 );
    S0_AXI_RRESP : out STD_LOGIC_VECTOR ( 1 downto 0 );
    S0_AXI_RLAST : out STD_LOGIC;
    S0_AXI_RVALID : out STD_LOGIC;
    S0_AXI_RREADY : in STD_LOGIC;
    M0_AXI_AWID : out STD_LOGIC_VECTOR ( 3 downto 0 );
    M0_AXI_AWADDR : out STD_LOGIC_VECTOR ( 31 downto 0 );
    M0_AXI_AWLEN : out STD_LOGIC_VECTOR ( 7 downto 0 );
    M0_AXI_AWSIZE : out STD_LOGIC_VECTOR ( 2 downto 0 );
    M0_AXI_AWBURST : out STD_LOGIC_VECTOR ( 1 downto 0 );
    M0_AXI_AWLOCK : out STD_LOGIC;
    M0_AXI_AWCACHE : out STD_LOGIC_VECTOR ( 3 downto 0 );
    M0_AXI_AWPROT : out STD_LOGIC_VECTOR ( 2 downto 0 );
    M0_AXI_AWQOS : out STD_LOGIC_VECTOR ( 3 downto 0 );
    M0_AXI_AWVALID : out STD_LOGIC;
    M0_AXI_AWREADY : in STD_LOGIC;
    M0_AXI_WDATA : out STD_LOGIC_VECTOR ( 127 downto 0 );
    M0_AXI_WSTRB : out STD_LOGIC_VECTOR ( 15 downto 0 );
    M0_AXI_WLAST : out STD_LOGIC;
    M0_AXI_WVALID : out STD_LOGIC;
    M0_AXI_WREADY : in STD_LOGIC;
    M0_AXI_BRESP : in STD_LOGIC_VECTOR ( 1 downto 0 );
    M0_AXI_BID : in STD_LOGIC_VECTOR ( 3 downto 0 );
    M0_AXI_BVALID : in STD_LOGIC;
    M0_AXI_BREADY : out STD_LOGIC;
    M0_AXI_ARID : out STD_LOGIC_VECTOR ( 3 downto 0 );
    M0_AXI_ARADDR : out STD_LOGIC_VECTOR ( 31 downto 0 );
    M0_AXI_ARLEN : out STD_LOGIC_VECTOR ( 7 downto 0 );
    M0_AXI_ARSIZE : out STD_LOGIC_VECTOR ( 2 downto 0 );
    M0_AXI_ARBURST : out STD_LOGIC_VECTOR ( 1 downto 0 );
    M0_AXI_ARLOCK : out STD_LOGIC;
    M0_AXI_ARCACHE : out STD_LOGIC_VECTOR ( 3 downto 0 );
    M0_AXI_ARPROT : out STD_LOGIC_VECTOR ( 2 downto 0 );
    M0_AXI_ARQOS : out STD_LOGIC_VECTOR ( 3 downto 0 );
    M0_AXI_ARVALID : out STD_LOGIC;
    M0_AXI_ARREADY : in STD_LOGIC;
    M0_AXI_RID : in STD_LOGIC_VECTOR ( 3 downto 0 );
    M0_AXI_RDATA : in STD_LOGIC_VECTOR ( 127 downto 0 );
    M0_AXI_RRESP : in STD_LOGIC_VECTOR ( 1 downto 0 );
    M0_AXI_RLAST : in STD_LOGIC;
    M0_AXI_RVALID : in STD_LOGIC;
    M0_AXI_RREADY : out STD_LOGIC
  );

end system_cache_0;

architecture stub of system_cache_0 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "ACLK,ARESETN,Initializing,S0_AXI_AWID[0:0],S0_AXI_AWADDR[31:0],S0_AXI_AWLEN[7:0],S0_AXI_AWSIZE[2:0],S0_AXI_AWBURST[1:0],S0_AXI_AWLOCK,S0_AXI_AWCACHE[3:0],S0_AXI_AWPROT[2:0],S0_AXI_AWQOS[3:0],S0_AXI_AWVALID,S0_AXI_AWREADY,S0_AXI_AWUSER[0:0],S0_AXI_WDATA[127:0],S0_AXI_WSTRB[15:0],S0_AXI_WLAST,S0_AXI_WVALID,S0_AXI_WREADY,S0_AXI_BRESP[1:0],S0_AXI_BID[0:0],S0_AXI_BVALID,S0_AXI_BREADY,S0_AXI_ARID[0:0],S0_AXI_ARADDR[31:0],S0_AXI_ARLEN[7:0],S0_AXI_ARSIZE[2:0],S0_AXI_ARBURST[1:0],S0_AXI_ARLOCK,S0_AXI_ARCACHE[3:0],S0_AXI_ARPROT[2:0],S0_AXI_ARQOS[3:0],S0_AXI_ARVALID,S0_AXI_ARREADY,S0_AXI_ARUSER[0:0],S0_AXI_RID[0:0],S0_AXI_RDATA[127:0],S0_AXI_RRESP[1:0],S0_AXI_RLAST,S0_AXI_RVALID,S0_AXI_RREADY,M0_AXI_AWID[3:0],M0_AXI_AWADDR[31:0],M0_AXI_AWLEN[7:0],M0_AXI_AWSIZE[2:0],M0_AXI_AWBURST[1:0],M0_AXI_AWLOCK,M0_AXI_AWCACHE[3:0],M0_AXI_AWPROT[2:0],M0_AXI_AWQOS[3:0],M0_AXI_AWVALID,M0_AXI_AWREADY,M0_AXI_WDATA[127:0],M0_AXI_WSTRB[15:0],M0_AXI_WLAST,M0_AXI_WVALID,M0_AXI_WREADY,M0_AXI_BRESP[1:0],M0_AXI_BID[3:0],M0_AXI_BVALID,M0_AXI_BREADY,M0_AXI_ARID[3:0],M0_AXI_ARADDR[31:0],M0_AXI_ARLEN[7:0],M0_AXI_ARSIZE[2:0],M0_AXI_ARBURST[1:0],M0_AXI_ARLOCK,M0_AXI_ARCACHE[3:0],M0_AXI_ARPROT[2:0],M0_AXI_ARQOS[3:0],M0_AXI_ARVALID,M0_AXI_ARREADY,M0_AXI_RID[3:0],M0_AXI_RDATA[127:0],M0_AXI_RRESP[1:0],M0_AXI_RLAST,M0_AXI_RVALID,M0_AXI_RREADY";
attribute x_core_info : string;
attribute x_core_info of stub : architecture is "system_cache,Vivado 2019.2";
begin
end;
