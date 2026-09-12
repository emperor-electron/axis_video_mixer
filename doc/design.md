# AXI4-Stream video mixer — design document

A specification and a set of design decisions, written so the block can be
re-implemented from scratch rather than read. Diagrams are in
[`mixer_design.drawio`](mixer_design.drawio) — five tabs, uncompressed XML so
it diffs.

Sections 3 and 4 are the ones worth reading slowly. Everything else is
bookkeeping by comparison.

---

## 1. What it does

Composites `N` RGBA8 video streams into one, under AXI4-Lite control, for
picture-in-picture and tiled layouts.

```
N x  AXI4-Stream RGBA8  ──►  mixer  ──►  1 x AXI4-Stream RGB8 or RGBA8
                               ▲
                          AXI4-Lite
```

Video AXI4-Stream conventions throughout (UG934): `TUSER` = SOF on the first
pixel of a frame, `TLAST` = EOL on the last pixel of every line, one pixel per
beat.

### 1.1 Requirements

Numbered so the verification plan in §8 can cite them.

| | Requirement |
|---|---|
| **R1** | Composite `N` layers over a solid background using Porter-Duff *over* with straight (non-premultiplied) alpha. |
| **R2** | Each layer occupies an arbitrary rectangle of the canvas, set at run time by `Ln_POS` and `Ln_SIZE`. |
| **R3** | No scaling. A layer's stream must arrive at exactly the size its `Ln_SIZE` declares. |
| **R4** | Per-layer alpha from a register, optionally multiplied by the pixel's own alpha channel. |
| **R5** | Z-order is fixed by port index: layer 0 nearest the background, highest-numbered on top. |
| **R6** | **The output stream never stalls waiting on an input.** A layer with no pixel available when its window opens is dropped for the remainder of that frame. |
| **R7** | Configuration changes take effect at an output frame boundary, never mid-frame. |
| **R8** | Every fault is latched, attributable to a layer, and clearable: `CFG`, `STARVE`, `GEOM`, `SRC_STALL`, `OUT_STALL`. |
| **R9** | Single clock domain — every input stream, the output, and the AXI4-Lite port. |
| **R10** | `N` is a parameter. The register map is generated from the same number. |
| **R11** | `P_PPC` ∈ {1, 2, 4, 8} pixels per beat, on **every** stream — all `N` inputs and the output. Lane 0 in the least significant bits. |
| **R12** | Horizontal geometry — `CANVAS.WIDTH`, every `Ln_POS.X`, every `Ln_SIZE.WIDTH` — must be a multiple of `P_PPC`. A value that is not is **rejected** with `ERR.CFG`, never rounded. `CAPS.PPC` reports the granularity. |

### 1.2 Explicit non-goals

- **Scaling.** A scaler is a different block with different arithmetic and its
  own line buffers. Keeping it out is what lets a layer be a plain FIFO.
- **Clock domain crossing.** Put an AXI4-Stream clock converter in front of a
  layer if it needs one. Absorbing it here would mean `N` asynchronous FIFOs
  whether or not anyone needed them.
- **Per-interface pixel width.** `P_PPC` is one number for the whole block, not
  one per input. §9.1 gives the reasoning; the short version is that a source at
  a different width belongs behind an AXI4-Stream width converter, for exactly
  the same reason a source on another clock belongs behind a clock converter.
- **Sub-beat horizontal placement.** At `P_PPC > 1` a layer lands on a
  `P_PPC`-pixel grid horizontally (R12). Vertical placement is unconstrained.
  §10 is the whole chapter on lifting this, because it is the interesting part.
- **Run-time z-order.** See §5.4.
- **Colour space conversion**, chroma subsampling, more than one pixel per beat.

---

## 2. Structure

Tab 1 of the drawio file. Three pieces:

- `axis_mixer_layer` × N — SOF-alignment FSM plus a FWFT FIFO. Owns the input
  handshake.
- `axis_video_mixer_core` — output raster, window comparison, frame-boundary
  latch, blend cascade, error aggregation.
- `axis_video_mixer_csr` — the generated register block plus an adapter that
  turns corsair's flat per-layer ports into arrays.

Latency SOF-in to SOF-out is `2 + N` cycles: stage F, stage A, then one blend
stage per layer.

---

## 3. Backpressure

The part that is easy to get subtly wrong, and where a mistake shows up as a
picture that is *almost* right. Tab 2 of the drawio file.

There are three handshake domains. They are deliberately decoupled, and the
decoupling is the design.

### 3.1 Domain A — source into a layer

```systemverilog
assign s_axis_tready = enable ? !fifo_full : 1'b1;
```

`TREADY` depends on FIFO space and nothing else. Not on the raster position,
not on whether the window is currently open, not on the sink.

That is worth stating as a rule because the tempting alternative — assert
`TREADY` only while the raster is inside this layer's window — is wrong in a way
that looks plausible. It couples the input rate to the output raster, so a layer
occupying 5% of the canvas gets 5% of the bandwidth and its source, which is
producing a full frame's worth, backs up until it is a frame behind. The FIFO
exists precisely so the two rates need not match instant to instant.

**The `enable` term is load bearing.** A disabled layer asserts `TREADY`
permanently and discards what it receives. If you backpressure a disabled layer
instead, switching a layer off wedges its upstream source forever — and the
source has no way to discover why. "Drain, don't backpressure" is the rule for
anything you have switched off.

### 3.2 Domain B — FIFO into the cascade

```systemverilog
assign want_px[i] = in_win[i] && lay_active[i] && !lay_dropped[i];
assign lay_pop[i] = want_px[i] &&  lay_px_valid[i] && pipe_en && s0_valid;
assign starve[i]  = want_px[i] && !lay_px_valid[i] && pipe_en && s0_valid;
```

A pop happens when the raster is inside the window, the layer is taking part in
this frame, and a pixel is actually there.

If the raster wants a pixel and none has arrived, that is `starve` — and
**starve does not stall** (R6). It drops the layer for the rest of the frame,
flushes its FIFO, and re-arms at the next input SOF.

Why flush rather than skip a single pixel and carry on: whatever is in that FIFO
is now positionally wrong by however many pixels were missed, and nothing in the
stream says by how many. There is no mid-frame resynchronisation available. SOF
is the only landmark, so the recovery has to wait for one.

### 3.3 Domain C — the output, and the gate everything hangs off

```systemverilog
assign pipe_en = m_axis_tready || !m_axis_tvalid;
```

Read it as: *the last stage may be overwritten if it is being consumed, or if it
holds nothing worth keeping.*

Because every stage shifts under the **same** `pipe_en`, that one condition
propagates backwards for free. The pipeline is a single shift register — either
everything moves or nothing does — and the invariant "no stage is overwritten
while still holding unconsumed valid data" holds by construction rather than by
per-stage argument.

The `|| !m_axis_tvalid` term is not an optimisation. Drop it and a sink that
holds `TREADY` low while the pipe is empty freezes the raster for no reason, and
you lose the fill time you needed in order to have data ready the moment
`TREADY` returns. With it, the pipe fills behind a stalled sink and delivers on
the first ready cycle.

**`pipe_en` must gate every piece of datapath state:**

| | |
|---|---|
| `out_x`, `out_y` | miss these and the raster runs ahead of the pixels — the picture shears |
| `lay_pop[i]` | miss these and you pop a pixel that is never used, shifting that layer by one for the rest of the frame |
| stage F, stage A | |
| `acc_q`, `v_q`, `sof_q`, `eol_q`, `eof_q` | every cascade stage |

### 3.4 The rule that makes it legal AXI4-Stream

**No combinational path from `TREADY` to `TVALID`.**

`m_axis_tvalid` is `v_q[N]`, a flip-flop. `pipe_en` does depend on
`m_axis_tready`, but `pipe_en` only drives register *enables* — it never appears
in the expression for `TVALID`. That is what stops two of these back to back
from forming a combinational loop, and it is the single most common way to break
an AXI4-Stream master.

The same applies at the input: `TREADY` is a function of `fifo_full`, never of
`TVALID`. Either direction of dependency is legal on its own; both at once is a
loop.

### 3.5 Why the monolithic rail rather than an elastic pipeline

An elastic pipeline gives each stage its own valid/ready and a skid buffer, so a
stalled stage does not freeze the ones behind it. More area, more state, and
genuinely better when there are several independent stall sources.

Here there is exactly one — the sink — so nothing is gained. The monolithic rail
is a handful of gates and is much easier to argue about, which matters more than
the throughput it does not cost.

---

## 4. Alignment: the bug you will write

Tab 4 of the drawio file. This one cost real debugging time and is not obvious
from the requirements.

**The mixer consumes a layer positionally.** One pop per output pixel inside the
window. Nothing in the layer's stream carries coordinates, so wherever the first
pop happens is where that layer's top-left corner lands.

Now consider a layer that arms — sees its first SOF — part way through an output
frame. Its pixel zero gets popped part way along a line. And because the layer
thereafter supplies exactly as many pixels per frame as its window consumes,
**that offset never works itself out.** The layer sits skewed by a fixed number
of pixels for as long as it runs. It looks like a diagonal tear that no amount of
staring at the blend logic will explain.

The fix needs two distinct notions of readiness:

| | |
|---|---|
| `armed` | this layer has seen a SOF and is delivering pixels |
| `active` | this layer is taking part in the current output frame |

```systemverilog
if (frame_latch)
    lay_active[i] <= lay_armed[i] && want_en[i] && !lay_flush[i];
```

`active` is set **only** at an output frame boundary. Since nothing pops an
inactive layer, the FIFO head is guaranteed to be pixel zero when the window
first opens.

### 4.1 The layer FSM

Two states, and alignment is re-established from evidence rather than assumed:

- **`WAIT_SOF`** — discard everything until `TUSER`. `armed` low. The SOF beat
  itself is the frame's pixel zero and is kept.
- **`STREAM`** — buffer pixels, counting against `WIDTH` and `HEIGHT`.

```systemverilog
assign geom_bad = accept && ((s_axis_tlast != last_px_of_line) ||
                             (s_axis_tuser != (state != S_STREAM)));
```

`TLAST` anywhere but the configured last pixel of a line, or `TUSER` anywhere
except the frame's first pixel, means the source and the `SIZE` register
disagree about the shape of a frame. Every pixel after that lands in the wrong
place, so: flag `GEOM`, flush, re-arm.

**A clean end of frame returns to `WAIT_SOF` without flushing**, and `armed`
stays high. The FIFO still holds pixels the output has not consumed, and the
next frame queues behind them. That prefill is exactly what keeps a layer at
x = 0 from starving on the first line of the next frame.

---

## 5. Decisions

### 5.1 Cascade, not a tree

Porter-Duff *over* is associative, so a `log2(N)` tree is tempting. It does not
work with an RGB-only accumulator: combining two layers before compositing them
onto the background needs the pair's **composite alpha**, which means carrying
premultiplied RGBA through the tree — more bits, more arithmetic, and a
premultiply/unpremultiply at the boundaries.

The cascade sidesteps it because the bottom of the stack is the **opaque**
background. The accumulator is therefore opaque by construction at every stage,
and *over* onto an opaque destination needs only the top layer's alpha.

Cost is depth `N` rather than `log2(N)` — latency, not frequency, since each
stage is one multiply.

### 5.2 `div255`, not `>> 8`

An alpha of 255 must return the top colour exactly. `>> 8` returns 254/255 of
it, and over a cascade that error accumulates until a stack of nominally opaque
layers visibly darkens.

```systemverilog
div255(v) = (t + (t >> 8)) >> 8,  where t = v + 128
```

Two adds and two shifts, no divider, no table. Exact against `round(v / 255)`
for every `v` in `0 .. 65025` — verify this exhaustively before you trust it;
that range is the full span the blend can produce, because `a + (255 - a) = 255`
caps the numerator at `255 × 255`.

### 5.3 Alpha in its own stage

`effective_alpha = pixel_a × global_a` and the blend are both multiplies. Doing
them in one stage puts two in series and roughly halves the achievable clock.

And that stage is kept clear of the BRAM read (§5.5).

### 5.4 Fixed z-order

Programmable z-order turns a straight pipelined cascade into a crossbar. Z-order
is chosen by which stream is wired to which port. If you want it programmable,
the honest implementation is an `N×N` permutation ahead of the cascade, and you
should expect it to cost you the frequency the cascade was buying.

### 5.5 Stage F, which does nothing

The layer pixel comes out of block RAM, and BRAM clock-to-out is most of a cycle
at 148.5 MHz. Feeding it straight into the alpha multiply left 14 levels of
logic in what remained and missed setup by 0.27 ns.

Stage F captures the read and performs no arithmetic, so stage A starts from a
flip-flop. If you hit timing on the read path, this is the cheap fix.

### 5.6 FIFO depth ≥ one layer line

Tab 5. The worst case is a window at **x = 0**: a layer further right has the
span from the start of the output line until the raster reaches its left edge to
push pixels, but a layer at x = 0 has none. The instant the line begins the
mixer starts popping, so everything that line needs must already be buffered.

Over a whole frame the rates balance exactly — the layer supplies `w × h` and
the mixer consumes `w × h` — so the FIFO absorbs *intra-frame* burstiness, not a
rate mismatch. If the rates genuinely differ you get `STARVE`, and no depth
fixes that.

### 5.7 FWFT, with a prefetch register

The consumer decides whether to pop based on whether data is present; it cannot
afford a read-latency cycle inside the blend pipeline and cannot speculatively
pop. At `2048 × 32 × N` the storage must be block RAM, which has registered
output. So: BRAM plus a prefetch register.

```systemverilog
assign mem_rd_en = (rd_ptr != wr_ptr) && (!rd_valid || rd_en);
```

One condition covers all four combinations of `rd_valid` and `rd_en` with no
state machine: fetch whenever memory holds something and the prefetch slot is
empty or is being emptied this cycle.

Pointers carry one bit more than the address so full and empty are
distinguishable without sacrificing an entry.

### 5.8 `SRC_STALL`, not `OVERFLOW`

The first draft had an `ERR.OVERFLOW` for a source writing to a full FIFO. It
cannot happen: `TREADY = !full`, so a compliant master never pushes while full,
and a non-compliant one is out of scope.

What is worth reporting is the mirror of `OUT_STALL` — a source held
backpressured beyond `STALL_LIMIT`, meaning it is producing faster than the
mixer consumes. Note that this is *normal* for a small layer whose source runs
at full canvas rate, which is why it is thresholded rather than flagged on the
first stalled cycle, and why `STALL_LIMIT = 0` disables it.

---

### 5.9 Suggested build order

Each step is independently testable, so a failure is localised rather than a
whole-design mystery. This is roughly the order the block was built in, and the
order the traps in §7 surface.

| | Build | Done when |
|---|---|---|
| 1 | `div255` / `blend_ch` / `blend_rgb` as pure functions | exhaustively checked against `round(v/255)` over `0..65025` in whatever language is convenient — do this before any RTL |
| 2 | FWFT FIFO alone | random push/pop, `full`/`rd_valid` never lie, `level` matches |
| 3 | **N = 1, layer spans the canvas, alpha forced 255** | a pass-through: output is bit-identical to input. Proves the raster, the pop, and the pipeline shift before any blending is in the way |
| 4 | Add the blend against a solid background, still N = 1 | alpha 0 and 255 exactly, then the middle |
| 5 | Shrink the layer to a sub-rectangle | this is where the FIFO depth argument (§5.6) and window comparison get exercised |
| 6 | `pipe_en` and a random-`TREADY` sink | pixels bit-identical to the step-5 run. **This is the test that catches every flow-control mistake in §3.3** |
| 7 | N > 1 and the cascade | different pattern per layer, so a z-order error is visible |
| 8 | The layer FSM: `armed`, then `active` | arm a layer mid-frame deliberately and watch §4 happen |
| 9 | Frame-boundary latch, then the register map | §6.1 |
| 10 | Errors and watchdogs | last, because every one of them needs a way to provoke it |
| 11 | `P_PPC > 1` | §9. Do it after step 10, not before — every bug above is easier to find with one pixel per beat, and the multi-pixel version is a replication of a design that already works |

For step 11 the single most valuable test is a mutation that is **invisible at
`P_PPC = 1`**: make every lane composite lane 0's pixel. If your suite still
passes at `P_PPC = 4`, it is checking lane 0 and calling it a beat.

Step 6 is the one to spend time on. If the pixel stream under random
backpressure is not bit-identical to the unstalled stream, something is not
gated on `pipe_en`, and finding out at step 6 is much cheaper than at step 10.

---

### 5.10 Cheat sheet

Everything load-bearing in one place.

```systemverilog
// ---- the flow control -------------------------------------------------
pipe_en   = m_axis_tready || !m_axis_tvalid;   // gates ALL datapath state
s_tready  = enable ? !fifo_full : 1'b1;        // drain a disabled layer
m_tvalid  = v_q[N];                            // registered. never from tready

// ---- consuming a layer (beat domain; at PPC=1 a beat is a pixel) -------
out_bx    = beat index across the canvas, 0 .. W/P - 1
in_win[i] = act_en[i] && out_bx >= bx[i] && out_bx < bx[i]+bw[i]
                      && out_y  >=  y[i] && out_y  <  y[i]+h[i];
want_px[i]= in_win[i] && lay_active[i] && !lay_dropped[i];
pop[i]    = want_px[i] &&  px_valid[i] && pipe_en && s0_valid;
starve[i] = want_px[i] && !px_valid[i] && pipe_en && s0_valid;  // drop, never stall

// ---- alignment --------------------------------------------------------
if (frame_latch) lay_active[i] <= lay_armed[i] && want_en[i] && !lay_flush[i];

// ---- double buffering -------------------------------------------------
frame_boundary = soft_rst || (pipe_en && s0_valid && s0_eof);
frame_latch    = frame_boundary || !act_ok || !ctrl_en;   // last two terms matter

// ---- FIFO prefetch ----------------------------------------------------
mem_rd_en = (rd_ptr != wr_ptr) && (!rd_valid || rd_en);

// ---- multi-pixel ------------------------------------------------------
bx[i]  = x[i] >> log2(P);   bw[i] = w[i] >> log2(P);   // exact: alignment enforced
win_ok = ((x[i] | w[i] | canvas_width) & (P-1)) == 0;  // else ERR.CFG
// lanes share CONTROL, not data:
//   per beat: v_q[k] sof_q[k] eol_q[k] eof_q[k] popf_q[i] alphaf_q[i]
//   per lane: acc_q[k][j] lrgb_q[k][i][j] la_q[k][i][j]

// ---- arithmetic -------------------------------------------------------
div255(v)          = (t + (t>>8)) >> 8,  t = v + 128
blend_ch(top,bot,a)= div255(top*a + bot*(255-a))
effective_alpha    = src_sel ? global_a : mul255(pixel_a, global_a)
```

---

## 6. Registers

Full map in [`axis_video_mixer_regs.md`](axis_video_mixer_regs.md). Generated by
`regs/gen_regs.py` from the same `N` that parameterises the RTL; the RTL asserts
at elaboration that the two agree.

Global block at `0x00`, per-layer blocks at `0x40 + 0x10n`, so adding a global
register never renumbers a layer register.

### 6.1 Double buffering

```systemverilog
assign frame_boundary = soft_rst || (pipe_en && s0_valid && s0_eof);
assign frame_latch    = frame_boundary || !act_ok || !ctrl_en;
```

Everything geometric is latched at `frame_latch` into `act_*` registers, and the
datapath reads only those (R7).

**The `!ctrl_en` term is not tidiness — it is a bug fix.** A disabled mixer does
not advance its raster, so it never reaches a frame boundary. Without that term,
a canvas written *before* `EN` was set could never take effect, and the block
would silently keep drawing at its reset size. Which is to say: the natural
software order — configure, then enable — was the one order that did not work.

Alpha is deliberately excluded from `geo_changed`: it changes the blend but not
the pixel accounting, so it can take effect without costing the layer a frame.

### 6.2 `ERR.CFG` latches once per frame, not continuously

corsair gives the hardware set priority over the software clear, by design, so
an error is never lost. A level-driven `CFG` would therefore re-set the bit
every cycle and software could never clear it while the bad value remained.
Once per frame boundary stays clearable; the live view is in `Ln_STATUS.CFG_BAD`.

---

## 7. Traps

Ranked by how long each one cost.

1. **Layer arming mid-frame** (§4). Permanent fixed skew, self-consistent,
   invisible in the blend logic.
2. **Config unreachable before `EN`** (§6.1).
3. **BRAM clock-to-out into the multiply** (§5.5).
4. **`rw1c` on a multi-bit field.** corsair drives one shared set strobe across
   the whole field, so `ERR_LAYER` as an N-bit mask set every bit at once and any
   non-zero write cleared all of them. Emit one 1-bit field per layer.
5. **Concurrent assertions on combinational signals.** `rd_en |-> rd_valid` is
   structurally impossible to violate, and fired thousands of times under XSIM —
   evaluated on an intermediate delta before the combinational network resettled.
   Check at the clock edge in an `always_ff` and you sample what the hardware
   samples. Anything checking combinationally-derived signals belongs there.
6. **A regression that could not fail.** The point above was found only because
   an independent Makefile gate grepped for the assertion text. A pass/fail
   channel that nothing tests is not a pass/fail channel.

---

## 8. Verification

`cd tb && make regress`. Nine tests; the ones that earn their place:

| Test | Requirement |
|---|---|
| `mixer_tiling_test` | R1, R2, R5 — non-overlapping layers, z-order |
| `mixer_stacked_alpha_test` | R1, R4 — overlapping, blend arithmetic |
| `mixer_alpha_extremes_test` | R4 — 0 and 255 exactly, where a `>>8` approximation still looks plausible |
| `mixer_starve_test` | R6 — a source that stops; output must keep running |
| `mixer_geometry_error_test` | R3, R8 — stream disagrees with `SIZE` |
| `mixer_bad_config_test` | R8 — window out of bounds |
| `mixer_move_layer_test` | R2, R7 — layer moved on a running mixer |
| `mixer_backpressure_test` | R6 — random `TREADY`; pixels must be bit-identical to the unstalled run |

Two properties of the bench worth copying:

- **The golden blend is written independently** — integer division where the RTL
  uses the shift-and-add identity. Sharing the function would make the model
  agree with the DUT by construction, which is the agreement the scoreboard
  exists to test.
- **The scoreboard recomputes each layer's pixels** from a shared content
  function rather than observing the input streams. That is what lets it predict
  a composite without subscribing to N input monitors and re-deriving their
  framing — and it is the stronger check, because it verifies the pixel at
  canvas `(x, y)` is the one the covering layer should have produced *at its own
  coordinate*.

Mutation-test the bench before believing it. Reverse the hash word order,
transpose a window, swap two layers — if the suite still passes, it is not
testing what you think.

---

## 9. Multi-pixel per clock

Pixel rate is the reason this exists. 4K60 is 594 MHz, which no fabric of this
class will clock; at `P_PPC = 4` it is 148.5 MHz, which this block already
meets. The knob buys throughput with area and costs nothing in frequency,
because the blend is **replicated per lane** rather than made deeper.

### 9.1 Why one PPC for the block, not one per interface

The obvious reading of "N pixels per clock per input interface" is that each
input gets its own width. It is worth being explicit that this design does not
do that, and why.

Inside its window a layer must supply **one pixel per canvas pixel**. So a layer
feeding a canvas that consumes `P` pixels per beat has to deliver `P` per beat
while the window is open, whatever its own natural width is. A 1-pixel-per-beat
source into a 4-pixel-per-beat canvas cannot sustain its window — not on
average, and the average is not the binding constraint anyway.

You can make it work with a width converter: buffer at the source's width, read
at the canvas's. That is a standard, well-understood piece of IP that needs to
know nothing about this block. Building `N` of them inside would cost area
whether or not anyone used them, and would put a second rate-matching FIFO
behind the one already there.

So the rule is the same as for clocks: **convert outside, at the port that needs
it.** The mixer has one width, and it is `P_PPC`.

### 9.2 The beat-alignment constraint, and what it buys

R12 constrains horizontal geometry to whole beats. That single decision is why
almost nothing in this design had to change:

| | `P_PPC = 1` | `P_PPC > 1`, beat aligned | `P_PPC > 1`, arbitrary x |
|---|---|---|---|
| Window test | 1 compare / layer / beat | **1 compare / layer / beat** | `P` compares / layer / beat |
| Pixels popped per beat | 0 or 1 | **0 or `P`, all lanes together** | 0..`P`, varying |
| Layer read side | FIFO head | **FIFO head** | barrel shifter + residue |
| Line ends mid-beat? | no | **no** | yes — `TKEEP` starts meaning something |

With the constraint, every output beat is **entirely inside or entirely outside**
each window. So `in_win` stays one bit per layer per beat, `lay_pop` stays one
bit per layer per beat, and the layer front end counts beats where it counted
pixels. The blend becomes `P` copies of the same cascade sharing one set of
control signals.

That last point is the one to internalise when implementing it: **lanes share
control, not data.** Valid, SOF, EOL, EOF, which layer is popped, and each
layer's alpha are per beat. Only the pixel and the accumulator are per lane.

```systemverilog
// per beat                            // per lane
v_q[k], sof_q[k], eol_q[k], eof_q[k]   acc_q[k][j]
popf_q[i], alphaf_q[i], asrcf_q[i]     lrgb_q[k][i][j], la_q[k][i][j]
```

### 9.3 What changes, concretely

| | |
|---|---|
| Beat width | `P_PPC * 32` on every stream |
| Raster | counts **beats** across the canvas: `out_bx` runs `0 .. W/P - 1` |
| Window | compared in beats: `act_bx = x >> log2(P)`, `act_bxe = (x + w) >> log2(P)` |
| Layer FSM | counts beats per line — `cfg_w_beats`, not `cfg_width` |
| FIFO | depth in **beats** — 2048×32 at P=1 is 256×256 at P=8, the same bits (but not the same BRAMs, see §9.5) |
| Blend | `P` independent cascades, `N` stages each |
| Validation | `(x \| w \| canvas_width) & (P-1)` must be zero, else `ERR.CFG` |
| `CAPS.PPC` | reports `P`, so software can round before writing |

Every pixels-to-beats conversion is a shift, which is why `P_PPC` is restricted
to powers of two.

### 9.5 The layer buffer stops being depth-limited, and it costs you

The buffer holds the same number of **bits** at every `P_PPC` — one layer line
of 2048 pixels is 65536 bits whether that is 2048×32 or 256×256. It is tempting
to conclude the block RAM count is constant. It is not, and the measured numbers
say so:

| `P_PPC` | buffer per layer | RAMB36 total |
|---|---|---|
| 1 | 2048 × 32 | 8 |
| 2 | 1024 × 64 | 8 |
| 4 | 512 × 128 | 8 |
| 8 | 256 × 256 | **16** |

A RAMB36 is at most **72 bits wide** (SDP; 36 in TDP). Below that the memory is
*depth*-limited and you pay for the bits. Above it the memory is *width*-limited:
at `P_PPC = 8` each layer needs four RAMB36 side by side just to make 256 bits,
and each of them is only a quarter full.

Two consequences worth knowing before you size anything:

- **Depth above the width-limited threshold is free.** At `P_PPC = 8` those four
  RAMB36 give 512 beats whether you ask for 256 or not. Asking for 256 buys a
  4096-pixel line buffer at no cost over a 2048-pixel one — so take it.
- **If BRAM is tight**, that is the knob. `P_PPC = 4` is the last width that
  fits a 72-bit port cleanly, and it is where the bits-per-BRAM efficiency
  peaks for this geometry.

### 9.4 Traps specific to this

1. **Reject, don't round.** Snapping a misaligned window to a beat boundary puts
   the picture up to `P-1` pixels from where the register says. That difference
   is invisible in the register file and maddening on a screen.
2. **The cross-check between the map and the build.** `CAPS.PPC` is a constant
   in the generated map, so a build whose `P_PPC` differs reports an alignment
   granularity it does not enforce — software then computes a layout the
   hardware rejects. The CSR wrapper fails elaboration on the mismatch.
3. **Beat counts vs pixel counts in the testbench.** Every "send `n` beats" and
   "assert TLAST at index `k`" in the bench is in beats, while widths are in
   pixels. Writing one where the other is meant does not fail loudly: at `P = 4`
   the starve test's partial frame became two *complete* frames and the layer
   never starved, so the test passed for the wrong reason until the re-arm
   check caught it.
4. **Fixed cycle waits.** A wait of `canvas_w * canvas_h` cycles covers `P`
   times as many output frames once a beat carries `P` pixels. Scale waits by
   the output frame in beats, or poll the status bit you actually care about.

---

## 10. Lifting the alignment constraint

Not implemented here. This is the design if you want arbitrary `x`, and it is
the most interesting part of a multi-pixel mixer.

### 10.1 The problem

Layer pixel `k` lands at canvas `x = lay_x + k`, so it belongs in lane
`(lay_x + k) mod P` of beat `(lay_x + k) / P`. Define

```
phi = lay_x mod P
```

If `phi != 0` the layer's beats are **offset** from the output's: one output
beat is built from the top `P - phi` pixels of one layer beat and the bottom
`phi` of the next.

### 10.2 The insight that makes it affordable

`phi` is **constant for the whole frame** — it is latched with the rest of the
geometry. So this is not a per-beat variable barrel shift; it is a fixed
rotation whose select changes only at a frame boundary.

Per layer you need:

- a **residue register** holding the `P - phi` pixels left over from the
  previous layer beat;
- a `P`-way select per lane, choosing between the residue and the fresh beat.
  That is a `P:1` mux of 32 bits per lane, not the `2P:1` a general shifter
  would need.

At `P = 8` that is roughly 500 LUTs per layer — real, but an order of magnitude
less than a dynamic crossbar.

### 10.3 What else stops being free

- **Window test becomes per lane.** Lane `j` covers canvas `out_bx*P + j`, so
  each lane needs its own `in_win`. `P` compares per layer per beat.
- **Variable pop.** The number of pixels a layer owes this beat is
  `popcount(in_win_lanes)`, which is `0..P`. The FIFO read side has to pop a
  variable count, so it is no longer a plain FIFO head — it is the alignment
  buffer above.
- **Partial beats on the input.** If `lay_w` is also unconstrained, a layer line
  ends mid-beat and the source must signal how many lanes are valid. That is
  `TKEEP`, and the layer FSM's `geom_bad` check has to count *pixels* from
  `TKEEP` rather than beats.
- **Starve accounting.** Starve is now per lane, or conservatively per beat if
  any wanted lane is missing.

### 10.4 Suggested order if you do it

1. Keep `lay_w` beat-aligned; relax only `lay_x`. That gets you arbitrary
   horizontal placement without `TKEEP` anywhere.
2. Per-lane `in_win` first, with `phi` forced to 0 — proves the window logic
   before the alignment buffer exists.
3. Then the residue register and the fixed-`phi` select.
4. Only then relax `lay_w` and take on `TKEEP`.

Steps 1–3 give you everything most layouts need. Step 4 is a lot of work for the
last `P-1` pixels of width.

---

## 11. Results

Out-of-context, `xc7z045ffg900-2`, N = 4, constrained at **148.5 MHz**
(`syn/syn.tcl`, 6.734 ns) — the 1080p60 pixel clock, so the numbers cover the
harder of the two modes this was built for. Layer buffers hold 2048 pixels at
every `P_PPC`, so the beat depth falls as the width rises.

```bash
vivado -mode batch -log s.log -journal s.jou -source syn.tcl -tclargs 4   # PPC 4
```

| `P_PPC` | WNS | WHS | LUT | FF | RAMB36 | DSP |
|---|---|---|---|---|---|---|
| 1 | +0.282 ns | +0.057 ns | 4021 | 2055 | 8 | 0 |
| 2 | +0.371 ns | +0.088 ns | 6434 | 2425 | 8 | 0 |
| 4 | +0.257 ns | +0.070 ns | 11043 | 3244 | 8 | 0 |
| 8 | +0.269 ns | +0.068 ns | 20201 | 4942 | 16 | 0 |

**Timing is flat across all four.** That is the claim §9 makes — the cascade is
replicated per lane, not made deeper, so the critical path is the same one at
every width. Slack varies by 0.11 ns across a 4× range of area, which is
placement noise rather than a trend.

LUTs run a little under linear: ×1.6 for `P_PPC` 2, ×2.7 for 4, ×5.0 for 8. The
sub-linearity is the shared control — one raster, one set of window compares,
one register file, regardless of width.

Zero DSPs at every width. The blend is `div255`, a pair of adds and shifts
(§5.2), and the `× 255` multiplies map to LUT logic at this size.

RAMB36 is flat to `P_PPC = 4` and then doubles; §9.5 is why, and it is not what
you would guess from the bit count.

**The mixer closes 1080p60 on its own.** That is worth stating precisely,
because in the ZC706 design it is wrapped by `hdmi_mixer_src` — four pattern
generators plus this block — and *that* wrapper misses 148.5 MHz by 1.725 ns.
The failing path there starts in a generator's pattern logic, not in the mixer,
and is roughly two-thirds routing. Do not read the wrapper's number as this
block's.
