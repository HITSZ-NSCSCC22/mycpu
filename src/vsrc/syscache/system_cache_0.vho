-- (c) Copyright 1995-2022 Xilinx, Inc. All rights reserved.
-- 
-- This file contains confidential and proprietary information
-- of Xilinx, Inc. and is protected under U.S. and
-- international copyright and other intellectual property
-- laws.
-- 
-- DISCLAIMER
-- This disclaimer is not a license and does not grant any
-- rights to the materials distributed herewith. Except as
-- otherwise provided in a valid license issued to you by
-- Xilinx, and to the maximum extent permitted by applicable
-- law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
-- WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
-- AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
-- BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
-- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
-- (2) Xilinx shall not be liable (whether in contract or tort,
-- including negligence, or under any other theory of
-- liability) for any loss or damage of any kind or nature
-- related to, arising under or in connection with these
-- materials, including for any direct, or any indirect,
-- special, incidental, or consequential loss or damage
-- (including loss of data, profits, goodwill, or any type of
-- loss or damage suffered as a result of any action brought
-- by a third party) even if such damage or loss was
-- reasonably foreseeable or Xilinx had been advised of the
-- possibility of the same.
-- 
-- CRITICAL APPLICATIONS
-- Xilinx products are not designed or intended to be fail-
-- safe, or for use in any application requiring fail-safe
-- performance, such as life-support or safety devices or
-- systems, Class III medical devices, nuclear facilities,
-- applications related to the deployment of airbags, or any
-- other applications that could lead to death, personal
-- injury, or severe property or environmental damage
-- (individually and collectively, "Critical
-- Applications"). Customer assumes the sole risk and
-- liability of any use of Xilinx products in Critical
-- Applications, subject only to applicable laws and
-- regulations governing limitations on product liability.
-- 
-- THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
-- PART OF THIS FILE AT ALL TIMES.
-- 
-- DO NOT MODIFY THIS FILE.

-- IP VLNV: xilinx.com:ip:system_cache:5.0
-- IP Revision: 0

-- The following code must appear in the VHDL architecture header.

------------- Begin Cut here for COMPONENT Declaration ------ COMP_TAG
COMPONENT system_cache_0
  PORT (
    ACLK : IN STD_LOGIC;
    ARESETN : IN STD_LOGIC;
    Initializing : OUT STD_LOGIC;
    S0_AXI_AWID : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    S0_AXI_AWADDR : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    S0_AXI_AWLEN : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    S0_AXI_AWSIZE : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    S0_AXI_AWBURST : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    S0_AXI_AWLOCK : IN STD_LOGIC;
    S0_AXI_AWCACHE : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    S0_AXI_AWPROT : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    S0_AXI_AWQOS : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    S0_AXI_AWVALID : IN STD_LOGIC;
    S0_AXI_AWREADY : OUT STD_LOGIC;
    S0_AXI_AWUSER : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    S0_AXI_WDATA : IN STD_LOGIC_VECTOR(127 DOWNTO 0);
    S0_AXI_WSTRB : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    S0_AXI_WLAST : IN STD_LOGIC;
    S0_AXI_WVALID : IN STD_LOGIC;
    S0_AXI_WREADY : OUT STD_LOGIC;
    S0_AXI_BRESP : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    S0_AXI_BID : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
    S0_AXI_BVALID : OUT STD_LOGIC;
    S0_AXI_BREADY : IN STD_LOGIC;
    S0_AXI_ARID : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    S0_AXI_ARADDR : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    S0_AXI_ARLEN : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    S0_AXI_ARSIZE : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    S0_AXI_ARBURST : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    S0_AXI_ARLOCK : IN STD_LOGIC;
    S0_AXI_ARCACHE : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    S0_AXI_ARPROT : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    S0_AXI_ARQOS : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    S0_AXI_ARVALID : IN STD_LOGIC;
    S0_AXI_ARREADY : OUT STD_LOGIC;
    S0_AXI_ARUSER : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    S0_AXI_RID : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
    S0_AXI_RDATA : OUT STD_LOGIC_VECTOR(127 DOWNTO 0);
    S0_AXI_RRESP : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    S0_AXI_RLAST : OUT STD_LOGIC;
    S0_AXI_RVALID : OUT STD_LOGIC;
    S0_AXI_RREADY : IN STD_LOGIC;
    M0_AXI_AWID : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    M0_AXI_AWADDR : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    M0_AXI_AWLEN : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    M0_AXI_AWSIZE : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    M0_AXI_AWBURST : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    M0_AXI_AWLOCK : OUT STD_LOGIC;
    M0_AXI_AWCACHE : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    M0_AXI_AWPROT : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    M0_AXI_AWQOS : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    M0_AXI_AWVALID : OUT STD_LOGIC;
    M0_AXI_AWREADY : IN STD_LOGIC;
    M0_AXI_WDATA : OUT STD_LOGIC_VECTOR(127 DOWNTO 0);
    M0_AXI_WSTRB : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    M0_AXI_WLAST : OUT STD_LOGIC;
    M0_AXI_WVALID : OUT STD_LOGIC;
    M0_AXI_WREADY : IN STD_LOGIC;
    M0_AXI_BRESP : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    M0_AXI_BID : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    M0_AXI_BVALID : IN STD_LOGIC;
    M0_AXI_BREADY : OUT STD_LOGIC;
    M0_AXI_ARID : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    M0_AXI_ARADDR : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    M0_AXI_ARLEN : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    M0_AXI_ARSIZE : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    M0_AXI_ARBURST : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    M0_AXI_ARLOCK : OUT STD_LOGIC;
    M0_AXI_ARCACHE : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    M0_AXI_ARPROT : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    M0_AXI_ARQOS : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    M0_AXI_ARVALID : OUT STD_LOGIC;
    M0_AXI_ARREADY : IN STD_LOGIC;
    M0_AXI_RID : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    M0_AXI_RDATA : IN STD_LOGIC_VECTOR(127 DOWNTO 0);
    M0_AXI_RRESP : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    M0_AXI_RLAST : IN STD_LOGIC;
    M0_AXI_RVALID : IN STD_LOGIC;
    M0_AXI_RREADY : OUT STD_LOGIC
  );
END COMPONENT;
-- COMP_TAG_END ------ End COMPONENT Declaration ------------

-- The following code must appear in the VHDL architecture
-- body. Substitute your own instance name and net names.

------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
your_instance_name : system_cache_0
  PORT MAP (
    ACLK => ACLK,
    ARESETN => ARESETN,
    Initializing => Initializing,
    S0_AXI_AWID => S0_AXI_AWID,
    S0_AXI_AWADDR => S0_AXI_AWADDR,
    S0_AXI_AWLEN => S0_AXI_AWLEN,
    S0_AXI_AWSIZE => S0_AXI_AWSIZE,
    S0_AXI_AWBURST => S0_AXI_AWBURST,
    S0_AXI_AWLOCK => S0_AXI_AWLOCK,
    S0_AXI_AWCACHE => S0_AXI_AWCACHE,
    S0_AXI_AWPROT => S0_AXI_AWPROT,
    S0_AXI_AWQOS => S0_AXI_AWQOS,
    S0_AXI_AWVALID => S0_AXI_AWVALID,
    S0_AXI_AWREADY => S0_AXI_AWREADY,
    S0_AXI_AWUSER => S0_AXI_AWUSER,
    S0_AXI_WDATA => S0_AXI_WDATA,
    S0_AXI_WSTRB => S0_AXI_WSTRB,
    S0_AXI_WLAST => S0_AXI_WLAST,
    S0_AXI_WVALID => S0_AXI_WVALID,
    S0_AXI_WREADY => S0_AXI_WREADY,
    S0_AXI_BRESP => S0_AXI_BRESP,
    S0_AXI_BID => S0_AXI_BID,
    S0_AXI_BVALID => S0_AXI_BVALID,
    S0_AXI_BREADY => S0_AXI_BREADY,
    S0_AXI_ARID => S0_AXI_ARID,
    S0_AXI_ARADDR => S0_AXI_ARADDR,
    S0_AXI_ARLEN => S0_AXI_ARLEN,
    S0_AXI_ARSIZE => S0_AXI_ARSIZE,
    S0_AXI_ARBURST => S0_AXI_ARBURST,
    S0_AXI_ARLOCK => S0_AXI_ARLOCK,
    S0_AXI_ARCACHE => S0_AXI_ARCACHE,
    S0_AXI_ARPROT => S0_AXI_ARPROT,
    S0_AXI_ARQOS => S0_AXI_ARQOS,
    S0_AXI_ARVALID => S0_AXI_ARVALID,
    S0_AXI_ARREADY => S0_AXI_ARREADY,
    S0_AXI_ARUSER => S0_AXI_ARUSER,
    S0_AXI_RID => S0_AXI_RID,
    S0_AXI_RDATA => S0_AXI_RDATA,
    S0_AXI_RRESP => S0_AXI_RRESP,
    S0_AXI_RLAST => S0_AXI_RLAST,
    S0_AXI_RVALID => S0_AXI_RVALID,
    S0_AXI_RREADY => S0_AXI_RREADY,
    M0_AXI_AWID => M0_AXI_AWID,
    M0_AXI_AWADDR => M0_AXI_AWADDR,
    M0_AXI_AWLEN => M0_AXI_AWLEN,
    M0_AXI_AWSIZE => M0_AXI_AWSIZE,
    M0_AXI_AWBURST => M0_AXI_AWBURST,
    M0_AXI_AWLOCK => M0_AXI_AWLOCK,
    M0_AXI_AWCACHE => M0_AXI_AWCACHE,
    M0_AXI_AWPROT => M0_AXI_AWPROT,
    M0_AXI_AWQOS => M0_AXI_AWQOS,
    M0_AXI_AWVALID => M0_AXI_AWVALID,
    M0_AXI_AWREADY => M0_AXI_AWREADY,
    M0_AXI_WDATA => M0_AXI_WDATA,
    M0_AXI_WSTRB => M0_AXI_WSTRB,
    M0_AXI_WLAST => M0_AXI_WLAST,
    M0_AXI_WVALID => M0_AXI_WVALID,
    M0_AXI_WREADY => M0_AXI_WREADY,
    M0_AXI_BRESP => M0_AXI_BRESP,
    M0_AXI_BID => M0_AXI_BID,
    M0_AXI_BVALID => M0_AXI_BVALID,
    M0_AXI_BREADY => M0_AXI_BREADY,
    M0_AXI_ARID => M0_AXI_ARID,
    M0_AXI_ARADDR => M0_AXI_ARADDR,
    M0_AXI_ARLEN => M0_AXI_ARLEN,
    M0_AXI_ARSIZE => M0_AXI_ARSIZE,
    M0_AXI_ARBURST => M0_AXI_ARBURST,
    M0_AXI_ARLOCK => M0_AXI_ARLOCK,
    M0_AXI_ARCACHE => M0_AXI_ARCACHE,
    M0_AXI_ARPROT => M0_AXI_ARPROT,
    M0_AXI_ARQOS => M0_AXI_ARQOS,
    M0_AXI_ARVALID => M0_AXI_ARVALID,
    M0_AXI_ARREADY => M0_AXI_ARREADY,
    M0_AXI_RID => M0_AXI_RID,
    M0_AXI_RDATA => M0_AXI_RDATA,
    M0_AXI_RRESP => M0_AXI_RRESP,
    M0_AXI_RLAST => M0_AXI_RLAST,
    M0_AXI_RVALID => M0_AXI_RVALID,
    M0_AXI_RREADY => M0_AXI_RREADY
  );
-- INST_TAG_END ------ End INSTANTIATION Template ---------

-- You must compile the wrapper file system_cache_0.vhd when simulating
-- the core, system_cache_0. When compiling the wrapper file, be sure to
-- reference the VHDL simulation library.

