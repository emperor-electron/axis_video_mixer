`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_layer.sv
// Purpose : Formal top for axis_mixer_layer against a free source and a free
//           consumer.
//
//           The source is unconstrained: TVALID, TDATA, TUSER and TLAST are
//           free every cycle, so the solver is allowed to send a SOF in the
//           middle of a line, a TLAST on the wrong beat, nothing at all for
//           twenty cycles, or a frame of the wrong size. That is the point --
//           this block's job is to stay aligned to its registers when the
//           source disagrees with them, and it cannot be shown to do that by
//           a source that always agrees.
//
//           TVALID stability while backpressured is deliberately NOT assumed,
//           even though AXI4-Stream requires it. The layer only ever samples
//           on a completed handshake, so dropping the assumption costs nothing
//           and removes one thing that has to be true of whatever is wired up.
//
//           WHAT IS ASSUMED, and where each assumption is discharged:
//
//             px_pop only when px_valid       asserted in fv_core_props.sv
//             geometry constant between       asserted in fv_core_props.sv
//               flushes                         (a_geom_change_flushes)
//             geometry non-zero               asserted in fv_core_props.sv
//                                               (a_active_window_legal)
//
//           None of the three is a property of this block, and all three are
//           properties of the block that drives it. Listing them here and
//           proving them there is the whole structure of the layer result: an
//           assumption nobody discharges is a hole, and these are the holes
//           this file would have.
///////////////////////////////////////////////////////////////////

module fv_layer
  import axis_video_mixer_pkg::*;
#(
    // Four beats, not 2048. Depth enters these properties only through the
    // FIFO's own pointer width, which fv_fifo.sby already covers at two
    // different depths; here it is as small as it can be without making full
    // unreachable.
    parameter int P_FIFO_DEPTH = 4,
    parameter int P_PPC = 1,
    // Upper bounds on the free geometry constants. Left wide open for the
    // invariant tasks -- the counter bounds hold for any geometry and should be
    // proved that way -- and narrowed by the align task, where a multiply of
    // two 16-bit registers is not something a solver will finish.
    parameter int FV_MAX_BEATS = 16'hFFFF,
    parameter int FV_MAX_LINES = 16'hFFFF,
    // Zero means "no bound", which is what the invariant tasks want: the
    // watchdog properties there are about it never firing wrongly, and hold at
    // any threshold. The watchdog task narrows it so that the threshold is
    // actually reachable within the BMC depth.
    parameter int FV_MAX_STALL = 0,
    // Derived.
    parameter int P_BEAT_W = P_PPC * PX_W
) (
    input logic clk,

    // Free source.
    input logic                s_axis_tvalid,
    input logic [P_BEAT_W-1:0] s_axis_tdata,
    input logic                s_axis_tuser,
    input logic                s_axis_tlast,

    // Free control from the core.
    input logic flush,
    input logic enable,
    input logic px_pop
);
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Modelled reset
  //
  // One cycle, for the reason set out in fv_fifo.sv: the counters and the FIFO
  // pointers have no initial value, so before a reset they hold whatever the
  // solver likes and the invariants simply are not true yet. Mid-stream resets
  // are not lost by pinning it, because flush is free above and the RTL folds
  // reset and flush into the same expression.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic rst_n;
  logic fv_in_reset = 1'b1;
  always_ff @(posedge clk) fv_in_reset <= 1'b0;
  assign rst_n = !fv_in_reset;

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Free but constant configuration
  //
  // The self-holding-register idiom again: no reset, no initial value, so the
  // solver picks the value and it never changes. Constant is the right model
  // because the core only ever changes a layer's geometry at a frame boundary
  // and flushes the layer when it does -- so from this block's point of view
  // the geometry it is counting against does not move underneath it.
  //
  // That is a real guarantee from the core, not an article of faith:
  // fv_core_props.sv asserts it as a_geom_change_flushes.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [15:0] cfg_w_beats;
  logic [15:0] cfg_height;
  logic [31:0] stall_limit;

  always_ff @(posedge clk) begin
    cfg_w_beats <= cfg_w_beats;
    cfg_height  <= cfg_height;
    stall_limit <= stall_limit;
  end

  logic                px_valid;
  logic [P_BEAT_W-1:0] px_data;
  logic                s_axis_tready;
  logic                armed, geom_err, src_stall;
  logic [        15:0] level;

  axis_mixer_layer #(
      .P_FIFO_DEPTH(P_FIFO_DEPTH),
      .P_PPC       (P_PPC)
  ) dut (
      .clk  (clk),
      .rst_n(rst_n),

      .flush      (flush),
      .enable     (enable),
      .cfg_w_beats(cfg_w_beats),
      .cfg_height (cfg_height),
      .stall_limit(stall_limit),

      .s_axis_tvalid(s_axis_tvalid),
      .s_axis_tready(s_axis_tready),
      .s_axis_tdata (s_axis_tdata),
      .s_axis_tuser (s_axis_tuser),
      .s_axis_tlast (s_axis_tlast),

      .px_data (px_data),
      .px_valid(px_valid),
      .px_pop  (px_pop),

      .armed    (armed),
      .geom_err (geom_err),
      .src_stall(src_stall),
      .level    (level)
  );

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Environment assumptions
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (rst_n) begin
      // A geometry of zero beats or zero lines is meaningless, and the core
      // never presents one: want_en is false for a zero-sized window, so the
      // layer is held disabled instead. Without this the counter bounds are
      // trivially false -- bt_cnt < 0 has no solutions -- and the failure says
      // nothing about the block.
      m_geometry_nonzero : assume ((cfg_w_beats >= 16'd1) && (cfg_height >= 16'd1));
      m_geometry_bounded : assume ((cfg_w_beats <= 16'(FV_MAX_BEATS)) &&
                                   (cfg_height <= 16'(FV_MAX_LINES)));

      if (FV_MAX_STALL != 0) begin
        m_stall_bounded : assume (stall_limit <= 32'(FV_MAX_STALL));
      end

      // The core's obligation, assumed here and asserted there. The layer
      // forwards px_pop straight to the FIFO's rd_en, so a pop with nothing
      // to pop is not something it can defend against.
      m_no_pop_when_empty : assume (!(px_pop && !px_valid));
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Watchdog liveness
  //
  // The properties in fv_layer_props.sv say the source-stall watchdog never
  // fires wrongly. This says it fires at all -- that a source held off for the
  // threshold really does get reported -- which is the half a "never fires
  // wrongly" property is happy to satisfy by never firing.
  //
  // It lives here rather than in the bound property file because it is only
  // meaningful with stall_limit small enough to reach inside the BMC depth,
  // which is a property of this environment and not of the layer.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  if (FV_MAX_STALL != 0) begin : g_watchdog
    logic [31:0] fv_run;

    always_ff @(posedge clk) begin
      if (!rst_n || src_stall) begin
        fv_run <= 32'd0;
      end else if (s_axis_tvalid && !s_axis_tready) begin
        fv_run <= fv_run + 32'd1;
      end else begin
        fv_run <= 32'd0;
      end
    end

    always_ff @(posedge clk) begin
      if (rst_n && (stall_limit != 32'd0)) begin
        // Backpressure is never held for longer than the threshold without
        // being reported. A watchdog that silently never fires leaves a frame
        // rate mismatch looking like a stuck FRAME_COUNT with no cause.
        a_watchdog_fires : assert (fv_run <= stall_limit);
      end
      if (rst_n) begin
        c_watchdog_fired : cover (src_stall);
      end
    end
  end

endmodule
