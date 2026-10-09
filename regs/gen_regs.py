#!/usr/bin/env python3
"""
Filename: gen_regs.py
Author  : Benjamin Tamayo
Date    : 09/06/2026
Purpose : Emit regs.json for the AXI4-Stream video mixer, plus the adapter that
          turns corsair's flat port list into the arrays the datapath wants.

          The map is generated for the MAXIMUM layer count the RTL brings out
          as ports -- eight -- not for the layer count a particular build
          instantiates. One map therefore describes every build, and a build
          with fewer layers simply leaves the upper blocks unwired: their
          configuration outputs go nowhere and their status inputs read zero.
          Software is told the real count by CAPS.NUM_LAYERS.

          That is why nothing else here is a generator option any more. Layer
          count, pixels per clock, component width, FIFO depth and whether the
          output carries alpha are all RTL parameters, and all five are
          reported through CAPS as hardware inputs rather than baked in as
          reset values. A map and a build cannot disagree about them because
          the map no longer holds an opinion.

          Usage:
              ./gen_regs.py                 # 8 layer blocks, writes regs.json
              ./gen_regs.py -n 4            # a smaller map, for a build that
                                            # will never want more than 4

          Then run corsair as usual:
              corsair -r regs.json -c csrconfig

          Building with a P_NUM_LAYERS larger than the map is caught at
          elaboration by an assertion in the generated adapter.
"""

import argparse
import json
import sys

# Layout constants. LAYER_BASE is deliberately well clear of the global block so
# that adding a global register never renumbers a layer register -- software
# that hardcodes a layer offset stays correct across map revisions.
GLOBAL_BASE = 0x00
LAYER_BASE = 0x40
LAYER_STRIDE = 0x10

# The number of layer stream port sets axis_video_mixer.sv brings out, and so
# the largest map worth generating. Mirrored by MAX_LAYERS in the RTL package.
MAX_LAYERS = 8

VER_MAJOR = 1
# 1.1 adds four more layer blocks, CAPS.CH_W, and turns the rest of CAPS from
# baked constants into hardware inputs. Every existing field keeps its address,
# position and meaning, so it is a minor revision: software written against 1.0
# still works, it just cannot see the new layers.
VER_MINOR = 1
MAGIC = 0x4D58  # ASCII 'MX'


def bf(name, description, lsb, width, access="rw", hardware="o", reset=0, enums=None):
    return {
        "name": name,
        "description": description,
        "reset": reset,
        "width": width,
        "lsb": lsb,
        "access": access,
        "hardware": hardware,
        "enums": enums or [],
    }


def enum(name, description, value):
    return {"name": name, "description": description, "value": value}


def reg(name, description, address, bitfields):
    return {
        "name": name,
        "description": description,
        "address": address,
        "bitfields": bitfields,
    }


def global_regs(num_layers):
    """The registers that exist once, regardless of layer count."""
    return [
        reg(
            "ID",
            "Identification and version. Read-only constants, so a correct read here proves "
            "the AXI4-Lite path reaches this block before any other register is trusted.",
            GLOBAL_BASE + 0x00,
            [
                bf("MAGIC", "Always 0x4D58 (ASCII 'MX'). A read of 0x0000 or 0xFFFF means the "
                   "bus is not reaching the mixer.", 16, 16, "ro", "f", MAGIC),
                bf("VER_MAJOR", "Major version. Increment on any incompatible map change.",
                   8, 8, "ro", "f", VER_MAJOR),
                bf("VER_MINOR", "Minor version. Increment on backwards-compatible additions.",
                   0, 8, "ro", "f", VER_MINOR),
            ],
        ),
        reg(
            "CAPS",
            "Build-time capabilities, so software can size its own layer loops and unpack "
            "pixels from the hardware it is actually talking to instead of from a compile-time "
            "assumption. Every field is driven from the corresponding RTL parameter rather "
            "than baked into the map, so one map describes every build and none of these can "
            "be stale.",
            GLOBAL_BASE + 0x04,
            [
                bf("NUM_LAYERS", "Number of layer input streams this build instantiates, 1 to "
                   "%d. The top level brings out %d sets of stream ports regardless; the ones "
                   "at or above this index are not implemented and hold their TREADY low, and "
                   "their L<i>_* registers read as zero." % (MAX_LAYERS, MAX_LAYERS),
                   0, 8, "ro", "i"),
                bf("FIFO_DEPTH_LOG2", "Per-layer input FIFO depth in BEATS, as a power of two. "
                   "A layer wider than PPC * 2**this cannot be guaranteed free of underflow, "
                   "because a window at x = 0 gets no head start within the output line.",
                   8, 8, "ro", "i"),
                bf("OUT_HAS_ALPHA", "1 if the output stream carries RGBA per pixel, "
                   "0 if it carries RGB with alpha discarded after blending.",
                   16, 1, "ro", "i"),
                bf("CH_W", "Colour component width in bits: 8, 10, 12 or 16. A pixel is four "
                   "components, 4*CH_W bits, packed {R, G, B, A} with R in the most "
                   "significant and alpha in the least. Read this before unpacking TDATA -- it "
                   "is the only thing that says where the component boundaries are.",
                   17, 7, "ro", "i"),
                bf("PPC", "Pixels per beat on every stream, 1, 2, 4 or 8. Also the horizontal "
                   "alignment granularity: CANVAS.WIDTH, Ln_POS.X and Ln_SIZE.WIDTH must all be "
                   "multiples of this, and a write that is not is rejected with ERR.CFG rather "
                   "than rounded. Read it before computing a layout.",
                   24, 8, "ro", "i"),
            ],
        ),
        reg(
            "SCRATCH",
            "Read/write scratchpad with no hardware effect. Exists so a write-then-read test "
            "can prove the bus end to end without disturbing the picture.",
            GLOBAL_BASE + 0x08,
            [bf("VALUE", "Any value. Reads back exactly what was written.", 0, 32, "rw", "n")],
        ),
        reg(
            "CTRL",
            "Global mixer control.",
            GLOBAL_BASE + 0x0C,
            [
                bf("EN", "Enable the output stream. While 0 the mixer holds TVALID low and "
                   "accepts and discards nothing -- layer inputs are backpressured. Set the "
                   "canvas and layer geometry first, then set this.", 0, 1, "rw", "o", 0),
                bf("SOFT_RST", "Write 1 to resynchronise the whole datapath: flush every layer "
                   "FIFO, drop to the top of a new output frame, and re-arm each layer at its "
                   "next input SOF. Self-clearing; does not touch configuration registers.",
                   8, 1, "wosc", "o", 0),
            ],
        ),
        reg(
            "CANVAS",
            "Output raster size in pixels. The mixer emits HEIGHT lines of WIDTH pixels per "
            "frame. Changing either takes effect at the next output frame boundary.",
            GLOBAL_BASE + 0x10,
            [
                bf("WIDTH", "Output active width in pixels. Must be non-zero.",
                   0, 16, "rw", "o", 1280),
                bf("HEIGHT", "Output active height in lines. Must be non-zero.",
                   16, 16, "rw", "o", 720),
            ],
        ),
        reg(
            "BACKGROUND",
            "Colour of the canvas underneath every layer. This is what shows through wherever "
            "no enabled layer covers a pixel, which is why no layer is obliged to span the "
            "whole canvas -- every input can be an arbitrary rectangle.",
            GLOBAL_BASE + 0x14,
            [bf("RGB", "Background colour, {R[23:16], G[15:8], B[7:0]}.", 0, 24, "rw", "o", 0)],
        ),
        reg(
            "STATUS",
            "Live state. Read-only and never latched -- these reflect the current cycle, unlike "
            "the ERR register which latches.",
            GLOBAL_BASE + 0x18,
            [
                bf("ERR_ANY", "1 while any bit in ERR is set. Lets a polling loop check one "
                   "register instead of two.", 0, 1, "ro", "i"),
                bf("FRAME_ACTIVE", "1 while the output is mid-frame (between SOF and the last "
                   "pixel of the last line).", 1, 1, "ro", "i"),
                bf("LAYER_ARMED", "One bit per layer: 1 once that layer has seen its input SOF "
                   "and is delivering pixels. A layer that stays 0 is not receiving a stream.",
                   16, max(num_layers, 1), "ro", "i"),
            ],
        ),
        reg(
            "FRAME_COUNT",
            "Output frames completed since reset. Incrementing proves the pipeline is running; "
            "a stuck value with EN set means the output is stalled or a layer is starving.",
            GLOBAL_BASE + 0x1C,
            [bf("COUNT", "Free-running, wraps at 2**32.", 0, 32, "ro", "i")],
        ),
        reg(
            "ERR",
            "Latched error flags. Hardware sets, software clears by writing 1 to the bit. "
            "Latched rather than live because every one of these is a transient that would "
            "otherwise be missed between two polls.",
            GLOBAL_BASE + 0x20,
            [
                bf("CFG", "Configuration rejected: canvas width or height is zero, or an enabled "
                   "layer's window is zero-sized or extends past the canvas edge. The offending "
                   "layer is flagged in ERR_LAYER; a canvas fault sets this bit alone. The "
                   "mixer keeps running on the last valid configuration.",
                   0, 1, "rw1c", "s"),
                bf("STARVE", "A layer's input FIFO ran empty at a pixel where that layer was "
                   "due to contribute. The layer is dropped for the remainder of the frame and "
                   "re-arms at its next input SOF; the output never stalls.",
                   1, 1, "rw1c", "s"),
                bf("GEOM", "A layer's stream geometry disagreed with its SIZE register -- TLAST "
                   "arrived somewhere other than the configured last pixel of a line, or TUSER "
                   "somewhere other than the first pixel of a frame. That layer resynchronises "
                   "at its next input SOF.", 2, 1, "rw1c", "s"),
                bf("SRC_STALL", "A layer input was held backpressured -- TVALID high, TREADY "
                   "low because its FIFO was full -- for longer than STALL_LIMIT cycles. The "
                   "mirror image of OUT_STALL: that source is producing faster than the mixer "
                   "consumes, which in practice means a frame rate mismatch. Harmless in "
                   "short bursts, which is why it is measured against a threshold rather than "
                   "flagged on the first stalled cycle.", 3, 1, "rw1c", "s"),
                bf("OUT_STALL", "The downstream sink held TREADY low for longer than the stall "
                   "threshold while the mixer had a beat to give. Distinguishes 'the display "
                   "pipeline is blocked' from 'a source is starving', which look identical from "
                   "a stuck FRAME_COUNT alone.", 4, 1, "rw1c", "s"),
            ],
        ),
        reg(
            "ERR_LAYER",
            "One latched bit per layer, set alongside the per-layer causes in ERR. Names which "
            "input is at fault without having to read every layer's status register. Write 1 "
            "to a bit to clear that layer alone.",
            GLOBAL_BASE + 0x24,
            # Deliberately one bitfield per layer rather than a single N-bit MASK. corsair
            # gives a multi-bit rw1c field one shared set strobe that sets every bit at once,
            # and clears the whole field on a write of any non-zero value -- so an N-bit mask
            # would report every layer faulted whenever one was, and clearing one would clear
            # all. Per-bit fields get a set port each and a clear keyed on that bit of wdata.
            [bf("L%d" % i, "Layer %d has latched a starve, geometry or overflow fault." % i,
                i, 1, "rw1c", "s") for i in range(num_layers)],
        ),
        reg(
            "IRQ_EN",
            "Interrupt enable, one bit per ERR bit and in the same order. The irq output is the "
            "OR of (ERR & IRQ_EN), so it stays asserted until software clears the ERR bit.",
            GLOBAL_BASE + 0x28,
            [
                bf("CFG", "Enable interrupt on ERR.CFG.", 0, 1, "rw", "o", 0),
                bf("STARVE", "Enable interrupt on ERR.STARVE.", 1, 1, "rw", "o", 0),
                bf("GEOM", "Enable interrupt on ERR.GEOM.", 2, 1, "rw", "o", 0),
                bf("SRC_STALL", "Enable interrupt on ERR.SRC_STALL.", 3, 1, "rw", "o", 0),
                bf("OUT_STALL", "Enable interrupt on ERR.OUT_STALL.", 4, 1, "rw", "o", 0),
            ],
        ),
        reg(
            "STALL_LIMIT",
            "How long a stream may stay stalled before ERR.OUT_STALL or ERR.SRC_STALL latches, "
            "in clock cycles. Applies to both directions: the downstream sink holding TREADY "
            "low, and a layer source held backpressured on a full FIFO. Reset is 0x10000 -- "
            "comfortably longer than any legitimate gap, comfortably shorter than a frame.",
            GLOBAL_BASE + 0x2C,
            [bf("CYCLES", "0 disables the check.", 0, 32, "rw", "o", 0x10000)],
        ),
    ]


def layer_regs(index):
    """The four registers belonging to one layer."""
    base = LAYER_BASE + index * LAYER_STRIDE
    p = "L%d" % index
    zbase = "Layer %d" % index
    z = ("%s. Layers composite bottom-up in port order, so layer 0 is nearest the background "
         "and the highest-numbered enabled layer is on top." % zbase)
    return [
        reg(
            "%s_CTRL" % p,
            "%s enable and alpha. Takes effect at the next output frame boundary." % zbase,
            base + 0x00,
            [
                bf("EN", "Enable this layer. %s" % z, 0, 1, "rw", "o", 0),
                bf("ALPHA", "Global alpha, 0 transparent to 255 opaque. Multiplied into each "
                   "pixel's own alpha unless ALPHA_SRC selects otherwise.",
                   8, 8, "rw", "o", 255),
                bf("ALPHA_SRC", "Where this layer's alpha comes from.", 16, 1, "rw", "o", 0,
                   [
                       enum("PIXEL_X_GLOBAL", "Per-pixel alpha from TDATA multiplied by ALPHA. "
                            "The usual choice.", 0),
                       enum("GLOBAL_ONLY", "Ignore the pixel's alpha channel and use ALPHA "
                            "alone. Use for a source that leaves its alpha byte undefined.", 1),
                   ]),
            ],
        ),
        reg(
            "%s_POS" % p,
            "%s top-left corner, in canvas pixels. Takes effect at the next output frame "
            "boundary, so a moving window never tears." % zbase,
            base + 0x04,
            [
                bf("X", "Left edge, 0 is the leftmost canvas pixel.", 0, 16, "rw", "o", 0),
                bf("Y", "Top edge, 0 is the topmost canvas line.", 16, 16, "rw", "o", 0),
            ],
        ),
        reg(
            "%s_SIZE" % p,
            "%s size, in pixels. The mixer does not scale: this must match the geometry the "
            "input stream actually delivers, or ERR.GEOM latches and the layer is dropped."
            % zbase,
            base + 0x08,
            [
                bf("WIDTH", "Width in pixels. Must be non-zero and X+WIDTH must not exceed the "
                   "canvas width.", 0, 16, "rw", "o", 0),
                bf("HEIGHT", "Height in lines. Must be non-zero and Y+HEIGHT must not exceed "
                   "the canvas height.", 16, 16, "rw", "o", 0),
            ],
        ),
        reg(
            "%s_STATUS" % p,
            "%s live state. Read-only, not latched -- for the latched history see ERR and "
            "ERR_LAYER." % zbase,
            base + 0x0C,
            [
                bf("ARMED", "1 once the layer has seen its input SOF and is streaming.",
                   0, 1, "ro", "i"),
                bf("DROPPED", "1 while the layer is being skipped for the rest of the current "
                   "frame, after a starve or geometry fault.", 1, 1, "ro", "i"),
                bf("CFG_BAD", "1 while this layer's window is rejected as out of bounds or "
                   "zero-sized. The layer contributes nothing while this is set.",
                   2, 1, "ro", "i"),
                bf("FIFO_LEVEL", "Current occupancy of this layer's input FIFO, in pixels. A "
                   "level pinned at 0 means the source is too slow; pinned at full means the "
                   "source is ahead and being backpressured, which is healthy.",
                   16, 16, "ro", "i"),
            ],
        ),
    ]


def build(num_layers):
    regmap = global_regs(num_layers)
    for i in range(num_layers):
        regmap.extend(layer_regs(i))
    return {"regmap": regmap}


CSR_WRAPPER_HEADER = """`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: axis_video_mixer_csr.sv
// GENERATED by regs/gen_regs.py -- do not edit, your changes will be overwritten.
//
// Purpose : Adapt the flat, per-field port list that corsair generates into the
//           per-layer arrays the mixer datapath actually wants.
//
//           corsair cannot emit an array of register blocks, so a map with
//           @@MAP_LAYERS@@ layer blocks produces @@MAP_LAYERS@@ individually
//           named sets of ports. Hand-wiring those would make the layer count a
//           hand-edit in two places, which is exactly the drift this generator
//           exists to prevent.
//
//           The map is generated for the MAXIMUM layer count, not for the one a
//           build instantiates. P_NUM_LAYERS may be anything from 1 to
//           @@MAP_LAYERS@@: the blocks below that index are wired to the
//           datapath, and the ones at or above it have their configuration
//           outputs left dangling and their status inputs tied to zero, so they
//           read as a disabled, unarmed, empty layer. Software is told the real
//           count by CAPS.NUM_LAYERS, which is an input here rather than a
//           constant in the map.
//
//           Regenerate with:
//               cd regs && ./gen_regs.py && corsair -r regs.json -c csrconfig
///////////////////////////////////////////////////////////////////

module axis_video_mixer_csr #(
    // Layers this build instantiates, 1 .. @@MAP_LAYERS@@.
    parameter int P_NUM_LAYERS = @@DEFAULT_LAYERS@@,
    // Reported through CAPS so software never has to assume them.
    parameter int P_PPC = 1,
    parameter int P_CH_W = 8,
    parameter int P_FIFO_DEPTH = 2048,
    parameter bit P_OUT_HAS_ALPHA = 1'b1,
    parameter int P_ADDR_W = 12
) (
    input logic clk,
    input logic rst_n,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // AXI4-Lite slave
    ////////////////////////////////////////////////////////////////////////////////////////////////
    input  logic [P_ADDR_W-1:0] axil_awaddr,
    input  logic [         2:0] axil_awprot,
    input  logic                axil_awvalid,
    output logic                axil_awready,
    input  logic [        31:0] axil_wdata,
    input  logic [         3:0] axil_wstrb,
    input  logic                axil_wvalid,
    output logic                axil_wready,
    output logic [         1:0] axil_bresp,
    output logic                axil_bvalid,
    input  logic                axil_bready,
    input  logic [P_ADDR_W-1:0] axil_araddr,
    input  logic [         2:0] axil_arprot,
    input  logic                axil_arvalid,
    output logic                axil_arready,
    output logic [        31:0] axil_rdata,
    output logic [         1:0] axil_rresp,
    output logic                axil_rvalid,
    input  logic                axil_rready,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Global configuration out to the datapath
    ////////////////////////////////////////////////////////////////////////////////////////////////
    output logic        ctrl_en,
    output logic        ctrl_soft_rst,
    output logic [15:0] canvas_width,
    output logic [15:0] canvas_height,
    output logic [23:0] background_rgb,
    output logic [31:0] stall_limit,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Global status back from the datapath
    ////////////////////////////////////////////////////////////////////////////////////////////////
    input logic        status_frame_active,
    input logic [31:0] frame_count,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Error set strobes. One cycle high latches the corresponding ERR bit.
    ////////////////////////////////////////////////////////////////////////////////////////////////
    input  logic                    err_cfg_set,
    input  logic                    err_starve_set,
    input  logic                    err_geom_set,
    input  logic                    err_src_stall_set,
    input  logic                    err_out_stall_set,
    input  logic [P_NUM_LAYERS-1:0] err_layer_set,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Per-layer configuration out, status in
    ////////////////////////////////////////////////////////////////////////////////////////////////
    output logic [P_NUM_LAYERS-1:0]       lay_en,
    output logic [               7:0]     lay_alpha    [P_NUM_LAYERS],
    output logic [P_NUM_LAYERS-1:0]       lay_alpha_src,
    output logic [              15:0]     lay_x        [P_NUM_LAYERS],
    output logic [              15:0]     lay_y        [P_NUM_LAYERS],
    output logic [              15:0]     lay_w        [P_NUM_LAYERS],
    output logic [              15:0]     lay_h        [P_NUM_LAYERS],

    input  logic [P_NUM_LAYERS-1:0]       lay_armed,
    input  logic [P_NUM_LAYERS-1:0]       lay_dropped,
    input  logic [P_NUM_LAYERS-1:0]       lay_cfg_bad,
    input  logic [              15:0]     lay_level    [P_NUM_LAYERS],

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Level-sensitive interrupt, the OR of (ERR & IRQ_EN)
    ////////////////////////////////////////////////////////////////////////////////////////////////
    output logic irq
);
  // Layer blocks in the generated map. A build may use fewer, never more.
  localparam int LP_MAP_LAYERS = @@MAP_LAYERS@@;

  initial begin
    if (P_NUM_LAYERS < 1 || P_NUM_LAYERS > LP_MAP_LAYERS) begin
      $fatal(1, "axis_video_mixer_csr: P_NUM_LAYERS=%0d but the register map has %0d layer blocks",
             P_NUM_LAYERS, LP_MAP_LAYERS);
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Map-width layer signals
  //
  // corsair's ports are per layer block and there are LP_MAP_LAYERS of them,
  // so the connection list below is fixed. These arrays carry the full map
  // width; the bridge further down connects the first P_NUM_LAYERS of each to
  // the datapath and ties off the rest.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [LP_MAP_LAYERS-1:0] map_en;
  logic [              7:0] map_alpha    [LP_MAP_LAYERS];
  logic [LP_MAP_LAYERS-1:0] map_alpha_src;
  logic [             15:0] map_x        [LP_MAP_LAYERS];
  logic [             15:0] map_y        [LP_MAP_LAYERS];
  logic [             15:0] map_w        [LP_MAP_LAYERS];
  logic [             15:0] map_h        [LP_MAP_LAYERS];

  logic [LP_MAP_LAYERS-1:0] map_armed;
  logic [LP_MAP_LAYERS-1:0] map_dropped;
  logic [LP_MAP_LAYERS-1:0] map_cfg_bad;
  logic [             15:0] map_level    [LP_MAP_LAYERS];
  logic [LP_MAP_LAYERS-1:0] map_err_layer_set;

  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_layer_used
    assign lay_en[gi]             = map_en[gi];
    assign lay_alpha[gi]          = map_alpha[gi];
    assign lay_alpha_src[gi]      = map_alpha_src[gi];
    assign lay_x[gi]              = map_x[gi];
    assign lay_y[gi]              = map_y[gi];
    assign lay_w[gi]              = map_w[gi];
    assign lay_h[gi]              = map_h[gi];
    assign map_armed[gi]          = lay_armed[gi];
    assign map_dropped[gi]        = lay_dropped[gi];
    assign map_cfg_bad[gi]        = lay_cfg_bad[gi];
    assign map_level[gi]          = lay_level[gi];
    assign map_err_layer_set[gi]  = err_layer_set[gi];
  end

  // A layer block the build does not implement reads back as a layer that is
  // switched off and has never seen a stream, which is exactly what it is.
  // Its configuration outputs are still writable and still read back -- that
  // is corsair's storage, and leaving it connected to nothing is what makes
  // the block harmless rather than absent.
  for (genvar gi = P_NUM_LAYERS; gi < LP_MAP_LAYERS; gi++) begin : g_layer_unused
    assign map_armed[gi]         = 1'b0;
    assign map_dropped[gi]       = 1'b0;
    assign map_cfg_bad[gi]       = 1'b0;
    assign map_level[gi]         = 16'd0;
    assign map_err_layer_set[gi] = 1'b0;
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Capabilities
  //
  // Driven from the parameters rather than baked into the map, so a build and
  // its register map cannot disagree about what was built. $clog2 of the depth
  // rather than the depth itself because the field is 8 bits and the depth is
  // a power of two by construction -- axis_video_mixer.sv fails the build if
  // it is not.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [7:0] caps_num_layers;
  logic [7:0] caps_fifo_depth_log2;
  logic [6:0] caps_ch_w;
  logic [7:0] caps_ppc;

  assign caps_num_layers      = 8'(P_NUM_LAYERS);
  assign caps_fifo_depth_log2 = 8'($clog2(P_FIFO_DEPTH));
  assign caps_ch_w            = 7'(P_CH_W);
  assign caps_ppc             = 8'(P_PPC);

  // ERR readback, needed to build irq and STATUS.ERR_ANY.
  //
  // The register block keeps its latched bits private -- they leave only down
  // the AXI read path -- so this mirrors them. corsair's copy stays the
  // authoritative one that software reads and clears; this exists purely to
  // drive the two derived signals.
  logic [4:0] err_ff;
  logic [4:0] irq_en;
  logic [4:0] err_set;
  logic       err_wr_clear;

  assign err_set = {
    err_out_stall_set, err_src_stall_set, err_geom_set, err_starve_set, err_cfg_set
  };

  // The write address has to be captured on the AW handshake rather than read
  // live when the data beat lands. AXI4-Lite's address and data channels are
  // independent, and the register block holds WREADY high permanently, so a
  // master that sends the address first and the data some cycles later would
  // otherwise be decoded against whatever AWADDR had drifted to by then --
  // clearing the wrong register's mirror, or missing the clear entirely.
  logic [P_ADDR_W-1:0] wr_addr_q;
  logic                wr_addr_held;
  logic [P_ADDR_W-1:0] wr_addr;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_addr_q    <= '0;
      wr_addr_held <= 1'b0;
    end else begin
      if (axil_awvalid && axil_awready) begin
        wr_addr_q    <= axil_awaddr;
        wr_addr_held <= 1'b1;
      end
      if (axil_bvalid && axil_bready) begin
        wr_addr_held <= 1'b0;
      end
    end
  end

  // Address and data in the same cycle is the common case and arrives before
  // anything is captured, so fall back to the live address then.
  assign wr_addr      = wr_addr_held ? wr_addr_q : axil_awaddr;
  assign err_wr_clear = axil_wvalid && axil_wready && (wr_addr == 'h20);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      err_ff <= 5'b0;
    end else begin
      for (int b = 0; b < 5; b++) begin
        // Set beats clear, matching the register block's own priority: an error
        // that arrives in the same cycle as its acknowledgement is not lost.
        if (err_set[b]) err_ff[b] <= 1'b1;
        else if (err_wr_clear && axil_wstrb[0] && axil_wdata[b]) err_ff[b] <= 1'b0;
      end
    end
  end

  assign irq = |(err_ff & irq_en);

"""


def emit_csr_wrapper(num_layers, path):
    """Emit the array adapter around corsair's flat register block."""
    o = []
    o.append(CSR_WRAPPER_HEADER
             .replace("@@MAP_LAYERS@@", str(num_layers))
             .replace("@@DEFAULT_LAYERS@@", str(num_layers)))

    o.append("  ////////////////////////////////////////////////////////////////////"
             "////////////////////////////////\n")
    o.append("  // Generated register block\n")
    o.append("  ////////////////////////////////////////////////////////////////////"
             "////////////////////////////////\n")
    o.append("  axis_video_mixer_regs #(\n")
    o.append("      .ADDR_W(P_ADDR_W),\n")
    o.append("      .DATA_W(32)\n")
    o.append("  ) u_regs (\n")
    o.append("      .clk(clk),\n")
    o.append("      .rst(rst_n),\n\n")

    conns = [
        ("csr_caps_num_layers_in", "caps_num_layers"),
        ("csr_caps_fifo_depth_log2_in", "caps_fifo_depth_log2"),
        ("csr_caps_out_has_alpha_in", "P_OUT_HAS_ALPHA"),
        ("csr_caps_ch_w_in", "caps_ch_w"),
        ("csr_caps_ppc_in", "caps_ppc"),
        ("csr_ctrl_en_out", "ctrl_en"),
        ("csr_ctrl_soft_rst_out", "ctrl_soft_rst"),
        ("csr_canvas_width_out", "canvas_width"),
        ("csr_canvas_height_out", "canvas_height"),
        ("csr_background_rgb_out", "background_rgb"),
        ("csr_stall_limit_cycles_out", "stall_limit"),
        ("csr_status_err_any_in", "(|err_ff)"),
        ("csr_status_frame_active_in", "status_frame_active"),
        ("csr_status_layer_armed_in", "map_armed"),
        ("csr_frame_count_count_in", "frame_count"),
        ("csr_err_cfg_set", "err_cfg_set"),
        ("csr_err_starve_set", "err_starve_set"),
        ("csr_err_geom_set", "err_geom_set"),
        ("csr_err_src_stall_set", "err_src_stall_set"),
        ("csr_err_out_stall_set", "err_out_stall_set"),
        ("csr_irq_en_cfg_out", "irq_en[0]"),
        ("csr_irq_en_starve_out", "irq_en[1]"),
        ("csr_irq_en_geom_out", "irq_en[2]"),
        ("csr_irq_en_src_stall_out", "irq_en[3]"),
        ("csr_irq_en_out_stall_out", "irq_en[4]"),
    ]
    for i in range(num_layers):
        conns.append(("csr_err_layer_l%d_set" % i, "map_err_layer_set[%d]" % i))
    for i in range(num_layers):
        conns += [
            ("csr_l%d_ctrl_en_out" % i, "map_en[%d]" % i),
            ("csr_l%d_ctrl_alpha_out" % i, "map_alpha[%d]" % i),
            ("csr_l%d_ctrl_alpha_src_out" % i, "map_alpha_src[%d]" % i),
            ("csr_l%d_pos_x_out" % i, "map_x[%d]" % i),
            ("csr_l%d_pos_y_out" % i, "map_y[%d]" % i),
            ("csr_l%d_size_width_out" % i, "map_w[%d]" % i),
            ("csr_l%d_size_height_out" % i, "map_h[%d]" % i),
            ("csr_l%d_status_armed_in" % i, "map_armed[%d]" % i),
            ("csr_l%d_status_dropped_in" % i, "map_dropped[%d]" % i),
            ("csr_l%d_status_cfg_bad_in" % i, "map_cfg_bad[%d]" % i),
            ("csr_l%d_status_fifo_level_in" % i, "map_level[%d]" % i),
        ]

    width = max(len(p) for p, _ in conns)
    for port, sig in conns:
        o.append("      .%-*s (%s),\n" % (width, port, sig))

    for sig in ("awaddr", "awprot", "awvalid", "awready", "wdata", "wstrb", "wvalid", "wready",
                "bresp", "bvalid", "bready", "araddr", "arprot", "arvalid", "arready",
                "rdata", "rresp", "rvalid", "rready"):
        o.append("      .axil_%-*s (axil_%s),\n" % (width - 5, sig, sig))

    # Drop the trailing comma of the final connection.
    o[-1] = o[-1].rstrip().rstrip(",") + "\n"
    o.append("  );\n\nendmodule\n")

    with open(path, "w") as f:
        f.write("".join(o))
    return path


def main():
    ap = argparse.ArgumentParser(description=__doc__.strip().splitlines()[3])
    ap.add_argument("-n", "--num-layers", type=int, default=MAX_LAYERS,
                    help="layer blocks in the map, 1 to %d (default %d). This is the maximum "
                         "a build may instantiate, not what it must." % (MAX_LAYERS, MAX_LAYERS))
    ap.add_argument("-o", "--output", default="regs.json", help="output path")
    ap.add_argument("-w", "--wrapper", default="../src/generated/axis_video_mixer_csr.sv",
                    help="path for the generated array adapter")
    args = ap.parse_args()

    if not 1 <= args.num_layers <= MAX_LAYERS:
        sys.exit("gen_regs: layer count must be between 1 and %d, got %d"
                 % (MAX_LAYERS, args.num_layers))

    doc = build(args.num_layers)
    with open(args.output, "w") as f:
        json.dump(doc, f, indent=4)
        f.write("\n")

    emit_csr_wrapper(args.num_layers, args.wrapper)

    last = doc["regmap"][-1]["address"]
    print("wrote %s: %d layer blocks, %d registers, highest address 0x%02X"
          % (args.output, args.num_layers, len(doc["regmap"]), last))
    print("wrote %s: array adapter for up to %d layers"
          % (args.wrapper, args.num_layers))


if __name__ == "__main__":
    main()
