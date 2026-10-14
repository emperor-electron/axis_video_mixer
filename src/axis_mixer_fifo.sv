`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: axis_mixer_fifo.sv
// Author  : Benjamin Tamayo
// Date    : 09/06/2026
// Purpose : Synchronous first-word-fall-through FIFO, one per mixer layer.
//
//           This is the elasticity that lets a layer smaller than the canvas
//           work at all. The output raster consumes a layer's pixels only while
//           the scan is inside that layer's window -- w pixels out of every W on
//           the lines it covers, and none at all on the lines it does not. The
//           source, meanwhile, delivers at whatever rate it likes. The FIFO
//           absorbs the difference.
//
//           Depth therefore has to cover the worst case, which is a layer whose
//           window starts at x = 0: the source gets no in-line head start, so
//           everything it will need for that line must already be buffered when
//           the line begins. One full layer line is the safe sizing, hence a
//           default depth of 2048 covering any width up to 1920.
//
//           First-word fall-through matters because the consumer decides
//           whether to pop based on whether data is there -- it cannot afford a
//           read-latency cycle inside the blend pipeline. The prefetch register
//           below provides that while keeping the storage in a hard memory
//           rather than in LUTs, which at 2048 x 32 bits per layer it must be.
//
//           BLOCK RAM OR ULTRARAM. P_RAM_STYLE picks the primitive: "block"
//           for RAMB18/RAMB36, "ultra" for URAM288 on UltraScale+. The code
//           below is written to the INTERSECTION of what the two will accept,
//           so the parameter changes the attribute and nothing else.
//
//           What UltraRAM requires, and where each requirement is met:
//
//             One clock. URAM288 is a single-clock macro -- there is no
//             independent second clock domain on it at all. This FIFO has
//             always been synchronous, so this is free, and it is the reason
//             the choice is available here and would not be across a CDC.
//
//             A synchronous read. No asynchronous or distributed read path.
//             Met: the read is registered into mem_dout and nothing reads the
//             array combinationally.
//
//             No reset on the array. URAM has no way to clear its storage.
//             Met: flush resets the POINTERS and nothing else -- the array
//             keeps whatever it held, which is why flush is one cycle rather
//             than P_DEPTH of them, and why this was already true before
//             UltraRAM was a consideration.
//
//             No read-first behaviour at a colliding address. URAM does not
//             implement read-before-write, so a read and a write to the same
//             address in the same cycle would have to be resolved in fabric.
//             Met structurally, and this one is worth the argument: a read
//             needs rd_ptr != wr_ptr, so the two addresses differ unless they
//             are exactly P_DEPTH apart, which is the full condition -- and a
//             write while full is gated off. So the collision cannot occur.
//             See the assertions at the bottom.
//
//           mem_dout carries a synchronous clear, which was the one thing
//           worth checking: a clear the macro cannot take has to be built from
//           fabric flops beside it, P_WIDTH of them, which at a 512-bit beat is
//           not a rounding error. It does not come to that. Vivado 2023.2 on
//           xczu7ev, 32 x 2048: 26 flops with "block" against 25 with "ultra",
//           so the read register is inside the macro either way.
//
//           What Vivado does NOT do is merge URAM's OPTIONAL output register,
//           and it says so -- Synth 8-7052, "no optional output register could
//           be merged into the ram block". That register would cost a second
//           cycle of read latency, which this FIFO does not have and does not
//           want, so declining it is correct rather than a missed
//           optimisation. The accompanying advice to pipeline for high
//           performance is real but not binding here: at the 148.5 MHz this
//           design targets, "block" closes with 5.015 ns of slack and "ultra"
//           with 5.018 ns. Push the clock far enough and URAM without an
//           output register becomes the limit; at 1080p60 it is nowhere near.
//
//           The clear is kept rather than dropped because without it rd_data
//           holds X until the first read, and X multiplied by an alpha of zero
//           is X rather than zero, so it would reach the blend in simulation
//           even though the hardware would mask it.
//
//           All of the above is Vivado 2023.2, synth_design out-of-context.
//           The FIFO's BEHAVIOUR under both settings is verified separately:
//           bit-identical to the pre-parameter FIFO over 6000 cycles of random
//           traffic including flush, and proved again by fv_fifo's ultra task.
///////////////////////////////////////////////////////////////////

module axis_mixer_fifo #(
    parameter int P_WIDTH = 32,
    parameter int P_DEPTH = 2048,  // must be a power of two
    // "block" for RAMB18/RAMB36, "ultra" for URAM288 on UltraScale+. Nothing
    // but the synthesis attribute changes; see the header for the argument
    // that the coding style below suits both.
    parameter string P_RAM_STYLE = "block"
) (
    input logic clk,
    input logic rst_n,

    // Synchronous flush. Empties the FIFO in one cycle, discarding everything.
    // Used to resynchronise a layer after a fault or a geometry change.
    input logic flush,

    input  logic               wr_en,
    input  logic [P_WIDTH-1:0] wr_data,
    output logic               full,

    // Read side. rd_valid and rd_data present the head combinationally; assert
    // rd_en for one cycle to consume it.
    output logic               rd_valid,
    output logic [P_WIDTH-1:0] rd_data,
    input  logic               rd_en,

    // Total occupancy including the prefetch register, for the status register.
    output logic [15:0] level
);
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Local Parameters
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  localparam int LP_ADDR_W = $clog2(P_DEPTH);

  // Caught here rather than silently falling through to "block", because a
  // typo in a string parameter that quietly selects the other primitive is a
  // resource surprise found at place and route rather than at elaboration.
  if ((P_RAM_STYLE != "block") && (P_RAM_STYLE != "ultra")) begin : g_bad_ram_style
    $fatal(1, "axis_mixer_fifo: P_RAM_STYLE must be \"block\" or \"ultra\", got \"%s\"",
           P_RAM_STYLE);
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Storage
  //
  // The pointers carry one bit more than the address so that full and empty are
  // distinguishable without sacrificing an entry.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [LP_ADDR_W:0] wr_ptr;
  logic [LP_ADDR_W:0] rd_ptr;
  logic [LP_ADDR_W:0] mem_count;

  logic mem_rd_en;
  // The array's output register. It is the prefetch register: FWFT does not
  // cost a stage on top of the memory read, it IS the memory read.
  logic [P_WIDTH-1:0] mem_dout;
  logic               mem_clr;

  assign mem_count = wr_ptr - rd_ptr;
  assign full      = (mem_count == (LP_ADDR_W + 1)'(P_DEPTH));

  // Occupancy counts the prefetched word too, otherwise a FIFO holding exactly
  // one pixel would report empty and the status register would mislead.
  assign level = 16'(mem_count) + 16'(rd_valid);

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // The array itself
  //
  // Two declarations rather than one, because `ram_style` takes a string
  // LITERAL -- there is no spelling of the attribute that reads a parameter --
  // so choosing the primitive means choosing the declaration. The bodies are
  // deliberately character-for-character identical: if they ever diverge, the
  // two styles stop being the same FIFO, which is the one thing this
  // parameter must not do.
  //
  // Write and read live in the same process on purpose. Both Vivado and
  // yosys-slang infer a memory more reliably when one process owns the array
  // and its output register, and splitting them is how a 2048-deep buffer
  // quietly becomes flops.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  assign mem_clr = !rst_n || flush;

  if (P_RAM_STYLE == "ultra") begin : g_ultra
    (* ram_style = "ultra" *) logic [P_WIDTH-1:0] mem[P_DEPTH];

    always_ff @(posedge clk) begin
      if (wr_en && !full) mem[wr_ptr[LP_ADDR_W-1:0]] <= wr_data;
      if (mem_clr) mem_dout <= '0;
      else if (mem_rd_en) mem_dout <= mem[rd_ptr[LP_ADDR_W-1:0]];
    end
  end else begin : g_block
    (* ram_style = "block" *) logic [P_WIDTH-1:0] mem[P_DEPTH];

    always_ff @(posedge clk) begin
      if (wr_en && !full) mem[wr_ptr[LP_ADDR_W-1:0]] <= wr_data;
      if (mem_clr) mem_dout <= '0;
      else if (mem_rd_en) mem_dout <= mem[rd_ptr[LP_ADDR_W-1:0]];
    end
  end

  assign rd_data = mem_dout;

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Write pointer
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (!rst_n || flush) begin
      wr_ptr <= '0;
    end else if (wr_en && !full) begin
      wr_ptr <= wr_ptr + 1'b1;
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Read side with prefetch
  //
  // Fetch whenever the memory holds something and the prefetch register is
  // either empty or being consumed this cycle. That single condition covers all
  // four combinations of rd_valid and rd_en without a state machine.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  assign mem_rd_en = (rd_ptr != wr_ptr) && (!rd_valid || rd_en);

  always_ff @(posedge clk) begin
    if (!rst_n || flush) begin
      rd_ptr   <= '0;
      rd_valid <= 1'b0;
    end else begin
      if (mem_rd_en) begin
        rd_ptr   <= rd_ptr + 1'b1;
        rd_valid <= 1'b1;
      end else if (rd_en) begin
        rd_valid <= 1'b0;
      end
    end
  end

`ifdef SIMULATION
  // These are procedural rather than concurrent assertions, deliberately.
  //
  // rd_en is combinational and derives from rd_valid, so `rd_en |-> rd_valid`
  // is structurally impossible to violate on settled values. Written as an
  // `assert property` it nevertheless fired thousands of times under XSIM,
  // reporting rd_en=1 alongside rd_valid=1 in the same message -- the assertion
  // was being evaluated on an intermediate delta, before the combinational
  // network resettled after rd_valid updated.
  //
  // Checking at the clock edge in an always_ff samples exactly what the
  // hardware samples: the values as they stood before the edge. That is the
  // property worth checking, and it is the one that holds.
  always_ff @(posedge clk) begin
    if (rst_n) begin
      // A pop with nothing to pop would silently duplicate a pixel and shift
      // the whole layer by one, which on screen looks like a subtle diagonal
      // tear rather than an obvious fault.
      if (rd_en && !rd_valid) begin
        $error("RTL-ASSERT axis_mixer_fifo: rd_en asserted while rd_valid low");
      end
      // The layer holds TREADY low while full, so a write attempt here means
      // that gating is broken. The write is dropped either way.
      if (wr_en && full) begin
        $error("RTL-ASSERT axis_mixer_fifo: write attempted while full, pixel dropped");
      end
      // UltraRAM has no read-first mode, so a read and a write to one address
      // in one cycle would have to be resolved outside the macro. The header
      // argues it cannot happen; this is that argument made checkable, and
      // fv_fifo proves it outright.
      if ((wr_en && !full) && mem_rd_en &&
          (wr_ptr[LP_ADDR_W-1:0] == rd_ptr[LP_ADDR_W-1:0])) begin
        $error({"RTL-ASSERT axis_mixer_fifo: same-address read and write in one cycle, ",
                "which UltraRAM cannot resolve"});
      end
    end
  end

`endif

endmodule
