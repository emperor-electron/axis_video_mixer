`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_core.sv
// Purpose : Formal top for axis_video_mixer_core: the raster, the layer front
//           ends, their FIFOs and the blend cascade, against free sources, a
//           free sink and free software.
//
//           Everything the register block would drive is free here -- EN,
//           SOFT_RST, the canvas, the background, every layer's position,
//           size, enable and alpha -- so the solver is allowed to write a
//           misaligned window, a window off the canvas, a zero-sized canvas, a
//           canvas of one beat by one line, or a new geometry every cycle. The
//           register block cannot prevent any of those; the core is supposed
//           to reject them, and that rejection is a large part of what is
//           being proved.
//
//           Every input stream is free too, so a source may deliver nothing,
//           deliver a frame of the wrong size, or raise TUSER mid-line. And
//           m_axis_tready is free, so the sink may stall at any point,
//           including forever.
//
//           SIZING. Two layers, a four-beat FIFO, one pixel per beat. None of
//           those is the shipping configuration, and each is chosen for a
//           reason:
//
//             Two layers rather than four is the smallest count at which the
//             cascade is a cascade and at which "layer 0 is nearest the
//             background" means anything. The per-layer logic is generated, so
//             a third and fourth instance are copies of the second.
//
//             Four beats rather than 2048 keeps the memory the solver models
//             small. Depth enters these properties only through the FIFO's own
//             pointer width, which fv_fifo.sby proves at two depths.
//
//             One pixel per beat for most tasks, two for the ppc task. The
//             lanes of a beat are completely independent in the cascade and
//             share only control, so two lanes is where a control signal
//             reaching the wrong lane would show up.
//
//           GEOMETRY BOUNDS. The canvas and window registers are held to
//           FV_MAX_DIM by assumption. That is a real restriction and worth being
//           plain about: a 16-bit canvas would put the raster comparisons
//           beyond what the solver will finish, and the frame task needs a
//           canvas small enough to emit whole frames inside the BMC depth.
//           The properties in fv_core_props.sv are about relations between
//           registers, not about their magnitudes, so a small canvas exercises
//           the same logic -- but a bug that only appears above some threshold
//           would not be caught, and nothing here claims otherwise.
///////////////////////////////////////////////////////////////////

module fv_core
  import axis_video_mixer_pkg::*;
#(
    parameter int P_NUM_LAYERS = 2,
    parameter int P_FIFO_DEPTH = 4,
    parameter bit P_OUT_HAS_ALPHA = 1'b1,
    parameter int P_PPC = 1,

    // Upper bounds on the free configuration. Small by necessity -- see the
    // header.
    parameter int FV_MAX_DIM = 4,

    // 1: hold the configuration constant after reset. The framing and
    // datapath properties in fv_core_frame.sv need this, because they compare
    // the output against a model that has to know the canvas, and the beat
    // leaving the pipeline was rastered up to P_NUM_LAYERS+2 cycles ago.
    // 0: software may rewrite anything at any time, which is what the
    // invariant tasks want.
    parameter bit FV_STATIC_CFG = 1'b0,

    // 1: force every layer fully transparent, so the composite must be exactly
    // the background. Used by the datapath task.
    parameter bit FV_ALL_TRANSPARENT = 1'b0,

    // 1: hold every layer's pixel data and the background at zero.
    //
    // This is a proof-cost knob and nothing else, and it is only sound for
    // properties that do not look at pixel values. The framing check in
    // fv_core_frame.sv is one: it reads TUSER, TLAST and the handshakes, and
    // never a pixel. Freeing the pixel data there costs the solver the entire
    // blend cascade -- 24 bits of accumulator and 24 of operand per layer per
    // lane, unrolled once per BMC step -- for properties that cannot observe
    // any of it, and the frame task did not finish in two minutes with it on.
    //
    // The datapath task leaves this OFF, deliberately: free pixel data behind
    // a zero alpha is exactly what that task is checking.
    parameter bit FV_CONST_PIXELS = 1'b0,

    // 1: check the bounded output-continuity assertion below. It is a BMC
    // result and cannot be anything else -- see the comment on it -- so the
    // prove task turns it off rather than reporting an induction failure that
    // says nothing about the design.
    parameter bit FV_CHECK_LIVENESS = 1'b1,

    // Colour component width. The raster, the window compares, the flow
    // control and the error logic are all width-independent, so the invariant
    // tasks run at the narrowest; the datapath task is where the width is
    // actually part of the claim, because the composite it checks is built out
    // of blend_rgb at this width.
    parameter int P_CH_W = 8,

    // Derived; do not override.
    parameter int P_PX_W = 4 * P_CH_W,
    parameter int P_RGB_W = 3 * P_CH_W,
    parameter int P_PX_OUT_W = P_OUT_HAS_ALPHA ? P_PX_W : P_RGB_W,
    parameter int P_OUT_W = P_PPC * P_PX_OUT_W,
    parameter int P_BEAT_W = P_PPC * P_PX_W
) (
    input logic clk,

    // Free software.
    input logic                    ctrl_en_i,
    input logic                    ctrl_soft_rst,
    input logic [            15:0] canvas_width_i,
    input logic [            15:0] canvas_height_i,
    input logic [            23:0] background_rgb_i,
    input logic [            31:0] stall_limit_i,
    input logic [P_NUM_LAYERS-1:0] lay_en_i,
    input logic [             7:0] lay_alpha_i    [P_NUM_LAYERS],
    input logic [P_NUM_LAYERS-1:0] lay_alpha_src_i,
    input logic [            15:0] lay_x_i        [P_NUM_LAYERS],
    input logic [            15:0] lay_y_i        [P_NUM_LAYERS],
    input logic [            15:0] lay_w_i        [P_NUM_LAYERS],
    input logic [            15:0] lay_h_i        [P_NUM_LAYERS],

    // Free sources.
    input logic [P_NUM_LAYERS-1:0] s_axis_tvalid,
    input logic [    P_BEAT_W-1:0] s_axis_tdata [P_NUM_LAYERS],
    input logic [P_NUM_LAYERS-1:0] s_axis_tuser,
    input logic [P_NUM_LAYERS-1:0] s_axis_tlast,

    // Free sink.
    input logic m_axis_tready
);
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Modelled reset
  //
  // One cycle, for the reason in fv_fifo.sv. SOFT_RST is free above, and the
  // core folds `!rst_n || soft_rst` into the same expression nearly
  // everywhere, so pinning hardware reset does not cost mid-stream reset
  // coverage.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic rst_n;
  logic fv_in_reset = 1'b1;
  always_ff @(posedge clk) fv_in_reset <= 1'b0;
  assign rst_n = !fv_in_reset;

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Configuration presented to the core
  //
  // Either the free inputs passed straight through, or a latched copy that
  // never changes again. FV_STATIC_CFG picks, and the latch is the
  // self-holding-register idiom: written only while in reset, so afterwards it
  // holds an arbitrary but fixed value.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic                    ctrl_en;
  logic [            15:0] canvas_width, canvas_height;
  logic [            23:0] background_rgb;
  logic [            31:0] stall_limit;
  logic [P_NUM_LAYERS-1:0] lay_en;
  logic [             7:0] lay_alpha                   [P_NUM_LAYERS];
  logic [P_NUM_LAYERS-1:0] lay_alpha_src;
  logic [            15:0] lay_x                       [P_NUM_LAYERS];
  logic [            15:0] lay_y                       [P_NUM_LAYERS];
  logic [            15:0] lay_w                       [P_NUM_LAYERS];
  logic [            15:0] lay_h                       [P_NUM_LAYERS];

  if (FV_STATIC_CFG) begin : g_static_cfg
    logic                    q_en;
    logic [            15:0] q_cw, q_ch;
    logic [            23:0] q_bg;
    logic [            31:0] q_sl;
    logic [P_NUM_LAYERS-1:0] q_lay_en;
    logic [             7:0] q_alpha         [P_NUM_LAYERS];
    logic [P_NUM_LAYERS-1:0] q_asrc;
    logic [            15:0] q_x             [P_NUM_LAYERS];
    logic [            15:0] q_y             [P_NUM_LAYERS];
    logic [            15:0] q_w             [P_NUM_LAYERS];
    logic [            15:0] q_h             [P_NUM_LAYERS];

    always_ff @(posedge clk) begin
      if (fv_in_reset) begin
        q_en     <= ctrl_en_i;
        q_cw     <= canvas_width_i;
        q_ch     <= canvas_height_i;
        q_bg     <= background_rgb_i;
        q_sl     <= stall_limit_i;
        q_lay_en <= lay_en_i;
        q_asrc   <= lay_alpha_src_i;
        for (int i = 0; i < P_NUM_LAYERS; i++) begin
          q_alpha[i] <= lay_alpha_i[i];
          q_x[i]     <= lay_x_i[i];
          q_y[i]     <= lay_y_i[i];
          q_w[i]     <= lay_w_i[i];
          q_h[i]     <= lay_h_i[i];
        end
      end
    end

    assign ctrl_en        = q_en;
    assign canvas_width   = q_cw;
    assign canvas_height  = q_ch;
    assign background_rgb = q_bg;
    assign stall_limit    = q_sl;
    assign lay_en         = q_lay_en;
    assign lay_alpha_src  = q_asrc;
    assign lay_alpha      = q_alpha;
    assign lay_x          = q_x;
    assign lay_y          = q_y;
    assign lay_w          = q_w;
    assign lay_h          = q_h;
  end else begin : g_live_cfg
    assign ctrl_en        = ctrl_en_i;
    assign canvas_width   = canvas_width_i;
    assign canvas_height  = canvas_height_i;
    assign background_rgb = background_rgb_i;
    assign stall_limit    = stall_limit_i;
    assign lay_en         = lay_en_i;
    assign lay_alpha_src  = lay_alpha_src_i;
    assign lay_alpha      = lay_alpha_i;
    assign lay_x          = lay_x_i;
    assign lay_y          = lay_y_i;
    assign lay_w          = lay_w_i;
    assign lay_h          = lay_h_i;
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // DUT
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic                    status_frame_active;
  logic [            31:0] frame_count;
  logic                    err_cfg_set, err_starve_set, err_geom_set;
  logic                    err_src_stall_set, err_out_stall_set;
  logic [P_NUM_LAYERS-1:0] err_layer_set;
  logic [P_NUM_LAYERS-1:0] lay_armed, lay_dropped, lay_cfg_bad;
  logic [            15:0] lay_level                       [P_NUM_LAYERS];
  logic [P_NUM_LAYERS-1:0] s_axis_tready;
  logic                    m_axis_tvalid, m_axis_tuser, m_axis_tlast;
  logic [     P_OUT_W-1:0] m_axis_tdata;

  axis_video_mixer_core #(
      .P_NUM_LAYERS   (P_NUM_LAYERS),
      .P_FIFO_DEPTH   (P_FIFO_DEPTH),
      .P_OUT_HAS_ALPHA(P_OUT_HAS_ALPHA),
      .P_PPC          (P_PPC),
      .P_CH_W         (P_CH_W)
  ) dut (
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
      .s_axis_tdata (s_axis_tdata),
      .s_axis_tuser (s_axis_tuser),
      .s_axis_tlast (s_axis_tlast),

      .m_axis_tvalid(m_axis_tvalid),
      .m_axis_tready(m_axis_tready),
      .m_axis_tdata (m_axis_tdata),
      .m_axis_tuser (m_axis_tuser),
      .m_axis_tlast (m_axis_tlast)
  );

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Environment assumptions
  //
  // There are no behavioural assumptions here at all -- no polite sources, no
  // sink that eventually accepts, no software that writes sensible values. The
  // only constraints are magnitude bounds on the configuration registers, and
  // those exist to keep the proofs finishable rather than to make any property
  // true.
  //
  // In particular nothing assumes the configuration is legal. A zero canvas, a
  // misaligned window, a window hanging off the canvas: all reachable, and all
  // things the core has to reject rather than draw.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Per-layer constraints go in a GENERATE loop, not a procedural one. A
  // labelled assumption inside `for (int i = ...)` inside always_ff unrolls
  // into several checks that all carry the same name, and yosys-slang then
  // dies on a duplicate cell name -- "Assert `count_id(cell->name) == 0'
  // failed in kernel/rtlil.cc". A genvar loop gives each one its own scope and
  // its own name. Worth knowing: the failure is an internal assertion in the
  // tool, with no hint that a label is the cause.
  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_assume
    always_ff @(posedge clk) begin
      m_window_bounded : assume ((lay_x_i[gi] <= 16'(FV_MAX_DIM)) &&
                                 (lay_y_i[gi] <= 16'(FV_MAX_DIM)) &&
                                 (lay_w_i[gi] <= 16'(FV_MAX_DIM)) &&
                                 (lay_h_i[gi] <= 16'(FV_MAX_DIM)));

      if (FV_ALL_TRANSPARENT) begin
        // The layer contributes nothing: global alpha zero, and ALPHA_SRC
        // selecting the global alpha alone. The layers stay enabled and keep
        // streaming, so the whole cascade is exercised and every stage must
        // still pass the accumulator through untouched.
        m_alpha_zero : assume (lay_alpha_i[gi] == 8'd0);
        m_alpha_src_global : assume (lay_alpha_src_i[gi] == ALPHA_GLOBAL_ONLY);
      end
    end
  end

  always_ff @(posedge clk) begin
    m_canvas_bounded : assume ((canvas_width_i <= 16'(FV_MAX_DIM)) &&
                               (canvas_height_i <= 16'(FV_MAX_DIM)));
    // The watchdogs are proved in fv_layer.sby and by a_out_stall_bounded;
    // here a large threshold would only mean the stall counters never do
    // anything, and a small one keeps them in range of the BMC depth.
    m_stall_bounded : assume (stall_limit_i <= 32'd3);

    if (FV_CONST_PIXELS) begin
      m_bg_zero : assume (background_rgb_i == 24'd0);
    end
  end

  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_const_px
    if (FV_CONST_PIXELS) begin : g_on
      always_ff @(posedge clk) begin
        m_pixels_zero : assume (s_axis_tdata[gi] == '0);
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Liveness, bounded
  //
  // Every safety property above is happy with a core that never emits
  // anything, and the cover statements only show that output is possible on
  // some run. This says something stronger on the runs that matter: with the
  // mixer enabled, a valid canvas, and a sink that always accepts, a beat
  // comes out every cycle once the pipeline has filled -- no layer, in any
  // state, can introduce a bubble.
  //
  // That is the positive form of "the output never stalls on an input", and it
  // is the property a starving source would break if the design dropped the
  // layer by stalling the raster instead of by dropping the layer.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  localparam int LP_PIPE_DEPTH = P_NUM_LAYERS + 2;

  logic [7:0] fv_run_cycles;
  logic       fv_running;

  assign fv_running = rst_n && !ctrl_soft_rst && ctrl_en && dut.act_ok && m_axis_tready;

  always_ff @(posedge clk) begin
    if (!rst_n || !fv_running) begin
      fv_run_cycles <= 8'd0;
    end else if (fv_run_cycles != 8'hFF) begin
      fv_run_cycles <= fv_run_cycles + 8'd1;
    end
  end

  if (FV_CHECK_LIVENESS) begin : g_liveness
    always_ff @(posedge clk) begin
      // Once the pipeline has had time to fill under those conditions, output
      // is continuous. LP_PIPE_DEPTH is the fill time: stage F, stage A, and
      // one stage per layer.
      if (fv_running && (fv_run_cycles > 8'(LP_PIPE_DEPTH))) begin
        a_output_continuous : assert (m_axis_tvalid);
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst_n) begin
      c_pipeline_full : cover (fv_run_cycles > 8'(LP_PIPE_DEPTH) && m_axis_tvalid);
      c_continuous_while_starving : cover (fv_run_cycles > 8'(LP_PIPE_DEPTH) && m_axis_tvalid &&
                                           (|dut.starve));
    end
  end

endmodule
