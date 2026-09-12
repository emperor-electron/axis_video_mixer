`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_core_props.sv
// Purpose : Formal properties for axis_video_mixer_core, bound in.
//
//           The core's header names two properties as load bearing. Both are
//           here, and they are the reason this file exists:
//
//             The output never stalls on an input. a_raster_advances says the
//             raster moves on every enabled, unstalled cycle regardless of
//             what any layer is doing, and the starve cover shows that it does
//             so while a layer is actually starving. A video sink loses lock
//             if the stream pauses, so a starving source must not be able to
//             take the display down with it -- and "must not" is exactly the
//             kind of claim simulation can only fail to disprove.
//
//             Horizontal geometry is a whole number of beats. Every window
//             comparison in the datapath is in beat units and is one compare
//             per layer per beat, which is only sound because a window starts
//             and ends on a beat boundary. a_active_window_* is where that is
//             established: not "the validation logic looks right" but "no
//             window that is misaligned or outside the canvas can ever become
//             active, by any path, including a canvas that changed underneath
//             it".
//
//           Beyond those, three groups:
//
//             Protocol     The output holds its payload while backpressured
//                          and keeps TVALID up. Required by AXI4-Stream, and
//                          the RTL checks it in simulation already.
//
//             Arbitration  Every beat a layer's window asks for is either
//                          popped or recorded as a starve, never silently
//                          skipped; a dropped layer is not popped again; a
//                          layer joins the composite only at a frame
//                          boundary.
//
//             Discharge    The three assumptions fv_layer.sv makes about its
//                          driver -- never pop empty, geometry constant
//                          between flushes, geometry non-zero -- are asserted
//                          here. An assumption nobody discharges is a hole,
//                          and these are those holes closed.
//
//           Output framing and the datapath itself are in fv_core_frame.sv,
//           which needs a constant configuration to say anything.
///////////////////////////////////////////////////////////////////

module fv_core_props #(
    parameter int P_NUM_LAYERS = 2,
    parameter int P_PPC = 1,
    parameter logic [15:0] LP_PPC_MASK = 16'(P_PPC - 1)
) (
    input logic clk,
    input logic rst_n,

    input logic ctrl_en,
    input logic soft_rst,

    // Raster and pipeline control.
    input logic [15:0] out_bx,
    input logic [15:0] out_y,
    input logic        s0_valid,
    input logic        s0_eol,
    input logic        s0_eof,
    input logic        pipe_en,
    input logic        frame_boundary,
    input logic        frame_latch,

    // Active configuration.
    input logic                    act_ok,
    input logic [            15:0] act_w,
    input logic [            15:0] act_h,
    input logic [            15:0] act_bw,
    input logic [P_NUM_LAYERS-1:0] act_en,
    input logic [            15:0] act_x     [P_NUM_LAYERS],
    input logic [            15:0] act_y     [P_NUM_LAYERS],
    input logic [            15:0] act_w_l   [P_NUM_LAYERS],
    input logic [            15:0] act_bx    [P_NUM_LAYERS],
    input logic [            16:0] act_bxe   [P_NUM_LAYERS],
    input logic [            16:0] act_ye    [P_NUM_LAYERS],
    input logic [            15:0] act_bw_l  [P_NUM_LAYERS],
    input logic [            15:0] act_h_l   [P_NUM_LAYERS],

    // Shadow validation.
    input logic                    canvas_ok,
    input logic [P_NUM_LAYERS-1:0] want_en,
    input logic [P_NUM_LAYERS-1:0] geo_changed,
    input logic                    cfg_fault,

    // Layer arbitration.
    input logic [P_NUM_LAYERS-1:0] in_win,
    input logic [P_NUM_LAYERS-1:0] want_px,
    input logic [P_NUM_LAYERS-1:0] starve,
    input logic [P_NUM_LAYERS-1:0] lay_active,
    input logic [P_NUM_LAYERS-1:0] lay_pop,
    input logic [P_NUM_LAYERS-1:0] lay_px_valid,
    input logic [P_NUM_LAYERS-1:0] lay_flush,
    input logic [P_NUM_LAYERS-1:0] lay_armed,
    input logic [P_NUM_LAYERS-1:0] lay_dropped,
    input logic [P_NUM_LAYERS-1:0] lay_cfg_bad,

    // Output stream.
    input logic m_axis_tvalid,
    input logic m_axis_tready,
    input logic m_axis_tuser,
    input logic m_axis_tlast,

    // Status and errors.
    input logic        status_frame_active,
    input logic        sof_out,           // sof_q[P_NUM_LAYERS], the output stage
    input logic        eof_out,           // eof_q[P_NUM_LAYERS]
    input logic        out_beat,
    input logic [31:0] frame_count,
    input logic        err_cfg_set,
    input logic        err_starve_set,
    input logic [31:0] out_stall_cnt,
    input logic [31:0] stall_limit,
    input logic        err_out_stall_set
);
  // See the note in fv_fifo_props.sv: the delayed copies below have no reset,
  // so their first-state contents are history that never happened.
  logic fv_started = 1'b0;
  always_ff @(posedge clk) fv_started <= 1'b1;

  logic [15:0] out_bx_d, out_y_d;
  logic s0_valid_d, s0_eol_d, s0_eof_d, pipe_en_d;
  logic rst_n_d, soft_rst_d, ctrl_en_d, frame_latch_d;
  logic [P_NUM_LAYERS-1:0] lay_active_d, lay_dropped_d, starve_d, lay_flush_d;
  logic [15:0] act_bw_l_d[P_NUM_LAYERS];
  logic [15:0] act_h_l_d[P_NUM_LAYERS];
  logic mstall_d;
  logic [31:0] frame_count_d;
  logic [31:0] stall_limit_d;
  logic status_frame_active_d, sof_out_d, eof_out_d, out_beat_d;

  always_ff @(posedge clk) begin
    out_bx_d      <= out_bx;
    out_y_d       <= out_y;
    s0_valid_d    <= s0_valid;
    s0_eol_d      <= s0_eol;
    s0_eof_d      <= s0_eof;
    pipe_en_d     <= pipe_en;
    rst_n_d       <= rst_n;
    soft_rst_d    <= soft_rst;
    ctrl_en_d     <= ctrl_en;
    frame_latch_d <= frame_latch;
    lay_active_d  <= lay_active;
    lay_dropped_d <= lay_dropped;
    starve_d      <= starve;
    lay_flush_d   <= lay_flush;
    mstall_d      <= m_axis_tvalid && !m_axis_tready;
    frame_count_d <= frame_count;
    // Delayed, because stall_limit comes straight from a register software can
    // rewrite at any time: a pulse registered under a threshold of three can
    // be observed in a cycle where the threshold has already become zero.
    stall_limit_d <= stall_limit;
    status_frame_active_d <= status_frame_active;
    sof_out_d             <= sof_out;
    eof_out_d             <= eof_out;
    out_beat_d            <= out_beat;
    for (int i = 0; i < P_NUM_LAYERS; i++) begin
      act_bw_l_d[i] <= act_bw_l[i];
      act_h_l_d[i]  <= act_h_l[i];
    end
  end

  // An ordinary running cycle, with an ordinary running cycle behind it.
  logic ran;
  assign ran = fv_started && rst_n && rst_n_d && !soft_rst_d;

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // The output never stalls on an input
  //
  // This is the property the whole starve-handling design exists to provide,
  // and the one the RTL's own simulation assertion goes after with "raster
  // stalled while enabled and not backpressured".
  //
  // Stated here as the exact next value of the raster rather than as "it
  // changed", for two reasons. A 1x1 canvas legitimately never changes its
  // counters, which the simulation assertion has to carve out as a special
  // case and this formulation does not. And "it changed" would be satisfied by
  // a raster that advanced wrongly -- skipping a beat, or wrapping a line
  // early -- which is a worse failure than not advancing at all, because the
  // picture stays in sync with nothing and the block reports no error.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [15:0] exp_bx, exp_y;
  assign exp_bx = s0_eol_d ? 16'd0 : (out_bx_d + 16'd1);
  assign exp_y  = s0_eol_d ? (s0_eof_d ? 16'd0 : (out_y_d + 16'd1)) : out_y_d;

  always_ff @(posedge clk) begin
    if (ran && ctrl_en_d && pipe_en_d && s0_valid_d) begin
      // Nothing in this condition mentions a layer, and that is the content of
      // the property: whatever the layers did last cycle -- starved, faulted,
      // been flushed, delivered nothing at all -- the raster moved on by
      // exactly one beat.
      a_raster_advances : assert ((out_bx == exp_bx) && (out_y == exp_y));
    end

    // And the converse: it does not advance when it should not, so a beat is
    // never emitted twice or skipped while the downstream is holding it off.
    if (ran && ctrl_en_d && !(pipe_en_d && s0_valid_d)) begin
      a_raster_holds : assert ((out_bx == out_bx_d) && (out_y == out_y_d));
    end

    // The raster sits at the origin whenever there is no frame to draw. This
    // is the helper that makes the bound below inductive, and the case it
    // covers is a real one: the canvas is latched not only at a frame boundary
    // but also whenever !act_ok or !ctrl_en, which is what makes the natural
    // software order work -- a disabled mixer never reaches a frame boundary,
    // so a canvas written before EN was set could otherwise never take effect.
    //
    // That extra latch path is exactly what an arbitrary induction start state
    // exploits: a stale raster part way across a wide canvas, a latch that
    // installs a narrow one, and the bound is broken on a state the design can
    // never reach. It cannot reach it because the same conditions that allow
    // the latch also hold the raster at zero, which is what this says.
    // ctrl_en DELAYED, and act_ok live, because the two reach the raster by
    // different routes. !ctrl_en is in the raster register's reset branch, so
    // it parks the counters on the next edge rather than immediately -- the
    // cycle in which software clears EN still shows the old position. act_ok
    // is not in that branch at all: it gates s0_valid, so a raster with no
    // valid canvas simply holds, and holds at zero because it has never been
    // anywhere else.
    if (ran && (!ctrl_en_d || !act_ok)) begin
      a_raster_parked : assert ((out_bx == 16'd0) && (out_y == 16'd0));
    end

    // A usable canvas is at least one beat by one line. act_ok is only ever
    // set alongside a canvas that passed canvas_ok, which rejects zero in
    // either axis -- and the horizontal shift to beats is exact because the
    // same check rejects a width that is not a multiple of P_PPC, so a
    // non-zero width cannot shift down to zero beats.
    if (rst_n && act_ok) begin
      a_canvas_nonzero : assert ((act_bw >= 16'd1) && (act_h >= 16'd1));
    end

    // The raster stays on the canvas. out_bx indexes beats and out_y lines, and
    // every window comparison is against these, so a raster off the canvas
    // would put pixels outside it.
    if (rst_n && act_ok) begin
      a_raster_in_canvas : assert ((out_bx < act_bw) && (out_y < act_h));
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Protocol on the output stream
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic mtvalid_d, mtuser_d, mtlast_d;

  always_ff @(posedge clk) begin
    mtvalid_d <= m_axis_tvalid;
    mtuser_d  <= m_axis_tuser;
    mtlast_d  <= m_axis_tlast;
  end

  always_ff @(posedge clk) begin
    if (ran && mstall_d) begin
      // AXI4-Stream: once offered, a beat is held until it is taken. Dropping
      // TVALID or changing the payload under a sink that has not accepted it
      // yet loses a beat, and a video sink loses a line with it.
      a_out_tvalid_held : assert (m_axis_tvalid);
      a_out_tuser_held : assert (m_axis_tuser == mtuser_d);
      a_out_tlast_held : assert (m_axis_tlast == mtlast_d);
      // TDATA stability is in fv_core_frame.sv, where the payload is in scope.
    end

    if (rst_n) begin
      // pipe_en is the pipeline's only enable, and it is exactly "the output
      // stage is free". If it were ever high while a beat was being held, the
      // pipeline would advance and overwrite that beat.
      a_pipe_en_exact : assert (pipe_en == (m_axis_tready || !m_axis_tvalid));
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // No active window is ever illegal
  //
  // This is the invariant the beat-domain datapath rests on. It is not a
  // restatement of the validation logic: win_ok is evaluated against the
  // SHADOW canvas, while these are the ACTIVE window and the ACTIVE canvas,
  // and the two are latched by the same frame_latch but under different
  // conditions -- the canvas only updates when canvas_ok, the windows always
  // do. Whether a window can end up active against a canvas it was never
  // checked against is a real question about that interaction, and this is the
  // answer.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_win
    always_ff @(posedge clk) begin
      // The beat-domain and pixel-domain copies of a window are latched from
      // the same shadow registers in the same cycle, so they are always
      // consistent -- whether or not the layer is enabled.
      //
      // Asserting this UNCONDITIONALLY rather than only for an enabled layer
      // is what makes a_geom_change_flushes inductive, and the reason is worth
      // recording. geo_changed is computed from act_w_l, while the layer
      // counts against act_bw_l. They are separate registers, so an arbitrary
      // induction start state can have them disagree -- and then act_bw_l can
      // change with geo_changed false, and the discharge property fails on a
      // state the design can never actually be in. Tying them together closes
      // that, because k-induction gets to assume every asserted property in
      // the pre-states.
      if (rst_n) begin
        a_bw_shift_consistent : assert (act_bw_l[gi] == (act_w_l[gi] >> $clog2(P_PPC)));
        a_bx_shift_consistent : assert (act_bx[gi] == (act_x[gi] >> $clog2(P_PPC)));
        a_bxe_consistent : assert (act_bxe[gi] == (17'(act_bx[gi]) + 17'(act_bw_l[gi])));
        a_ye_consistent : assert (act_ye[gi] == (17'(act_y[gi]) + 17'(act_h_l[gi])));
      end

      if (rst_n && act_en[gi]) begin
        // The canvas is usable at all. An enabled layer against no valid
        // canvas would compare its window against zero.
        a_active_canvas_ok : assert (act_ok);

        // Inside the canvas, in both axes, in the units each axis is compared
        // in: beats horizontally, lines vertically.
        a_active_window_in_canvas : assert ((act_bxe[gi] <= 17'(act_bw)) &&
                                            (act_ye[gi] <= 17'(act_h)));

        // Non-degenerate. A zero-width or zero-height window would make
        // in_win false everywhere, so the layer would arm, never be popped,
        // and fill its FIFO until its source stalled.
        a_active_window_nonzero : assert ((act_bw_l[gi] >= 16'd1) &&
                                          (act_h_l[gi] >= 16'd1));

        // Beat aligned. This is the constraint that makes one compare per
        // layer per beat sound, and rejecting rather than rounding is
        // deliberate -- silently snapping a window to a beat boundary would
        // put the picture up to P_PPC-1 pixels from where the register says.
        a_active_x_aligned : assert ((act_x[gi] & LP_PPC_MASK) == 16'd0);
        a_active_w_aligned : assert ((act_w_l[gi] & LP_PPC_MASK) == 16'd0);

        // The shift to the beat domain lost nothing, which is only true
        // because of the alignment above -- and it is what makes act_bx and
        // act_bw_l faithful to what software asked for rather than to a
        // rounded-down version of it.
        a_active_bx_exact : assert ((act_bx[gi] << $clog2(P_PPC)) == act_x[gi]);
        a_active_bw_exact : assert ((act_bw_l[gi] << $clog2(P_PPC)) == act_w_l[gi]);
      end

      // A layer is only ever popped inside its own window, and only while it
      // is contributing.
      if (rst_n && lay_pop[gi]) begin
        a_pop_in_window : assert (in_win[gi]);
        a_pop_when_active : assert (lay_active[gi] && act_en[gi]);
      end

      if (rst_n && in_win[gi]) begin
        a_in_win_enabled : assert (act_en[gi]);
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Arbitration
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_arb
    always_ff @(posedge clk) begin
      if (rst_n) begin
        // The obligation axis_mixer_layer and axis_mixer_fifo both assume
        // about whoever pops them, discharged here. Without this the entire
        // FIFO and layer result rests on an assumption nothing proves.
        a_no_pop_empty : assert (!(lay_pop[gi] && !lay_px_valid[gi]));

        // Every beat a window asks for is accounted for: it is either popped
        // or recorded as a starve, never both and never neither. "Never
        // neither" is the one that matters -- a silently skipped beat shifts
        // the layer by one for the rest of the frame with no error raised.
        if (want_px[gi] && pipe_en && s0_valid) begin
          a_pop_xor_starve : assert (lay_pop[gi] != starve[gi]);
        end
        a_not_both : assert (!(lay_pop[gi] && starve[gi]));

        // A starved layer is desynchronised by definition: the beats still in
        // its FIFO belong to positions the raster has already passed. So it is
        // flushed, not merely skipped.
        if (starve[gi]) begin
          a_starve_flushes : assert (lay_flush[gi]);
        end

        // A dropped layer stays out for the rest of the frame rather than
        // rejoining part way through, which would land its beat zero part way
        // along a line.
        if (lay_dropped[gi]) begin
          a_dropped_not_popped : assert (!lay_pop[gi]);
        end

        // A layer is never popped unless it has seen its first SOF. Popping a
        // layer that has not armed would consume whatever happened to be in
        // its FIFO as though it were beat zero of a frame.
        if (lay_pop[gi]) begin
          a_pop_needs_armed : assert (lay_armed[gi]);
        end

        // A layer reported as badly configured is never counted as enabled, so
        // L<i>_STATUS.CFG_BAD and the layer taking part in the composite can
        // never both be true of the same write.
        if (lay_cfg_bad[gi]) begin
          a_cfg_bad_not_wanted : assert (!want_en[gi]);
        end

        // And nothing is enabled against a canvas that was rejected.
        if (want_en[gi]) begin
          a_want_needs_canvas : assert (canvas_ok);
        end
      end

      if (ran) begin
        // A starve latches the drop, unless the frame ended in the same cycle
        // -- the clear is deliberately written after the sets so that a starve
        // on the last beat of a frame does not carry into the next one.
        if (starve_d[gi] && !frame_latch_d) begin
          a_starve_drops : assert (lay_dropped[gi]);
        end

        // A layer joins the composite only at a frame boundary. This is a
        // correctness requirement and not a nicety: the mixer consumes a layer
        // positionally, so a layer that went active part way through an output
        // frame would have its beat zero consumed part way along a line, and
        // because it then supplies exactly as many beats per frame as the
        // window consumes, the offset would never work itself out.
        if (lay_active[gi] && !lay_active_d[gi]) begin
          a_join_at_boundary : assert (frame_latch_d);
        end

        // Dropped clears only at a frame boundary too, so the "for the rest of
        // the frame" above means what it says.
        if (!lay_dropped[gi] && lay_dropped_d[gi]) begin
          a_drop_clears_at_boundary : assert (frame_latch_d || soft_rst_d);
        end
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Discharging what fv_layer.sv assumes
  //
  // fv_layer.sv models each layer's geometry as a free constant. That is only
  // legitimate if the core never moves a layer's geometry underneath it
  // without also flushing it, because everything the layer has buffered was
  // counted against the old size. Here is where that is established.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_discharge
    always_ff @(posedge clk) begin
      if (ran) begin
        // If what the layer is counting against changed, the layer was flushed
        // in the same cycle the change was latched. Stated over the values the
        // layer actually sees -- cfg_w_beats and cfg_height -- rather than over
        // geo_changed, because geo_changed is the core's own reasoning and this
        // has to be true of the wires.
        if ((act_bw_l[gi] != act_bw_l_d[gi]) || (act_h_l[gi] != act_h_l_d[gi])) begin
          a_geom_change_flushes : assert (lay_flush_d[gi]);
        end
      end

      // And the geometry a layer is asked to count against is never
      // degenerate while it is enabled, which is the other thing fv_layer.sv
      // assumes. A disabled layer is held in flush, so a zero there is
      // harmless.
      if (rst_n && act_en[gi]) begin
        a_geom_nonzero : assert ((act_bw_l[gi] != 16'd0) && (act_h_l[gi] != 16'd0));
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Status and error reporting
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (rst_n) begin
      // ERR.CFG latches once per frame boundary rather than continuously,
      // because corsair gives the hardware set priority over the software
      // clear -- a level would keep re-setting the bit and software could
      // never clear it while the bad value remained.
      a_err_cfg_gated : assert (!err_cfg_set || (frame_boundary && cfg_fault));

      // ERR.STARVE is exactly the OR of the per-layer starves, so a set bit
      // always has a layer behind it in ERR_LAYER.
      a_err_starve_faithful : assert (err_starve_set == (|starve));

      // The active canvas width in beats is the pixel width shifted, exactly.
      // Software writes pixels and every comparison in the datapath is in
      // beats, so a shift that lost a bit would draw a canvas narrower than
      // the register says -- and CANVAS would then be a lie rather than a
      // rejected value.
      if (act_ok) begin
        a_canvas_beats_exact : assert ((act_bw << $clog2(P_PPC)) == act_w);
      end
    end

    if (ran) begin
      // STATUS.FRAME_ACTIVE moves only on an accepted beat that carries SOF or
      // EOF. Software polls it to decide when a configuration write is safe,
      // so a bit that moved at any other time would hand it the wrong answer
      // at exactly the moment it matters.
      if (status_frame_active != status_frame_active_d) begin
        a_frame_active_edges : assert (out_beat_d && (sof_out_d || eof_out_d));
      end
    end

    if (ran) begin
      // The downstream watchdog, same shape as the per-layer source watchdog:
      // between them, a stuck FRAME_COUNT can be attributed to the right side
      // of the pipeline instead of merely observed.
      if (err_out_stall_set) begin
        a_out_watchdog_off : assert (stall_limit_d != 32'd0);
        a_out_stall_real : assert (mstall_d);
      end
      if (!mstall_d) begin
        a_out_stall_cleared : assert (out_stall_cnt == 32'd0);
      end

      // FRAME_COUNT only ever counts up, and by one. Software polls it to tell
      // a stalled pipeline from a slow one, so a count that moved for any
      // other reason would be worse than no count at all.
      if (frame_count != frame_count_d) begin
        a_frame_count_steps : assert (frame_count == (frame_count_d + 32'd1));
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Cover
  //
  // The starve covers are the important ones: a_raster_advances is a much
  // weaker statement if no layer ever starves, and that is precisely the
  // scenario it is there for.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (rst_n) begin
      c_starve : cover (|starve);
      c_starve_while_running : cover ((|starve) && pipe_en && s0_valid && m_axis_tvalid);
      c_pop : cover (|lay_pop);
      c_two_layers_popped : cover (lay_pop == '1);
      c_dropped : cover (|lay_dropped);
      c_cfg_fault : cover (cfg_fault && frame_boundary);
      c_frame_done : cover (m_axis_tvalid && m_axis_tready && m_axis_tlast && m_axis_tuser);
      c_out_backpressured : cover (m_axis_tvalid && !m_axis_tready);
      c_rejoin : cover ((|lay_active) && frame_latch);
      c_geom_change : cover (frame_latch && (|geo_changed));
    end
  end

endmodule
