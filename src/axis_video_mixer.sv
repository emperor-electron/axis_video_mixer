`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: axis_video_mixer.sv
// Author  : Benjamin Tamayo
// Date    : 09/06/2026
// Purpose : Top level of the reusable AXI4-Stream video mixer.
//
//           Composites P_NUM_LAYERS RGBA8 video streams into one, under
//           AXI4-Lite control, for picture-in-picture and tiled layouts. The
//           layers are not scaled: each stream must already arrive at the size
//           its SIZE register declares.
//
//           This file only wires together three pieces:
//               axis_video_mixer_csr   generated register block plus adapter
//               axis_video_mixer_core  raster, layer buffers, blend cascade
//           and flattens the per-layer arrays to packed vectors at the boundary,
//           because unpacked array ports do not survive an IP-XACT or block
//           design boundary. Inside, arrays; outside, one wide vector per field.
//
//           Streams. All of them, in and out, use the Xilinx video AXI4-Stream
//           conventions already used elsewhere in this pipeline:
//               TUSER = SOF, on the first pixel of a frame
//               TLAST = EOL, on the last pixel of every line
//               TDATA = {R, G, B, A} for inputs, R in the most significant byte
//
//           Clocking. Single domain: every input stream, the output stream and
//           the AXI4-Lite port all run on clk. Feeding a source from another
//           clock is the caller's job -- put an ordinary AXI4-Stream clock
//           converter in front of the relevant layer port. Absorbing that here
//           would mean N asynchronous FIFOs whether or not anyone needed them.
///////////////////////////////////////////////////////////////////

module axis_video_mixer
  import axis_video_mixer_pkg::*;
#(
    parameter int P_NUM_LAYERS = 4,
    // Per-layer input buffer depth in pixels. Must be a power of two, and must
    // be at least the widest layer this build will ever show: a window at x = 0
    // gets no head start within the line, so a full line has to be buffered
    // before that line begins.
    parameter int P_FIFO_DEPTH = 2048,
    // 1: the output carries RGBA8 with alpha forced opaque, and two mixers can
    //    be cascaded. 0: 24-bit RGB, which drops straight into a video output
    //    stage without an adapter.
    parameter bit P_OUT_HAS_ALPHA = 1'b1,
    parameter int P_AXIL_ADDR_W = 12,
    // Derived; do not override.
    parameter int P_OUT_W = P_OUT_HAS_ALPHA ? PX_W : RGB_W
) (
    input logic clk,
    input logic rst_n,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // AXI4-Lite control
    ////////////////////////////////////////////////////////////////////////////////////////////////
    input  logic [P_AXIL_ADDR_W-1:0] s_axil_awaddr,
    input  logic [              2:0] s_axil_awprot,
    input  logic                     s_axil_awvalid,
    output logic                     s_axil_awready,
    input  logic [             31:0] s_axil_wdata,
    input  logic [              3:0] s_axil_wstrb,
    input  logic                     s_axil_wvalid,
    output logic                     s_axil_wready,
    output logic [              1:0] s_axil_bresp,
    output logic                     s_axil_bvalid,
    input  logic                     s_axil_bready,
    input  logic [P_AXIL_ADDR_W-1:0] s_axil_araddr,
    input  logic [              2:0] s_axil_arprot,
    input  logic                     s_axil_arvalid,
    output logic                     s_axil_arready,
    output logic [             31:0] s_axil_rdata,
    output logic [              1:0] s_axil_rresp,
    output logic                     s_axil_rvalid,
    input  logic                     s_axil_rready,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Layer input streams, flattened. Layer i occupies bit i of the handshake
    // vectors and TDATA[(i+1)*32-1 : i*32].
    ////////////////////////////////////////////////////////////////////////////////////////////////
    input  logic [     P_NUM_LAYERS-1:0] s_axis_tvalid,
    output logic [     P_NUM_LAYERS-1:0] s_axis_tready,
    input  logic [P_NUM_LAYERS*PX_W-1:0] s_axis_tdata,
    input  logic [     P_NUM_LAYERS-1:0] s_axis_tuser,
    input  logic [     P_NUM_LAYERS-1:0] s_axis_tlast,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Composited output stream
    ////////////////////////////////////////////////////////////////////////////////////////////////
    output logic               m_axis_tvalid,
    input  logic               m_axis_tready,
    output logic [P_OUT_W-1:0] m_axis_tdata,
    output logic               m_axis_tuser,
    output logic               m_axis_tlast,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Level-sensitive interrupt: the OR of (ERR & IRQ_EN). Stays asserted until
    // software clears the underlying ERR bit.
    ////////////////////////////////////////////////////////////////////////////////////////////////
    output logic irq
);
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Configuration and status between the register block and the datapath
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic        ctrl_en;
  logic        ctrl_soft_rst;
  logic [15:0] canvas_width;
  logic [15:0] canvas_height;
  logic [23:0] background_rgb;
  logic [31:0] stall_limit;

  logic        status_frame_active;
  logic [31:0] frame_count;

  logic err_cfg_set, err_starve_set, err_geom_set, err_src_stall_set, err_out_stall_set;
  logic [P_NUM_LAYERS-1:0] err_layer_set;

  logic [P_NUM_LAYERS-1:0] lay_en;
  logic [             7:0] lay_alpha    [P_NUM_LAYERS];
  logic [P_NUM_LAYERS-1:0] lay_alpha_src;
  logic [            15:0] lay_x        [P_NUM_LAYERS];
  logic [            15:0] lay_y        [P_NUM_LAYERS];
  logic [            15:0] lay_w        [P_NUM_LAYERS];
  logic [            15:0] lay_h        [P_NUM_LAYERS];

  logic [P_NUM_LAYERS-1:0] lay_armed;
  logic [P_NUM_LAYERS-1:0] lay_dropped;
  logic [P_NUM_LAYERS-1:0] lay_cfg_bad;
  logic [            15:0] lay_level    [P_NUM_LAYERS];

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Unflatten the input streams
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [PX_W-1:0] s_axis_tdata_arr[P_NUM_LAYERS];

  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_unflatten
    assign s_axis_tdata_arr[gi] = s_axis_tdata[gi*PX_W+:PX_W];
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Register block
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  axis_video_mixer_csr #(
      .P_NUM_LAYERS(P_NUM_LAYERS),
      .P_ADDR_W    (P_AXIL_ADDR_W)
  ) u_csr (
      .clk  (clk),
      .rst_n(rst_n),

      .axil_awaddr (s_axil_awaddr),
      .axil_awprot (s_axil_awprot),
      .axil_awvalid(s_axil_awvalid),
      .axil_awready(s_axil_awready),
      .axil_wdata  (s_axil_wdata),
      .axil_wstrb  (s_axil_wstrb),
      .axil_wvalid (s_axil_wvalid),
      .axil_wready (s_axil_wready),
      .axil_bresp  (s_axil_bresp),
      .axil_bvalid (s_axil_bvalid),
      .axil_bready (s_axil_bready),
      .axil_araddr (s_axil_araddr),
      .axil_arprot (s_axil_arprot),
      .axil_arvalid(s_axil_arvalid),
      .axil_arready(s_axil_arready),
      .axil_rdata  (s_axil_rdata),
      .axil_rresp  (s_axil_rresp),
      .axil_rvalid (s_axil_rvalid),
      .axil_rready (s_axil_rready),

      .ctrl_en       (ctrl_en),
      .ctrl_soft_rst (ctrl_soft_rst),
      .canvas_width  (canvas_width),
      .canvas_height (canvas_height),
      .background_rgb(background_rgb),
      .stall_limit   (stall_limit),

      .status_frame_active(status_frame_active),
      .frame_count        (frame_count),

      .err_cfg_set      (err_cfg_set),
      .err_starve_set   (err_starve_set),
      .err_geom_set     (err_geom_set),
      .err_src_stall_set(err_src_stall_set),
      .err_out_stall_set(err_out_stall_set),
      .err_layer_set    (err_layer_set),

      .lay_en       (lay_en),
      .lay_alpha    (lay_alpha),
      .lay_alpha_src(lay_alpha_src),
      .lay_x        (lay_x),
      .lay_y        (lay_y),
      .lay_w        (lay_w),
      .lay_h        (lay_h),

      .lay_armed  (lay_armed),
      .lay_dropped(lay_dropped),
      .lay_cfg_bad(lay_cfg_bad),
      .lay_level  (lay_level),

      .irq(irq)
  );

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Datapath
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  axis_video_mixer_core #(
      .P_NUM_LAYERS   (P_NUM_LAYERS),
      .P_FIFO_DEPTH   (P_FIFO_DEPTH),
      .P_OUT_HAS_ALPHA(P_OUT_HAS_ALPHA)
  ) u_core (
      .clk  (clk),
      .rst_n(rst_n),

      .ctrl_en       (ctrl_en),
      .ctrl_soft_rst (ctrl_soft_rst),
      .canvas_width  (canvas_width),
      .canvas_height (canvas_height),
      .background_rgb(background_rgb),
      .stall_limit   (stall_limit),
      .lay_en        (lay_en),
      .lay_alpha     (lay_alpha),
      .lay_alpha_src (lay_alpha_src),
      .lay_x         (lay_x),
      .lay_y         (lay_y),
      .lay_w         (lay_w),
      .lay_h         (lay_h),

      .status_frame_active(status_frame_active),
      .frame_count        (frame_count),
      .err_cfg_set        (err_cfg_set),
      .err_starve_set     (err_starve_set),
      .err_geom_set       (err_geom_set),
      .err_src_stall_set  (err_src_stall_set),
      .err_out_stall_set  (err_out_stall_set),
      .err_layer_set      (err_layer_set),
      .lay_armed          (lay_armed),
      .lay_dropped        (lay_dropped),
      .lay_cfg_bad        (lay_cfg_bad),
      .lay_level          (lay_level),

      .s_axis_tvalid(s_axis_tvalid),
      .s_axis_tready(s_axis_tready),
      .s_axis_tdata (s_axis_tdata_arr),
      .s_axis_tuser (s_axis_tuser),
      .s_axis_tlast (s_axis_tlast),

      .m_axis_tvalid(m_axis_tvalid),
      .m_axis_tready(m_axis_tready),
      .m_axis_tdata (m_axis_tdata),
      .m_axis_tuser (m_axis_tuser),
      .m_axis_tlast (m_axis_tlast)
  );

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Build-time checks
  //
  // Each of these is something that produces working-looking RTL and a wrong
  // picture, so they are worth failing the build over rather than discovering
  // on a monitor.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  initial begin
    if (P_FIFO_DEPTH != (1 << $clog2(P_FIFO_DEPTH))) begin
      $fatal(1, "axis_video_mixer: P_FIFO_DEPTH=%0d is not a power of two", P_FIFO_DEPTH);
    end
    if (P_NUM_LAYERS < 1 || P_NUM_LAYERS > 16) begin
      $fatal(1, "axis_video_mixer: P_NUM_LAYERS=%0d out of range 1..16", P_NUM_LAYERS);
    end
  end

endmodule
