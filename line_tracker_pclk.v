module line_tracker_pclk #(
  parameter integer ROI_LINES = 40
)(
  input  wire        pclk, reset_n,
  input  wire        vsync, href,
  input  wire        we,               // from ov7670_capture
  input  wire [11:0] pix_rgb444,       // wrdata

  output reg         frame_pulse,
  output reg  [15:0] width_px, height_ln,
  output reg  [15:0] centroid_x,
  output reg         centroid_valid,
  output reg         detected
);
  // edge detect
  reg href_d, vsync_d;  always @(posedge pclk) begin href_d<=href; vsync_d<=vsync; end
  wire href_rise = ~href_d & href, href_fall = href_d & ~href;
  wire vsync_rise = ~vsync_d & vsync; // keep same polarity as your design

  // running x/y & auto width/height
  reg [15:0] x_cnt=0, y_cnt=0, width_latch=0, height_latch=0;
  reg last_line_write=0, first_line_cap=0;

  // threshold
  wire is_yellow;
  yellow_thresh_12b u_th(.rgb444(pix_rgb444), .is_yellow(is_yellow));

  // bottom-ROI gate
  wire [15:0] cur_h = (height_latch!=0)? height_latch : y_cnt;
  wire in_roi = (y_cnt >= ((cur_h>ROI_LINES)? (cur_h-ROI_LINES) : 16'd0));

  // accumulators
  reg [31:0] sum_x=0, sum_n=0;

  always @(posedge pclk or negedge reset_n) begin
    if(!reset_n) begin
      x_cnt<=0; y_cnt<=0; width_latch<=0; height_latch<=0; first_line_cap<=0;
      last_line_write<=0; sum_x<=0; sum_n<=0;
      centroid_x<=0; centroid_valid<=0; detected<=0; frame_pulse<=0;
      width_px<=0; height_ln<=0;
    end else begin
      centroid_valid<=1'b0; frame_pulse<=1'b0;

      if(href_rise) begin
        x_cnt<=0;
        if(last_line_write) begin
          y_cnt<=y_cnt+1'b1;
          if(!first_line_cap) begin width_latch<=x_cnt; first_line_cap<=1'b1; end
          height_latch<=y_cnt+1'b1;
        end
        last_line_write<=1'b0;
      end

      if(we) begin
        last_line_write<=1'b1;
        x_cnt<=x_cnt+1'b1;
        if(in_roi && is_yellow) begin sum_n<=sum_n+1; sum_x<=sum_x+x_cnt; end
      end

      if(vsync_rise) begin
        frame_pulse<=1'b1;
        width_px<=width_latch; height_ln<=height_latch;
        if(sum_n!=0) begin centroid_x<=sum_x/sum_n; detected<=1'b1; end
        else begin centroid_x<=0; detected<=1'b0; end
        centroid_valid<=1'b1;

        // clear for next frame
        x_cnt<=0; y_cnt<=0; width_latch<=0; height_latch<=0; first_line_cap<=0;
        last_line_write<=0; sum_x<=0; sum_n<=0;
      end
    end
  end
endmodule
