///////////////////////////////////////////////////////////////////
// Filename: mixer_scoreboard.sv
// Author  : Benjamin Tamayo
// Date    : 09/06/2026
// Purpose : Golden model and checker for the composited output stream.
//
//           Included into mixer_tb_pkg; not a standalone compilation unit.
///////////////////////////////////////////////////////////////////
//
// It subscribes to the output monitor's *beat* analysis port rather than the
// packet port, for the same reason the TPG scoreboard does: TUSER carries SOF
// and axi_stream_packet::do_compare() ignores TUSER, so framing can only be
// checked one beat at a time.
//
// The model does not observe the layer inputs at all. It recomputes their
// content from layer_pixel(), the same function the stimulus draws from, which
// is what lets it predict a composite without reconstructing N input framings
// and their independent flow control. The price is that the test has to tell
// the scoreboard what it configured -- hence set_layer() -- and that price is
// worth paying, because the alternative model would have to reimplement the
// very starve and resynchronisation logic it is supposed to be checking.

class mixer_scoreboard extends uvm_subscriber #(axi_stream_seq_item);

  `uvm_component_utils(mixer_scoreboard)

  // ---- Configuration, set by the test before the run phase ------------
  int unsigned num_layers = 4;
  int unsigned canvas_w = 64;
  int unsigned canvas_h = 8;
  logic [23:0] background = 24'h000000;

  bit lay_en[MIX_MAX_LAYERS];
  int unsigned lay_x[MIX_MAX_LAYERS];
  int unsigned lay_y[MIX_MAX_LAYERS];
  int unsigned lay_w[MIX_MAX_LAYERS];
  int unsigned lay_h[MIX_MAX_LAYERS];
  logic [7:0] lay_alpha[MIX_MAX_LAYERS];
  bit lay_alpha_src[MIX_MAX_LAYERS];
  int unsigned lay_phase[MIX_MAX_LAYERS];

  // Layers the test knows will not be delivering pixels this run. They
  // composite as absent rather than as content, which is what the DUT does
  // for a layer that has never seen a SOF.
  bit lay_absent[MIX_MAX_LAYERS];

  // Directed error tests deliberately desynchronise a layer, at which point
  // predicting pixels stops being meaningful. Framing is still checked.
  bit check_pixels = 1'b1;

  // The DUT is built with alpha on the output, so a pixel is four components
  // and the lowest one must be at full scale on every beat.
  bit out_has_alpha = 1'b1;

  // ---- Running state ---------------------------------------------------
  int unsigned x = 0;
  int unsigned y = 0;
  bit seen_sof = 1'b0;

  int unsigned frames_seen = 0;
  // Frames in which pixels were actually compared. A test that checks nothing
  // passes just as quietly as one that checks everything, so this is reported
  // and asserted on rather than left implicit.
  int unsigned frames_checked = 0;
  int unsigned beats_seen = 0;
  int unsigned pixel_errors = 0;
  int unsigned framing_errors = 0;

  // The window of frames pixels are compared over, as [check_from, check_until).
  //
  // The bounds live here rather than in the test because only this component
  // sees frame boundaries exactly. A test polling frames_seen and clearing a
  // flag samples at whatever granularity its loop runs at, and will always
  // catch part of the frame it meant to exclude -- which then reports the
  // test's own end as a pixel fault.
  //
  // check_from lets a test skip a frame it knows is legitimately wrong: after a
  // geometry change the affected layer flushes and costs a frame by design.
  // check_until closes the window before the sources run out and the mixer
  // starts drawing background over starved layers.
  int unsigned check_from_frame = 0;
  int unsigned check_until_frame = 32'hFFFF_FFFF;

  extern function new(string name = "mixer_scoreboard", uvm_component parent = null);
  extern virtual function void write(axi_stream_seq_item t);
  extern virtual function void report_phase(uvm_phase phase);

  extern function void set_layer(int unsigned i, bit en, int unsigned lx, int unsigned ly,
                                 int unsigned lw, int unsigned lh, logic [7:0] alpha,
                                 bit alpha_src = 1'b0, int unsigned phase = 0);
  extern function logic [MIX_RGB_W-1:0] expected_rgb(int unsigned px, int unsigned py);

endclass : mixer_scoreboard


function mixer_scoreboard::new(string name = "mixer_scoreboard", uvm_component parent = null);
  super.new(name, parent);
  foreach (lay_en[i]) begin
    lay_en[i]        = 1'b0;
    lay_absent[i]    = 1'b0;
    lay_alpha[i]     = 8'hFF;
    lay_alpha_src[i] = 1'b0;
    lay_phase[i]     = 0;
  end
endfunction : new


function void mixer_scoreboard::set_layer(int unsigned i, bit en, int unsigned lx,
                                          int unsigned ly, int unsigned lw, int unsigned lh,
                                          logic [7:0] alpha, bit alpha_src = 1'b0,
                                          int unsigned phase = 0);
  lay_en[i]        = en;
  lay_x[i]         = lx;
  lay_y[i]         = ly;
  lay_w[i]         = lw;
  lay_h[i]         = lh;
  lay_alpha[i]     = alpha;
  lay_alpha_src[i] = alpha_src;
  lay_phase[i]     = phase;
endfunction : set_layer


///////////////////////////////////////////////////////////////////
// The composite, bottom up. Layer 0 is nearest the background and the
// highest-numbered enabled layer is on top, which is the port order the RTL
// cascade fixes -- so an off-by-one in either direction shows up as a colour
// error on every overlapped pixel rather than as a subtle shift.
///////////////////////////////////////////////////////////////////
function logic [MIX_RGB_W-1:0] mixer_scoreboard::expected_rgb(int unsigned px,
                                                              int unsigned py);
  // The background register is 8 bits per component whatever the component
  // width is, and the datapath expands it as it latches -- so the model has to
  // expand it too, or every uncovered pixel would miscompare at 10, 12 and 16
  // bits while being right at 8.
  logic [MIX_RGB_W-1:0] acc = gold_rgb_up(background);

  for (int unsigned i = 0; i < num_layers; i++) begin
    if (!lay_en[i] || lay_absent[i]) continue;
    if (px < lay_x[i] || px >= (lay_x[i] + lay_w[i])) continue;
    if (py < lay_y[i] || py >= (lay_y[i] + lay_h[i])) continue;

    begin
      logic [MIX_PX_W-1:0] p;
      logic [MIX_CH_W-1:0] a;
      logic [MIX_CH_W-1:0] ga;
      p  = layer_pixel(i, (px - lay_x[i]) + lay_phase[i], (py - lay_y[i]) + lay_phase[i]);
      ga = gold_up(lay_alpha[i]);
      a  = lay_alpha_src[i] ? ga : gold_mul_max(p[MIX_CH_W-1:0], ga);
      acc = gold_blend_rgb(p[MIX_PX_W-1-:MIX_RGB_W], acc, a);
    end
  end

  return acc;
endfunction : expected_rgb


function void mixer_scoreboard::write(axi_stream_seq_item t);
  bit exp_sof, exp_eol;
  logic [MIX_RGB_W-1:0] got_rgb, exp_rgb;
  logic [MIX_CH_W-1:0] got_alpha;
  // The beat, reassembled as bits. Lanes are byte-aligned but the components
  // inside a pixel are not at 10 or 12 bits, so the comparison has to work in
  // bits rather than in the UVC's bytes.
  logic [MIX_DATA_BYTES*8-1:0] beat_bits;
  int unsigned w_beats;
  int unsigned bx;
  int unsigned lane_x;

  beats_seen++;

  beat_bits = '0;
  for (int unsigned k = 0; k < MIX_DATA_BYTES; k++) beat_bits[k*8+:8] = t.tdata[k];

  // The model still walks the raster in PIXELS -- x is a pixel coordinate --
  // because that is the coordinate expected_rgb() and the layer windows are
  // expressed in. Only the framing checks and the byte extraction work in
  // beats, which is the smallest change that keeps the model independent of
  // how the DUT happens to pack its output.
  w_beats = canvas_w / MIX_PPC;
  bx      = x / MIX_PPC;

  // ---- Framing -------------------------------------------------------
  // SOF must appear on the first pixel of a frame and nowhere else. Checked
  // before anything else because every pixel comparison below depends on the
  // model and the DUT agreeing on where in the raster this beat sits.
  exp_sof = (x == 0) && (y == 0);
  exp_eol = (bx == (w_beats - 1));

  if (!seen_sof) begin
    if (!t.tuser[0]) begin
      framing_errors++;
      `uvm_error("SOF", "first beat of the stream did not carry TUSER (SOF)")
    end
    seen_sof = 1'b1;
  end else if (t.tuser[0] != exp_sof) begin
    framing_errors++;
    `uvm_error("SOF", $sformatf("TUSER=%0b at (%0d,%0d), expected %0b", t.tuser[0], x, y,
                                exp_sof))
  end

  if (t.tlast != exp_eol) begin
    framing_errors++;
    `uvm_error("EOL", $sformatf({"TLAST=%0b at beat %0d of line %0d, expected %0b (line is %0d ",
                                 "pixels = %0d beats at PPC %0d)"}, t.tlast, bx, y, exp_eol,
                                canvas_w, w_beats, MIX_PPC))
  end

  // ---- Pixel content --------------------------------------------------
  // One beat carries MIX_PPC pixels, lane 0 in the low bits. Every lane is
  // checked: a fault confined to one lane -- a mis-indexed replica of the
  // cascade, say -- would otherwise show up only as a vertical stripe that a
  // lane-0-only check would miss entirely.
  for (int unsigned j = 0; j < MIX_PPC; j++) begin
    lane_x = (bx * MIX_PPC) + j;

    if (out_has_alpha) begin
      logic [MIX_PX_W-1:0] p;
      p         = beat_bits[j*MIX_PX_W+:MIX_PX_W];
      got_alpha = p[MIX_CH_W-1:0];
      got_rgb   = p[MIX_PX_W-1-:MIX_RGB_W];
      if (got_alpha !== MIX_CH_W'(MIX_MAX)) begin
        pixel_errors++;
        if (pixel_errors <= 20) begin
          `uvm_error("ALPHA", $sformatf({"output alpha at (%0d,%0d) lane %0d is 0x%h, expected ",
                                         "0x%h (full scale)"}, lane_x, y, j, got_alpha,
                                        MIX_CH_W'(MIX_MAX)))
        end
      end
    end else begin
      got_rgb = beat_bits[j*MIX_RGB_W+:MIX_RGB_W];
    end

    if (check_pixels && (frames_seen >= check_from_frame) &&
        (frames_seen < check_until_frame)) begin
      exp_rgb = expected_rgb(lane_x, y);
      if (got_rgb !== exp_rgb) begin
        pixel_errors++;
        // Capped so a systematic fault does not bury the log; the count in the
        // report is the honest total.
        if (pixel_errors <= 20) begin
          `uvm_error("PIXEL", $sformatf("(%0d,%0d) lane %0d frame %0d: got 0x%h, expected 0x%h",
                                        lane_x, y, j, frames_seen, got_rgb, exp_rgb))
        end
      end
    end
  end

  // ---- Advance the raster, one whole beat ------------------------------
  if (bx == (w_beats - 1)) begin
    x = 0;
    if (y == (canvas_h - 1)) begin
      y = 0;
      if (check_pixels && (frames_seen >= check_from_frame) &&
          (frames_seen < check_until_frame)) frames_checked++;
      frames_seen++;
    end else begin
      y++;
    end
  end else begin
    x += MIX_PPC;
  end
endfunction : write


function void mixer_scoreboard::report_phase(uvm_phase phase);
  super.report_phase(phase);
  `uvm_info("SB", $sformatf(
            "%0d beats, %0d complete frames (%0d pixel-checked), %0d pixel errors, %0d framing errors",
            beats_seen, frames_seen, frames_checked, pixel_errors, framing_errors), UVM_LOW)

  if (beats_seen == 0) `uvm_error("SB", "no output beats were observed at all")
endfunction : report_phase
