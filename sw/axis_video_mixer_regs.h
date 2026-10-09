// Created with Corsair v1.0.4
#ifndef __AXIS_VIDEO_MIXER_REGS_H
#define __AXIS_VIDEO_MIXER_REGS_H

#define __I  volatile const // 'read only' permissions
#define __O  volatile       // 'write only' permissions
#define __IO volatile       // 'read / write' permissions


#ifdef __cplusplus
#include <cstdint>
extern "C" {
#else
#include <stdint.h>
#endif

#define MIXER_BASE_ADDR 0x0

// ID - Identification and version. Read-only constants, so a correct read here proves the AXI4-Lite path reaches this block before any other register is trusted.
#define MIXER_ID_ADDR 0x0
#define MIXER_ID_RESET 0x4d580101
typedef struct {
    uint32_t VER_MINOR : 8; // Minor version. Increment on backwards-compatible additions.
    uint32_t VER_MAJOR : 8; // Major version. Increment on any incompatible map change.
    uint32_t MAGIC : 16; // Always 0x4D58 (ASCII 'MX'). A read of 0x0000 or 0xFFFF means the bus is not reaching the mixer.
} mixer_id_t;

// ID.VER_MINOR - Minor version. Increment on backwards-compatible additions.
#define MIXER_ID_VER_MINOR_WIDTH 8
#define MIXER_ID_VER_MINOR_LSB 0
#define MIXER_ID_VER_MINOR_MASK 0xff
#define MIXER_ID_VER_MINOR_RESET 0x1

// ID.VER_MAJOR - Major version. Increment on any incompatible map change.
#define MIXER_ID_VER_MAJOR_WIDTH 8
#define MIXER_ID_VER_MAJOR_LSB 8
#define MIXER_ID_VER_MAJOR_MASK 0xff00
#define MIXER_ID_VER_MAJOR_RESET 0x1

// ID.MAGIC - Always 0x4D58 (ASCII 'MX'). A read of 0x0000 or 0xFFFF means the bus is not reaching the mixer.
#define MIXER_ID_MAGIC_WIDTH 16
#define MIXER_ID_MAGIC_LSB 16
#define MIXER_ID_MAGIC_MASK 0xffff0000
#define MIXER_ID_MAGIC_RESET 0x4d58

// CAPS - Build-time capabilities, so software can size its own layer loops and unpack pixels from the hardware it is actually talking to instead of from a compile-time assumption. Every field is driven from the corresponding RTL parameter rather than baked into the map, so one map describes every build and none of these can be stale.
#define MIXER_CAPS_ADDR 0x4
#define MIXER_CAPS_RESET 0x0
typedef struct {
    uint32_t NUM_LAYERS : 8; // Number of layer input streams this build instantiates, 1 to 8. The top level brings out 8 sets of stream ports regardless; the ones at or above this index are not implemented and hold their TREADY low, and their L<i>_* registers read as zero.
    uint32_t FIFO_DEPTH_LOG2 : 8; // Per-layer input FIFO depth in BEATS, as a power of two. A layer wider than PPC * 2**this cannot be guaranteed free of underflow, because a window at x = 0 gets no head start within the output line.
    uint32_t OUT_HAS_ALPHA : 1; // 1 if the output stream carries RGBA per pixel, 0 if it carries RGB with alpha discarded after blending.
    uint32_t CH_W : 7; // Colour component width in bits: 8, 10, 12 or 16. A pixel is four components, 4*CH_W bits, packed {R, G, B, A} with R in the most significant and alpha in the least. Read this before unpacking TDATA -- it is the only thing that says where the component boundaries are.
    uint32_t PPC : 8; // Pixels per beat on every stream, 1, 2, 4 or 8. Also the horizontal alignment granularity: CANVAS.WIDTH, Ln_POS.X and Ln_SIZE.WIDTH must all be multiples of this, and a write that is not is rejected with ERR.CFG rather than rounded. Read it before computing a layout.
} mixer_caps_t;

// CAPS.NUM_LAYERS - Number of layer input streams this build instantiates, 1 to 8. The top level brings out 8 sets of stream ports regardless; the ones at or above this index are not implemented and hold their TREADY low, and their L<i>_* registers read as zero.
#define MIXER_CAPS_NUM_LAYERS_WIDTH 8
#define MIXER_CAPS_NUM_LAYERS_LSB 0
#define MIXER_CAPS_NUM_LAYERS_MASK 0xff
#define MIXER_CAPS_NUM_LAYERS_RESET 0x0

// CAPS.FIFO_DEPTH_LOG2 - Per-layer input FIFO depth in BEATS, as a power of two. A layer wider than PPC * 2**this cannot be guaranteed free of underflow, because a window at x = 0 gets no head start within the output line.
#define MIXER_CAPS_FIFO_DEPTH_LOG2_WIDTH 8
#define MIXER_CAPS_FIFO_DEPTH_LOG2_LSB 8
#define MIXER_CAPS_FIFO_DEPTH_LOG2_MASK 0xff00
#define MIXER_CAPS_FIFO_DEPTH_LOG2_RESET 0x0

// CAPS.OUT_HAS_ALPHA - 1 if the output stream carries RGBA per pixel, 0 if it carries RGB with alpha discarded after blending.
#define MIXER_CAPS_OUT_HAS_ALPHA_WIDTH 1
#define MIXER_CAPS_OUT_HAS_ALPHA_LSB 16
#define MIXER_CAPS_OUT_HAS_ALPHA_MASK 0x10000
#define MIXER_CAPS_OUT_HAS_ALPHA_RESET 0x0

// CAPS.CH_W - Colour component width in bits: 8, 10, 12 or 16. A pixel is four components, 4*CH_W bits, packed {R, G, B, A} with R in the most significant and alpha in the least. Read this before unpacking TDATA -- it is the only thing that says where the component boundaries are.
#define MIXER_CAPS_CH_W_WIDTH 7
#define MIXER_CAPS_CH_W_LSB 17
#define MIXER_CAPS_CH_W_MASK 0xfe0000
#define MIXER_CAPS_CH_W_RESET 0x0

// CAPS.PPC - Pixels per beat on every stream, 1, 2, 4 or 8. Also the horizontal alignment granularity: CANVAS.WIDTH, Ln_POS.X and Ln_SIZE.WIDTH must all be multiples of this, and a write that is not is rejected with ERR.CFG rather than rounded. Read it before computing a layout.
#define MIXER_CAPS_PPC_WIDTH 8
#define MIXER_CAPS_PPC_LSB 24
#define MIXER_CAPS_PPC_MASK 0xff000000
#define MIXER_CAPS_PPC_RESET 0x0

// SCRATCH - Read/write scratchpad with no hardware effect. Exists so a write-then-read test can prove the bus end to end without disturbing the picture.
#define MIXER_SCRATCH_ADDR 0x8
#define MIXER_SCRATCH_RESET 0x0
typedef struct {
    uint32_t VALUE : 32; // Any value. Reads back exactly what was written.
} mixer_scratch_t;

// SCRATCH.VALUE - Any value. Reads back exactly what was written.
#define MIXER_SCRATCH_VALUE_WIDTH 32
#define MIXER_SCRATCH_VALUE_LSB 0
#define MIXER_SCRATCH_VALUE_MASK 0xffffffff
#define MIXER_SCRATCH_VALUE_RESET 0x0

// CTRL - Global mixer control.
#define MIXER_CTRL_ADDR 0xc
#define MIXER_CTRL_RESET 0x0
typedef struct {
    uint32_t EN : 1; // Enable the output stream. While 0 the mixer holds TVALID low and accepts and discards nothing -- layer inputs are backpressured. Set the canvas and layer geometry first, then set this.
    uint32_t : 7; // reserved
    uint32_t SOFT_RST : 1; // Write 1 to resynchronise the whole datapath: flush every layer FIFO, drop to the top of a new output frame, and re-arm each layer at its next input SOF. Self-clearing; does not touch configuration registers.
    uint32_t : 23; // reserved
} mixer_ctrl_t;

// CTRL.EN - Enable the output stream. While 0 the mixer holds TVALID low and accepts and discards nothing -- layer inputs are backpressured. Set the canvas and layer geometry first, then set this.
#define MIXER_CTRL_EN_WIDTH 1
#define MIXER_CTRL_EN_LSB 0
#define MIXER_CTRL_EN_MASK 0x1
#define MIXER_CTRL_EN_RESET 0x0

// CTRL.SOFT_RST - Write 1 to resynchronise the whole datapath: flush every layer FIFO, drop to the top of a new output frame, and re-arm each layer at its next input SOF. Self-clearing; does not touch configuration registers.
#define MIXER_CTRL_SOFT_RST_WIDTH 1
#define MIXER_CTRL_SOFT_RST_LSB 8
#define MIXER_CTRL_SOFT_RST_MASK 0x100
#define MIXER_CTRL_SOFT_RST_RESET 0x0

// CANVAS - Output raster size in pixels. The mixer emits HEIGHT lines of WIDTH pixels per frame. Changing either takes effect at the next output frame boundary.
#define MIXER_CANVAS_ADDR 0x10
#define MIXER_CANVAS_RESET 0x2d00500
typedef struct {
    uint32_t WIDTH : 16; // Output active width in pixels. Must be non-zero.
    uint32_t HEIGHT : 16; // Output active height in lines. Must be non-zero.
} mixer_canvas_t;

// CANVAS.WIDTH - Output active width in pixels. Must be non-zero.
#define MIXER_CANVAS_WIDTH_WIDTH 16
#define MIXER_CANVAS_WIDTH_LSB 0
#define MIXER_CANVAS_WIDTH_MASK 0xffff
#define MIXER_CANVAS_WIDTH_RESET 0x500

// CANVAS.HEIGHT - Output active height in lines. Must be non-zero.
#define MIXER_CANVAS_HEIGHT_WIDTH 16
#define MIXER_CANVAS_HEIGHT_LSB 16
#define MIXER_CANVAS_HEIGHT_MASK 0xffff0000
#define MIXER_CANVAS_HEIGHT_RESET 0x2d0

// BACKGROUND - Colour of the canvas underneath every layer. This is what shows through wherever no enabled layer covers a pixel, which is why no layer is obliged to span the whole canvas -- every input can be an arbitrary rectangle.
#define MIXER_BACKGROUND_ADDR 0x14
#define MIXER_BACKGROUND_RESET 0x0
typedef struct {
    uint32_t RGB : 24; // Background colour, {R[23:16], G[15:8], B[7:0]}.
    uint32_t : 8; // reserved
} mixer_background_t;

// BACKGROUND.RGB - Background colour, {R[23:16], G[15:8], B[7:0]}.
#define MIXER_BACKGROUND_RGB_WIDTH 24
#define MIXER_BACKGROUND_RGB_LSB 0
#define MIXER_BACKGROUND_RGB_MASK 0xffffff
#define MIXER_BACKGROUND_RGB_RESET 0x0

// STATUS - Live state. Read-only and never latched -- these reflect the current cycle, unlike the ERR register which latches.
#define MIXER_STATUS_ADDR 0x18
#define MIXER_STATUS_RESET 0x0
typedef struct {
    uint32_t ERR_ANY : 1; // 1 while any bit in ERR is set. Lets a polling loop check one register instead of two.
    uint32_t FRAME_ACTIVE : 1; // 1 while the output is mid-frame (between SOF and the last pixel of the last line).
    uint32_t : 14; // reserved
    uint32_t LAYER_ARMED : 8; // One bit per layer: 1 once that layer has seen its input SOF and is delivering pixels. A layer that stays 0 is not receiving a stream.
    uint32_t : 8; // reserved
} mixer_status_t;

// STATUS.ERR_ANY - 1 while any bit in ERR is set. Lets a polling loop check one register instead of two.
#define MIXER_STATUS_ERR_ANY_WIDTH 1
#define MIXER_STATUS_ERR_ANY_LSB 0
#define MIXER_STATUS_ERR_ANY_MASK 0x1
#define MIXER_STATUS_ERR_ANY_RESET 0x0

// STATUS.FRAME_ACTIVE - 1 while the output is mid-frame (between SOF and the last pixel of the last line).
#define MIXER_STATUS_FRAME_ACTIVE_WIDTH 1
#define MIXER_STATUS_FRAME_ACTIVE_LSB 1
#define MIXER_STATUS_FRAME_ACTIVE_MASK 0x2
#define MIXER_STATUS_FRAME_ACTIVE_RESET 0x0

// STATUS.LAYER_ARMED - One bit per layer: 1 once that layer has seen its input SOF and is delivering pixels. A layer that stays 0 is not receiving a stream.
#define MIXER_STATUS_LAYER_ARMED_WIDTH 8
#define MIXER_STATUS_LAYER_ARMED_LSB 16
#define MIXER_STATUS_LAYER_ARMED_MASK 0xff0000
#define MIXER_STATUS_LAYER_ARMED_RESET 0x0

// FRAME_COUNT - Output frames completed since reset. Incrementing proves the pipeline is running; a stuck value with EN set means the output is stalled or a layer is starving.
#define MIXER_FRAME_COUNT_ADDR 0x1c
#define MIXER_FRAME_COUNT_RESET 0x0
typedef struct {
    uint32_t COUNT : 32; // Free-running, wraps at 2**32.
} mixer_frame_count_t;

// FRAME_COUNT.COUNT - Free-running, wraps at 2**32.
#define MIXER_FRAME_COUNT_COUNT_WIDTH 32
#define MIXER_FRAME_COUNT_COUNT_LSB 0
#define MIXER_FRAME_COUNT_COUNT_MASK 0xffffffff
#define MIXER_FRAME_COUNT_COUNT_RESET 0x0

// ERR - Latched error flags. Hardware sets, software clears by writing 1 to the bit. Latched rather than live because every one of these is a transient that would otherwise be missed between two polls.
#define MIXER_ERR_ADDR 0x20
#define MIXER_ERR_RESET 0x0
typedef struct {
    uint32_t CFG : 1; // Configuration rejected: canvas width or height is zero, or an enabled layer's window is zero-sized or extends past the canvas edge. The offending layer is flagged in ERR_LAYER; a canvas fault sets this bit alone. The mixer keeps running on the last valid configuration.
    uint32_t STARVE : 1; // A layer's input FIFO ran empty at a pixel where that layer was due to contribute. The layer is dropped for the remainder of the frame and re-arms at its next input SOF; the output never stalls.
    uint32_t GEOM : 1; // A layer's stream geometry disagreed with its SIZE register -- TLAST arrived somewhere other than the configured last pixel of a line, or TUSER somewhere other than the first pixel of a frame. That layer resynchronises at its next input SOF.
    uint32_t SRC_STALL : 1; // A layer input was held backpressured -- TVALID high, TREADY low because its FIFO was full -- for longer than STALL_LIMIT cycles. The mirror image of OUT_STALL: that source is producing faster than the mixer consumes, which in practice means a frame rate mismatch. Harmless in short bursts, which is why it is measured against a threshold rather than flagged on the first stalled cycle.
    uint32_t OUT_STALL : 1; // The downstream sink held TREADY low for longer than the stall threshold while the mixer had a beat to give. Distinguishes 'the display pipeline is blocked' from 'a source is starving', which look identical from a stuck FRAME_COUNT alone.
    uint32_t : 27; // reserved
} mixer_err_t;

// ERR.CFG - Configuration rejected: canvas width or height is zero, or an enabled layer's window is zero-sized or extends past the canvas edge. The offending layer is flagged in ERR_LAYER; a canvas fault sets this bit alone. The mixer keeps running on the last valid configuration.
#define MIXER_ERR_CFG_WIDTH 1
#define MIXER_ERR_CFG_LSB 0
#define MIXER_ERR_CFG_MASK 0x1
#define MIXER_ERR_CFG_RESET 0x0

// ERR.STARVE - A layer's input FIFO ran empty at a pixel where that layer was due to contribute. The layer is dropped for the remainder of the frame and re-arms at its next input SOF; the output never stalls.
#define MIXER_ERR_STARVE_WIDTH 1
#define MIXER_ERR_STARVE_LSB 1
#define MIXER_ERR_STARVE_MASK 0x2
#define MIXER_ERR_STARVE_RESET 0x0

// ERR.GEOM - A layer's stream geometry disagreed with its SIZE register -- TLAST arrived somewhere other than the configured last pixel of a line, or TUSER somewhere other than the first pixel of a frame. That layer resynchronises at its next input SOF.
#define MIXER_ERR_GEOM_WIDTH 1
#define MIXER_ERR_GEOM_LSB 2
#define MIXER_ERR_GEOM_MASK 0x4
#define MIXER_ERR_GEOM_RESET 0x0

// ERR.SRC_STALL - A layer input was held backpressured -- TVALID high, TREADY low because its FIFO was full -- for longer than STALL_LIMIT cycles. The mirror image of OUT_STALL: that source is producing faster than the mixer consumes, which in practice means a frame rate mismatch. Harmless in short bursts, which is why it is measured against a threshold rather than flagged on the first stalled cycle.
#define MIXER_ERR_SRC_STALL_WIDTH 1
#define MIXER_ERR_SRC_STALL_LSB 3
#define MIXER_ERR_SRC_STALL_MASK 0x8
#define MIXER_ERR_SRC_STALL_RESET 0x0

// ERR.OUT_STALL - The downstream sink held TREADY low for longer than the stall threshold while the mixer had a beat to give. Distinguishes 'the display pipeline is blocked' from 'a source is starving', which look identical from a stuck FRAME_COUNT alone.
#define MIXER_ERR_OUT_STALL_WIDTH 1
#define MIXER_ERR_OUT_STALL_LSB 4
#define MIXER_ERR_OUT_STALL_MASK 0x10
#define MIXER_ERR_OUT_STALL_RESET 0x0

// ERR_LAYER - One latched bit per layer, set alongside the per-layer causes in ERR. Names which input is at fault without having to read every layer's status register. Write 1 to a bit to clear that layer alone.
#define MIXER_ERR_LAYER_ADDR 0x24
#define MIXER_ERR_LAYER_RESET 0x0
typedef struct {
    uint32_t L0 : 1; // Layer 0 has latched a starve, geometry or overflow fault.
    uint32_t L1 : 1; // Layer 1 has latched a starve, geometry or overflow fault.
    uint32_t L2 : 1; // Layer 2 has latched a starve, geometry or overflow fault.
    uint32_t L3 : 1; // Layer 3 has latched a starve, geometry or overflow fault.
    uint32_t L4 : 1; // Layer 4 has latched a starve, geometry or overflow fault.
    uint32_t L5 : 1; // Layer 5 has latched a starve, geometry or overflow fault.
    uint32_t L6 : 1; // Layer 6 has latched a starve, geometry or overflow fault.
    uint32_t L7 : 1; // Layer 7 has latched a starve, geometry or overflow fault.
    uint32_t : 24; // reserved
} mixer_err_layer_t;

// ERR_LAYER.L0 - Layer 0 has latched a starve, geometry or overflow fault.
#define MIXER_ERR_LAYER_L0_WIDTH 1
#define MIXER_ERR_LAYER_L0_LSB 0
#define MIXER_ERR_LAYER_L0_MASK 0x1
#define MIXER_ERR_LAYER_L0_RESET 0x0

// ERR_LAYER.L1 - Layer 1 has latched a starve, geometry or overflow fault.
#define MIXER_ERR_LAYER_L1_WIDTH 1
#define MIXER_ERR_LAYER_L1_LSB 1
#define MIXER_ERR_LAYER_L1_MASK 0x2
#define MIXER_ERR_LAYER_L1_RESET 0x0

// ERR_LAYER.L2 - Layer 2 has latched a starve, geometry or overflow fault.
#define MIXER_ERR_LAYER_L2_WIDTH 1
#define MIXER_ERR_LAYER_L2_LSB 2
#define MIXER_ERR_LAYER_L2_MASK 0x4
#define MIXER_ERR_LAYER_L2_RESET 0x0

// ERR_LAYER.L3 - Layer 3 has latched a starve, geometry or overflow fault.
#define MIXER_ERR_LAYER_L3_WIDTH 1
#define MIXER_ERR_LAYER_L3_LSB 3
#define MIXER_ERR_LAYER_L3_MASK 0x8
#define MIXER_ERR_LAYER_L3_RESET 0x0

// ERR_LAYER.L4 - Layer 4 has latched a starve, geometry or overflow fault.
#define MIXER_ERR_LAYER_L4_WIDTH 1
#define MIXER_ERR_LAYER_L4_LSB 4
#define MIXER_ERR_LAYER_L4_MASK 0x10
#define MIXER_ERR_LAYER_L4_RESET 0x0

// ERR_LAYER.L5 - Layer 5 has latched a starve, geometry or overflow fault.
#define MIXER_ERR_LAYER_L5_WIDTH 1
#define MIXER_ERR_LAYER_L5_LSB 5
#define MIXER_ERR_LAYER_L5_MASK 0x20
#define MIXER_ERR_LAYER_L5_RESET 0x0

// ERR_LAYER.L6 - Layer 6 has latched a starve, geometry or overflow fault.
#define MIXER_ERR_LAYER_L6_WIDTH 1
#define MIXER_ERR_LAYER_L6_LSB 6
#define MIXER_ERR_LAYER_L6_MASK 0x40
#define MIXER_ERR_LAYER_L6_RESET 0x0

// ERR_LAYER.L7 - Layer 7 has latched a starve, geometry or overflow fault.
#define MIXER_ERR_LAYER_L7_WIDTH 1
#define MIXER_ERR_LAYER_L7_LSB 7
#define MIXER_ERR_LAYER_L7_MASK 0x80
#define MIXER_ERR_LAYER_L7_RESET 0x0

// IRQ_EN - Interrupt enable, one bit per ERR bit and in the same order. The irq output is the OR of (ERR & IRQ_EN), so it stays asserted until software clears the ERR bit.
#define MIXER_IRQ_EN_ADDR 0x28
#define MIXER_IRQ_EN_RESET 0x0
typedef struct {
    uint32_t CFG : 1; // Enable interrupt on ERR.CFG.
    uint32_t STARVE : 1; // Enable interrupt on ERR.STARVE.
    uint32_t GEOM : 1; // Enable interrupt on ERR.GEOM.
    uint32_t SRC_STALL : 1; // Enable interrupt on ERR.SRC_STALL.
    uint32_t OUT_STALL : 1; // Enable interrupt on ERR.OUT_STALL.
    uint32_t : 27; // reserved
} mixer_irq_en_t;

// IRQ_EN.CFG - Enable interrupt on ERR.CFG.
#define MIXER_IRQ_EN_CFG_WIDTH 1
#define MIXER_IRQ_EN_CFG_LSB 0
#define MIXER_IRQ_EN_CFG_MASK 0x1
#define MIXER_IRQ_EN_CFG_RESET 0x0

// IRQ_EN.STARVE - Enable interrupt on ERR.STARVE.
#define MIXER_IRQ_EN_STARVE_WIDTH 1
#define MIXER_IRQ_EN_STARVE_LSB 1
#define MIXER_IRQ_EN_STARVE_MASK 0x2
#define MIXER_IRQ_EN_STARVE_RESET 0x0

// IRQ_EN.GEOM - Enable interrupt on ERR.GEOM.
#define MIXER_IRQ_EN_GEOM_WIDTH 1
#define MIXER_IRQ_EN_GEOM_LSB 2
#define MIXER_IRQ_EN_GEOM_MASK 0x4
#define MIXER_IRQ_EN_GEOM_RESET 0x0

// IRQ_EN.SRC_STALL - Enable interrupt on ERR.SRC_STALL.
#define MIXER_IRQ_EN_SRC_STALL_WIDTH 1
#define MIXER_IRQ_EN_SRC_STALL_LSB 3
#define MIXER_IRQ_EN_SRC_STALL_MASK 0x8
#define MIXER_IRQ_EN_SRC_STALL_RESET 0x0

// IRQ_EN.OUT_STALL - Enable interrupt on ERR.OUT_STALL.
#define MIXER_IRQ_EN_OUT_STALL_WIDTH 1
#define MIXER_IRQ_EN_OUT_STALL_LSB 4
#define MIXER_IRQ_EN_OUT_STALL_MASK 0x10
#define MIXER_IRQ_EN_OUT_STALL_RESET 0x0

// STALL_LIMIT - How long a stream may stay stalled before ERR.OUT_STALL or ERR.SRC_STALL latches, in clock cycles. Applies to both directions: the downstream sink holding TREADY low, and a layer source held backpressured on a full FIFO. Reset is 0x10000 -- comfortably longer than any legitimate gap, comfortably shorter than a frame.
#define MIXER_STALL_LIMIT_ADDR 0x2c
#define MIXER_STALL_LIMIT_RESET 0x10000
typedef struct {
    uint32_t CYCLES : 32; // 0 disables the check.
} mixer_stall_limit_t;

// STALL_LIMIT.CYCLES - 0 disables the check.
#define MIXER_STALL_LIMIT_CYCLES_WIDTH 32
#define MIXER_STALL_LIMIT_CYCLES_LSB 0
#define MIXER_STALL_LIMIT_CYCLES_MASK 0xffffffff
#define MIXER_STALL_LIMIT_CYCLES_RESET 0x10000

// L0_CTRL - Layer 0 enable and alpha. Takes effect at the next output frame boundary.
#define MIXER_L0_CTRL_ADDR 0x40
#define MIXER_L0_CTRL_RESET 0xff00
typedef struct {
    uint32_t EN : 1; // Enable this layer. Layer 0. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
    uint32_t : 7; // reserved
    uint32_t ALPHA : 8; // Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
    uint32_t ALPHA_SRC : 1; // Where this layer's alpha comes from.
    uint32_t : 15; // reserved
} mixer_l0_ctrl_t;

// L0_CTRL.EN - Enable this layer. Layer 0. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
#define MIXER_L0_CTRL_EN_WIDTH 1
#define MIXER_L0_CTRL_EN_LSB 0
#define MIXER_L0_CTRL_EN_MASK 0x1
#define MIXER_L0_CTRL_EN_RESET 0x0

// L0_CTRL.ALPHA - Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
#define MIXER_L0_CTRL_ALPHA_WIDTH 8
#define MIXER_L0_CTRL_ALPHA_LSB 8
#define MIXER_L0_CTRL_ALPHA_MASK 0xff00
#define MIXER_L0_CTRL_ALPHA_RESET 0xff

// L0_CTRL.ALPHA_SRC - Where this layer's alpha comes from.
#define MIXER_L0_CTRL_ALPHA_SRC_WIDTH 1
#define MIXER_L0_CTRL_ALPHA_SRC_LSB 16
#define MIXER_L0_CTRL_ALPHA_SRC_MASK 0x10000
#define MIXER_L0_CTRL_ALPHA_SRC_RESET 0x0
typedef enum {
    MIXER_L0_CTRL_ALPHA_SRC_PIXEL_X_GLOBAL = 0x0, //Per-pixel alpha from TDATA multiplied by ALPHA. The usual choice.
    MIXER_L0_CTRL_ALPHA_SRC_GLOBAL_ONLY = 0x1, //Ignore the pixel's alpha channel and use ALPHA alone. Use for a source that leaves its alpha byte undefined.
} mixer_l0_ctrl_alpha_src_t;

// L0_POS - Layer 0 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
#define MIXER_L0_POS_ADDR 0x44
#define MIXER_L0_POS_RESET 0x0
typedef struct {
    uint32_t X : 16; // Left edge, 0 is the leftmost canvas pixel.
    uint32_t Y : 16; // Top edge, 0 is the topmost canvas line.
} mixer_l0_pos_t;

// L0_POS.X - Left edge, 0 is the leftmost canvas pixel.
#define MIXER_L0_POS_X_WIDTH 16
#define MIXER_L0_POS_X_LSB 0
#define MIXER_L0_POS_X_MASK 0xffff
#define MIXER_L0_POS_X_RESET 0x0

// L0_POS.Y - Top edge, 0 is the topmost canvas line.
#define MIXER_L0_POS_Y_WIDTH 16
#define MIXER_L0_POS_Y_LSB 16
#define MIXER_L0_POS_Y_MASK 0xffff0000
#define MIXER_L0_POS_Y_RESET 0x0

// L0_SIZE - Layer 0 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
#define MIXER_L0_SIZE_ADDR 0x48
#define MIXER_L0_SIZE_RESET 0x0
typedef struct {
    uint32_t WIDTH : 16; // Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
    uint32_t HEIGHT : 16; // Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
} mixer_l0_size_t;

// L0_SIZE.WIDTH - Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
#define MIXER_L0_SIZE_WIDTH_WIDTH 16
#define MIXER_L0_SIZE_WIDTH_LSB 0
#define MIXER_L0_SIZE_WIDTH_MASK 0xffff
#define MIXER_L0_SIZE_WIDTH_RESET 0x0

// L0_SIZE.HEIGHT - Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
#define MIXER_L0_SIZE_HEIGHT_WIDTH 16
#define MIXER_L0_SIZE_HEIGHT_LSB 16
#define MIXER_L0_SIZE_HEIGHT_MASK 0xffff0000
#define MIXER_L0_SIZE_HEIGHT_RESET 0x0

// L0_STATUS - Layer 0 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
#define MIXER_L0_STATUS_ADDR 0x4c
#define MIXER_L0_STATUS_RESET 0x0
typedef struct {
    uint32_t ARMED : 1; // 1 once the layer has seen its input SOF and is streaming.
    uint32_t DROPPED : 1; // 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
    uint32_t CFG_BAD : 1; // 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
    uint32_t : 13; // reserved
    uint32_t FIFO_LEVEL : 16; // Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
} mixer_l0_status_t;

// L0_STATUS.ARMED - 1 once the layer has seen its input SOF and is streaming.
#define MIXER_L0_STATUS_ARMED_WIDTH 1
#define MIXER_L0_STATUS_ARMED_LSB 0
#define MIXER_L0_STATUS_ARMED_MASK 0x1
#define MIXER_L0_STATUS_ARMED_RESET 0x0

// L0_STATUS.DROPPED - 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
#define MIXER_L0_STATUS_DROPPED_WIDTH 1
#define MIXER_L0_STATUS_DROPPED_LSB 1
#define MIXER_L0_STATUS_DROPPED_MASK 0x2
#define MIXER_L0_STATUS_DROPPED_RESET 0x0

// L0_STATUS.CFG_BAD - 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
#define MIXER_L0_STATUS_CFG_BAD_WIDTH 1
#define MIXER_L0_STATUS_CFG_BAD_LSB 2
#define MIXER_L0_STATUS_CFG_BAD_MASK 0x4
#define MIXER_L0_STATUS_CFG_BAD_RESET 0x0

// L0_STATUS.FIFO_LEVEL - Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
#define MIXER_L0_STATUS_FIFO_LEVEL_WIDTH 16
#define MIXER_L0_STATUS_FIFO_LEVEL_LSB 16
#define MIXER_L0_STATUS_FIFO_LEVEL_MASK 0xffff0000
#define MIXER_L0_STATUS_FIFO_LEVEL_RESET 0x0

// L1_CTRL - Layer 1 enable and alpha. Takes effect at the next output frame boundary.
#define MIXER_L1_CTRL_ADDR 0x50
#define MIXER_L1_CTRL_RESET 0xff00
typedef struct {
    uint32_t EN : 1; // Enable this layer. Layer 1. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
    uint32_t : 7; // reserved
    uint32_t ALPHA : 8; // Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
    uint32_t ALPHA_SRC : 1; // Where this layer's alpha comes from.
    uint32_t : 15; // reserved
} mixer_l1_ctrl_t;

// L1_CTRL.EN - Enable this layer. Layer 1. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
#define MIXER_L1_CTRL_EN_WIDTH 1
#define MIXER_L1_CTRL_EN_LSB 0
#define MIXER_L1_CTRL_EN_MASK 0x1
#define MIXER_L1_CTRL_EN_RESET 0x0

// L1_CTRL.ALPHA - Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
#define MIXER_L1_CTRL_ALPHA_WIDTH 8
#define MIXER_L1_CTRL_ALPHA_LSB 8
#define MIXER_L1_CTRL_ALPHA_MASK 0xff00
#define MIXER_L1_CTRL_ALPHA_RESET 0xff

// L1_CTRL.ALPHA_SRC - Where this layer's alpha comes from.
#define MIXER_L1_CTRL_ALPHA_SRC_WIDTH 1
#define MIXER_L1_CTRL_ALPHA_SRC_LSB 16
#define MIXER_L1_CTRL_ALPHA_SRC_MASK 0x10000
#define MIXER_L1_CTRL_ALPHA_SRC_RESET 0x0
typedef enum {
    MIXER_L1_CTRL_ALPHA_SRC_PIXEL_X_GLOBAL = 0x0, //Per-pixel alpha from TDATA multiplied by ALPHA. The usual choice.
    MIXER_L1_CTRL_ALPHA_SRC_GLOBAL_ONLY = 0x1, //Ignore the pixel's alpha channel and use ALPHA alone. Use for a source that leaves its alpha byte undefined.
} mixer_l1_ctrl_alpha_src_t;

// L1_POS - Layer 1 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
#define MIXER_L1_POS_ADDR 0x54
#define MIXER_L1_POS_RESET 0x0
typedef struct {
    uint32_t X : 16; // Left edge, 0 is the leftmost canvas pixel.
    uint32_t Y : 16; // Top edge, 0 is the topmost canvas line.
} mixer_l1_pos_t;

// L1_POS.X - Left edge, 0 is the leftmost canvas pixel.
#define MIXER_L1_POS_X_WIDTH 16
#define MIXER_L1_POS_X_LSB 0
#define MIXER_L1_POS_X_MASK 0xffff
#define MIXER_L1_POS_X_RESET 0x0

// L1_POS.Y - Top edge, 0 is the topmost canvas line.
#define MIXER_L1_POS_Y_WIDTH 16
#define MIXER_L1_POS_Y_LSB 16
#define MIXER_L1_POS_Y_MASK 0xffff0000
#define MIXER_L1_POS_Y_RESET 0x0

// L1_SIZE - Layer 1 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
#define MIXER_L1_SIZE_ADDR 0x58
#define MIXER_L1_SIZE_RESET 0x0
typedef struct {
    uint32_t WIDTH : 16; // Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
    uint32_t HEIGHT : 16; // Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
} mixer_l1_size_t;

// L1_SIZE.WIDTH - Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
#define MIXER_L1_SIZE_WIDTH_WIDTH 16
#define MIXER_L1_SIZE_WIDTH_LSB 0
#define MIXER_L1_SIZE_WIDTH_MASK 0xffff
#define MIXER_L1_SIZE_WIDTH_RESET 0x0

// L1_SIZE.HEIGHT - Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
#define MIXER_L1_SIZE_HEIGHT_WIDTH 16
#define MIXER_L1_SIZE_HEIGHT_LSB 16
#define MIXER_L1_SIZE_HEIGHT_MASK 0xffff0000
#define MIXER_L1_SIZE_HEIGHT_RESET 0x0

// L1_STATUS - Layer 1 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
#define MIXER_L1_STATUS_ADDR 0x5c
#define MIXER_L1_STATUS_RESET 0x0
typedef struct {
    uint32_t ARMED : 1; // 1 once the layer has seen its input SOF and is streaming.
    uint32_t DROPPED : 1; // 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
    uint32_t CFG_BAD : 1; // 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
    uint32_t : 13; // reserved
    uint32_t FIFO_LEVEL : 16; // Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
} mixer_l1_status_t;

// L1_STATUS.ARMED - 1 once the layer has seen its input SOF and is streaming.
#define MIXER_L1_STATUS_ARMED_WIDTH 1
#define MIXER_L1_STATUS_ARMED_LSB 0
#define MIXER_L1_STATUS_ARMED_MASK 0x1
#define MIXER_L1_STATUS_ARMED_RESET 0x0

// L1_STATUS.DROPPED - 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
#define MIXER_L1_STATUS_DROPPED_WIDTH 1
#define MIXER_L1_STATUS_DROPPED_LSB 1
#define MIXER_L1_STATUS_DROPPED_MASK 0x2
#define MIXER_L1_STATUS_DROPPED_RESET 0x0

// L1_STATUS.CFG_BAD - 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
#define MIXER_L1_STATUS_CFG_BAD_WIDTH 1
#define MIXER_L1_STATUS_CFG_BAD_LSB 2
#define MIXER_L1_STATUS_CFG_BAD_MASK 0x4
#define MIXER_L1_STATUS_CFG_BAD_RESET 0x0

// L1_STATUS.FIFO_LEVEL - Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
#define MIXER_L1_STATUS_FIFO_LEVEL_WIDTH 16
#define MIXER_L1_STATUS_FIFO_LEVEL_LSB 16
#define MIXER_L1_STATUS_FIFO_LEVEL_MASK 0xffff0000
#define MIXER_L1_STATUS_FIFO_LEVEL_RESET 0x0

// L2_CTRL - Layer 2 enable and alpha. Takes effect at the next output frame boundary.
#define MIXER_L2_CTRL_ADDR 0x60
#define MIXER_L2_CTRL_RESET 0xff00
typedef struct {
    uint32_t EN : 1; // Enable this layer. Layer 2. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
    uint32_t : 7; // reserved
    uint32_t ALPHA : 8; // Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
    uint32_t ALPHA_SRC : 1; // Where this layer's alpha comes from.
    uint32_t : 15; // reserved
} mixer_l2_ctrl_t;

// L2_CTRL.EN - Enable this layer. Layer 2. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
#define MIXER_L2_CTRL_EN_WIDTH 1
#define MIXER_L2_CTRL_EN_LSB 0
#define MIXER_L2_CTRL_EN_MASK 0x1
#define MIXER_L2_CTRL_EN_RESET 0x0

// L2_CTRL.ALPHA - Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
#define MIXER_L2_CTRL_ALPHA_WIDTH 8
#define MIXER_L2_CTRL_ALPHA_LSB 8
#define MIXER_L2_CTRL_ALPHA_MASK 0xff00
#define MIXER_L2_CTRL_ALPHA_RESET 0xff

// L2_CTRL.ALPHA_SRC - Where this layer's alpha comes from.
#define MIXER_L2_CTRL_ALPHA_SRC_WIDTH 1
#define MIXER_L2_CTRL_ALPHA_SRC_LSB 16
#define MIXER_L2_CTRL_ALPHA_SRC_MASK 0x10000
#define MIXER_L2_CTRL_ALPHA_SRC_RESET 0x0
typedef enum {
    MIXER_L2_CTRL_ALPHA_SRC_PIXEL_X_GLOBAL = 0x0, //Per-pixel alpha from TDATA multiplied by ALPHA. The usual choice.
    MIXER_L2_CTRL_ALPHA_SRC_GLOBAL_ONLY = 0x1, //Ignore the pixel's alpha channel and use ALPHA alone. Use for a source that leaves its alpha byte undefined.
} mixer_l2_ctrl_alpha_src_t;

// L2_POS - Layer 2 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
#define MIXER_L2_POS_ADDR 0x64
#define MIXER_L2_POS_RESET 0x0
typedef struct {
    uint32_t X : 16; // Left edge, 0 is the leftmost canvas pixel.
    uint32_t Y : 16; // Top edge, 0 is the topmost canvas line.
} mixer_l2_pos_t;

// L2_POS.X - Left edge, 0 is the leftmost canvas pixel.
#define MIXER_L2_POS_X_WIDTH 16
#define MIXER_L2_POS_X_LSB 0
#define MIXER_L2_POS_X_MASK 0xffff
#define MIXER_L2_POS_X_RESET 0x0

// L2_POS.Y - Top edge, 0 is the topmost canvas line.
#define MIXER_L2_POS_Y_WIDTH 16
#define MIXER_L2_POS_Y_LSB 16
#define MIXER_L2_POS_Y_MASK 0xffff0000
#define MIXER_L2_POS_Y_RESET 0x0

// L2_SIZE - Layer 2 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
#define MIXER_L2_SIZE_ADDR 0x68
#define MIXER_L2_SIZE_RESET 0x0
typedef struct {
    uint32_t WIDTH : 16; // Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
    uint32_t HEIGHT : 16; // Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
} mixer_l2_size_t;

// L2_SIZE.WIDTH - Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
#define MIXER_L2_SIZE_WIDTH_WIDTH 16
#define MIXER_L2_SIZE_WIDTH_LSB 0
#define MIXER_L2_SIZE_WIDTH_MASK 0xffff
#define MIXER_L2_SIZE_WIDTH_RESET 0x0

// L2_SIZE.HEIGHT - Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
#define MIXER_L2_SIZE_HEIGHT_WIDTH 16
#define MIXER_L2_SIZE_HEIGHT_LSB 16
#define MIXER_L2_SIZE_HEIGHT_MASK 0xffff0000
#define MIXER_L2_SIZE_HEIGHT_RESET 0x0

// L2_STATUS - Layer 2 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
#define MIXER_L2_STATUS_ADDR 0x6c
#define MIXER_L2_STATUS_RESET 0x0
typedef struct {
    uint32_t ARMED : 1; // 1 once the layer has seen its input SOF and is streaming.
    uint32_t DROPPED : 1; // 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
    uint32_t CFG_BAD : 1; // 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
    uint32_t : 13; // reserved
    uint32_t FIFO_LEVEL : 16; // Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
} mixer_l2_status_t;

// L2_STATUS.ARMED - 1 once the layer has seen its input SOF and is streaming.
#define MIXER_L2_STATUS_ARMED_WIDTH 1
#define MIXER_L2_STATUS_ARMED_LSB 0
#define MIXER_L2_STATUS_ARMED_MASK 0x1
#define MIXER_L2_STATUS_ARMED_RESET 0x0

// L2_STATUS.DROPPED - 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
#define MIXER_L2_STATUS_DROPPED_WIDTH 1
#define MIXER_L2_STATUS_DROPPED_LSB 1
#define MIXER_L2_STATUS_DROPPED_MASK 0x2
#define MIXER_L2_STATUS_DROPPED_RESET 0x0

// L2_STATUS.CFG_BAD - 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
#define MIXER_L2_STATUS_CFG_BAD_WIDTH 1
#define MIXER_L2_STATUS_CFG_BAD_LSB 2
#define MIXER_L2_STATUS_CFG_BAD_MASK 0x4
#define MIXER_L2_STATUS_CFG_BAD_RESET 0x0

// L2_STATUS.FIFO_LEVEL - Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
#define MIXER_L2_STATUS_FIFO_LEVEL_WIDTH 16
#define MIXER_L2_STATUS_FIFO_LEVEL_LSB 16
#define MIXER_L2_STATUS_FIFO_LEVEL_MASK 0xffff0000
#define MIXER_L2_STATUS_FIFO_LEVEL_RESET 0x0

// L3_CTRL - Layer 3 enable and alpha. Takes effect at the next output frame boundary.
#define MIXER_L3_CTRL_ADDR 0x70
#define MIXER_L3_CTRL_RESET 0xff00
typedef struct {
    uint32_t EN : 1; // Enable this layer. Layer 3. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
    uint32_t : 7; // reserved
    uint32_t ALPHA : 8; // Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
    uint32_t ALPHA_SRC : 1; // Where this layer's alpha comes from.
    uint32_t : 15; // reserved
} mixer_l3_ctrl_t;

// L3_CTRL.EN - Enable this layer. Layer 3. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
#define MIXER_L3_CTRL_EN_WIDTH 1
#define MIXER_L3_CTRL_EN_LSB 0
#define MIXER_L3_CTRL_EN_MASK 0x1
#define MIXER_L3_CTRL_EN_RESET 0x0

// L3_CTRL.ALPHA - Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
#define MIXER_L3_CTRL_ALPHA_WIDTH 8
#define MIXER_L3_CTRL_ALPHA_LSB 8
#define MIXER_L3_CTRL_ALPHA_MASK 0xff00
#define MIXER_L3_CTRL_ALPHA_RESET 0xff

// L3_CTRL.ALPHA_SRC - Where this layer's alpha comes from.
#define MIXER_L3_CTRL_ALPHA_SRC_WIDTH 1
#define MIXER_L3_CTRL_ALPHA_SRC_LSB 16
#define MIXER_L3_CTRL_ALPHA_SRC_MASK 0x10000
#define MIXER_L3_CTRL_ALPHA_SRC_RESET 0x0
typedef enum {
    MIXER_L3_CTRL_ALPHA_SRC_PIXEL_X_GLOBAL = 0x0, //Per-pixel alpha from TDATA multiplied by ALPHA. The usual choice.
    MIXER_L3_CTRL_ALPHA_SRC_GLOBAL_ONLY = 0x1, //Ignore the pixel's alpha channel and use ALPHA alone. Use for a source that leaves its alpha byte undefined.
} mixer_l3_ctrl_alpha_src_t;

// L3_POS - Layer 3 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
#define MIXER_L3_POS_ADDR 0x74
#define MIXER_L3_POS_RESET 0x0
typedef struct {
    uint32_t X : 16; // Left edge, 0 is the leftmost canvas pixel.
    uint32_t Y : 16; // Top edge, 0 is the topmost canvas line.
} mixer_l3_pos_t;

// L3_POS.X - Left edge, 0 is the leftmost canvas pixel.
#define MIXER_L3_POS_X_WIDTH 16
#define MIXER_L3_POS_X_LSB 0
#define MIXER_L3_POS_X_MASK 0xffff
#define MIXER_L3_POS_X_RESET 0x0

// L3_POS.Y - Top edge, 0 is the topmost canvas line.
#define MIXER_L3_POS_Y_WIDTH 16
#define MIXER_L3_POS_Y_LSB 16
#define MIXER_L3_POS_Y_MASK 0xffff0000
#define MIXER_L3_POS_Y_RESET 0x0

// L3_SIZE - Layer 3 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
#define MIXER_L3_SIZE_ADDR 0x78
#define MIXER_L3_SIZE_RESET 0x0
typedef struct {
    uint32_t WIDTH : 16; // Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
    uint32_t HEIGHT : 16; // Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
} mixer_l3_size_t;

// L3_SIZE.WIDTH - Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
#define MIXER_L3_SIZE_WIDTH_WIDTH 16
#define MIXER_L3_SIZE_WIDTH_LSB 0
#define MIXER_L3_SIZE_WIDTH_MASK 0xffff
#define MIXER_L3_SIZE_WIDTH_RESET 0x0

// L3_SIZE.HEIGHT - Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
#define MIXER_L3_SIZE_HEIGHT_WIDTH 16
#define MIXER_L3_SIZE_HEIGHT_LSB 16
#define MIXER_L3_SIZE_HEIGHT_MASK 0xffff0000
#define MIXER_L3_SIZE_HEIGHT_RESET 0x0

// L3_STATUS - Layer 3 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
#define MIXER_L3_STATUS_ADDR 0x7c
#define MIXER_L3_STATUS_RESET 0x0
typedef struct {
    uint32_t ARMED : 1; // 1 once the layer has seen its input SOF and is streaming.
    uint32_t DROPPED : 1; // 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
    uint32_t CFG_BAD : 1; // 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
    uint32_t : 13; // reserved
    uint32_t FIFO_LEVEL : 16; // Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
} mixer_l3_status_t;

// L3_STATUS.ARMED - 1 once the layer has seen its input SOF and is streaming.
#define MIXER_L3_STATUS_ARMED_WIDTH 1
#define MIXER_L3_STATUS_ARMED_LSB 0
#define MIXER_L3_STATUS_ARMED_MASK 0x1
#define MIXER_L3_STATUS_ARMED_RESET 0x0

// L3_STATUS.DROPPED - 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
#define MIXER_L3_STATUS_DROPPED_WIDTH 1
#define MIXER_L3_STATUS_DROPPED_LSB 1
#define MIXER_L3_STATUS_DROPPED_MASK 0x2
#define MIXER_L3_STATUS_DROPPED_RESET 0x0

// L3_STATUS.CFG_BAD - 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
#define MIXER_L3_STATUS_CFG_BAD_WIDTH 1
#define MIXER_L3_STATUS_CFG_BAD_LSB 2
#define MIXER_L3_STATUS_CFG_BAD_MASK 0x4
#define MIXER_L3_STATUS_CFG_BAD_RESET 0x0

// L3_STATUS.FIFO_LEVEL - Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
#define MIXER_L3_STATUS_FIFO_LEVEL_WIDTH 16
#define MIXER_L3_STATUS_FIFO_LEVEL_LSB 16
#define MIXER_L3_STATUS_FIFO_LEVEL_MASK 0xffff0000
#define MIXER_L3_STATUS_FIFO_LEVEL_RESET 0x0

// L4_CTRL - Layer 4 enable and alpha. Takes effect at the next output frame boundary.
#define MIXER_L4_CTRL_ADDR 0x80
#define MIXER_L4_CTRL_RESET 0xff00
typedef struct {
    uint32_t EN : 1; // Enable this layer. Layer 4. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
    uint32_t : 7; // reserved
    uint32_t ALPHA : 8; // Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
    uint32_t ALPHA_SRC : 1; // Where this layer's alpha comes from.
    uint32_t : 15; // reserved
} mixer_l4_ctrl_t;

// L4_CTRL.EN - Enable this layer. Layer 4. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
#define MIXER_L4_CTRL_EN_WIDTH 1
#define MIXER_L4_CTRL_EN_LSB 0
#define MIXER_L4_CTRL_EN_MASK 0x1
#define MIXER_L4_CTRL_EN_RESET 0x0

// L4_CTRL.ALPHA - Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
#define MIXER_L4_CTRL_ALPHA_WIDTH 8
#define MIXER_L4_CTRL_ALPHA_LSB 8
#define MIXER_L4_CTRL_ALPHA_MASK 0xff00
#define MIXER_L4_CTRL_ALPHA_RESET 0xff

// L4_CTRL.ALPHA_SRC - Where this layer's alpha comes from.
#define MIXER_L4_CTRL_ALPHA_SRC_WIDTH 1
#define MIXER_L4_CTRL_ALPHA_SRC_LSB 16
#define MIXER_L4_CTRL_ALPHA_SRC_MASK 0x10000
#define MIXER_L4_CTRL_ALPHA_SRC_RESET 0x0
typedef enum {
    MIXER_L4_CTRL_ALPHA_SRC_PIXEL_X_GLOBAL = 0x0, //Per-pixel alpha from TDATA multiplied by ALPHA. The usual choice.
    MIXER_L4_CTRL_ALPHA_SRC_GLOBAL_ONLY = 0x1, //Ignore the pixel's alpha channel and use ALPHA alone. Use for a source that leaves its alpha byte undefined.
} mixer_l4_ctrl_alpha_src_t;

// L4_POS - Layer 4 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
#define MIXER_L4_POS_ADDR 0x84
#define MIXER_L4_POS_RESET 0x0
typedef struct {
    uint32_t X : 16; // Left edge, 0 is the leftmost canvas pixel.
    uint32_t Y : 16; // Top edge, 0 is the topmost canvas line.
} mixer_l4_pos_t;

// L4_POS.X - Left edge, 0 is the leftmost canvas pixel.
#define MIXER_L4_POS_X_WIDTH 16
#define MIXER_L4_POS_X_LSB 0
#define MIXER_L4_POS_X_MASK 0xffff
#define MIXER_L4_POS_X_RESET 0x0

// L4_POS.Y - Top edge, 0 is the topmost canvas line.
#define MIXER_L4_POS_Y_WIDTH 16
#define MIXER_L4_POS_Y_LSB 16
#define MIXER_L4_POS_Y_MASK 0xffff0000
#define MIXER_L4_POS_Y_RESET 0x0

// L4_SIZE - Layer 4 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
#define MIXER_L4_SIZE_ADDR 0x88
#define MIXER_L4_SIZE_RESET 0x0
typedef struct {
    uint32_t WIDTH : 16; // Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
    uint32_t HEIGHT : 16; // Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
} mixer_l4_size_t;

// L4_SIZE.WIDTH - Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
#define MIXER_L4_SIZE_WIDTH_WIDTH 16
#define MIXER_L4_SIZE_WIDTH_LSB 0
#define MIXER_L4_SIZE_WIDTH_MASK 0xffff
#define MIXER_L4_SIZE_WIDTH_RESET 0x0

// L4_SIZE.HEIGHT - Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
#define MIXER_L4_SIZE_HEIGHT_WIDTH 16
#define MIXER_L4_SIZE_HEIGHT_LSB 16
#define MIXER_L4_SIZE_HEIGHT_MASK 0xffff0000
#define MIXER_L4_SIZE_HEIGHT_RESET 0x0

// L4_STATUS - Layer 4 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
#define MIXER_L4_STATUS_ADDR 0x8c
#define MIXER_L4_STATUS_RESET 0x0
typedef struct {
    uint32_t ARMED : 1; // 1 once the layer has seen its input SOF and is streaming.
    uint32_t DROPPED : 1; // 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
    uint32_t CFG_BAD : 1; // 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
    uint32_t : 13; // reserved
    uint32_t FIFO_LEVEL : 16; // Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
} mixer_l4_status_t;

// L4_STATUS.ARMED - 1 once the layer has seen its input SOF and is streaming.
#define MIXER_L4_STATUS_ARMED_WIDTH 1
#define MIXER_L4_STATUS_ARMED_LSB 0
#define MIXER_L4_STATUS_ARMED_MASK 0x1
#define MIXER_L4_STATUS_ARMED_RESET 0x0

// L4_STATUS.DROPPED - 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
#define MIXER_L4_STATUS_DROPPED_WIDTH 1
#define MIXER_L4_STATUS_DROPPED_LSB 1
#define MIXER_L4_STATUS_DROPPED_MASK 0x2
#define MIXER_L4_STATUS_DROPPED_RESET 0x0

// L4_STATUS.CFG_BAD - 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
#define MIXER_L4_STATUS_CFG_BAD_WIDTH 1
#define MIXER_L4_STATUS_CFG_BAD_LSB 2
#define MIXER_L4_STATUS_CFG_BAD_MASK 0x4
#define MIXER_L4_STATUS_CFG_BAD_RESET 0x0

// L4_STATUS.FIFO_LEVEL - Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
#define MIXER_L4_STATUS_FIFO_LEVEL_WIDTH 16
#define MIXER_L4_STATUS_FIFO_LEVEL_LSB 16
#define MIXER_L4_STATUS_FIFO_LEVEL_MASK 0xffff0000
#define MIXER_L4_STATUS_FIFO_LEVEL_RESET 0x0

// L5_CTRL - Layer 5 enable and alpha. Takes effect at the next output frame boundary.
#define MIXER_L5_CTRL_ADDR 0x90
#define MIXER_L5_CTRL_RESET 0xff00
typedef struct {
    uint32_t EN : 1; // Enable this layer. Layer 5. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
    uint32_t : 7; // reserved
    uint32_t ALPHA : 8; // Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
    uint32_t ALPHA_SRC : 1; // Where this layer's alpha comes from.
    uint32_t : 15; // reserved
} mixer_l5_ctrl_t;

// L5_CTRL.EN - Enable this layer. Layer 5. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
#define MIXER_L5_CTRL_EN_WIDTH 1
#define MIXER_L5_CTRL_EN_LSB 0
#define MIXER_L5_CTRL_EN_MASK 0x1
#define MIXER_L5_CTRL_EN_RESET 0x0

// L5_CTRL.ALPHA - Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
#define MIXER_L5_CTRL_ALPHA_WIDTH 8
#define MIXER_L5_CTRL_ALPHA_LSB 8
#define MIXER_L5_CTRL_ALPHA_MASK 0xff00
#define MIXER_L5_CTRL_ALPHA_RESET 0xff

// L5_CTRL.ALPHA_SRC - Where this layer's alpha comes from.
#define MIXER_L5_CTRL_ALPHA_SRC_WIDTH 1
#define MIXER_L5_CTRL_ALPHA_SRC_LSB 16
#define MIXER_L5_CTRL_ALPHA_SRC_MASK 0x10000
#define MIXER_L5_CTRL_ALPHA_SRC_RESET 0x0
typedef enum {
    MIXER_L5_CTRL_ALPHA_SRC_PIXEL_X_GLOBAL = 0x0, //Per-pixel alpha from TDATA multiplied by ALPHA. The usual choice.
    MIXER_L5_CTRL_ALPHA_SRC_GLOBAL_ONLY = 0x1, //Ignore the pixel's alpha channel and use ALPHA alone. Use for a source that leaves its alpha byte undefined.
} mixer_l5_ctrl_alpha_src_t;

// L5_POS - Layer 5 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
#define MIXER_L5_POS_ADDR 0x94
#define MIXER_L5_POS_RESET 0x0
typedef struct {
    uint32_t X : 16; // Left edge, 0 is the leftmost canvas pixel.
    uint32_t Y : 16; // Top edge, 0 is the topmost canvas line.
} mixer_l5_pos_t;

// L5_POS.X - Left edge, 0 is the leftmost canvas pixel.
#define MIXER_L5_POS_X_WIDTH 16
#define MIXER_L5_POS_X_LSB 0
#define MIXER_L5_POS_X_MASK 0xffff
#define MIXER_L5_POS_X_RESET 0x0

// L5_POS.Y - Top edge, 0 is the topmost canvas line.
#define MIXER_L5_POS_Y_WIDTH 16
#define MIXER_L5_POS_Y_LSB 16
#define MIXER_L5_POS_Y_MASK 0xffff0000
#define MIXER_L5_POS_Y_RESET 0x0

// L5_SIZE - Layer 5 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
#define MIXER_L5_SIZE_ADDR 0x98
#define MIXER_L5_SIZE_RESET 0x0
typedef struct {
    uint32_t WIDTH : 16; // Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
    uint32_t HEIGHT : 16; // Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
} mixer_l5_size_t;

// L5_SIZE.WIDTH - Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
#define MIXER_L5_SIZE_WIDTH_WIDTH 16
#define MIXER_L5_SIZE_WIDTH_LSB 0
#define MIXER_L5_SIZE_WIDTH_MASK 0xffff
#define MIXER_L5_SIZE_WIDTH_RESET 0x0

// L5_SIZE.HEIGHT - Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
#define MIXER_L5_SIZE_HEIGHT_WIDTH 16
#define MIXER_L5_SIZE_HEIGHT_LSB 16
#define MIXER_L5_SIZE_HEIGHT_MASK 0xffff0000
#define MIXER_L5_SIZE_HEIGHT_RESET 0x0

// L5_STATUS - Layer 5 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
#define MIXER_L5_STATUS_ADDR 0x9c
#define MIXER_L5_STATUS_RESET 0x0
typedef struct {
    uint32_t ARMED : 1; // 1 once the layer has seen its input SOF and is streaming.
    uint32_t DROPPED : 1; // 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
    uint32_t CFG_BAD : 1; // 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
    uint32_t : 13; // reserved
    uint32_t FIFO_LEVEL : 16; // Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
} mixer_l5_status_t;

// L5_STATUS.ARMED - 1 once the layer has seen its input SOF and is streaming.
#define MIXER_L5_STATUS_ARMED_WIDTH 1
#define MIXER_L5_STATUS_ARMED_LSB 0
#define MIXER_L5_STATUS_ARMED_MASK 0x1
#define MIXER_L5_STATUS_ARMED_RESET 0x0

// L5_STATUS.DROPPED - 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
#define MIXER_L5_STATUS_DROPPED_WIDTH 1
#define MIXER_L5_STATUS_DROPPED_LSB 1
#define MIXER_L5_STATUS_DROPPED_MASK 0x2
#define MIXER_L5_STATUS_DROPPED_RESET 0x0

// L5_STATUS.CFG_BAD - 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
#define MIXER_L5_STATUS_CFG_BAD_WIDTH 1
#define MIXER_L5_STATUS_CFG_BAD_LSB 2
#define MIXER_L5_STATUS_CFG_BAD_MASK 0x4
#define MIXER_L5_STATUS_CFG_BAD_RESET 0x0

// L5_STATUS.FIFO_LEVEL - Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
#define MIXER_L5_STATUS_FIFO_LEVEL_WIDTH 16
#define MIXER_L5_STATUS_FIFO_LEVEL_LSB 16
#define MIXER_L5_STATUS_FIFO_LEVEL_MASK 0xffff0000
#define MIXER_L5_STATUS_FIFO_LEVEL_RESET 0x0

// L6_CTRL - Layer 6 enable and alpha. Takes effect at the next output frame boundary.
#define MIXER_L6_CTRL_ADDR 0xa0
#define MIXER_L6_CTRL_RESET 0xff00
typedef struct {
    uint32_t EN : 1; // Enable this layer. Layer 6. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
    uint32_t : 7; // reserved
    uint32_t ALPHA : 8; // Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
    uint32_t ALPHA_SRC : 1; // Where this layer's alpha comes from.
    uint32_t : 15; // reserved
} mixer_l6_ctrl_t;

// L6_CTRL.EN - Enable this layer. Layer 6. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
#define MIXER_L6_CTRL_EN_WIDTH 1
#define MIXER_L6_CTRL_EN_LSB 0
#define MIXER_L6_CTRL_EN_MASK 0x1
#define MIXER_L6_CTRL_EN_RESET 0x0

// L6_CTRL.ALPHA - Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
#define MIXER_L6_CTRL_ALPHA_WIDTH 8
#define MIXER_L6_CTRL_ALPHA_LSB 8
#define MIXER_L6_CTRL_ALPHA_MASK 0xff00
#define MIXER_L6_CTRL_ALPHA_RESET 0xff

// L6_CTRL.ALPHA_SRC - Where this layer's alpha comes from.
#define MIXER_L6_CTRL_ALPHA_SRC_WIDTH 1
#define MIXER_L6_CTRL_ALPHA_SRC_LSB 16
#define MIXER_L6_CTRL_ALPHA_SRC_MASK 0x10000
#define MIXER_L6_CTRL_ALPHA_SRC_RESET 0x0
typedef enum {
    MIXER_L6_CTRL_ALPHA_SRC_PIXEL_X_GLOBAL = 0x0, //Per-pixel alpha from TDATA multiplied by ALPHA. The usual choice.
    MIXER_L6_CTRL_ALPHA_SRC_GLOBAL_ONLY = 0x1, //Ignore the pixel's alpha channel and use ALPHA alone. Use for a source that leaves its alpha byte undefined.
} mixer_l6_ctrl_alpha_src_t;

// L6_POS - Layer 6 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
#define MIXER_L6_POS_ADDR 0xa4
#define MIXER_L6_POS_RESET 0x0
typedef struct {
    uint32_t X : 16; // Left edge, 0 is the leftmost canvas pixel.
    uint32_t Y : 16; // Top edge, 0 is the topmost canvas line.
} mixer_l6_pos_t;

// L6_POS.X - Left edge, 0 is the leftmost canvas pixel.
#define MIXER_L6_POS_X_WIDTH 16
#define MIXER_L6_POS_X_LSB 0
#define MIXER_L6_POS_X_MASK 0xffff
#define MIXER_L6_POS_X_RESET 0x0

// L6_POS.Y - Top edge, 0 is the topmost canvas line.
#define MIXER_L6_POS_Y_WIDTH 16
#define MIXER_L6_POS_Y_LSB 16
#define MIXER_L6_POS_Y_MASK 0xffff0000
#define MIXER_L6_POS_Y_RESET 0x0

// L6_SIZE - Layer 6 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
#define MIXER_L6_SIZE_ADDR 0xa8
#define MIXER_L6_SIZE_RESET 0x0
typedef struct {
    uint32_t WIDTH : 16; // Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
    uint32_t HEIGHT : 16; // Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
} mixer_l6_size_t;

// L6_SIZE.WIDTH - Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
#define MIXER_L6_SIZE_WIDTH_WIDTH 16
#define MIXER_L6_SIZE_WIDTH_LSB 0
#define MIXER_L6_SIZE_WIDTH_MASK 0xffff
#define MIXER_L6_SIZE_WIDTH_RESET 0x0

// L6_SIZE.HEIGHT - Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
#define MIXER_L6_SIZE_HEIGHT_WIDTH 16
#define MIXER_L6_SIZE_HEIGHT_LSB 16
#define MIXER_L6_SIZE_HEIGHT_MASK 0xffff0000
#define MIXER_L6_SIZE_HEIGHT_RESET 0x0

// L6_STATUS - Layer 6 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
#define MIXER_L6_STATUS_ADDR 0xac
#define MIXER_L6_STATUS_RESET 0x0
typedef struct {
    uint32_t ARMED : 1; // 1 once the layer has seen its input SOF and is streaming.
    uint32_t DROPPED : 1; // 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
    uint32_t CFG_BAD : 1; // 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
    uint32_t : 13; // reserved
    uint32_t FIFO_LEVEL : 16; // Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
} mixer_l6_status_t;

// L6_STATUS.ARMED - 1 once the layer has seen its input SOF and is streaming.
#define MIXER_L6_STATUS_ARMED_WIDTH 1
#define MIXER_L6_STATUS_ARMED_LSB 0
#define MIXER_L6_STATUS_ARMED_MASK 0x1
#define MIXER_L6_STATUS_ARMED_RESET 0x0

// L6_STATUS.DROPPED - 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
#define MIXER_L6_STATUS_DROPPED_WIDTH 1
#define MIXER_L6_STATUS_DROPPED_LSB 1
#define MIXER_L6_STATUS_DROPPED_MASK 0x2
#define MIXER_L6_STATUS_DROPPED_RESET 0x0

// L6_STATUS.CFG_BAD - 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
#define MIXER_L6_STATUS_CFG_BAD_WIDTH 1
#define MIXER_L6_STATUS_CFG_BAD_LSB 2
#define MIXER_L6_STATUS_CFG_BAD_MASK 0x4
#define MIXER_L6_STATUS_CFG_BAD_RESET 0x0

// L6_STATUS.FIFO_LEVEL - Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
#define MIXER_L6_STATUS_FIFO_LEVEL_WIDTH 16
#define MIXER_L6_STATUS_FIFO_LEVEL_LSB 16
#define MIXER_L6_STATUS_FIFO_LEVEL_MASK 0xffff0000
#define MIXER_L6_STATUS_FIFO_LEVEL_RESET 0x0

// L7_CTRL - Layer 7 enable and alpha. Takes effect at the next output frame boundary.
#define MIXER_L7_CTRL_ADDR 0xb0
#define MIXER_L7_CTRL_RESET 0xff00
typedef struct {
    uint32_t EN : 1; // Enable this layer. Layer 7. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
    uint32_t : 7; // reserved
    uint32_t ALPHA : 8; // Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
    uint32_t ALPHA_SRC : 1; // Where this layer's alpha comes from.
    uint32_t : 15; // reserved
} mixer_l7_ctrl_t;

// L7_CTRL.EN - Enable this layer. Layer 7. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
#define MIXER_L7_CTRL_EN_WIDTH 1
#define MIXER_L7_CTRL_EN_LSB 0
#define MIXER_L7_CTRL_EN_MASK 0x1
#define MIXER_L7_CTRL_EN_RESET 0x0

// L7_CTRL.ALPHA - Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
#define MIXER_L7_CTRL_ALPHA_WIDTH 8
#define MIXER_L7_CTRL_ALPHA_LSB 8
#define MIXER_L7_CTRL_ALPHA_MASK 0xff00
#define MIXER_L7_CTRL_ALPHA_RESET 0xff

// L7_CTRL.ALPHA_SRC - Where this layer's alpha comes from.
#define MIXER_L7_CTRL_ALPHA_SRC_WIDTH 1
#define MIXER_L7_CTRL_ALPHA_SRC_LSB 16
#define MIXER_L7_CTRL_ALPHA_SRC_MASK 0x10000
#define MIXER_L7_CTRL_ALPHA_SRC_RESET 0x0
typedef enum {
    MIXER_L7_CTRL_ALPHA_SRC_PIXEL_X_GLOBAL = 0x0, //Per-pixel alpha from TDATA multiplied by ALPHA. The usual choice.
    MIXER_L7_CTRL_ALPHA_SRC_GLOBAL_ONLY = 0x1, //Ignore the pixel's alpha channel and use ALPHA alone. Use for a source that leaves its alpha byte undefined.
} mixer_l7_ctrl_alpha_src_t;

// L7_POS - Layer 7 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
#define MIXER_L7_POS_ADDR 0xb4
#define MIXER_L7_POS_RESET 0x0
typedef struct {
    uint32_t X : 16; // Left edge, 0 is the leftmost canvas pixel.
    uint32_t Y : 16; // Top edge, 0 is the topmost canvas line.
} mixer_l7_pos_t;

// L7_POS.X - Left edge, 0 is the leftmost canvas pixel.
#define MIXER_L7_POS_X_WIDTH 16
#define MIXER_L7_POS_X_LSB 0
#define MIXER_L7_POS_X_MASK 0xffff
#define MIXER_L7_POS_X_RESET 0x0

// L7_POS.Y - Top edge, 0 is the topmost canvas line.
#define MIXER_L7_POS_Y_WIDTH 16
#define MIXER_L7_POS_Y_LSB 16
#define MIXER_L7_POS_Y_MASK 0xffff0000
#define MIXER_L7_POS_Y_RESET 0x0

// L7_SIZE - Layer 7 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
#define MIXER_L7_SIZE_ADDR 0xb8
#define MIXER_L7_SIZE_RESET 0x0
typedef struct {
    uint32_t WIDTH : 16; // Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
    uint32_t HEIGHT : 16; // Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
} mixer_l7_size_t;

// L7_SIZE.WIDTH - Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
#define MIXER_L7_SIZE_WIDTH_WIDTH 16
#define MIXER_L7_SIZE_WIDTH_LSB 0
#define MIXER_L7_SIZE_WIDTH_MASK 0xffff
#define MIXER_L7_SIZE_WIDTH_RESET 0x0

// L7_SIZE.HEIGHT - Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
#define MIXER_L7_SIZE_HEIGHT_WIDTH 16
#define MIXER_L7_SIZE_HEIGHT_LSB 16
#define MIXER_L7_SIZE_HEIGHT_MASK 0xffff0000
#define MIXER_L7_SIZE_HEIGHT_RESET 0x0

// L7_STATUS - Layer 7 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
#define MIXER_L7_STATUS_ADDR 0xbc
#define MIXER_L7_STATUS_RESET 0x0
typedef struct {
    uint32_t ARMED : 1; // 1 once the layer has seen its input SOF and is streaming.
    uint32_t DROPPED : 1; // 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
    uint32_t CFG_BAD : 1; // 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
    uint32_t : 13; // reserved
    uint32_t FIFO_LEVEL : 16; // Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
} mixer_l7_status_t;

// L7_STATUS.ARMED - 1 once the layer has seen its input SOF and is streaming.
#define MIXER_L7_STATUS_ARMED_WIDTH 1
#define MIXER_L7_STATUS_ARMED_LSB 0
#define MIXER_L7_STATUS_ARMED_MASK 0x1
#define MIXER_L7_STATUS_ARMED_RESET 0x0

// L7_STATUS.DROPPED - 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
#define MIXER_L7_STATUS_DROPPED_WIDTH 1
#define MIXER_L7_STATUS_DROPPED_LSB 1
#define MIXER_L7_STATUS_DROPPED_MASK 0x2
#define MIXER_L7_STATUS_DROPPED_RESET 0x0

// L7_STATUS.CFG_BAD - 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
#define MIXER_L7_STATUS_CFG_BAD_WIDTH 1
#define MIXER_L7_STATUS_CFG_BAD_LSB 2
#define MIXER_L7_STATUS_CFG_BAD_MASK 0x4
#define MIXER_L7_STATUS_CFG_BAD_RESET 0x0

// L7_STATUS.FIFO_LEVEL - Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
#define MIXER_L7_STATUS_FIFO_LEVEL_WIDTH 16
#define MIXER_L7_STATUS_FIFO_LEVEL_LSB 16
#define MIXER_L7_STATUS_FIFO_LEVEL_MASK 0xffff0000
#define MIXER_L7_STATUS_FIFO_LEVEL_RESET 0x0


// Register map structure
typedef struct {
    union {
        __I uint32_t ID; // Identification and version. Read-only constants, so a correct read here proves the AXI4-Lite path reaches this block before any other register is trusted.
        __I mixer_id_t ID_bf; // Bit access for ID register
    };
    union {
        __I uint32_t CAPS; // Build-time capabilities, so software can size its own layer loops and unpack pixels from the hardware it is actually talking to instead of from a compile-time assumption. Every field is driven from the corresponding RTL parameter rather than baked into the map, so one map describes every build and none of these can be stale.
        __I mixer_caps_t CAPS_bf; // Bit access for CAPS register
    };
    union {
        __IO uint32_t SCRATCH; // Read/write scratchpad with no hardware effect. Exists so a write-then-read test can prove the bus end to end without disturbing the picture.
        __IO mixer_scratch_t SCRATCH_bf; // Bit access for SCRATCH register
    };
    union {
        __IO uint32_t CTRL; // Global mixer control.
        __IO mixer_ctrl_t CTRL_bf; // Bit access for CTRL register
    };
    union {
        __IO uint32_t CANVAS; // Output raster size in pixels. The mixer emits HEIGHT lines of WIDTH pixels per frame. Changing either takes effect at the next output frame boundary.
        __IO mixer_canvas_t CANVAS_bf; // Bit access for CANVAS register
    };
    union {
        __IO uint32_t BACKGROUND; // Colour of the canvas underneath every layer. This is what shows through wherever no enabled layer covers a pixel, which is why no layer is obliged to span the whole canvas -- every input can be an arbitrary rectangle.
        __IO mixer_background_t BACKGROUND_bf; // Bit access for BACKGROUND register
    };
    union {
        __I uint32_t STATUS; // Live state. Read-only and never latched -- these reflect the current cycle, unlike the ERR register which latches.
        __I mixer_status_t STATUS_bf; // Bit access for STATUS register
    };
    union {
        __I uint32_t FRAME_COUNT; // Output frames completed since reset. Incrementing proves the pipeline is running; a stuck value with EN set means the output is stalled or a layer is starving.
        __I mixer_frame_count_t FRAME_COUNT_bf; // Bit access for FRAME_COUNT register
    };
    union {
        __IO uint32_t ERR; // Latched error flags. Hardware sets, software clears by writing 1 to the bit. Latched rather than live because every one of these is a transient that would otherwise be missed between two polls.
        __IO mixer_err_t ERR_bf; // Bit access for ERR register
    };
    union {
        __IO uint32_t ERR_LAYER; // One latched bit per layer, set alongside the per-layer causes in ERR. Names which input is at fault without having to read every layer's status register. Write 1 to a bit to clear that layer alone.
        __IO mixer_err_layer_t ERR_LAYER_bf; // Bit access for ERR_LAYER register
    };
    union {
        __IO uint32_t IRQ_EN; // Interrupt enable, one bit per ERR bit and in the same order. The irq output is the OR of (ERR & IRQ_EN), so it stays asserted until software clears the ERR bit.
        __IO mixer_irq_en_t IRQ_EN_bf; // Bit access for IRQ_EN register
    };
    union {
        __IO uint32_t STALL_LIMIT; // How long a stream may stay stalled before ERR.OUT_STALL or ERR.SRC_STALL latches, in clock cycles. Applies to both directions: the downstream sink holding TREADY low, and a layer source held backpressured on a full FIFO. Reset is 0x10000 -- comfortably longer than any legitimate gap, comfortably shorter than a frame.
        __IO mixer_stall_limit_t STALL_LIMIT_bf; // Bit access for STALL_LIMIT register
    };
    __IO uint32_t RESERVED0[4];
    union {
        __IO uint32_t L0_CTRL; // Layer 0 enable and alpha. Takes effect at the next output frame boundary.
        __IO mixer_l0_ctrl_t L0_CTRL_bf; // Bit access for L0_CTRL register
    };
    union {
        __IO uint32_t L0_POS; // Layer 0 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
        __IO mixer_l0_pos_t L0_POS_bf; // Bit access for L0_POS register
    };
    union {
        __IO uint32_t L0_SIZE; // Layer 0 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
        __IO mixer_l0_size_t L0_SIZE_bf; // Bit access for L0_SIZE register
    };
    union {
        __I uint32_t L0_STATUS; // Layer 0 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
        __I mixer_l0_status_t L0_STATUS_bf; // Bit access for L0_STATUS register
    };
    union {
        __IO uint32_t L1_CTRL; // Layer 1 enable and alpha. Takes effect at the next output frame boundary.
        __IO mixer_l1_ctrl_t L1_CTRL_bf; // Bit access for L1_CTRL register
    };
    union {
        __IO uint32_t L1_POS; // Layer 1 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
        __IO mixer_l1_pos_t L1_POS_bf; // Bit access for L1_POS register
    };
    union {
        __IO uint32_t L1_SIZE; // Layer 1 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
        __IO mixer_l1_size_t L1_SIZE_bf; // Bit access for L1_SIZE register
    };
    union {
        __I uint32_t L1_STATUS; // Layer 1 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
        __I mixer_l1_status_t L1_STATUS_bf; // Bit access for L1_STATUS register
    };
    union {
        __IO uint32_t L2_CTRL; // Layer 2 enable and alpha. Takes effect at the next output frame boundary.
        __IO mixer_l2_ctrl_t L2_CTRL_bf; // Bit access for L2_CTRL register
    };
    union {
        __IO uint32_t L2_POS; // Layer 2 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
        __IO mixer_l2_pos_t L2_POS_bf; // Bit access for L2_POS register
    };
    union {
        __IO uint32_t L2_SIZE; // Layer 2 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
        __IO mixer_l2_size_t L2_SIZE_bf; // Bit access for L2_SIZE register
    };
    union {
        __I uint32_t L2_STATUS; // Layer 2 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
        __I mixer_l2_status_t L2_STATUS_bf; // Bit access for L2_STATUS register
    };
    union {
        __IO uint32_t L3_CTRL; // Layer 3 enable and alpha. Takes effect at the next output frame boundary.
        __IO mixer_l3_ctrl_t L3_CTRL_bf; // Bit access for L3_CTRL register
    };
    union {
        __IO uint32_t L3_POS; // Layer 3 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
        __IO mixer_l3_pos_t L3_POS_bf; // Bit access for L3_POS register
    };
    union {
        __IO uint32_t L3_SIZE; // Layer 3 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
        __IO mixer_l3_size_t L3_SIZE_bf; // Bit access for L3_SIZE register
    };
    union {
        __I uint32_t L3_STATUS; // Layer 3 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
        __I mixer_l3_status_t L3_STATUS_bf; // Bit access for L3_STATUS register
    };
    union {
        __IO uint32_t L4_CTRL; // Layer 4 enable and alpha. Takes effect at the next output frame boundary.
        __IO mixer_l4_ctrl_t L4_CTRL_bf; // Bit access for L4_CTRL register
    };
    union {
        __IO uint32_t L4_POS; // Layer 4 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
        __IO mixer_l4_pos_t L4_POS_bf; // Bit access for L4_POS register
    };
    union {
        __IO uint32_t L4_SIZE; // Layer 4 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
        __IO mixer_l4_size_t L4_SIZE_bf; // Bit access for L4_SIZE register
    };
    union {
        __I uint32_t L4_STATUS; // Layer 4 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
        __I mixer_l4_status_t L4_STATUS_bf; // Bit access for L4_STATUS register
    };
    union {
        __IO uint32_t L5_CTRL; // Layer 5 enable and alpha. Takes effect at the next output frame boundary.
        __IO mixer_l5_ctrl_t L5_CTRL_bf; // Bit access for L5_CTRL register
    };
    union {
        __IO uint32_t L5_POS; // Layer 5 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
        __IO mixer_l5_pos_t L5_POS_bf; // Bit access for L5_POS register
    };
    union {
        __IO uint32_t L5_SIZE; // Layer 5 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
        __IO mixer_l5_size_t L5_SIZE_bf; // Bit access for L5_SIZE register
    };
    union {
        __I uint32_t L5_STATUS; // Layer 5 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
        __I mixer_l5_status_t L5_STATUS_bf; // Bit access for L5_STATUS register
    };
    union {
        __IO uint32_t L6_CTRL; // Layer 6 enable and alpha. Takes effect at the next output frame boundary.
        __IO mixer_l6_ctrl_t L6_CTRL_bf; // Bit access for L6_CTRL register
    };
    union {
        __IO uint32_t L6_POS; // Layer 6 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
        __IO mixer_l6_pos_t L6_POS_bf; // Bit access for L6_POS register
    };
    union {
        __IO uint32_t L6_SIZE; // Layer 6 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
        __IO mixer_l6_size_t L6_SIZE_bf; // Bit access for L6_SIZE register
    };
    union {
        __I uint32_t L6_STATUS; // Layer 6 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
        __I mixer_l6_status_t L6_STATUS_bf; // Bit access for L6_STATUS register
    };
    union {
        __IO uint32_t L7_CTRL; // Layer 7 enable and alpha. Takes effect at the next output frame boundary.
        __IO mixer_l7_ctrl_t L7_CTRL_bf; // Bit access for L7_CTRL register
    };
    union {
        __IO uint32_t L7_POS; // Layer 7 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
        __IO mixer_l7_pos_t L7_POS_bf; // Bit access for L7_POS register
    };
    union {
        __IO uint32_t L7_SIZE; // Layer 7 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
        __IO mixer_l7_size_t L7_SIZE_bf; // Bit access for L7_SIZE register
    };
    union {
        __I uint32_t L7_STATUS; // Layer 7 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
        __I mixer_l7_status_t L7_STATUS_bf; // Bit access for L7_STATUS register
    };
} mixer_t;

#define MIXER ((mixer_t*)(MIXER_BASE_ADDR))

#ifdef __cplusplus
}
#endif

#endif /* __AXIS_VIDEO_MIXER_REGS_H */