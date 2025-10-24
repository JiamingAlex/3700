// line_break_pclk.v — Half-break detector (Verilog-2001)
module line_break_pclk #(
  parameter integer ROI_LINES = 40,  // bottom ROI height (lines)
  parameter integer COVER_PCT = 8    // per-half coverage threshold (%)
)(
  input  wire        pclk,
  input  wire        reset_n,
  input  wire        vsync,
  input  wire        href,
  input  wire        we,
  input  wire [11:0] pix_rgb444,

  output reg         line_half_break,  // 1 only when exactly one half passes
  output reg         valid_pulse       // 1 for one pclk at frame end
);

  // Use your yellow threshold module
  wire is_yellow;
  yellow_thresh_12b u_yth (
    .rgb444    (pix_rgb444),
    .is_yellow (is_yellow)
  );

  // x/y counters and width/height measure
  reg [15:0] x_cnt, y_cnt, width_px, height_ln;
  always @(posedge pclk or negedge reset_n) begin
    if(!reset_n) begin
      x_cnt<=0; y_cnt<=0; width_px<=0; height_ln<=0;
    end else begin
      if (vsync) begin
        height_ln <= y_cnt;
        x_cnt<=0; y_cnt<=0;
      end else if (href) begin
        if (we) x_cnt <= x_cnt + 16'd1;
      end else begin
        if (x_cnt != 16'd0) begin
          width_px <= x_cnt;
          x_cnt<=0; y_cnt<=y_cnt + 16'd1;
        end
      end
    end
  end

  // Bottom ROI split into upper/lower halves
  wire [15:0] roi_top = (height_ln > ROI_LINES) ? (height_ln - ROI_LINES) : 16'd0;
  wire        in_roi   = (y_cnt >= roi_top);
  wire [15:0] roi_mid  = roi_top + (ROI_LINES >> 1);
  wire        in_upper = in_roi && (y_cnt <  roi_mid);
  wire        in_lower = in_roi && (y_cnt >= roi_mid);

  // Per-half coverage counters
  reg [31:0] sum_upper, sum_lower;

  always @(posedge pclk or negedge reset_n) begin
    if(!reset_n) begin
      sum_upper<=0; sum_lower<=0; line_half_break<=1'b0; valid_pulse<=1'b0;
    end else begin
      valid_pulse <= 1'b0;

      if (we && in_roi && is_yellow) begin
        if (in_upper) sum_upper <= sum_upper + 32'd1;
        else          sum_lower <= sum_lower + 32'd1;
      end

      // Frame end: evaluate “half break” (XOR only)
      if (vsync) begin
        reg [15:0] wp;
        reg [31:0] half_area, th_half_cover;
        reg        upper_ok, lower_ok;

        wp = (width_px == 16'd0) ? 16'd1 : width_px;
        half_area     = wp * (ROI_LINES >> 1);
        th_half_cover = (half_area * COVER_PCT) / 100;

        upper_ok = (sum_upper > th_half_cover);
        lower_ok = (sum_lower > th_half_cover);

        line_half_break <= ~(upper_ok & lower_ok); // exactly one half OK
        valid_pulse     <= 1'b1;

        sum_upper<=0; sum_lower<=0;
      end
    end
  end
endmodule
