`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/23 14:35:08
// Design Name: 
// Module Name: pixel_count_request_ctrl
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


module pixel_count_request_ctrl
#(
    parameter                           R_FIFO_RD_DATA_CNT_WIDTH    = 11                   ,
    parameter                           FIFO_USER_DATA_WIDTH        = 16                   ,  //fifo din/dout的位宽，异步FIFO内部完成 16bit → 128bit 位宽拼接，转到AXI4时为128bit       
    parameter                           RGB_PIC_DATA_WIDTH          = 16                   ,
    // ==================== 有关输出的图像信息 ====================
    parameter                           IMAGE_WIDTH                 = 1280                 ,//图片宽度
    parameter                           IMAGE_HEIGHT                = 720                  
)
(
    // ==================== 全局信号 ====================
    input                               clk                            ,// 处理时钟
    input                               reset                          ,// 高有效复位

    // ==================== 帧启动信号 ====================
    input                               p_switch_pulse,                 // 四缓冲控制器给的开始脉冲
    // ==================== 输入的fifo数据流 ====================
    input [FIFO_USER_DATA_WIDTH-1: 0]       dout_proc_r_fifo           ,
    input                                   empty_proc_r_fifo          ,
    input [R_FIFO_RD_DATA_CNT_WIDTH-1: 0]   rd_data_count_proc_r_fifo  ,

    // ==================== 对外输出的fifo控制信号 ====================
    output reg                              rd_en_proc_r_fifo          ,
    output reg [($clog2(IMAGE_WIDTH))-1: 0] video_data_hcnt            ,
    output reg [($clog2(IMAGE_HEIGHT))-1: 0]video_data_vcnt            ,
    // ==================== 对外输出的视频信号 ====================
    output               [RGB_PIC_DATA_WIDTH-1: 0]video_data           ,// RGB565数据输出
    output reg                              video_data_valid           ,// 输出数据有效
    output reg                              video_data_hs              ,// 输出行同步
    output reg                              video_data_vs              ,// 输出场同步    
    // ==================== 对外输出p模块读完信号 ====================
    output reg                              p_r_done
    );

//===============================================================================================================
//逻辑输出

    assign                              video_data                  = dout_proc_r_fifo     ;//产生的图像数据流直接与fifo输出的数据流直连

//=================================================
//指示数据有效
    always @(posedge clk or posedge reset)           
        begin                                        
            if(reset)                               
                video_data_valid<=0;                                                 
            else 
                video_data_valid<=rd_en_proc_r_fifo;//fifo出数据延后一拍，因此打了一拍
        end                                          


//=================================================
//产生fifo读使能信号

    reg  frame_active;      // 当前正在处理一帧
    // 帧激活标志
    always @(posedge clk or posedge reset) begin
        if (reset)
            frame_active <= 0;
        else if (p_switch_pulse)
            frame_active <= 1;          // 新帧开始
        else if (p_r_done)
            frame_active <= 0;          // 当前帧结束
    end


    always @(posedge clk or posedge reset) begin
        if (reset)
            rd_en_proc_r_fifo <= 0;
        else if (p_switch_pulse)
            rd_en_proc_r_fifo <= 1;     // 最高优先级：新帧来了就启动
        else if (p_r_done)
            rd_en_proc_r_fifo <= 0;     // 一帧读完停止
        else if (empty_proc_r_fifo)
            rd_en_proc_r_fifo <= 0;     // FIFO空了暂停
        else if (frame_active)
            rd_en_proc_r_fifo <= 1;     // 正常读
        else
            rd_en_proc_r_fifo <= 0;
    end

    
//=================================================
//产生hs,vs信号
  //generate image data hs or vs
  always@(posedge clk or posedge reset)
    if(reset)
      video_data_hcnt <= 0;
    else if (p_switch_pulse)
        video_data_hcnt <= 0;   // 新帧开始，强制清零
    else if(video_data_valid) begin
      if(video_data_hcnt == (IMAGE_WIDTH - 1))
        video_data_hcnt <= 0;
      else
        video_data_hcnt <= video_data_hcnt + 1;
    end

  always@(posedge clk or posedge reset)
    if(reset)
      video_data_vcnt <= 0;
    else if (p_switch_pulse)
        video_data_vcnt <= 0;   // 新帧开始，强制清零
    else if(video_data_valid) begin
      if(video_data_hcnt == (IMAGE_WIDTH - 1)) begin
        if(video_data_vcnt == (IMAGE_HEIGHT - 1))
          video_data_vcnt <= 0;
        else
          video_data_vcnt <= video_data_vcnt + 1;
      end
    end
  //hs
  always@(posedge clk or posedge reset)
    if(reset)
      video_data_hs <= 0;
    else if(video_data_valid && video_data_hcnt == (IMAGE_WIDTH - 1))
      video_data_hs <= 0;
    else
      video_data_hs <= 1;
  //vs
  always@(posedge clk or posedge reset)
    if(reset)
      video_data_vs <= 0;
    else if(video_data_valid && video_data_hcnt == (IMAGE_WIDTH - 1) &&
            video_data_vcnt == (IMAGE_HEIGHT - 1))
      video_data_vs <= 0;
    else
      video_data_vs <= 1;

//=================================================
//产生p模块读完一帧信号
  always@(posedge clk or posedge reset)
    if(reset)
      p_r_done<= 0;
    else if(video_data_valid && video_data_hcnt == (IMAGE_WIDTH - 1) &&
            video_data_vcnt == (IMAGE_HEIGHT - 1))
      p_r_done<= 1;
    else
     p_r_done<= 0;





endmodule
