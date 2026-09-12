`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_core_bind.sv
// Purpose : Attach fv_core_props to axis_video_mixer_core.
//
//           Reaches the raster, the active and shadow configuration, and every
//           per-layer arbitration signal. Those are what the properties are
//           about: whether a window can become active while illegal, whether a
//           wanted beat can be silently skipped, and whether the raster can be
//           stopped by an input are all questions about internal state that
//           the port list does not expose.
///////////////////////////////////////////////////////////////////

bind axis_video_mixer_core fv_core_props #(
    .P_NUM_LAYERS(P_NUM_LAYERS),
    .P_PPC       (P_PPC)
) u_fv_props (
    .clk  (clk),
    .rst_n(rst_n),

    .ctrl_en (ctrl_en),
    .soft_rst(soft_rst),

    .out_bx        (out_bx),
    .out_y         (out_y),
    .s0_valid      (s0_valid),
    .s0_eol        (s0_eol),
    .s0_eof        (s0_eof),
    .pipe_en       (pipe_en),
    .frame_boundary(frame_boundary),
    .frame_latch   (frame_latch),

    .act_ok  (act_ok),
    .act_w   (act_w),
    .act_h   (act_h),
    .act_bw  (act_bw),
    .act_en  (act_en),
    .act_x   (act_x),
    .act_y   (act_y),
    .act_w_l (act_w_l),
    .act_bx  (act_bx),
    .act_bxe (act_bxe),
    .act_ye  (act_ye),
    .act_bw_l(act_bw_l),
    .act_h_l (act_h_l),

    .canvas_ok  (canvas_ok),
    .want_en    (want_en),
    .geo_changed(geo_changed),
    .cfg_fault  (cfg_fault),

    .in_win      (in_win),
    .want_px     (want_px),
    .starve      (starve),
    .lay_active  (lay_active),
    .lay_pop     (lay_pop),
    .lay_px_valid(lay_px_valid),
    .lay_flush   (lay_flush),
    .lay_armed   (lay_armed),
    .lay_dropped (lay_dropped),
    .lay_cfg_bad (lay_cfg_bad),

    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tuser (m_axis_tuser),
    .m_axis_tlast (m_axis_tlast),

    .status_frame_active(status_frame_active),
    .sof_out            (sof_q[P_NUM_LAYERS]),
    .eof_out            (eof_q[P_NUM_LAYERS]),
    .out_beat           (out_beat),
    .frame_count        (frame_count),
    .err_cfg_set        (err_cfg_set),
    .err_starve_set     (err_starve_set),
    .out_stall_cnt      (out_stall_cnt),
    .stall_limit        (stall_limit),
    .err_out_stall_set  (err_out_stall_set)
);
