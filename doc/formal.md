# Formal verification

What is proved about this block, how, and — the part worth reading — what is
*not* proved and why not.

The scripts live in [`formal/`](../formal). `make -C formal` runs everything;
the table in §9 is what it prints when it passes.

This is a companion to §8 of [`design.md`](design.md), not a replacement for
it. The UVM suite and the proofs answer different questions and neither
subsumes the other: the bench checks that the block produces the right picture
from realistic stimulus, and the proofs check that a short list of structural
claims hold under *every* stimulus, including the ones nobody thought to write.

---

## 1. Why formal, on this block

Three things here are worth proving rather than sampling.

**R6, the load-bearing requirement.** "The output stream never stalls waiting
on an input" is a claim about all possible input behaviour. `mixer_starve_test`
stops one source at one moment and confirms the output keeps going; that is
evidence, and it is the wrong shape of evidence for a universal claim. The
property wanted is that *no* combination of starving, faulting and
backpressured layers can stop the raster, and there is no number of directed
tests that gets there.

**Alignment, the bug you will write.** §4 of the design document is a whole
chapter on it: nothing links a layer's stream to the output raster except a
count, and the mixer cannot tell a correct pixel from one that is a line late.
A one-beat offset is not a crash. It is a picture that looks almost right, and
it survives a scoreboard that was built from the same assumption as the RTL.
Counter invariants are exactly what induction is good at.

**Configuration rejection.** At `P_PPC > 1` every horizontal geometry register
must be a multiple of `P_PPC`, and the block must *reject* a value that is not
rather than round it (R12). Rejection logic is only ever exercised by tests
that deliberately write bad values, so it is tested by however many bad values
someone thought of. Here the solver writes every bad value there is, every
cycle, in any combination — and the claim proved is not "the validation logic
looks right" but "no illegal window can become active, by any path".

Two more fall out cheaply once the flow exists. The blend arithmetic
(§4) is pure combinational logic over a small input space, where formal is
simply the right tool and simulation never was. And the AXI4-Lite control port
(§7) is generated code that nobody reviews line by line, where a protocol
violation wedges a processor bus rather than producing a wrong picture.

---

## 2. Tools

| | |
|---|---|
| Engine | SymbiYosys (`sby`), BMC and k-induction |
| Front end | **yosys-slang** (`yosys -m slang`) |
| Solver | boolector, via `yosys-smtbmc` |

All three ship in the [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build).
`make -C formal tools` checks for them and says what is missing.

**yosys-slang is not optional.** Yosys's built-in Verilog frontend cannot read
this RTL: unpacked array ports, packages with functions, `import` in the module
header, and multi-dimensional unpacked arrays are all used, and all beyond it.
The slang frontend elaborates the whole design, testbench-grade SystemVerilog
included, which is what makes a formal flow possible here at all without an
`sv2v` step that would obscure every line number.

What it costs is SVA. yosys-slang implements immediate assertions and
boolean-only concurrent ones; the temporal operators are not there:

```systemverilog
// None of these elaborate: "encountered unsupported SVA feature"
assert property (@(posedge clk) disable iff (!rst_n) a |-> b);
assert property (@(posedge clk) a |=> b);
assert property (@(posedge clk) b |-> $past(a));
```

`$past`, `$stable`, `$rose`, `$anyconst`, `$anyseq` and `$initstate` are all
absent as well. So every property in this suite is written as a **procedural
immediate assertion sampled at the clock edge**, with history kept in explicit
registers:

```systemverilog
logic a_d;
always_ff @(posedge clk) a_d <= a;
always_ff @(posedge clk) if (rst_n) a_follows : assert (!a_d || b);
```

This is more of a feature than it sounds, and not only because it is forced.
The RTL's own simulation assertions are written the same way and say why —
`axis_mixer_fifo.sv` documents an `assert property` that fired thousands of
times under XSIM on intermediate deltas, before the combinational network had
resettled, while the equivalent check in an `always_ff` was clean. Sampling at
the edge checks what the hardware samples. The suite and the RTL end up in one
idiom rather than two.

---

## 3. Three idioms this suite leans on

Small things, but they appear everywhere below and are worth naming once.

### `$anyconst`, without `$anyconst`

A register that holds itself, has no reset and no initial value:

```systemverilog
logic [3:0] fv_k;
always_ff @(posedge clk) fv_k <= fv_k;
```

Formal leaves an uninitialised register's value unconstrained, and this one
never changes, so `fv_k` is an arbitrary constant. Proving a property for an
arbitrary index proves it for every index — which is what lets the FIFO's
storage be checked with one shadow register instead of a model of the whole
memory.

### A history-valid guard

Delayed copies have no reset either, so in the first state of a BMC run — and
in *every* start state of an induction step — they hold history that never
happened. Every property that reads one is gated:

```systemverilog
logic fv_started = 1'b0;
always_ff @(posedge clk) fv_started <= 1'b1;
```

The first version of `fv_fifo_props.sv` omitted this and failed instantly on a
fabricated `wr_fire_d`. Worth knowing because the counterexample looks like a
real pointer bug.

### A modelled reset

Reset is held low for exactly one cycle and high afterwards, rather than left
free. This is not tidiness: `wr_ptr`, `rd_ptr` and the layer's beat counters
have no initial value and are only ever cleared by `!rst_n || flush`, so before
a reset the occupancy of an eight-entry FIFO can be nine and `a_no_overrun`
fails — correctly. The invariants of these blocks hold *after* a reset.

Nothing is lost by pinning it. `flush` stays free in the FIFO and layer proofs
and `SOFT_RST` stays free in the core proof, and the RTL folds reset and flush
into the same expression, so a reset arriving mid-stream is still covered.

---

## 4. `axis_video_mixer_pkg` — the blend arithmetic

`sby -f fv_blend.sby` · [`tops/fv_blend.sv`](../formal/tops/fv_blend.sv)

The package comment for `div255` says the identity is "exact against
`round(v / 255)` for every `v` in 0 .. 65025 ... Verified exhaustively." That is
a fine thing to have done and it covers one function. It does not reach
`blend_ch`, `blend_rgb`, `mul255` or `effective_alpha`, whose input spaces are
2²⁴ and larger.

Everything here is combinational and nothing is driven, so the solver picks
every input over its full range and two BMC steps are the entire input space.

| Property | What it rules out |
|---|---|
| `a_div255_floor_lo` / `_hi` | `div255(v)` is exactly `floor((v + 127) / 255)` |
| `a_div255_rounded` | the residual never exceeds half a divisor |
| `a_div255_zero` / `_max` | the two endpoints the cascade depends on |
| `a_blend_alpha0` | alpha 0 returns the accumulator **bit-exactly** — this is what lets the core represent "layer absent" as alpha zero with no special case anywhere |
| `a_blend_alpha255` | alpha 255 returns the top pixel bit-exactly — the one a `>> 8` gets wrong, and the whole reason `div255` exists |
| `a_blend_bounded_lo` / `_hi` | no overshoot: a convex combination stays between its operands. An off-by-one here is a bright or dark fringe on every edge in the picture |
| `a_blend_flat` | blending a value with itself is the identity at every alpha, so a flat region stays flat |
| `a_rgb_per_channel` | no channel crosstalk — invisible in a greyscale test pattern |
| `a_ea_*` | `ALPHA_SRC` decoding, and that a global alpha of zero hides a layer whichever source is selected |

Two things about how these are *written* mattered more than what they say.

**No division appears anywhere.** The obvious statement of exactness is
`div255(v) == (v + 127) / 255`. It is correct and it is unusable: a bit-vector
divide is the one operation these solvers have no good decision procedure for,
and it did not discharge in ten minutes on its own. Stated as the pair of
multiplicative bounds that *define* integer division — `q*255 <= v+127 <
(q+1)*255` — it lands instantly.

**Monotonicity is proved in two pieces.** Asserted directly, "raising the top
pixel never lowers the result" needs two whole `blend_ch` instances in one
query and did not finish in a minute. `blend_ch` is `div255` composed with a
numerator, so it is split at the seam: `a_num_monotone` for the numerator,
`a_div255_monotone` for `div255`, and the conclusion is an ordinary syllogism
rather than something the solver has to be trusted for.

---

## 5. `axis_mixer_fifo`

`sby -f fv_fifo.sby` · [`props/fv_fifo_props.sv`](../formal/props/fv_fifo_props.sv)

Free producer, free consumer, free `flush`. The solver drives `wr_en`, `rd_en`
and `flush` in any combination every cycle — a far harsher environment than the
layer will ever provide, and deliberately so, because this is the one block
reused three times over.

### What is proved, unboundedly

| Property | |
|---|---|
| `a_no_overrun` | occupancy never exceeds `P_DEPTH`. The pointers carry one extra bit precisely so this can hold, and everything else rests on it |
| `a_full_exact` | `full` is exactly "no room", not an approximation |
| `a_full_write_dropped` | a write offered while full is dropped without disturbing the pointers |
| `a_wr_step` / `a_rd_step` | each pointer advances by exactly one per transfer and by nothing else |
| `a_fwft_no_bubble` | first-word fall-through: a word in memory with the prefetch register empty resolves next cycle and cannot persist |
| `a_flush_*` | a flush is complete in one cycle and leaves nothing behind — pointers, prefetch register and reported level all clear |
| `a_level_empty_iff` | `level == 0` means genuinely empty, in memory *and* in the prefetch register |
| `a_shadow_tracks_mem`, `a_storage_readback` | the memory returns at an arbitrary address exactly what was last written there |

### Ordering, and why it is argued rather than asserted

The property one actually wants is that the *i*-th word read is the *i*-th word
written. It is not asserted directly in the proved set, because stating it
needs a pair of running transaction counters and a running counter is precisely
what k-induction cannot reason about: the arbitrary start state can place the
counters anywhere, including one step from wrapping.

So ordering is derived from three facts, each proved unboundedly above:

1. `a_storage_readback` — addressed storage works, at every address.
2. `a_wr_step` / `a_rd_step` — the addresses are consecutive, one at a time.
3. `a_no_overrun` — the window between the pointers never wraps onto itself.
   It covers both directions, because `mem_count` is the modular difference in
   the extra pointer bit: a read pointer one ahead of the write pointer shows
   up not as −1 but as all-ones, far above `P_DEPTH`.

A circular buffer with those three properties delivers in order.

[`props/fv_fifo_order.sv`](../formal/props/fv_fifo_order.sv) then asserts the
end-to-end statement directly — `a_order_data`, plus `a_conservation` saying
everything written is either still inside or has come out — as a **bounded**
cross-check on that argument, run by the `order` task only, from reset, to a
depth its counters cannot wrap in. It is bounded by construction and says so in
its own header.

Its counters are five bits wide and the task's depth is 16. That coupling is
not incidental: at eight bits the task did not get past step 19 in three
minutes, and at five it finishes in eight seconds. Raising the depth means
raising `CNT_W` to match, and the header says so.

### Sizing

`P_DEPTH` is 8, not the 2048 the design ships with. Depth enters these
properties only through the pointer width, and the pointer arithmetic is
identical at 8 and at 2048, while the memory the solver models is 256 times
smaller. The `depth` task re-runs the invariants at 64 to catch anything that
was accidentally specific to a three-bit address.

`P_WIDTH` is 8 rather than 32 for the same reason: every payload bit is a bit
carried through the shadow register, and none of these properties is about how
wide a word is.

---

## 6. `axis_mixer_layer` and `axis_video_mixer_core`

`sby -f fv_layer.sby`, `sby -f fv_core.sby`

The FIFO's properties are **bound to the module**, not written into the RTL and
not instantiated in one place. That is the point of `bind`: the same file is
checked three times over — standalone, inside the layer, and once per layer
inside the core — so a FIFO invariant that only holds because of how the layer
drives it is still proved, and one the layer breaks is caught where it breaks.

`bind` also reaches internal signals, which is where the interesting properties
live. `wr_ptr`, `bt_cnt`, `lay_active`, `act_bxe` are not on any port, and the
port list alone cannot distinguish a layer that is correctly aligned from one
that is a line late.

### The layer

| | |
|---|---|
| `a_no_overflow` | nothing is ever pushed into a full FIFO. This is what makes the FIFO's producer-side assumption true |
| `a_disabled_never_blocks` | a disabled layer drains its source rather than backpressuring it |
| `a_push_tlast_agrees`, `a_push_tuser_agrees` | **nothing is buffered from a beat whose framing disagreed with `SIZE`.** One bad beat buffered is a layer permanently offset |
| `a_wait_sof_zeroed` | both counters are zero whenever the layer is waiting for a SOF |
| `a_bt_in_range`, `a_ln_in_range` | the counters never run past the configured geometry |
| `a_flush_*` | a flush disarms, resynchronises, empties and zeroes the counters, in one cycle |
| `a_geom_err_faithful` | `ERR.GEOM` is reported exactly when the stream disagreed, never as a false alarm |
| `a_disarmed_holds_nothing` | a disarmed layer holds nothing — `armed` is set by the same push that writes the buffer and cleared by the same flush that empties it |
| `a_level_bounded` | `L`*i*`_STATUS.FIFO_LEVEL` never exceeds what the buffer holds |
| `a_watchdog_off`, `a_stall_cnt_cleared` | `SRC_STALL` never fires without real, continuous backpressure |

`a_wait_sof_zeroed` and `a_disarmed_holds_nothing` both deserve a note, because
each looks like a detail and each is an invariant something else rests on.

The first is the one the counter bounds need. On a beat that is not the last of
its line the RTL does not assign `ln_cnt` at all — it carries whatever it held.
What makes that correct is that every path into `WAIT_SOF` zeroes it. Without
this asserted, neither counter bound is inductive, and the induction failure
gives no hint that this is the missing piece.

The second is load bearing in the *core's* proof rather than in the layer's.
There is a legitimate one-cycle window in which the core sees `lay_active` high
and `lay_armed` already low — a geometry fault disarms the layer a cycle before
`lay_geom_err` clears `lay_active` — and what makes `a_pop_needs_armed` hold
across it is that the same fault emptied the buffer, so there is nothing to
pop. Stated as a layer invariant, that becomes something k-induction can use
two levels up. It took an induction counterexample at the core level to find,
and the fix belonged in the layer.

[`props/fv_layer_align.sv`](../formal/props/fv_layer_align.sv) carries the
positional claim: `a_position` says beats buffered since the frame's SOF equals
`ln_cnt * cfg_w_beats + bt_cnt`, and `a_frame_exact` says a frame delivers
exactly `cfg_w_beats * cfg_height` beats. This is the property the block exists
for — the mixer consumes a layer positionally, so an accounting error of one is
a layer skewed for as long as it runs. It is **bounded**: both need a multiply
of two configuration registers, which a 16-bit geometry makes hopeless, so it
runs as BMC over a canvas a few beats by a few lines, deep enough to cover more
than one whole frame.

### The core

The two claims the core's header calls load bearing are both here.

**`a_raster_advances`** — on every enabled, unstalled cycle the raster moves on
by exactly one beat. Nothing in the property's guard mentions a layer, and that
is its whole content: whatever the layers did, starved, faulted or delivered
nothing at all, the raster moved. It is stated as the *exact* next value rather
than "it changed", for two reasons: a 1×1 canvas legitimately never changes its
counters, which the RTL's simulation assertion has to carve out as a special
case, and "it changed" would be satisfied by a raster that advanced *wrongly* —
which is worse than not advancing, because the picture then stays in sync with
nothing and no error is raised. `a_raster_holds` is the converse: it does not
advance when it should not, so a beat is never emitted twice.

`a_output_continuous` in [`tops/fv_core.sv`](../formal/tops/fv_core.sv) is the
positive form of the same claim — once the pipeline has filled, output is
continuous — and is bounded, because it needs a counter.

**`a_active_window_*`** — no window that is misaligned or outside the canvas can
ever become active. This is not a restatement of the validation logic, and the
reason is worth being precise about: `win_ok` is evaluated against the *shadow*
canvas, while these are the *active* window and the *active* canvas, and the two
are latched by the same `frame_latch` under different conditions — the canvas
only updates when `canvas_ok`, the windows always do. Whether a window can end
up active against a canvas it was never checked against is a real question
about that interaction, and this is the answer.

Alongside those:

| | |
|---|---|
| `a_no_pop_empty` | **discharges** the assumption the FIFO and layer proofs both make about whoever pops them |
| `a_pop_xor_starve` | every beat a window asks for is either popped or recorded as a starve, never neither. A silently skipped beat shifts the layer for the rest of the frame with no error raised |
| `a_join_at_boundary` | a layer joins the composite only at a frame boundary — a correctness requirement, not a nicety, for the reason in the core's own header |
| `a_geom_change_flushes` | **discharges** the constant-geometry assumption `fv_layer.sv` makes |
| `a_out_tvalid_held`, `a_out_tuser_held`, `a_out_tlast_held`, `a_tdata_held` | AXI4-Stream: a beat offered and refused is held, unchanged |
| `a_frame_count_steps` | `FRAME_COUNT` only ever counts up, and by one |
| `a_frame_active_edges` | `STATUS.FRAME_ACTIVE` moves only on an accepted beat carrying SOF or EOF. Software polls it to decide when a configuration write is safe |
| `a_pop_needs_armed` | a layer is never popped before it has seen its first SOF |
| `a_cfg_bad_not_wanted`, `a_want_needs_canvas` | a layer reported as badly configured is never counted as enabled, and nothing is enabled against a rejected canvas |
| `a_canvas_beats_exact` | the active canvas width in beats is the pixel width shifted, exactly — `CANVAS` is either honoured or rejected, never silently narrowed |

[`props/fv_core_frame.sv`](../formal/props/fv_core_frame.sv) adds two things
that need a configuration which does not move, and so run under
`FV_STATIC_CFG`:

- **Framing.** An independent raster counts accepted output beats — derived
  from `TUSER` and the accepted-beat count, never from the core's own `out_bx`
  and `out_y`, which would make it a restatement of the design. `TUSER` must be
  on the first beat of a frame and nowhere else; `TLAST` on the last beat of
  every line and nowhere else. A downstream video timing generator locks to
  exactly these two bits.
- **Value.** With every layer's effective alpha at zero, the composite must be
  the background colour exactly, on every lane. That is one assertion across
  the whole cascade: the FIFO capture stage, the alpha stage, `P_NUM_LAYERS`
  blend stages and the output packing. `fv_blend` proves the arithmetic
  identity it rests on; this proves the cascade is wired to it.

### Sizing, and what that costs

Two layers, four-beat FIFOs, `P_PPC` 1 for most tasks and 2 for the `ppc` task,
canvas and windows bounded to a handful of pixels.

Two layers rather than four is the smallest count at which the cascade is a
cascade and at which "layer 0 nearest the background" means anything; the
per-layer logic is generated, so the third and fourth instances are copies of
the second. `P_PPC` 2 is where a control signal reaching the wrong lane would
show, since the lanes are independent in the cascade and share only control.

The geometry bound is a real restriction and worth stating plainly. A 16-bit
canvas puts the raster comparisons beyond what the solver will finish, and the
`frame` task needs a canvas small enough to emit whole frames inside the BMC
depth. The properties are about *relations* between registers rather than their
magnitudes, so a small canvas exercises the same logic — but a bug that only
appears above some threshold would not be caught here, and nothing in this
suite claims otherwise.

---

## 7. `axis_video_mixer` — the control port

`sby -f fv_top.sby` · [`props/fv_axil_props.sv`](../formal/props/fv_axil_props.sv)

The register block is generated by corsair and the adapter around it by
`regs/gen_regs.py`, so nobody reads this RTL line by line — which is exactly
why it is worth checking mechanically. A response channel that drops `BVALID`
before `BREADY`, or changes `RDATA` under a master that has not accepted it,
hangs or corrupts a processor bus, and the symptom is a wedged CPU rather than
a wrong picture.

| | |
|---|---|
| `a_bvalid_held`, `a_bresp_held`, `a_rvalid_held`, `a_rdata_held`, `a_rresp_held` | once offered, a response is held until accepted and its payload does not change underneath |
| `a_bresp_okay`, `a_rresp_okay` | every access is `OKAY`. The map decodes the whole space it claims, so a `SLVERR` would mean an advertised address is not actually decoded |
| `a_irq_is_masked_or` | `irq` is exactly `|(ERR & IRQ_EN)`, level sensitive. A pulse would be lost on a shared line |
| `a_err_set_wins` | an error arriving in the same cycle as its acknowledgement is not lost — the hardware set beats the software clear, which is R8's hard part |
| `a_err_sticky` | an `ERR` bit only ever clears because software wrote a one to it. A bit that cleared itself is a fault software never saw |
| `a_unflatten_tdata`, `a_unflatten_ready` | layer *i* really does occupy bit *i* and `TDATA[(i+1)*W-1 : i*W]` |
| `a_bvalid_solicited`, `a_rvalid_solicited` | no unsolicited response (bounded) |
| `a_write_responds`, `a_read_responds` | an accepted access is answered within 2 cycles (bounded) |

`a_unflatten_*` is there because unpacked array ports do not survive an IP-XACT
or block design boundary, so the top flattens per-layer arrays into one wide
vector per field. A transposed index there gives layer 1 layer 0's stream —
which composites into an entirely plausible picture, two windows in the right
places showing the wrong contents, and which a single-source bring-up test
cannot see at all.

The datapath properties are deliberately **not** re-run at this level.
`fv_core.sby` proves them with the configuration completely free, which is a
strictly harsher environment than one reached through a register file: the
register block cannot produce a configuration the core has not already been
proved to handle. What is left for this level is the control port, the
interrupt, and the wiring between.

`P_NUM_LAYERS` is four here and two in `fv_core.sby`, because the generated map
is built for four layers and `axis_video_mixer_csr` refuses to elaborate
against any other count.

### One finding worth recording

`a_write_responds` failed on the first run, and the counterexample was not a
bug in the property.

`axis_video_mixer_csr` keeps **one** captured write address — `wr_addr_q` with
`wr_addr_held`, taken on the AW handshake and released on the B handshake. With
two writes in flight the second address overwrites the first, and the
write-one-to-clear decode for `ERR` then applies to the wrong register.
AXI4-Lite *permits* multiple outstanding transactions, so this is a real
constraint: the block is safe behind any ordinary AXI4-Lite master or
interconnect, which issue one at a time, and it is not safe behind one that
pipelines.

It is now an explicit, documented assumption in `fv_top.sv`
(`m_one_write_addr`, `m_one_write_data`, `m_one_read`) rather than an
undocumented property of the implementation. Note what did *not* need it: the
protocol properties above hold either way. What fails without it is the latency
bound, because the adapter is waiting on a handshake for a transaction whose
address it has already lost.

`LP_AXIL_MAX_LATENCY` is 2, and 2 is exact — 1 fails. The number was found by
tightening it until it broke, which means a regeneration that makes the
register block slower fails this task instead of silently costing every driver
a cycle per register access.

---

## 8. Assumptions, and where each is discharged

An assumption nobody discharges is a hole in the result, so all fifteen are
listed. Most are magnitude bounds that exist only to keep the solver finishing,
or setup for one specific task; the behavioural ones are the first two rows and
the AXI4-Lite ordering constraint.

| Assumption | Where | Discharged by |
|---|---|---|
| `m_no_pop_when_empty` | `fv_fifo.sv`, `fv_layer.sv` | `a_no_pop_empty` in `fv_core_props.sv` |
| geometry constant between flushes | `fv_layer.sv` | `a_geom_change_flushes` in `fv_core_props.sv` |
| `m_geometry_nonzero` | `fv_layer.sv` | `a_geom_nonzero` in `fv_core_props.sv` |
| `m_one_write_addr` / `_data`, `m_one_read` | `fv_top.sv` | **nothing** — a constraint on the caller, see §7 |
| `m_canvas_bounded`, `m_window_bounded`, `m_geometry_bounded`, `m_stall_bounded` | `fv_core.sv`, `fv_layer.sv` | **nothing** — solver-cost bounds, see §6 |
| `m_alpha_zero`, `m_alpha_src_global` | `fv_core.sv` | **nothing** — these *set up* the datapath task rather than constraining the design |
| `m_bg_zero`, `m_pixels_zero` | `fv_core.sv` | **nothing** — proof-cost only, and used only by the `frame` task, whose properties read `TUSER`, `TLAST` and the handshakes and never a pixel value |

The core proof assumes nothing about behaviour at all. Every stream, the sink,
and every register software can write are free, and in particular nothing
assumes the configuration is legal — a zero canvas, a misaligned window and a
window hanging off the canvas are all reachable, and all things the core has to
reject rather than draw.

---

## 9. Results

135 assertion statements, 49 cover statements and 15 assumptions across five
proofs and 26 tasks. Assertions inside per-layer and per-lane generate loops
are elaborated once per instance, so the checked count is higher.

```bash
make -C formal            # everything, about 3m45 from clean
make -C formal quick      # every bmc task plus the cheap blend groups, ~30 s
make -C formal core TASKS=prove
```

| Unit | Tasks | Result | Wall |
|---|---|---|---|
| `fv_blend` | `div` `scale` `blend` `bound` `mono` `cover` | pass | ~40 s |
| `fv_fifo` | `bmc` `prove` `order` `cover` `depth` | pass | ~10 s |
| `fv_layer` | `bmc` `prove` `align` `watchdog` `cover` `ppc` | pass | ~10 s |
| `fv_core` | `bmc` `prove` `ppc` `cover` | pass | ~20 s |
| `fv_core` | `frame` `datapath` | pass | ~2 min |
| `fv_top` | `bmc` `prove` `cover` | pass | ~20 s |

Three and three-quarter minutes for the whole suite from clean on one machine,
most of it the two `fv_core` outliers; `sby` runs the tasks of one file in
parallel. `make quick` is the subset worth running while editing RTL and takes
just over thirty seconds — every `bmc` task plus the three cheap blend groups,
which between them catch the great majority of RTL mistakes.

`fv_core frame` and `datapath` are worth a note: per-step BMC cost climbs
steeply past step 13 there, so both the depth and the canvas size are held down
hard, and the `.sby` header lists what each of the five configuration choices
buys. `FV_CONST_PIXELS` is the most useful of them — freezing the pixel data
for the framing check, which reads `TUSER`, `TLAST` and the handshakes and never
a pixel, halves that task's runtime by keeping the blend cascade's 24-bit
operands out of the unrolling.

`prove` tasks are unbounded k-induction. `bmc`, `order`, `align`, `frame`,
`datapath` and `watchdog` are bounded model checking from reset, for the reasons
given where each appears. Every `cover` task passes with no unreached
statement, which is what stops a passing proof from being a proof over a dead
environment — `fv_core.sby cover` in particular reaches
`c_starve_while_running`, a layer starving while the output keeps producing
beats, which is R6 happening rather than R6 merely not being contradicted.

### Cover statements that were unreachable as first written

Both were checker bugs, and both are the kind that would have left a property
quietly vacuous.

`c_rearm` looked for `armed` rising in the cycle after a geometry fault. The
fault flushes, and a flush cannot be followed immediately by a push, so it can
never happen. What matters is that the layer comes back *at all*, so the fault
is now remembered in a sticky flag and the cover looks for an armed layer
afterwards.

`c_data_before_addr` looked for a W handshake while `w_outstanding >
aw_outstanding`. On the handshake cycle the counters have not incremented yet
and both are equal. Covered as a state rather than on the handshake, both
orders are reachable, which is what AXI4-Lite requires.

One assertion went the same way and is worth recording alongside them.
`a_irq_needs_enable` said "no interrupt from a masked bit" — which is implied,
term for term, by the equality `a_irq_is_masked_or` sitting two lines above it.
A property that cannot fail unless another one does is noise in the count and
nothing else; it was replaced by `a_err_set_wins` and `a_err_sticky`, which say
something the equality does not.

---

## 10. What is not covered

Stated plainly, because the gaps are the part of a verification claim that
matters.

- **Magnitudes.** Every proof runs over a small canvas and small windows. A bug
  that only appears above some threshold — a 16-bit comparison that is wrong
  only near its top, say — is not caught. §6 has the reasoning.
- **Layer counts above two, and `P_PPC` above two.** The per-layer and per-lane
  logic is generated, so the untested instances are copies. That is an argument,
  not a proof.
- **FIFO depths other than 2, 4, 8 and 64.** The properties are about pointer
  arithmetic, which is depth-independent, and the `depth` task checks that
  claim at one larger size. The shipping depth is 2048 and is never simulated
  by a solver here.
- **Ordering and positional accounting beyond their BMC depths.** §5 and §6.
  Ordering has an unbounded compositional argument behind it; positional
  accounting does not.
- **The register map's decode.** That software can *reach* the datapath is
  covered — `c_sw_enables`, `c_sw_canvas`, `c_sw_layer_active`,
  `c_sw_background`, `c_sw_clears_err` — but which address maps to which field
  is not asserted, because restating a generated decode in the checker would
  prove only that the two copies agree. The covers show the reachable behaviour
  exists, which is what a bad decode or a stuck-at register would make
  unreachable.
- **The picture.** No proof here says the composite is the *right* image for a
  given set of layer contents, except in the all-transparent case. That is what
  the UVM scoreboard is for, and its independently written golden blend is the
  right tool for it. The proofs cover the arithmetic identities the scoreboard
  cannot exhaust and the structural claims it cannot generalise.
- **Timing, area, CDC.** Not what this is.

---

## 11. If a property fails

`sby` leaves a VCD and a Verilog testbench in the task's work directory:

```
formal/fv_core_bmc/engine_0/trace.vcd
formal/fv_core_bmc/engine_0/trace_tb.v
```

Read the trace at the *step number the summary names*, and read the delayed
copies alongside the live ones — most early failures in writing this suite were
guard-timing mistakes, not design bugs: comparing a registered value against a
live one, or forgetting that `flush` in the previous cycle is the one that
matters for a next-cycle property.

Start from `bmc` rather than `prove`. It fails fast and its counterexample is a
trace from reset, which is readable. An induction failure is a trace from an
arbitrary state, which usually means a missing helper invariant rather than a
bug — `a_wait_sof_zeroed` in §6 and `a_raster_parked` in `fv_core_props.sv` are
both invariants that exist only because induction would not close without them,
and both took reading an induction counterexample to find.

One tool failure mode is worth knowing because its message names nothing
useful. A labelled assertion inside a procedural `for` loop unrolls into several
checks that all carry the same name, and yosys-slang dies with:

```
ERROR: Assert `count_id(cell->name) == 0' failed in kernel/rtlil.cc
```

Per-layer and per-lane properties therefore go in `for (genvar ...)` generate
loops, which give each one its own scope and its own name.
