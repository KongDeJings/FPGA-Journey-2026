`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/20
// Design Name: 
// Module Name: rgb_2_gray
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: RGB565 转 8bit 灰度，流水线延迟1拍
// 
// Dependencies: 
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module rgb_2_gray
#(
    parameter DATA_WIDTH = 8            // 输出灰度位宽（固定8）
)
(
    // ==================== 全局信号 ====================
    input                               clk,
    input                               rst,

    // ==================== 输入 RGB565 数据 ====================
    input  [15:0]                       data_in,          // RGB565: {R[4:0],G[5:0],B[4:0]}
    input                               data_in_valid,
    input                               data_in_hs,
    input                               data_in_vs,

    // ==================== 输出灰度数据 ====================
    output reg [DATA_WIDTH-1:0]         data_out,
    output reg                          data_out_valid,
    output reg                          data_out_hs,
    output reg                          data_out_vs
);

//=================================================
// 本地参数与信号
// RGB565 分量提取
wire [4:0] r_in;
wire [5:0] g_in;
wire [4:0] b_in;

assign r_in = data_in[15:11];
assign g_in = data_in[10:5];
assign b_in = data_in[4:0];

// 将 5/6/5 位扩展到 8 位（高位填充低位，避免直接补0造成偏暗）
wire [7:0] r8, g8, b8;
assign r8 = {r_in, r_in[4:2]};         // 5 -> 8 : 重复高3位
assign g8 = {g_in, g_in[5:4]};         // 6 -> 8 : 重复高2位
assign b8 = {b_in, b_in[4:2]};         // 5 -> 8 : 重复高3位

// 灰度加权系数，使用整数乘法并舍入
// Gray = (77*R + 150*G + 29*B + 128) >> 8
wire [15:0] mul_r, mul_g, mul_b;
wire [15:0] sum_rgb;
wire [15:0] sum_rounded;

assign mul_r     = r8 * 8'd77;
assign mul_g     = g8 * 8'd150;
assign mul_b     = b8 * 8'd29;
assign sum_rgb   = mul_r + mul_g + mul_b;
assign sum_rounded = sum_rgb + 16'd128;

//=================================================
// 打拍输出
always @(posedge clk or posedge rst) begin
    if (rst) begin
        data_out       <= {DATA_WIDTH{1'b0}};
        data_out_valid <= 1'b0;
        data_out_hs    <= 1'b0;
        data_out_vs    <= 1'b0;
    end else begin
        // 控制信号延迟一拍
        data_out_valid <= data_in_valid;
        data_out_hs    <= data_in_hs;
        data_out_vs    <= data_in_vs;

        // 输出灰度值，截取高8位
        data_out <= sum_rounded[15:8];
    end
end

endmodule