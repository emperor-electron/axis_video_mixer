`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_layer_props.sv
// Purpose : Formal properties for axis_mixer_layer, bound in.
//
//           axis_mixer_layer exists to solve one problem, stated in its own
//           header: nothing links a layer's stream to the output raster except
//           a count, and the mixer cannot tell a correct pixel from one that is
//           a line late. Everything here is aimed at that. The properties fall
//           into three groups:
//
//             Containment   The layer never overflows its own FIFO, and never
//                           backpressures a source it is not using. These are
//                           what make the FIFO's assumptions true and what
//                           keep a disabled layer from stalling a source.
//
//             Accounting    The beat and line counters stay inside the
//                           configured geometry, and nothing is ever buffered
//                           from a beat whose TLAST or TUSER disagreed with
//                           that geometry. A layer that buffers one bad beat
//                           is skewed for as long as it runs.
//
//             Recovery      A flush is complete in one cycle, and a geometry
//                           fault really does flush. Re-arming from a stale
//                           FIFO would leave the layer permanently offset.
//
//           The exact positional claim -- that the n-th beat buffered is beat
//           (ln_cnt, bt_cnt) of the frame -- is in fv_layer_align.sv, which
//           needs a multiply and so is run bounded over a small geometry.
///////////////////////////////////////////////////////////////////

module fv_layer_props #(
    parameter int P_FIFO_DEPTH = 4,
    parameter int P_BEAT_W = 32
) (
    input logic clk,
    input logic rst_n,

    input logic        flush,
    input logic        enable,
    input logic [15:0] cfg_w_beats,
    input logic [15:0] cfg_height,
    input logic [31:0] stall_limit,

    input logic                s_axis_tvalid,
    input logic                s_axis_tready,
    input logic [P_BEAT_W-1:0] s_axis_tdata,
    input logic                s_axis_tuser,
    input logic                s_axis_tlast,

    input logic [P_BEAT_W-1:0] px_data,
    input logic                px_valid,
    input logic                px_pop,

    input logic        armed,
    input logic        geom_err,
    input logic        src_stall,
    input logic [15:0] level,

    // Internals, reached through the bind.
    input logic        state,
    input logic [15:0] bt_cnt,
    input logic [15:0] ln_cnt,
    input logic [15:0] cur_bt,
    input logic [15:0] cur_ln,
    input logic        fifo_full,
    input logic        accept,
    input logic        push,
    input logic        flush_now,
    input logic        geom_bad,
    input logic        last_bt_of_line,
    input logic [31:0] stall_cnt
);
  localparam logic S_WAIT_SOF = 1'b0;
  localparam logic S_STREAM = 1'b1;

  // See the corresponding note in fv_fifo_props.sv: the delayed copies below
  // have no reset, so their first-state contents are history that never
  // happened, and every property that reads them has to wait one edge.
  logic fv_started = 1'b0;
  always_ff @(posedge clk) fv_started <= 1'b1;

  logic flush_now_d, push_d, geom_bad_d, rst_n_d, enable_d, stalled_d, armed_d;
  logic [31:0] stall_limit_d;

  always_ff @(posedge clk) begin
    flush_now_d <= flush_now;
    push_d      <= push;
    geom_bad_d  <= geom_bad;
    rst_n_d     <= rst_n;
    enable_d    <= enable;
    stalled_d   <= s_axis_tvalid && !s_axis_tready;
    armed_d     <= armed;
    // The threshold as it stood when the pulse was decided. It matters that
    // this is the delayed copy: inside the core, stall_limit comes straight
    // from a register software can rewrite at any time, so a pulse registered
    // under a threshold of three can be observed in a cycle where the
    // threshold has already become zero. Compared against the live value, the
    // watchdog properties are false for reasons that have nothing to do with
    // the watchdog.
    stall_limit_d <= stall_limit;
  end

  logic ran;
  assign ran = fv_started && rst_n && rst_n_d;

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Containment
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (rst_n) begin
      // The obligation axis_mixer_fifo assumes about its producer, discharged
      // here. TREADY is gated on FIFO space, so a beat can only be accepted
      // when there is room -- but "so" is doing a lot of work in that
      // sentence, because accept also fires in WAIT_SOF and for a disabled
      // layer, and it is not obvious by inspection that the gating covers
      // every one of those paths.
      a_no_overflow : assert (!(push && fifo_full));

      // A disabled layer drains its source rather than backpressuring it.
      // Without this, switching a layer off would stall whatever is feeding
      // it, and the RTL header calls that out as a requirement: a disabled
      // layer must never raise a spurious src_stall either.
      a_disabled_never_blocks : assert (enable || s_axis_tready);

      // Nothing is buffered from a beat that disagreed with the geometry. This
      // is the whole point of the block: one bad beat buffered is a layer
      // permanently offset, and the offset never works itself out because the
      // layer then supplies exactly as many beats per frame as the window
      // consumes.
      if (push) begin
        a_push_tlast_agrees : assert (s_axis_tlast == last_bt_of_line);
        a_push_tuser_agrees : assert (s_axis_tuser == (state != S_STREAM));
      end

      // Accepting a beat and rejecting it are the only two outcomes, and a
      // rejected beat is never also pushed.
      a_push_implies_accept : assert (!push || accept);
      a_geom_bad_blocks_push : assert (!(geom_bad && push));

      // L<i>_STATUS.FIFO_LEVEL never exceeds what the buffer can hold, counting
      // the prefetched beat. Software reads this to tell a starve caused by a
      // slow source from one caused by a late enable, so a level above the
      // buffer's capacity would send it looking in the wrong place.
      a_level_bounded : assert (level <= 16'(P_FIFO_DEPTH + 1));

      // A disarmed layer holds nothing. armed is set by the same push that
      // writes the buffer and cleared by the same flush that empties it, and
      // nothing else can put a beat in there, so the two cannot disagree.
      //
      // This one is load bearing in the CORE's proof rather than in this
      // block's. There is a legitimate one-cycle window in which the core sees
      // lay_active high and lay_armed already low -- a geometry fault
      // disarms the layer a cycle before lay_geom_err clears lay_active -- and
      // what makes a_pop_needs_armed hold across it is that the same fault
      // emptied the buffer, so there is nothing to pop. Stated here, that
      // becomes an invariant k-induction can use there.
      if (!armed) begin
        a_disarmed_holds_nothing : assert ((level == 16'd0) && !px_valid);
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Accounting
  //
  // These hold for a stable geometry. The core guarantees that by flushing a
  // layer whenever its geometry changes -- see geo_changed and lay_flush in
  // axis_video_mixer_core.sv, and a_geom_change_flushes in fv_core_props.sv,
  // which is where that guarantee is actually proved. fv_layer.sv assumes it.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    // The counters are zero whenever the layer is waiting for a SOF. This
    // looks like a detail and is the invariant the counter bounds below rest
    // on -- without it neither of them is inductive, and the reason is worth
    // knowing about the RTL: on a beat that is not the last of its line,
    // ln_cnt is not assigned at all, so it carries whatever it held. What
    // makes that correct is that every path into WAIT_SOF zeroes it, which is
    // precisely what this asserts.
    if (rst_n && (state == S_WAIT_SOF)) begin
      a_wait_sof_zeroed : assert ((bt_cnt == 16'd0) && (ln_cnt == 16'd0));
    end

    if (rst_n && (state == S_STREAM)) begin
      // The counters never run past the configured geometry. A counter that
      // overshoots puts TLAST on the wrong beat, which the geometry check then
      // reports as the source's fault.
      a_bt_in_range : assert (bt_cnt < cfg_w_beats);
      a_ln_in_range : assert (ln_cnt < cfg_height);

      // Streaming implies armed: the two cannot disagree, because the core
      // decides whether to pop from armed and pops positionally.
      a_stream_implies_armed : assert (armed);
    end

    // cur_bt and cur_ln are the counters with the WAIT_SOF case folded in, so
    // that the SOF beat is counted by the same arithmetic as every other beat.
    // That folding is what makes a one-beat-wide or one-line-tall layer work
    // without a special case, so it is worth checking it really is the
    // identity in STREAM and zero otherwise.
    if (rst_n) begin
      a_cur_bt_fold : assert (cur_bt == ((state == S_STREAM) ? bt_cnt : 16'd0));
      a_cur_ln_fold : assert (cur_ln == ((state == S_STREAM) ? ln_cnt : 16'd0));
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Recovery
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (ran && flush_now_d) begin
      // One cycle, and nothing survives. The layer re-arms at the next input
      // SOF from a genuinely empty buffer; anything left behind would be
      // consumed as though it were pixel zero of the next frame.
      a_flush_disarms : assert (!armed);
      a_flush_resyncs : assert (state == S_WAIT_SOF);
      a_flush_empties : assert (level == 16'd0);
      a_flush_no_px : assert (!px_valid);
      a_flush_zeroes_counters : assert ((bt_cnt == 16'd0) && (ln_cnt == 16'd0));
    end

    if (ran) begin
      // A geometry fault flushes. What was buffered was counted against a
      // geometry the source disagrees with, so it cannot be trusted -- and
      // geom_err is reported one cycle after the fault, by which time the
      // buffer must already be empty.
      if (geom_bad_d) begin
        a_geom_err_reported : assert (geom_err);
        a_geom_err_flushed : assert (level == 16'd0 && !armed);
      end
      // And the converse: geom_err is never reported without a fault, so
      // ERR.GEOM cannot be a false alarm.
      a_geom_err_faithful : assert (geom_err == geom_bad_d);

      // armed only ever rises on a push. A layer that armed without buffering
      // anything would be popped by the core with nothing behind it.
      if (armed && !armed_d) begin
        a_arm_needs_push : assert (push_d);
      end

      // A disabled layer is held in flush, so it can never be armed or holding
      // anything. That is what makes re-enabling it start cleanly from the
      // next SOF instead of from whatever was buffered when it was switched
      // off.
      if (!enable_d) begin
        a_disabled_disarmed : assert (!armed);
        a_disabled_empty : assert (level == 16'd0);
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Source stall watchdog
  //
  // Backpressure is normal in bursts and only a fault when it persists, so the
  // RTL measures it against a threshold. Two things can go wrong with a
  // threshold: it fires when it should not, and it never fires at all. Both
  // are checked -- the second one in fv_layer.sv's watchdog task, where
  // stall_limit is held small enough for the bound to be reachable.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [31:0] fv_stall_run;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      fv_stall_run <= 32'd0;
    end else if (s_axis_tvalid && !s_axis_tready) begin
      fv_stall_run <= fv_stall_run + 32'd1;
    end else begin
      fv_stall_run <= 32'd0;
    end
  end

  always_ff @(posedge clk) begin
    if (ran && src_stall) begin
      // Zero disables the check, and it has to disable it completely: a
      // spurious ERR.SRC_STALL on a build that never asked for the watchdog
      // would be indistinguishable from a real frame rate mismatch.
      a_watchdog_off : assert (stall_limit_d != 32'd0);

      // And never reported without backpressure in the cycle it was measured.
      a_stall_real : assert (stalled_d);
    end

    if (ran && !stalled_d) begin
      // Any non-stalled cycle clears the run, so bursts of backpressure do not
      // accumulate across gaps into a fault that never actually happened.
      // Together with the threshold bound in fv_layer.sv, this is what makes
      // the watchdog mean "held off continuously for this long".
      a_stall_cnt_cleared : assert (stall_cnt == 32'd0);
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Cover
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic fv_saw_geom_fault;
  always_ff @(posedge clk) begin
    if (!rst_n) fv_saw_geom_fault <= 1'b0;
    else if (geom_bad) fv_saw_geom_fault <= 1'b1;
  end

  always_ff @(posedge clk) begin
    if (rst_n) begin
      c_armed : cover (armed && px_valid);
      c_frame_end : cover (push && last_bt_of_line && (cur_ln == cfg_height - 16'd1));
      c_geom_fault : cover (geom_bad);
      c_full : cover (fifo_full);
      c_stall_fires : cover (src_stall);
      // Recovery: the layer re-arms after a geometry fault. The obvious
      // spelling of this -- armed rising in the cycle after geom_bad -- is
      // unreachable by construction, because the fault flushes and a flush
      // cannot be followed immediately by a push. What matters is that the
      // layer comes back at all, so the fault is remembered and the cover
      // looks for an armed layer afterwards.
      c_rearm_after_fault : cover (armed && fv_saw_geom_fault);
    end
  end

endmodule
