// Created with Corsair v1.0.4

module axis_video_mixer_regs #(
    parameter ADDR_W = 12,
    parameter DATA_W = 32,
    parameter STRB_W = DATA_W / 8
)(
    // System
    input clk,
    input rst,
    // ID.VER_MINOR
    // ID.VER_MAJOR
    // ID.MAGIC

    // CAPS.NUM_LAYERS
    // CAPS.FIFO_DEPTH_LOG2
    // CAPS.OUT_HAS_ALPHA

    // SCRATCH.VALUE

    // CTRL.EN
    output  csr_ctrl_en_out,
    // CTRL.SOFT_RST
    output  csr_ctrl_soft_rst_out,

    // CANVAS.WIDTH
    output [15:0] csr_canvas_width_out,
    // CANVAS.HEIGHT
    output [15:0] csr_canvas_height_out,

    // BACKGROUND.RGB
    output [23:0] csr_background_rgb_out,

    // STATUS.ERR_ANY
    input  csr_status_err_any_in,
    // STATUS.FRAME_ACTIVE
    input  csr_status_frame_active_in,
    // STATUS.LAYER_ARMED
    input [3:0] csr_status_layer_armed_in,

    // FRAME_COUNT.COUNT
    input [31:0] csr_frame_count_count_in,

    // ERR.CFG
    input csr_err_cfg_set,
    // ERR.STARVE
    input csr_err_starve_set,
    // ERR.GEOM
    input csr_err_geom_set,
    // ERR.SRC_STALL
    input csr_err_src_stall_set,
    // ERR.OUT_STALL
    input csr_err_out_stall_set,

    // ERR_LAYER.L0
    input csr_err_layer_l0_set,
    // ERR_LAYER.L1
    input csr_err_layer_l1_set,
    // ERR_LAYER.L2
    input csr_err_layer_l2_set,
    // ERR_LAYER.L3
    input csr_err_layer_l3_set,

    // IRQ_EN.CFG
    output  csr_irq_en_cfg_out,
    // IRQ_EN.STARVE
    output  csr_irq_en_starve_out,
    // IRQ_EN.GEOM
    output  csr_irq_en_geom_out,
    // IRQ_EN.SRC_STALL
    output  csr_irq_en_src_stall_out,
    // IRQ_EN.OUT_STALL
    output  csr_irq_en_out_stall_out,

    // STALL_LIMIT.CYCLES
    output [31:0] csr_stall_limit_cycles_out,

    // L0_CTRL.EN
    output  csr_l0_ctrl_en_out,
    // L0_CTRL.ALPHA
    output [7:0] csr_l0_ctrl_alpha_out,
    // L0_CTRL.ALPHA_SRC
    output  csr_l0_ctrl_alpha_src_out,

    // L0_POS.X
    output [15:0] csr_l0_pos_x_out,
    // L0_POS.Y
    output [15:0] csr_l0_pos_y_out,

    // L0_SIZE.WIDTH
    output [15:0] csr_l0_size_width_out,
    // L0_SIZE.HEIGHT
    output [15:0] csr_l0_size_height_out,

    // L0_STATUS.ARMED
    input  csr_l0_status_armed_in,
    // L0_STATUS.DROPPED
    input  csr_l0_status_dropped_in,
    // L0_STATUS.CFG_BAD
    input  csr_l0_status_cfg_bad_in,
    // L0_STATUS.FIFO_LEVEL
    input [15:0] csr_l0_status_fifo_level_in,

    // L1_CTRL.EN
    output  csr_l1_ctrl_en_out,
    // L1_CTRL.ALPHA
    output [7:0] csr_l1_ctrl_alpha_out,
    // L1_CTRL.ALPHA_SRC
    output  csr_l1_ctrl_alpha_src_out,

    // L1_POS.X
    output [15:0] csr_l1_pos_x_out,
    // L1_POS.Y
    output [15:0] csr_l1_pos_y_out,

    // L1_SIZE.WIDTH
    output [15:0] csr_l1_size_width_out,
    // L1_SIZE.HEIGHT
    output [15:0] csr_l1_size_height_out,

    // L1_STATUS.ARMED
    input  csr_l1_status_armed_in,
    // L1_STATUS.DROPPED
    input  csr_l1_status_dropped_in,
    // L1_STATUS.CFG_BAD
    input  csr_l1_status_cfg_bad_in,
    // L1_STATUS.FIFO_LEVEL
    input [15:0] csr_l1_status_fifo_level_in,

    // L2_CTRL.EN
    output  csr_l2_ctrl_en_out,
    // L2_CTRL.ALPHA
    output [7:0] csr_l2_ctrl_alpha_out,
    // L2_CTRL.ALPHA_SRC
    output  csr_l2_ctrl_alpha_src_out,

    // L2_POS.X
    output [15:0] csr_l2_pos_x_out,
    // L2_POS.Y
    output [15:0] csr_l2_pos_y_out,

    // L2_SIZE.WIDTH
    output [15:0] csr_l2_size_width_out,
    // L2_SIZE.HEIGHT
    output [15:0] csr_l2_size_height_out,

    // L2_STATUS.ARMED
    input  csr_l2_status_armed_in,
    // L2_STATUS.DROPPED
    input  csr_l2_status_dropped_in,
    // L2_STATUS.CFG_BAD
    input  csr_l2_status_cfg_bad_in,
    // L2_STATUS.FIFO_LEVEL
    input [15:0] csr_l2_status_fifo_level_in,

    // L3_CTRL.EN
    output  csr_l3_ctrl_en_out,
    // L3_CTRL.ALPHA
    output [7:0] csr_l3_ctrl_alpha_out,
    // L3_CTRL.ALPHA_SRC
    output  csr_l3_ctrl_alpha_src_out,

    // L3_POS.X
    output [15:0] csr_l3_pos_x_out,
    // L3_POS.Y
    output [15:0] csr_l3_pos_y_out,

    // L3_SIZE.WIDTH
    output [15:0] csr_l3_size_width_out,
    // L3_SIZE.HEIGHT
    output [15:0] csr_l3_size_height_out,

    // L3_STATUS.ARMED
    input  csr_l3_status_armed_in,
    // L3_STATUS.DROPPED
    input  csr_l3_status_dropped_in,
    // L3_STATUS.CFG_BAD
    input  csr_l3_status_cfg_bad_in,
    // L3_STATUS.FIFO_LEVEL
    input [15:0] csr_l3_status_fifo_level_in,

    // AXI
    input  [ADDR_W-1:0] axil_awaddr,
    input  [2:0]        axil_awprot,
    input               axil_awvalid,
    output              axil_awready,
    input  [DATA_W-1:0] axil_wdata,
    input  [STRB_W-1:0] axil_wstrb,
    input               axil_wvalid,
    output              axil_wready,
    output [1:0]        axil_bresp,
    output              axil_bvalid,
    input               axil_bready,

    input  [ADDR_W-1:0] axil_araddr,
    input  [2:0]        axil_arprot,
    input               axil_arvalid,
    output              axil_arready,
    output [DATA_W-1:0] axil_rdata,
    output [1:0]        axil_rresp,
    output              axil_rvalid,
    input               axil_rready
);
wire              wready;
wire [ADDR_W-1:0] waddr;
wire [DATA_W-1:0] wdata;
wire              wen;
wire [STRB_W-1:0] wstrb;
wire [DATA_W-1:0] rdata;
wire              rvalid;
wire [ADDR_W-1:0] raddr;
wire              ren;
    reg [ADDR_W-1:0] waddr_int;
    reg [ADDR_W-1:0] raddr_int;
    reg [DATA_W-1:0] wdata_int;
    reg [STRB_W-1:0] strb_int;
    reg              awflag;
    reg              wflag;
    reg              arflag;
    reg              rflag;

    reg              axil_bvalid_int;
    reg [DATA_W-1:0] axil_rdata_int;
    reg              axil_rvalid_int;

    assign axil_awready = ~awflag;
    assign axil_wready  = ~wflag;
    assign axil_bvalid  = axil_bvalid_int;
    assign waddr        = waddr_int;
    assign wdata        = wdata_int;
    assign wstrb        = strb_int;
    assign wen          = awflag && wflag;
    assign axil_bresp   = 'd0; // always okay

    always @(posedge clk) begin
        if (rst == 1'b0) begin
            waddr_int       <= 'd0;
            wdata_int       <= 'd0;
            strb_int        <= 'd0;
            awflag          <= 1'b0;
            wflag           <= 1'b0;
            axil_bvalid_int <= 1'b0;
        end else begin
            if (axil_awvalid == 1'b1 && awflag == 1'b0) begin
                awflag    <= 1'b1;
                waddr_int <= axil_awaddr;
            end else if (wen == 1'b1 && wready == 1'b1) begin
                awflag    <= 1'b0;
            end

            if (axil_wvalid == 1'b1 && wflag == 1'b0) begin
                wflag     <= 1'b1;
                wdata_int <= axil_wdata;
                strb_int  <= axil_wstrb;
            end else if (wen == 1'b1 && wready == 1'b1) begin
                wflag     <= 1'b0;
            end

            if (axil_bvalid_int == 1'b1 && axil_bready == 1'b1) begin
                axil_bvalid_int <= 1'b0;
            end else if ((axil_wvalid == 1'b1 && awflag == 1'b1) || (axil_awvalid == 1'b1 && wflag == 1'b1) || (wflag == 1'b1 && awflag == 1'b1)) begin
                axil_bvalid_int <= wready;
            end
        end
    end

    assign axil_arready = ~arflag;
    assign axil_rdata   = axil_rdata_int;
    assign axil_rvalid  = axil_rvalid_int;
    assign raddr        = raddr_int;
    assign ren          = arflag && ~rflag;
    assign axil_rresp   = 'd0; // always okay

    always @(posedge clk) begin
        if (rst == 1'b0) begin
            raddr_int       <= 'd0;
            arflag          <= 1'b0;
            rflag           <= 1'b0;
            axil_rdata_int  <= 'd0;
            axil_rvalid_int <= 1'b0;
        end else begin
            if (axil_arvalid == 1'b1 && arflag == 1'b0) begin
                arflag    <= 1'b1;
                raddr_int <= axil_araddr;
            end else if (axil_rvalid_int == 1'b1 && axil_rready == 1'b1) begin
                arflag    <= 1'b0;
            end

            if (rvalid == 1'b1 && ren == 1'b1 && rflag == 1'b0) begin
                rflag <= 1'b1;
            end else if (axil_rvalid_int == 1'b1 && axil_rready == 1'b1) begin
                rflag <= 1'b0;
            end

            if (rvalid == 1'b1 && axil_rvalid_int == 1'b0) begin
                axil_rdata_int  <= rdata;
                axil_rvalid_int <= 1'b1;
            end else if (axil_rvalid_int == 1'b1 && axil_rready == 1'b1) begin
                axil_rvalid_int <= 1'b0;
            end
        end
    end

//------------------------------------------------------------------------------
// CSR:
// [0x0] - ID - Identification and version. Read-only constants, so a correct read here proves the AXI4-Lite path reaches this block before any other register is trusted.
//------------------------------------------------------------------------------
wire [31:0] csr_id_rdata;


wire csr_id_ren;
assign csr_id_ren = ren && (raddr == 12'h0);
reg csr_id_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_id_ren_ff <= 1'b0;
    end else begin
        csr_id_ren_ff <= csr_id_ren;
    end
end
//---------------------
// Bit field:
// ID[7:0] - VER_MINOR - Minor version. Increment on backwards-compatible additions.
// access: ro, hardware: f
//---------------------
reg [7:0] csr_id_ver_minor_ff;

assign csr_id_rdata[7:0] = csr_id_ver_minor_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_id_ver_minor_ff <= 8'h0;
    end else  begin
      begin
            csr_id_ver_minor_ff <= csr_id_ver_minor_ff;
        end
    end
end


//---------------------
// Bit field:
// ID[15:8] - VER_MAJOR - Major version. Increment on any incompatible map change.
// access: ro, hardware: f
//---------------------
reg [7:0] csr_id_ver_major_ff;

assign csr_id_rdata[15:8] = csr_id_ver_major_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_id_ver_major_ff <= 8'h1;
    end else  begin
      begin
            csr_id_ver_major_ff <= csr_id_ver_major_ff;
        end
    end
end


//---------------------
// Bit field:
// ID[31:16] - MAGIC - Always 0x4D58 (ASCII 'MX'). A read of 0x0000 or 0xFFFF means the bus is not reaching the mixer.
// access: ro, hardware: f
//---------------------
reg [15:0] csr_id_magic_ff;

assign csr_id_rdata[31:16] = csr_id_magic_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_id_magic_ff <= 16'h4d58;
    end else  begin
      begin
            csr_id_magic_ff <= csr_id_magic_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x4] - CAPS - Build-time capabilities, so software can size its own layer loops from the hardware it is actually talking to instead of from a compile-time assumption. These are constants baked into the map by gen_regs.py; axis_video_mixer.sv asserts at elaboration that they match the RTL parameters, so a map and a build that disagree fail loudly rather than misreporting.
//------------------------------------------------------------------------------
wire [31:0] csr_caps_rdata;
assign csr_caps_rdata[31:17] = 15'h0;


wire csr_caps_ren;
assign csr_caps_ren = ren && (raddr == 12'h4);
reg csr_caps_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_caps_ren_ff <= 1'b0;
    end else begin
        csr_caps_ren_ff <= csr_caps_ren;
    end
end
//---------------------
// Bit field:
// CAPS[7:0] - NUM_LAYERS - Number of layer input streams this build instantiates.
// access: ro, hardware: f
//---------------------
reg [7:0] csr_caps_num_layers_ff;

assign csr_caps_rdata[7:0] = csr_caps_num_layers_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_caps_num_layers_ff <= 8'h4;
    end else  begin
      begin
            csr_caps_num_layers_ff <= csr_caps_num_layers_ff;
        end
    end
end


//---------------------
// Bit field:
// CAPS[15:8] - FIFO_DEPTH_LOG2 - Per-layer input FIFO depth, as a power of two. A layer wider than 2**this cannot be guaranteed free of underflow.
// access: ro, hardware: f
//---------------------
reg [7:0] csr_caps_fifo_depth_log2_ff;

assign csr_caps_rdata[15:8] = csr_caps_fifo_depth_log2_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_caps_fifo_depth_log2_ff <= 8'hb;
    end else  begin
      begin
            csr_caps_fifo_depth_log2_ff <= csr_caps_fifo_depth_log2_ff;
        end
    end
end


//---------------------
// Bit field:
// CAPS[16] - OUT_HAS_ALPHA - 1 if the output stream carries RGBA8 (32-bit TDATA), 0 if it carries RGB8 (24-bit TDATA) with alpha discarded after blending.
// access: ro, hardware: f
//---------------------
reg  csr_caps_out_has_alpha_ff;

assign csr_caps_rdata[16] = csr_caps_out_has_alpha_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_caps_out_has_alpha_ff <= 1'b1;
    end else  begin
      begin
            csr_caps_out_has_alpha_ff <= csr_caps_out_has_alpha_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x8] - SCRATCH - Read/write scratchpad with no hardware effect. Exists so a write-then-read test can prove the bus end to end without disturbing the picture.
//------------------------------------------------------------------------------
wire [31:0] csr_scratch_rdata;

wire csr_scratch_wen;
assign csr_scratch_wen = wen && (waddr == 12'h8);

wire csr_scratch_ren;
assign csr_scratch_ren = ren && (raddr == 12'h8);
reg csr_scratch_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_scratch_ren_ff <= 1'b0;
    end else begin
        csr_scratch_ren_ff <= csr_scratch_ren;
    end
end
//---------------------
// Bit field:
// SCRATCH[31:0] - VALUE - Any value. Reads back exactly what was written.
// access: rw, hardware: n
//---------------------
reg [31:0] csr_scratch_value_ff;

assign csr_scratch_rdata[31:0] = csr_scratch_value_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_scratch_value_ff <= 32'h0;
    end else  begin
     if (csr_scratch_wen) begin
            if (wstrb[0]) begin
                csr_scratch_value_ff[7:0] <= wdata[7:0];
            end
            if (wstrb[1]) begin
                csr_scratch_value_ff[15:8] <= wdata[15:8];
            end
            if (wstrb[2]) begin
                csr_scratch_value_ff[23:16] <= wdata[23:16];
            end
            if (wstrb[3]) begin
                csr_scratch_value_ff[31:24] <= wdata[31:24];
            end
        end else begin
            csr_scratch_value_ff <= csr_scratch_value_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0xc] - CTRL - Global mixer control.
//------------------------------------------------------------------------------
wire [31:0] csr_ctrl_rdata;
assign csr_ctrl_rdata[7:1] = 7'h0;
assign csr_ctrl_rdata[31:9] = 23'h0;

wire csr_ctrl_wen;
assign csr_ctrl_wen = wen && (waddr == 12'hc);

wire csr_ctrl_ren;
assign csr_ctrl_ren = ren && (raddr == 12'hc);
reg csr_ctrl_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_ctrl_ren_ff <= 1'b0;
    end else begin
        csr_ctrl_ren_ff <= csr_ctrl_ren;
    end
end
//---------------------
// Bit field:
// CTRL[0] - EN - Enable the output stream. While 0 the mixer holds TVALID low and accepts and discards nothing -- layer inputs are backpressured. Set the canvas and layer geometry first, then set this.
// access: rw, hardware: o
//---------------------
reg  csr_ctrl_en_ff;

assign csr_ctrl_rdata[0] = csr_ctrl_en_ff;

assign csr_ctrl_en_out = csr_ctrl_en_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_ctrl_en_ff <= 1'b0;
    end else  begin
     if (csr_ctrl_wen) begin
            if (wstrb[0]) begin
                csr_ctrl_en_ff <= wdata[0];
            end
        end else begin
            csr_ctrl_en_ff <= csr_ctrl_en_ff;
        end
    end
end


//---------------------
// Bit field:
// CTRL[8] - SOFT_RST - Write 1 to resynchronise the whole datapath: flush every layer FIFO, drop to the top of a new output frame, and re-arm each layer at its next input SOF. Self-clearing; does not touch configuration registers.
// access: wosc, hardware: o
//---------------------
reg  csr_ctrl_soft_rst_ff;

assign csr_ctrl_rdata[8] = 1'b0;

assign csr_ctrl_soft_rst_out = csr_ctrl_soft_rst_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_ctrl_soft_rst_ff <= 1'b0;
    end else  begin
     if (csr_ctrl_wen) begin
            if (wstrb[1]) begin
                csr_ctrl_soft_rst_ff <= wdata[8];
            end
        end else begin
            csr_ctrl_soft_rst_ff <= 1'b0;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x10] - CANVAS - Output raster size in pixels. The mixer emits HEIGHT lines of WIDTH pixels per frame. Changing either takes effect at the next output frame boundary.
//------------------------------------------------------------------------------
wire [31:0] csr_canvas_rdata;

wire csr_canvas_wen;
assign csr_canvas_wen = wen && (waddr == 12'h10);

wire csr_canvas_ren;
assign csr_canvas_ren = ren && (raddr == 12'h10);
reg csr_canvas_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_canvas_ren_ff <= 1'b0;
    end else begin
        csr_canvas_ren_ff <= csr_canvas_ren;
    end
end
//---------------------
// Bit field:
// CANVAS[15:0] - WIDTH - Output active width in pixels. Must be non-zero.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_canvas_width_ff;

assign csr_canvas_rdata[15:0] = csr_canvas_width_ff;

assign csr_canvas_width_out = csr_canvas_width_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_canvas_width_ff <= 16'h500;
    end else  begin
     if (csr_canvas_wen) begin
            if (wstrb[0]) begin
                csr_canvas_width_ff[7:0] <= wdata[7:0];
            end
            if (wstrb[1]) begin
                csr_canvas_width_ff[15:8] <= wdata[15:8];
            end
        end else begin
            csr_canvas_width_ff <= csr_canvas_width_ff;
        end
    end
end


//---------------------
// Bit field:
// CANVAS[31:16] - HEIGHT - Output active height in lines. Must be non-zero.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_canvas_height_ff;

assign csr_canvas_rdata[31:16] = csr_canvas_height_ff;

assign csr_canvas_height_out = csr_canvas_height_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_canvas_height_ff <= 16'h2d0;
    end else  begin
     if (csr_canvas_wen) begin
            if (wstrb[2]) begin
                csr_canvas_height_ff[7:0] <= wdata[23:16];
            end
            if (wstrb[3]) begin
                csr_canvas_height_ff[15:8] <= wdata[31:24];
            end
        end else begin
            csr_canvas_height_ff <= csr_canvas_height_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x14] - BACKGROUND - Colour of the canvas underneath every layer. This is what shows through wherever no enabled layer covers a pixel, which is why no layer is obliged to span the whole canvas -- every input can be an arbitrary rectangle.
//------------------------------------------------------------------------------
wire [31:0] csr_background_rdata;
assign csr_background_rdata[31:24] = 8'h0;

wire csr_background_wen;
assign csr_background_wen = wen && (waddr == 12'h14);

wire csr_background_ren;
assign csr_background_ren = ren && (raddr == 12'h14);
reg csr_background_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_background_ren_ff <= 1'b0;
    end else begin
        csr_background_ren_ff <= csr_background_ren;
    end
end
//---------------------
// Bit field:
// BACKGROUND[23:0] - RGB - Background colour, {R[23:16], G[15:8], B[7:0]}.
// access: rw, hardware: o
//---------------------
reg [23:0] csr_background_rgb_ff;

assign csr_background_rdata[23:0] = csr_background_rgb_ff;

assign csr_background_rgb_out = csr_background_rgb_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_background_rgb_ff <= 24'h0;
    end else  begin
     if (csr_background_wen) begin
            if (wstrb[0]) begin
                csr_background_rgb_ff[7:0] <= wdata[7:0];
            end
            if (wstrb[1]) begin
                csr_background_rgb_ff[15:8] <= wdata[15:8];
            end
            if (wstrb[2]) begin
                csr_background_rgb_ff[23:16] <= wdata[23:16];
            end
        end else begin
            csr_background_rgb_ff <= csr_background_rgb_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x18] - STATUS - Live state. Read-only and never latched -- these reflect the current cycle, unlike the ERR register which latches.
//------------------------------------------------------------------------------
wire [31:0] csr_status_rdata;
assign csr_status_rdata[15:2] = 14'h0;
assign csr_status_rdata[31:20] = 12'h0;


wire csr_status_ren;
assign csr_status_ren = ren && (raddr == 12'h18);
reg csr_status_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_status_ren_ff <= 1'b0;
    end else begin
        csr_status_ren_ff <= csr_status_ren;
    end
end
//---------------------
// Bit field:
// STATUS[0] - ERR_ANY - 1 while any bit in ERR is set. Lets a polling loop check one register instead of two.
// access: ro, hardware: i
//---------------------
reg  csr_status_err_any_ff;

assign csr_status_rdata[0] = csr_status_err_any_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_status_err_any_ff <= 1'b0;
    end else  begin
              begin            csr_status_err_any_ff <= csr_status_err_any_in;
        end
    end
end


//---------------------
// Bit field:
// STATUS[1] - FRAME_ACTIVE - 1 while the output is mid-frame (between SOF and the last pixel of the last line).
// access: ro, hardware: i
//---------------------
reg  csr_status_frame_active_ff;

assign csr_status_rdata[1] = csr_status_frame_active_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_status_frame_active_ff <= 1'b0;
    end else  begin
              begin            csr_status_frame_active_ff <= csr_status_frame_active_in;
        end
    end
end


//---------------------
// Bit field:
// STATUS[19:16] - LAYER_ARMED - One bit per layer: 1 once that layer has seen its input SOF and is delivering pixels. A layer that stays 0 is not receiving a stream.
// access: ro, hardware: i
//---------------------
reg [3:0] csr_status_layer_armed_ff;

assign csr_status_rdata[19:16] = csr_status_layer_armed_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_status_layer_armed_ff <= 4'h0;
    end else  begin
              begin            csr_status_layer_armed_ff <= csr_status_layer_armed_in;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x1c] - FRAME_COUNT - Output frames completed since reset. Incrementing proves the pipeline is running; a stuck value with EN set means the output is stalled or a layer is starving.
//------------------------------------------------------------------------------
wire [31:0] csr_frame_count_rdata;


wire csr_frame_count_ren;
assign csr_frame_count_ren = ren && (raddr == 12'h1c);
reg csr_frame_count_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_frame_count_ren_ff <= 1'b0;
    end else begin
        csr_frame_count_ren_ff <= csr_frame_count_ren;
    end
end
//---------------------
// Bit field:
// FRAME_COUNT[31:0] - COUNT - Free-running, wraps at 2**32.
// access: ro, hardware: i
//---------------------
reg [31:0] csr_frame_count_count_ff;

assign csr_frame_count_rdata[31:0] = csr_frame_count_count_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_frame_count_count_ff <= 32'h0;
    end else  begin
              begin            csr_frame_count_count_ff <= csr_frame_count_count_in;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x20] - ERR - Latched error flags. Hardware sets, software clears by writing 1 to the bit. Latched rather than live because every one of these is a transient that would otherwise be missed between two polls.
//------------------------------------------------------------------------------
wire [31:0] csr_err_rdata;
assign csr_err_rdata[31:5] = 27'h0;

wire csr_err_wen;
assign csr_err_wen = wen && (waddr == 12'h20);

wire csr_err_ren;
assign csr_err_ren = ren && (raddr == 12'h20);
reg csr_err_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_err_ren_ff <= 1'b0;
    end else begin
        csr_err_ren_ff <= csr_err_ren;
    end
end
//---------------------
// Bit field:
// ERR[0] - CFG - Configuration rejected: canvas width or height is zero, or an enabled layer's window is zero-sized or extends past the canvas edge. The offending layer is flagged in ERR_LAYER; a canvas fault sets this bit alone. The mixer keeps running on the last valid configuration.
// access: rw1c, hardware: s
//---------------------
reg  csr_err_cfg_ff;

assign csr_err_rdata[0] = csr_err_cfg_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_err_cfg_ff <= 1'b0;
    end else  begin
        if (csr_err_cfg_set) begin
            csr_err_cfg_ff <= 1'b1;
        end else     if (csr_err_wen) begin
            if (wstrb[0] && wdata[0]) begin
                csr_err_cfg_ff <= 1'b0;
            end
        end else begin
            csr_err_cfg_ff <= csr_err_cfg_ff;
        end
    end
end


//---------------------
// Bit field:
// ERR[1] - STARVE - A layer's input FIFO ran empty at a pixel where that layer was due to contribute. The layer is dropped for the remainder of the frame and re-arms at its next input SOF; the output never stalls.
// access: rw1c, hardware: s
//---------------------
reg  csr_err_starve_ff;

assign csr_err_rdata[1] = csr_err_starve_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_err_starve_ff <= 1'b0;
    end else  begin
        if (csr_err_starve_set) begin
            csr_err_starve_ff <= 1'b1;
        end else     if (csr_err_wen) begin
            if (wstrb[0] && wdata[1]) begin
                csr_err_starve_ff <= 1'b0;
            end
        end else begin
            csr_err_starve_ff <= csr_err_starve_ff;
        end
    end
end


//---------------------
// Bit field:
// ERR[2] - GEOM - A layer's stream geometry disagreed with its SIZE register -- TLAST arrived somewhere other than the configured last pixel of a line, or TUSER somewhere other than the first pixel of a frame. That layer resynchronises at its next input SOF.
// access: rw1c, hardware: s
//---------------------
reg  csr_err_geom_ff;

assign csr_err_rdata[2] = csr_err_geom_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_err_geom_ff <= 1'b0;
    end else  begin
        if (csr_err_geom_set) begin
            csr_err_geom_ff <= 1'b1;
        end else     if (csr_err_wen) begin
            if (wstrb[0] && wdata[2]) begin
                csr_err_geom_ff <= 1'b0;
            end
        end else begin
            csr_err_geom_ff <= csr_err_geom_ff;
        end
    end
end


//---------------------
// Bit field:
// ERR[3] - SRC_STALL - A layer input was held backpressured -- TVALID high, TREADY low because its FIFO was full -- for longer than STALL_LIMIT cycles. The mirror image of OUT_STALL: that source is producing faster than the mixer consumes, which in practice means a frame rate mismatch. Harmless in short bursts, which is why it is measured against a threshold rather than flagged on the first stalled cycle.
// access: rw1c, hardware: s
//---------------------
reg  csr_err_src_stall_ff;

assign csr_err_rdata[3] = csr_err_src_stall_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_err_src_stall_ff <= 1'b0;
    end else  begin
        if (csr_err_src_stall_set) begin
            csr_err_src_stall_ff <= 1'b1;
        end else     if (csr_err_wen) begin
            if (wstrb[0] && wdata[3]) begin
                csr_err_src_stall_ff <= 1'b0;
            end
        end else begin
            csr_err_src_stall_ff <= csr_err_src_stall_ff;
        end
    end
end


//---------------------
// Bit field:
// ERR[4] - OUT_STALL - The downstream sink held TREADY low for longer than the stall threshold while the mixer had a beat to give. Distinguishes 'the display pipeline is blocked' from 'a source is starving', which look identical from a stuck FRAME_COUNT alone.
// access: rw1c, hardware: s
//---------------------
reg  csr_err_out_stall_ff;

assign csr_err_rdata[4] = csr_err_out_stall_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_err_out_stall_ff <= 1'b0;
    end else  begin
        if (csr_err_out_stall_set) begin
            csr_err_out_stall_ff <= 1'b1;
        end else     if (csr_err_wen) begin
            if (wstrb[0] && wdata[4]) begin
                csr_err_out_stall_ff <= 1'b0;
            end
        end else begin
            csr_err_out_stall_ff <= csr_err_out_stall_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x24] - ERR_LAYER - One latched bit per layer, set alongside the per-layer causes in ERR. Names which input is at fault without having to read every layer's status register. Write 1 to a bit to clear that layer alone.
//------------------------------------------------------------------------------
wire [31:0] csr_err_layer_rdata;
assign csr_err_layer_rdata[31:4] = 28'h0;

wire csr_err_layer_wen;
assign csr_err_layer_wen = wen && (waddr == 12'h24);

wire csr_err_layer_ren;
assign csr_err_layer_ren = ren && (raddr == 12'h24);
reg csr_err_layer_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_err_layer_ren_ff <= 1'b0;
    end else begin
        csr_err_layer_ren_ff <= csr_err_layer_ren;
    end
end
//---------------------
// Bit field:
// ERR_LAYER[0] - L0 - Layer 0 has latched a starve, geometry or overflow fault.
// access: rw1c, hardware: s
//---------------------
reg  csr_err_layer_l0_ff;

assign csr_err_layer_rdata[0] = csr_err_layer_l0_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_err_layer_l0_ff <= 1'b0;
    end else  begin
        if (csr_err_layer_l0_set) begin
            csr_err_layer_l0_ff <= 1'b1;
        end else     if (csr_err_layer_wen) begin
            if (wstrb[0] && wdata[0]) begin
                csr_err_layer_l0_ff <= 1'b0;
            end
        end else begin
            csr_err_layer_l0_ff <= csr_err_layer_l0_ff;
        end
    end
end


//---------------------
// Bit field:
// ERR_LAYER[1] - L1 - Layer 1 has latched a starve, geometry or overflow fault.
// access: rw1c, hardware: s
//---------------------
reg  csr_err_layer_l1_ff;

assign csr_err_layer_rdata[1] = csr_err_layer_l1_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_err_layer_l1_ff <= 1'b0;
    end else  begin
        if (csr_err_layer_l1_set) begin
            csr_err_layer_l1_ff <= 1'b1;
        end else     if (csr_err_layer_wen) begin
            if (wstrb[0] && wdata[1]) begin
                csr_err_layer_l1_ff <= 1'b0;
            end
        end else begin
            csr_err_layer_l1_ff <= csr_err_layer_l1_ff;
        end
    end
end


//---------------------
// Bit field:
// ERR_LAYER[2] - L2 - Layer 2 has latched a starve, geometry or overflow fault.
// access: rw1c, hardware: s
//---------------------
reg  csr_err_layer_l2_ff;

assign csr_err_layer_rdata[2] = csr_err_layer_l2_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_err_layer_l2_ff <= 1'b0;
    end else  begin
        if (csr_err_layer_l2_set) begin
            csr_err_layer_l2_ff <= 1'b1;
        end else     if (csr_err_layer_wen) begin
            if (wstrb[0] && wdata[2]) begin
                csr_err_layer_l2_ff <= 1'b0;
            end
        end else begin
            csr_err_layer_l2_ff <= csr_err_layer_l2_ff;
        end
    end
end


//---------------------
// Bit field:
// ERR_LAYER[3] - L3 - Layer 3 has latched a starve, geometry or overflow fault.
// access: rw1c, hardware: s
//---------------------
reg  csr_err_layer_l3_ff;

assign csr_err_layer_rdata[3] = csr_err_layer_l3_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_err_layer_l3_ff <= 1'b0;
    end else  begin
        if (csr_err_layer_l3_set) begin
            csr_err_layer_l3_ff <= 1'b1;
        end else     if (csr_err_layer_wen) begin
            if (wstrb[0] && wdata[3]) begin
                csr_err_layer_l3_ff <= 1'b0;
            end
        end else begin
            csr_err_layer_l3_ff <= csr_err_layer_l3_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x28] - IRQ_EN - Interrupt enable, one bit per ERR bit and in the same order. The irq output is the OR of (ERR & IRQ_EN), so it stays asserted until software clears the ERR bit.
//------------------------------------------------------------------------------
wire [31:0] csr_irq_en_rdata;
assign csr_irq_en_rdata[31:5] = 27'h0;

wire csr_irq_en_wen;
assign csr_irq_en_wen = wen && (waddr == 12'h28);

wire csr_irq_en_ren;
assign csr_irq_en_ren = ren && (raddr == 12'h28);
reg csr_irq_en_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_irq_en_ren_ff <= 1'b0;
    end else begin
        csr_irq_en_ren_ff <= csr_irq_en_ren;
    end
end
//---------------------
// Bit field:
// IRQ_EN[0] - CFG - Enable interrupt on ERR.CFG.
// access: rw, hardware: o
//---------------------
reg  csr_irq_en_cfg_ff;

assign csr_irq_en_rdata[0] = csr_irq_en_cfg_ff;

assign csr_irq_en_cfg_out = csr_irq_en_cfg_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_irq_en_cfg_ff <= 1'b0;
    end else  begin
     if (csr_irq_en_wen) begin
            if (wstrb[0]) begin
                csr_irq_en_cfg_ff <= wdata[0];
            end
        end else begin
            csr_irq_en_cfg_ff <= csr_irq_en_cfg_ff;
        end
    end
end


//---------------------
// Bit field:
// IRQ_EN[1] - STARVE - Enable interrupt on ERR.STARVE.
// access: rw, hardware: o
//---------------------
reg  csr_irq_en_starve_ff;

assign csr_irq_en_rdata[1] = csr_irq_en_starve_ff;

assign csr_irq_en_starve_out = csr_irq_en_starve_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_irq_en_starve_ff <= 1'b0;
    end else  begin
     if (csr_irq_en_wen) begin
            if (wstrb[0]) begin
                csr_irq_en_starve_ff <= wdata[1];
            end
        end else begin
            csr_irq_en_starve_ff <= csr_irq_en_starve_ff;
        end
    end
end


//---------------------
// Bit field:
// IRQ_EN[2] - GEOM - Enable interrupt on ERR.GEOM.
// access: rw, hardware: o
//---------------------
reg  csr_irq_en_geom_ff;

assign csr_irq_en_rdata[2] = csr_irq_en_geom_ff;

assign csr_irq_en_geom_out = csr_irq_en_geom_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_irq_en_geom_ff <= 1'b0;
    end else  begin
     if (csr_irq_en_wen) begin
            if (wstrb[0]) begin
                csr_irq_en_geom_ff <= wdata[2];
            end
        end else begin
            csr_irq_en_geom_ff <= csr_irq_en_geom_ff;
        end
    end
end


//---------------------
// Bit field:
// IRQ_EN[3] - SRC_STALL - Enable interrupt on ERR.SRC_STALL.
// access: rw, hardware: o
//---------------------
reg  csr_irq_en_src_stall_ff;

assign csr_irq_en_rdata[3] = csr_irq_en_src_stall_ff;

assign csr_irq_en_src_stall_out = csr_irq_en_src_stall_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_irq_en_src_stall_ff <= 1'b0;
    end else  begin
     if (csr_irq_en_wen) begin
            if (wstrb[0]) begin
                csr_irq_en_src_stall_ff <= wdata[3];
            end
        end else begin
            csr_irq_en_src_stall_ff <= csr_irq_en_src_stall_ff;
        end
    end
end


//---------------------
// Bit field:
// IRQ_EN[4] - OUT_STALL - Enable interrupt on ERR.OUT_STALL.
// access: rw, hardware: o
//---------------------
reg  csr_irq_en_out_stall_ff;

assign csr_irq_en_rdata[4] = csr_irq_en_out_stall_ff;

assign csr_irq_en_out_stall_out = csr_irq_en_out_stall_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_irq_en_out_stall_ff <= 1'b0;
    end else  begin
     if (csr_irq_en_wen) begin
            if (wstrb[0]) begin
                csr_irq_en_out_stall_ff <= wdata[4];
            end
        end else begin
            csr_irq_en_out_stall_ff <= csr_irq_en_out_stall_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x2c] - STALL_LIMIT - How long a stream may stay stalled before ERR.OUT_STALL or ERR.SRC_STALL latches, in clock cycles. Applies to both directions: the downstream sink holding TREADY low, and a layer source held backpressured on a full FIFO. Reset is 0x10000 -- comfortably longer than any legitimate gap, comfortably shorter than a frame.
//------------------------------------------------------------------------------
wire [31:0] csr_stall_limit_rdata;

wire csr_stall_limit_wen;
assign csr_stall_limit_wen = wen && (waddr == 12'h2c);

wire csr_stall_limit_ren;
assign csr_stall_limit_ren = ren && (raddr == 12'h2c);
reg csr_stall_limit_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_stall_limit_ren_ff <= 1'b0;
    end else begin
        csr_stall_limit_ren_ff <= csr_stall_limit_ren;
    end
end
//---------------------
// Bit field:
// STALL_LIMIT[31:0] - CYCLES - 0 disables the check.
// access: rw, hardware: o
//---------------------
reg [31:0] csr_stall_limit_cycles_ff;

assign csr_stall_limit_rdata[31:0] = csr_stall_limit_cycles_ff;

assign csr_stall_limit_cycles_out = csr_stall_limit_cycles_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_stall_limit_cycles_ff <= 32'h10000;
    end else  begin
     if (csr_stall_limit_wen) begin
            if (wstrb[0]) begin
                csr_stall_limit_cycles_ff[7:0] <= wdata[7:0];
            end
            if (wstrb[1]) begin
                csr_stall_limit_cycles_ff[15:8] <= wdata[15:8];
            end
            if (wstrb[2]) begin
                csr_stall_limit_cycles_ff[23:16] <= wdata[23:16];
            end
            if (wstrb[3]) begin
                csr_stall_limit_cycles_ff[31:24] <= wdata[31:24];
            end
        end else begin
            csr_stall_limit_cycles_ff <= csr_stall_limit_cycles_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x40] - L0_CTRL - Layer 0 enable and alpha. Takes effect at the next output frame boundary.
//------------------------------------------------------------------------------
wire [31:0] csr_l0_ctrl_rdata;
assign csr_l0_ctrl_rdata[7:1] = 7'h0;
assign csr_l0_ctrl_rdata[31:17] = 15'h0;

wire csr_l0_ctrl_wen;
assign csr_l0_ctrl_wen = wen && (waddr == 12'h40);

wire csr_l0_ctrl_ren;
assign csr_l0_ctrl_ren = ren && (raddr == 12'h40);
reg csr_l0_ctrl_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_l0_ctrl_ren_ff <= 1'b0;
    end else begin
        csr_l0_ctrl_ren_ff <= csr_l0_ctrl_ren;
    end
end
//---------------------
// Bit field:
// L0_CTRL[0] - EN - Enable this layer. Layer 0. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
// access: rw, hardware: o
//---------------------
reg  csr_l0_ctrl_en_ff;

assign csr_l0_ctrl_rdata[0] = csr_l0_ctrl_en_ff;

assign csr_l0_ctrl_en_out = csr_l0_ctrl_en_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l0_ctrl_en_ff <= 1'b0;
    end else  begin
     if (csr_l0_ctrl_wen) begin
            if (wstrb[0]) begin
                csr_l0_ctrl_en_ff <= wdata[0];
            end
        end else begin
            csr_l0_ctrl_en_ff <= csr_l0_ctrl_en_ff;
        end
    end
end


//---------------------
// Bit field:
// L0_CTRL[15:8] - ALPHA - Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
// access: rw, hardware: o
//---------------------
reg [7:0] csr_l0_ctrl_alpha_ff;

assign csr_l0_ctrl_rdata[15:8] = csr_l0_ctrl_alpha_ff;

assign csr_l0_ctrl_alpha_out = csr_l0_ctrl_alpha_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l0_ctrl_alpha_ff <= 8'hff;
    end else  begin
     if (csr_l0_ctrl_wen) begin
            if (wstrb[1]) begin
                csr_l0_ctrl_alpha_ff[7:0] <= wdata[15:8];
            end
        end else begin
            csr_l0_ctrl_alpha_ff <= csr_l0_ctrl_alpha_ff;
        end
    end
end


//---------------------
// Bit field:
// L0_CTRL[16] - ALPHA_SRC - Where this layer's alpha comes from.
// access: rw, hardware: o
//---------------------
reg  csr_l0_ctrl_alpha_src_ff;

assign csr_l0_ctrl_rdata[16] = csr_l0_ctrl_alpha_src_ff;

assign csr_l0_ctrl_alpha_src_out = csr_l0_ctrl_alpha_src_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l0_ctrl_alpha_src_ff <= 1'b0;
    end else  begin
     if (csr_l0_ctrl_wen) begin
            if (wstrb[2]) begin
                csr_l0_ctrl_alpha_src_ff <= wdata[16];
            end
        end else begin
            csr_l0_ctrl_alpha_src_ff <= csr_l0_ctrl_alpha_src_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x44] - L0_POS - Layer 0 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
//------------------------------------------------------------------------------
wire [31:0] csr_l0_pos_rdata;

wire csr_l0_pos_wen;
assign csr_l0_pos_wen = wen && (waddr == 12'h44);

wire csr_l0_pos_ren;
assign csr_l0_pos_ren = ren && (raddr == 12'h44);
reg csr_l0_pos_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_l0_pos_ren_ff <= 1'b0;
    end else begin
        csr_l0_pos_ren_ff <= csr_l0_pos_ren;
    end
end
//---------------------
// Bit field:
// L0_POS[15:0] - X - Left edge, 0 is the leftmost canvas pixel.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_l0_pos_x_ff;

assign csr_l0_pos_rdata[15:0] = csr_l0_pos_x_ff;

assign csr_l0_pos_x_out = csr_l0_pos_x_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l0_pos_x_ff <= 16'h0;
    end else  begin
     if (csr_l0_pos_wen) begin
            if (wstrb[0]) begin
                csr_l0_pos_x_ff[7:0] <= wdata[7:0];
            end
            if (wstrb[1]) begin
                csr_l0_pos_x_ff[15:8] <= wdata[15:8];
            end
        end else begin
            csr_l0_pos_x_ff <= csr_l0_pos_x_ff;
        end
    end
end


//---------------------
// Bit field:
// L0_POS[31:16] - Y - Top edge, 0 is the topmost canvas line.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_l0_pos_y_ff;

assign csr_l0_pos_rdata[31:16] = csr_l0_pos_y_ff;

assign csr_l0_pos_y_out = csr_l0_pos_y_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l0_pos_y_ff <= 16'h0;
    end else  begin
     if (csr_l0_pos_wen) begin
            if (wstrb[2]) begin
                csr_l0_pos_y_ff[7:0] <= wdata[23:16];
            end
            if (wstrb[3]) begin
                csr_l0_pos_y_ff[15:8] <= wdata[31:24];
            end
        end else begin
            csr_l0_pos_y_ff <= csr_l0_pos_y_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x48] - L0_SIZE - Layer 0 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
//------------------------------------------------------------------------------
wire [31:0] csr_l0_size_rdata;

wire csr_l0_size_wen;
assign csr_l0_size_wen = wen && (waddr == 12'h48);

wire csr_l0_size_ren;
assign csr_l0_size_ren = ren && (raddr == 12'h48);
reg csr_l0_size_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_l0_size_ren_ff <= 1'b0;
    end else begin
        csr_l0_size_ren_ff <= csr_l0_size_ren;
    end
end
//---------------------
// Bit field:
// L0_SIZE[15:0] - WIDTH - Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_l0_size_width_ff;

assign csr_l0_size_rdata[15:0] = csr_l0_size_width_ff;

assign csr_l0_size_width_out = csr_l0_size_width_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l0_size_width_ff <= 16'h0;
    end else  begin
     if (csr_l0_size_wen) begin
            if (wstrb[0]) begin
                csr_l0_size_width_ff[7:0] <= wdata[7:0];
            end
            if (wstrb[1]) begin
                csr_l0_size_width_ff[15:8] <= wdata[15:8];
            end
        end else begin
            csr_l0_size_width_ff <= csr_l0_size_width_ff;
        end
    end
end


//---------------------
// Bit field:
// L0_SIZE[31:16] - HEIGHT - Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_l0_size_height_ff;

assign csr_l0_size_rdata[31:16] = csr_l0_size_height_ff;

assign csr_l0_size_height_out = csr_l0_size_height_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l0_size_height_ff <= 16'h0;
    end else  begin
     if (csr_l0_size_wen) begin
            if (wstrb[2]) begin
                csr_l0_size_height_ff[7:0] <= wdata[23:16];
            end
            if (wstrb[3]) begin
                csr_l0_size_height_ff[15:8] <= wdata[31:24];
            end
        end else begin
            csr_l0_size_height_ff <= csr_l0_size_height_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x4c] - L0_STATUS - Layer 0 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
//------------------------------------------------------------------------------
wire [31:0] csr_l0_status_rdata;
assign csr_l0_status_rdata[15:3] = 13'h0;


wire csr_l0_status_ren;
assign csr_l0_status_ren = ren && (raddr == 12'h4c);
reg csr_l0_status_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_l0_status_ren_ff <= 1'b0;
    end else begin
        csr_l0_status_ren_ff <= csr_l0_status_ren;
    end
end
//---------------------
// Bit field:
// L0_STATUS[0] - ARMED - 1 once the layer has seen its input SOF and is streaming.
// access: ro, hardware: i
//---------------------
reg  csr_l0_status_armed_ff;

assign csr_l0_status_rdata[0] = csr_l0_status_armed_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_l0_status_armed_ff <= 1'b0;
    end else  begin
              begin            csr_l0_status_armed_ff <= csr_l0_status_armed_in;
        end
    end
end


//---------------------
// Bit field:
// L0_STATUS[1] - DROPPED - 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
// access: ro, hardware: i
//---------------------
reg  csr_l0_status_dropped_ff;

assign csr_l0_status_rdata[1] = csr_l0_status_dropped_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_l0_status_dropped_ff <= 1'b0;
    end else  begin
              begin            csr_l0_status_dropped_ff <= csr_l0_status_dropped_in;
        end
    end
end


//---------------------
// Bit field:
// L0_STATUS[2] - CFG_BAD - 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
// access: ro, hardware: i
//---------------------
reg  csr_l0_status_cfg_bad_ff;

assign csr_l0_status_rdata[2] = csr_l0_status_cfg_bad_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_l0_status_cfg_bad_ff <= 1'b0;
    end else  begin
              begin            csr_l0_status_cfg_bad_ff <= csr_l0_status_cfg_bad_in;
        end
    end
end


//---------------------
// Bit field:
// L0_STATUS[31:16] - FIFO_LEVEL - Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
// access: ro, hardware: i
//---------------------
reg [15:0] csr_l0_status_fifo_level_ff;

assign csr_l0_status_rdata[31:16] = csr_l0_status_fifo_level_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_l0_status_fifo_level_ff <= 16'h0;
    end else  begin
              begin            csr_l0_status_fifo_level_ff <= csr_l0_status_fifo_level_in;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x50] - L1_CTRL - Layer 1 enable and alpha. Takes effect at the next output frame boundary.
//------------------------------------------------------------------------------
wire [31:0] csr_l1_ctrl_rdata;
assign csr_l1_ctrl_rdata[7:1] = 7'h0;
assign csr_l1_ctrl_rdata[31:17] = 15'h0;

wire csr_l1_ctrl_wen;
assign csr_l1_ctrl_wen = wen && (waddr == 12'h50);

wire csr_l1_ctrl_ren;
assign csr_l1_ctrl_ren = ren && (raddr == 12'h50);
reg csr_l1_ctrl_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_l1_ctrl_ren_ff <= 1'b0;
    end else begin
        csr_l1_ctrl_ren_ff <= csr_l1_ctrl_ren;
    end
end
//---------------------
// Bit field:
// L1_CTRL[0] - EN - Enable this layer. Layer 1. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
// access: rw, hardware: o
//---------------------
reg  csr_l1_ctrl_en_ff;

assign csr_l1_ctrl_rdata[0] = csr_l1_ctrl_en_ff;

assign csr_l1_ctrl_en_out = csr_l1_ctrl_en_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l1_ctrl_en_ff <= 1'b0;
    end else  begin
     if (csr_l1_ctrl_wen) begin
            if (wstrb[0]) begin
                csr_l1_ctrl_en_ff <= wdata[0];
            end
        end else begin
            csr_l1_ctrl_en_ff <= csr_l1_ctrl_en_ff;
        end
    end
end


//---------------------
// Bit field:
// L1_CTRL[15:8] - ALPHA - Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
// access: rw, hardware: o
//---------------------
reg [7:0] csr_l1_ctrl_alpha_ff;

assign csr_l1_ctrl_rdata[15:8] = csr_l1_ctrl_alpha_ff;

assign csr_l1_ctrl_alpha_out = csr_l1_ctrl_alpha_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l1_ctrl_alpha_ff <= 8'hff;
    end else  begin
     if (csr_l1_ctrl_wen) begin
            if (wstrb[1]) begin
                csr_l1_ctrl_alpha_ff[7:0] <= wdata[15:8];
            end
        end else begin
            csr_l1_ctrl_alpha_ff <= csr_l1_ctrl_alpha_ff;
        end
    end
end


//---------------------
// Bit field:
// L1_CTRL[16] - ALPHA_SRC - Where this layer's alpha comes from.
// access: rw, hardware: o
//---------------------
reg  csr_l1_ctrl_alpha_src_ff;

assign csr_l1_ctrl_rdata[16] = csr_l1_ctrl_alpha_src_ff;

assign csr_l1_ctrl_alpha_src_out = csr_l1_ctrl_alpha_src_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l1_ctrl_alpha_src_ff <= 1'b0;
    end else  begin
     if (csr_l1_ctrl_wen) begin
            if (wstrb[2]) begin
                csr_l1_ctrl_alpha_src_ff <= wdata[16];
            end
        end else begin
            csr_l1_ctrl_alpha_src_ff <= csr_l1_ctrl_alpha_src_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x54] - L1_POS - Layer 1 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
//------------------------------------------------------------------------------
wire [31:0] csr_l1_pos_rdata;

wire csr_l1_pos_wen;
assign csr_l1_pos_wen = wen && (waddr == 12'h54);

wire csr_l1_pos_ren;
assign csr_l1_pos_ren = ren && (raddr == 12'h54);
reg csr_l1_pos_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_l1_pos_ren_ff <= 1'b0;
    end else begin
        csr_l1_pos_ren_ff <= csr_l1_pos_ren;
    end
end
//---------------------
// Bit field:
// L1_POS[15:0] - X - Left edge, 0 is the leftmost canvas pixel.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_l1_pos_x_ff;

assign csr_l1_pos_rdata[15:0] = csr_l1_pos_x_ff;

assign csr_l1_pos_x_out = csr_l1_pos_x_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l1_pos_x_ff <= 16'h0;
    end else  begin
     if (csr_l1_pos_wen) begin
            if (wstrb[0]) begin
                csr_l1_pos_x_ff[7:0] <= wdata[7:0];
            end
            if (wstrb[1]) begin
                csr_l1_pos_x_ff[15:8] <= wdata[15:8];
            end
        end else begin
            csr_l1_pos_x_ff <= csr_l1_pos_x_ff;
        end
    end
end


//---------------------
// Bit field:
// L1_POS[31:16] - Y - Top edge, 0 is the topmost canvas line.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_l1_pos_y_ff;

assign csr_l1_pos_rdata[31:16] = csr_l1_pos_y_ff;

assign csr_l1_pos_y_out = csr_l1_pos_y_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l1_pos_y_ff <= 16'h0;
    end else  begin
     if (csr_l1_pos_wen) begin
            if (wstrb[2]) begin
                csr_l1_pos_y_ff[7:0] <= wdata[23:16];
            end
            if (wstrb[3]) begin
                csr_l1_pos_y_ff[15:8] <= wdata[31:24];
            end
        end else begin
            csr_l1_pos_y_ff <= csr_l1_pos_y_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x58] - L1_SIZE - Layer 1 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
//------------------------------------------------------------------------------
wire [31:0] csr_l1_size_rdata;

wire csr_l1_size_wen;
assign csr_l1_size_wen = wen && (waddr == 12'h58);

wire csr_l1_size_ren;
assign csr_l1_size_ren = ren && (raddr == 12'h58);
reg csr_l1_size_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_l1_size_ren_ff <= 1'b0;
    end else begin
        csr_l1_size_ren_ff <= csr_l1_size_ren;
    end
end
//---------------------
// Bit field:
// L1_SIZE[15:0] - WIDTH - Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_l1_size_width_ff;

assign csr_l1_size_rdata[15:0] = csr_l1_size_width_ff;

assign csr_l1_size_width_out = csr_l1_size_width_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l1_size_width_ff <= 16'h0;
    end else  begin
     if (csr_l1_size_wen) begin
            if (wstrb[0]) begin
                csr_l1_size_width_ff[7:0] <= wdata[7:0];
            end
            if (wstrb[1]) begin
                csr_l1_size_width_ff[15:8] <= wdata[15:8];
            end
        end else begin
            csr_l1_size_width_ff <= csr_l1_size_width_ff;
        end
    end
end


//---------------------
// Bit field:
// L1_SIZE[31:16] - HEIGHT - Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_l1_size_height_ff;

assign csr_l1_size_rdata[31:16] = csr_l1_size_height_ff;

assign csr_l1_size_height_out = csr_l1_size_height_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l1_size_height_ff <= 16'h0;
    end else  begin
     if (csr_l1_size_wen) begin
            if (wstrb[2]) begin
                csr_l1_size_height_ff[7:0] <= wdata[23:16];
            end
            if (wstrb[3]) begin
                csr_l1_size_height_ff[15:8] <= wdata[31:24];
            end
        end else begin
            csr_l1_size_height_ff <= csr_l1_size_height_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x5c] - L1_STATUS - Layer 1 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
//------------------------------------------------------------------------------
wire [31:0] csr_l1_status_rdata;
assign csr_l1_status_rdata[15:3] = 13'h0;


wire csr_l1_status_ren;
assign csr_l1_status_ren = ren && (raddr == 12'h5c);
reg csr_l1_status_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_l1_status_ren_ff <= 1'b0;
    end else begin
        csr_l1_status_ren_ff <= csr_l1_status_ren;
    end
end
//---------------------
// Bit field:
// L1_STATUS[0] - ARMED - 1 once the layer has seen its input SOF and is streaming.
// access: ro, hardware: i
//---------------------
reg  csr_l1_status_armed_ff;

assign csr_l1_status_rdata[0] = csr_l1_status_armed_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_l1_status_armed_ff <= 1'b0;
    end else  begin
              begin            csr_l1_status_armed_ff <= csr_l1_status_armed_in;
        end
    end
end


//---------------------
// Bit field:
// L1_STATUS[1] - DROPPED - 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
// access: ro, hardware: i
//---------------------
reg  csr_l1_status_dropped_ff;

assign csr_l1_status_rdata[1] = csr_l1_status_dropped_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_l1_status_dropped_ff <= 1'b0;
    end else  begin
              begin            csr_l1_status_dropped_ff <= csr_l1_status_dropped_in;
        end
    end
end


//---------------------
// Bit field:
// L1_STATUS[2] - CFG_BAD - 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
// access: ro, hardware: i
//---------------------
reg  csr_l1_status_cfg_bad_ff;

assign csr_l1_status_rdata[2] = csr_l1_status_cfg_bad_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_l1_status_cfg_bad_ff <= 1'b0;
    end else  begin
              begin            csr_l1_status_cfg_bad_ff <= csr_l1_status_cfg_bad_in;
        end
    end
end


//---------------------
// Bit field:
// L1_STATUS[31:16] - FIFO_LEVEL - Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
// access: ro, hardware: i
//---------------------
reg [15:0] csr_l1_status_fifo_level_ff;

assign csr_l1_status_rdata[31:16] = csr_l1_status_fifo_level_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_l1_status_fifo_level_ff <= 16'h0;
    end else  begin
              begin            csr_l1_status_fifo_level_ff <= csr_l1_status_fifo_level_in;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x60] - L2_CTRL - Layer 2 enable and alpha. Takes effect at the next output frame boundary.
//------------------------------------------------------------------------------
wire [31:0] csr_l2_ctrl_rdata;
assign csr_l2_ctrl_rdata[7:1] = 7'h0;
assign csr_l2_ctrl_rdata[31:17] = 15'h0;

wire csr_l2_ctrl_wen;
assign csr_l2_ctrl_wen = wen && (waddr == 12'h60);

wire csr_l2_ctrl_ren;
assign csr_l2_ctrl_ren = ren && (raddr == 12'h60);
reg csr_l2_ctrl_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_l2_ctrl_ren_ff <= 1'b0;
    end else begin
        csr_l2_ctrl_ren_ff <= csr_l2_ctrl_ren;
    end
end
//---------------------
// Bit field:
// L2_CTRL[0] - EN - Enable this layer. Layer 2. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
// access: rw, hardware: o
//---------------------
reg  csr_l2_ctrl_en_ff;

assign csr_l2_ctrl_rdata[0] = csr_l2_ctrl_en_ff;

assign csr_l2_ctrl_en_out = csr_l2_ctrl_en_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l2_ctrl_en_ff <= 1'b0;
    end else  begin
     if (csr_l2_ctrl_wen) begin
            if (wstrb[0]) begin
                csr_l2_ctrl_en_ff <= wdata[0];
            end
        end else begin
            csr_l2_ctrl_en_ff <= csr_l2_ctrl_en_ff;
        end
    end
end


//---------------------
// Bit field:
// L2_CTRL[15:8] - ALPHA - Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
// access: rw, hardware: o
//---------------------
reg [7:0] csr_l2_ctrl_alpha_ff;

assign csr_l2_ctrl_rdata[15:8] = csr_l2_ctrl_alpha_ff;

assign csr_l2_ctrl_alpha_out = csr_l2_ctrl_alpha_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l2_ctrl_alpha_ff <= 8'hff;
    end else  begin
     if (csr_l2_ctrl_wen) begin
            if (wstrb[1]) begin
                csr_l2_ctrl_alpha_ff[7:0] <= wdata[15:8];
            end
        end else begin
            csr_l2_ctrl_alpha_ff <= csr_l2_ctrl_alpha_ff;
        end
    end
end


//---------------------
// Bit field:
// L2_CTRL[16] - ALPHA_SRC - Where this layer's alpha comes from.
// access: rw, hardware: o
//---------------------
reg  csr_l2_ctrl_alpha_src_ff;

assign csr_l2_ctrl_rdata[16] = csr_l2_ctrl_alpha_src_ff;

assign csr_l2_ctrl_alpha_src_out = csr_l2_ctrl_alpha_src_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l2_ctrl_alpha_src_ff <= 1'b0;
    end else  begin
     if (csr_l2_ctrl_wen) begin
            if (wstrb[2]) begin
                csr_l2_ctrl_alpha_src_ff <= wdata[16];
            end
        end else begin
            csr_l2_ctrl_alpha_src_ff <= csr_l2_ctrl_alpha_src_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x64] - L2_POS - Layer 2 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
//------------------------------------------------------------------------------
wire [31:0] csr_l2_pos_rdata;

wire csr_l2_pos_wen;
assign csr_l2_pos_wen = wen && (waddr == 12'h64);

wire csr_l2_pos_ren;
assign csr_l2_pos_ren = ren && (raddr == 12'h64);
reg csr_l2_pos_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_l2_pos_ren_ff <= 1'b0;
    end else begin
        csr_l2_pos_ren_ff <= csr_l2_pos_ren;
    end
end
//---------------------
// Bit field:
// L2_POS[15:0] - X - Left edge, 0 is the leftmost canvas pixel.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_l2_pos_x_ff;

assign csr_l2_pos_rdata[15:0] = csr_l2_pos_x_ff;

assign csr_l2_pos_x_out = csr_l2_pos_x_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l2_pos_x_ff <= 16'h0;
    end else  begin
     if (csr_l2_pos_wen) begin
            if (wstrb[0]) begin
                csr_l2_pos_x_ff[7:0] <= wdata[7:0];
            end
            if (wstrb[1]) begin
                csr_l2_pos_x_ff[15:8] <= wdata[15:8];
            end
        end else begin
            csr_l2_pos_x_ff <= csr_l2_pos_x_ff;
        end
    end
end


//---------------------
// Bit field:
// L2_POS[31:16] - Y - Top edge, 0 is the topmost canvas line.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_l2_pos_y_ff;

assign csr_l2_pos_rdata[31:16] = csr_l2_pos_y_ff;

assign csr_l2_pos_y_out = csr_l2_pos_y_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l2_pos_y_ff <= 16'h0;
    end else  begin
     if (csr_l2_pos_wen) begin
            if (wstrb[2]) begin
                csr_l2_pos_y_ff[7:0] <= wdata[23:16];
            end
            if (wstrb[3]) begin
                csr_l2_pos_y_ff[15:8] <= wdata[31:24];
            end
        end else begin
            csr_l2_pos_y_ff <= csr_l2_pos_y_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x68] - L2_SIZE - Layer 2 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
//------------------------------------------------------------------------------
wire [31:0] csr_l2_size_rdata;

wire csr_l2_size_wen;
assign csr_l2_size_wen = wen && (waddr == 12'h68);

wire csr_l2_size_ren;
assign csr_l2_size_ren = ren && (raddr == 12'h68);
reg csr_l2_size_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_l2_size_ren_ff <= 1'b0;
    end else begin
        csr_l2_size_ren_ff <= csr_l2_size_ren;
    end
end
//---------------------
// Bit field:
// L2_SIZE[15:0] - WIDTH - Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_l2_size_width_ff;

assign csr_l2_size_rdata[15:0] = csr_l2_size_width_ff;

assign csr_l2_size_width_out = csr_l2_size_width_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l2_size_width_ff <= 16'h0;
    end else  begin
     if (csr_l2_size_wen) begin
            if (wstrb[0]) begin
                csr_l2_size_width_ff[7:0] <= wdata[7:0];
            end
            if (wstrb[1]) begin
                csr_l2_size_width_ff[15:8] <= wdata[15:8];
            end
        end else begin
            csr_l2_size_width_ff <= csr_l2_size_width_ff;
        end
    end
end


//---------------------
// Bit field:
// L2_SIZE[31:16] - HEIGHT - Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_l2_size_height_ff;

assign csr_l2_size_rdata[31:16] = csr_l2_size_height_ff;

assign csr_l2_size_height_out = csr_l2_size_height_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l2_size_height_ff <= 16'h0;
    end else  begin
     if (csr_l2_size_wen) begin
            if (wstrb[2]) begin
                csr_l2_size_height_ff[7:0] <= wdata[23:16];
            end
            if (wstrb[3]) begin
                csr_l2_size_height_ff[15:8] <= wdata[31:24];
            end
        end else begin
            csr_l2_size_height_ff <= csr_l2_size_height_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x6c] - L2_STATUS - Layer 2 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
//------------------------------------------------------------------------------
wire [31:0] csr_l2_status_rdata;
assign csr_l2_status_rdata[15:3] = 13'h0;


wire csr_l2_status_ren;
assign csr_l2_status_ren = ren && (raddr == 12'h6c);
reg csr_l2_status_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_l2_status_ren_ff <= 1'b0;
    end else begin
        csr_l2_status_ren_ff <= csr_l2_status_ren;
    end
end
//---------------------
// Bit field:
// L2_STATUS[0] - ARMED - 1 once the layer has seen its input SOF and is streaming.
// access: ro, hardware: i
//---------------------
reg  csr_l2_status_armed_ff;

assign csr_l2_status_rdata[0] = csr_l2_status_armed_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_l2_status_armed_ff <= 1'b0;
    end else  begin
              begin            csr_l2_status_armed_ff <= csr_l2_status_armed_in;
        end
    end
end


//---------------------
// Bit field:
// L2_STATUS[1] - DROPPED - 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
// access: ro, hardware: i
//---------------------
reg  csr_l2_status_dropped_ff;

assign csr_l2_status_rdata[1] = csr_l2_status_dropped_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_l2_status_dropped_ff <= 1'b0;
    end else  begin
              begin            csr_l2_status_dropped_ff <= csr_l2_status_dropped_in;
        end
    end
end


//---------------------
// Bit field:
// L2_STATUS[2] - CFG_BAD - 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
// access: ro, hardware: i
//---------------------
reg  csr_l2_status_cfg_bad_ff;

assign csr_l2_status_rdata[2] = csr_l2_status_cfg_bad_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_l2_status_cfg_bad_ff <= 1'b0;
    end else  begin
              begin            csr_l2_status_cfg_bad_ff <= csr_l2_status_cfg_bad_in;
        end
    end
end


//---------------------
// Bit field:
// L2_STATUS[31:16] - FIFO_LEVEL - Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
// access: ro, hardware: i
//---------------------
reg [15:0] csr_l2_status_fifo_level_ff;

assign csr_l2_status_rdata[31:16] = csr_l2_status_fifo_level_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_l2_status_fifo_level_ff <= 16'h0;
    end else  begin
              begin            csr_l2_status_fifo_level_ff <= csr_l2_status_fifo_level_in;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x70] - L3_CTRL - Layer 3 enable and alpha. Takes effect at the next output frame boundary.
//------------------------------------------------------------------------------
wire [31:0] csr_l3_ctrl_rdata;
assign csr_l3_ctrl_rdata[7:1] = 7'h0;
assign csr_l3_ctrl_rdata[31:17] = 15'h0;

wire csr_l3_ctrl_wen;
assign csr_l3_ctrl_wen = wen && (waddr == 12'h70);

wire csr_l3_ctrl_ren;
assign csr_l3_ctrl_ren = ren && (raddr == 12'h70);
reg csr_l3_ctrl_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_l3_ctrl_ren_ff <= 1'b0;
    end else begin
        csr_l3_ctrl_ren_ff <= csr_l3_ctrl_ren;
    end
end
//---------------------
// Bit field:
// L3_CTRL[0] - EN - Enable this layer. Layer 3. Layers composite bottom-up in port order, so layer 0 is nearest the background and the highest-numbered enabled layer is on top.
// access: rw, hardware: o
//---------------------
reg  csr_l3_ctrl_en_ff;

assign csr_l3_ctrl_rdata[0] = csr_l3_ctrl_en_ff;

assign csr_l3_ctrl_en_out = csr_l3_ctrl_en_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l3_ctrl_en_ff <= 1'b0;
    end else  begin
     if (csr_l3_ctrl_wen) begin
            if (wstrb[0]) begin
                csr_l3_ctrl_en_ff <= wdata[0];
            end
        end else begin
            csr_l3_ctrl_en_ff <= csr_l3_ctrl_en_ff;
        end
    end
end


//---------------------
// Bit field:
// L3_CTRL[15:8] - ALPHA - Global alpha, 0 transparent to 255 opaque. Multiplied into each pixel's own alpha unless ALPHA_SRC selects otherwise.
// access: rw, hardware: o
//---------------------
reg [7:0] csr_l3_ctrl_alpha_ff;

assign csr_l3_ctrl_rdata[15:8] = csr_l3_ctrl_alpha_ff;

assign csr_l3_ctrl_alpha_out = csr_l3_ctrl_alpha_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l3_ctrl_alpha_ff <= 8'hff;
    end else  begin
     if (csr_l3_ctrl_wen) begin
            if (wstrb[1]) begin
                csr_l3_ctrl_alpha_ff[7:0] <= wdata[15:8];
            end
        end else begin
            csr_l3_ctrl_alpha_ff <= csr_l3_ctrl_alpha_ff;
        end
    end
end


//---------------------
// Bit field:
// L3_CTRL[16] - ALPHA_SRC - Where this layer's alpha comes from.
// access: rw, hardware: o
//---------------------
reg  csr_l3_ctrl_alpha_src_ff;

assign csr_l3_ctrl_rdata[16] = csr_l3_ctrl_alpha_src_ff;

assign csr_l3_ctrl_alpha_src_out = csr_l3_ctrl_alpha_src_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l3_ctrl_alpha_src_ff <= 1'b0;
    end else  begin
     if (csr_l3_ctrl_wen) begin
            if (wstrb[2]) begin
                csr_l3_ctrl_alpha_src_ff <= wdata[16];
            end
        end else begin
            csr_l3_ctrl_alpha_src_ff <= csr_l3_ctrl_alpha_src_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x74] - L3_POS - Layer 3 top-left corner, in canvas pixels. Takes effect at the next output frame boundary, so a moving window never tears.
//------------------------------------------------------------------------------
wire [31:0] csr_l3_pos_rdata;

wire csr_l3_pos_wen;
assign csr_l3_pos_wen = wen && (waddr == 12'h74);

wire csr_l3_pos_ren;
assign csr_l3_pos_ren = ren && (raddr == 12'h74);
reg csr_l3_pos_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_l3_pos_ren_ff <= 1'b0;
    end else begin
        csr_l3_pos_ren_ff <= csr_l3_pos_ren;
    end
end
//---------------------
// Bit field:
// L3_POS[15:0] - X - Left edge, 0 is the leftmost canvas pixel.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_l3_pos_x_ff;

assign csr_l3_pos_rdata[15:0] = csr_l3_pos_x_ff;

assign csr_l3_pos_x_out = csr_l3_pos_x_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l3_pos_x_ff <= 16'h0;
    end else  begin
     if (csr_l3_pos_wen) begin
            if (wstrb[0]) begin
                csr_l3_pos_x_ff[7:0] <= wdata[7:0];
            end
            if (wstrb[1]) begin
                csr_l3_pos_x_ff[15:8] <= wdata[15:8];
            end
        end else begin
            csr_l3_pos_x_ff <= csr_l3_pos_x_ff;
        end
    end
end


//---------------------
// Bit field:
// L3_POS[31:16] - Y - Top edge, 0 is the topmost canvas line.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_l3_pos_y_ff;

assign csr_l3_pos_rdata[31:16] = csr_l3_pos_y_ff;

assign csr_l3_pos_y_out = csr_l3_pos_y_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l3_pos_y_ff <= 16'h0;
    end else  begin
     if (csr_l3_pos_wen) begin
            if (wstrb[2]) begin
                csr_l3_pos_y_ff[7:0] <= wdata[23:16];
            end
            if (wstrb[3]) begin
                csr_l3_pos_y_ff[15:8] <= wdata[31:24];
            end
        end else begin
            csr_l3_pos_y_ff <= csr_l3_pos_y_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x78] - L3_SIZE - Layer 3 size, in pixels. The mixer does not scale: this must match the geometry the input stream actually delivers, or ERR.GEOM latches and the layer is dropped.
//------------------------------------------------------------------------------
wire [31:0] csr_l3_size_rdata;

wire csr_l3_size_wen;
assign csr_l3_size_wen = wen && (waddr == 12'h78);

wire csr_l3_size_ren;
assign csr_l3_size_ren = ren && (raddr == 12'h78);
reg csr_l3_size_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_l3_size_ren_ff <= 1'b0;
    end else begin
        csr_l3_size_ren_ff <= csr_l3_size_ren;
    end
end
//---------------------
// Bit field:
// L3_SIZE[15:0] - WIDTH - Width in pixels. Must be non-zero and X+WIDTH must not exceed the canvas width.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_l3_size_width_ff;

assign csr_l3_size_rdata[15:0] = csr_l3_size_width_ff;

assign csr_l3_size_width_out = csr_l3_size_width_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l3_size_width_ff <= 16'h0;
    end else  begin
     if (csr_l3_size_wen) begin
            if (wstrb[0]) begin
                csr_l3_size_width_ff[7:0] <= wdata[7:0];
            end
            if (wstrb[1]) begin
                csr_l3_size_width_ff[15:8] <= wdata[15:8];
            end
        end else begin
            csr_l3_size_width_ff <= csr_l3_size_width_ff;
        end
    end
end


//---------------------
// Bit field:
// L3_SIZE[31:16] - HEIGHT - Height in lines. Must be non-zero and Y+HEIGHT must not exceed the canvas height.
// access: rw, hardware: o
//---------------------
reg [15:0] csr_l3_size_height_ff;

assign csr_l3_size_rdata[31:16] = csr_l3_size_height_ff;

assign csr_l3_size_height_out = csr_l3_size_height_ff;

always @(posedge clk) begin
    if (!rst) begin
        csr_l3_size_height_ff <= 16'h0;
    end else  begin
     if (csr_l3_size_wen) begin
            if (wstrb[2]) begin
                csr_l3_size_height_ff[7:0] <= wdata[23:16];
            end
            if (wstrb[3]) begin
                csr_l3_size_height_ff[15:8] <= wdata[31:24];
            end
        end else begin
            csr_l3_size_height_ff <= csr_l3_size_height_ff;
        end
    end
end


//------------------------------------------------------------------------------
// CSR:
// [0x7c] - L3_STATUS - Layer 3 live state. Read-only, not latched -- for the latched history see ERR and ERR_LAYER.
//------------------------------------------------------------------------------
wire [31:0] csr_l3_status_rdata;
assign csr_l3_status_rdata[15:3] = 13'h0;


wire csr_l3_status_ren;
assign csr_l3_status_ren = ren && (raddr == 12'h7c);
reg csr_l3_status_ren_ff;
always @(posedge clk) begin
    if (!rst) begin
        csr_l3_status_ren_ff <= 1'b0;
    end else begin
        csr_l3_status_ren_ff <= csr_l3_status_ren;
    end
end
//---------------------
// Bit field:
// L3_STATUS[0] - ARMED - 1 once the layer has seen its input SOF and is streaming.
// access: ro, hardware: i
//---------------------
reg  csr_l3_status_armed_ff;

assign csr_l3_status_rdata[0] = csr_l3_status_armed_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_l3_status_armed_ff <= 1'b0;
    end else  begin
              begin            csr_l3_status_armed_ff <= csr_l3_status_armed_in;
        end
    end
end


//---------------------
// Bit field:
// L3_STATUS[1] - DROPPED - 1 while the layer is being skipped for the rest of the current frame, after a starve or geometry fault.
// access: ro, hardware: i
//---------------------
reg  csr_l3_status_dropped_ff;

assign csr_l3_status_rdata[1] = csr_l3_status_dropped_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_l3_status_dropped_ff <= 1'b0;
    end else  begin
              begin            csr_l3_status_dropped_ff <= csr_l3_status_dropped_in;
        end
    end
end


//---------------------
// Bit field:
// L3_STATUS[2] - CFG_BAD - 1 while this layer's window is rejected as out of bounds or zero-sized. The layer contributes nothing while this is set.
// access: ro, hardware: i
//---------------------
reg  csr_l3_status_cfg_bad_ff;

assign csr_l3_status_rdata[2] = csr_l3_status_cfg_bad_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_l3_status_cfg_bad_ff <= 1'b0;
    end else  begin
              begin            csr_l3_status_cfg_bad_ff <= csr_l3_status_cfg_bad_in;
        end
    end
end


//---------------------
// Bit field:
// L3_STATUS[31:16] - FIFO_LEVEL - Current occupancy of this layer's input FIFO, in pixels. A level pinned at 0 means the source is too slow; pinned at full means the source is ahead and being backpressured, which is healthy.
// access: ro, hardware: i
//---------------------
reg [15:0] csr_l3_status_fifo_level_ff;

assign csr_l3_status_rdata[31:16] = csr_l3_status_fifo_level_ff;


always @(posedge clk) begin
    if (!rst) begin
        csr_l3_status_fifo_level_ff <= 16'h0;
    end else  begin
              begin            csr_l3_status_fifo_level_ff <= csr_l3_status_fifo_level_in;
        end
    end
end


//------------------------------------------------------------------------------
// Write ready
//------------------------------------------------------------------------------
assign wready = 1'b1;

//------------------------------------------------------------------------------
// Read address decoder
//------------------------------------------------------------------------------
reg [31:0] rdata_ff;
always @(posedge clk) begin
    if (!rst) begin
        rdata_ff <= 32'h0;
    end else if (ren) begin
        case (raddr)
            12'h0: rdata_ff <= csr_id_rdata;
            12'h4: rdata_ff <= csr_caps_rdata;
            12'h8: rdata_ff <= csr_scratch_rdata;
            12'hc: rdata_ff <= csr_ctrl_rdata;
            12'h10: rdata_ff <= csr_canvas_rdata;
            12'h14: rdata_ff <= csr_background_rdata;
            12'h18: rdata_ff <= csr_status_rdata;
            12'h1c: rdata_ff <= csr_frame_count_rdata;
            12'h20: rdata_ff <= csr_err_rdata;
            12'h24: rdata_ff <= csr_err_layer_rdata;
            12'h28: rdata_ff <= csr_irq_en_rdata;
            12'h2c: rdata_ff <= csr_stall_limit_rdata;
            12'h40: rdata_ff <= csr_l0_ctrl_rdata;
            12'h44: rdata_ff <= csr_l0_pos_rdata;
            12'h48: rdata_ff <= csr_l0_size_rdata;
            12'h4c: rdata_ff <= csr_l0_status_rdata;
            12'h50: rdata_ff <= csr_l1_ctrl_rdata;
            12'h54: rdata_ff <= csr_l1_pos_rdata;
            12'h58: rdata_ff <= csr_l1_size_rdata;
            12'h5c: rdata_ff <= csr_l1_status_rdata;
            12'h60: rdata_ff <= csr_l2_ctrl_rdata;
            12'h64: rdata_ff <= csr_l2_pos_rdata;
            12'h68: rdata_ff <= csr_l2_size_rdata;
            12'h6c: rdata_ff <= csr_l2_status_rdata;
            12'h70: rdata_ff <= csr_l3_ctrl_rdata;
            12'h74: rdata_ff <= csr_l3_pos_rdata;
            12'h78: rdata_ff <= csr_l3_size_rdata;
            12'h7c: rdata_ff <= csr_l3_status_rdata;
            default: rdata_ff <= 32'h0;
        endcase
    end else begin
        rdata_ff <= 32'h0;
    end
end
assign rdata = rdata_ff;

//------------------------------------------------------------------------------
// Read data valid
//------------------------------------------------------------------------------
reg rvalid_ff;
always @(posedge clk) begin
    if (!rst) begin
        rvalid_ff <= 1'b0;
    end else if (ren && rvalid) begin
        rvalid_ff <= 1'b0;
    end else if (ren) begin
        rvalid_ff <= 1'b1;
    end
end

assign rvalid = rvalid_ff;

endmodule