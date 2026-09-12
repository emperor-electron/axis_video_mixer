`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_layer_bind.sv
// Purpose : Attach fv_layer_props to every axis_mixer_layer instance -- once
//           in fv_layer, and P_NUM_LAYERS times in fv_core.
//
//           Reaches the state machine and both counters, which is where the
//           properties need to be: the interface alone cannot distinguish a
//           layer that is correctly aligned from one that is a line late, and
//           that distinction is the block's entire job.
///////////////////////////////////////////////////////////////////

bind axis_mixer_layer fv_layer_props #(
    .P_FIFO_DEPTH(P_FIFO_DEPTH),
    .P_BEAT_W    (P_BEAT_W)
) u_fv_props (
    .clk  (clk),
    .rst_n(rst_n),

    .flush      (flush),
    .enable     (enable),
    .cfg_w_beats(cfg_w_beats),
    .cfg_height (cfg_height),
    .stall_limit(stall_limit),

    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata (s_axis_tdata),
    .s_axis_tuser (s_axis_tuser),
    .s_axis_tlast (s_axis_tlast),

    .px_data (px_data),
    .px_valid(px_valid),
    .px_pop  (px_pop),

    .armed    (armed),
    .geom_err (geom_err),
    .src_stall(src_stall),
    .level    (level),

    .state          (state),
    .bt_cnt         (bt_cnt),
    .ln_cnt         (ln_cnt),
    .cur_bt         (cur_bt),
    .cur_ln         (cur_ln),
    .fifo_full      (fifo_full),
    .accept         (accept),
    .push           (push),
    .flush_now      (flush_now),
    .geom_bad       (geom_bad),
    .last_bt_of_line(last_bt_of_line),
    .stall_cnt      (stall_cnt)
);
