`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/13 11:22:13
// Design Name: 
// Module Name: ddr3_double_buffer_ctrl_tb
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


module ddr3_double_buffer_ctrl_tb(

    );



reg clk, reset;
reg w_done, r_done;
wire w_buf, r_buf, w_addr_switch_pulse, r_addr_switch_pulse;

// 产生时钟
always #5 clk = ~clk;  // 100MHz

// 例化你的控制模块
ddr3_double_buffer_ctrl uut (
    .ui_clk                             (clk                       ),
    .reset                              (reset                     ),
    .w_done                             (w_done                    ),
    .r_done                             (r_done                    ),
    .w_buf                              (w_buf                     ),
    .w_addr_switch_pulse                (w_addr_switch_pulse       ),
    .r_buf                              (r_buf                     ),
    .r_addr_switch_pulse                (r_addr_switch_pulse       ) 
);

// 模拟摄像头30fps (33.33ms) → 在100MHz下约3.33e6个周期
// 用简单周期数模拟，比如写完成每33333个时钟
// 读完成每16667个时钟
reg [31:0] cnt;
always @(posedge clk) begin
    cnt <= cnt + 1;
    w_done <= (cnt % 33333 == 0);
    r_done <= (cnt % 16667 == 0);
end

initial begin
    clk = 0; reset = 1; cnt = 0;
    #100 reset = 0;
    #5000000 $finish;
end

endmodule    

