`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/23 14:35:08
// Design Name: 
// Module Name: pixel_count_write_ctrl
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
module pixel_count_write_ctrl
#(
    parameter                           W_FIFO_RD_DATA_CNT_WIDTH    = 11                   ,
    parameter                           FIFO_USER_DATA_WIDTH        = 16                   ,  //fifo din/dout的位宽，异步FIFO内部完成 16bit → 128bit 位宽拼接，转到AXI4时为128bit       
    parameter                           RGB_PIC_DATA_WIDTH          = 16                   ,
    // ==================== 有关输出的图像信息 ====================
    parameter                           IMAGE_WIDTH                 = 1280                 ,//图片宽度
    parameter                           IMAGE_HEIGHT                = 720                  
)
(
    // ==================== 全局信号 ====================
    input                               clk                               ,// 处理时钟
    input                               reset                             ,// 高有效复位


    // ==================== 输入的视频信号 ====================
    input                [RGB_PIC_DATA_WIDTH-1: 0]video_data_out          ,// RGB565数据输出
    input                               video_data_out_valid              ,// 输出有效
    input                               video_data_out_hs                 ,// 输出行同步
    input                               video_data_out_vs                 ,// 输出场同步


    // ==================== 输入的fifo写入信号 ====================.
    input                                  full_proc_w_fifo               ,
    input  [W_FIFO_RD_DATA_CNT_WIDTH-1: 0] wr_data_count_proc_w_fifo      ,
    output      [ FIFO_USER_DATA_WIDTH-1: 0]    din_proc_w_fifo           ,
    output                                   wr_en_proc_w_fifo         ,

      
    // ==================== 对外输出p模块写完信号 ====================
    output reg                              p_w_done
    );

//===============================================================================================================
//逻辑输出
assign din_proc_w_fifo=video_data_out;
assign  wr_en_proc_w_fifo = video_data_out_valid && (!full_proc_w_fifo);
//===============================================
//输出当前帧写完信号
    always @(posedge clk or posedge reset) begin
        if (reset)
            p_w_done <= 0;
        else if (video_data_out_valid&&~video_data_out_hs&& ~video_data_out_vs)
             p_w_done <= 1;          // 当前帧结束
        else
            p_w_done <= 0;
    end

    
endmodule
