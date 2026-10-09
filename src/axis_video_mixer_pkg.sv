`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: axis_video_mixer_pkg.sv
// Author  : Benjamin Tamayo
// Date    : 09/06/2026
// Purpose : Shared constants and blend arithmetic for the AXI4-Stream video mixer.
//
//           Everything the RTL and the testbench golden model both need lives
//           here, so the reference implementation cannot drift from the design.
//
//           Pixel packing, RGBA with a C-bit component, 4*C bits per pixel:
//               TDATA[4C-1:3C] = R
//               TDATA[3C-1:2C] = G
//               TDATA[2C-1: C] = B
//               TDATA[  C-1:0] = A   full scale = opaque, 0 = fully transparent
//
//           R in the most significant component matches the {red, green, blue}
//           ordering already used by the 24-bit stream in this pipeline; alpha
//           is appended below it rather than displacing anything. At C = 8 that
//           is exactly the RGBA8 packing this block started with.
//
//           COMPONENT WIDTH. C is an RTL parameter -- 8, 10, 12 or 16 -- and a
//           SystemVerilog package cannot be parameterised, so every function
//           below takes the width as its first argument instead. Callers pass a
//           parameter, so the width folds to a constant at elaboration and
//           nothing variable survives into the netlist.
//
//           The convention for those arguments: a component arrives
//           right-aligned and zero-extended in a CH_MAX_W-wide container, a
//           colour in an RGB_MAX_W-wide one, a pixel in PX_MAX_W. The
//           accessors below mask on the way out, so a container carrying junk
//           above bit C cannot leak into the arithmetic -- but a caller
//           assembling a component by hand is responsible for zeroing it.
///////////////////////////////////////////////////////////////////

package axis_video_mixer_pkg;

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Widths
  //
  // These are containers, not the implemented widths. The implemented widths
  // come from P_CH_W in the RTL; these just have to be wide enough to carry the
  // largest supported component through a function argument.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  localparam int CH_MAX_W = 16;  // widest supported colour component
  localparam int PX_MAX_W = 4 * CH_MAX_W;  // 64, one RGBA pixel
  localparam int RGB_MAX_W = 3 * CH_MAX_W;  // 48, colour without alpha
  // A blend numerator is top*a + bot*(MAX-a), which peaks at MAX*MAX because a
  // and (MAX-a) sum to exactly MAX. At C = 16 that is 65535*65535, which needs
  // all 32 bits and not one more.
  localparam int NUM_MAX_W = 2 * CH_MAX_W;  // 32, a blend numerator
  // Two bits of headroom above the numerator for the div_max identity, which
  // forms t = v + 2**(C-1) and then t + (t >> C).
  localparam int ACC_MAX_W = NUM_MAX_W + 2;  // 34

  // The number of layer input streams the top level brings out as named ports.
  // A build may instantiate fewer -- P_NUM_LAYERS -- but never more.
  localparam int MAX_LAYERS = 8;

  // Identification, mirrored from regs/gen_regs.py.
  localparam logic [15:0] MIXER_MAGIC = 16'h4D58;  // ASCII 'MX'
  localparam logic [ 7:0] MIXER_VER_MAJOR = 8'd1;
  localparam logic [ 7:0] MIXER_VER_MINOR = 8'd1;  // 1: 8 streams, 10/12/16-bit components

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Legal parameter values
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Pixels per clock. A beat carries P_PPC pixels, lane 0 in the LEAST
  // significant bits, so lane j of a beat is canvas x = out_x + j. That order
  // matters and is worth stating once: it matches the byte order an
  // AXI4-Stream carries on the wire, so a width converter placed in front of a
  // layer produces lanes in the order this block expects with no reversal.
  //
  // Only powers of two are supported, because every conversion between pixels
  // and beats in the datapath is then a shift rather than a divide.
  function automatic bit ppc_legal(input int p);
    return (p == 1) || (p == 2) || (p == 4) || (p == 8);
  endfunction

  // Colour component width.
  //
  // 8 is RGBA8. 10 and 12 are the deep-colour depths HDMI and DisplayPort
  // carry, 16 is what a linear-light or HDR intermediate wants. Everything
  // between them is excluded deliberately rather than for want of effort: the
  // blend identity below is proved exact only at these four widths, and a
  // width that is not a whole number of nibbles makes every software-side
  // pixel unpack a shift-and-mask with no byte alignment to fall back on.
  function automatic bit ch_w_legal(input int w);
    return (w == 8) || (w == 10) || (w == 12) || (w == 16);
  endfunction

  // ALPHA_SRC encoding, mirrored from the register map.
  localparam logic ALPHA_PIXEL_X_GLOBAL = 1'b0;
  localparam logic ALPHA_GLOBAL_ONLY = 1'b1;

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Masks and full scale
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Full scale for a C-bit component: 2**C - 1. This is the value that means
  // "opaque" and the divisor the blend divides by -- the two have to be the
  // same number or an alpha of full scale would not return the top colour
  // exactly. See div_max.
  function automatic logic [CH_MAX_W-1:0] ch_max(input int ch_w);
    return CH_MAX_W'((1 << ch_w) - 1);
  endfunction

  function automatic logic [PX_MAX_W-1:0] ch_mask(input int ch_w);
    return (PX_MAX_W'(1) << ch_w) - PX_MAX_W'(1);
  endfunction

  function automatic logic [PX_MAX_W-1:0] rgb_mask(input int ch_w);
    return (PX_MAX_W'(1) << (3 * ch_w)) - PX_MAX_W'(1);
  endfunction

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Pixel field accessors
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Shift and mask rather than a part-select, because `p[4*ch_w-1 -: ch_w]`
  // needs a constant width and ch_w is a function argument. Constant-folded at
  // elaboration either way.
  function automatic logic [CH_MAX_W-1:0] px_r(input int ch_w, input logic [PX_MAX_W-1:0] p);
    return CH_MAX_W'((p >> (3 * ch_w)) & ch_mask(ch_w));
  endfunction

  function automatic logic [CH_MAX_W-1:0] px_g(input int ch_w, input logic [PX_MAX_W-1:0] p);
    return CH_MAX_W'((p >> (2 * ch_w)) & ch_mask(ch_w));
  endfunction

  function automatic logic [CH_MAX_W-1:0] px_b(input int ch_w, input logic [PX_MAX_W-1:0] p);
    return CH_MAX_W'((p >> ch_w) & ch_mask(ch_w));
  endfunction

  function automatic logic [CH_MAX_W-1:0] px_a(input int ch_w, input logic [PX_MAX_W-1:0] p);
    return CH_MAX_W'(p & ch_mask(ch_w));
  endfunction

  // The colour of a pixel, alpha dropped: the top three components, moved down
  // so the result is an RGB value in its own right.
  function automatic logic [RGB_MAX_W-1:0] px_rgb(input int ch_w, input logic [PX_MAX_W-1:0] p);
    return RGB_MAX_W'((p >> ch_w) & rgb_mask(ch_w));
  endfunction

  // Components of a colour that has already had its alpha dropped.
  function automatic logic [CH_MAX_W-1:0] rgb_r(input int ch_w, input logic [RGB_MAX_W-1:0] c);
    return CH_MAX_W'((PX_MAX_W'(c) >> (2 * ch_w)) & ch_mask(ch_w));
  endfunction

  function automatic logic [CH_MAX_W-1:0] rgb_g(input int ch_w, input logic [RGB_MAX_W-1:0] c);
    return CH_MAX_W'((PX_MAX_W'(c) >> ch_w) & ch_mask(ch_w));
  endfunction

  function automatic logic [CH_MAX_W-1:0] rgb_b(input int ch_w, input logic [RGB_MAX_W-1:0] c);
    return CH_MAX_W'(PX_MAX_W'(c) & ch_mask(ch_w));
  endfunction

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Blend arithmetic
  //
  // Alpha compositing needs a divide by full scale, not by the next power of
  // two: an alpha of 2**C - 1 must return the top colour exactly, and >>C would
  // return (2**C - 2)/(2**C - 1) of it. Over a cascade of layers that error
  // accumulates and a stack of nominally opaque layers visibly darkens.
  //
  // This identity gives the correctly rounded quotient with two adds and two
  // shifts, no divider and no lookup table:
  //
  //     div_max(C, v) = (t + (t >> C)) >> C    where t = v + 2**(C-1)
  //
  // It is the C = 8 identity -- (t + (t >> 8)) >> 8 with t = v + 128 -- read at
  // a general width, and it holds for the same reason: 1/(2**C - 1) is
  // 2**-C * (1 + 2**-C + 2**-2C + ...), and over the range a blend can produce
  // the first two terms plus the rounding offset are already exact.
  //
  // Checked exhaustively against round(v / (2**C - 1)) at C = 8, 10, 12 and 16
  // over the full 0 .. (2**C - 1)**2 that blend_ch can produce -- all four
  // billion values at C = 16 -- and proved in formal/tops/fv_blend.sv. Those
  // four widths are exactly the ones ch_w_legal admits.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  function automatic logic [CH_MAX_W-1:0] div_max(input int ch_w,
                                                  input logic [NUM_MAX_W-1:0] v);
    logic [ACC_MAX_W-1:0] t;
    begin
      t = ACC_MAX_W'(v) + (ACC_MAX_W'(1) << (ch_w - 1));
      div_max = CH_MAX_W'(((t + (t >> ch_w)) >> ch_w) & ACC_MAX_W'(ch_mask(ch_w)));
    end
  endfunction

  // Scale one component by another treated as a 0..1 fraction: (a * b) / MAX.
  function automatic logic [CH_MAX_W-1:0] mul_max(input int ch_w, input logic [CH_MAX_W-1:0] a,
                                                  input logic [CH_MAX_W-1:0] b);
    return div_max(ch_w, NUM_MAX_W'(a) * NUM_MAX_W'(b));
  endfunction

  // Porter-Duff "over" for a single component, straight (non-premultiplied)
  // alpha:
  //
  //     out = (top * a + bot * (MAX - a)) / MAX
  //
  // The numerator peaks at MAX * MAX, because a and (MAX - a) sum to exactly
  // MAX. That is why NUM_MAX_W bits are enough and why div_max only has to be
  // exact up to MAX*MAX.
  function automatic logic [CH_MAX_W-1:0] blend_ch(input int ch_w, input logic [CH_MAX_W-1:0] top,
                                                   input logic [CH_MAX_W-1:0] bot,
                                                   input logic [CH_MAX_W-1:0] a);
    return div_max(ch_w, NUM_MAX_W'(top) * NUM_MAX_W'(a) +
                         NUM_MAX_W'(bot) * NUM_MAX_W'(ch_max(ch_w) - a));
  endfunction

  // Full RGB "over". Alpha of 0 returns bot bit-exactly, so a disabled or
  // absent layer costs nothing in accuracy as it passes through the cascade.
  function automatic logic [RGB_MAX_W-1:0] blend_rgb(input int ch_w,
                                                     input logic [RGB_MAX_W-1:0] top,
                                                     input logic [RGB_MAX_W-1:0] bot,
                                                     input logic [CH_MAX_W-1:0] a);
    logic [CH_MAX_W-1:0] r, g, b;
    begin
      r = blend_ch(ch_w, rgb_r(ch_w, top), rgb_r(ch_w, bot), a);
      g = blend_ch(ch_w, rgb_g(ch_w, top), rgb_g(ch_w, bot), a);
      b = blend_ch(ch_w, rgb_b(ch_w, top), rgb_b(ch_w, bot), a);
      blend_rgb = (RGB_MAX_W'(r) << (2 * ch_w)) | (RGB_MAX_W'(g) << ch_w) | RGB_MAX_W'(b);
    end
  endfunction

  // The alpha a layer actually composites with, given its pixel and its
  // registers. Computed once per pixel ahead of the cascade so that each blend
  // stage is a single multiply deep rather than two.
  function automatic logic [CH_MAX_W-1:0] effective_alpha(input int ch_w,
                                                          input logic [CH_MAX_W-1:0] pixel_a,
                                                          input logic [CH_MAX_W-1:0] global_a,
                                                          input logic src_sel);
    return (src_sel == ALPHA_GLOBAL_ONLY) ? global_a : mul_max(ch_w, pixel_a, global_a);
  endfunction

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Expanding the 8-bit register fields to the component width
  //
  // L<i>_CTRL.ALPHA and BACKGROUND.RGB stay 8 bits per component in the
  // register map whatever P_CH_W is, and are expanded here. Two reasons, and
  // the first is the stronger: widening ALPHA would collide with ALPHA_SRC in
  // the same register and widening BACKGROUND would need a second one, so a
  // C-bit build and an 8-bit build would not share a register map -- and the
  // whole point of CAPS is that one map describes every build.
  //
  // The second is that neither field is a sample. Alpha is a fraction and a
  // background is a colour someone picked; 8 bits of each is not the thing
  // deep colour was wanted for. What deep colour is wanted for is the pixels,
  // and those arrive at full width.
  //
  // The expansion is bit replication -- the standard 8-to-C deep-colour
  // expansion -- which is to say 0x00 maps to 0 and 0xFF maps to full scale,
  // both exactly, so "transparent" and "opaque" survive it. In between it is
  // monotone and within one LSB of the exact rational scaling a * MAX / 255.
  // Checked exhaustively at all four widths and proved in fv_blend.sv.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  function automatic logic [CH_MAX_W-1:0] ch_up(input int ch_w, input logic [7:0] v);
    return CH_MAX_W'(((CH_MAX_W'(v) << (ch_w - 8)) | (CH_MAX_W'(v) >> (16 - ch_w))) &
                     CH_MAX_W'(ch_mask(ch_w)));
  endfunction

  function automatic logic [RGB_MAX_W-1:0] rgb_up(input int ch_w, input logic [23:0] c);
    return (RGB_MAX_W'(ch_up(ch_w, c[23:16])) << (2 * ch_w)) |
           (RGB_MAX_W'(ch_up(ch_w, c[15:8])) << ch_w) | RGB_MAX_W'(ch_up(ch_w, c[7:0]));
  endfunction

endpackage
