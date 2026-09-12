`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_axil_bind.sv
// Purpose : Attach fv_axil_props to the CSR adapter.
//
//           Bound to axis_video_mixer_csr rather than to the top, because
//           err_ff and irq_en live in the adapter -- they are the shadow the
//           adapter keeps so that a hardware set beats a software clear, and
//           the interrupt properties are about them. The AXI4-Lite signals are
//           the same wires either way.
///////////////////////////////////////////////////////////////////

bind axis_video_mixer_csr fv_axil_props #(
    .P_ADDR_W(P_ADDR_W)
) u_fv_axil (
    .clk  (clk),
    .rst_n(rst_n),

    .awaddr (axil_awaddr),
    .awvalid(axil_awvalid),
    .awready(axil_awready),
    .wdata  (axil_wdata),
    .wstrb  (axil_wstrb),
    .wvalid (axil_wvalid),
    .wready (axil_wready),
    .bresp  (axil_bresp),
    .bvalid (axil_bvalid),
    .bready (axil_bready),
    .araddr (axil_araddr),
    .arvalid(axil_arvalid),
    .arready(axil_arready),
    .rdata  (axil_rdata),
    .rresp  (axil_rresp),
    .rvalid (axil_rvalid),
    .rready (axil_rready),

    .irq         (irq),
    .err_ff      (err_ff),
    .irq_en      (irq_en),
    .err_set     (err_set),
    .err_wr_clear(err_wr_clear)
);
