`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_fifo_props.sv
// Purpose : Formal properties for axis_mixer_fifo, bound in rather than
//           written into the RTL.
//
//           Binding keeps the properties out of the synthesised source and,
//           more usefully, means this one file is checked in three places: on
//           its own against a free environment, inside axis_mixer_layer, and
//           inside axis_video_mixer_core. A FIFO invariant that only holds
//           because of how the layer drives it will still be proved, and an
//           invariant the layer breaks will be caught where it is broken.
//
//           The port list reaches into the FIFO's internals -- wr_ptr, rd_ptr,
//           mem_count, mem_rd_en. That is the point of bind: the properties
//           can talk about the pointer arithmetic that the bugs actually live
//           in, not only about what the ports show.
//
//           WHAT IS AND IS NOT PROVED HERE, and why it is split that way.
//
//           Ordering -- that the i-th word read is the i-th word written -- is
//           not asserted directly anywhere in the proved set. Stating it needs
//           a pair of running transaction counters, and a running counter is
//           exactly what k-induction cannot reason about: an arbitrary start
//           state can place the counters anywhere, including one step from
//           wrapping, so the property can only ever be a bounded result.
//
//           It is instead established from three facts:
//
//             1. Addressed storage works: the memory returns at an arbitrary
//                address exactly what was last written there.
//                -> a_shadow_tracks_mem and a_storage_readback, in
//                   tops/fv_fifo.sv
//
//             2. The addresses are consecutive, one at a time, in both
//                directions.
//                -> a_wr_step and a_rd_step, below
//
//             3. The window between the pointers never wraps onto itself: the
//                write pointer never laps the read pointer, and the read
//                pointer never passes the write pointer.
//                -> a_no_overrun, below. It covers both directions, because
//                   mem_count is the modular difference in the extra pointer
//                   bit: a read pointer one ahead of the write pointer shows
//                   up not as -1 but as all-ones, which is far above P_DEPTH.
//
//           A circular buffer with those three properties delivers in order,
//           and all three are proved unboundedly. See doc/formal.md section 5.
//
//           fv_fifo_order.sv then asserts the end-to-end statement directly,
//           as a BOUNDED cross-check on that argument. It says so in its own
//           header.
//
//           Fact (1) is in the formal top rather than here for a tool reason,
//           and it is worth recording. Reading the memory means getting at the
//           array, and a bind port connection forces the array to a plain
//           variable -- which yosys-slang then refuses outright: "cannot infer
//           memory from a variable despite 'ram_style' attribute". A
//           hierarchical read from the formal top leaves the inference alone.
//           No loss: storage integrity is a FIFO-internal property, so the
//           standalone proof is the right place for it, and what this file
//           carries is the interface behaviour -- which is what the layer and
//           core proofs need to re-check in context.
///////////////////////////////////////////////////////////////////

module fv_fifo_props #(
    parameter int P_WIDTH = 32,
    parameter int P_DEPTH = 8,
    // Derived; matches the DUT's own localparam.
    parameter int LP_ADDR_W = $clog2(P_DEPTH)
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

    input logic [15:0] level,

    // Internals, reached through the bind.
    input logic [LP_ADDR_W:0] wr_ptr,
    input logic [LP_ADDR_W:0] rd_ptr,
    input logic [LP_ADDR_W:0] mem_count,
    input logic               mem_rd_en
);
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Delayed copies
  //
  // $past is not available: yosys-slang does not implement it, and this whole
  // suite is written in the procedural, clock-edge-sampled style the RTL's own
  // simulation assertions already use -- see the note at the bottom of
  // axis_mixer_fifo.sv for why that style was chosen there. Delaying by hand
  // costs three lines and samples exactly what the hardware samples.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // One real clock edge must have happened before any of the delayed copies
  // below mean anything. They have no reset and no initial value, so in the
  // very first state of a BMC run -- and in every start state of an induction
  // step -- they hold whatever the solver likes, which is history that never
  // happened. Without this guard the step properties fail immediately on
  // fabricated history rather than on a bug.
  //
  // Under induction the solver may still choose fv_started low for the first
  // pre-state, so the induction depth has to be at least 2 for the properties
  // to be non-vacuous at the state being proved. Every prove task here uses
  // considerably more than that.
  logic fv_started = 1'b0;
  always_ff @(posedge clk) fv_started <= 1'b1;

  logic [LP_ADDR_W:0] wr_ptr_d, rd_ptr_d;
  logic wr_fire_d, rd_fire_d, rst_n_d, flush_d, wr_blocked_d;

  logic wr_fire, rd_fire;
  assign wr_fire = wr_en && !full;
  assign rd_fire = mem_rd_en;

  always_ff @(posedge clk) begin
    wr_ptr_d  <= wr_ptr;
    rd_ptr_d  <= rd_ptr;
    wr_fire_d <= wr_fire;
    // A write offered and refused, remembered for one cycle so the pointer can
    // be checked against the offer that was made rather than the one being
    // made now.
    wr_blocked_d <= wr_en && full;
    rd_fire_d <= rd_fire;
    rst_n_d   <= rst_n;
    flush_d   <= flush;
  end

  // True only on cycles where the previous cycle was an ordinary, running one:
  // no reset, no flush. Both of those move the pointers by something other
  // than a transfer, so the step properties must not look across them.
  logic ran;
  assign ran = fv_started && rst_n && rst_n_d && !flush_d;

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Occupancy
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (rst_n) begin
      // The pointers carry one bit more than the address precisely so that
      // this can be true, and everything else rests on it. If occupancy could
      // exceed the depth the pointers would alias and a write would silently
      // land on an unread word.
      a_no_overrun : assert (mem_count <= (LP_ADDR_W + 1)'(P_DEPTH));

      // full is exactly "no room", not an approximation of it. An off-by-one
      // here either drops a pixel or wastes an entry, and one of those is
      // silent.
      a_full_exact : assert (full == (mem_count == (LP_ADDR_W + 1)'(P_DEPTH)));

      // Occupancy reported to software includes the prefetched word, so it can
      // reach P_DEPTH+1 but no further. A layer's L<i>_STATUS.LEVEL is read
      // straight from this.
      a_level_bound : assert (level <= 16'(P_DEPTH + 1));

      // level == 0 has to mean genuinely empty, both in the memory and in the
      // prefetch register, or the status register misleads in the one
      // direction that matters when debugging a starve.
      a_level_empty_iff : assert ((level == 16'd0) == ((mem_count == '0) && !rd_valid));

      // A write offered while full is dropped, not misapplied. The layer holds
      // TREADY low so this should never be offered, but if it is, the pointer
      // must not move -- a moving write pointer on a full FIFO overwrites the
      // oldest unread word and corrupts the stream from that point on.
      if (ran && wr_blocked_d) begin
        a_full_write_dropped : assert (wr_ptr == wr_ptr_d);
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Pointer stepping
  //
  // Together with the storage property below, this is what makes the FIFO a
  // FIFO: consecutive addresses, one at a time, in both directions.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (ran) begin
      a_wr_step : assert (wr_ptr == (wr_fire_d ? (LP_ADDR_W + 1)'(wr_ptr_d + 1'b1) : wr_ptr_d));
      a_rd_step : assert (rd_ptr == (rd_fire_d ? (LP_ADDR_W + 1)'(rd_ptr_d + 1'b1) : rd_ptr_d));
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Read side: first-word fall-through
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic bubble_d;

  always_ff @(posedge clk) begin
    // A word sitting in the memory with the prefetch register empty is the one
    // transient state the read side is allowed: the fetch is already committed
    // and lands next cycle. What it must not do is persist, because the
    // consumer decides whether to pop from rd_valid and cannot wait.
    bubble_d <= !rd_valid && (rd_ptr != wr_ptr);
    if (ran && bubble_d) begin
      a_fwft_no_bubble : assert (rd_valid);
    end

    // The other half of fall-through: rd_valid does not drop while there is
    // still data behind it, so a consumer that pops every cycle is never
    // stalled by the FIFO's own bookkeeping.
    if (ran && rd_fire_d) begin
      a_fetch_presents : assert (rd_valid);
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Flush
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    // A flush has to be complete in one cycle and leave nothing behind. This
    // is what axis_mixer_layer relies on to resynchronise after a fault: if
    // anything survived, the re-armed layer would start from a stale pixel and
    // sit skewed for as long as it ran.
    if (fv_started && rst_n && flush_d) begin
      a_flush_empty : assert (level == 16'd0);
      a_flush_no_valid : assert (!rd_valid);
      a_flush_ptrs : assert (wr_ptr == '0 && rd_ptr == '0);
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Cover
  //
  // Occupancy extremes, so a passing proof cannot be one over an environment
  // that never fills or empties the thing.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (rst_n) begin
      c_full : cover (full);
      c_empty_after_full : cover (fv_started && !rd_valid && (level == 16'd0) && rd_fire_d);
      c_pop_while_full : cover (full && rd_en && rd_valid);
      c_wrap : cover (wr_ptr[LP_ADDR_W] != rd_ptr[LP_ADDR_W]);
    end
  end

endmodule
