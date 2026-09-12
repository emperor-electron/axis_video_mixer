`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_fifo_order_bind.sv
// Purpose : Attach the bounded ordering cross-check to every axis_mixer_fifo.
//           Separate from fv_fifo_bind.sv because the transaction counters are
//           proof overhead everywhere except the one task that needs them --
//           see the header of fv_fifo_order.sv.
///////////////////////////////////////////////////////////////////

bind axis_mixer_fifo fv_fifo_order #(
    .P_WIDTH(P_WIDTH),
    .P_DEPTH(P_DEPTH)
) u_fv_order (
    .clk  (clk),
    .rst_n(rst_n),
    .flush(flush),

    .wr_en  (wr_en),
    .wr_data(wr_data),
    .full   (full),

    .rd_valid(rd_valid),
    .rd_data (rd_data),
    .rd_en   (rd_en),

    .level(level)
);
