`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: axis_mixer_layer.sv
// Author  : Benjamin Tamayo
// Date    : 09/06/2026
// Purpose : Input front end for one mixer layer: buffer the incoming stream and
//           keep it aligned to the layer's configured geometry.
//
//           The core problem this solves is that nothing links a layer's stream
//           to the output raster except a count. The mixer pops one pixel per
//           output pixel inside the layer's window, and it has no way to tell a
//           correct pixel from one that is a line late. If the source and the
//           SIZE register ever disagree about how many pixels make a line, every
//           pixel after that point is wrong and stays wrong forever.
//
//           So alignment is re-established from evidence rather than assumed.
//           TUSER (start of frame) is the only trustworthy landmark in the
//           stream, and this block re-synchronises to it after every fault:
//
//             WAIT_SOF - discard everything until TUSER marks a frame start.
//                        A layer here contributes nothing and reports ARMED low.
//             STREAM   - buffer pixels, counting them against WIDTH and HEIGHT.
//                        TLAST anywhere but the configured last pixel of a line,
//                        or TUSER anywhere at all, means the source disagrees
//                        with the registers: flag it and drop back to WAIT_SOF.
//
//           Reaching the end of a frame cleanly also returns to WAIT_SOF, but
//           without flushing -- the FIFO still holds pixels the output has not
//           consumed yet, and the next frame queues up behind them. That is the
//           prefill that keeps a layer positioned at x = 0 from starving.
//
//           MULTI-PIXEL PER CLOCK. Everything here counts BEATS, not pixels. A
//           beat carries P_PPC pixels and the core guarantees, by rejecting any
//           other configuration, that a layer's width is a whole number of
//           beats -- so a line is exactly cfg_w_beats beats with no partial one
//           at the end, and TLAST lands on a beat boundary.
//
//           That constraint is the entire reason this file barely changed. Take
//           it away and every line ends mid-beat, TKEEP starts meaning
//           something, and the FIFO read side needs a barrel shifter to realign
//           lanes. See doc/design.md section 10.
///////////////////////////////////////////////////////////////////

module axis_mixer_layer
  import axis_video_mixer_pkg::*;
#(
    parameter int P_FIFO_DEPTH = 2048,
    parameter int P_PPC = 1,
    // Derived; do not override.
    parameter int P_BEAT_W = P_PPC * PX_W
) (
    input logic clk,
    input logic rst_n,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Control from the mixer core
    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Discard everything buffered and re-arm at the next input SOF. Raised on a
    // soft reset, on a starve, and when this layer's geometry changes.
    input logic        flush,
    // Layer is enabled and taking part in the composite. A disabled layer drains
    // its input rather than backpressuring it, so switching a layer off never
    // stalls the source that feeds it -- and never raises a spurious src_stall.
    input logic        enable,
    // Active (frame-latched) geometry, in BEATS horizontally and lines
    // vertically. The core does the pixels-to-beats shift, so this block never
    // has to know the layer's width in pixels.
    input logic [15:0] cfg_w_beats,
    input logic [15:0] cfg_height,
    // Cycles a source may be held backpressured before src_stall is reported.
    // Zero disables the check.
    input logic [31:0] stall_limit,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Layer input stream, RGBA8
    ////////////////////////////////////////////////////////////////////////////////////////////////
    input  logic                s_axis_tvalid,
    output logic                s_axis_tready,
    input  logic [P_BEAT_W-1:0] s_axis_tdata,   // P_PPC pixels, lane 0 in the LSBs
    input  logic                s_axis_tuser,   // SOF, on the first beat of a frame
    input  logic                s_axis_tlast,   // EOL, on the last beat of a line

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Pixel output to the blend cascade
    ////////////////////////////////////////////////////////////////////////////////////////////////
    output logic [P_BEAT_W-1:0] px_data,
    output logic                px_valid,
    input  logic                px_pop,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Status
    ////////////////////////////////////////////////////////////////////////////////////////////////
    output logic        armed,      // has seen SOF and is delivering pixels
    output logic        geom_err,   // one-cycle pulse: stream disagreed with SIZE
    output logic        src_stall,  // one-cycle pulse: backpressured too long
    output logic [15:0] level
);
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // State
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  typedef enum logic {
    S_WAIT_SOF = 1'b0,
    S_STREAM   = 1'b1
  } state_e;

  state_e state;

  logic [15:0] bt_cnt;  // beat within the current line, 0 .. cfg_w_beats-1
  logic [15:0] ln_cnt;  // line within the current frame, 0 .. cfg_height-1

  logic [15:0] cur_bt;
  logic [15:0] cur_ln;

  logic fifo_full;
  logic beat;
  logic accept;
  logic push;
  logic flush_now;

  logic last_bt_of_line;
  logic last_ln_of_frame;
  logic geom_bad;

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Handshake
  //
  // TREADY is gated only on FIFO space, in both states. Discarding an unwanted
  // beat while full would otherwise be impossible, and while the layer is armed
  // the output is draining the FIFO, so space always reappears.
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  assign s_axis_tready = enable ? !fifo_full : 1'b1;
  assign beat = s_axis_tvalid && s_axis_tready;

  // In WAIT_SOF everything before the SOF landmark is consumed and discarded;
  // the SOF beat itself is the first beat of the frame and is kept. A disabled
  // layer accepts beats but keeps none of them.
  assign accept = enable && beat && ((state == S_STREAM) || s_axis_tuser);

  // The SOF beat is the frame's beat zero, so it is counted with the same
  // arithmetic as every other beat rather than as a special case. That is what
  // makes a one-beat-wide or one-line-tall layer fall out correctly instead of
  // needing its own branch.
  assign cur_bt = (state == S_STREAM) ? bt_cnt : 16'd0;
  assign cur_ln = (state == S_STREAM) ? ln_cnt : 16'd0;

  assign last_bt_of_line = (cur_bt == cfg_w_beats - 16'd1);
  assign last_ln_of_frame = (cur_ln == cfg_height - 16'd1);

  // Two things must hold on every accepted beat: TLAST marks the configured last
  // beat of a line and nothing else, and TUSER appears on the frame's first beat
  // and nowhere else. Either violation means the source and the SIZE register
  // disagree, and every pixel after it would land in the wrong place.
  //
  // Note this is a BEAT-level check even though SIZE is written in pixels. That
  // is only sound because the core rejects any width that is not a whole number
  // of beats, so "last beat of the line" and "last pixel of the line" name the
  // same beat. Without that constraint a source could end a line mid-beat and
  // this check would pass while the geometry was wrong.
  assign geom_bad = accept && ((s_axis_tlast != last_bt_of_line) ||
                               (s_axis_tuser != (state != S_STREAM)));

  assign push = accept && !geom_bad;

  // A geometry fault flushes as well, because whatever is buffered was counted
  // against the wrong geometry and cannot be trusted.
  // Holding a disabled layer in flush keeps its FIFO empty and armed low, so
  // re-enabling it always starts cleanly from the next SOF rather than from
  // whatever happened to be buffered when it was switched off.
  assign flush_now = flush || geom_bad || !enable;

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Frame tracking
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (!rst_n || flush_now) begin
      state  <= S_WAIT_SOF;
      bt_cnt <= 16'd0;
      ln_cnt <= 16'd0;
      armed  <= 1'b0;
    end else if (push) begin
      // armed stays high across a clean end of frame: the FIFO is still holding
      // pixels the output has not consumed, and the next frame prefills behind
      // them. Only a flush disarms the layer.
      armed <= 1'b1;
      if (last_bt_of_line) begin
        bt_cnt <= 16'd0;
        if (last_ln_of_frame) begin
          ln_cnt <= 16'd0;
          state  <= S_WAIT_SOF;
        end else begin
          ln_cnt <= cur_ln + 16'd1;
          state  <= S_STREAM;
        end
      end else begin
        bt_cnt <= cur_bt + 16'd1;
        state  <= S_STREAM;
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Error pulses
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (!rst_n) geom_err <= 1'b0;
    else geom_err <= geom_bad;
  end

  // Backpressure is normal in bursts and only meaningful as a fault when it
  // persists, so it is measured against a threshold rather than flagged on the
  // first stalled cycle. A source held off this long is producing faster than
  // the mixer consumes, which in practice means a frame rate mismatch.
  logic [31:0] stall_cnt;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      stall_cnt <= 32'd0;
      src_stall <= 1'b0;
    end else begin
      src_stall <= 1'b0;
      if (s_axis_tvalid && !s_axis_tready) begin
        if (stall_limit != 32'd0 && stall_cnt == stall_limit - 32'd1) begin
          src_stall <= 1'b1;
          stall_cnt <= 32'd0;
        end else begin
          stall_cnt <= stall_cnt + 32'd1;
        end
      end else begin
        stall_cnt <= 32'd0;
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Buffer
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Depth is in BEATS. Total storage is therefore constant across P_PPC for a
  // given pixel capacity -- a 2048-pixel line buffer is 2048 x 32 at P_PPC = 1
  // and 256 x 256 at P_PPC = 8, both 65536 bits, both 2 RAMB36.
  axis_mixer_fifo #(
      .P_WIDTH(P_BEAT_W),
      .P_DEPTH(P_FIFO_DEPTH)
  ) u_fifo (
      .clk     (clk),
      .rst_n   (rst_n),
      .flush   (flush_now),
      .wr_en   (push),
      .wr_data (s_axis_tdata),
      .full    (fifo_full),
      .rd_valid(px_valid),
      .rd_data (px_data),
      .rd_en   (px_pop),
      .level   (level)
  );

endmodule
