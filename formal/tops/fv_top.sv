`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_top.sv
// Purpose : Formal top for axis_video_mixer: the whole block, register file
//           included, against a free AXI4-Lite master, free sources and a free
//           sink.
//
//           What this adds over fv_core.sby is everything between software and
//           the datapath -- the generated register block, the adapter that
//           flattens it, and the flattening of the stream ports. Two classes
//           of bug live only here:
//
//             Protocol bugs on the control port. The register block is
//             generated and nobody reads it, so a response channel that drops
//             VALID before READY would ship. It wedges a processor bus rather
//             than producing a wrong picture, which makes it both more serious
//             and harder to attribute. See props/fv_axil_props.sv.
//
//             Wiring bugs at the stream boundary. The top level brings out a
//             named port per signal per stream -- eight streams, nothing
//             packed -- and gathers them into the arrays the datapath indexes.
//             That gathering is eight hand-written assigns per field, which is
//             exactly the shape of code a transposed index survives: give
//             layer 1 layer 0's stream and the result is a plausible picture,
//             two windows in the right places showing the wrong contents, and
//             a single-source bring-up test cannot see it at all. a_wire_*
//             below is the check, and it is why this file enumerates the
//             port names a second time.
//
//           The datapath properties are NOT re-run here: fv_core.sby covers
//           them with the configuration free, which is a strictly harsher
//           environment than one reached through a register file. What is
//           checked here is that software can reach the configuration at all,
//           and that the path between is wired correctly.
///////////////////////////////////////////////////////////////////

module fv_top
  import axis_video_mixer_pkg::*;
#(
    // Four by default, and eight in the wire task. The register map is
    // generated for MAX_LAYERS and the adapter accepts anything up to it, so
    // unlike the old four-layer-only map this is now a free choice -- which is
    // itself worth proving at both ends, because the tie-off of the streams a
    // build does not implement only exists when P_NUM_LAYERS < MAX_LAYERS.
    parameter int P_NUM_LAYERS = 4,
    // Two beats, the minimum the top level's own elaboration check allows.
    // Nothing in this file is about buffering.
    parameter int P_FIFO_DEPTH = 2,
    parameter bit P_OUT_HAS_ALPHA = 1'b1,
    parameter int P_PPC = 1,
    parameter int P_AXIL_ADDR_W = 12,
    // 1: check the two bounded properties below -- no unsolicited response,
    // and bounded response latency. Both are built on transaction counters,
    // and an arbitrary k-induction start state can put a counter anywhere, so
    // neither can be anything but a BMC result. The prove task turns them off
    // rather than reporting an induction failure that says nothing about the
    // design.
    parameter bit FV_CHECK_BOUNDED = 1'b1,
    // Component width. Nothing in this file is about pixel values -- the
    // datapath proofs own those -- so it only has to be a legal width for the
    // DUT to elaborate. The wire properties below compare whole beats, so they
    // are the one place it matters, and they hold at any width.
    parameter int P_CH_W = 8,
    // Derived; do not override.
    parameter int P_PX_W = 4 * P_CH_W,
    parameter int P_RGB_W = 3 * P_CH_W,
    parameter int P_PX_OUT_W = P_OUT_HAS_ALPHA ? P_PX_W : P_RGB_W,
    parameter int P_OUT_W = P_PPC * P_PX_OUT_W,
    parameter int P_BEAT_W = P_PPC * P_PX_W
) (
    input logic clk,

    // Free AXI4-Lite master. No ordering, no politeness, no limit on how many
    // channels move at once.
    input logic [P_AXIL_ADDR_W-1:0] s_axil_awaddr,
    input logic [              2:0] s_axil_awprot,
    input logic                     s_axil_awvalid,
    input logic [             31:0] s_axil_wdata,
    input logic [              3:0] s_axil_wstrb,
    input logic                     s_axil_wvalid,
    input logic                     s_axil_bready,
    input logic [P_AXIL_ADDR_W-1:0] s_axil_araddr,
    input logic [              2:0] s_axil_arprot,
    input logic                     s_axil_arvalid,
    input logic                     s_axil_rready,

    // Free sources. One named port per signal per stream, all MAX_LAYERS of
    // them, exactly as the top level presents them -- including the ones a
    // build with fewer layers does not implement, because "an unimplemented
    // stream is backpressured and ignored" is one of the properties below.
    input logic                s_axis0_tvalid,
    input logic [P_BEAT_W-1:0] s_axis0_tdata,
    input logic                s_axis0_tuser,
    input logic                s_axis0_tlast,

    input logic                s_axis1_tvalid,
    input logic [P_BEAT_W-1:0] s_axis1_tdata,
    input logic                s_axis1_tuser,
    input logic                s_axis1_tlast,

    input logic                s_axis2_tvalid,
    input logic [P_BEAT_W-1:0] s_axis2_tdata,
    input logic                s_axis2_tuser,
    input logic                s_axis2_tlast,

    input logic                s_axis3_tvalid,
    input logic [P_BEAT_W-1:0] s_axis3_tdata,
    input logic                s_axis3_tuser,
    input logic                s_axis3_tlast,

    input logic                s_axis4_tvalid,
    input logic [P_BEAT_W-1:0] s_axis4_tdata,
    input logic                s_axis4_tuser,
    input logic                s_axis4_tlast,

    input logic                s_axis5_tvalid,
    input logic [P_BEAT_W-1:0] s_axis5_tdata,
    input logic                s_axis5_tuser,
    input logic                s_axis5_tlast,

    input logic                s_axis6_tvalid,
    input logic [P_BEAT_W-1:0] s_axis6_tdata,
    input logic                s_axis6_tuser,
    input logic                s_axis6_tlast,

    input logic                s_axis7_tvalid,
    input logic [P_BEAT_W-1:0] s_axis7_tdata,
    input logic                s_axis7_tuser,
    input logic                s_axis7_tlast,

    // Free sink.
    input logic m_axis_tready
);
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Modelled reset
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic rst_n;
  logic fv_in_reset = 1'b1;
  always_ff @(posedge clk) fv_in_reset <= 1'b0;
  assign rst_n = !fv_in_reset;

  logic s_axil_awready, s_axil_wready, s_axil_bvalid, s_axil_arready, s_axil_rvalid;
  logic [1:0] s_axil_bresp, s_axil_rresp;
  logic [31:0] s_axil_rdata;
  logic s_axis0_tready;
  logic s_axis1_tready;
  logic s_axis2_tready;
  logic s_axis3_tready;
  logic s_axis4_tready;
  logic s_axis5_tready;
  logic s_axis6_tready;
  logic s_axis7_tready;
  logic m_axis_tvalid, m_axis_tuser, m_axis_tlast;
  logic [P_OUT_W-1:0] m_axis_tdata;
  logic irq;

  axis_video_mixer #(
      .P_NUM_LAYERS   (P_NUM_LAYERS),
      .P_FIFO_DEPTH   (P_FIFO_DEPTH),
      .P_OUT_HAS_ALPHA(P_OUT_HAS_ALPHA),
      .P_PPC          (P_PPC),
      .P_CH_W         (P_CH_W),
      .P_AXIL_ADDR_W  (P_AXIL_ADDR_W)
  ) dut (
      .clk  (clk),
      .rst_n(rst_n),

      .s_axil_awaddr (s_axil_awaddr),
      .s_axil_awprot (s_axil_awprot),
      .s_axil_awvalid(s_axil_awvalid),
      .s_axil_awready(s_axil_awready),
      .s_axil_wdata  (s_axil_wdata),
      .s_axil_wstrb  (s_axil_wstrb),
      .s_axil_wvalid (s_axil_wvalid),
      .s_axil_wready (s_axil_wready),
      .s_axil_bresp  (s_axil_bresp),
      .s_axil_bvalid (s_axil_bvalid),
      .s_axil_bready (s_axil_bready),
      .s_axil_araddr (s_axil_araddr),
      .s_axil_arprot (s_axil_arprot),
      .s_axil_arvalid(s_axil_arvalid),
      .s_axil_arready(s_axil_arready),
      .s_axil_rdata  (s_axil_rdata),
      .s_axil_rresp  (s_axil_rresp),
      .s_axil_rvalid (s_axil_rvalid),
      .s_axil_rready (s_axil_rready),

      .s_axis0_tvalid(s_axis0_tvalid),
      .s_axis0_tready(s_axis0_tready),
      .s_axis0_tdata (s_axis0_tdata),
      .s_axis0_tuser (s_axis0_tuser),
      .s_axis0_tlast (s_axis0_tlast),

      .s_axis1_tvalid(s_axis1_tvalid),
      .s_axis1_tready(s_axis1_tready),
      .s_axis1_tdata (s_axis1_tdata),
      .s_axis1_tuser (s_axis1_tuser),
      .s_axis1_tlast (s_axis1_tlast),

      .s_axis2_tvalid(s_axis2_tvalid),
      .s_axis2_tready(s_axis2_tready),
      .s_axis2_tdata (s_axis2_tdata),
      .s_axis2_tuser (s_axis2_tuser),
      .s_axis2_tlast (s_axis2_tlast),

      .s_axis3_tvalid(s_axis3_tvalid),
      .s_axis3_tready(s_axis3_tready),
      .s_axis3_tdata (s_axis3_tdata),
      .s_axis3_tuser (s_axis3_tuser),
      .s_axis3_tlast (s_axis3_tlast),

      .s_axis4_tvalid(s_axis4_tvalid),
      .s_axis4_tready(s_axis4_tready),
      .s_axis4_tdata (s_axis4_tdata),
      .s_axis4_tuser (s_axis4_tuser),
      .s_axis4_tlast (s_axis4_tlast),

      .s_axis5_tvalid(s_axis5_tvalid),
      .s_axis5_tready(s_axis5_tready),
      .s_axis5_tdata (s_axis5_tdata),
      .s_axis5_tuser (s_axis5_tuser),
      .s_axis5_tlast (s_axis5_tlast),

      .s_axis6_tvalid(s_axis6_tvalid),
      .s_axis6_tready(s_axis6_tready),
      .s_axis6_tdata (s_axis6_tdata),
      .s_axis6_tuser (s_axis6_tuser),
      .s_axis6_tlast (s_axis6_tlast),

      .s_axis7_tvalid(s_axis7_tvalid),
      .s_axis7_tready(s_axis7_tready),
      .s_axis7_tdata (s_axis7_tdata),
      .s_axis7_tuser (s_axis7_tuser),
      .s_axis7_tlast (s_axis7_tlast),

      .m_axis_tvalid(m_axis_tvalid),
      .m_axis_tready(m_axis_tready),
      .m_axis_tdata (m_axis_tdata),
      .m_axis_tuser (m_axis_tuser),
      .m_axis_tlast (m_axis_tlast),

      .irq(irq)
  );

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // The stream boundary
  //
  // Stream i's five named ports must reach layer i of the datapath and nothing
  // else. A transposed index in the top level's gather gives layer 1 layer 0's
  // stream, which composites into a picture that looks entirely plausible --
  // two windows in the right places showing the wrong contents -- and which a
  // single-source bring-up test cannot see at all.
  //
  // Checked against what the core actually receives, through a hierarchical
  // reference. That is what makes this more than two copies of the same list
  // agreeing with each other: the right-hand side is the port, the left-hand
  // side is the signal arriving at the layer instance, and everything the top
  // level does in between is under test. The enumeration below is this file's
  // own, written out a second time on purpose.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic [MAX_LAYERS-1:0] fv_tvalid;
  logic [MAX_LAYERS-1:0] fv_tuser;
  logic [MAX_LAYERS-1:0] fv_tlast;
  logic [MAX_LAYERS-1:0] fv_tready;
  logic [  P_BEAT_W-1:0] fv_tdata [MAX_LAYERS];

  assign fv_tvalid = {
    s_axis7_tvalid,
    s_axis6_tvalid,
    s_axis5_tvalid,
    s_axis4_tvalid,
    s_axis3_tvalid,
    s_axis2_tvalid,
    s_axis1_tvalid,
    s_axis0_tvalid
  };

  assign fv_tuser = {
    s_axis7_tuser,
    s_axis6_tuser,
    s_axis5_tuser,
    s_axis4_tuser,
    s_axis3_tuser,
    s_axis2_tuser,
    s_axis1_tuser,
    s_axis0_tuser
  };

  assign fv_tlast = {
    s_axis7_tlast,
    s_axis6_tlast,
    s_axis5_tlast,
    s_axis4_tlast,
    s_axis3_tlast,
    s_axis2_tlast,
    s_axis1_tlast,
    s_axis0_tlast
  };

  assign fv_tready = {
    s_axis7_tready,
    s_axis6_tready,
    s_axis5_tready,
    s_axis4_tready,
    s_axis3_tready,
    s_axis2_tready,
    s_axis1_tready,
    s_axis0_tready
  };

  assign fv_tdata[0] = s_axis0_tdata;
  assign fv_tdata[1] = s_axis1_tdata;
  assign fv_tdata[2] = s_axis2_tdata;
  assign fv_tdata[3] = s_axis3_tdata;
  assign fv_tdata[4] = s_axis4_tdata;
  assign fv_tdata[5] = s_axis5_tdata;
  assign fv_tdata[6] = s_axis6_tdata;
  assign fv_tdata[7] = s_axis7_tdata;

  for (genvar gi = 0; gi < P_NUM_LAYERS; gi++) begin : g_wire
    always_ff @(posedge clk) begin
      if (rst_n) begin
        a_wire_tvalid : assert (dut.u_core.s_axis_tvalid[gi] == fv_tvalid[gi]);
        a_wire_tdata : assert (dut.u_core.s_axis_tdata[gi] == fv_tdata[gi]);
        a_wire_tuser : assert (dut.u_core.s_axis_tuser[gi] == fv_tuser[gi]);
        a_wire_tlast : assert (dut.u_core.s_axis_tlast[gi] == fv_tlast[gi]);
        a_wire_tready : assert (fv_tready[gi] == dut.u_core.s_axis_tready[gi]);
      end
    end
  end

  // A stream this build does not implement must be backpressured for good.
  // High would consume beats and discard them, which looks like a working
  // connection and produces a black layer; low stalls the producer at once.
  // Vacuous at P_NUM_LAYERS = MAX_LAYERS, so the tasks come in pairs: the
  // default four-layer ones prove the tie-off, and the eight-layer one proves
  // the wiring of every port the block brings out.
  for (genvar gi = P_NUM_LAYERS; gi < MAX_LAYERS; gi++) begin : g_wire_unused
    always_ff @(posedge clk) begin
      if (rst_n) begin
        a_unused_stream_stalled : assert (!fv_tready[gi]);
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Software can reach the datapath
  //
  // Every safety property in this suite is satisfied by a block that ignores
  // its register file entirely. These are the ones that are not: a written
  // value arrives, and a configuration once written is acted on.
  //
  // Written as covers rather than assertions, deliberately. "A write to
  // CANVAS lands in canvas_width" is a property of the generated address
  // decode, and restating the decode in the checker would prove only that the
  // two copies agree. A cover says the reachable behaviour exists -- the
  // solver has to find a write sequence that produces a running mixer -- and
  // that is the part worth knowing, because it is what a bad decode or a
  // stuck-at register would make unreachable.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  logic fv_saw_err;
  always_ff @(posedge clk) begin
    if (!rst_n) fv_saw_err <= 1'b0;
    else if (|dut.u_csr.err_ff) fv_saw_err <= 1'b1;
  end

  always_ff @(posedge clk) begin
    if (rst_n) begin
      // Software wrote EN and a legal canvas, and the datapath is drawing.
      c_sw_enables : cover (dut.ctrl_en && dut.u_core.act_ok && m_axis_tvalid);

      // Software wrote a non-reset canvas and it became the active one.
      c_sw_canvas : cover (dut.u_core.act_ok && (dut.u_core.act_w > 16'd1) &&
                           (dut.u_core.act_h > 16'd1));

      // Software enabled a layer and it joined the composite.
      c_sw_layer_active : cover (|dut.u_core.lay_active);

      // Software wrote a background colour and it reached the cascade.
      c_sw_background : cover (dut.u_core.act_bg != 24'd0);

      // A full output frame came out.
      c_frame_out : cover (m_axis_tvalid && m_axis_tready && m_axis_tlast &&
                           dut.u_core.eof_q[P_NUM_LAYERS]);

      // The hardware raised an error bit and software cleared it -- the
      // write-one-to-clear path. That is where a generated block's
      // set-beats-clear priority could go wrong in the direction that costs
      // software the clear entirely, leaving ERR and irq stuck for good.
      c_sw_clears_err : cover (fv_saw_err && (dut.u_csr.err_ff == '0));
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // One transaction in flight at a time
  //
  // The only behavioural assumption in this file, and it is a real constraint
  // on the design rather than a convenience: axis_video_mixer_csr keeps ONE
  // captured write address, in wr_addr_q with wr_addr_held, taken on the AW
  // handshake and released on the B handshake. With two writes in flight the
  // second address overwrites the first, and the write-one-to-clear decode for
  // ERR then applies to the wrong register.
  //
  // AXI4-Lite permits multiple outstanding transactions, so this is worth
  // being explicit about: the block is safe behind any ordinary AXI4-Lite
  // master or interconnect, which issue one at a time, and it is not safe
  // behind one that pipelines. Without this assumption the protocol
  // properties still hold -- what fails is a_write_responds, because the
  // adapter is waiting on a handshake for a transaction whose address it has
  // already lost.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // What the master has issued and not yet had answered. Environment
  // bookkeeping, not a property of the slave, which is why it sits here rather
  // than in the bound property module -- and why the two properties built on
  // it sit here too.
  logic [3:0] aw_outstanding, w_outstanding, ar_outstanding;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      aw_outstanding <= 4'd0;
      w_outstanding  <= 4'd0;
      ar_outstanding <= 4'd0;
    end else begin
      if (s_axil_awvalid && s_axil_awready) aw_outstanding <= aw_outstanding + 4'd1;
      if (s_axil_wvalid && s_axil_wready) w_outstanding <= w_outstanding + 4'd1;
      if (s_axil_arvalid && s_axil_arready) ar_outstanding <= ar_outstanding + 4'd1;
      if (s_axil_bvalid && s_axil_bready) begin
        aw_outstanding <= aw_outstanding - 4'd1 +
            ((s_axil_awvalid && s_axil_awready) ? 4'd1 : 4'd0);
        w_outstanding <= w_outstanding - 4'd1 +
            ((s_axil_wvalid && s_axil_wready) ? 4'd1 : 4'd0);
      end
      if (s_axil_rvalid && s_axil_rready) begin
        ar_outstanding <= ar_outstanding - 4'd1 +
            ((s_axil_arvalid && s_axil_arready) ? 4'd1 : 4'd0);
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst_n) begin
      m_one_write_addr : assume (!(s_axil_awvalid && (aw_outstanding != 4'd0)));
      m_one_write_data : assume (!(s_axil_wvalid && (w_outstanding != 4'd0)));
      m_one_read : assume (!(s_axil_arvalid && (ar_outstanding != 4'd0)));
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // No unsolicited responses
  //
  // An extra BVALID is not a transient glitch: the master's outstanding count
  // is permanently one out from then on, and every subsequent write is
  // attributed to the wrong transaction.
  //
  // A write response requires BOTH halves of the write to have been accepted.
  // AXI4-Lite lets the address and the data arrive in either order, so neither
  // count on its own is enough.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  if (FV_CHECK_BOUNDED) begin : g_solicited
    always_ff @(posedge clk) begin
      if (rst_n) begin
        if (s_axil_bvalid) begin
          a_bvalid_solicited : assert ((aw_outstanding != 4'd0) && (w_outstanding != 4'd0));
        end
        if (s_axil_rvalid) begin
          a_rvalid_solicited : assert (ar_outstanding != 4'd0);
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst_n) begin
      // Both orders on the write channels are reachable, and both have to
      // work. Address-first is the one the adapter's captured wr_addr_q exists
      // for: the register block holds WREADY high permanently, so a late data
      // beat would otherwise be decoded against whatever AWADDR had drifted
      // to.
      //
      // Covered as a state -- one half accepted, the other not yet -- rather
      // than on the handshake cycle. On the handshake cycle the counters have
      // not been incremented yet, both are still equal, and the cover is
      // unreachable. That is how it was first written, and sby duly reported
      // it unreached.
      c_data_before_addr : cover (w_outstanding > aw_outstanding);
      c_addr_before_data : cover (aw_outstanding > w_outstanding);
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Bounded liveness on the control port
  //
  // The protocol properties in fv_axil_props.sv are all safety: they are
  // satisfied by a slave that accepts nothing and answers nothing. This is the
  // other half -- an access that has been accepted gets a response, within a
  // fixed number of cycles, provided the master is taking responses.
  //
  // Bounded, and the bound is a constant rather than something derived: the
  // register block is generated and its latency is documented nowhere, so the
  // number was found by tightening it until it failed. Two is exact -- one
  // fails -- and pinning the exact value means a regeneration that makes the
  // block slower fails this task instead of silently costing every driver a
  // cycle per register access.
  //
  // BMC only, and necessarily so. The property is stated with a wait counter,
  // and k-induction starts from an arbitrary state in which that counter can
  // already be at its limit with no response owed -- so induction reports a
  // failure that is an artefact of the start state and not a fact about the
  // block. Latency is a statement about a fixed number of cycles from an
  // event; bounded model checking from reset is the right tool for it. The
  // prove task sets FV_CHECK_BOUNDED to 0.
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  localparam int LP_AXIL_MAX_LATENCY = 2;

  logic [3:0] w_wait, r_wait;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      w_wait <= 4'd0;
    end else if (s_axil_bvalid || !w_outstanding || !aw_outstanding) begin
      // Nothing owed, or the response is already there.
      w_wait <= 4'd0;
    end else if (s_axil_bready) begin
      w_wait <= w_wait + 4'd1;
    end

    if (!rst_n) begin
      r_wait <= 4'd0;
    end else if (s_axil_rvalid || !ar_outstanding) begin
      r_wait <= 4'd0;
    end else if (s_axil_rready) begin
      r_wait <= r_wait + 4'd1;
    end
  end

  if (FV_CHECK_BOUNDED) begin : g_liveness
    always_ff @(posedge clk) begin
      if (rst_n) begin
        a_write_responds : assert (w_wait <= 4'(LP_AXIL_MAX_LATENCY));
        a_read_responds : assert (r_wait <= 4'(LP_AXIL_MAX_LATENCY));
      end
    end
  end

endmodule
