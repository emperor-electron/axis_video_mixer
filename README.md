# axis_video_mixer

An eight-input AXI4-Stream video mixer. It composites up to eight RGBA video
streams into one, under AXI4-Lite control, for picture-in-picture and tiled
layouts. Components are 8, 10, 12 or 16 bits wide.

It does not scale. Each layer must already arrive at the size its `SIZE`
register declares; the mixer decides only *where* each layer lands and *how*
it blends.

```
   s_axis0 ──►┐
   s_axis1 ──►│
      ...     │  axis_video_mixer  ──► composited AXI4-Stream ──► video out
   s_axis6 ──►│                              (RGB or RGBA)
   s_axis7 ──►┘
                     ▲
                AXI4-Lite
```

Each stream is five named ports — `s_axis3_tvalid`, `s_axis3_tready`,
`s_axis3_tdata`, `s_axis3_tuser`, `s_axis3_tlast` — not a slice of a packed
bus, so a block design or an IP-XACT package sees eight separate AXI4-Stream
interfaces and infers them from the names with no manual mapping.

Forty ports is forty chances to transpose one. §11.5 to §11.9 of
[`doc/design.md`](doc/design.md) are the practical half of that: how to write
the port list and the gather so a swap is visible, the mirror image of the
problem in the parent and the testbench, the lint a partly-wired build
produces, and how to prove the wiring rather than hope.

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
MAX = 2**P_CH_W - 1
a   = ALPHA_SRC ? ALPHA : (pixel_alpha * ALPHA) / MAX
out = (layer * a + below * (MAX - a)) / MAX
```

The divide is by full scale, not by the next power of two. An alpha of `MAX`
has to return the top colour exactly; `>> P_CH_W` returns `(MAX-1)/MAX` of it,
and across a cascade that error accumulates until a stack of nominally opaque
layers is visibly dark. The RTL uses an identity that costs two adds and two
shifts:

```
div_max(C, v) = (t + (t >> C)) >> C      where t = v + 2**(C-1)
```

This is exact against `round(v / MAX)` for every value in `0 .. MAX*MAX`, which
is the whole range the blend can produce. It was checked exhaustively rather
than assumed — all four billion values at `P_CH_W = 16` — and it is proved in
formal at all four widths. The testbench's model computes the same quantity by
integer division, so the two only agree if the identity really holds.

`ALPHA` and `BACKGROUND` stay 8 bits per component at every width and are
expanded in the datapath by bit replication: exact at 0 and full scale,
monotone, and within one LSB of the exact scaling in between. Widening either
would mean a different register map per build, and §12.3 of the design document
is why that trade went the way it did.

## Stream format

All streams, in and out, follow the Xilinx video AXI4-Stream conventions:

| Signal | Meaning |
|---|---|
| `TUSER` | SOF, on the first beat of a frame |
| `TLAST` | EOL, on the last beat of every line |
| `TDATA` | `P_PPC` pixels, lane 0 in the least significant bits; each pixel `{R, G, B, A}` with R in the most significant component |

A pixel is `4 * P_CH_W` bits — 32, 40, 48 or 64 — so it is always a whole
number of bytes, and lane `j` of a beat starts on a byte boundary even though
the components inside it do not. Read `CAPS.CH_W` before unpacking `TDATA`: it
is the only thing that says where the component boundaries are.

Set `P_OUT_HAS_ALPHA = 0` for a `3 * P_CH_W`-bit RGB output that drops straight
into a video output stage; leave it at 1 for RGBA with alpha forced to full
scale, so two mixers can be cascaded.

Everything runs on one clock — every layer input, the output, and the AXI4-Lite
port. Feeding a layer from another clock domain is the caller's job: put an
ordinary AXI4-Stream clock converter in front of that port. Absorbing it here
would mean N asynchronous FIFOs whether or not anyone needed them.

## Parameters

| Parameter | Default | Notes |
|---|---|---|
| `P_NUM_LAYERS` | 4 | Layer streams wired to the datapath, 1 to 8. All eight port sets exist regardless; the rest hold `TREADY` low |
| `P_FIFO_DEPTH` | 2048 | Per layer, in beats. Power of two |
| `P_OUT_HAS_ALPHA` | 1 | 1 = RGBA out, 0 = RGB out |
| `P_PPC` | 1 | Pixels per beat on every stream: 1, 2, 4 or 8 |
| `P_CH_W` | 8 | Colour component width: 8, 10, 12 or 16 |
| `P_AXIL_ADDR_W` | 12 | |

All five are reported back through `CAPS`, driven from the parameters rather
than baked into the register map — so one map describes every build and
software never has to assume any of them.

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

Set `P_NUM_LAYERS`. Nothing else — the register map is generated for the
maximum of eight and the adapter wires up as many layer blocks as the build
asks for, tying off the rest, so any count from 1 to 8 uses the committed map
and the committed C header.

The map only has to be regenerated to change that maximum, and
`regs/gen_regs.py` emits both it and the array adapter that wires corsair's
flat per-field ports to it, so the two cannot disagree:

```bash
cd regs && ./gen_regs.py && corsair -r regs.json -c csrconfig
```

## Design document

[`doc/design.md`](doc/design.md) — requirements, every decision and why, the
traps, and a suggested build order for re-implementing the block from scratch.
[`doc/formal.md`](doc/formal.md) is its verification companion: what the proofs
establish, and where the gaps are.
Diagrams in [`doc/mixer_design.drawio`](doc/mixer_design.drawio) (five tabs,
uncompressed XML).

The section on AXI4-Stream backpressure is the longest, because the three
handshake domains here are deliberately decoupled and that decoupling is the
design: input backpressure must never become output backpressure.

## Registers

Full map in [doc/axis_video_mixer_regs.md](doc/axis_video_mixer_regs.md);
C header in [sw/axis_video_mixer_regs.h](sw/axis_video_mixer_regs.h).

| Offset | Register | |
|---|---|---|
| `0x00` | `ID` | `0x4D58` ('MX'), major, minor |
| `0x04` | `CAPS` | layer count, FIFO depth, output format, component width, pixels per beat |
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
| `0x40 + 0x10*i` | `L<i>_CTRL/POS/SIZE/STATUS` | per layer, `i` = 0..7 |

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
2. Read CAPS        -- layer count, component width and PPC from the hardware,
                       not from an assumption
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

Two suites. Simulation checks that the block produces the right picture from
realistic stimulus; formal checks that a short list of structural claims hold
under *every* stimulus. Neither subsumes the other.

### Simulation

```bash
cd tb
make                      # base test
make regress              # everything
make full                 # one real 1920x1080 frame
make ppc-sweep            # the regression at PPC 1, 2, 4 and 8
make ch-sweep             # the regression at CH_W 8, 10, 12 and 16
make NUM_LAYERS=8 regress
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
| `mixer_alpha_extremes_test` | Alpha 0 and full scale exactly — the two values an approximate blend gets *almost* right |
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

`NUM_LAYERS`, `PPC` and `CH_W` are all plain overrides now: `CAPS` reports them
from the parameters, so none of them needs the register map regenerated.

`PPC` and `CH_W` are compile-time defines rather than elaboration generics,
because the link width the stream UVC is specialised on follows from both — so
changing either rebuilds rather than just re-elaborates, and the snapshot name
carries them so switching cannot silently reuse the other one's build.

### Formal

```bash
make -C formal            # every proof, every task -- about 4m45 from clean
make -C formal quick      # every bmc task, about 30 s, for use while editing
```

SymbiYosys with yosys-slang and boolector, all three from the OSS CAD Suite.
Five proofs over 49 tasks — 154 assertions, 49 cover statements, 15 assumptions
— in [`formal/`](formal), documented in
[`doc/formal.md`](doc/formal.md) — which is where to look for what is bounded
rather than proved, where each assumption is discharged, and what is not
covered.

The three claims that motivated it are the ones a directed test cannot make:

| | |
|---|---|
| **The output never stalls on an input** | `a_raster_advances` — no combination of starving, faulting or backpressured layers can stop the raster. Proved by induction, not sampled by one starve test. |
| **Alignment** | A one-beat offset is a picture that looks almost right, and it survives a scoreboard built from the same assumption as the RTL. The counters are proved to stay inside the configured geometry, and a frame proved to deliver exactly `w x h` beats. |
| **Configuration rejection** | No misaligned or out-of-bounds window can become active, by any path. The solver writes every illegal value there is; a test suite writes the ones someone thought of. |
| **Stream wiring** | Stream `i`'s five named ports reach layer `i` of the datapath and nothing else, and a stream this build does not implement is backpressured rather than silently consumed. A transposed index is two windows in the right places showing the wrong contents, which no single-source bring-up test can see. |

`div_max`'s "verified exhaustively" is now a proof, at all four component
widths, and it extends to `blend_ch` and `blend_rgb`, whose input spaces are
2^48 and larger and were never exhausted — alpha 0 and full scale exactly, no
overshoot, no channel crosstalk — and to the bit replication that expands the
8-bit `ALPHA` and `BACKGROUND` registers to the component width.

Two groups do not run at every width: the ones that put two free-operand
multiplications into one query cost 79 s and 39 s at 8 bits and did not
discharge in five minutes at 10, 12 or 16, on boolector or on bitwuzla, yices
or z3. They are corollaries of the exactness proof, which does run at every
width — `doc/formal.md` §4 is the argument and what it leaves open.

What the proofs leave to the bench is **the picture**: no property says the
composite is the right image for a given set of layer contents, except in the
all-transparent case. That is what the independently written golden blend is
for.

## Files

```
src/axis_video_mixer.sv          top: CSR + core, gathers the named stream ports
src/axis_video_mixer_core.sv     raster, frame latch, blend cascade, errors
src/axis_mixer_layer.sv          per-layer input FSM and resynchronisation
src/axis_mixer_fifo.sv           first-word-fall-through line buffer
src/axis_video_mixer_pkg.sv      blend arithmetic, width-generic, shared with the testbench
src/generated/                   corsair output + the generated array adapter
src/axis_video_mixer.f           drop-in filelist
regs/gen_regs.py                 emits regs.json AND the adapter, sized for 8 layers
tb/                              UVM environment, reusing axi_stream_uvc and axi_lite
formal/                          SymbiYosys proofs; properties bound in, not inlined
```

Consume it from another project with:

```
-f $AXIS_VIDEO_MIXER_ROOT/src/axis_video_mixer.f
```

## Cost and timing

Out-of-context on `xc7z045ffg900-2` at 148.5 MHz (the 1080p60 pixel clock), four
layers, 8-bit components, 2048-deep FIFOs. Reproduce with `syn/syn.tcl`.

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

These figures predate `P_CH_W` and the named ports and stand for the
configuration they name. At eight bits the register expansion folds away to a
wire and the port gather is wires, so this configuration's datapath is the one
that was measured — checked by synthesising the old and new RTL side by side,
which gives the same datapath flop count and combinational totals within 0.3%.
The one real addition is 296 flip-flops in the register file, because the map
now carries eight layer blocks whatever the build instantiates.

**Eight layers and the wider components have not been measured**: expect the
cascade to grow with both — one stage per layer, and `C x C` multiplies per
component per stage — while the raster, the window compares and the register
file do not grow at all. §12.4 of the design document is the shape to expect.

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

**One outstanding AXI4-Lite write at a time.** The CSR adapter keeps a single
captured write address — taken on the `AW` handshake, released on the `B`
handshake — so a second write issued before the first is answered overwrites
it, and the write-one-to-clear decode for `ERR` then applies to the wrong
register. AXI4-Lite *permits* multiple outstanding transactions, so this is
worth stating: the block is safe behind any ordinary master or interconnect,
which issue one at a time, and unsafe behind one that pipelines. Found by
formal, where it is now an explicit assumption rather than an undocumented
property of the implementation — §7 of [`doc/formal.md`](doc/formal.md).
