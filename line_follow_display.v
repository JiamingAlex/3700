// ---------- Verilog-2001 compatible line_follow_display.v ----------
module line_follow_display #(
  parameter integer MAX_W = 640
)(
  input  wire        clk,
  input  wire        reset_n,
  // PCLK 域帧结果（跨域：这里做最小同步）
  input  wire        pclk_frame_pulse,
  input  wire [15:0] pclk_width,
  input  wire [15:0] pclk_centroid_x,
  input  wire        pclk_detected,

  output reg  signed [15:0] error,   // 质心-中心
  output reg  [17:0]        LEDR,
  output reg  [8:0]         LEDG,
  output reg  [6:0]         HEX0, HEX1, HEX2, HEX3
);

  // 7段译码（Verilog-2001 function）
  function [6:0] hex7seg;
    input [3:0] v;
    begin
      case (v)
        4'h0: hex7seg=7'b1000000; 4'h1: hex7seg=7'b1111001;
        4'h2: hex7seg=7'b0100100; 4'h3: hex7seg=7'b0110000;
        4'h4: hex7seg=7'b0011001; 4'h5: hex7seg=7'b0010010;
        4'h6: hex7seg=7'b0000010; 4'h7: hex7seg=7'b1111000;
        4'h8: hex7seg=7'b0000000; 4'h9: hex7seg=7'b0010000;
        4'hA: hex7seg=7'b0001000; 4'hB: hex7seg=7'b0000011;
        4'hC: hex7seg=7'b1000110; 4'hD: hex7seg=7'b0100001;
        4'hE: hex7seg=7'b0000110; 4'hF: hex7seg=7'b0001110;
      endcase
    end
  endfunction

  // 生成低位 N 个 1 的掩码（替代 [n-1:0] 可变切片）
  function [17:0] ones_mask18;
    input [4:0] count; // 0..18
    integer i;
    begin
      ones_mask18 = 18'd0;
      for (i=0; i<18; i=i+1)
        if (i < count) ones_mask18[i] = 1'b1;
    end
  endfunction

  // ====== 简单 CDC：把帧脉冲“加宽”一拍，防漏采 ======
  reg fp_d;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) fp_d <= 1'b0;
    else          fp_d <= pclk_frame_pulse;
  end
  wire frame_strobe = fp_d | pclk_frame_pulse;

  // 锁存来自 PCLK 的结果
  reg [15:0] width_reg, cx_reg;
  reg        det_reg;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      width_reg <= 16'd0;
      cx_reg    <= 16'd0;
      det_reg   <= 1'b0;
    end else if (frame_strobe) begin
      width_reg <= (pclk_width==16'd0) ? MAX_W[15:0] : pclk_width;
      cx_reg    <= pclk_centroid_x;
      det_reg   <= pclk_detected;
    end
  end

  // 计算误差 error = cx - width/2
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      error <= 16'sd0;
    end else begin
      if (width_reg != 16'd0)
        error <= $signed({1'b0, cx_reg}) - $signed({1'b0, (width_reg>>1)});
      else
        error <= 16'sd0;
    end
  end

  // 下面用模块级临时量，避免在 always 内再声明
  integer     n;               // 点亮LED的个数 (0..17)
  reg [15:0]  abs_e;           // |error|
  reg [17:0]  mask;            // 低位n个1的掩码
  reg signed [15:0] e;         // 误差副本（带符号）

  // 驱动 LED / HEX
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      LEDR <= 18'd0;
      LEDG <= 9'd0;
      HEX0 <= 7'h7f; HEX1 <= 7'h7f; HEX2 <= 7'h7f; HEX3 <= 7'h7f;
    end else begin
      // 清空
      LEDR <= 18'd0;
      LEDG <= 9'd0;

      if (!det_reg) begin
        // 未检测到黄线→报警
        LEDR[17] <= 1'b1;
        abs_e    <= 16'd0;
      end else begin
        // 计算 |error| 与强度 n
        e     <= error;
        abs_e <= e[15] ? (~e + 16'd1) : e;
        // n = min(17, abs_e[4:0]) 作为简单强度映射
        n     <= (abs_e > 16'd17) ? 17 : abs_e[4:0];
        mask  <= ones_mask18(n[4:0]);

        if (e[15]) begin
          // 左侧（负误差）点亮红灯
          LEDR <= mask;
        end else begin
          // 右侧（正误差）点亮绿灯低 9 位
          LEDG[8:0] <= mask[8:0];
        end
      end

      // HEX 显示 |error|（三位十六进制）
      HEX0 <= hex7seg(abs_e[3:0]);
      HEX1 <= hex7seg(abs_e[7:4]);
      HEX2 <= hex7seg(abs_e[11:8]);
      HEX3 <= hex7seg(4'h0);
    end
  end

endmodule
