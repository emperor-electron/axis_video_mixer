# ==============================================================================
# Drop-in filelist for the AXI4-Stream video mixer.
#
# Consume it from a project with:
#     -f $AXIS_VIDEO_MIXER_ROOT/src/axis_video_mixer.f
#
# Order matters: the package must compile before anything that imports it, and
# the generated register block before the adapter that instantiates it.
#
# The two files under generated/ come from regs/gen_regs.py and corsair. Do not
# edit them; regenerate with
#     cd regs && ./gen_regs.py && corsair -r regs.json -c csrconfig
#
# They do not depend on P_NUM_LAYERS, P_PPC or P_CH_W: the map is generated for
# the maximum layer count and CAPS reports what a build actually instantiates,
# so one set of generated files serves every configuration.
# ==============================================================================

${AXIS_VIDEO_MIXER_ROOT}/src/axis_video_mixer_pkg.sv

${AXIS_VIDEO_MIXER_ROOT}/src/generated/axis_video_mixer_regs.v
${AXIS_VIDEO_MIXER_ROOT}/src/generated/axis_video_mixer_csr.sv

${AXIS_VIDEO_MIXER_ROOT}/src/axis_mixer_fifo.sv
${AXIS_VIDEO_MIXER_ROOT}/src/axis_mixer_layer.sv
${AXIS_VIDEO_MIXER_ROOT}/src/axis_video_mixer_core.sv
${AXIS_VIDEO_MIXER_ROOT}/src/axis_video_mixer.sv
