`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/20
// Design Name: 
// Module Name: gray_2_rgb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 灰度图转 RGB565，支持灰度直出 / 二值化
// 
// Dependencies: 
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module gray_2_rgb
#(
    parameter DATA_WIDTH = 8,           // 输入灰度位宽
    parameter PROC_TYPE  = 0,           // 0:灰度直出  1:二值化
    parameter THRESHOLD  = 125          // 二值化阈值（仅 PROC_TYPE=1 时有效）
)
(
    // ==================== 全局信号 ====================
    input                               clk,
    input                               rst,

    // ==================== 输入灰度图像数据 ====================
    input  [DATA_WIDTH-1:0]             data_in,
    input                               data_in_valid,
    input                               data_in_hs,
    input                               data_in_vs,

    // ==================== 输出 RGB565 图像数据 ====================
    output reg [15:0]                   data_out,
    output reg                          data_out_valid,
    output reg                          data_out_hs,
    output reg                          data_out_vs
);

//=================================================
// 灰度 → RGB565 转换（组合逻辑）
//  R[4:0] = gray[7:3]
//  G[5:0] = gray[7:2]
//  B[4:0] = gray[7:3]
wire [4:0] r_comp;
wire [5:0] g_comp;
wire [4:0] b_comp;

assign r_comp = data_in[7:3];
assign g_comp = data_in[7:2];
assign b_comp = data_in[7:3];

// 组合生成 RGB565 灰度值
wire [15:0] gray_rgb565;
assign gray_rgb565 = {r_comp, g_comp, b_comp};

//=================================================
// 输出选择与打拍（实现 PROC_TYPE 0/1）
always @(posedge clk or posedge rst) begin
    if (rst) begin
        data_out       <= 16'd0;
        data_out_valid <= 1'b0;
        data_out_hs    <= 1'b0;
        data_out_vs    <= 1'b0;
    end
     else begin
        // 控制信号直接打一拍，与数据对齐
        data_out_valid <= data_in_valid;
        data_out_hs    <= data_in_hs;
        data_out_vs    <= data_in_vs;

        // 根据 PROC_TYPE 选择输出
        if (PROC_TYPE == 0) begin
            // 灰度模式：直接输出转换后的 RGB565
            data_out <= gray_rgb565;
        end else begin
            // 二值化模式：比较阈值
            if (data_in > THRESHOLD)
                data_out <= 16'hFFFF;   // 白色
            else
                data_out <= 16'h0000;   // 黑色
        end
    end
end

endmodule