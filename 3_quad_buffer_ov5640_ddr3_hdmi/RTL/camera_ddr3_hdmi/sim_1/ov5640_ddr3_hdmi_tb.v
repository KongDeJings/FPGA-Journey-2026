`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/30
// Design Name: 
// Module Name: ov5640_ddr3_hdmi_tb
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

module ov5640_ddr3_hdmi_tb;

    // ==================== 仿真图像参数 ====================
    parameter   WIDTH       = 256;
    parameter   HEIGHT      = 2;

    // ==================== 信号定义 ====================
    reg                         rst_n;
    reg                         vsync;
    reg                         href;
    reg   [   7: 0]             DVP_data;
    reg                         PCLK;
    reg                         clk;

    integer i, j;

    // ==================== 时钟生成 ====================
    always #23 PCLK = ~PCLK;    // 22MHz，完全模拟摄像头 
    always #10 clk  = ~clk;

    // ==================== 测试主流程 ====================
    initial begin
        // 初始值
        rst_n    = 1;
        PCLK     = 1;
        clk      = 1;
        vsync    = 0;
        href     = 0;
        DVP_data = 8'h00;

        // 复位
        #2  rst_n = 0;
        #805 rst_n = 1;


        #400;
        @ (posedge PCLK);#6
        // 开始发送图像数据，永久循环
        repeat(30) begin
            // ---- 场同步 ----
            vsync = 1;
            #120;
            vsync = 0;
            #300;

            // ---- 逐行扫描 ----
            for (i = 0; i < HEIGHT; i = i + 1) begin
                for (j = 0; j < WIDTH; j = j + 1) begin
                    href = 1;
                    // 第一字节前4位：行号（pixel_data[15:8]）
                    DVP_data = {i[3:0],j[11:8]};
                    @ (posedge PCLK);#6;
                    // 第二字节：列号（pixel_data[7:0]）
                    DVP_data = j[7:0];
                    @ (posedge PCLK);#6;
                end
                href = 0;
                #300;
            end
        end
    end

    // ==================== DUT 例化 ====================
ov5640_ddr3_hdmi_testbench #(
    .IMAGE_WIDTH                        (WIDTH                     ),
    .IMAGE_HEIGHT                       (HEIGHT                    ),
    .DUMP_FRAMES                        (1                         ) 
    ) u_ov5640_ddr3_hdmi (
    .clk                                (clk                       ),
    .rst_n                              (rst_n                     ),
    .camera_pclk                        (PCLK                      ),
    .camera_vsync                       (vsync                     ),
    .camera_href                        (href                      ),
    .camera_data                        (DVP_data                  ) 
    );

endmodule