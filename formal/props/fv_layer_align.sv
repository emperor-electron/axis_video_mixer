`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_layer_align.sv
// Purpose : Positional accounting for axis_mixer_layer: the claim that the
//           beat counters really do say where in the frame the buffered beats
//           came from.
//
//           This is the property the block exists for. The mixer consumes a
//           layer positionally -- one beat per output beat inside the window --
//           so wherever a beat is consumed is where it lands on the canvas. If
//           the layer's own accounting of how many beats it has buffered ever
//           disagrees with (ln_cnt, bt_cnt) by even one, the layer sits skewed
//           for as long as it runs, and because it then supplies exactly as
//           many beats per frame as the window consumes, the offset never
//           works itself out.
//
//           Two statements:
//
//             a_position      beats buffered since the frame's SOF equals
//                             ln_cnt * cfg_w_beats + bt_cnt
//             a_frame_exact   a frame delivers exactly cfg_w_beats *
//                             cfg_height beats, no more and no fewer
//
//           BOUNDED, and by construction. Both need a multiply of two
//           configuration registers, which is expensive in itself and which a
//           16-bit geometry makes hopeless; and a_frame_exact only says
//           anything on runs long enough to reach the end of a frame. So this
//           is run as BMC over a deliberately tiny canvas -- a few beats by a
//           few lines -- deep enough to cover more than one whole frame. The
//           accounting logic under test does not know how big the geometry is,
//           so a proof over small geometries is strong evidence rather than a
//           proof over all of them, and it is worth being clear that that is
//           the distinction.
//
//           Kept out of fv_layer_props.sv because the multiply is pure
//           overhead for every other task.
///////////////////////////////////////////////////////////////////

module fv_layer_align (
    input logic clk,
    input logic rst_n,

    input logic [15:0] cfg_w_beats,
    input logic [15:0] cfg_height,

    input logic        state,
    input logic [15:0] bt_cnt,
    input logic [15:0] ln_cnt,
    input logic        push,
    input logic        flush_now,
    input logic        last_bt_of_line,
    input logic        last_ln_of_frame
);
  localparam logic S_STREAM = 1'b1;

  // Beats buffered so far for the frame in flight. Restarted by the SOF beat
  // rather than by the end of the previous frame, because a clean end of frame
  // deliberately does not flush -- the FIFO is still holding pixels the output
  // has not consumed, and the next frame queues up behind them.
  logic [15:0] frame_beats;

  always_ff @(posedge clk) begin
    if (!rst_n || flush_now) begin
      frame_beats <= 16'd0;
    end else if (push) begin
      frame_beats <= (state == S_STREAM) ? (frame_beats + 16'd1) : 16'd1;
    end
  end

  // Folded the same way the RTL folds cur_bt and cur_ln: outside STREAM the
  // count so far is zero, because the beat being accepted is the frame's first
  // one. Without the fold, the count left over from the previous frame -- a
  // clean end of frame deliberately does not flush -- is still sitting in
  // frame_beats, and a_frame_exact fails on the next frame's first beat of a
  // 1x1 layer.
  logic [15:0] beats_so_far;
  assign beats_so_far = (state == S_STREAM) ? frame_beats : 16'd0;

  always_ff @(posedge clk) begin
    if (rst_n && (state == S_STREAM)) begin
      a_position : assert (frame_beats == 16'(ln_cnt) * cfg_w_beats + bt_cnt);
    end

    // The last beat of the last line is the (w*h)-th beat of the frame. This
    // is what guarantees a layer supplies exactly what its window consumes;
    // one beat either way and every subsequent frame is offset.
    if (rst_n && push && last_bt_of_line && last_ln_of_frame) begin
      a_frame_exact : assert ((beats_so_far + 16'd1) == cfg_w_beats * cfg_height);
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Cover
  //
  // a_frame_exact is vacuous until a frame actually completes, and a_position
  // is much weaker on a single-line layer, so both corners are covered
  // explicitly. Without these a pass could mean the BMC depth never got far
  // enough to say anything.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (rst_n) begin
      c_frame_completes : cover (push && last_bt_of_line && last_ln_of_frame &&
                                 (cfg_height > 16'd1) && (cfg_w_beats > 16'd1));
      c_second_frame : cover (push && (state != S_STREAM) && (frame_beats != 16'd0));
    end
  end

endmodule
