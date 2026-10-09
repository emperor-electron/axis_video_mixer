///////////////////////////////////////////////////////////////////
// Filename: mixer_seq_lib.sv
// Author  : Benjamin Tamayo
// Date    : 09/06/2026
// Purpose : Stimulus sequences for the video mixer testbench.
//
//           Included into mixer_tb_pkg; not a standalone compilation unit.
///////////////////////////////////////////////////////////////////


///////////////////////////////////////////////////////////////////
// One layer frame: (width / MIX_PPC) * height beats, TUSER on the very first,
// TLAST on the last beat of each line. This is the framing the DUT
// re-synchronises to, so it is also the framing the error tests deliberately
// corrupt.
//
// width is in PIXELS and must be a multiple of MIX_PPC -- the DUT rejects any
// other layer width, so a sequence that could send a partial beat would be
// generating stimulus the hardware is entitled to refuse.
//
// The corruption knobs exist because a geometry fault has to be provoked
// exactly, not approximately. Sending a frame that is merely "wrong" tends to
// trip several checks at once and proves nothing about which one fired.
///////////////////////////////////////////////////////////////////
class mixer_layer_frame_seq extends axi_stream_base_seq;

  int unsigned layer  = 0;
  int unsigned width  = 64;
  int unsigned height = 8;
  int unsigned frames = 1;

  // Pixel offset applied to the content function, so successive frames of an
  // animated source differ. The scoreboard is told the same number.
  int unsigned content_phase = 0;

  // Per-beat idle cycles, for pacing a source slower than the raster.
  int unsigned min_delay = 0;
  int unsigned max_delay = 0;

  // ---- Deliberate framing corruption, for the geometry error tests -------
  // Move TLAST off the configured last pixel of a line: the beat index within
  // the frame at which TLAST is asserted instead. -1 disables.
  int tlast_at = -1;
  // Assert TUSER mid-frame at this beat index. -1 disables.
  int tuser_at = -1;
  // Send this many beats instead of width*height. 0 means the natural count.
  int unsigned truncate_to = 0;

  `uvm_object_utils(mixer_layer_frame_seq)

  extern function new(string name = "mixer_layer_frame_seq");
  extern virtual task body();

endclass : mixer_layer_frame_seq


function mixer_layer_frame_seq::new(string name = "mixer_layer_frame_seq");
  super.new(name);
endfunction : new


task mixer_layer_frame_seq::body();
  int unsigned w_beats = width / MIX_PPC;

  if ((width % MIX_PPC) != 0) begin
    `uvm_fatal("SEQ", $sformatf("layer width %0d is not a multiple of PPC %0d", width, MIX_PPC))
  end

  for (int unsigned f = 0; f < frames; f++) begin
    int unsigned total = (truncate_to != 0) ? truncate_to : (w_beats * height);

    for (int unsigned i = 0; i < total; i++) begin
      axi_stream_seq_item beat;
      logic [MIX_PX_W-1:0] px;
      byte unsigned bytes[];
      bit want_last, want_user;
      int unsigned bx, y;
      int unsigned d;

      bx = i % w_beats;
      y  = i / w_beats;

      // Content is identical from frame to frame. Varying it per frame would
      // mean the scoreboard had to track which of the source's frames each
      // output frame drew from -- a second alignment model, sitting alongside
      // the one under test and just as capable of being wrong. That frames
      // actually advance is established by FRAME_COUNT and by SOF framing,
      // neither of which depends on the pixel values.
      want_last = (tlast_at >= 0) ? (i == int'(tlast_at)) : (bx == (w_beats - 1));
      want_user = (tuser_at >= 0) ? ((i == 0) || (i == int'(tuser_at))) : (i == 0);

      // Lane j of the beat is layer pixel bx*PPC + j, lane 0 in the low bytes.
      // A pixel is a whole number of bytes at every supported component width
      // -- 4, 5, 6 or 8 -- so a lane still starts on a byte boundary even when
      // the components inside it do not.
      bytes = new[MIX_PX_BYTES * MIX_PPC];
      for (int unsigned j = 0; j < MIX_PPC; j++) begin
        px = layer_pixel(layer, (bx * MIX_PPC) + j + content_phase, y + content_phase);
        // tdata[0] of a lane is its TDATA[7:0], which is the bottom of alpha.
        for (int unsigned k = 0; k < MIX_PX_BYTES; k++) begin
          bytes[j*MIX_PX_BYTES + k] = px[k*8+:8];
        end
      end

      d    = (max_delay > min_delay) ? ($urandom_range(max_delay, min_delay)) : min_delay;
      beat = new_beat($sformatf("l%0d_f%0d_%0d", layer, f, i));

      start_item(beat);
      beat.set_bytes(bytes);
      beat.tlast = want_last;
      beat.tuser = want_user;
      beat.delay = d;
      finish_item(beat);
    end
  end
endtask : body


///////////////////////////////////////////////////////////////////
// A layer that starts a frame and then simply stops, mid-line. Used to
// provoke a starve without any protocol violation at all: every beat sent is
// correct, there are just not enough of them in time.
///////////////////////////////////////////////////////////////////
class mixer_layer_partial_seq extends axi_stream_base_seq;

  int unsigned layer = 0;
  // Line width in PIXELS, as everywhere else. beats is in BEATS, so a caller
  // wanting "n lines" writes n * (width / MIX_PPC) -- see the starve test.
  int unsigned width = 64;
  int unsigned beats = 16;

  `uvm_object_utils(mixer_layer_partial_seq)

  extern function new(string name = "mixer_layer_partial_seq");
  extern virtual task body();

endclass : mixer_layer_partial_seq


function mixer_layer_partial_seq::new(string name = "mixer_layer_partial_seq");
  super.new(name);
endfunction : new


task mixer_layer_partial_seq::body();
  int unsigned w_beats = width / MIX_PPC;

  if ((width % MIX_PPC) != 0) begin
    `uvm_fatal("SEQ", $sformatf("layer width %0d is not a multiple of PPC %0d", width, MIX_PPC))
  end

  for (int unsigned i = 0; i < beats; i++) begin
    axi_stream_seq_item beat;
    logic [MIX_PX_W-1:0] px;
    byte unsigned bytes[];
    int unsigned bx = i % w_beats;
    int unsigned y  = i / w_beats;

    bytes = new[MIX_PX_BYTES * MIX_PPC];
    for (int unsigned j = 0; j < MIX_PPC; j++) begin
      px = layer_pixel(layer, (bx * MIX_PPC) + j, y);
      for (int unsigned k = 0; k < MIX_PX_BYTES; k++) begin
        bytes[j*MIX_PX_BYTES + k] = px[k*8+:8];
      end
    end

    beat = new_beat($sformatf("partial_l%0d_%0d", layer, i));
    start_item(beat);
    beat.set_bytes(bytes);
    beat.tlast = (bx == (w_beats - 1));
    beat.tuser = (i == 0);
    beat.delay = 0;
    finish_item(beat);
  end
endtask : body
