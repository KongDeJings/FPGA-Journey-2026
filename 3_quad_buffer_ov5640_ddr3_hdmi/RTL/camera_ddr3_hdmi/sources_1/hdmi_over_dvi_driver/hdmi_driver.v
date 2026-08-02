
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/03 20:09:45
// Design Name: 
// Module Name: hdmi_driver
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description:    input RGB_Data,clock  ,output hdmi singals
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module hdmi_driver(
    input                                        clk                        ,
    input                                        clk_5x                     ,
    input                                        rst_n                      ,
    input                       [  23: 0]        Data_i                     ,

    output                      [  11: 0]        h_counter                  ,
    output                      [  10: 0]        v_counter                  ,
    output                      [2:0]            TMDS_Data_p                ,
    output                      [2:0]            TMDS_Data_n                ,
    output                                       tmds_clk_p                 ,
    output                                       tmds_clk_n                 ,

    output                                       disp_data_req              ,//显示数据请求信号，用以fifo侧读使能
    output                                       frame_begin                ,//用以读fifo清零  
    output                                       VSYNC                      ,
    output                                       DE                         ,

    input                                        camera_w_done               
    );



    wire                                       HSYNC                      ;


    wire                      [  23: 0]        RGB_Data                   ;


vga_ctrl u_vga_ctrl(
    .disp_clk                           (clk                       ),// 输入时钟要根据显示分辨率改变
    .rst_n                              (rst_n                     ),
    .Data_i                             (Data_i                    ),// RGB888
    .RGB_Data_o                         (RGB_Data                  ),//输出的RGB888
    .HSYNC_o                            (HSYNC                     ),// 行同步
    .VSYNC_o                            (VSYNC                     ),// 列同步
    .DE_o                               (DE                        ),// 场同步
    .h_counter_o                        (h_counter                 ),// 这两个计数器的作用是标定数据显示的位置
    .v_counter_o                        (v_counter                 ),
    .disp_data_req                      (disp_data_req             ),// 显示数据请求信号，用以fifo侧读使能
    .frame_begin                        (frame_begin               ),// 用以读fifo清零
    .camera_w_done                      (camera_w_done             ) 
);


hdmi_over_dvi_encode u_hdmi_over_dvi_encode(
    .clk                                (clk                       ),
    .clk_5x                             (clk_5x                    ),
    .rst_n                              (rst_n                     ),
//VGA_signals
    .RGB_data                           (RGB_Data                  ),
    .HSYNC                              (HSYNC                     ),
    .VSYNC                              (VSYNC                     ),
    .DE                                 (DE                        ),
//  HDMI_signals
//tmds_data0 → 蓝通道  tmds_data1 → 绿通道  tmds_data2 → 红通道
    .TMDS_Data_p                        (TMDS_Data_p               ),
    .TMDS_Data_n                        (TMDS_Data_n               ),
    .tmds_clk_p                         (tmds_clk_p                ),
    .tmds_clk_n                         (tmds_clk_n                )
);

endmodule
