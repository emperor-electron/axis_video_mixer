# AXI4-Stream video mixer register map

Created with [Corsair](https://github.com/esynr3z/corsair) v1.0.4.

## Conventions

| Access mode | Description               |
| :---------- | :------------------------ |
| rw          | Read and Write            |
| rw1c        | Read and Write 1 to Clear |
| rw1s        | Read and Write 1 to Set   |
| ro          | Read Only                 |
| roc         | Read Only to Clear        |
| roll        | Read Only / Latch Low     |
| rolh        | Read Only / Latch High    |
| wo          | Write only                |
| wosc        | Write Only / Self Clear   |

## Register map summary

Base address: 0x00000000

| Name                     | Address    | Description |
| :---                     | :---       | :---        |
| [ID](#id)                | 0x000      | Identification and version. Read-only constants, so a correct read here proves the AXI4-Lite path reaches this block before any other register is trusted. |
| [CAPS](#caps)            | 0x004      | Build-time capabilities, so software can size its own layer loops from the hardware it is actually talking to instead of from a compile-time assumption. These are constants baked into the map by gen_regs.py; axis_video_mixer.sv asserts at elaboration that they match the RTL parameters, so a map and a build that disagree fail loudly rather than misreporting. |
| [SCRATCH](#scratch)      | 0x008      | Read/write scratchpad with no hardware effect. Exists so a write-then-read test can prove the bus end to end without disturbing the picture. |
| [CTRL](#ctrl)            | 0x00c      | Global mixer control. |
| [CANVAS](#canvas)        | 0x010      | Output raster size in pixels. The mixer emits HEIGHT lines of WIDTH pixels per frame. Changing either takes effect at the next output frame boundary. |
| [BACKGROUND](#background) | 0x014      | Colour of the canvas underneath every layer. This is what shows through wherever no enabled layer covers a pixel, which is why no layer is obliged to span the whole canvas -- every input can be an arbitrary rectangle. |
| [STATUS](#status)        | 0x018      | Live state. Read-only and never latched -- these reflect the current cycle, unlike the ERR register which latches. |
| [FRAME_COUNT](#frame_count) | 0x01c      | Output frames completed since reset. Incrementing proves the pipeline is running; a stuck value with EN set means the output is stalled or a layer is starving. |
| [ERR](#err)              | 0x020      | Latched error flags. Hardware sets, software clears by writing 1 to the bit. Latched rather than live because every one of these is a transient that would otherwise be missed between two polls. |
| [ERR_LAYER](#err_layer)  | 0x024      | One latched bit per layer, set alongside the per-layer causes in ERR. Names which input is at fault without having to read every layer's status register. Write 1 to a bit to clear that layer alone. |
| [IRQ_EN](#irq_en)        | 0x028      | Interrupt enable, one bit per ERR bit and in the same order. The irq output is the OR of (ERR & IRQ_EN), so it stays asserted until software clears the ERR bit. |
| [STALL_LIMIT](#stall_limit) | 0x02c      | How long a stream may stay stalled before ERR.OUT_STALL or ERR.SRC_STALL latches, in clock cycles. Applies to both directions: the downstream sink holding TREADY low, and a layer source held backpressured on a full FIFO. Reset is 0x10000 -- comfortably longer than any legitimate gap, comfortably shorter than a frame. |
| [L0_CTRL](#l0_ctrl)      | 0x040      | Layer 0 enable and alpha. Takes effect at the next output frame boundary. |
| [L0_POS](#l0_pos)        | 0x044      | Layer 0 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears. |
| [L0_SIZE](#l0_size)      | 0x048      | Layer 0 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped. |
| [L0_STATUS](#l0_status)  | 0x04c      | Layer 0 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER. |
| [L1_CTRL](#l1_ctrl)      | 0x050      | Layer 1 enable and alpha. Takes effect at the next output frame boundary. |
| [L1_POS](#l1_pos)        | 0x054      | Layer 1 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears. |
| [L1_SIZE](#l1_size)      | 0x058      | Layer 1 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped. |
| [L1_STATUS](#l1_status)  | 0x05c      | Layer 1 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER. |
| [L2_CTRL](#l2_ctrl)      | 0x060      | Layer 2 enable and alpha. Takes effect at the next output frame boundary. |
| [L2_POS](#l2_pos)        | 0x064      | Layer 2 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears. |
| [L2_SIZE](#l2_size)      | 0x068      | Layer 2 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped. |
| [L2_STATUS](#l2_status)  | 0x06c      | Layer 2 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER. |
| [L3_CTRL](#l3_ctrl)      | 0x070      | Layer 3 enable and alpha. Takes effect at the next output frame boundary. |
| [L3_POS](#l3_pos)        | 0x074      | Layer 3 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears. |
| [L3_SIZE](#l3_size)      | 0x078      | Layer 3 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped. |
| [L3_STATUS](#l3_status)  | 0x07c      | Layer 3 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER. |

## ID

Identification and version. Read-only constants, so a correct read here proves the AXI4-Lite path reaches this block before any other register is trusted.

Address offset: 0x000

Reset value: 0x4d580100


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| MAGIC            | 31:16  | ro              | 0x4d58     | Always 0x4D58 (ASCII 'MX'). A read of 0x0000 or 0xFFFF means the bus is not reaching the mixer. |
| VER_MAJOR        | 15:8   | ro              | 0x01       | Major version. Increment on any incompatible map change. |
| VER_MINOR        | 7:0    | ro              | 0x00       | Minor version. Increment on backwards-compatible additions. |

Back to [Register map](#register-map-summary).

## CAPS

Build-time capabilities, so software can size its own layer loops from the hardware it is actually talking to instead of from a compile-time assumption. These are constants baked into the map by gen_regs.py; axis_video_mixer.sv asserts at elaboration that they match the RTL parameters, so a map and a build that disagree fail loudly rather than misreporting.

Address offset: 0x004

Reset value: 0x01010b04


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| PPC              | 31:24  | ro              | 0x01       | Pixels per beat on every stream, 1, 2, 4 or 8. Also the horizontal alignment granularity: CANVAS.WIDTH, Ln_POS.X and Ln_SIZE.WIDTH must all be multiples of this, and a write that is not is rejected with ERR.CFG rather than rounded. Read it before computing a layout. |
| -                | 23:17  | -               | 0x0        | Reserved |
| OUT_HAS_ALPHA    | 16     | ro              | 0x1        | 1 if the output stream carries RGBA8 per pixel, 0 if it carries RGB8 with alpha discarded after blending. |
| FIFO_DEPTH_LOG2  | 15:8   | ro              | 0x0b       | Per-layer input FIFO depth in BEATS, as a power of two. A layer wider than PPC * 2**this cannot be guaranteed free of underflow, because a window at x = 0 gets no head start within the output line. |
| NUM_LAYERS       | 7:0    | ro              | 0x04       | Number of layer input streams this build instantiates. |

Back to [Register map](#register-map-summary).

## SCRATCH

Read/write scratchpad with no hardware effect. Exists so a write-then-read test can prove the bus end to end without disturbing the picture.

Address offset: 0x008

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| VALUE            | 31:0   | rw              | 0x00000000 | Any value. Reads back exactly what was written. |

Back to [Register map](#register-map-summary).

## CTRL

Global mixer control.

Address offset: 0x00c

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| -                | 31:9   | -               | 0x00000    | Reserved |
| SOFT_RST         | 8      | wosc            | 0x0        | Write 1 to resynchronise the whole datapath: flush every layer FIFO, drop to the top of a new output frame, and re-arm each layer at its next input SOF. Self-clearing; does not touch configuration registers. |
| -                | 7:1    | -               | 0x0        | Reserved |
| EN               | 0      | rw              | 0x0        | Enable the output stream. While 0 the mixer holds TVALID low and accepts and discards nothing -- layer inputs are backpressured. Set the canvas and layer geometry first, then set this. |

Back to [Register map](#register-map-summary).

## CANVAS

Output raster size in pixels. The mixer emits HEIGHT lines of WIDTH pixels per frame. Changing either takes effect at the next output frame boundary.

Address offset: 0x010

Reset value: 0x02d00500


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| HEIGHT           | 31:16  | rw              | 0x02d0     | Output active height in lines. Must be non-zero. |
| WIDTH            | 15:0   | rw              | 0x0500     | Output active width in pixels. Must be non-zero. |

Back to [Register map](#register-map-summary).

## BACKGROUND

Colour of the canvas underneath every layer. This is what shows through wherever no enabled layer covers a pixel, which is why no layer is obliged to span the whole canvas -- every input can be an arbitrary rectangle.

Address offset: 0x014

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| -                | 31:24  | -               | 0x00       | Reserved |
| RGB              | 23:0   | rw              | 0x000000   | Background colour, {R[23:16], G[15:8], B[7:0]}. |

Back to [Register map](#register-map-summary).

## STATUS

Live state. Read-only and never latched -- these reflect the current cycle, unlike the ERR register which latches.

Address offset: 0x018

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| -                | 31:20  | -               | 0x000      | Reserved |
| LAYER_ARMED      | 19:16  | ro              | 0x0        | One bit per layer: 1 once that layer has seen its input SOF and is delivering pixels. A layer that stays 0 is not receiving a stream. |
| -                | 15:2   | -               | 0x000      | Reserved |
| FRAME_ACTIVE     | 1      | ro              | 0x0        | 1 while the output is mid-frame (between SOF and the last pixel of the last line). |
| ERR_ANY          | 0      | ro              | 0x0        | 1 while any bit in ERR is set. Lets a polling loop check one register instead of two. |

Back to [Register map](#register-map-summary).

## FRAME_COUNT

Output frames completed since reset. Incrementing proves the pipeline is running; a stuck value with EN set means the output is stalled or a layer is starving.

Address offset: 0x01c

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| COUNT            | 31:0   | ro              | 0x00000000 | Free-running, wraps at 2**32. |

Back to [Register map](#register-map-summary).

## ERR

Latched error flags. Hardware sets, software clears by writing 1 to the bit. Latched rather than live because every one of these is a transient that would otherwise be missed between two polls.

Address offset: 0x020

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| -                | 31:5   | -               | 0x000000   | Reserved |
| OUT_STALL        | 4      | rw1c            | 0x0        | The downstream sink held TREADY low for longer than the stall threshold while the mixer had a beat to give. Distinguishes 'the display pipeline is blocked' from 'a source is starving', which look identical from a stuck FRAME_COUNT alone. |
| SRC_STALL        | 3      | rw1c            | 0x0        | A layer input was held backpressured -- TVALID high, TREADY low because its FIFO was full -- for longer than STALL_LIMIT cycles. The mirror image of OUT_STALL: that source is producing faster than the mixer consumes, which in practice means a frame rate mismatch. Harmless in short bursts, which is why it is measured against a threshold rather than flagged on the first stalled cycle. |
| GEOM             | 2      | rw1c            | 0x0        | A layer's stream geometry disagreed with its SIZE register -- TLAST arrived somewhere other than the configured last pixel of a line, or TUSER somewhere other than the first pixel of a frame. That layer resynchronises at its next input SOF. |
| STARVE           | 1      | rw1c            | 0x0        | A layer's input FIFO ran empty at a pixel where that layer was due to contribute. The layer is dropped for the remainder of the frame and re-arms at its next input SOF; the output never stalls. |
| CFG              | 0      | rw1c            | 0x0        | Configuration rejected: canvas width or height is zero, or an enabled layer's window is zero-sized or extends past the canvas edge. The offending layer is flagged in ERR_LAYER; a canvas fault sets this bit alone. The mixer keeps running on the last valid configuration. |

Back to [Register map](#register-map-summary).

## ERR_LAYER

One latched bit per layer, set alongside the per-layer causes in ERR. Names which input is at fault without having to read every layer's status register. Write 1 to a bit to clear that layer alone.

Address offset: 0x024

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| -                | 31:4   | -               | 0x0000000  | Reserved |
| L3               | 3      | rw1c            | 0x0        | Layer 3 has latched a starve, geometry or overflow fault. |
| L2               | 2      | rw1c            | 0x0        | Layer 2 has latched a starve, geometry or overflow fault. |
| L1               | 1      | rw1c            | 0x0        | Layer 1 has latched a starve, geometry or overflow fault. |
| L0               | 0      | rw1c            | 0x0        | Layer 0 has latched a starve, geometry or overflow fault. |

Back to [Register map](#register-map-summary).

## IRQ_EN

Interrupt enable, one bit per ERR bit and in the same order. The irq output is the OR of (ERR & IRQ_EN), so it stays asserted until software clears the ERR bit.

Address offset: 0x028

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| -                | 31:5   | -               | 0x000000   | Reserved |
| OUT_STALL        | 4      | rw              | 0x0        | Enable interrupt on ERR.OUT_STALL. |
| SRC_STALL        | 3      | rw              | 0x0        | Enable interrupt on ERR.SRC_STALL. |
| GEOM             | 2      | rw              | 0x0        | Enable interrupt on ERR.GEOM. |
| STARVE           | 1      | rw              | 0x0        | Enable interrupt on ERR.STARVE. |
| CFG              | 0      | rw              | 0x0        | Enable interrupt on ERR.CFG. |

Back to [Register map](#register-map-summary).

## STALL_LIMIT

How long a stream may stay stalled before ERR.OUT_STALL or ERR.SRC_STALL latches, in clock cycles. Applies to both directions: the downstream sink holding TREADY low, and a layer source held backpressured on a full FIFO. Reset is 0x10000 -- comfortably longer than any legitimate gap, comfortably shorter than a frame.

Address offset: 0x02c

Reset value: 0x00010000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| CYCLES           | 31:0   | rw              | 0x00010000 | 0 disables the check. |

Back to [Register map](#register-map-summary).

## L0_CTRL

Layer 0 enable and alpha. Takes effect at the next output frame boundary.

Address offset: 0x040

Reset value: 0x0000ff00


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| -                | 31:17  | -               | 0x000      | Reserved |
| ALPHA_SRC        | 16     | rw              | 0x0        | Where this layer's alpha comes from. |
| ALPHA            | 15:8   | rw              | 0xff       | Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise. |
| -                | 7:1    | -               | 0x0        | Reserved |
| EN               | 0      | rw              | 0x0        | Enable this layer. Layer 0. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top. |

Enumerated values for L0_CTRL.ALPHA_SRC.

| Name             | Value   | Description |
| :---             | :---    | :---        |
| PIXEL_X_GLOBAL   | 0x0    | Per-pixel alpha from TDATA multiplied by ALPHA. The usual choice. |
| GLOBAL_ONLY      | 0x1    | Ignore the pixel's alpha channel and use ALPHA alone. Use for a source that leaves its alpha byte undefined. |

Back to [Register map](#register-map-summary).

## L0_POS

Layer 0 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.

Address offset: 0x044

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| Y                | 31:16  | rw              | 0x0000     | Top edge, 0 is the topmost canvas line. |
| X                | 15:0   | rw              | 0x0000     | Left edge, 0 is the leftmost canvas pixel. |

Back to [Register map](#register-map-summary).

## L0_SIZE

Layer 0 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.

Address offset: 0x048

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| HEIGHT           | 31:16  | rw              | 0x0000     | Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height. |
| WIDTH            | 15:0   | rw              | 0x0000     | Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width. |

Back to [Register map](#register-map-summary).

## L0_STATUS

Layer 0 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.

Address offset: 0x04c

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| FIFO_LEVEL       | 31:16  | ro              | 0x0000     | Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy. |
| -                | 15:3   | -               | 0x000      | Reserved |
| CFG_BAD          | 2      | ro              | 0x0        | 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set. |
| DROPPED          | 1      | ro              | 0x0        | 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault. |
| ARMED            | 0      | ro              | 0x0        | 1 once the layer has seen its input SOF and is streaming. |

Back to [Register map](#register-map-summary).

## L1_CTRL

Layer 1 enable and alpha. Takes effect at the next output frame boundary.

Address offset: 0x050

Reset value: 0x0000ff00


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| -                | 31:17  | -               | 0x000      | Reserved |
| ALPHA_SRC        | 16     | rw              | 0x0        | Where this layer's alpha comes from. |
| ALPHA            | 15:8   | rw              | 0xff       | Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise. |
| -                | 7:1    | -               | 0x0        | Reserved |
| EN               | 0      | rw              | 0x0        | Enable this layer. Layer 1. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top. |

Enumerated values for L1_CTRL.ALPHA_SRC.

| Name             | Value   | Description |
| :---             | :---    | :---        |
| PIXEL_X_GLOBAL   | 0x0    | Per-pixel alpha from TDATA multiplied by ALPHA. The usual choice. |
| GLOBAL_ONLY      | 0x1    | Ignore the pixel's alpha channel and use ALPHA alone. Use for a source that leaves its alpha byte undefined. |

Back to [Register map](#register-map-summary).

## L1_POS

Layer 1 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.

Address offset: 0x054

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| Y                | 31:16  | rw              | 0x0000     | Top edge, 0 is the topmost canvas line. |
| X                | 15:0   | rw              | 0x0000     | Left edge, 0 is the leftmost canvas pixel. |

Back to [Register map](#register-map-summary).

## L1_SIZE

Layer 1 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.

Address offset: 0x058

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| HEIGHT           | 31:16  | rw              | 0x0000     | Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height. |
| WIDTH            | 15:0   | rw              | 0x0000     | Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width. |

Back to [Register map](#register-map-summary).

## L1_STATUS

Layer 1 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.

Address offset: 0x05c

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| FIFO_LEVEL       | 31:16  | ro              | 0x0000     | Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy. |
| -                | 15:3   | -               | 0x000      | Reserved |
| CFG_BAD          | 2      | ro              | 0x0        | 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set. |
| DROPPED          | 1      | ro              | 0x0        | 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault. |
| ARMED            | 0      | ro              | 0x0        | 1 once the layer has seen its input SOF and is streaming. |

Back to [Register map](#register-map-summary).

## L2_CTRL

Layer 2 enable and alpha. Takes effect at the next output frame boundary.

Address offset: 0x060

Reset value: 0x0000ff00


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| -                | 31:17  | -               | 0x000      | Reserved |
| ALPHA_SRC        | 16     | rw              | 0x0        | Where this layer's alpha comes from. |
| ALPHA            | 15:8   | rw              | 0xff       | Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise. |
| -                | 7:1    | -               | 0x0        | Reserved |
| EN               | 0      | rw              | 0x0        | Enable this layer. Layer 2. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top. |

Enumerated values for L2_CTRL.ALPHA_SRC.

| Name             | Value   | Description |
| :---             | :---    | :---        |
| PIXEL_X_GLOBAL   | 0x0    | Per-pixel alpha from TDATA multiplied by ALPHA. The usual choice. |
| GLOBAL_ONLY      | 0x1    | Ignore the pixel's alpha channel and use ALPHA alone. Use for a source that leaves its alpha byte undefined. |

Back to [Register map](#register-map-summary).

## L2_POS

Layer 2 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.

Address offset: 0x064

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| Y                | 31:16  | rw              | 0x0000     | Top edge, 0 is the topmost canvas line. |
| X                | 15:0   | rw              | 0x0000     | Left edge, 0 is the leftmost canvas pixel. |

Back to [Register map](#register-map-summary).

## L2_SIZE

Layer 2 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.

Address offset: 0x068

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| HEIGHT           | 31:16  | rw              | 0x0000     | Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height. |
| WIDTH            | 15:0   | rw              | 0x0000     | Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width. |

Back to [Register map](#register-map-summary).

## L2_STATUS

Layer 2 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.

Address offset: 0x06c

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| FIFO_LEVEL       | 31:16  | ro              | 0x0000     | Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy. |
| -                | 15:3   | -               | 0x000      | Reserved |
| CFG_BAD          | 2      | ro              | 0x0        | 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set. |
| DROPPED          | 1      | ro              | 0x0        | 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault. |
| ARMED            | 0      | ro              | 0x0        | 1 once the layer has seen its input SOF and is streaming. |

Back to [Register map](#register-map-summary).

## L3_CTRL

Layer 3 enable and alpha. Takes effect at the next output frame boundary.

Address offset: 0x070

Reset value: 0x0000ff00


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| -                | 31:17  | -               | 0x000      | Reserved |
| ALPHA_SRC        | 16     | rw              | 0x0        | Where this layer's alpha comes from. |
| ALPHA            | 15:8   | rw              | 0xff       | Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise. |
| -                | 7:1    | -               | 0x0        | Reserved |
| EN               | 0      | rw              | 0x0        | Enable this layer. Layer 3. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top. |

Enumerated values for L3_CTRL.ALPHA_SRC.

| Name             | Value   | Description |
| :---             | :---    | :---        |
| PIXEL_X_GLOBAL   | 0x0    | Per-pixel alpha from TDATA multiplied by ALPHA. The usual choice. |
| GLOBAL_ONLY      | 0x1    | Ignore the pixel's alpha channel and use ALPHA alone. Use for a source that leaves its alpha byte undefined. |

Back to [Register map](#register-map-summary).

## L3_POS

Layer 3 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.

Address offset: 0x074

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| Y                | 31:16  | rw              | 0x0000     | Top edge, 0 is the topmost canvas line. |
| X                | 15:0   | rw              | 0x0000     | Left edge, 0 is the leftmost canvas pixel. |

Back to [Register map](#register-map-summary).

## L3_SIZE

Layer 3 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.

Address offset: 0x078

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| HEIGHT           | 31:16  | rw              | 0x0000     | Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height. |
| WIDTH            | 15:0   | rw              | 0x0000     | Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width. |

Back to [Register map](#register-map-summary).

## L3_STATUS

Layer 3 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.

Address offset: 0x07c

Reset value: 0x00000000


| Name             | Bits   | Mode            | Reset      | Description |
| :---             | :---   | :---            | :---       | :---        |
| FIFO_LEVEL       | 31:16  | ro              | 0x0000     | Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy. |
| -                | 15:3   | -               | 0x000      | Reserved |
| CFG_BAD          | 2      | ro              | 0x0        | 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set. |
| DROPPED          | 1      | ro              | 0x0        | 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault. |
| ARMED            | 0      | ro              | 0x0        | 1 once the layer has seen its input SOF and is streaming. |

Back to [Register map](#register-map-summary).
