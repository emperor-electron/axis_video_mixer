`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: mixer_tb_top.sv
// Author  : Benjamin Tamayo
// Date    : 09/06/2026
// Purpose : Static top for the video mixer testbench: clock, reset, the
//           interfaces, the DUT, and publication of the virtual interfaces
//           into the config DB.
//
//           The canvas size is a parameter here rather than in the package so
//           that xelab --generic_top can shrink the raster for a fast
//           regression without any source change. The default 64x8 makes a
//           frame 512 beats.
///////////////////////////////////////////////////////////////////

module mixer_tb_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import mixer_tb_pkg::*;
  import axis_video_mixer_pkg::*;

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Build-time geometry
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  parameter int NUM_LAYERS = 4;
  parameter int CANVAS_W = 64;
  parameter int CANVAS_H = 8;
  // Deliberately far smaller than the synthesis default. A 2048-deep FIFO per
  // layer would model 8 block RAMs the simulation gains nothing from, and a
  // shallow buffer is a stricter test: it forces the flow control to work
  // rather than hiding behind capacity.
  parameter int FIFO_DEPTH = 128;

  // Pixels per beat and the component width come from the package, which takes
  // them from the MIX_PPC and MIX_CH_W defines. Deliberately NOT generics as
  // well: two ways to set the same thing is two ways for them to disagree, and
  // the link width the UVC is specialised on already follows the defines.
  //
  // NUM_LAYERS may be anything from 1 to MIX_MAX_LAYERS. The DUT brings out
  // MIX_MAX_LAYERS sets of stream ports in every build and reports how many
  // are implemented through CAPS.NUM_LAYERS, so the register map does not have
  // to be regenerated to change this.

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Clock and reset
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic aclk = 1'b0;
  logic aresetn = 1'b0;

  always #3.367 aclk = ~aclk;  // ~148.5 MHz, the 1080p60 pixel clock

  initial begin
    aresetn = 1'b0;
    repeat (16) @(posedge aclk);
    aresetn = 1'b1;
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Interfaces
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  axi_stream_if #(MIX_DATA_BYTES, MIX_ID_WIDTH, MIX_DEST_WIDTH, MIX_USER_WIDTH)
      layer_if[NUM_LAYERS] (aclk, aresetn);

  axi_stream_if #(MIX_DATA_BYTES, MIX_ID_WIDTH, MIX_DEST_WIDTH, MIX_USER_WIDTH)
      out_if (aclk, aresetn);

  axi_lite_if #(12, 32) axil_if (aclk, aresetn);

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Wire the per-layer interfaces to the DUT's named stream ports
  //
  // The arrays are indexed by a genvar so the interface array can be walked in
  // a loop; the DUT connection below is one line per port, because a port name
  // is not something a genvar can build. Entries at or above NUM_LAYERS have
  // no interface behind them and are driven idle -- the DUT holds their TREADY
  // low in any case, but leaving them undriven would propagate X into a port
  // that is supposed to be a don't-care.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [         MIX_DATA_BYTES*8-1:0] s_tdata [MIX_MAX_LAYERS];
  logic                                 s_tvalid[MIX_MAX_LAYERS];
  logic                                 s_tready[MIX_MAX_LAYERS];
  logic                                 s_tuser [MIX_MAX_LAYERS];
  logic                                 s_tlast [MIX_MAX_LAYERS];

  for (genvar gi = 0; gi < NUM_LAYERS; gi++) begin : g_layer_wire
    assign s_tvalid[gi] = layer_if[gi].tvalid;
    assign s_tdata[gi]  = layer_if[gi].tdata;
    assign s_tuser[gi]  = layer_if[gi].tuser[0];
    assign s_tlast[gi]  = layer_if[gi].tlast;
    assign layer_if[gi].tready = s_tready[gi];
  end

  for (genvar gi = NUM_LAYERS; gi < MIX_MAX_LAYERS; gi++) begin : g_layer_idle
    assign s_tvalid[gi] = 1'b0;
    assign s_tdata[gi]  = '0;
    assign s_tuser[gi]  = 1'b0;
    assign s_tlast[gi]  = 1'b0;
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // DUT
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic        m_tvalid;
  logic        m_tready;
  logic [MIX_DATA_BYTES*8-1:0] m_tdata;
  logic        m_tuser;
  logic        m_tlast;
  logic        irq;

  assign out_if.tvalid   = m_tvalid;
  assign out_if.tdata    = m_tdata;
  assign out_if.tuser[0] = m_tuser;
  assign out_if.tlast    = m_tlast;
  assign out_if.tkeep    = '1;
  assign out_if.tstrb    = '1;
  assign out_if.tid      = '0;
  assign out_if.tdest    = '0;
  assign m_tready        = out_if.tready;

  axis_video_mixer #(
      .P_NUM_LAYERS   (NUM_LAYERS),
      .P_FIFO_DEPTH   (FIFO_DEPTH),
      .P_OUT_HAS_ALPHA(1'b1),
      .P_PPC          (MIX_PPC),
      .P_CH_W         (MIX_CH_W),
      .P_AXIL_ADDR_W  (12)
  ) dut (
      .clk  (aclk),
      .rst_n(aresetn),

      .s_axil_awaddr (axil_if.awaddr),
      .s_axil_awprot (axil_if.awprot),
      .s_axil_awvalid(axil_if.awvalid),
      .s_axil_awready(axil_if.awready),
      .s_axil_wdata  (axil_if.wdata),
      .s_axil_wstrb  (axil_if.wstrb),
      .s_axil_wvalid (axil_if.wvalid),
      .s_axil_wready (axil_if.wready),
      .s_axil_bresp  (axil_if.bresp),
      .s_axil_bvalid (axil_if.bvalid),
      .s_axil_bready (axil_if.bready),
      .s_axil_araddr (axil_if.araddr),
      .s_axil_arprot (axil_if.arprot),
      .s_axil_arvalid(axil_if.arvalid),
      .s_axil_arready(axil_if.arready),
      .s_axil_rdata  (axil_if.rdata),
      .s_axil_rresp  (axil_if.rresp),
      .s_axil_rvalid (axil_if.rvalid),
      .s_axil_rready (axil_if.rready),

      .s_axis0_tvalid(s_tvalid[0]),
      .s_axis0_tready(s_tready[0]),
      .s_axis0_tdata (s_tdata[0]),
      .s_axis0_tuser (s_tuser[0]),
      .s_axis0_tlast (s_tlast[0]),

      .s_axis1_tvalid(s_tvalid[1]),
      .s_axis1_tready(s_tready[1]),
      .s_axis1_tdata (s_tdata[1]),
      .s_axis1_tuser (s_tuser[1]),
      .s_axis1_tlast (s_tlast[1]),

      .s_axis2_tvalid(s_tvalid[2]),
      .s_axis2_tready(s_tready[2]),
      .s_axis2_tdata (s_tdata[2]),
      .s_axis2_tuser (s_tuser[2]),
      .s_axis2_tlast (s_tlast[2]),

      .s_axis3_tvalid(s_tvalid[3]),
      .s_axis3_tready(s_tready[3]),
      .s_axis3_tdata (s_tdata[3]),
      .s_axis3_tuser (s_tuser[3]),
      .s_axis3_tlast (s_tlast[3]),

      .s_axis4_tvalid(s_tvalid[4]),
      .s_axis4_tready(s_tready[4]),
      .s_axis4_tdata (s_tdata[4]),
      .s_axis4_tuser (s_tuser[4]),
      .s_axis4_tlast (s_tlast[4]),

      .s_axis5_tvalid(s_tvalid[5]),
      .s_axis5_tready(s_tready[5]),
      .s_axis5_tdata (s_tdata[5]),
      .s_axis5_tuser (s_tuser[5]),
      .s_axis5_tlast (s_tlast[5]),

      .s_axis6_tvalid(s_tvalid[6]),
      .s_axis6_tready(s_tready[6]),
      .s_axis6_tdata (s_tdata[6]),
      .s_axis6_tuser (s_tuser[6]),
      .s_axis6_tlast (s_tlast[6]),

      .s_axis7_tvalid(s_tvalid[7]),
      .s_axis7_tready(s_tready[7]),
      .s_axis7_tdata (s_tdata[7]),
      .s_axis7_tuser (s_tuser[7]),
      .s_axis7_tlast (s_tlast[7]),

      .m_axis_tvalid(m_tvalid),
      .m_axis_tready(m_tready),
      .m_axis_tdata (m_tdata),
      .m_axis_tuser (m_tuser),
      .m_axis_tlast (m_tlast),

      .irq(irq)
  );

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Publish to the config DB and run
  //
  // The layer interfaces are published from a generate block rather than from
  // a loop inside the initial block below: an array of interface instances can
  // only be indexed by an elaboration-time constant, and a genvar is one while
  // a procedural loop variable is not.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  for (genvar gp = 0; gp < NUM_LAYERS; gp++) begin : g_publish
    initial begin
      uvm_config_db#(mix_vif_t)::set(null, "uvm_test_top.env",
                                     $sformatf("vif_layer%0d", gp), layer_if[gp]);
    end
  end

  initial begin
    uvm_config_db#(mix_vif_t)::set(null, "uvm_test_top.env", "vif_out", out_if);
    uvm_config_db#(mix_axil_vif_t)::set(null, "uvm_test_top.env", "vif_axil", axil_if);

    uvm_config_db#(int)::set(null, "uvm_test_top", "canvas_w", CANVAS_W);
    uvm_config_db#(int)::set(null, "uvm_test_top", "canvas_h", CANVAS_H);
    uvm_config_db#(int)::set(null, "uvm_test_top", "num_layers", NUM_LAYERS);

    run_test();
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Waves, on demand
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  initial begin
    if ($test$plusargs("WAVES")) begin
      $dumpfile("waves.vcd");
      $dumpvars(0, mixer_tb_top);
    end
  end

endmodule : mixer_tb_top
