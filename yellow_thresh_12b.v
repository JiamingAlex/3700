module yellow_thresh_12b #(
  parameter R_TH = 8'd200,   // R 下限（可调）
  parameter G_TH = 8'd200,   // G 下限（可调）
  parameter B_MAX= 8'd120    // B 上限（可调）
)(
  input  wire [11:0] rgb444, // {R[11:8], G[7:4], B[3:0]}
  output wire        is_yellow
);
  wire [7:0] r8 = {rgb444[11:8], rgb444[11:8]}; // 4->8
  wire [7:0] g8 = {rgb444[7:4],  rgb444[7:4] };
  wire [7:0] b8 = {rgb444[3:0],  rgb444[3:0] };

  assign is_yellow = (r8 >= R_TH) && (g8 >= G_TH) && (b8 <= B_MAX);
endmodule
