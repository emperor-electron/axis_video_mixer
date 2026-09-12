`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_fifo_bind.sv
// Purpose : Attach fv_fifo_props to every axis_mixer_fifo instance.
//
//           A bind on the module rather than on an instance path, so the
//           properties follow the FIFO wherever it is instantiated: on its own
//           in fv_fifo, once inside fv_layer, and P_NUM_LAYERS times inside
//           fv_core. The layer and core proofs then check the FIFO's own
//           invariants against the way those blocks actually drive it, which
//           is where a composition bug would show up.
//
//           Port connections and the parameter overrides are both resolved in
//           the scope of the target, which is what lets this reach wr_ptr,
//           rd_ptr, mem_count and mem_rd_en -- internal wires, and where the
//           interesting properties live.
///////////////////////////////////////////////////////////////////

bind axis_mixer_fifo fv_fifo_props #(
    .P_WIDTH(P_WIDTH),
    .P_DEPTH(P_DEPTH)
) u_fv_props (
    .clk  (clk),
    .rst_n(rst_n),
    .flush(flush),

    .wr_en  (wr_en),
    .wr_data(wr_data),
    .full   (full),

    .rd_valid(rd_valid),
    .rd_data (rd_data),
    .rd_en   (rd_en),

    .level(level),

    .wr_ptr   (wr_ptr),
    .rd_ptr   (rd_ptr),
    .mem_count(mem_count),
    .mem_rd_en(mem_rd_en)
);
