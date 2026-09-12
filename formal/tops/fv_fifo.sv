`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_fifo.sv
// Purpose : Formal top for axis_mixer_fifo on its own, against a completely
//           free environment.
//
//           Everything not driven here is a free input, so the solver drives
//           wr_en, rd_en, flush and rst_n however it likes, in any
//           combination, every cycle. That is a far harsher producer and
//           consumer than the layer will ever be, and deliberately so: the
//           FIFO is the one block in this design that is reused three times
//           over, and its invariants should not depend on being driven
//           politely.
//
//           The properties themselves live in props/fv_fifo_props.sv, bound in
//           rather than instantiated here, so the same file is checked again
//           inside fv_layer and fv_core.
//
//           P_DEPTH is 8, not the 2048 the design ships with. Depth enters the
//           proof only through the pointer width, and the pointer arithmetic
//           is the same at 8 as at 2048 -- while the memory the solver has to
//           model is 256 times smaller. The depth task raises it to check that
//           nothing was accidentally specific to a 3-bit address.
///////////////////////////////////////////////////////////////////

module fv_fifo #(
    // 8 bits rather than 32: the properties are about addressing and
    // bookkeeping, not about how wide a word is, and every bit of payload is a
    // bit the solver carries through the shadow register.
    parameter int P_WIDTH = 8,
    parameter int P_DEPTH = 8
) (
    input logic clk,

    // Free. flush is the FIFO's mid-stream resynchronisation, and the RTL
    // treats `!rst_n || flush` identically everywhere, so leaving this free
    // covers a reset arriving at any point without also having to model one.
    input logic flush,

    // Free producer.
    input logic               wr_en,
    input logic [P_WIDTH-1:0] wr_data,

    // Free consumer, constrained only by the one obligation below.
    input logic rd_en
);
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Modelled reset
  //
  // Reset cannot be left free here, and the reason is worth stating because it
  // is the first thing a proof of this block runs into. wr_ptr and rd_ptr have
  // no initial value -- they are only ever cleared by `!rst_n || flush` -- so
  // in the very first state of a BMC run they hold whatever the solver likes,
  // including a pair that makes the occupancy nine entries of an eight-entry
  // FIFO. a_no_overrun fails on that immediately, and correctly: the
  // invariants of this block hold after a reset, not before one.
  //
  // One cycle is enough. Every register the invariants speak about is cleared
  // synchronously by that single edge. Mid-stream resets are not lost by
  // pinning reset here, because flush above is free and the RTL's reset and
  // flush paths are literally the same expression.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic rst_n;
  logic fv_in_reset = 1'b1;
  always_ff @(posedge clk) fv_in_reset <= 1'b0;
  assign rst_n = !fv_in_reset;

  logic               full;
  logic               rd_valid;
  logic [P_WIDTH-1:0] rd_data;
  logic [        15:0] level;

  axis_mixer_fifo #(
      .P_WIDTH(P_WIDTH),
      .P_DEPTH(P_DEPTH)
  ) dut (
      .clk  (clk),
      .rst_n(rst_n),
      .flush(flush),

      .wr_en  (wr_en),
      .wr_data(wr_data),
      .full   (full),

      .rd_valid(rd_valid),
      .rd_data (rd_data),
      .rd_en   (rd_en),

      .level(level)
  );

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // The one environment obligation
  //
  // A pop with nothing to pop is not something the FIFO can defend against --
  // rd_en is an input and the RTL cannot refuse it -- so here it is assumed.
  // The RTL says the same thing as a simulation assertion, for the same
  // reason.
  //
  // An assumption is only as good as the proof that something discharges it,
  // and this one is discharged twice: fv_layer_props asserts that
  // axis_mixer_layer never pops empty, and fv_core_props asserts it for every
  // layer of the core. Without those two this would be the weak point of the
  // whole FIFO result.
  //
  // Note what is NOT assumed: writes while full. The FIFO is required to drop
  // those without disturbing its pointers, and a_full_write_dropped asserts
  // exactly that, so the solver is free to try it.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (rst_n) begin
      m_no_pop_when_empty : assume (!(rd_en && !rd_valid));
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Storage integrity at an arbitrary address
  //
  // This is the property that says the memory is a memory: what comes out of
  // address k is what last went into address k. Together with the unit pointer
  // steps and the occupancy bounds proved in fv_fifo_props.sv, it is what
  // makes the block a FIFO -- see the note at the top of that file.
  //
  // It is here rather than in the bound property module for a tool reason.
  // Reading the array means getting at it, and a bind port connection forces
  // the array to a plain variable, which yosys-slang then refuses: "cannot
  // infer memory from a variable despite 'ram_style' attribute". A
  // hierarchical read from the formal top -- dut.mem[fv_k] below -- leaves the
  // inference alone and costs nothing.
  //
  // fv_k is a free constant: a register that holds itself, never resets and
  // has no initial value, so formal leaves its value unconstrained and it
  // stays put. That is $anyconst; yosys-slang does not implement $anyconst and
  // this is the portable spelling. Proving the property at an arbitrary
  // address proves it at every address, using one shadow register rather than
  // a model of the whole memory.
  //
  // Two properties, and the order matters. a_shadow_tracks_mem is the
  // inductive invariant: the shadow holds what the memory holds at address k.
  // a_storage_readback is the consequence: a memory read at address k lands
  // that value in rd_data on the next cycle.
  //
  // Written with only the second of the two this was provable by BMC and not
  // by induction, and the reason is worth keeping. Induction starts from an
  // arbitrary state, in which the memory and the shadow are independent, so
  // the solver picks a state where they disagree and reads it back. Asserting
  // the relation between them closes that door, because k-induction gets to
  // assume every asserted property in the pre-states. Comparing the shadow one
  // cycle delayed also sidesteps the question of a write to address k landing
  // in the same cycle as a read from it.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  localparam int LP_ADDR_W = $clog2(P_DEPTH);

  logic [LP_ADDR_W-1:0] fv_k;
  always_ff @(posedge clk) fv_k <= fv_k;

  logic fv_started = 1'b0;
  always_ff @(posedge clk) fv_started <= 1'b1;

  logic [P_WIDTH-1:0] shadow, shadow_d;
  logic               shadow_vld, shadow_vld_d;
  logic               read_k_d;

  always_ff @(posedge clk) begin
    // Deliberately not cleared by flush: flush resets the pointers but does
    // not erase the memory, and neither does this.
    if (!rst_n) begin
      shadow_vld <= 1'b0;
    end else if (wr_en && !full && (dut.wr_ptr[LP_ADDR_W-1:0] == fv_k)) begin
      shadow     <= wr_data;
      shadow_vld <= 1'b1;
    end

    shadow_d     <= shadow;
    shadow_vld_d <= shadow_vld;
    // !flush matters: a flush in the same cycle as a memory read clears
    // rd_data to zero rather than letting the fetched word land, so there is
    // nothing to check on the cycle after one.
    read_k_d     <= rst_n && !flush && dut.mem_rd_en && (dut.rd_ptr[LP_ADDR_W-1:0] == fv_k);
  end

  always_ff @(posedge clk) begin
    // shadow_vld guards against a start state holding something this checker
    // never saw written. Under BMC from reset it simply means "address k has
    // been written at least once".
    if (rst_n && shadow_vld) begin
      a_shadow_tracks_mem : assert (shadow == dut.mem[fv_k]);
    end

    if (fv_started && rst_n && read_k_d && shadow_vld_d) begin
      a_storage_readback : assert (rd_data == shadow_d);
    end

    // The tracked word really is read back, and from an address other than
    // zero, so the proof is not passing on runs that never reach address k.
    if (rst_n) begin
      c_storage_checked : cover (read_k_d && shadow_vld_d && (fv_k != '0));
    end
  end

endmodule
