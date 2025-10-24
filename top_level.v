// ---------------- top_level.v  (DE2-115 + OV7670 + LED显示 + “半边中断仅占用 LEDR[17]”) ----------------

module top_level (
  input  wire        CLOCK_50,
  input  wire [3:0]  KEY,
  output wire [8:0]  LEDG,
  output wire [17:0] LEDR,
  // VGA
  output wire        VGA_HS,
  output wire        VGA_VS,
  output wire [7:0]  VGA_R,
  output wire [7:0]  VGA_G,
  output wire [7:0]  VGA_B,
  output wire        VGA_BLANK_N,
  output wire        VGA_SYNC_N,
  output wire        VGA_CLK,
  // 七段数码管
  output wire [6:0]  HEX0,
  output wire [6:0]  HEX1,
  output wire [6:0]  HEX2,
  output wire [6:0]  HEX3,
  // 摄像头与 GPIO
  inout  wire [35:0] GPIO
);

  // ---------------- Camera GPIO mapping ----------------
  wire ov7670_pclk;  assign ov7670_pclk  = GPIO[21];
  wire ov7670_xclk;  assign GPIO[20]     = ov7670_xclk;
  wire ov7670_vsync; assign ov7670_vsync = GPIO[23];
  wire ov7670_href;  assign ov7670_href  = GPIO[22];
  wire [7:0] ov7670_data; assign ov7670_data = GPIO[19:12];
  wire ov7670_sioc;  assign GPIO[25]     = ov7670_sioc;
  wire ov7670_siod;  assign GPIO[24]     = ov7670_siod;
  wire ov7670_pwdn;
  wire ov7670_reset; assign GPIO[11]     = ov7670_reset;

  // ---------------- Clocks & control ----------------
  wire clk_50_camera;
  wire clk_25_vga;
  wire wren;
  wire resend;
  wire nBlank;
  wire vSync;
  wire [16:0] wraddress;
  wire [11:0] wrdata;
  wire [16:0] rdaddress;
  wire [11:0] rddata;
  wire [7:0] red;
  wire [7:0] green;
  wire [7:0] blue;
  wire activeArea;

  // 复位（按键抬起=1）
  wire reset_n = KEY[0];

  assign VGA_R = red[7:0];
  assign VGA_G = green[7:0];
  assign VGA_B = blue[7:0];

  // ---------------- PLL ----------------
  my_altpll Inst_vga_pll(
    .inclk0 (CLOCK_50),
    .c0     (clk_50_camera),
    .c1     (clk_25_vga)
  );

  // KEY0 低有效，作为“重发配置”，与原设计保持一致
  assign resend        = ~KEY[0];
  assign VGA_VS        = vSync;
  assign VGA_BLANK_N   = nBlank;

  // ---------------- VGA timing ----------------
  VGA Inst_VGA(
    .CLK25      (clk_25_vga),
    .clkout     (VGA_CLK),
    .Hsync      (VGA_HS),
    .Vsync      (vSync),
    .Nblank     (nBlank),
    .Nsync      (VGA_SYNC_N),
    .activeArea (activeArea)
  );

  // ---------------- OV7670 config ----------------
  wire config_finished; // 如需在 LEDG 显示，可在 line_follow_display 内部处理；此处不改你的 LED 逻辑

  ov7670_controller Inst_ov7670_controller(
    .clk              (clk_50_camera),
    .resend           (resend),
    .config_finished  (config_finished),
    .sioc             (ov7670_sioc),
    .siod             (ov7670_siod),
    .reset            (ov7670_reset),
    .pwdn             (ov7670_pwdn),
    .xclk             (ov7670_xclk)
  );

  // ---------------- Capture ----------------
  ov7670_capture Inst_ov7670_capture(
    .pclk   (ov7670_pclk),
    .vsync  (ov7670_vsync),
    .href   (ov7670_href),
    .d      (ov7670_data),
    .addr   (wraddress),
    .dout   (wrdata),      // 12-bit RGB444: {R4,G4,B4}
    .we     (wren)
  );

  // ---------------- Frame buffer ----------------
  frame_buffer Inst_frame_buffer(
    .rdaddress (rdaddress),
    .rdclock   (clk_25_vga),
    .q         (rddata),
    .wrclock   (ov7670_pclk),
    .wraddress (wraddress[16:0]),
    .data      (wrdata),
    .wren      (wren)
  );

  // ---------------- RGB expand ----------------
  RGB Inst_RGB(
    .Din    (rddata),
    .Nblank (activeArea),
    .R      (red),
    .G      (green),
    .B      (blue)
  );

  // ---------------- Address generator ----------------
  Address_Generator Inst_Address_Generator(
    .CLK25   (clk_25_vga),
    .enable  (activeArea),
    .vsync   (vSync),
    .address (rdaddress)
  );

  // =====================================================================
  // ==============  Yellow-line tracking  ===============================
  // =====================================================================
  wire        lt_frame_pulse;
  wire [15:0] lt_width;
  wire [15:0] lt_height;
  wire [15:0] lt_cx;
  wire        lt_valid;
  wire        lt_detected;

  line_tracker_pclk #(.ROI_LINES(40)) u_line_tracker (
    .pclk           (ov7670_pclk),
    .reset_n        (reset_n),
    .vsync          (ov7670_vsync),
    .href           (ov7670_href),
    .we             (wren),
    .pix_rgb444     (wrdata),          // 12-bit R4G4B4
    .frame_pulse    (lt_frame_pulse),
    .width_px       (lt_width),
    .height_ln      (lt_height),
    .centroid_x     (lt_cx),
    .centroid_valid (lt_valid),
    .detected       (lt_detected)
  );

  // 50MHz 域显示/误差（保持你的 LED 逻辑，不在这里改）
  wire signed [15:0] lf_error;
  wire [17:0] led_from_lfd;
  wire [8:0]  ledg_from_lfd;

  line_follow_display u_lfd (
    .clk               (CLOCK_50),
    .reset_n           (reset_n),
    .pclk_frame_pulse  (lt_frame_pulse),
    .pclk_width        (lt_width),
    .pclk_centroid_x   (lt_cx),
    .pclk_detected     (lt_detected),
    .error             (lf_error),
    .LEDR              (led_from_lfd),  // ← 接到中间线
    .LEDG              (ledg_from_lfd), // ← 接到中间线
    .HEX0              (HEX0),
    .HEX1              (HEX1),
    .HEX2              (HEX2),
    .HEX3              (HEX3)
  );

  // =====================================================================
  // ==============  “半边中断”检测（新增，仅影响 LEDR[17]） ============
  // =====================================================================
  wire half_break_pclk, hb_valid_pclk;
  line_break_pclk #(
  
    .ROI_LINES(40),
    .COVER_PCT(1)
  ) u_line_half (
    .pclk            (ov7670_pclk),
    .reset_n         (reset_n),
    .vsync           (ov7670_vsync),
    .href            (ov7670_href),
    .we              (wren),
    .pix_rgb444      (wrdata),
    .line_half_break (half_break_pclk),
    .valid_pulse     (hb_valid_pclk)
  );

  // 跨域：把 PCLK 的帧结果锁存到 50MHz 域
  reg hb_50m, hb_v1, hb_v2;
  always @(posedge CLOCK_50 or negedge reset_n) begin
    if(!reset_n) begin
      hb_50m <= 1'b0;
      hb_v1  <= 1'b0;
      hb_v2  <= 1'b0;
    end else begin
      hb_v1 <= hb_valid_pclk;
      hb_v2 <= hb_v1;
      if (hb_v1 & ~hb_v2) begin
        hb_50m <= half_break_pclk; // 每帧锁存
      end
    end
  end

  // =====================================================================
  // ==============  最终 LED 映射（只改 LEDR[17]）  =====================
  // =====================================================================
  // 0..16 与 LEDG 完全沿用 line_follow_display 的输出
  assign LEDR[16:0] = led_from_lfd[16:0];
  assign LEDG       = ledg_from_lfd;

  // 17号灯只显示“半边中断”标志（exactly one vertical half has yellow）
  assign LEDR[17]   = hb_50m;

endmodule
