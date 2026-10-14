`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: mixer_output_smoke.sv
// Author  : Benjamin Tamayo
// Purpose : The scenarios behind doc/design.md 13.3 and 13.6, as a runnable
//           model rather than a table someone has to trust.
//
//           Every way of getting "background only" out of the mixer is here,
//           one scenario each, with the register signature it produces. The
//           point is not pass/fail -- it is that the five causes are
//           DISTINGUISHABLE from software, which is the claim 13.3 makes and
//           the thing that turns a day of probing into one register read.
//
//           It drives axis_video_mixer_core directly rather than through
//           AXI4-Lite, so a scenario is three lines of configuration instead
//           of a register sequence. That is deliberate: this is a model of the
//           datapath's behaviour, not of the register block, which fv_axil and
//           the UVM bench cover between them.
//
//           Built with Verilator rather than XSIM so it runs anywhere:
//               cd tb/smoke && make
//
//           Two traps this file exists to not re-learn. The source driver uses
//           BLOCKING assignments off the negedge and samples TREADY at the
//           posedge; written with non-blocking assignments, TVALID is never
//           actually seen high and every scenario reports a healthy-looking
//           transfer of nothing. And the configuration is applied while reset
//           is asserted, because CTRL.SYNC_START has a reset VALUE -- setting
//           it afterwards lets one frame escape before the gate shuts at the
//           next boundary, which is correct behaviour but not what these
//           scenarios mean to measure.
///////////////////////////////////////////////////////////////////
module mixer_output_smoke #(
    // Which memory primitive the layer buffers use. The scenarios below must
    // produce identical numbers under either, which is the whole claim
    // P_RAM_STYLE makes; `make RAM_STYLE=ultra` is the other half of it.
    parameter string P_RAM_STYLE = "block"
);
  import axis_video_mixer_pkg::*;

  localparam int NL = 1;
  localparam int W  = 8;
  localparam int H  = 8;
  localparam logic [23:0] BG = 24'h20_40_60;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  // shadow config
  logic ctrl_en = 0, ctrl_soft_rst = 0, ctrl_sync_start = 0;
  logic [31:0] sync_timeout = 0;
  logic [15:0] canvas_width = W, canvas_height = H;
  logic [23:0] background_rgb = BG;
  logic [31:0] stall_limit = 0;
  logic [NL-1:0] lay_en = 0;
  logic [NL-1:0][7:0] lay_alpha;
  logic [NL-1:0] lay_alpha_src = 0;
  logic [NL-1:0][15:0] lay_x, lay_y, lay_w, lay_h;

  // status
  logic status_frame_active, status_sync_wait;
  logic [31:0] frame_count;
  logic err_cfg_set, err_starve_set, err_geom_set, err_src_stall_set, err_out_stall_set;
  logic err_sync_to_set;
  logic [NL-1:0] err_layer_set, lay_armed, lay_dropped, lay_cfg_bad;
  logic [NL-1:0][15:0] lay_level;

  // streams
  logic [NL-1:0] s_tvalid, s_tready, s_tuser, s_tlast;
  logic [NL-1:0][31:0] s_tdata;
  logic m_tvalid, m_tready, m_tuser, m_tlast;
  logic [31:0] m_tdata;

  axis_video_mixer_core #(.P_NUM_LAYERS(NL), .P_FIFO_DEPTH(64), .P_RAM_STYLE(P_RAM_STYLE),
                          .P_OUT_HAS_ALPHA(1'b1),
                          .P_PPC(1), .P_CH_W(8)) dut (.*,
    .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready), .s_axis_tdata(s_tdata),
    .s_axis_tuser(s_tuser), .s_axis_tlast(s_tlast),
    .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready), .m_axis_tdata(m_tdata),
    .m_axis_tuser(m_tuser), .m_axis_tlast(m_tlast));

  // ---- sticky error view, like the register block ----
  logic e_cfg, e_starve, e_geom, e_srcstall, e_syncto;
  always_ff @(posedge clk) begin
    if (!rst_n) begin e_cfg<=0; e_starve<=0; e_geom<=0; e_srcstall<=0; e_syncto<=0; end
    else begin
      if (err_cfg_set)       e_cfg     <= 1;
      if (err_starve_set)    e_starve  <= 1;
      if (err_geom_set)      e_geom    <= 1;
      if (err_src_stall_set) e_srcstall<= 1;
      if (err_sync_to_set)   e_syncto  <= 1;
    end
  end

  // ---- output observer: how many beats are NOT the background colour ----
  int n_beats, n_nonbg, n_frames;
  logic tvalid_ever;
  always_ff @(posedge clk) if (!rst_n) tvalid_ever <= 0; else if (m_tvalid) tvalid_ever <= 1;
  logic [23:0] bg_exp;
  assign bg_exp = {rgb_up(8, BG)};
  always_ff @(posedge clk) begin
    // Gated on rst_n, or the final beat of the previous scenario is counted
    // against the next one: the pipeline's valid is cleared synchronously, so
    // the edge that clears it is also an edge on which it still reads 1.
    if (rst_n && m_tvalid && m_tready) begin
      n_beats++;
      if (m_tdata[31:8] !== bg_exp) n_nonbg++;
      if (m_tlast && dut.eof_q[NL]) n_frames++;
    end
  end

  // ---- source ----
  int src_gap;        // idle cycles between beats
  logic src_run;
  bit  src_alpha_zero;   // leave the alpha byte at 0
  bit  src_frame_tlast;  // TLAST only on the last beat of the FRAME, not each line
  int  src_frames;

  task automatic drive_beat(logic [31:0] d, logic u, logic l);
    @(negedge clk);
    s_tdata[0] = d; s_tuser[0] = u; s_tlast[0] = l; s_tvalid[0] = 1'b1;
    do @(posedge clk); while (!s_tready[0]);
    if (src_gap > 0) begin
      @(negedge clk);
      s_tvalid[0] = 1'b0;
      repeat (src_gap) @(posedge clk);
    end
  endtask

  task automatic drive_frame(int fno);
    int lw, lh;
    lw = (lay_w[0] == 0) ? W : int'(lay_w[0]);   // follow the layer, not the canvas
    lh = (lay_h[0] == 0) ? H : int'(lay_h[0]);
    for (int y = 0; y < lh; y++)
      for (int x = 0; x < lw; x++)
        drive_beat({8'(16*(y+1)), 8'(16*(x+1)), 8'hC0, src_alpha_zero ? 8'h00 : 8'hFF},
                   (x == 0) && (y == 0),
                   src_frame_tlast ? ((x == lw-1) && (y == lh-1)) : (x == lw-1));
    src_frames++;
  endtask

  initial begin
    s_tvalid[0] = 0; s_tuser[0] = 0; s_tlast[0] = 0; s_tdata[0] = 0;
    forever begin
      if (src_run) drive_frame(src_frames); else @(posedge clk);
    end
  end

  // ---- scenarios ----
  string name;
  int    pass_cnt, fail_cnt;

  // cfg_* are applied while reset is asserted, which is what a real build sees:
  // CTRL.SYNC_START has a reset VALUE, it is not written after the fact. Setting
  // it late lets one frame escape before the gate shuts at the next boundary,
  // which is correct behaviour but not what these scenarios mean to measure.
  bit        cfg_sync;
  logic [31:0] cfg_timeout;

  task automatic reset_all();
    src_run = 0; ctrl_en = 0; lay_en = 0; rst_n = 0;
    cfg_sync = 0; cfg_timeout = 0;
    src_gap = 0; src_alpha_zero = 0; src_frame_tlast = 0; src_frames = 0;
    n_beats = 0; n_nonbg = 0; n_frames = 0;
    lay_alpha[0] = 8'hFF; lay_alpha_src = 0;
    lay_x[0] = 0; lay_y[0] = 0;
    lay_w[0] = W; lay_h[0] = H;
    repeat (5) @(posedge clk);
  endtask

  // Release reset with the configuration already in place.
  task automatic release_reset();
    ctrl_sync_start = cfg_sync;
    sync_timeout    = cfg_timeout;
    rst_n = 1;
    repeat (5) @(posedge clk);
  endtask

  task automatic run(string s, int cycles);
    name = s;
    release_reset();
    src_run = 1;
    ctrl_en = 1;
    repeat (cycles) @(posedge clk);
    $display("%-28s beats=%4d nonbg=%4d frames=%2d | armed=%b lvl=%2d syncwait=%b | ERR cfg=%b starve=%b geom=%b syncto=%b | srcf=%0d",
             s, n_beats, n_nonbg, n_frames, lay_armed[0], lay_level[0], status_sync_wait,
             e_cfg, e_starve, e_geom, e_syncto, src_frames);
  endtask

  initial begin
    m_tready = 1;

    // 1. everything correct
    reset_all(); lay_en = 1; run("1 baseline-correct", 3000);

    // 2. source leaves the alpha byte at zero, ALPHA_SRC = PIXEL_X_GLOBAL
    reset_all(); lay_en = 1; src_alpha_zero = 1; run("2 pixel-alpha-zero", 3000);

    // 3. EN set but SIZE never written (reset value)
    reset_all(); lay_en = 1; lay_w[0] = 0; lay_h[0] = 0; run("3 size-zero", 3000);

    // 4. TLAST once per frame instead of per line
    reset_all(); lay_en = 1; src_frame_tlast = 1; run("4 tlast-per-frame", 3000);

    // 5. source slower than the raster, window at the origin
    reset_all(); lay_en = 1; src_gap = 3; run("5 slow-source", 3000);

    // 6. layer never enabled
    reset_all(); lay_en = 0; run("6 layer-not-enabled", 3000);

    // 7. window off the canvas (x+w > width)
    reset_all(); lay_en = 1; lay_x[0] = 4; lay_w[0] = 8; run("7 window-overhangs", 3000);

    $display("--- soft start ---");

    // 8/9. window at the canvas origin, half the canvas width, source at
    //      exactly the rate the window needs. No slack at beat zero.
    reset_all(); lay_en = 1; lay_w[0] = 4; src_gap = 1;
    run("8  half-width gap1 sync=0", 4000);
    reset_all(); lay_en = 1; lay_w[0] = 4; src_gap = 1; cfg_sync = 1;
    run("9  half-width gap1 sync=1", 4000);

    // 10. an enabled layer whose source never comes up, waiting indefinitely
    reset_all(); lay_en = 1; cfg_sync = 1; release_reset();
    ctrl_en = 1; src_run = 0;
    repeat (8000) @(posedge clk);
    $display("10 dead-source sync=1 to=0   beats=%4d nonbg=%4d frames=%2d | armed=%b lvl=%2d syncwait=%b | ERR cfg=%b starve=%b geom=%b syncto=%b | tvalid_ever=%b",
             n_beats, n_nonbg, n_frames, lay_armed[0], lay_level[0], status_sync_wait,
             e_cfg, e_starve, e_geom, e_syncto, tvalid_ever);

    // 11. the same, with the wait bounded
    reset_all(); lay_en = 1; cfg_sync = 1; cfg_timeout = 32'd500; release_reset();
    ctrl_en = 1; src_run = 0;
    repeat (4000) @(posedge clk); run("11 dead-source to=500", 1);

    // 12. correct source, gate on: must be no worse than sync=0
    reset_all(); lay_en = 1; cfg_sync = 1; run("12 correct sync=1", 4000);

    // 13. a layer that is enabled but off the visible area still gates
    reset_all(); lay_en = 1; src_gap = 1; lay_x[0] = 4; lay_w[0] = 4;
    cfg_sync = 1; run("13 offset-window sync=1", 4000);

    // 14. no layer enabled at all: nothing to wait for, so the gate must not
    //     shut. A gate that waits for an empty set is a black screen.
    reset_all(); lay_en = 0; cfg_sync = 1; run("14 no-layers sync=1", 2000);

    // 15. a layer enabled with an illegal window. want_en is false for it, so
    //     it is not in act_en and must not hold the gate -- otherwise one bad
    //     SIZE register blacks the output out instead of latching ERR.CFG.
    reset_all(); lay_en = 1; lay_w[0] = 0; lay_h[0] = 0; cfg_sync = 1;
    run("15 cfg-bad sync=1", 2000);

    $finish;
  end
endmodule
