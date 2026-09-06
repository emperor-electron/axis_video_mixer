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
//           below provides that while keeping the storage in block RAM rather
//           than in LUTs, which at 2048 x 32 bits per layer it must be.
///////////////////////////////////////////////////////////////////

module axis_mixer_fifo #(
    parameter int P_WIDTH = 32,
    parameter int P_DEPTH = 2048  // must be a power of two
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

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Storage
  //
  // The pointers carry one bit more than the address so that full and empty are
  // distinguishable without sacrificing an entry.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  (* ram_style = "block" *) logic [P_WIDTH-1:0] mem[P_DEPTH];

  logic [LP_ADDR_W:0] wr_ptr;
  logic [LP_ADDR_W:0] rd_ptr;
  logic [LP_ADDR_W:0] mem_count;

  logic mem_rd_en;

  assign mem_count = wr_ptr - rd_ptr;
  assign full      = (mem_count == (LP_ADDR_W + 1)'(P_DEPTH));

  // Occupancy counts the prefetched word too, otherwise a FIFO holding exactly
  // one pixel would report empty and the status register would mislead.
  assign level = 16'(mem_count) + 16'(rd_valid);

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Write side
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (wr_en && !full) begin
      mem[wr_ptr[LP_ADDR_W-1:0]] <= wr_data;
    end
  end

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
      rd_data  <= '0;
    end else begin
      if (mem_rd_en) begin
        rd_data  <= mem[rd_ptr[LP_ADDR_W-1:0]];
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
    end
  end

`endif

endmodule
