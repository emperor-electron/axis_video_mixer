`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////
// Filename: fv_core_frame_bind.sv
// Purpose : Attach the framing and datapath-value checks. Separate from
//           fv_core_bind.sv because both only say anything under a
//           configuration that does not move, which only the frame and
//           datapath tasks arrange -- see the header of fv_core_frame.sv.
///////////////////////////////////////////////////////////////////

bind axis_video_mixer_core fv_core_frame #(
    .P_NUM_LAYERS   (P_NUM_LAYERS),
    .P_PPC          (P_PPC),
    .P_OUT_HAS_ALPHA(P_OUT_HAS_ALPHA)
) u_fv_frame (
    .clk     (clk),
    .rst_n   (rst_n),
    .soft_rst(soft_rst),

    .act_bw   (act_bw),
    .act_h    (act_h),
    .act_bg   (act_bg),
    .act_ok   (act_ok),
    .act_en   (act_en),
    .act_alpha(act_alpha),
    .act_asrc (act_asrc),

    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata (m_axis_tdata),
    .m_axis_tuser (m_axis_tuser),
    .m_axis_tlast (m_axis_tlast)
);
