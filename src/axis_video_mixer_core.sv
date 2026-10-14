`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: axis_video_mixer_core.sv
// Author  : Benjamin Tamayo
// Date    : 09/06/2026
// Purpose : Datapath of the AXI4-Stream video mixer. Walks an output raster and
//           composites P_NUM_LAYERS input streams onto a background colour.
//
//           The output is the master, not the inputs. A raster counter free-runs
//           across the canvas and, at each pixel, asks every layer whose window
//           covers that pixel for one pixel. That inversion is what makes
//           picture-in-picture and tiling work from plain AXI4-Stream: layers
//           need no relationship to each other or to the output beyond their
//           own rectangle, and none of them has to span the canvas.
//
//           Composition is Porter-Duff "over" in port order, layer 0 nearest the
//           background. Fixed order rather than programmable keeps this a
//           straight pipelined cascade instead of a crossbar; z-order is chosen
//           by which stream is wired to which port.
//
//           Two properties are load bearing:
//
//           The output never stalls on an input. If a layer has no pixel ready
//           when its window opens, that layer is dropped for the remainder of
//           the frame, an error latches, and the raster carries on. A video sink
//           downstream loses lock if the stream pauses, so a starving source
//           must not be allowed to take the display down with it.
//
//           That is a statement about a frame in flight, not about when a frame
//           may start. CTRL.SYNC_START holds the raster at the top of a frame
//           until every enabled layer has a line buffered, which removes the
//           one case the drop rule handles badly: a window at the canvas origin
//           has no slack to fetch its first pixel, so it starves on beat zero
//           of every frame and never recovers. See "Soft start" below.
//
//           MULTI-PIXEL PER CLOCK. A beat carries P_PPC pixels, lane 0 in the
//           least significant bits. The raster counts BEATS across the canvas,
//           not pixels, and every layer's window is compared in beat units.
//
//           That works only because horizontal geometry is constrained to whole
//           beats -- canvas width, every layer x and every layer width must be
//           multiples of P_PPC, and the validation below rejects anything else
//           as ERR.CFG. With that, each output beat is entirely inside or
//           entirely outside each window, so the window test stays one compare
//           per layer per beat and a layer's beats line up with the output's
//           with no realignment. The blend is then simply P_PPC copies of the
//           same cascade sharing one set of control signals.
//
//           At P_PPC = 1 the constraint is vacuous, so the block behaves exactly
//           as it did before. See doc/design.md section 10 for what relaxing it
//           costs.
//
//           COMPONENT WIDTH. A colour component is P_CH_W bits -- 8, 10, 12 or
//           16 -- so a pixel is 4*P_CH_W bits and a beat is P_PPC of those. The
//           width reaches almost nothing here except as a vector size: the
//           blend arithmetic lives in the package and takes the width as an
//           argument, and the raster, the window compares and the flow control
//           never look inside a pixel at all.
//
//           Two things do change. The blend divides by 2**P_CH_W - 1 rather
//           than by 255, because full scale is what an alpha of "opaque" has to
//           be, and the two register fields that are expressed in 8 bits
//           whatever the component width -- L<i>_CTRL.ALPHA and BACKGROUND.RGB
//           -- are expanded to the component width as they are latched. Both
//           belong to the package; see ch_up and rgb_up there for why the
//           registers stay 8 bits.
//
//           Geometry is double buffered. Position, size, enable and alpha are
//           latched at a frame boundary and only there, so software can move a
//           window whenever it likes without tearing the frame in flight.
//           Changing a layer's geometry costs that layer one frame: it flushes
//           and re-arms at its next input SOF, because everything buffered was
//           counted against the old size.
///////////////////////////////////////////////////////////////////

module axis_video_mixer_core
  import axis_video_mixer_pkg::*;
#(
    parameter int P_NUM_LAYERS = 4,
    parameter int P_FIFO_DEPTH = 2048,
    parameter string P_RAM_STYLE = "block",
    parameter bit P_OUT_HAS_ALPHA = 1'b1,
    parameter int P_PPC = 1,
    parameter int P_CH_W = 8,
    // Derived; do not override. Present as parameters only because a port width
    // cannot reference a localparam declared in the module body.
    parameter int P_PX_W = 4 * P_CH_W,
    parameter int P_RGB_W = 3 * P_CH_W,
    parameter int P_PX_OUT_W = P_OUT_HAS_ALPHA ? P_PX_W : P_RGB_W,
    parameter int P_OUT_W = P_PPC * P_PX_OUT_W,
    parameter int P_BEAT_W = P_PPC * P_PX_W
) (
    input logic clk,
    input logic rst_n,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Shadow configuration, straight from the register block
    ////////////////////////////////////////////////////////////////////////////////////////////////
    input logic                    ctrl_en,
    input logic                    ctrl_soft_rst,
    // Hold the output off until every enabled layer has a line buffered. See
    // "Soft start" below.
    input logic                    ctrl_sync_start,
    input logic [            31:0] sync_timeout,
    input logic [            15:0] canvas_width,
    input logic [            15:0] canvas_height,
    input logic [            23:0] background_rgb,
    input logic [            31:0] stall_limit,
    input logic [P_NUM_LAYERS-1:0]       lay_en,
    // Per-layer signals are PACKED ARRAYS, not flat vectors: the layer is the
    // first dimension, so lay_x[i] is layer i and the bit arithmetic stays out
    // of the datapath. See the note on packing below.
    input logic [P_NUM_LAYERS-1:0][ 7:0] lay_alpha,
    input logic [P_NUM_LAYERS-1:0]       lay_alpha_src,
    input logic [P_NUM_LAYERS-1:0][15:0] lay_x,
    input logic [P_NUM_LAYERS-1:0][15:0] lay_y,
    input logic [P_NUM_LAYERS-1:0][15:0] lay_w,
    input logic [P_NUM_LAYERS-1:0][15:0] lay_h,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Status and error strobes back to the register block
    ////////////////////////////////////////////////////////////////////////////////////////////////
    output logic                    status_frame_active,
    output logic                    status_sync_wait,
    output logic [            31:0] frame_count,
    output logic                    err_cfg_set,
    output logic                    err_sync_to_set,
    output logic                    err_starve_set,
    output logic                    err_geom_set,
    output logic                    err_src_stall_set,
    output logic                    err_out_stall_set,
    output logic [P_NUM_LAYERS-1:0] err_layer_set,
    output logic [P_NUM_LAYERS-1:0] lay_armed,
    output logic [P_NUM_LAYERS-1:0] lay_dropped,
    output logic [P_NUM_LAYERS-1:0] lay_cfg_bad,
    output logic [P_NUM_LAYERS-1:0][15:0] lay_level,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Layer input streams, RGBA with a P_CH_W-bit component
    ////////////////////////////////////////////////////////////////////////////////////////////////
    input  logic [P_NUM_LAYERS-1:0] s_axis_tvalid,
    output logic [P_NUM_LAYERS-1:0] s_axis_tready,
    input  logic [P_NUM_LAYERS-1:0][P_BEAT_W-1:0] s_axis_tdata,
    input  logic [P_NUM_LAYERS-1:0] s_axis_tuser,
    input  logic [P_NUM_LAYERS-1:0] s_axis_tlast,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Composited output stream
    ////////////////////////////////////////////////////////////////////////////////////////////////
    output logic               m_axis_tvalid,
    input  logic               m_axis_tready,
    output logic [P_OUT_W-1:0] m_axis_tdata,
    output logic               m_axis_tuser,   // SOF
    output logic               m_axis_tlast    // EOL
);
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Local parameters
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Pixels-to-beats is a shift because P_PPC is a power of two, and the mask is
  // how alignment is tested. At P_PPC = 1 the mask is zero, so every alignment
  // check below is trivially true and the constraint does not exist.
  localparam int          LP_LOG2_PPC = $clog2(P_PPC);
  localparam logic [15:0] LP_PPC_MASK = 16'(P_PPC - 1);

  // Full scale for one component: what "opaque" means, and what the blend
  // divides by.
  localparam logic [P_CH_W-1:0] LP_OPAQUE = {P_CH_W{1'b1}};

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Active configuration
  //
  // "Shadow" is what software has written; "active" is what this frame is being
  // drawn with. The two are only ever equalised at a frame boundary.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [15:0] act_w, act_h;
  logic [     P_RGB_W-1:0] act_bg;  // expanded to the component width
  logic                    act_ok;  // the active canvas is usable

  logic [P_NUM_LAYERS-1:0]              act_en;
  logic [P_NUM_LAYERS-1:0][P_CH_W-1:0] act_alpha;
  logic [P_NUM_LAYERS-1:0]              act_asrc;
  logic [P_NUM_LAYERS-1:0][      15:0] act_x;
  logic [P_NUM_LAYERS-1:0][      15:0] act_y;
  logic [P_NUM_LAYERS-1:0][      15:0] act_w_l;
  logic [P_NUM_LAYERS-1:0][      15:0] act_h_l;
  // Window ends precomputed at the latch, so the per-beat compare is a
  // magnitude comparison rather than an adder followed by one.
  //
  // The horizontal pair are in BEATS; the vertical pair stay in lines, because
  // there is no vertical packing. Converting once at the latch keeps the shift
  // out of the per-beat path.
  logic [P_NUM_LAYERS-1:0][15:0] act_bx;
  logic [P_NUM_LAYERS-1:0][16:0] act_bxe;
  logic [P_NUM_LAYERS-1:0][16:0] act_ye;
  logic [P_NUM_LAYERS-1:0][15:0] act_bw_l;
  logic [                 15:0] act_bw;  // canvas width in beats

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Shadow validation
  //
  // Checked against what software wrote, not against what is active, because
  // the point is to refuse the new value before it ever becomes active. A
  // rejected configuration leaves the previous good one running.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic                    canvas_ok;
  logic [P_NUM_LAYERS-1:0] win_ok;
  logic [P_NUM_LAYERS-1:0] want_en;
  logic                    cfg_fault;

  // Horizontal geometry must be a whole number of beats. Rejecting rather than
  // rounding is deliberate: silently snapping a window to a beat boundary would
  // put the picture somewhere the register does not say, and the difference is
  // up to P_PPC-1 pixels of unexplained offset. CAPS.PPC tells software what
  // the granularity is so it can round before writing, and ERR.CFG says so when
  // it did not.
  assign canvas_ok = (canvas_width != 16'd0) && (canvas_height != 16'd0) &&
                     ((canvas_width & LP_PPC_MASK) == 16'd0);

  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_validate
    assign win_ok[gi] = (lay_w[gi] != 16'd0) && (lay_h[gi] != 16'd0) &&
                        ((lay_x[gi] & LP_PPC_MASK) == 16'd0) &&
                        ((lay_w[gi] & LP_PPC_MASK) == 16'd0) &&
                        ((17'(lay_x[gi]) + 17'(lay_w[gi])) <= 17'(canvas_width)) &&
                        ((17'(lay_y[gi]) + 17'(lay_h[gi])) <= 17'(canvas_height));
    // A layer only counts as enabled once its window is also legal.
    assign want_en[gi] = lay_en[gi] && win_ok[gi] && canvas_ok;
    assign lay_cfg_bad[gi] = lay_en[gi] && !(win_ok[gi] && canvas_ok);
  end

  assign cfg_fault = !canvas_ok || (|lay_cfg_bad);

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Output raster
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // out_bx is the BEAT index across the canvas, so it runs 0 .. act_bw-1.
  // Lane j of the beat is canvas pixel (out_bx * P_PPC + j), which is why
  // nothing below ever needs the pixel-domain x.
  logic [15:0] out_bx, out_y;
  logic s0_valid, s0_sof, s0_eol, s0_eof;
  logic pipe_en;
  logic frame_boundary;
  logic frame_latch;
  logic soft_rst;

  assign soft_rst = ctrl_soft_rst;

  // sync_wait is the soft-start gate. It is declared with the rest of the
  // soft-start logic below; only its effect belongs here.
  logic sync_wait;

  assign s0_valid = ctrl_en && act_ok && !sync_wait;
  assign s0_sof   = (out_bx == 16'd0) && (out_y == 16'd0);
  assign s0_eol   = (out_bx == act_bw - 16'd1);
  assign s0_eof   = s0_eol && (out_y == act_h - 16'd1);

  // Latch at the end of a frame -- and also whenever there is no frame to
  // protect. Double buffering exists to stop a mid-frame change from tearing
  // the picture; while the mixer is disabled or has no valid configuration
  // there is no picture, and holding changes back would be worse than useless.
  //
  // The !ctrl_en term is what makes the natural software order work at all.
  // A disabled mixer does not advance its raster, so it never reaches a frame
  // boundary; without this, a canvas written before EN was set could never
  // take effect, and the block would silently keep drawing at its reset size.
  // sync_wait joins !ctrl_en and !act_ok for the same reason they are there:
  // while the gate is shut there is no frame in flight to tear, so holding
  // configuration back would be worse than useless. It is also load bearing --
  // a layer has to be able to go active while the gate is shut, and only a
  // latch does that.
  assign frame_boundary = soft_rst || (pipe_en && s0_valid && s0_eof);
  assign frame_latch    = frame_boundary || !act_ok || !ctrl_en || sync_wait;

  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst || !ctrl_en) begin
      out_bx <= 16'd0;
      out_y  <= 16'd0;
    end else if (pipe_en && s0_valid) begin
      if (s0_eol) begin
        out_bx <= 16'd0;
        out_y  <= s0_eof ? 16'd0 : (out_y + 16'd1);
      end else begin
        out_bx <= out_bx + 16'd1;
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Frame-boundary latch
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [P_NUM_LAYERS-1:0] geo_changed;

  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_geo_change
    // Alpha is deliberately excluded: it changes the blend but not the pixel
    // accounting, so it can take effect without costing the layer a frame.
    assign geo_changed[gi] = (act_x[gi] != lay_x[gi]) || (act_y[gi] != lay_y[gi]) ||
                             (act_w_l[gi] != lay_w[gi]) || (act_h_l[gi] != lay_h[gi]) ||
                             (act_en[gi] != want_en[gi]);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      act_ok <= 1'b0;
      act_w <= 16'd0;
      act_bw <= 16'd0;
      act_h <= 16'd0;
      act_bg <= '0;
      act_en <= '0;
      act_asrc <= '0;
      for (int i = 0; i < P_NUM_LAYERS; i++) begin
        act_alpha[i] <= '0;
        act_x[i]     <= 16'd0;
        act_y[i]     <= 16'd0;
        act_w_l[i]   <= 16'd0;
        act_h_l[i]   <= 16'd0;
        act_bx[i]    <= 16'd0;
        act_bw_l[i]  <= 16'd0;
        act_bxe[i]   <= 17'd0;
        act_ye[i]    <= 17'd0;
      end
    end else if (frame_latch) begin
      // A rejected canvas leaves the last good one in place rather than
      // stopping the output; ERR.CFG records that it was rejected.
      if (canvas_ok) begin
        act_w  <= canvas_width;
        act_bw <= canvas_width >> LP_LOG2_PPC;
        act_h  <= canvas_height;
        act_ok <= 1'b1;
      end
      act_bg   <= P_RGB_W'(rgb_up(P_CH_W, background_rgb));
      act_en   <= want_en;
      act_asrc <= lay_alpha_src;
      for (int i = 0; i < P_NUM_LAYERS; i++) begin
        act_alpha[i] <= P_CH_W'(ch_up(P_CH_W, lay_alpha[i]));
        act_x[i]     <= lay_x[i];
        act_y[i]     <= lay_y[i];
        act_w_l[i]   <= lay_w[i];
        act_h_l[i]   <= lay_h[i];
        // Both are exact shifts: a window that is not beat aligned never gets
        // here, because want_en is false for it and the latch below stores it
        // disabled.
        act_bx[i]    <= lay_x[i] >> LP_LOG2_PPC;
        act_bw_l[i]  <= lay_w[i] >> LP_LOG2_PPC;
        act_bxe[i]   <= 17'(lay_x[i] >> LP_LOG2_PPC) + 17'(lay_w[i] >> LP_LOG2_PPC);
        act_ye[i]    <= 17'(lay_y[i]) + 17'(lay_h[i]);
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Layer front ends
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [P_NUM_LAYERS-1:0][P_BEAT_W-1:0] lay_px;
  logic [P_NUM_LAYERS-1:0] lay_px_valid;
  logic [P_NUM_LAYERS-1:0] lay_pop;
  logic [P_NUM_LAYERS-1:0] lay_flush;
  logic [P_NUM_LAYERS-1:0] lay_geom_err;
  logic [P_NUM_LAYERS-1:0] lay_src_stall;

  logic [P_NUM_LAYERS-1:0] in_win;
  logic [P_NUM_LAYERS-1:0] want_px;
  logic [P_NUM_LAYERS-1:0] starve;
  logic [P_NUM_LAYERS-1:0] lay_active;

  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_layer
    axis_mixer_layer #(
        .P_FIFO_DEPTH(P_FIFO_DEPTH),
        .P_RAM_STYLE (P_RAM_STYLE),
        .P_PPC       (P_PPC),
        .P_CH_W      (P_CH_W)
    ) u_layer (
        .clk          (clk),
        .rst_n        (rst_n),
        .flush        (lay_flush[gi]),
        .enable       (act_en[gi]),
        .cfg_w_beats  (act_bw_l[gi]),
        .cfg_height   (act_h_l[gi]),
        .stall_limit  (stall_limit),
        .s_axis_tvalid(s_axis_tvalid[gi]),
        .s_axis_tready(s_axis_tready[gi]),
        .s_axis_tdata (s_axis_tdata[gi]),
        .s_axis_tuser (s_axis_tuser[gi]),
        .s_axis_tlast (s_axis_tlast[gi]),
        .px_data      (lay_px[gi]),
        .px_valid     (lay_px_valid[gi]),
        .px_pop       (lay_pop[gi]),
        .armed        (lay_armed[gi]),
        .geom_err     (lay_geom_err[gi]),
        .src_stall    (lay_src_stall[gi]),
        .level        (lay_level[gi])
    );

    // One compare per layer per BEAT, not per lane. That is the whole payoff of
    // the beat-alignment constraint: because a window starts and ends on a beat
    // boundary, every lane of a given beat is inside or outside together, so
    // there is nothing per-lane to decide.
    assign in_win[gi] = act_en[gi] && (17'(out_bx) >= 17'(act_bx[gi])) &&
                        (17'(out_bx) < act_bxe[gi]) && (17'(out_y) >= 17'(act_y[gi])) &&
                        (17'(out_y) < act_ye[gi]);

    // Note lay_active, not lay_armed. A layer joins the composite only at a
    // frame boundary, never in the middle of one -- see the comment on
    // lay_active below for why that is a correctness requirement rather than
    // a nicety.
    //
    // A layer that has not yet seen its first SOF is simply absent, not
    // starving. Treating "no stream connected yet" as an error would latch a
    // fault on every frame between power-on and the first source coming up.
    assign want_px[gi] = in_win[gi] && lay_active[gi] && !lay_dropped[gi];

    assign lay_pop[gi] = want_px[gi] && lay_px_valid[gi] && pipe_en && s0_valid;
    assign starve[gi] = want_px[gi] && !lay_px_valid[gi] && pipe_en && s0_valid;

    // A starved layer is desynchronised by definition -- the pixels still in its
    // FIFO belong to positions the raster has already passed -- so it is flushed
    // and re-armed rather than simply skipped.
    assign lay_flush[gi] = soft_rst || starve[gi] || (frame_latch && geo_changed[gi]);
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Joining the composite
  //
  // A layer becomes active only at a frame boundary, even though it arms as
  // soon as its stream delivers a SOF. The delay is what establishes alignment
  // between the layer's frame and the output's.
  //
  // Nothing else would. The mixer consumes a layer positionally -- one pixel
  // per output pixel inside the window -- so wherever the first pixel is
  // consumed is where the layer's top-left corner lands. A layer that armed
  // part way through an output frame would have its pixel zero consumed part
  // way along a line, and because it then supplies exactly as many pixels per
  // frame as the window consumes, that offset would never work itself out: the
  // layer would sit skewed by a fixed number of pixels for as long as it ran.
  //
  // Holding off until the boundary guarantees the FIFO head is pixel zero when
  // the window first opens, because nothing pops an inactive layer.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      lay_active <= '0;
    end else begin
      for (int i = 0; i < P_NUM_LAYERS; i++) begin
        if (frame_latch) begin
          // A layer being flushed this cycle is about to disarm, so it joins
          // at the following boundary rather than this one.
          lay_active[i] <= lay_armed[i] && want_en[i] && !lay_flush[i];
        end else if (starve[i] || lay_geom_err[i]) begin
          lay_active[i] <= 1'b0;
        end
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Dropped layers
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      lay_dropped <= '0;
    end else begin
      for (int i = 0; i < P_NUM_LAYERS; i++) begin
        if (starve[i]) lay_dropped[i] <= 1'b1;
      end
      // The clear is written after the sets, so a starve on the very last pixel
      // of a frame does not carry into the next one.
      if (frame_latch) lay_dropped <= '0;
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Soft start
  //
  // R6 says the output must never stall on an input, and it still does not: a
  // frame that has begun always completes at full rate whatever the sources do.
  // But R6 says nothing about when a frame may BEGIN, and that is the gap this
  // fills.
  //
  // Without it, "armed" is the only thing standing between a layer and the
  // composite, and armed means one beat has arrived -- not a frame's worth, not
  // a line's worth. A layer whose window touches the canvas origin needs its
  // first pixel on the first beat of the frame and has no slack whatever to go
  // and get it. If the source is not already ahead of the raster the layer
  // starves on beat zero, is dropped and flushed, re-arms at its next input
  // SOF, and does the same thing again on the next frame -- for ever, while
  // every register except ERR.STARVE looks healthy. See doc/design.md 13.4.
  //
  // So the gate holds the raster at the top of a frame until every enabled
  // layer has a full line buffered. Three things make that safe:
  //
  //   It gates only at a frame boundary. Re-closing mid-frame would stall the
  //   raster and break R6 outright, so sync_wait is only ever raised from
  //   reset or at frame_boundary.
  //
  //   The threshold is derived, not configured. One line of that layer is the
  //   sizing rule the FIFO was built to (5.6), so software cannot get it
  //   wrong, and it is capped at the buffer's capacity so an over-wide window
  //   cannot ask for more than could ever arrive and wedge the gate shut.
  //
  //   It is bounded. An enabled layer whose source never comes up would
  //   otherwise black the display out for ever, which is a far worse failure
  //   in the field than the skewed picture it was protecting against.
  //   SYNC_TIMEOUT caps the wait and latches ERR.SYNC_TO when it fires, so the
  //   degraded case is reached loudly rather than silently.
  //
  // CTRL.SYNC_START turns the whole thing off, which is the pre-soft-start
  // behaviour exactly: the gate is then never shut and s0_valid reduces to
  // ctrl_en && act_ok.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // The buffer holds P_FIFO_DEPTH beats, and level counts the prefetch register
  // on top of that, so a demand of P_FIFO_DEPTH is always reachable.
  localparam logic [15:0] LP_PREFILL_CAP = 16'(P_FIFO_DEPTH);

  logic [P_NUM_LAYERS-1:0] lay_prefilled;
  logic                    sync_hold;  // some enabled layer is still short of a line
  logic [            31:0] sync_cnt;
  logic                    sync_expired;
  // Sticky from the moment the timeout fires until every enabled layer is
  // genuinely prefilled again. Without it the gate re-shuts at the next frame
  // boundary, waits out the timeout again, and emits one frame per timeout --
  // so a source that never comes up turns a smooth background into a stutter,
  // which is worse than the thing being protected against. Measured at 8
  // frames in 4000 cycles before this existed.
  logic                    sync_gave_up;

  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_prefill
    logic [15:0] need;
    // act_bw_l is this layer's width in BEATS, which is what level counts.
    assign need = (act_bw_l[gi] > LP_PREFILL_CAP) ? LP_PREFILL_CAP : act_bw_l[gi];
    assign lay_prefilled[gi] = lay_armed[gi] && (lay_level[gi] >= need);
  end

  assign sync_hold = |(act_en & ~lay_prefilled);

  // Zero means wait indefinitely. The count only runs while the gate is
  // actually holding something up, so a disabled mixer does not burn its
  // patience before the sources have had a chance to start.
  assign sync_expired = (sync_timeout != 32'd0) && (sync_cnt >= sync_timeout - 32'd1);

  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      sync_cnt <= 32'd0;
    end else if (sync_wait && ctrl_en && act_ok && (sync_timeout != 32'd0)) begin
      // The sync_timeout term only stops a counter nobody is reading from
      // free-running and wrapping while the wait is indefinite. It changes no
      // behaviour: sync_expired is false at a timeout of zero either way.
      if (!sync_expired) sync_cnt <= sync_cnt + 32'd1;
    end else begin
      sync_cnt <= 32'd0;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      // Shut from reset, so the very first frame is already synchronised rather
      // than being the one frame nothing protects.
      sync_wait       <= 1'b1;
      err_sync_to_set <= 1'b0;
    end else begin
      err_sync_to_set <= 1'b0;
      if (!ctrl_sync_start) begin
        sync_wait <= 1'b0;
      end else if (sync_wait) begin
        // act_ok qualifies the opening because act_en is latched by the same
        // always_ff that sets act_ok. Before that first latch act_en is still
        // zero, sync_hold is therefore false, and without this term the gate
        // would open in the one cycle before the configuration it is supposed
        // to be waiting on even exists.
        if (act_ok && ctrl_en && (!sync_hold || sync_expired)) begin
          sync_wait       <= 1'b0;
          err_sync_to_set <= sync_hold && sync_expired;
        end
      end else if (frame_boundary && sync_hold && !sync_gave_up) begin
        sync_wait <= 1'b1;
      end
    end
  end

  // Clearing on !sync_hold rather than on armed is deliberate: the condition to
  // leave the given-up state is the same one that would have opened the gate in
  // the first place, so a source that recovers gets the gate back without
  // needing a soft reset.
  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst || !ctrl_en) begin
      sync_gave_up <= 1'b0;
    end else if (sync_wait && act_ok && ctrl_en && sync_hold && sync_expired) begin
      sync_gave_up <= 1'b1;
    end else if (!sync_hold) begin
      sync_gave_up <= 1'b0;
    end
  end

  assign status_sync_wait = sync_wait;

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Blend cascade
  //
  // Stage 0 registers the raster, the background and every layer's pixel and
  // effective alpha. Stage k+1 then blends layer k onto the accumulator, one
  // layer per pipeline stage, so the combinational depth is a single multiply
  // regardless of how many layers are instantiated.
  //
  // Effective alpha is computed once, in its own stage, rather than inside each
  // blend stage. Both are a multiply; doing them together would put two in
  // series and halve the achievable clock.
  //
  // That alpha stage is also kept clear of the FIFO read. A layer's pixel comes
  // out of a block RAM, and a BRAM's clock-to-output is most of a cycle at this
  // frequency -- feeding it straight into the multiply left fourteen levels of
  // logic in whatever remained, and cost 0.27 ns of setup slack at 148.5 MHz.
  // Stage F does nothing but capture the read; the arithmetic starts from a
  // flip-flop in stage A.
  //
  // A layer that is not contributing arrives with an alpha of zero, and "over"
  // with alpha zero returns the accumulator bit-exactly. Absence needs no
  // special case anywhere in the cascade.
  //
  // MULTI-PIXEL. The cascade is replicated P_PPC times and the copies are
  // completely independent -- lane j composites canvas pixel out_bx*P_PPC + j
  // and never looks at its neighbours. Everything they share is CONTROL:
  // valid, SOF, EOL, EOF, which layer is popped, and each layer's alpha.
  //
  // That is worth being explicit about, because it is what makes the area scale
  // linearly and predictably: P_PPC copies of the arithmetic, one copy of the
  // control. It also means the per-lane pipeline depth is unchanged, so P_PPC
  // costs area and not frequency.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // PACKED ARRAYS, not unpacked arrays and not flat vectors.
  //
  // Unpacked is out because XSIM will not plot an unpacked array in its
  // waveform window, and these are exactly the signals you need to see while
  // bringing the block up. A flat vector plots, but it costs the indexing: the
  // layer or the stage stops being a subscript and becomes bit arithmetic at
  // every use site, which is the datapath made harder to read in order to
  // satisfy a waveform viewer.
  //
  // A packed ARRAY is both. The layout is identical to the flat vector --
  // logic [N-1:0][W-1:0] x puts x[i] at bits [i*W +: W] -- so nothing about
  // the hardware changes, while x[i] and x[k][i][j] stay subscripts.
  //
  // Index order is [stage][layer][lane], outermost first, which reads the way
  // the pipeline runs.
  //
  // Stage F: the FIFO read, captured raw. No arithmetic here by design.
  //
  // pxf_q is [layer][lane]: one beat per layer, split into lanes here so that
  // nothing downstream has to work out which lane of which beat it wants.
  logic [P_NUM_LAYERS-1:0][P_PPC-1:0][P_PX_W-1:0] pxf_q;
  logic [P_NUM_LAYERS-1:0]                        popf_q;
  logic [P_NUM_LAYERS-1:0][     P_CH_W-1:0]       alphaf_q;
  logic [P_NUM_LAYERS-1:0]                        asrcf_q;
  logic [         P_RGB_W-1:0]                    bgf_q;
  logic vf_q, soff_q, eolf_q, eoff_q;

  // [stage][lane] for the accumulator, [stage][layer][lane] for the operands.
  logic [P_NUM_LAYERS:0][P_PPC-1:0][P_RGB_W-1:0] acc_q;
  logic [P_NUM_LAYERS:0][P_NUM_LAYERS-1:0][P_PPC-1:0][P_RGB_W-1:0] lrgb_q;
  logic [P_NUM_LAYERS:0][P_NUM_LAYERS-1:0][P_PPC-1:0][ P_CH_W-1:0] la_q;
  // Control is per stage only -- every lane of a beat shares it. One bit per
  // stage, so these are a plain vector.
  logic [P_NUM_LAYERS:0] v_q;
  logic [P_NUM_LAYERS:0] sof_q;
  logic [P_NUM_LAYERS:0] eol_q;
  logic [P_NUM_LAYERS:0] eof_q;

  assign pipe_en = m_axis_tready || !m_axis_tvalid;

  // Stage F -- capture only. The alpha and colour registers travel alongside the
  // pixel so that a frame boundary landing between the two stages cannot apply
  // the next frame's alpha to this frame's pixel.
  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      vf_q   <= 1'b0;
      popf_q <= '0;
    end else if (pipe_en) begin
      vf_q <= s0_valid;
      soff_q <= s0_sof;
      eolf_q <= s0_eol;
      eoff_q <= s0_eof;
      bgf_q <= act_bg;
      popf_q <= lay_pop;
      asrcf_q <= act_asrc;
      for (int i = 0; i < P_NUM_LAYERS; i++) begin
        alphaf_q[i] <= act_alpha[i];
        for (int j = 0; j < P_PPC; j++) begin
          pxf_q[i][j] <= lay_px[i][j*P_PX_W+:P_PX_W];
        end
      end
    end
  end

  // Stage A and the blend cascade, in ONE always_ff.
  //
  // They were two processes while these signals were unpacked arrays, because
  // stage A wrote element [0] and each cascade stage wrote element [k+1] --
  // different elements of an unpacked array, which is legal from different
  // processes. Packed, they are slices of one vector, and a vector needs
  // exactly one procedural owner. Verilator says so directly:
  //
  //     %Warning-MULTIDRIVEN: Variable written to in always_ff also written
  //                           by other process: 'acc_q'
  //
  // That warning is the polite version. The impolite version is Verilator
  // accepting per-stage generate processes and silently dropping their writes,
  // with no warning at all, which is the trap in doc/design.md 11.7.
  //
  // So: one process, stage A first, then an unrolled loop over the stages. The
  // loop bound is constant, so this is the same flops and the same logic depth
  // -- one multiply per stage -- as the generate loop it replaces.
  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      v_q <= '0;
    end else if (pipe_en) begin
      v_q[0]   <= vf_q;
      sof_q[0] <= soff_q;
      eol_q[0] <= eolf_q;
      eof_q[0] <= eoff_q;
      // Every lane starts from the same background: it is a canvas-wide colour,
      // not a per-pixel one.
      for (int j = 0; j < P_PPC; j++) acc_q[0][j] <= bgf_q;
      for (int i = 0; i < P_NUM_LAYERS; i++) begin
        for (int j = 0; j < P_PPC; j++) begin
          // The package works in its maximum container widths, so every call
          // zero-extends on the way in and truncates on the way out. Both are
          // exact: a P_CH_W-bit value in a wider container is the same number,
          // and the result cannot exceed P_CH_W bits.
          lrgb_q[0][i][j] <=
              P_RGB_W'(px_rgb(P_CH_W, PX_MAX_W'(pxf_q[i][j])));
          // popf_q is per LAYER, not per lane -- a beat-aligned window pops all
          // P_PPC lanes of a layer together or none of them.
          la_q[0][i][j] <= popf_q[i] ?
              P_CH_W'(effective_alpha(P_CH_W, px_a(P_CH_W, PX_MAX_W'(pxf_q[i][j])),
                                      CH_MAX_W'(alphaf_q[i]), asrcf_q[i])) : '0;
        end
      end

      // The cascade. Stage k+1 blends layer k onto the accumulator.
      for (int k = 0; k < P_NUM_LAYERS; k++) begin
        v_q[k+1]   <= v_q[k];
        sof_q[k+1] <= sof_q[k];
        eol_q[k+1] <= eol_q[k];
        eof_q[k+1] <= eof_q[k];
        // P_PPC independent blends, one per lane, all of layer k.
        for (int j = 0; j < P_PPC; j++) begin
          acc_q[k+1][j] <=
              P_RGB_W'(blend_rgb(P_CH_W, RGB_MAX_W'(lrgb_q[k][k][j]),
                                 RGB_MAX_W'(acc_q[k][j]),
                                 CH_MAX_W'(la_q[k][k][j])));
        end
        // Only entries at or above k are still needed downstream; the rest form
        // a chain to nowhere and are trimmed during synthesis.
        for (int i = 0; i < P_NUM_LAYERS; i++) begin
          for (int j = 0; j < P_PPC; j++) begin
            lrgb_q[k+1][i][j] <= lrgb_q[k][i][j];
            la_q[k+1][i][j]      <= la_q[k][i][j];
          end
        end
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Output
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  assign m_axis_tvalid = v_q[P_NUM_LAYERS];
  assign m_axis_tuser  = sof_q[P_NUM_LAYERS];
  assign m_axis_tlast  = eol_q[P_NUM_LAYERS];

  // Lane 0 in the least significant bits, matching the input convention.
  for (genvar gj = 0; gj < P_PPC; gj++) begin : g_out_lane
    if (P_OUT_HAS_ALPHA) begin : g_rgba
      // Everything below the top layer has been composited in, so the result is
      // opaque by construction.
      assign m_axis_tdata[gj*P_PX_OUT_W+:P_PX_OUT_W] =
          {acc_q[P_NUM_LAYERS][gj], LP_OPAQUE};
    end else begin : g_rgb
      assign m_axis_tdata[gj*P_PX_OUT_W+:P_PX_OUT_W] = acc_q[P_NUM_LAYERS][gj];
    end
  end

  logic out_beat;
  assign out_beat = m_axis_tvalid && m_axis_tready;

  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      frame_count         <= 32'd0;
      status_frame_active <= 1'b0;
    end else begin
      if (out_beat && eof_q[P_NUM_LAYERS]) frame_count <= frame_count + 32'd1;
      if (out_beat) begin
        if (sof_q[P_NUM_LAYERS]) status_frame_active <= 1'b1;
        else if (eof_q[P_NUM_LAYERS]) status_frame_active <= 1'b0;
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Downstream stall watchdog
  //
  // The mirror of the per-layer source watchdog. Between them, a stuck
  // FRAME_COUNT can be attributed to the right side of the pipeline instead of
  // being merely observed.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [31:0] out_stall_cnt;

  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      out_stall_cnt     <= 32'd0;
      err_out_stall_set <= 1'b0;
    end else begin
      err_out_stall_set <= 1'b0;
      if (m_axis_tvalid && !m_axis_tready) begin
        if (stall_limit != 32'd0 && out_stall_cnt == stall_limit - 32'd1) begin
          err_out_stall_set <= 1'b1;
          out_stall_cnt     <= 32'd0;
        end else begin
          out_stall_cnt <= out_stall_cnt + 32'd1;
        end
      end else begin
        out_stall_cnt <= 32'd0;
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Error aggregation
  //
  // ERR.CFG latches once per frame boundary rather than continuously. A level
  // would keep re-setting the bit -- corsair gives the hardware set priority
  // over the software clear, by design, so an error is never lost -- and
  // software could then never clear it while the bad value remained. Once per
  // frame stays clearable, and the live view is in L<i>_STATUS.CFG_BAD.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  assign err_cfg_set       = frame_boundary && cfg_fault;
  assign err_starve_set    = |starve;
  assign err_geom_set      = |lay_geom_err;
  assign err_src_stall_set = |lay_src_stall;

  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_err_layer
    assign err_layer_set[gi] = starve[gi] || lay_geom_err[gi] || lay_src_stall[gi] ||
                               (frame_boundary && lay_cfg_bad[gi]);
  end

`ifdef SIMULATION
  // Procedural rather than concurrent, for the reason set out in
  // axis_mixer_fifo.sv: both properties below are functions of combinational
  // signals, and XSIM evaluates concurrent assertions on those before the
  // network resettles. Sampling at the clock edge checks what the hardware
  // actually sees.
  logic [15:0] chk_prev_x, chk_prev_y;
  logic               chk_raster_armed;

  logic [P_OUT_W-1:0] chk_prev_tdata;
  logic chk_prev_tuser, chk_prev_tlast;
  logic chk_was_stalled;

  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      chk_raster_armed <= 1'b0;
      chk_was_stalled  <= 1'b0;
    end else begin
      // The whole point of the starve handling is that the output keeps
      // running. If the raster ever stops advancing while enabled and
      // unstalled, the design has failed at its primary job. A 1x1 canvas is
      // excluded because its counters legitimately never change.
      if (chk_raster_armed && (out_bx == chk_prev_x) && (out_y == chk_prev_y)) begin
        $error(
            "RTL-ASSERT axis_video_mixer_core: raster stalled while enabled and not backpressured");
      end
      chk_raster_armed <= s0_valid && pipe_en && ((act_w > 16'd1) || (act_h > 16'd1));
      chk_prev_x       <= out_bx;
      chk_prev_y       <= out_y;

      // TDATA, TUSER and TLAST must hold, and TVALID must stay high, while a
      // beat is being offered and refused.
      if (chk_was_stalled) begin
        if (!m_axis_tvalid) begin
          $error("RTL-ASSERT axis_video_mixer_core: TVALID dropped during a stall");
        end else if ({m_axis_tdata, m_axis_tuser, m_axis_tlast} !==
                     {chk_prev_tdata, chk_prev_tuser, chk_prev_tlast}) begin
          $error("RTL-ASSERT axis_video_mixer_core: output payload changed during a stall");
        end
      end
      chk_was_stalled <= m_axis_tvalid && !m_axis_tready;
      chk_prev_tdata  <= m_axis_tdata;
      chk_prev_tuser  <= m_axis_tuser;
      chk_prev_tlast  <= m_axis_tlast;
    end
  end

`endif

endmodule
