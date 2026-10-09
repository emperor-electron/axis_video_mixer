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
  // Layer inputs are RGBA with a MIX_CH_W-bit component, so a pixel is four of
  // those -- 32, 40, 48 or 64 bits, always a whole number of bytes. The output
  // is the same when the DUT is built with alpha, which is how the testbench
  // builds it: checking the alpha component is forced to full scale is itself
  // worth doing.
  //
  // TUSER is one bit, SOF, matching the video AXI4-Stream convention used
  // throughout this pipeline.
  //
  // The layer count and canvas size are NOT here. They are parameters of
  // mixer_tb_top so that xelab --generic_top can shrink the raster for a fast
  // regression without touching the link types.
  // ---------------------------------------------------------------------
  // Pixels per beat, and the colour component width. Compile-time defines
  // rather than parameters because a SystemVerilog package cannot be
  // parameterised, and the link WIDTH -- which the UVC types below are
  // specialised on -- follows from both.
  //
  //   make PPC=4 regress
  //   make CH_W=12 regress
  //
`ifndef MIX_PPC
`define MIX_PPC 1
`endif
  parameter int MIX_PPC = `MIX_PPC;

`ifndef MIX_CH_W
`define MIX_CH_W 8
`endif
  parameter int MIX_CH_W = `MIX_CH_W;

  parameter int MIX_PX_W = 4 * MIX_CH_W;  // one pixel, {R, G, B, A}
  parameter int MIX_RGB_W = 3 * MIX_CH_W;  // a colour, alpha dropped
  parameter int MIX_PX_BYTES = MIX_PX_W / 8;  // 4, 5, 6 or 8
  // Full scale: what "opaque" is, and what the blend divides by.
  parameter longint unsigned MIX_MAX = (longint'(1) << MIX_CH_W) - 1;

  parameter int MIX_DATA_BYTES = MIX_PX_BYTES * MIX_PPC;  // lane 0 in the low bytes
  parameter int MIX_ID_WIDTH   = 0;
  parameter int MIX_DEST_WIDTH = 0;
  parameter int MIX_USER_WIDTH = 1;  // TUSER[0] = SOF

  // The number of stream ports the DUT brings out, which is the most any build
  // can instantiate.
  parameter int MIX_MAX_LAYERS = 8;

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
  // Golden blend arithmetic.
  //
  // Written out independently rather than by importing axis_video_mixer_pkg.
  // Sharing the functions would make the model agree with the DUT by
  // construction, which is precisely the agreement a scoreboard exists to
  // test. The RTL uses a shift-and-add identity; this uses integer division,
  // so the two only agree if the identity is actually right.
  // ---------------------------------------------------------------------
  function automatic logic [MIX_CH_W-1:0] gold_div_max(longint unsigned v);
    // round(v / MIX_MAX), half away from zero. A real divide, which is the
    // point: the RTL uses a shift-and-add identity instead.
    return MIX_CH_W'((2 * v + MIX_MAX) / (2 * MIX_MAX));
  endfunction

  function automatic logic [MIX_CH_W-1:0] gold_mul_max(logic [MIX_CH_W-1:0] a,
                                                       logic [MIX_CH_W-1:0] b);
    return gold_div_max(longint'(a) * longint'(b));
  endfunction

  function automatic logic [MIX_CH_W-1:0] gold_blend_ch(logic [MIX_CH_W-1:0] top,
                                                        logic [MIX_CH_W-1:0] bot,
                                                        logic [MIX_CH_W-1:0] a);
    return gold_div_max(longint'(top) * longint'(a) +
                        longint'(bot) * (MIX_MAX - longint'(a)));
  endfunction

  function automatic logic [MIX_RGB_W-1:0] gold_blend_rgb(logic [MIX_RGB_W-1:0] top,
                                                          logic [MIX_RGB_W-1:0] bot,
                                                          logic [MIX_CH_W-1:0] a);
    return {gold_blend_ch(top[3*MIX_CH_W-1-:MIX_CH_W], bot[3*MIX_CH_W-1-:MIX_CH_W], a),
            gold_blend_ch(top[2*MIX_CH_W-1-:MIX_CH_W], bot[2*MIX_CH_W-1-:MIX_CH_W], a),
            gold_blend_ch(top[MIX_CH_W-1:0], bot[MIX_CH_W-1:0], a)};
  endfunction

  // The 8-bit register fields -- L<i>_CTRL.ALPHA and BACKGROUND.RGB -- stay 8
  // bits whatever the component width and are expanded by bit replication.
  // Written out independently of the RTL's ch_up for the same reason as
  // everything else here.
  function automatic logic [MIX_CH_W-1:0] gold_up(logic [7:0] v);
    return MIX_CH_W'(((longint'(v) << (MIX_CH_W - 8)) | (longint'(v) >> (16 - MIX_CH_W))) &
                     MIX_MAX);
  endfunction

  function automatic logic [MIX_RGB_W-1:0] gold_rgb_up(logic [23:0] c);
    return {gold_up(c[23:16]), gold_up(c[15:8]), gold_up(c[7:0])};
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
  // One component of the pattern. The high 8 bits are the original 8-bit
  // pattern expanded to the component width, so at MIX_CH_W = 8 this function
  // reduces exactly to what it was and the regression stimulus is unchanged.
  // The low bits below bit 8 carry a second, differently shaped pattern, so a
  // wider build actually exercises the precision it was built for instead of
  // running an 8-bit picture through a wider bus.
  function automatic logic [MIX_CH_W-1:0] layer_component(int unsigned seed,
                                                          int unsigned low);
    longint unsigned lsbs = longint'(low) % (longint'(1) << (MIX_CH_W - 8));
    return MIX_CH_W'((longint'(gold_up(8'(seed & 32'hFF))) ^ lsbs) & MIX_MAX);
  endfunction

  function automatic logic [MIX_PX_W-1:0] layer_pixel(int unsigned layer, int unsigned x,
                                                      int unsigned y);
    logic [MIX_CH_W-1:0] r, g, b, a;
    r = layer_component(layer * 37 + x * 3 + y, x + y);
    g = layer_component(layer * 71 + y * 5 + x * 2, x * 3 + y);
    b = layer_component(layer * 113 + x + y * 7, x + y * 5);
    a = layer_component(layer * 29 + x * 7 + y * 3, x * 7 + y);
    return {r, g, b, a};
  endfunction

  `include "mixer_seq_lib.sv"
  `include "mixer_scoreboard.sv"
  `include "mixer_env.sv"
  `include "mixer_base_test.sv"

endpackage : mixer_tb_pkg
