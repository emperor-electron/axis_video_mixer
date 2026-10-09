`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_blend.sv
// Purpose : Formal proof of the blend arithmetic in axis_video_mixer_pkg, at
//           every component width the mixer supports.
//
//           The package comment for div_max claims the identity
//
//               div_max(C, v) = (t + (t >> C)) >> C,   t = v + 2**(C-1)
//
//           is exact against round(v / (2**C - 1)) for every v the blend can
//           produce, at C = 8, 10, 12 and 16. At C = 8 that is 65026 values
//           and exhaustible by simulation; at C = 16 it is four billion, and
//           the functions built on top of div_max -- blend_ch, blend_rgb,
//           mul_max, effective_alpha -- have input spaces of 2^48 and larger
//           that were never exhaustively covered at any width. This module
//           replaces the claim with a proof, and proves the composition the
//           datapath instantiates rather than div_max alone.
//
//           FV_CH_W selects the width. One task per width per group, because
//           the four widths are four independent arithmetic claims -- nothing
//           about C = 8 being exact says anything about C = 16, where the
//           numerator needs all 32 bits and the rounding offset is 32768.
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
//           discharge in ten minutes even at C = 8; split up, the cheap groups
//           land in seconds.
//
//           The split is by solver cost, and the line it follows is whether a
//           property puts two multiplications with free operands into one
//           query. Those are what bit-vector solvers are worst at, and the
//           cost climbs steeply with C. The groups that do -- BOUND and NUM --
//           are kept apart from everything else, because putting them in the
//           same query made all of it slow.
//
//           They are also the only groups that do not run at every width.
//           BOUND and NUM run at 8 bits; at 12 and 16 they did not discharge
//           in ten minutes on boolector, bitwuzla, yices or z3, all four of
//           which were tried.
//
//           What that costs is less than it looks, and worth being precise
//           about. Once DIV has shown that div_max(C, v) is exactly
//           round(v / MAX) over the whole interval 0 .. MAX*MAX -- which it
//           does, at every width, in seconds -- everything in BOUND and NUM is
//           a corollary about round(v / MAX) and integer algebra rather than a
//           separate fact about the hardware:
//
//               no overshoot    N - lo*MAX = (top-lo)*a + (bot-lo)*(MAX-a),
//                               both terms non-negative, and round(.) is
//                               monotone -- so the result is at least lo. The
//                               upper bound is the mirror image.
//               flat            top*a + top*(MAX-a) = top*MAX exactly, and
//                               round(top*MAX / MAX) = top.
//               numerator range top*a + bot*(MAX-a) <= MAX*a + MAX*(MAX-a)
//                               = MAX*MAX.
//
//           So what the wider widths lose is a redundant machine check of that
//           algebra, not the arithmetic underneath it -- and the algebra is
//           also covered by exhaustive simulation of div_max at all four
//           widths. See doc/formal.md section 4.
//
//           WHY NO DIVISION APPEARS. The obvious statement of exactness is
//           `div_max(C, v) == (v + (MAX-1)/2) / MAX`. It is correct and it is
//           unusable: a bit-vector divide is the one operation these solvers
//           have no good decision procedure for, and it did not discharge in
//           ten minutes on its own. Stated as the pair of multiplicative
//           bounds that define integer division -- q*MAX <= v + (MAX-1)/2 <
//           (q+1)*MAX -- it discharges instantly.
///////////////////////////////////////////////////////////////////

module fv_blend
  import axis_video_mixer_pkg::*;
#(
    // 0 all, 1 DIV, 2 SCALE, 3 BLEND, 4 BOUND, 5 MONO, 6 UP, 7 NUM. See the
    // header.
    parameter int FV_GROUP = 0,
    // Component width under proof: 8, 10, 12 or 16.
    parameter int FV_CH_W = 8
) (
    input logic clk,

    // Free: the solver picks these, every cycle, over their full range. They
    // arrive in the package's container widths and are masked to FV_CH_W below,
    // because a container carrying bits above the component width is outside
    // the functions' contract and would make a counterexample meaningless.
    input logic [NUM_MAX_W-1:0] v_free,
    input logic [NUM_MAX_W-1:0] v2_free,
    input logic [ CH_MAX_W-1:0] top_free,
    input logic [ CH_MAX_W-1:0] top2_free,
    input logic [ CH_MAX_W-1:0] bot_free,
    input logic [ CH_MAX_W-1:0] a_free,
    input logic [ CH_MAX_W-1:0] b_free,
    input logic [RGB_MAX_W-1:0] trgb_free,
    input logic [RGB_MAX_W-1:0] brgb_free,
    input logic [ CH_MAX_W-1:0] px_alpha_free,
    input logic [ CH_MAX_W-1:0] glob_alpha_free,
    input logic [          7:0] u8,
    input logic [          7:0] u8b,
    input logic [         23:0] c24,
    input logic                 asrc
);
  localparam bit G_DIV = (FV_GROUP == 0) || (FV_GROUP == 1);
  localparam bit G_SCALE = (FV_GROUP == 0) || (FV_GROUP == 2);
  localparam bit G_BLEND = (FV_GROUP == 0) || (FV_GROUP == 3);
  localparam bit G_BOUND = (FV_GROUP == 0) || (FV_GROUP == 4);
  localparam bit G_MONO = (FV_GROUP == 0) || (FV_GROUP == 5);
  localparam bit G_UP = (FV_GROUP == 0) || (FV_GROUP == 6);
  localparam bit G_NUM = (FV_GROUP == 0) || (FV_GROUP == 7);

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // The width under proof
  //
  // FV_AW is where the multiplicative bounds are evaluated. Two bits above the
  // numerator, which is enough for (q+1)*MAX at q = MAX: that is
  // (MAX+1)*MAX, which at C = 16 is 4294901760 and overflows a 32-bit
  // evaluation by nothing at all. Proving an identity in arithmetic that
  // itself wraps would prove nothing, so the headroom is not optional.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  localparam int FV_AW = 2 * FV_CH_W + 2;

  localparam logic [FV_AW-1:0] FV_MAX = FV_AW'(ch_max(FV_CH_W));
  // MAX is odd at every legal width, so floor((v + (MAX-1)/2) / MAX) is exactly
  // round-half-up(v / MAX) and the halfway offset is an integer.
  localparam logic [FV_AW-1:0] FV_HALF = (FV_MAX - FV_AW'(1)) / FV_AW'(2);
  localparam logic [FV_AW-1:0] FV_MAX_NUM = FV_MAX * FV_MAX;

  logic [ CH_MAX_W-1:0] top, top2, bot, a, b, px_alpha, glob_alpha;
  logic [RGB_MAX_W-1:0] trgb, brgb;
  logic [NUM_MAX_W-1:0] v, v2;

  assign top        = top_free & CH_MAX_W'(ch_mask(FV_CH_W));
  assign top2       = top2_free & CH_MAX_W'(ch_mask(FV_CH_W));
  assign bot        = bot_free & CH_MAX_W'(ch_mask(FV_CH_W));
  assign a          = a_free & CH_MAX_W'(ch_mask(FV_CH_W));
  assign b          = b_free & CH_MAX_W'(ch_mask(FV_CH_W));
  assign px_alpha   = px_alpha_free & CH_MAX_W'(ch_mask(FV_CH_W));
  assign glob_alpha = glob_alpha_free & CH_MAX_W'(ch_mask(FV_CH_W));
  assign trgb       = trgb_free & RGB_MAX_W'(rgb_mask(FV_CH_W));
  assign brgb       = brgb_free & RGB_MAX_W'(rgb_mask(FV_CH_W));
  assign v          = v_free;
  assign v2         = v2_free;

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // div_max
  //
  // The range bound is load bearing, not cosmetic. div_max returns a
  // component, so above MAX*MAX the correct quotient does not fit and the
  // expression truncates: at C = 8, div_max(8, 65535) evaluates to 1, not 257.
  // MAX*MAX is exactly the largest numerator blend_ch can produce -- reached
  // when top, bot and a are all at maximum, because a and (MAX-a) sum to
  // exactly MAX -- so the function is only ever asked for values it can
  // represent. That is assumed here rather than quietly ignored.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Compared at the container width, not at FV_AW. v is a full NUM_MAX_W
  // numerator and FV_AW is only 18 bits at C = 8, so narrowing v for the
  // comparison would let a huge value pass the range test with its top bits
  // truncated away and then reach div_max in full -- which is exactly the
  // counterexample the first version of this file reported, and it was the
  // property that was wrong rather than the function.
  logic in_range, in_range2;
  assign in_range  = (v <= NUM_MAX_W'(FV_MAX_NUM));
  assign in_range2 = (v2 <= NUM_MAX_W'(FV_MAX_NUM));

  logic [FV_AW-1:0] q;
  assign q = FV_AW'(div_max(FV_CH_W, v));

  if (G_DIV) begin : g_div
    always_ff @(posedge clk) begin
      if (in_range) begin
        // Exactness, as the two bounds that define
        // floor((v + (MAX-1)/2) / MAX) -- which is round(v / MAX) with ties
        // resolved upwards. Multiplicative rather than a divide, for the
        // reason in the header.
        a_div_floor_lo : assert (q * FV_MAX <= FV_AW'(v) + FV_HALF);
        a_div_floor_hi : assert (FV_AW'(v) + FV_HALF < (q + FV_AW'(1)) * FV_MAX);

        // The same statement read the other way round: div_max lands on the
        // nearest multiple of MAX, so the residual cannot exceed half a
        // divisor. This is the form worth quoting -- an off-by-one in the
        // rounding shows up here as a residual of HALF+1 rather than HALF.
        a_div_rounded : assert ((FV_AW'(v) >= q * FV_MAX) ?
                                (FV_AW'(v) - q * FV_MAX <= FV_HALF) :
                                (q * FV_MAX - FV_AW'(v) <= FV_HALF + FV_AW'(1)));

        // The quotient is a component and must fit in one.
        a_div_in_range : assert (q <= FV_MAX);

        // The two endpoints the cascade depends on directly: exact 0 is what
        // makes a transparent layer free, exact full scale is what makes an
        // opaque layer lossless.
        a_div_zero : assert (div_max(FV_CH_W, '0) == '0);
        a_div_max : assert (div_max(FV_CH_W, NUM_MAX_W'(FV_MAX_NUM)) == ch_max(FV_CH_W));
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // mul_max and effective_alpha
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  if (G_SCALE) begin : g_scale
    always_ff @(posedge clk) begin
      a_mul_by_one : assert (mul_max(FV_CH_W, a, ch_max(FV_CH_W)) == a);
      a_mul_by_zero : assert (mul_max(FV_CH_W, a, '0) == '0);
      // Commutative, which is what lets effective_alpha combine pixel alpha
      // and global alpha in either order without changing the picture.
      a_mul_comm : assert (mul_max(FV_CH_W, a, b) == mul_max(FV_CH_W, b, a));
      // A fraction of a value never exceeds it.
      a_mul_bounded : assert (mul_max(FV_CH_W, a, b) <= a);

      // ALPHA_SRC decoding, against the encoding in the register map.
      a_ea_global : assert (effective_alpha(FV_CH_W, px_alpha, glob_alpha, ALPHA_GLOBAL_ONLY) ==
                            glob_alpha);
      a_ea_pixel : assert (effective_alpha(FV_CH_W, px_alpha, ch_max(FV_CH_W),
                                           ALPHA_PIXEL_X_GLOBAL) == px_alpha);

      // A global alpha of zero hides the layer whichever source is selected.
      // That is what software relies on to fade a layer out without waiting
      // for a frame boundary, since alpha is deliberately excluded from
      // geo_changed in the core.
      a_ea_zero_hides : assert (effective_alpha(FV_CH_W, px_alpha, '0, asrc) == '0);

      // Effective alpha is never more opaque than the pixel's own alpha when
      // the pixel alpha participates, so a transparent pixel cannot be made
      // opaque by the global setting.
      a_ea_no_opaquer : assert (effective_alpha(FV_CH_W, px_alpha, glob_alpha,
                                                ALPHA_PIXEL_X_GLOBAL) <= px_alpha);
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
      a_blend_alpha0 : assert (blend_ch(FV_CH_W, top, bot, '0) == bot);

      // Alpha at full scale returns the top pixel bit-exactly. This is the one
      // a >>C would get wrong, and the whole reason div_max exists: with a
      // shift the result would be (MAX-1)/MAX of top, and a stack of nominally
      // opaque layers would visibly darken.
      a_blend_alpha_max : assert (blend_ch(FV_CH_W, top, bot, ch_max(FV_CH_W)) == top);

      // The three channels are independent and none of them bleeds into
      // another. Channel crosstalk from a bad bit slice is invisible in a
      // greyscale test pattern and obvious in a coloured one -- and it is the
      // failure a parameterised component width makes newly possible, since
      // every channel boundary now moves with P_CH_W.
      a_rgb_alpha0 : assert (blend_rgb(FV_CH_W, trgb, brgb, '0) == brgb);
      a_rgb_alpha_max : assert (blend_rgb(FV_CH_W, trgb, brgb, ch_max(FV_CH_W)) == trgb);
      a_rgb_per_channel : assert (blend_rgb(FV_CH_W, trgb, brgb, a) ==
                                  ((RGB_MAX_W'(blend_ch(FV_CH_W, rgb_r(FV_CH_W, trgb),
                                                         rgb_r(FV_CH_W, brgb), a))
                                    << (2 * FV_CH_W)) |
                                   (RGB_MAX_W'(blend_ch(FV_CH_W, rgb_g(FV_CH_W, trgb),
                                                         rgb_g(FV_CH_W, brgb), a))
                                    << FV_CH_W) |
                                   RGB_MAX_W'(blend_ch(FV_CH_W, rgb_b(FV_CH_W, trgb),
                                                        rgb_b(FV_CH_W, brgb), a))));

      // A pixel unpacks to the colour and alpha it was packed from, at
      // whatever width. The accessors are shift-and-mask rather than part
      // selects precisely because the width is a variable, so this is the
      // property that they still name the right bits.
      a_px_round_trip : assert (px_rgb(FV_CH_W, (PX_MAX_W'(trgb) << FV_CH_W) |
                                                PX_MAX_W'(a)) == trgb);
      a_px_alpha : assert (px_a(FV_CH_W, (PX_MAX_W'(trgb) << FV_CH_W) | PX_MAX_W'(a)) == a);
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
  // This is the expensive group: it holds two instances of the C x C
  // multiplier and asks the solver to bound their sum, which is the shape of
  // query bit-vector solvers are worst at, and the cost climbs steeply with C.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [CH_MAX_W-1:0] lo, hi;
  assign lo = (top < bot) ? top : bot;
  assign hi = (top < bot) ? bot : top;

  if (G_BOUND) begin : g_bound
    always_ff @(posedge clk) begin
      a_blend_bounded_lo : assert (blend_ch(FV_CH_W, top, bot, a) >= lo);
      a_blend_bounded_hi : assert (blend_ch(FV_CH_W, top, bot, a) <= hi);

      // Blending a value with itself is the identity for every alpha, so a
      // flat region of colour stays flat whatever alpha is applied to it. This
      // is the case where rounding error would be most visible: a large
      // translucent overlay on a solid background. It sits here rather than
      // with the other blend_ch properties because it is the same shape of
      // query -- two free multiplies the solver has to reason about together
      // -- and it was what made the BLEND group expensive.
      a_blend_flat : assert (blend_ch(FV_CH_W, top, top, a) == top);
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Monotonicity, proved in two pieces
  //
  // The statement wanted is: raising the top pixel never lowers the blended
  // result. Asserted directly it needs two whole blend_ch instances in one
  // query and did not discharge in a minute even at C = 8.
  //
  // Split at div_max it does. blend_ch is div_max composed with a numerator,
  // so monotonicity of the composition follows from monotonicity of each
  // piece:
  //
  //     a_num_monotone   the numerator is monotone in top
  //     a_div_monotone   div_max is monotone over its declared range
  //
  // Both are cheap. The conclusion is the composition, and it is an ordinary
  // syllogism rather than anything the solver has to be trusted for. The
  // numerator's range bound is discharged by the BOUND group above, which
  // shows the sum never leaves 0 .. MAX*MAX.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [NUM_MAX_W-1:0] num_top, num_top2;
  assign num_top = NUM_MAX_W'(top) * NUM_MAX_W'(a) +
                   NUM_MAX_W'(bot) * NUM_MAX_W'(ch_max(FV_CH_W) - a);
  assign num_top2 = NUM_MAX_W'(top2) * NUM_MAX_W'(a) +
                    NUM_MAX_W'(bot) * NUM_MAX_W'(ch_max(FV_CH_W) - a);

  if (G_MONO) begin : g_mono
    always_ff @(posedge clk) begin
      if (in_range && in_range2 && (v <= v2)) begin
        a_div_monotone : assert (div_max(FV_CH_W, v) <= div_max(FV_CH_W, v2));
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // The numerator
  //
  // Two facts about top*a + bot*(MAX-a) on its own, with div_max out of the
  // query. The first completes the monotonicity argument above; the second is
  // the discharge for the range guard the DIV group assumes -- blend_ch is the
  // only caller of div_max with a non-constant numerator, and this is what
  // says that numerator never leaves the interval div_max was proved over.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  if (G_NUM) begin : g_num
    always_ff @(posedge clk) begin
      if (top <= top2) begin
        a_num_monotone : assert (num_top <= num_top2);
      end
      a_num_in_range : assert (FV_AW'(num_top) <= FV_MAX_NUM);
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Expanding the 8-bit register fields
  //
  // L<i>_CTRL.ALPHA and BACKGROUND.RGB stay 8 bits per component whatever
  // P_CH_W is, so everything the datapath does with them rests on ch_up. The
  // two endpoints are the ones that have to be exact -- an alpha of 0xFF that
  // did not expand to full scale would stop an "opaque" layer being opaque,
  // which is the whole reason div_max divides by MAX rather than by 2**C --
  // and in between, within one LSB is the most any bit replication can
  // promise, because a * MAX / 255 is not an integer at C = 10 or 12.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [FV_AW-1:0] up, upb;
  assign up  = FV_AW'(ch_up(FV_CH_W, u8));
  assign upb = FV_AW'(ch_up(FV_CH_W, u8b));

  if (G_UP) begin : g_up
    always_ff @(posedge clk) begin
      a_up_zero : assert (ch_up(FV_CH_W, 8'h00) == '0);
      a_up_full : assert (ch_up(FV_CH_W, 8'hFF) == ch_max(FV_CH_W));
      a_up_in_range : assert (up <= FV_MAX);

      // Within one LSB of the exact rational scaling, stated without a divide:
      // |up*255 - u8*MAX| < 255.
      a_up_near_lo : assert (up * FV_AW'(255) <= FV_AW'(u8) * FV_MAX + FV_AW'(254));
      a_up_near_hi : assert (FV_AW'(u8) * FV_MAX <= up * FV_AW'(255) + FV_AW'(254));

      if (u8 <= u8b) begin
        a_up_monotone : assert (up <= upb);
      end

      // rgb_up is ch_up on each component, in the packing the datapath reads
      // back. A transposed channel here would tint the background and nothing
      // else, which is easy to look at and not notice.
      a_rgb_up_r : assert (rgb_r(FV_CH_W, rgb_up(FV_CH_W, c24)) == ch_up(FV_CH_W, c24[23:16]));
      a_rgb_up_g : assert (rgb_g(FV_CH_W, rgb_up(FV_CH_W, c24)) == ch_up(FV_CH_W, c24[15:8]));
      a_rgb_up_b : assert (rgb_b(FV_CH_W, rgb_up(FV_CH_W, c24)) == ch_up(FV_CH_W, c24[7:0]));
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
    c_alpha_mid : cover (a == CH_MAX_W'(FV_MAX >> 1) && top == ch_max(FV_CH_W) && bot == '0);
    c_div_max : cover (in_range && FV_AW'(v) == FV_MAX_NUM);
    c_div_tie : cover (in_range && FV_AW'(v) == FV_HALF + FV_AW'(1));
  end

endmodule
