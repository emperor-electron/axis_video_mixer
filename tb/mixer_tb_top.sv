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

  // Pixels per beat comes from the package, which takes it from the MIX_PPC
  // define. Deliberately NOT a generic as well: two ways to set the same thing
  // is two ways for them to disagree, and the link width the UVC is
  // specialised on already follows the define.

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
  // Flatten the per-layer interfaces into the DUT's packed vectors
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [           NUM_LAYERS-1:0] s_tvalid;
  logic [           NUM_LAYERS-1:0] s_tready;
  logic [NUM_LAYERS*MIX_DATA_BYTES*8-1:0] s_tdata;
  logic [           NUM_LAYERS-1:0] s_tuser;
  logic [           NUM_LAYERS-1:0] s_tlast;

  for (genvar gi = 0; gi < NUM_LAYERS; gi++) begin : g_layer_wire
    assign s_tvalid[gi] = layer_if[gi].tvalid;
    assign s_tdata[gi*MIX_DATA_BYTES*8+:MIX_DATA_BYTES*8] = layer_if[gi].tdata;
    assign s_tuser[gi] = layer_if[gi].tuser[0];
    assign s_tlast[gi] = layer_if[gi].tlast;
    assign layer_if[gi].tready = s_tready[gi];
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

      .s_axis_tvalid(s_tvalid),
      .s_axis_tready(s_tready),
      .s_axis_tdata (s_tdata),
      .s_axis_tuser (s_tuser),
      .s_axis_tlast (s_tlast),

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
