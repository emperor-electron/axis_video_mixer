`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_core_frame.sv
// Purpose : Output framing and datapath value for axis_video_mixer_core, under
//           a configuration that does not move.
//
//           Two things are checked here that cannot be checked in
//           fv_core_props.sv, and both for the same reason: they compare the
//           output against an independent model of what the output should be,
//           and such a model needs to know the canvas. The canvas is latched at
//           frame boundaries and the pipeline is P_NUM_LAYERS+2 stages deep, so
//           in general the beat leaving the pipeline was rastered under a
//           canvas that may already have been replaced. Rather than model that
//           delay -- which would mean re-deriving the pipeline inside the
//           checker and proving nothing -- fv_core.sv holds the configuration
//           constant for these tasks and the model becomes simple enough to be
//           worth trusting.
//
//           FRAMING. An independent raster counts accepted output beats and
//           says where in the frame each one is. TUSER must be on the first
//           beat of a frame and nowhere else; TLAST on the last beat of every
//           line and nowhere else. A downstream video sink derives its timing
//           from exactly these two bits, so an extra or missing one is a lost
//           frame rather than a cosmetic defect.
//
//           VALUE. With every layer's effective alpha at zero -- either
//           because no layer is enabled, or because the global alpha is zero
//           and ALPHA_SRC selects it -- "over" returns the accumulator
//           bit-exactly at every stage, so the output must be the background
//           colour, exactly, on every lane. That is a single assertion that
//           exercises the entire cascade end to end: P_NUM_LAYERS blend
//           stages, the alpha stage, the FIFO capture stage and the output
//           packing, across all P_PPC lanes. fv_blend proves the arithmetic
//           identity it relies on; this proves the cascade is wired to it.
///////////////////////////////////////////////////////////////////

module fv_core_frame
  import axis_video_mixer_pkg::*;
#(
    parameter int P_NUM_LAYERS = 2,
    parameter int P_PPC = 1,
    parameter bit P_OUT_HAS_ALPHA = 1'b1,
    parameter int P_PX_OUT_W = P_OUT_HAS_ALPHA ? PX_W : RGB_W,
    parameter int P_OUT_W = P_PPC * P_PX_OUT_W
) (
    input logic clk,
    input logic rst_n,
    input logic soft_rst,

    input logic [15:0] act_bw,
    input logic [15:0] act_h,
    input logic [23:0] act_bg,
    input logic                    act_ok,
    input logic [P_NUM_LAYERS-1:0] act_en,
    input logic [             7:0] act_alpha[P_NUM_LAYERS],
    input logic [P_NUM_LAYERS-1:0] act_asrc,

    input logic               m_axis_tvalid,
    input logic               m_axis_tready,
    input logic [P_OUT_W-1:0] m_axis_tdata,
    input logic               m_axis_tuser,
    input logic               m_axis_tlast
);
  logic fv_started = 1'b0;
  always_ff @(posedge clk) fv_started <= 1'b1;

  logic out_beat;
  assign out_beat = m_axis_tvalid && m_axis_tready;

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Independent output raster
  //
  // Derived from accepted beats and from TUSER alone -- never from the core's
  // own out_bx and out_y, which would make this a restatement of the design
  // instead of a check on it. TUSER starts the model; from then on it counts.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [15:0] o_bx, o_y;
  logic        o_locked;  // a SOF has been seen, so the model is aligned

  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      o_bx     <= 16'd0;
      o_y      <= 16'd0;
      o_locked <= 1'b0;
    end else if (out_beat) begin
      if (m_axis_tuser) begin
        // Re-align on every SOF. If SOF lands where the model did not expect
        // it, a_tuser_only_at_origin has already failed; realigning here keeps
        // one framing error from cascading into a failure on every beat after
        // it, which makes the counterexample trace readable.
        o_locked <= 1'b1;
        o_bx     <= (act_bw == 16'd1) ? 16'd0 : 16'd1;
        o_y      <= (act_bw == 16'd1) ? ((act_h == 16'd1) ? 16'd0 : 16'd1) : 16'd0;
      end else if (o_bx == act_bw - 16'd1) begin
        o_bx <= 16'd0;
        o_y  <= (o_y == act_h - 16'd1) ? 16'd0 : (o_y + 16'd1);
      end else begin
        o_bx <= o_bx + 16'd1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (fv_started && rst_n && !soft_rst && o_locked && out_beat) begin
      // EOL on the last beat of a line and nowhere else.
      a_tlast_on_eol : assert (m_axis_tlast == (o_bx == act_bw - 16'd1));

      // SOF on the first beat of a frame and nowhere else. The two together
      // are what a downstream video timing generator locks to.
      a_tuser_only_at_origin : assert (m_axis_tuser == ((o_bx == 16'd0) && (o_y == 16'd0)));
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Payload stability while backpressured
  //
  // In fv_core_props.sv for TUSER and TLAST; here for TDATA, which is only in
  // scope in this module.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [P_OUT_W-1:0] tdata_d;
  logic               mstall_d, rst_n_d;

  always_ff @(posedge clk) begin
    tdata_d  <= m_axis_tdata;
    mstall_d <= m_axis_tvalid && !m_axis_tready;
    rst_n_d  <= rst_n;
  end

  always_ff @(posedge clk) begin
    if (fv_started && rst_n && rst_n_d && !soft_rst && mstall_d) begin
      a_tdata_held : assert (m_axis_tdata == tdata_d);
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Value: an all-transparent composite is the background, exactly
  //
  // The condition is per layer: either the layer is not enabled, or its global
  // alpha is zero and ALPHA_SRC says to use the global alpha alone. In both
  // cases effective_alpha is zero for every pixel of that layer, whatever the
  // layer's stream happens to be delivering, and "over" with alpha zero
  // returns the accumulator untouched -- which fv_blend proves.
  //
  // Held constant by fv_core.sv, so the condition being true now means it was
  // true when this beat entered the pipeline.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic all_transparent;
  always_comb begin
    all_transparent = 1'b1;
    for (int i = 0; i < P_NUM_LAYERS; i++) begin
      if (act_en[i] && !((act_alpha[i] == 8'd0) && (act_asrc[i] == ALPHA_GLOBAL_ONLY))) begin
        all_transparent = 1'b0;
      end
    end
  end

  for (genvar gj = 0; gj < P_PPC; gj++) begin : g_lane
    always_ff @(posedge clk) begin
      if (rst_n && !soft_rst && m_axis_tvalid && act_ok && all_transparent) begin
        // With alpha on the output, alpha is forced opaque: everything below
        // the top layer has been composited in, so the result is opaque by
        // construction and two mixers can be cascaded. Without it the output
        // is bare RGB and drops into a video output stage unadapted.
        a_lane_is_background : assert (m_axis_tdata[gj*P_PX_OUT_W+:P_PX_OUT_W] ==
                                       (P_OUT_HAS_ALPHA ? P_PX_OUT_W'({act_bg, OPAQUE}) :
                                                          P_PX_OUT_W'(act_bg)));
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Cover
  //
  // Framing says nothing until a frame has been emitted, and the background
  // property says nothing unless a beat comes out while a layer is enabled but
  // fully transparent -- which is the case that exercises the cascade rather
  // than an idle one.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (rst_n) begin
      c_sof : cover (out_beat && m_axis_tuser && o_locked);
      c_eol : cover (out_beat && m_axis_tlast && !m_axis_tuser);
      c_multi_line : cover (out_beat && o_locked && (o_y != 16'd0));
      c_transparent_with_layer : cover (m_axis_tvalid && all_transparent && (|act_en));
    end
  end

endmodule
