`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_fifo_order.sv
// Purpose : End-to-end ordering and accounting for axis_mixer_fifo, as a
//           BOUNDED cross-check on the compositional argument in
//           fv_fifo_props.sv.
//
//           This says the thing one actually wants said -- the i-th word out
//           is the i-th word in, and the count out plus the count still inside
//           equals the count in -- and it says it with two running transaction
//           counters.
//
//           Running counters are why this is bounded rather than proved.
//           k-induction starts from an arbitrary state, which can place the
//           counters anywhere, including one step from wrapping, and a wrapped
//           counter makes the comparison meaningless. The `wrapped` guard
//           keeps the assertions honest rather than false in that case, but
//           the consequence is that induction proves nothing here: it
//           discharges the properties vacuously from a start state that
//           already has wrapped set.
//
//           So this file is run in BMC only, from reset, to a depth where
//           CNT_W bits cannot wrap. Within that depth it is a genuine
//           exhaustive result, and it is the unbounded properties in
//           fv_fifo_props.sv -- addressed storage, unit pointer steps, no
//           overrun or underrun -- that carry ordering beyond it.
//
//           Kept in its own file, and bound only by the order task, because
//           the counters and the tracker are pure proof overhead for every
//           other task.
///////////////////////////////////////////////////////////////////

module fv_fifo_order #(
    parameter int P_WIDTH = 8,
    parameter int P_DEPTH = 8,
    // Wide enough that a BMC run cannot reach the wrap, and no wider. The
    // order task's depth must stay below 2**CNT_W -- and every bit above that
    // is a bit the solver carries through two counters and a comparison, which
    // is not free: at 8 bits this task did not get past step 19 in three
    // minutes, and at 5 bits it finishes. Raising the task's depth means
    // raising this to match.
    parameter int CNT_W = 5
) (
    input logic clk,
    input logic rst_n,
    input logic flush,

    input logic               wr_en,
    input logic [P_WIDTH-1:0] wr_data,
    input logic               full,

    input logic               rd_valid,
    input logic [P_WIDTH-1:0] rd_data,
    input logic               rd_en,

    input logic [15:0] level
);
  logic wr_fire, rd_fire;
  assign wr_fire = wr_en && !full;
  assign rd_fire = rd_valid && rd_en;

  // Which transaction to follow. A free constant -- a register that holds
  // itself, never resets and has no initial value, so formal leaves it
  // unconstrained and it stays put. Proving it for an arbitrary index proves
  // it for every index, which is what makes one tracked word enough.
  logic [CNT_W-1:0] fv_k;
  always_ff @(posedge clk) fv_k <= fv_k;

  logic [CNT_W-1:0] wcnt, rcnt;
  logic [P_WIDTH-1:0] tracked;
  logic tracked_vld;
  logic wrapped;

  always_ff @(posedge clk) begin
    // Flush discards everything, so the accounting restarts with it. That is
    // the behaviour axis_mixer_layer depends on, and fv_fifo_props proves
    // separately that the flush really does leave nothing behind.
    if (!rst_n || flush) begin
      wcnt        <= '0;
      rcnt        <= '0;
      tracked_vld <= 1'b0;
      wrapped     <= 1'b0;
    end else begin
      if (wr_fire) begin
        if (wcnt == fv_k) begin
          tracked     <= wr_data;
          tracked_vld <= 1'b1;
        end
        wcnt <= wcnt + 1'b1;
        if (wcnt == '1) wrapped <= 1'b1;
      end
      if (rd_fire) begin
        rcnt <= rcnt + 1'b1;
        if (rcnt == '1) wrapped <= 1'b1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst_n && !flush && !wrapped) begin
      // Ordering and data integrity together: when the k-th word leaves, it is
      // the k-th word that went in. A reordering, a duplication or a dropped
      // word all show up as this failing.
      if (rd_fire && (rcnt == fv_k)) begin
        // Nothing is ever read before it was written. Under BMC from reset
        // this is a real property, not a guard.
        a_order_written_first : assert (tracked_vld);
        a_order_data : assert (rd_data == tracked);
      end

      // Conservation: everything written is either still inside or has come
      // out. This is what rules out a silent drop, which the tracked word
      // alone would only catch if it happened to be the word dropped.
      a_conservation : assert (16'(wcnt - rcnt) == level);

      // Nothing comes out that did not go in.
      a_no_underrun : assert (rcnt <= wcnt);
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Cover: the tracked word really does make it through, and it does so having
  // been queued behind others rather than falling straight through an empty
  // FIFO. Without this, a_order_data could pass on runs where the tracked
  // index is never reached.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (rst_n && !flush) begin
      c_tracked_out : cover (rd_fire && (rcnt == fv_k) && tracked_vld && (fv_k != '0));
      c_tracked_queued : cover (rd_fire && (rcnt == fv_k) && tracked_vld && (level > 16'd2));
    end
  end

endmodule
