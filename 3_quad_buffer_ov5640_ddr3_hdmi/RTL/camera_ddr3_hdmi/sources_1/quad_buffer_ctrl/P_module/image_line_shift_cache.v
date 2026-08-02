`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/19 17:03:31
// Design Name: 
// Module Name: image_line_shift_cache
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module image_line_shift_cache
#(
    parameter DATA_WIDTH = 8,         // 像素位宽
    parameter LINE_LEN   = 1920       // 行长度，最大 2048，支持 1080p

)
(
    input                       clk,
    input                       rst,
    input                       data_in_valid,
    input  [DATA_WIDTH-1:0]     data_in,
    output [DATA_WIDTH-1:0]     data_out
);

    // 自动计算地址位宽
    localparam ADDR_WIDTH = $clog2(LINE_LEN);

    // Block RAM 存储体（强制综合为 BRAM）
    (* ram_style = "block" *) 
    reg [DATA_WIDTH-1:0] ram [0:LINE_LEN-1];


    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;

    // 读写指针控制
    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
        end
         else if (data_in_valid) begin
            // 写入数据
            ram[wr_ptr] <= data_in;

            // 写指针递增
            if (wr_ptr == (LINE_LEN - 1))
                wr_ptr <= 0;
            else
                wr_ptr <= wr_ptr + 1'b1;

            // 读指针同样逻辑
            if (rd_ptr == (LINE_LEN - 1))
                rd_ptr <= 0;
            else
                rd_ptr <= rd_ptr + 1'b1;
        end
    end

    // 读数据输出
    assign data_out = ram[rd_ptr];

endmodule
