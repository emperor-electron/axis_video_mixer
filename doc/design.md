# AXI4-Stream video mixer — design document

A specification and a set of design decisions, written so the block can be
re-implemented from scratch rather than read. Diagrams are in
[`mixer_design.drawio`](mixer_design.drawio) — five tabs, uncompressed XML so
it diffs.

Sections 3 and 4 are the ones worth reading slowly. Everything else is
bookkeeping by comparison.

---

## 1. What it does

Composites up to eight RGBA video streams into one, under AXI4-Lite control,
for picture-in-picture and tiled layouts.

```
N x  AXI4-Stream RGBA  ──►  mixer  ──►  1 x AXI4-Stream RGB or RGBA
   (N <= 8)                   ▲
                          AXI4-Lite
```

Video AXI4-Stream conventions throughout (UG934): `TUSER` = SOF on the first
pixel of a frame, `TLAST` = EOL on the last pixel of every line, `P_PPC` pixels
per beat.

A pixel is four colour components of `P_CH_W` bits each — 8, 10, 12 or 16 —
packed `{R, G, B, A}` with R in the most significant. §12 is that parameter;
§11 is the other thing the ports say about themselves, which is that each
stream's signals are named ports rather than slices of a packed bus.

### 1.1 Requirements

Numbered so the verification plan in §8 can cite them.

| | Requirement |
|---|---|
| **R1** | Composite `N` layers, `1 <= N <= 8`, over a solid background using Porter-Duff *over* with straight (non-premultiplied) alpha. |
| **R2** | Each layer occupies an arbitrary rectangle of the canvas, set at run time by `Ln_POS` and `Ln_SIZE`. |
| **R3** | No scaling. A layer's stream must arrive at exactly the size its `Ln_SIZE` declares. |
| **R4** | Per-layer alpha from a register, optionally multiplied by the pixel's own alpha channel. |
| **R5** | Z-order is fixed by port index: layer 0 nearest the background, highest-numbered on top. |
| **R6** | **The output stream never stalls waiting on an input.** A layer with no pixel available when its window opens is dropped for the remainder of that frame. |
| **R7** | Configuration changes take effect at an output frame boundary, never mid-frame. |
| **R8** | Every fault is latched, attributable to a layer, and clearable: `CFG`, `STARVE`, `GEOM`, `SRC_STALL`, `OUT_STALL`. |
| **R9** | Single clock domain — every input stream, the output, and the AXI4-Lite port. |
| **R10** | `N` is a parameter. One register map covers every `N`: it is generated for the maximum, and `CAPS.NUM_LAYERS` reports what was built. |
| **R11** | `P_PPC` ∈ {1, 2, 4, 8} pixels per beat, on **every** stream — all `N` inputs and the output. Lane 0 in the least significant bits. |
| **R12** | Horizontal geometry — `CANVAS.WIDTH`, every `Ln_POS.X`, every `Ln_SIZE.WIDTH` — must be a multiple of `P_PPC`. A value that is not is **rejected** with `ERR.CFG`, never rounded. `CAPS.PPC` reports the granularity. |
| **R13** | Every signal of every input stream is its own named port. Nothing is packed across streams, and all eight stream port sets exist in every build. |
| **R14** | `P_CH_W` ∈ {8, 10, 12, 16} bits per colour component, on **every** stream. The blend divides by `2**P_CH_W - 1`, so an alpha of full scale returns the top colour exactly at every width. `CAPS.CH_W` reports it. |

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
- **More than eight streams.** The limit is the port list, not the datapath —
  §11.3.
- **A component width that is not 8, 10, 12 or 16.** The blend identity is
  proved exact at those four and nowhere else, and a width that is not a whole
  number of nibbles makes every software-side pixel unpack a shift-and-mask
  with no byte alignment to fall back on. §12.1.
- **Deep alpha and background registers.** `Ln_CTRL.ALPHA` and
  `BACKGROUND.RGB` stay 8 bits per component at every `P_CH_W` and are expanded
  in the datapath. §12.3.
- **Per-interface component width**, for the same reason as per-interface
  `P_PPC`.
- **Colour space conversion** and chroma subsampling.

---

## 2. Structure

Tab 1 of the drawio file. Three pieces:

- `axis_mixer_layer` × N — SOF-alignment FSM plus a FWFT FIFO. Owns the input
  handshake.
- `axis_video_mixer_core` — output raster, window comparison, frame-boundary
  latch, blend cascade, error aggregation.
- `axis_video_mixer_csr` — the generated register block plus an adapter that
  turns corsair's flat per-layer ports into arrays, and ties off the layer
  blocks the build does not implement.

`axis_video_mixer` itself is wiring and nothing else: it gathers the eight sets
of named stream ports into the arrays the datapath indexes, and connects the
two blocks above. §11.

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

### 5.2 `div_max`, not `>> C`

An alpha at full scale must return the top colour exactly. `>> C` returns
`(MAX-1)/MAX` of it, and over a cascade that error accumulates until a stack of
nominally opaque layers visibly darkens.

```systemverilog
MAX = 2**C - 1
div_max(C, v) = (t + (t >> C)) >> C,  where t = v + 2**(C-1)
```

Two adds and two shifts, no divider, no table. Exact against
`round(v / MAX)` for every `v` in `0 .. MAX*MAX` — verify this exhaustively
before you trust it; that range is the full span the blend can produce, because
`a + (MAX - a) = MAX` caps the numerator at `MAX × MAX`.

At `C = 8` that is the familiar `(t + (t >> 8)) >> 8` with `t = v + 128`. §12.2
is why it generalises and §12.1 is why only four widths are admitted.

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
| 1 | `div_max` / `blend_ch` / `blend_rgb` as pure functions | exhaustively checked against `round(v/MAX)` over `0..MAX*MAX` in whatever language is convenient, at every component width you intend to support — do this before any RTL |
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

// ---- arithmetic (MAX = 2**C - 1, C = P_CH_W) --------------------------
div_max(C,v)       = (t + (t>>C)) >> C,  t = v + 2**(C-1)
blend_ch(C,top,bot,a) = div_max(C, top*a + bot*(MAX-a))
effective_alpha    = src_sel ? global_a : mul_max(C, pixel_a, global_a)
ch_up(C,v8)        = (v8 << (C-8)) | (v8 >> (16-C))   // 8-bit regs -> C bits
```

---

## 6. Registers

Full map in [`axis_video_mixer_regs.md`](axis_video_mixer_regs.md). Generated by
`regs/gen_regs.py` for the maximum layer count, with `CAPS` reporting what was
actually built — §11.4 is why it is that way round.

Global block at `0x00`, per-layer blocks at `0x40 + 0x10n` for `n` = 0..7, so
adding a global register never renumbers a layer register. Software reads
`CAPS.NUM_LAYERS` and stops there; the blocks above it are writable and
readable and connected to nothing.

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

Two suites, answering different questions. `cd tb && make regress` checks that
the block produces the right picture from realistic stimulus;
`make -C formal` checks that a short list of structural claims hold under
*every* stimulus. Neither subsumes the other, and §8.2 is about where the line
falls.

### 8.1 Simulation

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

`PPC` and `CH_W` are swept separately rather than crossed — `make ppc-sweep`
and `make ch-sweep`, four regressions each. Crossing them would be sixteen
regressions to find a fault either sweep finds on its own: `PPC` changes how
many pixels share a beat and `CH_W` changes how wide a pixel is, and no
mechanism in the block couples them. `make NUM_LAYERS=8 regress` is the third
axis, and none of the three needs the register map regenerated.

Two properties of the bench worth copying:

- **The golden blend is written independently** — integer division where the RTL
  uses the shift-and-add identity, and its own copy of the 8-to-`C` register
  expansion. Sharing the functions would make the model agree with the DUT by
  construction, which is the agreement the scoreboard exists to test.
- **The stimulus pattern reduces to the old one at `C = 8`.** A component is
  the original 8-bit pattern expanded to `P_CH_W`, xor a second pattern in the
  bits below bit 8 — and that second pattern is taken modulo `2**(C-8)`, which
  is 1 at `C = 8`. So the 8-bit regression is bit-for-bit the stimulus it
  always was, and a wider build exercises the precision it was built for
  instead of running an 8-bit picture down a wider bus.
- **The scoreboard recomputes each layer's pixels** from a shared content
  function rather than observing the input streams. That is what lets it predict
  a composite without subscribing to N input monitors and re-deriving their
  framing — and it is the stronger check, because it verifies the pixel at
  canvas `(x, y)` is the one the covering layer should have produced *at its own
  coordinate*.

Mutation-test the bench before believing it. Reverse the hash word order,
transpose a window, swap two layers — if the suite still passes, it is not
testing what you think.

### 8.2 Formal

`make -C formal`. Five proofs in [`formal/`](../formal), documented in full in
[`formal.md`](formal.md) — including what is bounded rather than proved, where
every assumption is discharged, and what is not covered.

Three things here are the wrong shape for directed tests, and they are why the
flow exists:

| | |
|---|---|
| **R6** | "The output never stalls waiting on an input" is a claim about all possible input behaviour. `mixer_starve_test` stops one source at one moment; `a_raster_advances` says no combination of starving, faulting and backpressured layers can stop the raster, and proves it by induction. |
| **§4** | Alignment is a counter invariant, which is what induction is good at. A one-beat offset is not a crash — it is a picture that looks almost right, and it survives a scoreboard built from the same assumption as the RTL. |
| **R12** | Rejection logic is only ever exercised by tests that deliberately write bad values. The solver writes every bad value there is, every cycle; the claim proved is not "the validation looks right" but "no illegal window can become active, by any path". |
| **R13** | The gather from the eight sets of named stream ports into the datapath's arrays is hand-written, eight assigns per field, and a transposed index there is two windows in the right places showing the wrong contents. A bring-up test with one source cannot see it, and a bench with eight similar sources cannot either. |

Two more fall out cheaply. The blend arithmetic (§5.2) is combinational logic,
where formal was always the right tool — `div_max`'s "verified exhaustively" is
now a proof at all four component widths, and it extends to `blend_ch` and
`blend_rgb`, whose input spaces are 2⁴⁸ and larger and were never exhausted.
And the AXI4-Lite port is generated code nobody reads, where a protocol
violation wedges a processor bus rather than producing a wrong picture.

What the proofs deliberately leave to the bench: **the picture**. No property
says the composite is the right image for a given set of layer contents, except
in the all-transparent case. The independently written golden blend is the right
tool for that, and the two suites divide along exactly that line — the bench
checks values from realistic stimulus, the proofs check the arithmetic
identities it cannot exhaust and the structural claims it cannot generalise.

One finding worth carrying back into the design record: `axis_video_mixer_csr`
keeps a single captured write address, so it is correct for **one outstanding
AXI4-Lite write at a time**. That is safe behind any ordinary master or
interconnect and unsafe behind one that pipelines. §7 of `formal.md` has it.

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

## 11. Eight streams, named ports

### 11.1 Why one port per signal

Every signal of every input stream is its own named port: `s_axis0_tvalid`,
`s_axis0_tready`, `s_axis0_tdata`, `s_axis0_tuser`, `s_axis0_tlast`, and the
same five for streams 1 through 7. Nothing is packed across streams (R13).

The block used to flatten them — one `P_NUM_LAYERS`-bit vector per handshake
signal and one `P_NUM_LAYERS * P_BEAT_W`-bit vector for `TDATA` — on the
grounds that unpacked array ports do not survive an IP-XACT or block design
boundary. They do not, but a packed vector is the wrong fix, because the thing
that has to survive the boundary is not the *array*, it is the *interface*.

Interface inference in Vivado's IP packager and in a block design keys on the
port name. Given `s_axis3_tdata`, `s_axis3_tvalid`, `s_axis3_tready`,
`s_axis3_tuser` and `s_axis3_tlast` it recognises an AXI4-Stream slave called
`s_axis3` with no manual mapping at all, and the connection automation will
draw it. Given one 128-bit `s_axis_tdata` it recognises nothing: the integrator
splits the bus by hand on the far side, and every integrator splits it slightly
differently. The packing also has to be undone by whatever produced the four
streams, which usually means four slices written out by hand there too — the
flattening saved nobody anything and cost a place for an off-by-one to live.

So the arrays stay, but they stay *inside*. `axis_video_mixer` gathers the
named ports into them in one assign per port, and that gather is the only thing
in the file that is not an instantiation.

### 11.2 All eight exist in every build

`P_NUM_LAYERS` is 1 to 8 and says how many streams are wired to the datapath.
The ports for all eight exist regardless, because a port list cannot be
generated — there is no construct that conditionally declares a port, and
emitting the module from a script to get one would make the RTL unreadable for
a gain of some wires.

An unimplemented stream has its inputs ignored and its `TREADY` held **low**.
Low rather than high, deliberately: high would consume beats and discard them,
which looks exactly like a working connection and produces a black layer, while
low stalls the producer in the first second of bring-up. A port that does not
exist in this build should not accept data.

Software is told the real count by `CAPS.NUM_LAYERS` and should size its layer
loop from it. The registers for the unimplemented layers are still there and
still read back what was written to them — that is corsair's storage, and
leaving it connected to nothing is what makes those blocks harmless rather than
absent — but their `Ln_STATUS` reads as a layer that is disabled and has never
seen a stream, which is what it is.

### 11.3 Why eight

The datapath does not care. `P_NUM_LAYERS` sets the depth of the blend cascade
and the number of layer front ends, and nothing in either has a limit short of
what will fit.

Eight is the port list and the register map. `ERR_LAYER` has one bit per layer
in a 32-bit register, so the map could carry far more; the limit is that the
map is generated for the maximum and every layer block costs four registers and
a run of `corsair`-generated decode. Eight layer blocks is 0x40 through 0xBF,
which keeps the whole map inside one 4 KiB page with room to spare, and eight
is already more than any picture-in-picture layout has wanted here.

Raising it is three edits in one place — `MAX_LAYERS` in the package,
`MAX_LAYERS` in `gen_regs.py`, and the port list — plus a regenerated map. The
cascade's latency is `2 + N` cycles, so the only thing that gets worse is how
long a frame takes to come out.

### 11.4 What the register map had to change

Nothing about the map's layout, and one thing about where its contents come
from.

The map used to be generated for the layer count a build instantiated, and the
adapter refused to elaborate against any other count. That made `N` a
regeneration rather than a parameter, and it made `CAPS` a set of baked reset
values that could only be right by having been regenerated. Two maps for two
builds also meant two C headers and two copies of the documentation.

Now the map is generated once, for `MAX_LAYERS`, and every field of `CAPS` is a
hardware input driven from the parameter it describes — layer count, FIFO
depth, output format, component width, pixels per clock. The adapter accepts
any `P_NUM_LAYERS` up to the map's size and ties off the rest. One map
describes every build, and a build and its map cannot disagree about what was
built because the map no longer holds an opinion.

That is also what took the register regeneration out of the `P_PPC` and
`P_CH_W` story: `make -C tb ppc-sweep` and `make -C tb ch-sweep` are now plain
regressions instead of rewriting checked-in generated files and putting them
back afterwards.

It is not free. The map carries eight layer blocks whatever the build
instantiates, so a four-layer build pays for four sets of registers it never
reads: 74 bits each, 296 flip-flops, about 0.3% of the block's flops (§13).
Writable, readable, connected to nothing. The alternative is a map per layer
count, and with it a C header per layer count, a copy of the register
documentation per layer count, and an elaboration-time check whose whole job is
to catch the moment they stop matching.

---

## 12. Colour component width

### 12.1 Which widths, and why only those

`P_CH_W` ∈ {8, 10, 12, 16} bits per colour component, on every stream in and
out (R14). A pixel is four of those, so 32, 40, 48 or 64 bits, packed
`{R, G, B, A}` with R in the most significant.

8 is RGBA8, what the block started as. 10 and 12 are the deep-colour depths
HDMI and DisplayPort carry, and the ones a camera pipeline tends to arrive in.
16 is what a linear-light or HDR intermediate wants — a 16-bit component gives
enough headroom that a cascade of blends does not quantise visibly in the
shadows.

The gaps are deliberate rather than for want of effort. The blend identity in
§12.2 is **proved** exact at those four widths and nowhere else, so an
unlisted width would composite with a rounding error that grows down the
cascade. And a width that is not a whole number of nibbles makes every
software-side pixel unpack a shift-and-mask with no byte alignment to fall back
on, for a bus that is then an awkward width as well.

One property of the four that is worth knowing because the testbench leans on
it: `4 * P_CH_W` is a multiple of 8 at all of them, so a pixel is a whole
number of bytes — 4, 5, 6 or 8 — and lane `j` of a beat still starts on a byte
boundary even though the components inside it do not.

### 12.2 The divide generalises; the shift does not

§5.2 is the argument for dividing by 255 rather than shifting by 8. It is the
same argument at any width, with the numbers moved: an alpha of full scale must
return the top colour exactly, and `>> C` returns `(2**C - 2)/(2**C - 1)` of
it. At 16 bits that is a smaller error per stage than at 8 — and it still
accumulates, and it is still wrong in the one case anybody checks.

So the divisor is `MAX = 2**C - 1`, and the identity is the 8-bit one read at a
general width:

```
div_max(C, v) = (t + (t >> C)) >> C      where t = v + 2**(C-1)
```

It holds for the same reason: `1/(2**C - 1)` is
`2**-C * (1 + 2**-C + 2**-2C + ...)`, and over the range a blend can produce
the first two terms plus the rounding offset are already exact.

"Already exact" is the part worth checking rather than believing, and it was
checked twice. Exhaustively, against `round(v / MAX)` over the full
`0 .. MAX*MAX` at all four widths — four billion values at `C = 16` — and in
formal, in `formal/tops/fv_blend.sv`, which proves it as the pair of
multiplicative bounds that define integer division. `doc/formal.md` §4 is what
that proof covers and what it does not.

The numerator peaks at `MAX * MAX`, because `a` and `MAX - a` sum to exactly
`MAX`. At `C = 16` that is `65535 * 65535`, which needs all 32 bits of its
container and not one more.

### 12.3 `ALPHA` and `BACKGROUND` stay 8 bits

`Ln_CTRL.ALPHA` is 8 bits and `BACKGROUND.RGB` is 24, at every `P_CH_W`. Both
are expanded to the component width in the datapath as they are latched.

The first reason is the map. Widening `ALPHA` would collide with `ALPHA_SRC` in
the same register and widening `BACKGROUND` would need a second one, so a
16-bit build and an 8-bit build would not share a register map — and §11.4 is
the whole argument for why one map describing every build is worth more than
this.

The second is that neither field is a sample. Alpha is a fraction and a
background is a colour someone picked; eight bits of each is not the thing deep
colour was wanted for. What it was wanted for is the pixels, and those arrive
at full width and are blended at full width.

The expansion is bit replication — `(v << (C-8)) | (v >> (16-C))`, the standard
8-to-`C` deep-colour expansion. `0x00` maps to 0 and `0xFF` maps to full scale,
both exactly, so "transparent" and "opaque" survive it; in between it is
monotone and within one LSB of the exact rational scaling `v * MAX / 255`.
Within one LSB rather than exact because `v * MAX / 255` is not an integer at
`C = 10` or 12 — no bit pattern can be exact there, which is the honest reason
and not a shortcut. All three properties are proved in `fv_blend.sv`.

At `C = 8` the expansion is `(v << 0) | (v >> 8)`, which is `v`. An 8-bit build
gets the hardware it had before.

### 12.4 What it costs

The blend cascade is where it lands. Every stage carries an accumulator and an
operand of `3 * P_CH_W` bits per layer per lane, and every stage is a
`C x C`-bit multiply per component — so the arithmetic grows faster than
linearly in `C` while the control does not grow at all.

The layer buffers grow linearly: a 2048-pixel line buffer is 2048 × 32 at
`C = 8` and 2048 × 64 at `C = 16`, twice the block RAM for the same number of
pixels. §9.5 is the related trap for `P_PPC`, and it applies here too — the
depth is in beats and what matters is the product.

The raster, the window compares, the frame latch, the flow control and the
error logic are all untouched. None of them looks inside a pixel, which is why
`axis_mixer_layer` and `axis_mixer_fifo` needed nothing but a wider beat.

### 12.5 Traps specific to this

- **A package cannot be parameterised.** The blend functions live in
  `axis_video_mixer_pkg` because the testbench's golden model and the RTL have
  to be able to disagree, and a SystemVerilog package takes no parameters. The
  functions therefore take the width as their first argument and work in
  containers sized for the widest supported component; callers pass a parameter,
  so it folds to a constant at elaboration and nothing variable survives into
  the netlist. The convention is that a value arrives right-aligned and
  zero-extended, and the accessors mask on the way out.
- **`p[4*ch_w-1 -: ch_w]` is illegal** when `ch_w` is a function argument: an
  indexed part-select needs a constant width. The accessors are shift-and-mask
  for that reason, not for taste.
- **Check the arithmetic container, not the declared width.** The first version
  of the formal range guard compared the numerator after narrowing it to the
  width the bounds were evaluated in, which let a value far outside the proved
  range pass the guard with its top bits truncated away and then reach
  `div_max` in full. The counterexample was real and the property was the thing
  that was wrong. `doc/formal.md` §4.
- **The register fields are not the datapath's widths.** `lay_alpha` is 8 bits
  all the way from the register block to the frame latch and `P_CH_W` bits
  after it. Mixing the two up gives a layer that is almost transparent at
  `C = 16` and correct at `C = 8`, which is the worst possible place for the
  bug to hide.

---

## 13. Results

Out-of-context, `xc7z045ffg900-2`, N = 4, `P_CH_W = 8`, constrained at
**148.5 MHz** (`syn/syn.tcl`, 6.734 ns) — the 1080p60 pixel clock, so the
numbers cover the harder of the two modes this was built for. Layer buffers hold
2048 pixels at every `P_PPC`, so the beat depth falls as the width rises.

These were measured before `P_CH_W` and the named stream ports existed, and
they stand for the configuration they name: four layers, 8-bit components.

The datapath for that configuration is unchanged, which was checked rather than
assumed: synthesising the old and the new RTL at `N = 4`, `P_PPC = 1`,
`P_CH_W = 8` gives the same flip-flop count in the datapath and combinational
totals within 0.3%. At `C = 8` the expansion in §12.3 folds to a wire and the
port gather is wires, so there is nothing for it to cost.

The register file does cost something, and it is worth naming: the map is now
generated for eight layer blocks whatever the build instantiates (§11.4), so a
four-layer build carries **296 extra flip-flops** — four unused blocks × 74
register bits — which is exactly the difference the two synthesis runs showed.
That is the price of one map describing every build, and at roughly 0.3% of this
block's flops it is the right way round.

**Nothing here has been measured at eight layers or at a wider component**, and
§12.4 is the shape to expect rather than a number to quote.

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

Zero DSPs at every width. The blend is `div_max`, a pair of adds and shifts
(§5.2), and the `× MAX` multiplies map to LUT logic at this size. That is a
statement about `P_CH_W = 8`; a 16-bit component makes every one of those
multiplies four times the work, and DSP inference is the first thing to try if
it gets tight.

RAMB36 is flat to `P_PPC = 4` and then doubles; §9.5 is why, and it is not what
you would guess from the bit count.

**The mixer closes 1080p60 on its own.** That is worth stating precisely,
because in the ZC706 design it is wrapped by `hdmi_mixer_src` — four pattern
generators plus this block — and *that* wrapper misses 148.5 MHz by 1.725 ns.
The failing path there starts in a generator's pattern logic, not in the mixer,
and is roughly two-thirds routing. Do not read the wrapper's number as this
block's.
