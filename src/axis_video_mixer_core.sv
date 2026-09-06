`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: axis_video_mixer_core.sv
// Author  : Benjamin Tamayo
// Date    : 09/06/2026
// Purpose : Datapath of the AXI4-Stream video mixer. Walks an output raster and
//           composites P_NUM_LAYERS input streams onto a background colour.
//
//           The output is the master, not the inputs. A raster counter free-runs
//           across the canvas and, at each pixel, asks every layer whose window
//           covers that pixel for one pixel. That inversion is what makes
//           picture-in-picture and tiling work from plain AXI4-Stream: layers
//           need no relationship to each other or to the output beyond their
//           own rectangle, and none of them has to span the canvas.
//
//           Composition is Porter-Duff "over" in port order, layer 0 nearest the
//           background. Fixed order rather than programmable keeps this a
//           straight pipelined cascade instead of a crossbar; z-order is chosen
//           by which stream is wired to which port.
//
//           Two properties are load bearing:
//
//           The output never stalls on an input. If a layer has no pixel ready
//           when its window opens, that layer is dropped for the remainder of
//           the frame, an error latches, and the raster carries on. A video sink
//           downstream loses lock if the stream pauses, so a starving source
//           must not be allowed to take the display down with it.
//
//           Geometry is double buffered. Position, size, enable and alpha are
//           latched at a frame boundary and only there, so software can move a
//           window whenever it likes without tearing the frame in flight.
//           Changing a layer's geometry costs that layer one frame: it flushes
//           and re-arms at its next input SOF, because everything buffered was
//           counted against the old size.
///////////////////////////////////////////////////////////////////

module axis_video_mixer_core
  import axis_video_mixer_pkg::*;
#(
    parameter int P_NUM_LAYERS = 4,
    parameter int P_FIFO_DEPTH = 2048,
    parameter bit P_OUT_HAS_ALPHA = 1'b1,
    // Derived; do not override. Present as a parameter only because a port
    // width cannot reference a localparam declared in the module body.
    parameter int P_OUT_W = P_OUT_HAS_ALPHA ? PX_W : RGB_W
) (
    input logic clk,
    input logic rst_n,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Shadow configuration, straight from the register block
    ////////////////////////////////////////////////////////////////////////////////////////////////
    input logic                    ctrl_en,
    input logic                    ctrl_soft_rst,
    input logic [            15:0] canvas_width,
    input logic [            15:0] canvas_height,
    input logic [            23:0] background_rgb,
    input logic [            31:0] stall_limit,
    input logic [P_NUM_LAYERS-1:0] lay_en,
    input logic [             7:0] lay_alpha    [P_NUM_LAYERS],
    input logic [P_NUM_LAYERS-1:0] lay_alpha_src,
    input logic [            15:0] lay_x        [P_NUM_LAYERS],
    input logic [            15:0] lay_y        [P_NUM_LAYERS],
    input logic [            15:0] lay_w        [P_NUM_LAYERS],
    input logic [            15:0] lay_h        [P_NUM_LAYERS],

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Status and error strobes back to the register block
    ////////////////////////////////////////////////////////////////////////////////////////////////
    output logic                    status_frame_active,
    output logic [            31:0] frame_count,
    output logic                    err_cfg_set,
    output logic                    err_starve_set,
    output logic                    err_geom_set,
    output logic                    err_src_stall_set,
    output logic                    err_out_stall_set,
    output logic [P_NUM_LAYERS-1:0] err_layer_set,
    output logic [P_NUM_LAYERS-1:0] lay_armed,
    output logic [P_NUM_LAYERS-1:0] lay_dropped,
    output logic [P_NUM_LAYERS-1:0] lay_cfg_bad,
    output logic [            15:0] lay_level    [P_NUM_LAYERS],

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Layer input streams, RGBA8
    ////////////////////////////////////////////////////////////////////////////////////////////////
    input  logic [P_NUM_LAYERS-1:0] s_axis_tvalid,
    output logic [P_NUM_LAYERS-1:0] s_axis_tready,
    input  logic [        PX_W-1:0] s_axis_tdata [P_NUM_LAYERS],
    input  logic [P_NUM_LAYERS-1:0] s_axis_tuser,
    input  logic [P_NUM_LAYERS-1:0] s_axis_tlast,

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Composited output stream
    ////////////////////////////////////////////////////////////////////////////////////////////////
    output logic               m_axis_tvalid,
    input  logic               m_axis_tready,
    output logic [P_OUT_W-1:0] m_axis_tdata,
    output logic               m_axis_tuser,  // SOF
    output logic               m_axis_tlast   // EOL
);
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Active configuration
  //
  // "Shadow" is what software has written; "active" is what this frame is being
  // drawn with. The two are only ever equalised at a frame boundary.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [15:0] act_w, act_h;
  logic [23:0] act_bg;
  logic        act_ok;  // the active canvas is usable

  logic [P_NUM_LAYERS-1:0] act_en;
  logic [             7:0] act_alpha[P_NUM_LAYERS];
  logic [P_NUM_LAYERS-1:0] act_asrc;
  logic [            15:0] act_x    [P_NUM_LAYERS];
  logic [            15:0] act_y    [P_NUM_LAYERS];
  logic [            15:0] act_w_l  [P_NUM_LAYERS];
  logic [            15:0] act_h_l  [P_NUM_LAYERS];
  // Window ends precomputed at the latch, so the per-pixel compare is a
  // magnitude comparison rather than an adder followed by one.
  logic [            16:0] act_xe   [P_NUM_LAYERS];
  logic [            16:0] act_ye   [P_NUM_LAYERS];

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Shadow validation
  //
  // Checked against what software wrote, not against what is active, because
  // the point is to refuse the new value before it ever becomes active. A
  // rejected configuration leaves the previous good one running.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic canvas_ok;
  logic [P_NUM_LAYERS-1:0] win_ok;
  logic [P_NUM_LAYERS-1:0] want_en;
  logic cfg_fault;

  assign canvas_ok = (canvas_width != 16'd0) && (canvas_height != 16'd0);

  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_validate
    assign win_ok[gi] = (lay_w[gi] != 16'd0) && (lay_h[gi] != 16'd0) &&
                        ((17'(lay_x[gi]) + 17'(lay_w[gi])) <= 17'(canvas_width)) &&
                        ((17'(lay_y[gi]) + 17'(lay_h[gi])) <= 17'(canvas_height));
    // A layer only counts as enabled once its window is also legal.
    assign want_en[gi]     = lay_en[gi] && win_ok[gi] && canvas_ok;
    assign lay_cfg_bad[gi] = lay_en[gi] && !(win_ok[gi] && canvas_ok);
  end

  assign cfg_fault = !canvas_ok || (|lay_cfg_bad);

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Output raster
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [15:0] out_x, out_y;
  logic        s0_valid, s0_sof, s0_eol, s0_eof;
  logic        pipe_en;
  logic        frame_boundary;
  logic        frame_latch;
  logic        soft_rst;

  assign soft_rst = ctrl_soft_rst;

  assign s0_valid = ctrl_en && act_ok;
  assign s0_sof   = (out_x == 16'd0) && (out_y == 16'd0);
  assign s0_eol   = (out_x == act_w - 16'd1);
  assign s0_eof   = s0_eol && (out_y == act_h - 16'd1);

  // Latch at the end of a frame -- and also whenever there is no frame to
  // protect. Double buffering exists to stop a mid-frame change from tearing
  // the picture; while the mixer is disabled or has no valid configuration
  // there is no picture, and holding changes back would be worse than useless.
  //
  // The !ctrl_en term is what makes the natural software order work at all.
  // A disabled mixer does not advance its raster, so it never reaches a frame
  // boundary; without this, a canvas written before EN was set could never
  // take effect, and the block would silently keep drawing at its reset size.
  assign frame_boundary = soft_rst || (pipe_en && s0_valid && s0_eof);
  assign frame_latch    = frame_boundary || !act_ok || !ctrl_en;

  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst || !ctrl_en) begin
      out_x <= 16'd0;
      out_y <= 16'd0;
    end else if (pipe_en && s0_valid) begin
      if (s0_eol) begin
        out_x <= 16'd0;
        out_y <= s0_eof ? 16'd0 : (out_y + 16'd1);
      end else begin
        out_x <= out_x + 16'd1;
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Frame-boundary latch
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [P_NUM_LAYERS-1:0] geo_changed;

  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_geo_change
    // Alpha is deliberately excluded: it changes the blend but not the pixel
    // accounting, so it can take effect without costing the layer a frame.
    assign geo_changed[gi] = (act_x[gi] != lay_x[gi]) || (act_y[gi] != lay_y[gi]) ||
                             (act_w_l[gi] != lay_w[gi]) || (act_h_l[gi] != lay_h[gi]) ||
                             (act_en[gi] != want_en[gi]);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      act_ok <= 1'b0;
      act_w  <= 16'd0;
      act_h  <= 16'd0;
      act_bg <= 24'd0;
      act_en <= '0;
      act_asrc <= '0;
      for (int i = 0; i < P_NUM_LAYERS; i++) begin
        act_alpha[i] <= 8'd0;
        act_x[i]     <= 16'd0;
        act_y[i]     <= 16'd0;
        act_w_l[i]   <= 16'd0;
        act_h_l[i]   <= 16'd0;
        act_xe[i]    <= 17'd0;
        act_ye[i]    <= 17'd0;
      end
    end else if (frame_latch) begin
      // A rejected canvas leaves the last good one in place rather than
      // stopping the output; ERR.CFG records that it was rejected.
      if (canvas_ok) begin
        act_w  <= canvas_width;
        act_h  <= canvas_height;
        act_ok <= 1'b1;
      end
      act_bg   <= background_rgb;
      act_en   <= want_en;
      act_asrc <= lay_alpha_src;
      for (int i = 0; i < P_NUM_LAYERS; i++) begin
        act_alpha[i] <= lay_alpha[i];
        act_x[i]     <= lay_x[i];
        act_y[i]     <= lay_y[i];
        act_w_l[i]   <= lay_w[i];
        act_h_l[i]   <= lay_h[i];
        act_xe[i]    <= 17'(lay_x[i]) + 17'(lay_w[i]);
        act_ye[i]    <= 17'(lay_y[i]) + 17'(lay_h[i]);
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Layer front ends
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [PX_W-1:0] lay_px   [P_NUM_LAYERS];
  logic [P_NUM_LAYERS-1:0] lay_px_valid;
  logic [P_NUM_LAYERS-1:0] lay_pop;
  logic [P_NUM_LAYERS-1:0] lay_flush;
  logic [P_NUM_LAYERS-1:0] lay_geom_err;
  logic [P_NUM_LAYERS-1:0] lay_src_stall;

  logic [P_NUM_LAYERS-1:0] in_win;
  logic [P_NUM_LAYERS-1:0] want_px;
  logic [P_NUM_LAYERS-1:0] starve;
  logic [P_NUM_LAYERS-1:0] lay_active;

  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_layer
    axis_mixer_layer #(
        .P_FIFO_DEPTH(P_FIFO_DEPTH)
    ) u_layer (
        .clk          (clk),
        .rst_n        (rst_n),
        .flush        (lay_flush[gi]),
        .enable       (act_en[gi]),
        .cfg_width    (act_w_l[gi]),
        .cfg_height   (act_h_l[gi]),
        .stall_limit  (stall_limit),
        .s_axis_tvalid(s_axis_tvalid[gi]),
        .s_axis_tready(s_axis_tready[gi]),
        .s_axis_tdata (s_axis_tdata[gi]),
        .s_axis_tuser (s_axis_tuser[gi]),
        .s_axis_tlast (s_axis_tlast[gi]),
        .px_data      (lay_px[gi]),
        .px_valid     (lay_px_valid[gi]),
        .px_pop       (lay_pop[gi]),
        .armed        (lay_armed[gi]),
        .geom_err     (lay_geom_err[gi]),
        .src_stall    (lay_src_stall[gi]),
        .level        (lay_level[gi])
    );

    assign in_win[gi] = act_en[gi] && (17'(out_x) >= 17'(act_x[gi])) &&
                        (17'(out_x) < act_xe[gi]) && (17'(out_y) >= 17'(act_y[gi])) &&
                        (17'(out_y) < act_ye[gi]);

    // Note lay_active, not lay_armed. A layer joins the composite only at a
    // frame boundary, never in the middle of one -- see the comment on
    // lay_active below for why that is a correctness requirement rather than
    // a nicety.
    //
    // A layer that has not yet seen its first SOF is simply absent, not
    // starving. Treating "no stream connected yet" as an error would latch a
    // fault on every frame between power-on and the first source coming up.
    assign want_px[gi] = in_win[gi] && lay_active[gi] && !lay_dropped[gi];

    assign lay_pop[gi] = want_px[gi] && lay_px_valid[gi] && pipe_en && s0_valid;
    assign starve[gi]  = want_px[gi] && !lay_px_valid[gi] && pipe_en && s0_valid;

    // A starved layer is desynchronised by definition -- the pixels still in its
    // FIFO belong to positions the raster has already passed -- so it is flushed
    // and re-armed rather than simply skipped.
    assign lay_flush[gi] = soft_rst || starve[gi] || (frame_latch && geo_changed[gi]);
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Joining the composite
  //
  // A layer becomes active only at a frame boundary, even though it arms as
  // soon as its stream delivers a SOF. The delay is what establishes alignment
  // between the layer's frame and the output's.
  //
  // Nothing else would. The mixer consumes a layer positionally -- one pixel
  // per output pixel inside the window -- so wherever the first pixel is
  // consumed is where the layer's top-left corner lands. A layer that armed
  // part way through an output frame would have its pixel zero consumed part
  // way along a line, and because it then supplies exactly as many pixels per
  // frame as the window consumes, that offset would never work itself out: the
  // layer would sit skewed by a fixed number of pixels for as long as it ran.
  //
  // Holding off until the boundary guarantees the FIFO head is pixel zero when
  // the window first opens, because nothing pops an inactive layer.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      lay_active <= '0;
    end else begin
      for (int i = 0; i < P_NUM_LAYERS; i++) begin
        if (frame_latch) begin
          // A layer being flushed this cycle is about to disarm, so it joins
          // at the following boundary rather than this one.
          lay_active[i] <= lay_armed[i] && want_en[i] && !lay_flush[i];
        end else if (starve[i] || lay_geom_err[i]) begin
          lay_active[i] <= 1'b0;
        end
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Dropped layers
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      lay_dropped <= '0;
    end else begin
      for (int i = 0; i < P_NUM_LAYERS; i++) begin
        if (starve[i]) lay_dropped[i] <= 1'b1;
      end
      // The clear is written after the sets, so a starve on the very last pixel
      // of a frame does not carry into the next one.
      if (frame_latch) lay_dropped <= '0;
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Blend cascade
  //
  // Stage 0 registers the raster, the background and every layer's pixel and
  // effective alpha. Stage k+1 then blends layer k onto the accumulator, one
  // layer per pipeline stage, so the combinational depth is a single multiply
  // regardless of how many layers are instantiated.
  //
  // Effective alpha is computed once, in its own stage, rather than inside each
  // blend stage. Both are a multiply; doing them together would put two in
  // series and halve the achievable clock.
  //
  // That alpha stage is also kept clear of the FIFO read. A layer's pixel comes
  // out of a block RAM, and a BRAM's clock-to-output is most of a cycle at this
  // frequency -- feeding it straight into the multiply left fourteen levels of
  // logic in whatever remained, and cost 0.27 ns of setup slack at 148.5 MHz.
  // Stage F does nothing but capture the read; the arithmetic starts from a
  // flip-flop in stage A.
  //
  // A layer that is not contributing arrives with an alpha of zero, and "over"
  // with alpha zero returns the accumulator bit-exactly. Absence needs no
  // special case anywhere in the cascade.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Stage F: the FIFO read, captured raw. No arithmetic here by design.
  logic [  PX_W-1:0] pxf_q [P_NUM_LAYERS];
  logic [P_NUM_LAYERS-1:0] popf_q;
  logic [       7:0] alphaf_q[P_NUM_LAYERS];
  logic [P_NUM_LAYERS-1:0] asrcf_q;
  logic [ RGB_W-1:0] bgf_q;
  logic              vf_q, soff_q, eolf_q, eoff_q;

  logic [ RGB_W-1:0] acc_q [P_NUM_LAYERS+1];
  logic [ RGB_W-1:0] lrgb_q[P_NUM_LAYERS+1][P_NUM_LAYERS];
  logic [       7:0] la_q  [P_NUM_LAYERS+1][P_NUM_LAYERS];
  logic              v_q   [P_NUM_LAYERS+1];
  logic              sof_q [P_NUM_LAYERS+1];
  logic              eol_q [P_NUM_LAYERS+1];
  logic              eof_q [P_NUM_LAYERS+1];

  assign pipe_en = m_axis_tready || !m_axis_tvalid;

  // Stage F -- capture only. The alpha and colour registers travel alongside the
  // pixel so that a frame boundary landing between the two stages cannot apply
  // the next frame's alpha to this frame's pixel.
  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      vf_q   <= 1'b0;
      popf_q <= '0;
    end else if (pipe_en) begin
      vf_q   <= s0_valid;
      soff_q <= s0_sof;
      eolf_q <= s0_eol;
      eoff_q <= s0_eof;
      bgf_q  <= act_bg;
      popf_q <= lay_pop;
      asrcf_q <= act_asrc;
      for (int i = 0; i < P_NUM_LAYERS; i++) begin
        pxf_q[i]    <= lay_px[i];
        alphaf_q[i] <= act_alpha[i];
      end
    end
  end

  // Stage A -- the alpha multiply, starting from flip-flops.
  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      v_q[0] <= 1'b0;
    end else if (pipe_en) begin
      v_q[0]   <= vf_q;
      sof_q[0] <= soff_q;
      eol_q[0] <= eolf_q;
      eof_q[0] <= eoff_q;
      acc_q[0] <= bgf_q;
      for (int i = 0; i < P_NUM_LAYERS; i++) begin
        lrgb_q[0][i] <= px_rgb(pxf_q[i]);
        la_q[0][i]   <= popf_q[i] ?
            effective_alpha(px_a(pxf_q[i]), alphaf_q[i], asrcf_q[i]) : 8'd0;
      end
    end
  end

  for (genvar gk = 0; gk < P_NUM_LAYERS; gk++) begin : g_blend
    always_ff @(posedge clk) begin
      if (!rst_n || soft_rst) begin
        v_q[gk+1] <= 1'b0;
      end else if (pipe_en) begin
        v_q[gk+1]   <= v_q[gk];
        sof_q[gk+1] <= sof_q[gk];
        eol_q[gk+1] <= eol_q[gk];
        eof_q[gk+1] <= eof_q[gk];
        acc_q[gk+1] <= blend_rgb(lrgb_q[gk][gk], acc_q[gk], la_q[gk][gk]);
        // Only entries at or above gk are still needed downstream; the rest
        // form a chain to nowhere and are trimmed during synthesis.
        for (int j = 0; j < P_NUM_LAYERS; j++) begin
          lrgb_q[gk+1][j] <= lrgb_q[gk][j];
          la_q[gk+1][j]   <= la_q[gk][j];
        end
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Output
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  assign m_axis_tvalid = v_q[P_NUM_LAYERS];
  assign m_axis_tuser  = sof_q[P_NUM_LAYERS];
  assign m_axis_tlast  = eol_q[P_NUM_LAYERS];

  if (P_OUT_HAS_ALPHA) begin : g_out_rgba
    // Everything below the top layer has been composited in, so the result is
    // opaque by construction.
    assign m_axis_tdata = {acc_q[P_NUM_LAYERS], OPAQUE};
  end else begin : g_out_rgb
    assign m_axis_tdata = acc_q[P_NUM_LAYERS];
  end

  logic out_beat;
  assign out_beat = m_axis_tvalid && m_axis_tready;

  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      frame_count         <= 32'd0;
      status_frame_active <= 1'b0;
    end else begin
      if (out_beat && eof_q[P_NUM_LAYERS]) frame_count <= frame_count + 32'd1;
      if (out_beat) begin
        if (sof_q[P_NUM_LAYERS]) status_frame_active <= 1'b1;
        else if (eof_q[P_NUM_LAYERS]) status_frame_active <= 1'b0;
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Downstream stall watchdog
  //
  // The mirror of the per-layer source watchdog. Between them, a stuck
  // FRAME_COUNT can be attributed to the right side of the pipeline instead of
  // being merely observed.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [31:0] out_stall_cnt;

  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      out_stall_cnt     <= 32'd0;
      err_out_stall_set <= 1'b0;
    end else begin
      err_out_stall_set <= 1'b0;
      if (m_axis_tvalid && !m_axis_tready) begin
        if (stall_limit != 32'd0 && out_stall_cnt == stall_limit - 32'd1) begin
          err_out_stall_set <= 1'b1;
          out_stall_cnt     <= 32'd0;
        end else begin
          out_stall_cnt <= out_stall_cnt + 32'd1;
        end
      end else begin
        out_stall_cnt <= 32'd0;
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Error aggregation
  //
  // ERR.CFG latches once per frame boundary rather than continuously. A level
  // would keep re-setting the bit -- corsair gives the hardware set priority
  // over the software clear, by design, so an error is never lost -- and
  // software could then never clear it while the bad value remained. Once per
  // frame stays clearable, and the live view is in L<i>_STATUS.CFG_BAD.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  assign err_cfg_set       = frame_boundary && cfg_fault;
  assign err_starve_set    = |starve;
  assign err_geom_set      = |lay_geom_err;
  assign err_src_stall_set = |lay_src_stall;

  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_err_layer
    assign err_layer_set[gi] = starve[gi] || lay_geom_err[gi] || lay_src_stall[gi] ||
                               (frame_boundary && lay_cfg_bad[gi]);
  end

`ifdef SIMULATION
  // Procedural rather than concurrent, for the reason set out in
  // axis_mixer_fifo.sv: both properties below are functions of combinational
  // signals, and XSIM evaluates concurrent assertions on those before the
  // network resettles. Sampling at the clock edge checks what the hardware
  // actually sees.
  logic [15:0] chk_prev_x, chk_prev_y;
  logic        chk_raster_armed;

  logic [P_OUT_W-1:0] chk_prev_tdata;
  logic               chk_prev_tuser, chk_prev_tlast;
  logic               chk_was_stalled;

  always_ff @(posedge clk) begin
    if (!rst_n || soft_rst) begin
      chk_raster_armed <= 1'b0;
      chk_was_stalled  <= 1'b0;
    end else begin
      // The whole point of the starve handling is that the output keeps
      // running. If the raster ever stops advancing while enabled and
      // unstalled, the design has failed at its primary job. A 1x1 canvas is
      // excluded because its counters legitimately never change.
      if (chk_raster_armed && (out_x == chk_prev_x) && (out_y == chk_prev_y)) begin
        $error("RTL-ASSERT axis_video_mixer_core: raster stalled while enabled and not backpressured");
      end
      chk_raster_armed <= s0_valid && pipe_en && ((act_w > 16'd1) || (act_h > 16'd1));
      chk_prev_x       <= out_x;
      chk_prev_y       <= out_y;

      // TDATA, TUSER and TLAST must hold, and TVALID must stay high, while a
      // beat is being offered and refused.
      if (chk_was_stalled) begin
        if (!m_axis_tvalid) begin
          $error("RTL-ASSERT axis_video_mixer_core: TVALID dropped during a stall");
        end else if ({m_axis_tdata, m_axis_tuser, m_axis_tlast} !==
                     {chk_prev_tdata, chk_prev_tuser, chk_prev_tlast}) begin
          $error("RTL-ASSERT axis_video_mixer_core: output payload changed during a stall");
        end
      end
      chk_was_stalled <= m_axis_tvalid && !m_axis_tready;
      chk_prev_tdata  <= m_axis_tdata;
      chk_prev_tuser  <= m_axis_tuser;
      chk_prev_tlast  <= m_axis_tlast;
    end
  end

`endif

endmodule
