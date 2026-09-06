# axis_video_mixer

An N-input AXI4-Stream video mixer. It composites several RGBA8 video streams
into one, under AXI4-Lite control, for picture-in-picture and tiled layouts.

It does not scale. Each layer must already arrive at the size its `SIZE`
register declares; the mixer decides only *where* each layer lands and *how*
it blends.

```
   layer 0 ──►┐
   layer 1 ──►│  axis_video_mixer  ──► composited AXI4-Stream ──► video out
   layer 2 ──►│                              (RGB8 or RGBA8)
   layer 3 ──►┘
                     ▲
                AXI4-Lite
```

## The idea

The output is the master, not the inputs. A raster counter free-runs across the
canvas and, at each pixel, asks every layer whose window covers that pixel for
one pixel.

That inversion is what makes picture-in-picture work from plain AXI4-Stream.
Layers need no relationship to each other or to the output beyond their own
rectangle, none has to span the canvas, and the background colour register fills
whatever no layer covers.

The elasticity that makes it work is one FIFO per layer. A layer is consumed
only while the scan is inside its window — `w` pixels out of every `W` on the
lines it covers, and none at all on the lines it does not — while its source
delivers at whatever rate it likes. The FIFO absorbs the difference.

## Two properties worth knowing

**The output never stalls on an input.** If a layer has no pixel ready when its
window opens, that layer is dropped for the remainder of the frame, `ERR.STARVE`
latches, and the raster carries on. A video sink downstream loses lock if the
stream pauses, so a starving source must not be allowed to take the display down
with it. The layer flushes and rejoins on its own once its source resumes.

**Geometry is double buffered.** Position, size, enable and alpha are latched at
a frame boundary and only there, so a window can be moved whenever software
likes without tearing the frame in flight.

## Blending

Porter-Duff *over* with straight (non-premultiplied) alpha, composited bottom-up
in port order: layer 0 nearest the background, the highest-numbered enabled
layer on top. Z-order is fixed by which stream is wired to which port — that
keeps the datapath a straight pipelined cascade rather than a crossbar.

```
a   = ALPHA_SRC ? ALPHA : (pixel_alpha * ALPHA) / 255
out = (layer * a + below * (255 - a)) / 255
```

The divide is by 255, not 256. An alpha of 255 has to return the top colour
exactly; `>> 8` returns 254/255 of it, and across a cascade that error
accumulates until a stack of nominally opaque layers is visibly dark. The RTL
uses an identity that costs two adds and two shifts:

```
div255(v) = (t + (t >> 8)) >> 8      where t = v + 128
```

This is exact against `round(v / 255)` for every value in `0 .. 65025`, which is
the whole range the blend can produce. It was checked exhaustively rather than
assumed, and the testbench's model computes the same quantity by integer
division so the two only agree if the identity really holds.

## Stream format

All streams, in and out, follow the Xilinx video AXI4-Stream conventions:

| Signal | Meaning |
|---|---|
| `TUSER` | SOF, on the first pixel of a frame |
| `TLAST` | EOL, on the last pixel of every line |
| `TDATA` | `{R, G, B, A}` — R in the most significant byte |

Set `P_OUT_HAS_ALPHA = 0` for a 24-bit RGB output that drops straight into a
video output stage; leave it at 1 for 32-bit RGBA8, with alpha forced opaque, so
two mixers can be cascaded.

Everything runs on one clock — every layer input, the output, and the AXI4-Lite
port. Feeding a layer from another clock domain is the caller's job: put an
ordinary AXI4-Stream clock converter in front of that port. Absorbing it here
would mean N asynchronous FIFOs whether or not anyone needed them.

## Parameters

| Parameter | Default | Notes |
|---|---|---|
| `P_NUM_LAYERS` | 4 | Must match the generated register map — checked at elaboration |
| `P_FIFO_DEPTH` | 2048 | Per layer, in pixels. Power of two |
| `P_OUT_HAS_ALPHA` | 1 | 1 = RGBA8 out, 0 = RGB8 out |
| `P_AXIL_ADDR_W` | 12 | |

**Sizing `P_FIFO_DEPTH`.** It must be at least the widest layer the build will
ever show. A window at `x = 0` gets no head start within the line, so a full
line has to be buffered before that line begins. 2048 covers any width up to
1920.

Depth alone is not sufficient, though. Over one output line a layer of width `w`
on a canvas of width `W` must be handed `w` pixels within `W` output beats, so
its source has to average `w/W` beats per cycle — the FIFO absorbs bursts around
that average, it does not lower it. A layer that spans the whole canvas is the
demanding case: `w/W` is 1, and its source must sustain the full pixel rate with
no sustained gap. Fall short and the layer starves, which the mixer reports and
survives, but the picture loses that layer for the frame.

## Changing the layer count

`N` is one command. `regs/gen_regs.py` emits both the register map and the
array adapter that wires corsair's flat, per-field ports to it, so the two
cannot disagree:

```bash
cd regs && ./gen_regs.py -n 8 && corsair -r regs.json -c csrconfig
```

Then build with `P_NUM_LAYERS = 8`. A parameter that disagrees with the
generated map stops elaboration rather than quietly leaving layers unwired.

## Registers

Full map in [doc/axis_video_mixer_regs.md](doc/axis_video_mixer_regs.md);
C header in [sw/axis_video_mixer_regs.h](sw/axis_video_mixer_regs.h).

| Offset | Register | |
|---|---|---|
| `0x00` | `ID` | `0x4D58` ('MX'), major, minor |
| `0x04` | `CAPS` | layer count, FIFO depth, output format |
| `0x08` | `SCRATCH` | proves the bus without changing the picture |
| `0x0C` | `CTRL` | `EN`, `SOFT_RST` |
| `0x10` | `CANVAS` | output width and height |
| `0x14` | `BACKGROUND` | colour under every layer |
| `0x18` | `STATUS` | live: `ERR_ANY`, `FRAME_ACTIVE`, `LAYER_ARMED` |
| `0x1C` | `FRAME_COUNT` | output frames since reset |
| `0x20` | `ERR` | latched faults, write 1 to clear |
| `0x24` | `ERR_LAYER` | which layer, one bit each, write 1 to clear |
| `0x28` | `IRQ_EN` | mask onto `irq` |
| `0x2C` | `STALL_LIMIT` | watchdog threshold, 0 disables |
| `0x40 + 0x10*i` | `L<i>_CTRL/POS/SIZE/STATUS` | per layer |

### Errors

`ERR` latches; `L<i>_STATUS` is live. Both exist because every one of these is a
transient that would otherwise fall between two polls.

| Bit | | Meaning |
|---|---|---|
| 0 | `CFG` | Canvas or an enabled layer's window rejected — zero-sized, or off the canvas. The mixer keeps running on the last valid configuration |
| 1 | `STARVE` | A layer had no pixel when its window opened. Dropped for that frame, re-arms at its next SOF |
| 2 | `GEOM` | A layer's `TLAST`/`TUSER` disagreed with its `SIZE`. That layer resynchronises |
| 3 | `SRC_STALL` | A layer source was backpressured for longer than `STALL_LIMIT` — it is producing faster than the mixer consumes |
| 4 | `OUT_STALL` | The sink held `TREADY` low longer than `STALL_LIMIT` |

`SRC_STALL` and `OUT_STALL` are deliberately a symmetric pair: between them, a
stuck `FRAME_COUNT` can be attributed to the right side of the pipeline instead
of merely observed.

## Bring-up order

```
1. Read ID          -- 0x4D58 or the bus is not reaching the block
2. Read CAPS        -- size your layer loop from the hardware, not an assumption
3. Write CANVAS, BACKGROUND
4. Write L<i>_POS, L<i>_SIZE, L<i>_CTRL for each layer
5. Start the sources; poll STATUS.LAYER_ARMED
6. Write CTRL.EN
```

Steps 5 and 6 are in that order for a reason. Enabling first is perfectly legal
— layers join at the next frame boundary — but the first frame is then
background only. That is correct behaviour that looks exactly like a fault.

While `EN` is 0 the mixer applies configuration immediately, because there is no
frame in flight to protect; once enabled it defers changes to frame boundaries.
Without that, a canvas written before enabling could never take effect: a
disabled mixer never advances its raster, so it never reaches a boundary.

## Verification

```bash
cd tb
make                      # base test
make regress              # everything
make full                 # one real 1920x1080 frame
make TEST=mixer_starve_test
```

The default canvas is 64x8, so a frame is 512 beats and the regression runs in
moments. The simulation FIFO is 128 deep rather than 2048 — a shallow buffer is
the stricter test, because it forces the flow control to work instead of hiding
behind capacity.

| Test | What it would catch |
|---|---|
| `mixer_base_test` | Picture-in-picture: a full-canvas layer and a half-transparent window over it |
| `mixer_backpressure_test` | FIFO pops not gated by the output handshake — every layer would slip against the raster |
| `mixer_tiling_test` | An off-by-one at a window edge, as a seam of background between abutting tiles |
| `mixer_stacked_alpha_test` | Rounding drift, four blend stages deep |
| `mixer_alpha_extremes_test` | Alpha 0 and 255 exactly — the two values an approximate blend gets *almost* right |
| `mixer_move_layer_test` | Geometry applied mid-frame, or a moved layer that never re-arms |
| `mixer_starve_test` | The output stalling when a source dies, and a layer that never comes back |
| `mixer_geometry_error_test` | A source whose `TLAST` disagrees with `SIZE` — legal AXI4-Stream, silently shearing |
| `mixer_bad_config_test` | An out-of-bounds or zero-sized window being acted on |

A test that needs more layers than the build has reports `SKIPPED`, not
`FAILED`.

**Two things the gate checks, not one.** `$error` from inside the RTL does not
touch UVM's error counters, so a run can print thousands of assertion failures
and still end with `result : PASSED`. The Makefile greps for `RTL-ASSERT`
separately and fails the test on any hit. This is not hypothetical: the FIFO's
underflow check fired hundreds of times per run inside a regression that
reported clean, and it went unnoticed until the logs were read directly rather
than through the gate.

**The in-RTL checks are procedural, not `assert property`.** Both the FIFO and
the core check signals that are combinational — `rd_en` is derived from
`rd_valid`, and the output-stability check depends on `TREADY` — and under XSIM
the concurrent form was evaluated on an intermediate delta, before the
combinational network resettled. It reported `rd_en=1` alongside `rd_valid=1`
in the same message, on a property that is structurally impossible to violate.
Checking in an `always_ff` at the clock edge samples what the hardware samples.
If you add a check here, follow that pattern.

 The scoreboard's model is written independently of the RTL's blend
functions, and the checked frame window is enforced inside the scoreboard, where
frame boundaries are seen exactly, rather than by a polling loop in the test.

Note `make regress` at a non-default `NUM_LAYERS` also needs the register map
regenerated to match — see *Changing the layer count*.

## Files

```
src/axis_video_mixer.sv          top: CSR + core, flattens arrays at the boundary
src/axis_video_mixer_core.sv     raster, frame latch, blend cascade, errors
src/axis_mixer_layer.sv          per-layer input FSM and resynchronisation
src/axis_mixer_fifo.sv           first-word-fall-through line buffer
src/axis_video_mixer_pkg.sv      blend arithmetic, shared with the testbench
src/generated/                   corsair output + the generated array adapter
src/axis_video_mixer.f           drop-in filelist
regs/gen_regs.py                 emits regs.json AND the adapter
tb/                              UVM environment, reusing axi_stream_uvc and axi_lite
```

Consume it from another project with:

```
-f $AXIS_VIDEO_MIXER_ROOT/src/axis_video_mixer.f
```

## Cost and timing

Out-of-context on `xc7z045ffg900-2` at 148.5 MHz (the 1080p60 pixel clock), four
layers, 2048-deep FIFOs. Reproduce with `syn/syn.tcl`.

| | |
|---|---|
| WNS / WHS | +0.337 ns / +0.093 ns |
| LUTs | 4040 |
| Flip-flops | 2110 |
| RAMB36 | 8 (two per layer) |
| DSP48 | 0 |

The blend arithmetic lands in LUTs rather than DSPs. That is fine here — it
closes timing with margin and leaves all 900 DSPs for whatever else the design
needs — but it is where the LUTs go, and forcing DSP inference is the first
thing to try if a wider build gets tight.

Getting there needed one structural change worth knowing about. A layer's pixel
comes out of a block RAM, and a BRAM's clock-to-output is most of a cycle at
this frequency. Feeding that straight into the alpha multiply left fourteen
levels of logic in what remained and missed timing by 0.27 ns. The FIFO read now
gets a capture stage of its own, so the arithmetic starts from a flip-flop.

## Known characteristics

The generated register block drives `ARREADY` from a flop cleared by reset, so
it accepts an address phase while held in reset and then returns zeroed data
once reset lifts. A real bus master never transacts during reset; the testbench
waits, and software should too.
