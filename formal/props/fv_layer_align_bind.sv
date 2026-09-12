`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_layer_align_bind.sv
// Purpose : Attach the bounded positional-accounting check. Separate from
//           fv_layer_bind.sv because the multiply it needs is overhead for
//           every other task -- see the header of fv_layer_align.sv.
///////////////////////////////////////////////////////////////////

bind axis_mixer_layer fv_layer_align u_fv_align (
    .clk  (clk),
    .rst_n(rst_n),

    .cfg_w_beats(cfg_w_beats),
    .cfg_height (cfg_height),

    .state           (state),
    .bt_cnt          (bt_cnt),
    .ln_cnt          (ln_cnt),
    .push            (push),
    .flush_now       (flush_now),
    .last_bt_of_line (last_bt_of_line),
    .last_ln_of_frame(last_ln_of_frame)
);
