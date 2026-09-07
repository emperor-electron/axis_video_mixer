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

### 1.2 Explicit non-goals

- **Scaling.** A scaler is a different block with different arithmetic and its
  own line buffers. Keeping it out is what lets a layer be a plain FIFO.
- **Clock domain crossing.** Put an AXI4-Stream clock converter in front of a
  layer if it needs one. Absorbing it here would mean `N` asynchronous FIFOs
  whether or not anyone needed them.
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

// ---- consuming a layer ------------------------------------------------
in_win[i] = act_en[i] && out_x >= x[i] && out_x < x[i]+w[i]
                      && out_y >= y[i] && out_y < y[i]+h[i];
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

## 9. Results

Out-of-context, `xc7z045ffg900-2`, N = 4, 2048-deep layer buffers, constrained
at **148.5 MHz** (`syn/syn.tcl`, 6.734 ns) — the 1080p60 pixel clock, so the
numbers cover the harder of the two modes this was built for.

| | |
|---|---|
| WNS | **+0.479 ns** |
| WHS | +0.082 ns |
| Total LUTs | 4028 |
| FFs | 2125 |
| RAMB36 | 8 |
| DSP | 0 |

Per layer that is ~280 LUTs and 2 BRAM36, of which the FIFO is ~220 LUTs; the
core outside the layers is ~2000 LUTs, which is the cascade and the window
comparisons. Zero DSPs — the blend is `div255`, a pair of adds and shifts (§5.2),
and the `× 255` multiplies map to LUT logic at this width.

**The mixer closes 1080p60 on its own.** That is worth stating precisely,
because in the ZC706 design it is wrapped by `hdmi_mixer_src` — four pattern
generators plus this block — and *that* wrapper misses 148.5 MHz by 1.725 ns.
The failing path there starts in a generator's pattern logic, not in the mixer,
and is roughly two-thirds routing. Do not read the wrapper's number as this
block's.
