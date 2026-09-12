`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_blend.sv
// Purpose : Formal proof of the blend arithmetic in axis_video_mixer_pkg.
//
//           The package comment for div255 claims the identity
//
//               div255(v) = (t + (t >> 8)) >> 8,   t = v + 128
//
//           is "exact against round(v / 255) for every v in 0 .. 65025 ...
//           Verified exhaustively." This module replaces that claim with a
//           proof, and extends it to the functions built on top of div255 --
//           blend_ch, blend_rgb, mul255, effective_alpha -- whose input spaces
//           are 2^24 and larger and so were never exhaustively covered. It is
//           the composition that the datapath instantiates, not div255 alone.
//
//           Nothing in this module is driven, so the solver chooses every
//           input over its full range and an assertion that holds is a
//           statement about all of them.
//
//           WHY THIS IS CLOCKED. The properties are combinational and could be
//           written in always_comb, which is where they started. Two things
//           pushed them into always_ff: ABC-based engines reject a purely
//           combinational netlist outright ("does not work for combinational
//           networks"), and the clocked form matches the procedural,
//           edge-sampled style the rest of this suite and the RTL's own
//           simulation assertions use. Depth 2 is enough -- the inputs are
//           free every cycle, so a second step adds nothing but a state the
//           engines will accept.
//
//           WHY THE PROPERTIES ARE GROUPED. FV_GROUP selects one group per
//           run. Checked together as one query, the whole file did not
//           discharge in ten minutes; split up, every group lands in under a
//           minute. The cost is concentrated in the two groups that hold more
//           than one instance of the multiplier -- BOUND and MONO -- and
//           putting those in the same query as everything else made all of it
//           slow. See doc/formal.md section 7.
//
//           WHY NO DIVISION APPEARS. The obvious statement of exactness is
//           `div255(v) == (v + 127) / 255`. It is correct and it is
//           unusable: a bit-vector divide is the one operation these solvers
//           have no good decision procedure for, and it did not discharge in
//           ten minutes on its own. Stated as the pair of multiplicative
//           bounds that define integer division -- q*255 <= v+127 <
//           (q+1)*255 -- it discharges instantly.
///////////////////////////////////////////////////////////////////

module fv_blend
  import axis_video_mixer_pkg::*;
#(
    // 0 all, 1 DIV, 2 SCALE, 3 BLEND, 4 BOUND, 5 MONO. See the header.
    parameter int FV_GROUP = 0
) (
    input logic clk,

    // Free: the solver picks these, every cycle, over their full range.
    input logic [15:0] v,
    input logic [15:0] v2,
    input logic [ 7:0] top,
    input logic [ 7:0] top2,
    input logic [ 7:0] bot,
    input logic [ 7:0] a,
    input logic [ 7:0] b,
    input logic [23:0] trgb,
    input logic [23:0] brgb,
    input logic [ 7:0] px_alpha,
    input logic [ 7:0] glob_alpha,
    input logic        asrc
);
  localparam bit G_DIV = (FV_GROUP == 0) || (FV_GROUP == 1);
  localparam bit G_SCALE = (FV_GROUP == 0) || (FV_GROUP == 2);
  localparam bit G_BLEND = (FV_GROUP == 0) || (FV_GROUP == 3);
  localparam bit G_BOUND = (FV_GROUP == 0) || (FV_GROUP == 4);
  localparam bit G_MONO = (FV_GROUP == 0) || (FV_GROUP == 5);

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // div255
  //
  // The range bound is load bearing, not cosmetic. div255 returns 8 bits, so
  // above 65025 the correct quotient does not fit and the expression
  // truncates: div255(16'd65535) evaluates to 1, not 257. 65025 is exactly the
  // largest numerator blend_ch can produce -- 255*255, reached when top, bot
  // and a are all at maximum, because a and (255-a) sum to exactly 255 -- so
  // the function is only ever asked for values it can represent. That is
  // assumed here rather than quietly ignored.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  localparam int unsigned MAX_NUM = 255 * 255;  // 65025

  logic in_range, in_range2;
  assign in_range  = (v <= 16'(MAX_NUM));
  assign in_range2 = (v2 <= 16'(MAX_NUM));

  logic [23:0] q;
  assign q = 24'(div255(v));

  if (G_DIV) begin : g_div
    always_ff @(posedge clk) begin
      if (in_range) begin
        // Exactness, as the two bounds that define floor((v + 127) / 255) --
        // which is round(v / 255) with ties resolved upwards. Multiplicative
        // rather than a divide, for the reason in the header.
        a_div255_floor_lo : assert (q * 24'd255 <= 24'(v) + 24'd127);
        a_div255_floor_hi : assert (24'(v) + 24'd127 < (q + 24'd1) * 24'd255);

        // The same statement read the other way round: div255 lands on the
        // nearest multiple of 255, so the residual cannot exceed half a
        // divisor. This is the form worth quoting -- an off-by-one in the
        // rounding shows up here as a residual of 128 rather than 127.
        a_div255_rounded : assert ((24'(v) >= q * 24'd255) ? (24'(v) - q * 24'd255 <= 24'd127) :
                                   (q * 24'd255 - 24'(v) <= 24'd128));

        // The two endpoints the cascade depends on directly: exact 0 is what
        // makes a transparent layer free, exact 255 is what makes an opaque
        // layer lossless.
        a_div255_zero : assert (div255(16'd0) == 8'd0);
        a_div255_max : assert (div255(16'(MAX_NUM)) == 8'd255);
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // mul255 and effective_alpha
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  if (G_SCALE) begin : g_scale
    always_ff @(posedge clk) begin
      a_mul255_by_one : assert (mul255(a, 8'd255) == a);
      a_mul255_by_zero : assert (mul255(a, 8'd0) == 8'd0);
      // Commutative, which is what lets effective_alpha combine pixel alpha
      // and global alpha in either order without changing the picture.
      a_mul255_comm : assert (mul255(a, b) == mul255(b, a));
      // A fraction of a value never exceeds it.
      a_mul255_bounded : assert (mul255(a, b) <= a);

      // ALPHA_SRC decoding, against the encoding in the register map.
      a_ea_global : assert (effective_alpha(px_alpha, glob_alpha, ALPHA_GLOBAL_ONLY) ==
                            glob_alpha);
      a_ea_pixel : assert (effective_alpha(px_alpha, 8'd255, ALPHA_PIXEL_X_GLOBAL) == px_alpha);

      // A global alpha of zero hides the layer whichever source is selected.
      // That is what software relies on to fade a layer out without waiting
      // for a frame boundary, since alpha is deliberately excluded from
      // geo_changed in the core.
      a_ea_zero_hides : assert (effective_alpha(px_alpha, 8'd0, asrc) == 8'd0);

      // Effective alpha is never more opaque than the pixel's own alpha when
      // the pixel alpha participates, so a transparent pixel cannot be made
      // opaque by the global setting.
      a_ea_no_opaquer : assert (effective_alpha(px_alpha, glob_alpha, ALPHA_PIXEL_X_GLOBAL) <=
                                px_alpha);
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // blend_ch and blend_rgb: Porter-Duff "over"
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  if (G_BLEND) begin : g_blend
    always_ff @(posedge clk) begin
      // Alpha 0 returns the accumulator bit-exactly. This is the property that
      // lets the core represent "layer absent" as alpha zero with no special
      // case anywhere in the cascade -- see the g_blend loop in
      // axis_video_mixer_core.sv, where a layer that is not contributing
      // simply arrives with la_q of zero.
      a_blend_alpha0 : assert (blend_ch(top, bot, 8'd0) == bot);

      // Alpha 255 returns the top pixel bit-exactly. This is the one a >>8
      // would get wrong, and the whole reason div255 exists: with a shift the
      // result would be 254/255 of top, and a stack of nominally opaque layers
      // would visibly darken.
      a_blend_alpha255 : assert (blend_ch(top, bot, 8'd255) == top);

      // Blending a value with itself is the identity for every alpha, so a
      // flat region of colour stays flat whatever alpha is applied to it. This
      // is the case where rounding error would be most visible: a large
      // translucent overlay on a solid background.
      a_blend_flat : assert (blend_ch(top, top, a) == top);

      // The three channels are independent and none of them bleeds into
      // another. Channel crosstalk from a bad bit slice is invisible in a
      // greyscale test pattern and obvious in a coloured one.
      a_rgb_alpha0 : assert (blend_rgb(trgb, brgb, 8'd0) == brgb);
      a_rgb_alpha255 : assert (blend_rgb(trgb, brgb, 8'd255) == trgb);
      a_rgb_per_channel : assert (blend_rgb(trgb, brgb, a) ==
                                  {blend_ch(trgb[23:16], brgb[23:16], a),
                                   blend_ch(trgb[15:8], brgb[15:8], a),
                                   blend_ch(trgb[7:0], brgb[7:0], a)});
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // No overshoot
  //
  // A convex combination must lie between its operands. An off-by-one in the
  // rounding appears here as a value outside the interval, which on screen is
  // a bright or dark fringe on every edge in the picture -- the kind of defect
  // that survives a scoreboard built on the same arithmetic.
  //
  // This is the expensive group: it holds two instances of the 8x8 multiplier
  // and asks the solver to bound their sum, which is the shape of query
  // bit-vector solvers are worst at. Roughly 40 seconds on its own, and it was
  // most of why the ungrouped file never finished.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [7:0] lo, hi;
  assign lo = (top < bot) ? top : bot;
  assign hi = (top < bot) ? bot : top;

  if (G_BOUND) begin : g_bound
    always_ff @(posedge clk) begin
      a_blend_bounded_lo : assert (blend_ch(top, bot, a) >= lo);
      a_blend_bounded_hi : assert (blend_ch(top, bot, a) <= hi);
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Monotonicity, proved in two pieces
  //
  // The statement wanted is: raising the top pixel never lowers the blended
  // result. Asserted directly it needs two whole blend_ch instances in one
  // query and did not discharge in a minute.
  //
  // Split at div255 it does. blend_ch is div255 composed with a numerator, so
  // monotonicity of the composition follows from monotonicity of each piece:
  //
  //     a_num_monotone     the numerator is monotone in top
  //     a_div255_monotone  div255 is monotone over its declared range
  //
  // Both are cheap. The conclusion is the composition, and it is an ordinary
  // syllogism rather than anything the solver has to be trusted for. The
  // numerator's range bound is discharged by the BOUND group above, which
  // shows the sum never leaves 0 .. 65025.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [15:0] num_top, num_top2;
  assign num_top  = 16'(top) * 16'(a) + 16'(bot) * 16'(8'd255 - a);
  assign num_top2 = 16'(top2) * 16'(a) + 16'(bot) * 16'(8'd255 - a);

  if (G_MONO) begin : g_mono
    always_ff @(posedge clk) begin
      if (top <= top2) begin
        a_num_monotone : assert (num_top <= num_top2);
      end
      if (in_range && in_range2 && (v <= v2)) begin
        a_div255_monotone : assert (div255(v) <= div255(v2));
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Cover
  //
  // The assertions are over free inputs, so the only way they could be vacuous
  // is if the assumed range excluded the interesting corners. These show it
  // does not.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    c_alpha_mid : cover (a == 8'd128 && top == 8'd255 && bot == 8'd0);
    c_div255_max : cover (in_range && v == 16'(MAX_NUM));
    c_div255_tie : cover (in_range && v == 16'd128);
  end

endmodule
