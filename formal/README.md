# formal/

Formal verification for the AXI4-Stream video mixer. SymbiYosys plus
yosys-slang plus boolector, all three from the OSS CAD Suite.

```bash
make            # every proof, every task
make quick      # the fast half, about a minute, for use while editing RTL
make core TASKS=prove
make blend TASKS="div16 bound8"
make report     # re-print the last run's summary without re-running
make tools      # check that sby, yosys, the slang plugin and boolector are here
```

**[`doc/formal.md`](../doc/formal.md) is the document to read.** It says what is
proved, what is bounded rather than proved, where every assumption is
discharged, and what is not covered at all. This file is only a map of the
directory.

## Layout

```
fv_blend.sby     blend arithmetic in axis_video_mixer_pkg
fv_fifo.sby      axis_mixer_fifo
fv_layer.sby     axis_mixer_layer, with the FIFO underneath
fv_core.sby      axis_video_mixer_core, with the layers and FIFOs underneath
fv_top.sby       axis_video_mixer entire, register file included

props/           properties, bound into the RTL rather than written into it
tops/            formal environments -- what is free, what is assumed, and why
```

The `.sby` files are the real interface. `sby -f fv_core.sby prove` and
`make core TASKS=prove` do the same thing; the Makefile exists to run them all
and to summarise, because a suite that is awkward to run in one command stops
being run.

Task names in `fv_blend.sby` are a property group and a component width:
`div16` is the exactness group at `P_CH_W = 16`, `up10` the register-expansion
group at 10. Both axes are there for solver cost, and §4 of `doc/formal.md`
says which groups do not run at every width and what that leaves open.

## Two things to know before reading a property file

**Properties are bound, not inlined.** `props/*_bind.sv` attaches each checker
to a module rather than to an instance, so one property file is checked
everywhere that module appears — `fv_fifo_props.sv` runs standalone, once
inside the layer, and once per layer inside the core. A FIFO invariant that
only holds because of how the layer drives it is still proved, and one the
layer breaks is caught where it breaks. Binding also reaches internal signals,
which is where the interesting properties live: `wr_ptr`, `bt_cnt`,
`lay_active` and `act_bxe` are on no port.

**There is no SVA here, and that is not an oversight.** yosys-slang does not
implement `|->`, `|=>`, `$past`, `$stable`, `$anyconst` or `$initstate`. Every
property is a procedural immediate assertion sampled at the clock edge, with
history in explicit registers — the same idiom the RTL's own simulation
assertions use, for the reason documented at the bottom of
`src/axis_mixer_fifo.sv`. §2 and §3 of `doc/formal.md` cover the three idioms
this forces and why each is sound.
