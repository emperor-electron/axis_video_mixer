///////////////////////////////////////////////////////////////////
// Filename: mixer_base_test.sv
// Author  : Benjamin Tamayo
// Date    : 09/06/2026
// Purpose : Test library for the video mixer.
//
//           Included into mixer_tb_pkg; not a standalone compilation unit.
///////////////////////////////////////////////////////////////////

class mixer_base_test extends uvm_test;

  `uvm_component_utils(mixer_base_test)

  mixer_env env;

  axi_stream_config out_config;
  axi_lite_config   axil_config;

  int unsigned num_layers = 4;
  int unsigned canvas_w = 64;
  int unsigned canvas_h = 8;
  int unsigned num_frames = 3;

  // Layers this test cannot run without. A build with fewer skips it rather
  // than failing: a four-layer test on a two-layer mixer has proved nothing
  // either way, and reporting that as a failure trains people to ignore the
  // regression result.
  int unsigned min_layers = 1;
  bit          skipped = 1'b0;

  logic [23:0] background = 24'h101820;

  extern function new(string name = "mixer_base_test", uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);

  // ---- Register access helpers ----------------------------------------
  extern virtual task wait_for_reset();
  extern virtual task reg_write(int unsigned addr, logic [31:0] data);
  extern virtual task reg_read(int unsigned addr, output logic [31:0] data);
  extern virtual task check_reg(int unsigned addr, logic [31:0] expected, string what);

  // ---- Configuration helpers -------------------------------------------
  extern virtual task configure_common();
  extern virtual task configure_layer(int unsigned i, bit en, int unsigned lx, int unsigned ly,
                                      int unsigned lw, int unsigned lh, logic [7:0] alpha,
                                      bit alpha_src = 1'b0);
  extern virtual task start_mixer();
  extern virtual task wait_layers_armed(int unsigned timeout_cycles = 20000);
  extern virtual task wait_frames(int unsigned target, int unsigned timeout_cycles = 400000);

  // ---- The layout under test, overridden per test ----------------------
  extern virtual task setup_layout();
  extern virtual task drive_layers(int unsigned frames);
  extern virtual task post_check();

  extern function void report_phase(uvm_phase phase);

endclass : mixer_base_test


function mixer_base_test::new(string name = "mixer_base_test", uvm_component parent = null);
  super.new(name, parent);
endfunction : new


function void mixer_base_test::build_phase(uvm_phase phase);
  int cw, ch, nl;

  super.build_phase(phase);

  if (uvm_config_db#(int)::get(this, "", "canvas_w", cw)) canvas_w = cw;
  if (uvm_config_db#(int)::get(this, "", "canvas_h", ch)) canvas_h = ch;
  if (uvm_config_db#(int)::get(this, "", "num_layers", nl)) num_layers = nl;

  // A full-resolution frame is two million beats, so the frame count has to be
  // reachable without an edit. Plusarg rather than a generic: it is a property
  // of the run, not of the elaborated hardware, so changing it must not force
  // a rebuild of the snapshot.
  void'($value$plusargs("NUM_FRAMES=%d", num_frames));

  uvm_config_db#(int)::set(this, "env", "canvas_w", canvas_w);
  uvm_config_db#(int)::set(this, "env", "canvas_h", canvas_h);
  uvm_config_db#(int)::set(this, "env", "num_layers", num_layers);

  // The output sink accepts every beat by default. Backpressure tests
  // override this before super.build_phase().
  out_config           = axi_stream_config::type_id::create("out_config");
  out_config.role      = AXIS_SLAVE;
  out_config.is_active = UVM_ACTIVE;
  out_config.has_tuser = 1'b1;
  out_config.user_width = MIX_USER_WIDTH;
  out_config.has_tlast = 1'b1;
  out_config.has_tkeep = 1'b0;
  out_config.has_tstrb = 1'b0;
  out_config.set_ready_mode(AXIS_READY_ALWAYS);

  axil_config           = axi_lite_config::type_id::create("axil_config");
  axil_config.role      = AXI_LITE_MASTER;
  axil_config.is_active = UVM_ACTIVE;
  axil_config.addr_lo   = 'h000;
  axil_config.addr_hi   = 'hFFF;

  uvm_config_db#(axi_stream_config)::set(this, "env", "out_config", out_config);
  uvm_config_db#(axi_lite_config)::set(this, "env", "axil_config", axil_config);

  env = mixer_env::type_id::create("env", this);
endfunction : build_phase


///////////////////////////////////////////////////////////////////
// Register access
///////////////////////////////////////////////////////////////////

// The generated register block drives ARREADY from a flop that is cleared by
// reset, so it accepts an address phase even while held in reset -- and then
// returns the zeroed read data once reset lifts. A real bus master never
// transacts during reset, and neither should the testbench. Waiting here is
// what makes the first register read mean something.
task mixer_base_test::wait_for_reset();
  if (env.axil_agent.vif.aresetn !== 1'b1) begin
    @(posedge env.axil_agent.vif.aresetn);
  end
  repeat (4) @(posedge env.axil_agent.vif.aclk);
endtask : wait_for_reset


// local:: on every argument reference is load bearing, not decoration. Inside
// an inline constraint the object's own scope is searched first, so a bare
// `addr` resolves to the sequence's addr field and `addr == addr` is a
// tautology the solver satisfies with a random address. The transaction still
// runs, still returns OKAY, and lands somewhere else entirely -- which is how
// this testbench first read 0x000 and got the contents of 0x0C8.
task mixer_base_test::reg_write(int unsigned addr, logic [31:0] data);
  axi_lite_write_seq wr = axi_lite_write_seq::type_id::create("wr");
  if (!wr.randomize() with {
        addr  == local::addr;
        wdata == local::data;
        wstrb == 4'hF;
        prot  == 3'b000;
      })
    `uvm_fatal("RAND", $sformatf("register write randomization failed for 0x%03h", addr))
  wr.start(env.axil_agent.sequencer);
endtask : reg_write


task mixer_base_test::reg_read(int unsigned addr, output logic [31:0] data);
  axi_lite_read_seq rd = axi_lite_read_seq::type_id::create("rd");
  if (!rd.randomize() with {
        addr == local::addr;
        prot == 3'b000;
      })
    `uvm_fatal("RAND", $sformatf("register read randomization failed for 0x%03h", addr))
  rd.start(env.axil_agent.sequencer);
  data = rd.rdata;
endtask : reg_read


task mixer_base_test::check_reg(int unsigned addr, logic [31:0] expected, string what);
  logic [31:0] got;
  reg_read(addr, got);
  if (got !== expected) begin
    `uvm_error("REG", $sformatf("%s: [0x%03h] read 0x%08h, expected 0x%08h", what, addr, got,
                                expected))
  end else begin
    `uvm_info("REG", $sformatf("%s: [0x%03h] = 0x%08h", what, addr, got), UVM_HIGH)
  end
endtask : check_reg


///////////////////////////////////////////////////////////////////
// Configuration
///////////////////////////////////////////////////////////////////
task mixer_base_test::configure_common();
  logic [31:0] id, caps;

  // Identity first. Every later check is meaningless if the bus is not
  // actually reaching the block, and this distinguishes that from a
  // functional fault immediately.
  reg_read(REG_ID, id);
  if (id[31:16] !== 16'h4D58) begin
    `uvm_fatal("ID", $sformatf("ID.MAGIC read 0x%04h, expected 0x4D58 -- bus not reaching the mixer",
                               id[31:16]))
  end

  reg_read(REG_CAPS, caps);
  if (caps[7:0] !== num_layers[7:0]) begin
    `uvm_error("CAPS", $sformatf("CAPS.NUM_LAYERS=%0d but the testbench built %0d layers",
                                 caps[7:0], num_layers))
  end

  // Scratch proves both directions of the data path before anything that
  // changes behaviour is written.
  reg_write(REG_SCRATCH, 32'hA5A5_5A5A);
  check_reg(REG_SCRATCH, 32'hA5A5_5A5A, "scratch readback");

  reg_write(REG_CANVAS, {canvas_h[15:0], canvas_w[15:0]});
  reg_write(REG_BACKGROUND, {8'h00, background});
  reg_write(REG_STALL_LIMIT, 32'd0);  // watchdogs off unless a test wants them

  env.scoreboard.canvas_w   = canvas_w;
  env.scoreboard.canvas_h   = canvas_h;
  env.scoreboard.background = background;
endtask : configure_common


task mixer_base_test::configure_layer(int unsigned i, bit en, int unsigned lx,
                                      int unsigned ly, int unsigned lw, int unsigned lh,
                                      logic [7:0] alpha, bit alpha_src = 1'b0);
  reg_write(layer_reg(i, REG_L_POS), {ly[15:0], lx[15:0]});
  reg_write(layer_reg(i, REG_L_SIZE), {lh[15:0], lw[15:0]});
  reg_write(layer_reg(i, REG_L_CTRL), {15'd0, alpha_src, alpha, 7'd0, en});
  env.scoreboard.set_layer(i, en, lx, ly, lw, lh, alpha, alpha_src);
endtask : configure_layer


task mixer_base_test::start_mixer();
  reg_write(REG_CTRL, 32'h0000_0001);  // EN
endtask : start_mixer


// Wait until every enabled layer has seen its first SOF, using the same
// STATUS.LAYER_ARMED bits software would use.
//
// This is the bring-up order that makes the first output frame meaningful:
// sources up, then the raster. Enabling first is legal and does not break
// anything -- layers simply join at the following frame boundary -- but the
// first frame is then background only, which is correct behaviour that looks
// exactly like a fault in a pixel comparison.
// Wait until the output has produced `target` complete frames.
//
// The source sequences finishing is NOT the same event. A layer's pixels are
// buffered, so the last frame a source sends is still in flight -- often
// entirely unread -- when its sequence returns. Stopping the checks at that
// point leaves most of the stimulus unverified, which is a test that passes
// without having looked.
task mixer_base_test::wait_frames(int unsigned target, int unsigned timeout_cycles = 400000);
  int unsigned waited = 0;
  int unsigned last = env.scoreboard.frames_seen;
  int unsigned stalled = 0;

  while (env.scoreboard.frames_seen < target) begin
    repeat (64) @(posedge env.axil_agent.vif.aclk);
    waited += 64;

    if (env.scoreboard.frames_seen == last) begin
      stalled += 64;
      // Frames have stopped arriving entirely. Waiting out the full timeout
      // would just make the failure slower, not clearer.
      if (stalled > (canvas_w * canvas_h * 4)) begin
        `uvm_error("FRAMES", $sformatf("output stopped after %0d frames, wanted %0d",
                                       env.scoreboard.frames_seen, target))
        return;
      end
    end else begin
      last    = env.scoreboard.frames_seen;
      stalled = 0;
    end

    if (waited > timeout_cycles) begin
      `uvm_error("FRAMES", $sformatf("timed out waiting for %0d frames, saw %0d", target,
                                     env.scoreboard.frames_seen))
      return;
    end
  end
endtask : wait_frames


task mixer_base_test::wait_layers_armed(int unsigned timeout_cycles = 20000);
  logic [31:0] status;
  logic [15:0] want = 16'd0;
  int unsigned waited = 0;

  for (int unsigned i = 0; i < num_layers; i++) begin
    if (env.scoreboard.lay_en[i]) want[i] = 1'b1;
  end
  if (want == 16'd0) return;

  forever begin
    reg_read(REG_STATUS, status);
    if ((status[31:16] & want) == want) break;
    repeat (32) @(posedge env.axil_agent.vif.aclk);
    waited += 32;
    if (waited > timeout_cycles) begin
      `uvm_error("ARM", $sformatf("layers %04h never armed (STATUS=0x%08h)", want, status))
      break;
    end
  end
endtask : wait_layers_armed


///////////////////////////////////////////////////////////////////
// The default layout: a full-canvas background layer with a smaller,
// half-transparent window on top of it. That is picture-in-picture, and it
// exercises the two cases that matter at once -- a layer whose window starts
// at x = 0 with no in-line head start, and a layer that is only present on
// part of the raster.
///////////////////////////////////////////////////////////////////
task mixer_base_test::setup_layout();
  configure_layer(0, 1'b1, 0, 0, canvas_w, canvas_h, 8'hFF);
  if (num_layers > 1) begin
    configure_layer(1, 1'b1, canvas_w / 4, canvas_h / 4, canvas_w / 2, canvas_h / 2, 8'h80);
  end
  for (int unsigned i = 2; i < num_layers; i++) begin
    configure_layer(i, 1'b0, 0, 0, 0, 0, 8'hFF);
    env.scoreboard.lay_absent[i] = 1'b1;
  end
endtask : setup_layout


task mixer_base_test::drive_layers(int unsigned frames);
  // Every enabled layer streams concurrently. Sending them one after another
  // would hide exactly the interleaving faults this block exists to avoid.
  fork
    begin
      if (env.scoreboard.lay_en[0]) begin
        mixer_layer_frame_seq s = mixer_layer_frame_seq::type_id::create("l0");
        s.layer  = 0;
        s.width  = env.scoreboard.lay_w[0];
        s.height = env.scoreboard.lay_h[0];
        s.frames = frames;
        s.start(env.layer_agent[0].sequencer);
      end
    end
    begin
      if (num_layers > 1 && env.scoreboard.lay_en[1]) begin
        mixer_layer_frame_seq s = mixer_layer_frame_seq::type_id::create("l1");
        s.layer  = 1;
        s.width  = env.scoreboard.lay_w[1];
        s.height = env.scoreboard.lay_h[1];
        s.frames = frames;
        s.start(env.layer_agent[1].sequencer);
      end
    end
    begin
      if (num_layers > 2 && env.scoreboard.lay_en[2]) begin
        mixer_layer_frame_seq s = mixer_layer_frame_seq::type_id::create("l2");
        s.layer  = 2;
        s.width  = env.scoreboard.lay_w[2];
        s.height = env.scoreboard.lay_h[2];
        s.frames = frames;
        s.start(env.layer_agent[2].sequencer);
      end
    end
    begin
      if (num_layers > 3 && env.scoreboard.lay_en[3]) begin
        mixer_layer_frame_seq s = mixer_layer_frame_seq::type_id::create("l3");
        s.layer  = 3;
        s.width  = env.scoreboard.lay_w[3];
        s.height = env.scoreboard.lay_h[3];
        s.frames = frames;
        s.start(env.layer_agent[3].sequencer);
      end
    end
  join
endtask : drive_layers


task mixer_base_test::post_check();
  logic [31:0] err, fc;
  logic [31:0] unexpected;

  // STARVE is excluded, and not as a convenience. A test ends by stopping its
  // sources while the mixer keeps rastering, which is precisely the condition
  // STARVE reports -- so its absence here would mean the mixer had stopped
  // when it should not have. Every other bit is a genuine failure.
  reg_read(REG_ERR, err);
  unexpected = err & ~(32'd1 << ERR_STARVE);
  if (unexpected !== 32'd0) begin
    `uvm_error("ERR", $sformatf("ERR is 0x%08h at end of test; unexpected bits 0x%08h", err,
                                unexpected))
  end

  reg_read(REG_FRAME_COUNT, fc);
  `uvm_info("FRAMES", $sformatf("FRAME_COUNT = %0d, scoreboard saw %0d (%0d pixel-checked)", fc,
                                env.scoreboard.frames_seen, env.scoreboard.frames_checked),
            UVM_LOW)
  if (fc == 32'd0) `uvm_error("FRAMES", "FRAME_COUNT never advanced");

  // A test that checked no frames passes for the wrong reason. Guard against
  // stimulus that silently stopped producing.
  if (env.scoreboard.frames_checked < 2) begin
    `uvm_error("FRAMES", $sformatf("only %0d frames were pixel-checked; expected at least 2",
                                   env.scoreboard.frames_checked))
  end
endtask : post_check


task mixer_base_test::run_phase(uvm_phase phase);
  phase.raise_objection(this, "mixer test running");

  if (num_layers < min_layers) begin
    skipped = 1'b1;
    `uvm_info("SKIP", $sformatf("needs %0d layers, this build has %0d", min_layers, num_layers),
              UVM_LOW)
    phase.drop_objection(this, "test skipped");
    return;
  end

  wait_for_reset();
  configure_common();
  setup_layout();

  // Sources first, raster second. The layer sequences run concurrently with
  // the enable because a source will backpressure on a full FIFO until the
  // mixer starts draining it, so starting them and then waiting would hang.
  // Each source supplies num_frames frames, and the raster consumes exactly one
  // source frame per output frame, so frames 0 .. num_frames-1 are the ones
  // with content behind them. Bounding the window here means the checks stop on
  // the exact beat rather than whenever a polling loop next looks.
  env.scoreboard.check_until_frame = num_frames;

  fork
    drive_layers(num_frames);
    begin
      wait_layers_armed();
      start_mixer();
    end
  join

  // The sources have stopped sending, but their last frames are still buffered.
  // Wait for the output to actually draw them before checking anything.
  wait_frames(num_frames);

  repeat (canvas_w * canvas_h + 512) @(posedge env.axil_agent.vif.aclk);

  post_check();

  phase.drop_objection(this, "mixer test done");
endtask : run_phase


function void mixer_base_test::report_phase(uvm_phase phase);
  uvm_report_server svr = uvm_report_server::get_server();
  int unsigned n_err;
  string result;

  super.report_phase(phase);
  n_err = svr.get_severity_count(UVM_ERROR) + svr.get_severity_count(UVM_FATAL);

  // Assigned through a string variable rather than selected inline with a
  // ternary. String literals in an expression are packed vectors sized to the
  // widest operand, so "PASSED" next to "SKIPPED" comes out zero-padded to
  // seven characters -- and the banner the Makefile greps for silently gains a
  // leading space.
  if (skipped) result = "SKIPPED";
  else if (n_err == 0) result = "PASSED";
  else result = "FAILED";

  // XSIM exits 0 even after UVM_FATAL, so the Makefile greps for this banner
  // rather than trusting the exit status.
  $display("");
  $display("=====================================");
  $display(" test    : %s", get_type_name());
  $display(" result  : %s", result);
  $display("=====================================");
endfunction : report_phase


///////////////////////////////////////////////////////////////////
// Backpressure. The output sink accepts on 60% of cycles at random.
//
// This is the test that catches a mixer whose FIFO pops are not gated by the
// output handshake: the pipeline would advance while the sink was not taking
// beats, and every layer would slip against the raster.
///////////////////////////////////////////////////////////////////
class mixer_backpressure_test extends mixer_base_test;

  `uvm_component_utils(mixer_backpressure_test)

  function new(string name = "mixer_backpressure_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    out_config.set_ready_mode(AXIS_READY_RANDOM, 60);
  endfunction

endclass : mixer_backpressure_test


///////////////////////////////////////////////////////////////////
// Four layers in a 2x2 tile, all opaque. Tiling is the case where every
// output pixel comes from exactly one layer and the windows abut without
// overlapping, so an off-by-one at any window edge shows up immediately as a
// seam of background colour.
///////////////////////////////////////////////////////////////////
class mixer_tiling_test extends mixer_base_test;

  `uvm_component_utils(mixer_tiling_test)

  function new(string name = "mixer_tiling_test", uvm_component parent = null);
    super.new(name, parent);
    min_layers = 4;
  endfunction

  virtual task setup_layout();
    int unsigned hw = canvas_w / 2;
    int unsigned hh = canvas_h / 2;
    configure_layer(0, 1'b1, 0, 0, hw, hh, 8'hFF);
    configure_layer(1, 1'b1, hw, 0, hw, hh, 8'hFF);
    configure_layer(2, 1'b1, 0, hh, hw, hh, 8'hFF);
    configure_layer(3, 1'b1, hw, hh, hw, hh, 8'hFF);
  endtask

endclass : mixer_tiling_test


///////////////////////////////////////////////////////////////////
// Four layers stacked on the same window, each half transparent.
//
// Every output pixel then passes through all four blend stages, which is the
// arrangement that would expose an accumulated rounding error: a divide by 256
// in place of a divide by 255 loses under half a percent per layer, invisible
// once and obvious four deep.
///////////////////////////////////////////////////////////////////
class mixer_stacked_alpha_test extends mixer_base_test;

  `uvm_component_utils(mixer_stacked_alpha_test)

  function new(string name = "mixer_stacked_alpha_test", uvm_component parent = null);
    super.new(name, parent);
    min_layers = 4;
  endfunction

  virtual task setup_layout();
    // Layer 0 opaque and full canvas so there is a defined base; the three
    // above it translucent, with a mix of global-only and per-pixel alpha.
    configure_layer(0, 1'b1, 0, 0, canvas_w, canvas_h, 8'hFF);
    configure_layer(1, 1'b1, 0, 0, canvas_w, canvas_h, 8'h40);
    configure_layer(2, 1'b1, 0, 0, canvas_w, canvas_h, 8'hC0, 1'b1);  // global only
    configure_layer(3, 1'b1, 0, 0, canvas_w, canvas_h, 8'h80);
  endtask

endclass : mixer_stacked_alpha_test


///////////////////////////////////////////////////////////////////
// Alpha at its exact endpoints.
//
// 0 must leave the layer below untouched and 255 must reproduce the top layer
// bit for bit. These are the two values an approximate blend gets almost
// right, and "almost" is what makes a stack of opaque layers drift dark.
///////////////////////////////////////////////////////////////////
class mixer_alpha_extremes_test extends mixer_base_test;

  `uvm_component_utils(mixer_alpha_extremes_test)

  function new(string name = "mixer_alpha_extremes_test", uvm_component parent = null);
    super.new(name, parent);
    min_layers = 3;
  endfunction

  virtual task setup_layout();
    configure_layer(0, 1'b1, 0, 0, canvas_w, canvas_h, 8'hFF);
    // Fully transparent: must be invisible despite covering everything.
    configure_layer(1, 1'b1, 0, 0, canvas_w, canvas_h, 8'h00, 1'b1);
    // Fully opaque over the left half: must replace whatever is beneath it.
    configure_layer(2, 1'b1, 0, 0, canvas_w / 2, canvas_h, 8'hFF, 1'b1);
    for (int unsigned i = 3; i < num_layers; i++) begin
      configure_layer(i, 1'b0, 0, 0, 0, 0, 8'hFF);
      env.scoreboard.lay_absent[i] = 1'b1;
    end
  endtask

endclass : mixer_alpha_extremes_test


///////////////////////////////////////////////////////////////////
// A layer that stops mid-frame.
//
// The point of the test is not the error bit, it is everything that happens
// afterwards: the output must keep producing pixels at full rate, the frame
// count must keep advancing, and the starved layer must come back on its own
// once its source resumes. A mixer that stalls here would take the display
// down with the source, which is the failure this design is built to avoid.
///////////////////////////////////////////////////////////////////
class mixer_starve_test extends mixer_base_test;

  `uvm_component_utils(mixer_starve_test)

  function new(string name = "mixer_starve_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    logic [31:0] err, err_layer, fc0, fc1, l1_status;

    phase.raise_objection(this, "starve test running");

    wait_for_reset();
  configure_common();
    configure_layer(0, 1'b1, 0, 0, canvas_w, canvas_h, 8'hFF);
    configure_layer(1, 1'b1, canvas_w / 4, canvas_h / 4, canvas_w / 2, canvas_h / 2, 8'hFF);
    for (int unsigned i = 2; i < num_layers; i++) begin
      configure_layer(i, 1'b0, 0, 0, 0, 0, 8'hFF);
      env.scoreboard.lay_absent[i] = 1'b1;
    end

    // A desynchronised layer makes pixel prediction meaningless; framing and
    // liveness are what this test is about.
    env.scoreboard.check_pixels = 1'b0;

    start_mixer();

    fork
      begin
        mixer_layer_frame_seq s = mixer_layer_frame_seq::type_id::create("l0");
        s.layer  = 0;
        s.width  = canvas_w;
        s.height = canvas_h;
        s.frames = 4;
        s.start(env.layer_agent[0].sequencer);
      end
      begin
        // Layer 1 sends part of one frame and then goes quiet.
        mixer_layer_partial_seq s = mixer_layer_partial_seq::type_id::create("l1_partial");
        s.layer = 1;
        s.width = canvas_w / 2;
        s.beats = (canvas_w / 2) * 2;
        s.start(env.layer_agent[1].sequencer);
      end
    join

    repeat (canvas_w * canvas_h * 2) @(posedge env.axil_agent.vif.aclk);

    reg_read(REG_ERR, err);
    reg_read(REG_ERR_LAYER, err_layer);
    reg_read(layer_reg(1, REG_L_STATUS), l1_status);

    if (!err[ERR_STARVE]) `uvm_error("STARVE", "ERR.STARVE did not latch after a layer ran dry");
    if (!err_layer[1]) `uvm_error("STARVE", "ERR_LAYER did not name layer 1");

    // Liveness across the starve is the real assertion here.
    reg_read(REG_FRAME_COUNT, fc0);
    repeat (canvas_w * canvas_h * 2) @(posedge env.axil_agent.vif.aclk);
    reg_read(REG_FRAME_COUNT, fc1);
    if (fc1 <= fc0) begin
      `uvm_error("STARVE",
                 $sformatf("output stopped after a starve: FRAME_COUNT %0d then %0d", fc0, fc1))
    end else begin
      `uvm_info("STARVE", $sformatf("output kept running: FRAME_COUNT %0d -> %0d", fc0, fc1),
                UVM_LOW)
    end

    // Clear, then prove the layer re-arms when its source comes back.
    reg_write(REG_ERR, 32'hFFFF_FFFF);
    reg_write(REG_ERR_LAYER, 32'hFFFF_FFFF);

    begin
      mixer_layer_frame_seq s = mixer_layer_frame_seq::type_id::create("l1_resume");
      s.layer  = 1;
      s.width  = canvas_w / 2;
      s.height = canvas_h / 2;
      s.frames = 2;
      s.start(env.layer_agent[1].sequencer);
    end

    repeat (canvas_w * canvas_h) @(posedge env.axil_agent.vif.aclk);
    reg_read(layer_reg(1, REG_L_STATUS), l1_status);
    if (!l1_status[0]) `uvm_error("STARVE", "layer 1 never re-armed after its source resumed");

    phase.drop_objection(this, "starve test done");
  endtask

endclass : mixer_starve_test


///////////////////////////////////////////////////////////////////
// A source whose framing disagrees with its SIZE register.
//
// TLAST lands one pixel early. Nothing about the beat is illegal AXI4-Stream,
// which is the point: only the mixer's own geometry check can catch it, and if
// it does not, the layer silently shears by a pixel per line for as long as it
// runs.
///////////////////////////////////////////////////////////////////
class mixer_geometry_error_test extends mixer_base_test;

  `uvm_component_utils(mixer_geometry_error_test)

  function new(string name = "mixer_geometry_error_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    logic [31:0] err, err_layer, fc0, fc1;

    phase.raise_objection(this, "geometry error test running");

    wait_for_reset();
  configure_common();
    configure_layer(0, 1'b1, 0, 0, canvas_w, canvas_h, 8'hFF);
    for (int unsigned i = 1; i < num_layers; i++) begin
      configure_layer(i, 1'b0, 0, 0, 0, 0, 8'hFF);
      env.scoreboard.lay_absent[i] = 1'b1;
    end
    env.scoreboard.check_pixels = 1'b0;

    start_mixer();

    begin
      mixer_layer_frame_seq s = mixer_layer_frame_seq::type_id::create("l0_bad");
      s.layer    = 0;
      s.width    = canvas_w;
      s.height   = canvas_h;
      s.frames   = 1;
      s.tlast_at = int'(canvas_w) - 2;  // one pixel early
      s.start(env.layer_agent[0].sequencer);
    end

    repeat (canvas_w * canvas_h) @(posedge env.axil_agent.vif.aclk);

    reg_read(REG_ERR, err);
    reg_read(REG_ERR_LAYER, err_layer);
    if (!err[ERR_GEOM]) `uvm_error("GEOM", "ERR.GEOM did not latch on a misplaced TLAST");
    if (!err_layer[0]) `uvm_error("GEOM", "ERR_LAYER did not name layer 0");

    reg_read(REG_FRAME_COUNT, fc0);
    repeat (canvas_w * canvas_h * 2) @(posedge env.axil_agent.vif.aclk);
    reg_read(REG_FRAME_COUNT, fc1);
    if (fc1 <= fc0) `uvm_error("GEOM", "output stopped after a geometry fault");

    phase.drop_objection(this, "geometry error test done");
  endtask

endclass : mixer_geometry_error_test


///////////////////////////////////////////////////////////////////
// Configuration the hardware must refuse: a window hanging off the right edge
// of the canvas, and a zero-sized one.
//
// Both would otherwise read pixels the source never sent. The mixer is
// required to reject them, say so in ERR.CFG and L<i>_STATUS.CFG_BAD, and keep
// drawing with the configuration it already had.
///////////////////////////////////////////////////////////////////
class mixer_bad_config_test extends mixer_base_test;

  `uvm_component_utils(mixer_bad_config_test)

  function new(string name = "mixer_bad_config_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    logic [31:0] err, st1, st2, fc0, fc1;

    phase.raise_objection(this, "bad config test running");

    wait_for_reset();
  configure_common();
    configure_layer(0, 1'b1, 0, 0, canvas_w, canvas_h, 8'hFF);
    env.scoreboard.check_pixels = 1'b0;
    for (int unsigned i = 1; i < num_layers; i++) begin
      configure_layer(i, 1'b0, 0, 0, 0, 0, 8'hFF);
      env.scoreboard.lay_absent[i] = 1'b1;
    end
    start_mixer();

    // Layer 1: overhangs the right edge by one pixel.
    reg_write(layer_reg(1, REG_L_POS), {16'd0, canvas_w[15:0] - 16'd4});
    reg_write(layer_reg(1, REG_L_SIZE), {16'd1, 16'd5});
    reg_write(layer_reg(1, REG_L_CTRL), {15'd0, 1'b0, 8'hFF, 7'd0, 1'b1});

    // Layer 2: zero width.
    if (num_layers > 2) begin
      reg_write(layer_reg(2, REG_L_POS), {16'd0, 16'd0});
      reg_write(layer_reg(2, REG_L_SIZE), {16'd4, 16'd0});
      reg_write(layer_reg(2, REG_L_CTRL), {15'd0, 1'b0, 8'hFF, 7'd0, 1'b1});
    end

    fork
      begin
        mixer_layer_frame_seq s = mixer_layer_frame_seq::type_id::create("l0");
        s.layer  = 0;
        s.width  = canvas_w;
        s.height = canvas_h;
        s.frames = 3;
        s.start(env.layer_agent[0].sequencer);
      end
    join

    repeat (canvas_w * canvas_h) @(posedge env.axil_agent.vif.aclk);

    reg_read(REG_ERR, err);
    reg_read(layer_reg(1, REG_L_STATUS), st1);
    if (!err[ERR_CFG]) `uvm_error("CFG", "ERR.CFG did not latch on an out-of-bounds window");
    if (!st1[2]) `uvm_error("CFG", "L1_STATUS.CFG_BAD not set for an out-of-bounds window");

    if (num_layers > 2) begin
      reg_read(layer_reg(2, REG_L_STATUS), st2);
      if (!st2[2]) `uvm_error("CFG", "L2_STATUS.CFG_BAD not set for a zero-width window");
    end

    // Rejecting a configuration must not take the output down with it.
    reg_read(REG_FRAME_COUNT, fc0);
    repeat (canvas_w * canvas_h * 2) @(posedge env.axil_agent.vif.aclk);
    reg_read(REG_FRAME_COUNT, fc1);
    if (fc1 <= fc0) `uvm_error("CFG", "output stopped after a rejected configuration");

    phase.drop_objection(this, "bad config test done");
  endtask

endclass : mixer_bad_config_test


///////////////////////////////////////////////////////////////////
// Move a layer between frames.
//
// Position is double buffered, so the window must move exactly at a frame
// boundary and never within one. The moved layer is allowed one frame to
// re-arm -- it flushes, since everything buffered was counted against the old
// geometry -- and must be correct in every frame after that.
///////////////////////////////////////////////////////////////////
class mixer_move_layer_test extends mixer_base_test;

  `uvm_component_utils(mixer_move_layer_test)

  function new(string name = "mixer_move_layer_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this, "move layer test running");

    wait_for_reset();
    configure_common();
    configure_layer(0, 1'b1, 0, 0, canvas_w, canvas_h, 8'hFF);
    configure_layer(1, 1'b1, 0, 0, canvas_w / 2, canvas_h / 2, 8'hFF);
    for (int unsigned i = 2; i < num_layers; i++) begin
      configure_layer(i, 1'b0, 0, 0, 0, 0, 8'hFF);
      env.scoreboard.lay_absent[i] = 1'b1;
    end

    // Three source frames go in before the move, so frames 0..2 have content.
    env.scoreboard.check_until_frame = 3;

    // ---- Phase one: layer 1 in the top-left corner ----------------------
    fork
      begin
        fork
          begin
            mixer_layer_frame_seq s = mixer_layer_frame_seq::type_id::create("l0a");
            s.layer  = 0;
            s.width  = canvas_w;
            s.height = canvas_h;
            s.frames = 3;
            s.start(env.layer_agent[0].sequencer);
          end
          begin
            mixer_layer_frame_seq s = mixer_layer_frame_seq::type_id::create("l1a");
            s.layer  = 1;
            s.width  = canvas_w / 2;
            s.height = canvas_h / 2;
            s.frames = 3;
            s.start(env.layer_agent[1].sequencer);
          end
        join
      end
      begin
        wait_layers_armed();
        start_mixer();
      end
    join

    wait_frames(2);
    if (env.scoreboard.pixel_errors != 0) begin
      `uvm_error("MOVE", $sformatf("%0d pixel errors before the move",
                                   env.scoreboard.pixel_errors))
    end

    // ---- Move it -------------------------------------------------------
    // Changing geometry flushes the layer and costs it one frame while it
    // re-arms at its next input SOF, so checking is suspended across the
    // change and resumed once the new position has had a frame to settle.
    env.scoreboard.check_pixels = 1'b0;
    configure_layer(1, 1'b1, canvas_w / 2, canvas_h / 2, canvas_w / 2, canvas_h / 2, 8'hFF);

    fork
      begin
        fork
          begin
            mixer_layer_frame_seq s = mixer_layer_frame_seq::type_id::create("l0b");
            s.layer  = 0;
            s.width  = canvas_w;
            s.height = canvas_h;
            s.frames = 5;
            s.start(env.layer_agent[0].sequencer);
          end
          begin
            mixer_layer_frame_seq s = mixer_layer_frame_seq::type_id::create("l1b");
            s.layer  = 1;
            s.width  = canvas_w / 2;
            s.height = canvas_h / 2;
            s.frames = 5;
            s.start(env.layer_agent[1].sequencer);
          end
        join
      end
      begin
        // Reopen the window two frames after the move, giving the flushed layer
        // time to re-arm and rejoin at a boundary, and close it again two frames
        // later -- comfortably inside the five frames the sources supply.
        wait_frames(env.scoreboard.frames_seen + 2);
        env.scoreboard.check_from_frame  = env.scoreboard.frames_seen + 1;
        env.scoreboard.check_until_frame = env.scoreboard.frames_seen + 3;
        env.scoreboard.check_pixels      = 1'b1;
      end
    join

    repeat (canvas_w * canvas_h) @(posedge env.axil_agent.vif.aclk);
    post_check();

    phase.drop_objection(this, "move layer test done");
  endtask

endclass : mixer_move_layer_test
