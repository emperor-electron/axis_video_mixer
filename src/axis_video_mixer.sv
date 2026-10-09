`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: axis_video_mixer.sv
// Author  : Benjamin Tamayo
// Date    : 09/06/2026
// Purpose : Top level of the reusable AXI4-Stream video mixer.
//
//           Composites up to eight RGBA video streams into one, under AXI4-Lite
//           control, for picture-in-picture and tiled layouts. The layers are
//           not scaled: each stream must already arrive at the size its SIZE
//           register declares.
//
//           This file only wires together two pieces:
//               axis_video_mixer_csr   generated register block plus adapter
//               axis_video_mixer_core  raster, layer buffers, blend cascade
//           and gathers the eight named input stream ports into the arrays the
//           datapath works in.
//
//           PORTS, ONE SIGNAL EACH. Every signal of every input stream is its
//           own named port -- s_axis0_tvalid, s_axis0_tready, s_axis0_tdata,
//           s_axis0_tuser, s_axis0_tlast, and the same five for streams 1
//           through 7. Nothing is packed across streams.
//
//           That is what lets a block design or an IP-XACT package see eight
//           separate AXI4-Stream interfaces rather than one wide bus it cannot
//           interpret: the interface inference in those tools keys on the port
//           name, so s_axis3_tdata is recognised as the TDATA of an interface
//           called s_axis3 with no manual mapping at all. A packed
//           {N*BEAT_W} vector has to be split by hand on the far side, and
//           every integrator splits it slightly differently.
//
//           All eight port sets exist in every build. P_NUM_LAYERS says how
//           many are wired to the datapath, from 1 to 8; the rest are left
//           unconnected inside and hold their TREADY low, so a stream wired to
//           a port this build does not implement stalls visibly instead of
//           being silently consumed. Software reads the real count from
//           CAPS.NUM_LAYERS rather than assuming eight.
//
//           Streams. All of them, in and out, use the Xilinx video AXI4-Stream
//           conventions already used elsewhere in this pipeline:
//               TUSER = SOF, on the first BEAT of a frame
//               TLAST = EOL, on the last BEAT of every line
//               TDATA = P_PPC pixels, lane 0 in the least significant bits,
//                       each pixel {R, G, B, A} with R in its top component
//
//           COMPONENT WIDTH. P_CH_W is the width of one colour component: 8,
//           10, 12 or 16, so a pixel is 32, 40, 48 or 64 bits. 8 is RGBA8; the
//           others are the deep-colour depths HDMI and DisplayPort carry and
//           what a linear-light intermediate wants. It applies to every port,
//           in and out, for the same reason P_PPC does -- a layer supplies one
//           pixel per canvas pixel, and a mixed-width composite would mean a
//           converter per layer inside this block. The blend divides by
//           2**P_CH_W - 1 rather than by 255 so that an alpha of full scale
//           returns the top colour exactly at every width.
//
//           Two register fields stay 8 bits wide whatever P_CH_W is, and are
//           expanded to the component width in the datapath: L<i>_CTRL.ALPHA
//           and BACKGROUND.RGB. See ch_up in the package for why.
//
//           P_PPC applies to every port -- all N inputs and the output. It is
//           not per interface, and the reason is arithmetic rather than taste:
//           inside its window a layer must supply one pixel per canvas pixel,
//           so a layer feeding a P-pixel-per-beat canvas has to deliver P per
//           beat. A source running at a different width belongs behind an
//           AXI4-Stream width converter, exactly as a source on another clock
//           belongs behind a clock converter. Both are standard IP that need
//           know nothing about this block, and building N of either inside
//           would cost area whether or not anyone used them.
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
    // Layer input streams actually instantiated, 1 to MAX_LAYERS. The ports for
    // all MAX_LAYERS exist regardless; this is how many are wired up.
    parameter int P_NUM_LAYERS = 4,
    // Per-layer input buffer depth in BEATS. Must be a power of two, and must
    // be at least the widest layer this build will ever show: a window at x = 0
    // gets no head start within the line, so a full line has to be buffered
    // before that line begins.
    parameter int P_FIFO_DEPTH = 2048,
    // 1: the output carries RGBA with alpha forced to full scale, and two
    //    mixers can be cascaded. 0: RGB only, which drops straight into a video
    //    output stage without an adapter.
    parameter bit P_OUT_HAS_ALPHA = 1'b1,
    // Pixels per beat on every stream. 1, 2, 4 or 8.
    //
    // This is the knob for pixel rates above the achievable fclk: 4K60 is a
    // 594 MHz pixel rate, which is 148.5 MHz at P_PPC = 4. It costs area
    // roughly linearly and frequency not at all, because the blend is
    // replicated per lane rather than made deeper.
    //
    // Horizontal geometry must be a whole number of beats -- see the register
    // map's CAPS.PPC and ERR.CFG. At 1 that constraint is vacuous.
    parameter int P_PPC = 1,
    // Colour component width on every stream: 8, 10, 12 or 16 bits. A pixel is
    // four of these, {R, G, B, A}, R in the most significant.
    parameter int P_CH_W = 8,
    parameter int P_AXIL_ADDR_W = 12,
    // Derived; do not override.
    parameter int P_PX_W = 4 * P_CH_W,
    parameter int P_RGB_W = 3 * P_CH_W,
    parameter int P_PX_OUT_W = P_OUT_HAS_ALPHA ? P_PX_W : P_RGB_W,
    parameter int P_OUT_W = P_PPC * P_PX_OUT_W,
    parameter int P_BEAT_W = P_PPC * P_PX_W
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
    // Layer input streams. One named port per signal per stream, eight streams,
    // nothing packed. Streams at or above P_NUM_LAYERS are not implemented in
    // this build: their inputs are ignored and their TREADY is held low.
    //
    // Layer 0 is nearest the background and the highest-numbered enabled layer
    // is on top -- z-order is chosen by which stream is wired to which port.
    ////////////////////////////////////////////////////////////////////////////////////////////////
    input  logic                s_axis0_tvalid,
    output logic                s_axis0_tready,
    input  logic [P_BEAT_W-1:0] s_axis0_tdata,
    input  logic                s_axis0_tuser,
    input  logic                s_axis0_tlast,

    input  logic                s_axis1_tvalid,
    output logic                s_axis1_tready,
    input  logic [P_BEAT_W-1:0] s_axis1_tdata,
    input  logic                s_axis1_tuser,
    input  logic                s_axis1_tlast,

    input  logic                s_axis2_tvalid,
    output logic                s_axis2_tready,
    input  logic [P_BEAT_W-1:0] s_axis2_tdata,
    input  logic                s_axis2_tuser,
    input  logic                s_axis2_tlast,

    input  logic                s_axis3_tvalid,
    output logic                s_axis3_tready,
    input  logic [P_BEAT_W-1:0] s_axis3_tdata,
    input  logic                s_axis3_tuser,
    input  logic                s_axis3_tlast,

    input  logic                s_axis4_tvalid,
    output logic                s_axis4_tready,
    input  logic [P_BEAT_W-1:0] s_axis4_tdata,
    input  logic                s_axis4_tuser,
    input  logic                s_axis4_tlast,

    input  logic                s_axis5_tvalid,
    output logic                s_axis5_tready,
    input  logic [P_BEAT_W-1:0] s_axis5_tdata,
    input  logic                s_axis5_tuser,
    input  logic                s_axis5_tlast,

    input  logic                s_axis6_tvalid,
    output logic                s_axis6_tready,
    input  logic [P_BEAT_W-1:0] s_axis6_tdata,
    input  logic                s_axis6_tuser,
    input  logic                s_axis6_tlast,

    input  logic                s_axis7_tvalid,
    output logic                s_axis7_tready,
    input  logic [P_BEAT_W-1:0] s_axis7_tdata,
    input  logic                s_axis7_tuser,
    input  logic                s_axis7_tlast,

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
  logic [             7:0] lay_alpha       [P_NUM_LAYERS];
  logic [P_NUM_LAYERS-1:0] lay_alpha_src;
  logic [            15:0] lay_x           [P_NUM_LAYERS];
  logic [            15:0] lay_y           [P_NUM_LAYERS];
  logic [            15:0] lay_w           [P_NUM_LAYERS];
  logic [            15:0] lay_h           [P_NUM_LAYERS];

  logic [P_NUM_LAYERS-1:0] lay_armed;
  logic [P_NUM_LAYERS-1:0] lay_dropped;
  logic [P_NUM_LAYERS-1:0] lay_cfg_bad;
  logic [            15:0] lay_level       [P_NUM_LAYERS];

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Gather the named stream ports
  //
  // Named ports outside, arrays inside. The datapath instantiates a layer per
  // element and indexes everything by layer, so it wants an array; the boundary
  // wants one port per signal. This is the whole of the translation, and it is
  // one assign per port rather than a generate loop because a port name is not
  // something a genvar can build.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [  MAX_LAYERS-1:0] in_tvalid;
  logic [  MAX_LAYERS-1:0] in_tready;
  logic [    P_BEAT_W-1:0] in_tdata        [MAX_LAYERS];
  logic [  MAX_LAYERS-1:0] in_tuser;
  logic [  MAX_LAYERS-1:0] in_tlast;

  assign in_tvalid = {
    s_axis7_tvalid,
    s_axis6_tvalid,
    s_axis5_tvalid,
    s_axis4_tvalid,
    s_axis3_tvalid,
    s_axis2_tvalid,
    s_axis1_tvalid,
    s_axis0_tvalid
  };

  assign in_tuser = {
    s_axis7_tuser,
    s_axis6_tuser,
    s_axis5_tuser,
    s_axis4_tuser,
    s_axis3_tuser,
    s_axis2_tuser,
    s_axis1_tuser,
    s_axis0_tuser
  };

  assign in_tlast = {
    s_axis7_tlast,
    s_axis6_tlast,
    s_axis5_tlast,
    s_axis4_tlast,
    s_axis3_tlast,
    s_axis2_tlast,
    s_axis1_tlast,
    s_axis0_tlast
  };

  assign in_tdata[0] = s_axis0_tdata;
  assign in_tdata[1] = s_axis1_tdata;
  assign in_tdata[2] = s_axis2_tdata;
  assign in_tdata[3] = s_axis3_tdata;
  assign in_tdata[4] = s_axis4_tdata;
  assign in_tdata[5] = s_axis5_tdata;
  assign in_tdata[6] = s_axis6_tdata;
  assign in_tdata[7] = s_axis7_tdata;

  assign s_axis0_tready = in_tready[0];
  assign s_axis1_tready = in_tready[1];
  assign s_axis2_tready = in_tready[2];
  assign s_axis3_tready = in_tready[3];
  assign s_axis4_tready = in_tready[4];
  assign s_axis5_tready = in_tready[5];
  assign s_axis6_tready = in_tready[6];
  assign s_axis7_tready = in_tready[7];

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Streams this build implements, and the ones it does not
  //
  // An unimplemented stream holds TREADY low rather than high. High would
  // consume beats and throw them away, which looks like a working connection
  // and produces a black layer; low stalls the producer at once, which is a
  // fault an integrator finds in the first second of bring-up.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [P_NUM_LAYERS-1:0] core_tvalid;
  logic [P_NUM_LAYERS-1:0] core_tready;
  logic [    P_BEAT_W-1:0] core_tdata     [P_NUM_LAYERS];
  logic [P_NUM_LAYERS-1:0] core_tuser;
  logic [P_NUM_LAYERS-1:0] core_tlast;

  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_stream_used
    assign core_tvalid[gi] = in_tvalid[gi];
    assign core_tdata[gi]  = in_tdata[gi];
    assign core_tuser[gi]  = in_tuser[gi];
    assign core_tlast[gi]  = in_tlast[gi];
    assign in_tready[gi]   = core_tready[gi];
  end

  for (genvar gi = P_NUM_LAYERS; gi < MAX_LAYERS; gi++) begin : g_stream_unused
    assign in_tready[gi] = 1'b0;
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Register block
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  axis_video_mixer_csr #(
      .P_NUM_LAYERS   (P_NUM_LAYERS),
      .P_PPC          (P_PPC),
      .P_CH_W         (P_CH_W),
      .P_FIFO_DEPTH   (P_FIFO_DEPTH),
      .P_OUT_HAS_ALPHA(P_OUT_HAS_ALPHA),
      .P_ADDR_W       (P_AXIL_ADDR_W)
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
      .P_OUT_HAS_ALPHA(P_OUT_HAS_ALPHA),
      .P_PPC          (P_PPC),
      .P_CH_W         (P_CH_W)
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

      .s_axis_tvalid(core_tvalid),
      .s_axis_tready(core_tready),
      .s_axis_tdata (core_tdata),
      .s_axis_tuser (core_tuser),
      .s_axis_tlast (core_tlast),

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
    // The upper bound is the number of named port sets this file brings out,
    // and the register map is generated for the same number. Asking for more
    // would leave the extra layers with no stream and no registers.
    if (P_NUM_LAYERS < 1 || P_NUM_LAYERS > MAX_LAYERS) begin
      $fatal(1, "axis_video_mixer: P_NUM_LAYERS=%0d out of range 1..%0d", P_NUM_LAYERS,
             MAX_LAYERS);
    end
    if (!ppc_legal(P_PPC)) begin
      $fatal(1, "axis_video_mixer: P_PPC=%0d must be 1, 2, 4 or 8", P_PPC);
    end
    // Not merely unusual widths: the blend identity in the package is proved
    // exact at these four and nowhere else, so an unlisted width would
    // composite with an error that grows down the cascade.
    if (!ch_w_legal(P_CH_W)) begin
      $fatal(1, "axis_video_mixer: P_CH_W=%0d must be 8, 10, 12 or 16", P_CH_W);
    end
    // The buffer is measured in beats now, so the depth needed for a given
    // pixel capacity falls with P_PPC. Getting this backwards is a starve on
    // every line, so it is worth failing the build over.
    if (P_FIFO_DEPTH < 2) begin
      $fatal(1, "axis_video_mixer: P_FIFO_DEPTH=%0d is a beat count and must cover one layer line",
             P_FIFO_DEPTH);
    end
  end

endmodule
