///////////////////////////////////////////////////////////////////
// Filename: mixer_tb_pkg.sv
// Author  : Benjamin Tamayo
// Date    : 09/06/2026
// Purpose : Testbench package for axis_video_mixer. Declares the link
//           geometries once, the layer content function the stimulus and the
//           golden model share, and the register offsets the tests use.
///////////////////////////////////////////////////////////////////

package mixer_tb_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi_stream_pkg::*;
  import axi_lite_pkg::*;

  // ---------------------------------------------------------------------
  // Link geometry.
  //
  // Layer inputs are RGBA8: four bytes. The output is the same when the DUT is
  // built with alpha, which is how the testbench builds it -- checking the
  // alpha byte is forced opaque is itself worth doing.
  //
  // TUSER is one bit, SOF, matching the video AXI4-Stream convention used
  // throughout this pipeline.
  //
  // The layer count and canvas size are NOT here. They are parameters of
  // mixer_tb_top so that xelab --generic_top can shrink the raster for a fast
  // regression without touching the link types.
  // ---------------------------------------------------------------------
  parameter int MIX_DATA_BYTES = 4;  // RGBA8
  parameter int MIX_ID_WIDTH   = 0;
  parameter int MIX_DEST_WIDTH = 0;
  parameter int MIX_USER_WIDTH = 1;  // TUSER[0] = SOF

  parameter int MIX_MAX_LAYERS = 16;

  typedef virtual axi_stream_if #(MIX_DATA_BYTES, MIX_ID_WIDTH, MIX_DEST_WIDTH,
                                  MIX_USER_WIDTH) mix_vif_t;

  typedef axi_stream_agent #(MIX_DATA_BYTES, MIX_ID_WIDTH, MIX_DEST_WIDTH,
                             MIX_USER_WIDTH) mix_agent_t;

  typedef virtual axi_lite_if #(12, 32) mix_axil_vif_t;
  typedef axi_lite_agent #(12, 32) mix_axil_agent_t;

  // ---------------------------------------------------------------------
  // Register offsets, mirrored from regs/regs.json.
  //
  // Deliberately hand-written rather than imported from the generated C
  // header: the tests are meant to prove the map the software will see, and a
  // model derived from the same generator as the DUT would agree with a wrong
  // map just as readily as with a right one.
  // ---------------------------------------------------------------------
  parameter int unsigned REG_ID          = 'h00;
  parameter int unsigned REG_CAPS        = 'h04;
  parameter int unsigned REG_SCRATCH     = 'h08;
  parameter int unsigned REG_CTRL        = 'h0C;
  parameter int unsigned REG_CANVAS      = 'h10;
  parameter int unsigned REG_BACKGROUND  = 'h14;
  parameter int unsigned REG_STATUS      = 'h18;
  parameter int unsigned REG_FRAME_COUNT = 'h1C;
  parameter int unsigned REG_ERR         = 'h20;
  parameter int unsigned REG_ERR_LAYER   = 'h24;
  parameter int unsigned REG_IRQ_EN      = 'h28;
  parameter int unsigned REG_STALL_LIMIT = 'h2C;

  parameter int unsigned REG_LAYER_BASE   = 'h40;
  parameter int unsigned REG_LAYER_STRIDE = 'h10;
  parameter int unsigned REG_L_CTRL       = 'h0;
  parameter int unsigned REG_L_POS        = 'h4;
  parameter int unsigned REG_L_SIZE       = 'h8;
  parameter int unsigned REG_L_STATUS     = 'hC;

  // ERR bit positions.
  parameter int unsigned ERR_CFG       = 0;
  parameter int unsigned ERR_STARVE    = 1;
  parameter int unsigned ERR_GEOM      = 2;
  parameter int unsigned ERR_SRC_STALL = 3;
  parameter int unsigned ERR_OUT_STALL = 4;

  function automatic int unsigned layer_reg(int unsigned layer, int unsigned which);
    return REG_LAYER_BASE + layer * REG_LAYER_STRIDE + which;
  endfunction

  // ---------------------------------------------------------------------
  // Layer content.
  //
  // Every layer's pixels come from this one function, so the stimulus and the
  // golden model never have to exchange data -- the scoreboard recomputes what
  // the sequence sent. That is what lets the model predict a composite without
  // subscribing to N input monitors and re-deriving their framing.
  //
  // The coefficients matter more than they look. Each channel varies with both
  // x and y so a layer transposed or offset by a line is not self-similar
  // enough to pass by accident, each layer differs from every other so a
  // z-order mistake cannot go unnoticed, and alpha sweeps the full 0..255
  // range so the blend is exercised at both ends and everywhere between --
  // including the exact values, 0 and 255, where a divide-by-256 approximation
  // would still look plausible but be wrong.
  // ---------------------------------------------------------------------
  function automatic logic [31:0] layer_pixel(int unsigned layer, int unsigned x,
                                              int unsigned y);
    logic [7:0] r, g, b, a;
    r = 8'((layer * 37 + x * 3 + y) & 32'hFF);
    g = 8'((layer * 71 + y * 5 + x * 2) & 32'hFF);
    b = 8'((layer * 113 + x + y * 7) & 32'hFF);
    a = 8'((layer * 29 + x * 7 + y * 3) & 32'hFF);
    return {r, g, b, a};
  endfunction

  // ---------------------------------------------------------------------
  // Golden blend arithmetic.
  //
  // Written out independently rather than by importing axis_video_mixer_pkg.
  // Sharing the functions would make the model agree with the DUT by
  // construction, which is precisely the agreement a scoreboard exists to
  // test. The RTL uses a shift-and-add identity; this uses integer division,
  // so the two only agree if the identity is actually right.
  // ---------------------------------------------------------------------
  function automatic logic [7:0] gold_div255(int unsigned v);
    // round(v / 255), half away from zero.
    return 8'((2 * v + 255) / 510);
  endfunction

  function automatic logic [7:0] gold_mul255(logic [7:0] a, logic [7:0] b);
    return gold_div255(int'(a) * int'(b));
  endfunction

  function automatic logic [7:0] gold_blend_ch(logic [7:0] top, logic [7:0] bot,
                                               logic [7:0] a);
    return gold_div255(int'(top) * int'(a) + int'(bot) * (255 - int'(a)));
  endfunction

  function automatic logic [23:0] gold_blend_rgb(logic [23:0] top, logic [23:0] bot,
                                                 logic [7:0] a);
    return {gold_blend_ch(top[23:16], bot[23:16], a), gold_blend_ch(top[15:8], bot[15:8], a),
            gold_blend_ch(top[7:0], bot[7:0], a)};
  endfunction

  `include "mixer_seq_lib.sv"
  `include "mixer_scoreboard.sv"
  `include "mixer_env.sv"
  `include "mixer_base_test.sv"

endpackage : mixer_tb_pkg
