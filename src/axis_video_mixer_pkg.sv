`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: axis_video_mixer_pkg.sv
// Author  : Benjamin Tamayo
// Date    : 09/06/2026
// Purpose : Shared constants and blend arithmetic for the AXI4-Stream video mixer.
//
//           Everything the RTL and the testbench golden model both need lives
//           here, so the reference implementation cannot drift from the design.
//           The scoreboard calls exactly these functions.
//
//           Pixel packing, RGBA8, 32 bits:
//               TDATA[31:24] = R
//               TDATA[23:16] = G
//               TDATA[15: 8] = B
//               TDATA[ 7: 0] = A     255 = opaque, 0 = fully transparent
//
//           R in the most significant byte matches the {red, green, blue}
//           ordering already used by the 24-bit stream in this pipeline;
//           alpha is appended below it rather than displacing anything.
///////////////////////////////////////////////////////////////////

package axis_video_mixer_pkg;

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Pixel geometry
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  localparam int PX_W  = 32;  // RGBA8 stream width
  localparam int RGB_W = 24;  // colour without alpha
  localparam int CH_W  = 8;   // one colour channel

  localparam logic [7:0] OPAQUE = 8'hFF;

  // Identification, mirrored from regs/gen_regs.py. The RTL checks these against
  // the generated register block at elaboration so a stale regs.json cannot ship.
  localparam logic [15:0] MIXER_MAGIC = 16'h4D58;  // ASCII 'MX'
  localparam logic [ 7:0] MIXER_VER_MAJOR = 8'd1;
  localparam logic [ 7:0] MIXER_VER_MINOR = 8'd0;

  // ALPHA_SRC encoding, mirrored from the register map.
  localparam logic ALPHA_PIXEL_X_GLOBAL = 1'b0;
  localparam logic ALPHA_GLOBAL_ONLY = 1'b1;

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Pixel field accessors
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  function automatic logic [7:0] px_r(input logic [PX_W-1:0] p);
    return p[31:24];
  endfunction

  function automatic logic [7:0] px_g(input logic [PX_W-1:0] p);
    return p[23:16];
  endfunction

  function automatic logic [7:0] px_b(input logic [PX_W-1:0] p);
    return p[15:8];
  endfunction

  function automatic logic [7:0] px_a(input logic [PX_W-1:0] p);
    return p[7:0];
  endfunction

  function automatic logic [RGB_W-1:0] px_rgb(input logic [PX_W-1:0] p);
    return p[31:8];
  endfunction

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Blend arithmetic
  //
  // Alpha compositing needs a divide by 255, not by 256: an alpha of 255 must
  // return the top colour exactly, and >>8 would return 254/255 of it. Over a
  // cascade of layers that error accumulates and a stack of nominally opaque
  // layers visibly darkens.
  //
  // This identity gives the correctly rounded quotient with two adds and two
  // shifts, no divider and no lookup table:
  //
  //     div255(v) = (t + (t >> 8)) >> 8   where t = v + 128
  //
  // It is exact against round(v / 255) for every v in 0 .. 65025, which is the
  // full range the blend below can produce. Verified exhaustively.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  function automatic logic [7:0] div255(input logic [15:0] v);
    logic [16:0] t;
    begin
      t = 17'(v) + 17'd128;
      div255 = 8'((t + (t >> 8)) >> 8);
    end
  endfunction

  // Scale one 8-bit value by another treated as a 0..1 fraction: (a * b) / 255.
  function automatic logic [7:0] mul255(input logic [7:0] a, input logic [7:0] b);
    return div255(16'(a) * 16'(b));
  endfunction

  // Porter-Duff "over" for a single channel, straight (non-premultiplied) alpha:
  //
  //     out = (top * a + bot * (255 - a)) / 255
  //
  // The numerator peaks at 255 * 255 = 65025 when top, bot and a are all at
  // maximum, because a and (255 - a) sum to exactly 255. That is why 16 bits is
  // enough and why div255 only has to be exact up to 65025.
  function automatic logic [7:0] blend_ch(input logic [7:0] top, input logic [7:0] bot,
                                          input logic [7:0] a);
    return div255(16'(top) * 16'(a) + 16'(bot) * 16'(8'd255 - a));
  endfunction

  // Full RGB "over". Alpha of 0 returns bot bit-exactly, so a disabled or
  // absent layer costs nothing in accuracy as it passes through the cascade.
  function automatic logic [RGB_W-1:0] blend_rgb(input logic [RGB_W-1:0] top,
                                                 input logic [RGB_W-1:0] bot,
                                                 input logic [    7:0] a);
    return {
      blend_ch(top[23:16], bot[23:16], a),
      blend_ch(top[15:8], bot[15:8], a),
      blend_ch(top[7:0], bot[7:0], a)
    };
  endfunction

  // The alpha a layer actually composites with, given its pixel and its
  // registers. Computed once per pixel ahead of the cascade so that each blend
  // stage is a single multiply deep rather than two.
  function automatic logic [7:0] effective_alpha(input logic [7:0] pixel_a,
                                                 input logic [7:0] global_a, input logic src_sel);
    return (src_sel == ALPHA_GLOBAL_ONLY) ? global_a : mul255(pixel_a, global_a);
  endfunction

endpackage
