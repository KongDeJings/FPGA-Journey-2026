`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/05/14 16:43:38
// Design Name: 
// Module Name: dvp_capture
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Additional Comments:
// 代码不可以出现魔数！
//////////////////////////////////////////////////////////////////////////////////
module dvp_capture
#(
  parameter IMAGE_WIDTH     = 12'd800,  // 图像宽度（像素）
  parameter IMAGE_HEIGHT    = 12'd600,  // 图像高度（像素）
  parameter DUMP_FRAMES     = 4'd10    // 舍弃前多少帧
)
(
    // ==================== 全局信号  ====================
    input                               rst_n                                    ,

    // ==================== DVP信号输入  ====================
    input                               vsync                                    ,//场同步信号
    input                               href                                     ,//行有效信号
    input                [   7: 0]      DVP_data                                 ,
    input                               PCLK                                     ,
    // ==================== 对外控制接口 ====================	
    output reg                          frame_rst_state                          ,// 复位时为1，需清空fifo中残留的图像数据
    output reg                          pixel_data_valid                         ,// 图像数据有效（丢弃前10帧信号后），可直接当作fifo的写入信号用
    output reg                          pixel_data_vs                            ,// 行同步
    output reg                          pixel_data_hs                            ,// 场同步
    // ==================== 数据输出    ====================
    output reg           [  15: 0]      pixel_data                               ,// RGB_565信号
    output               [($clog2(IMAGE_WIDTH))-1: 0]haddr                       ,// 标定像素在行的位置,从1开始算起
    output               [($clog2(IMAGE_HEIGHT))-1: 0]vaddr                       // 标定像素在列的位置,从1开始算起
    );

//===============================================================================================================   
   // ==================== 寄存器地址
    reg                  [($clog2(IMAGE_WIDTH*2))-1: 0]h_cnt                    ;//行计数器
    reg                  [($clog2(IMAGE_HEIGHT))-1: 0]v_cnt                     ;//列计数器
    reg                  [4: 0]frame_cnt                  ;//帧计数器，计数目前是第几帧

//=================================================
//将输入的数据打一拍（在PCLK下）,后面所有操作只能在打过拍的信号下产生
    reg                                 vsync_r                    ;
    reg                                 href_r                     ;
    reg                  [   7: 0]      DVP_data_r                 ;

    always @(posedge PCLK or negedge rst_n)           
        begin                                        
            if(!rst_n) begin
                vsync_r   <=0;
                href_r    <=0;
                DVP_data_r<=0;
            end                                                                                                                                          
            else  begin
                vsync_r   <=vsync   ;
                href_r    <=href    ;
                DVP_data_r<=DVP_data;
            end                                   
        end                                                                            

//=================================================
//产生VSYNC、HREF上升沿信号
wire VSYNC_Rising_Pulse;
wire HREF_Rising_Pulse;

assign VSYNC_Rising_Pulse=({vsync_r,vsync}==2'b01);
assign HREF_Rising_Pulse=({href_r,href}==2'b01);
//=================================================
//产生h_cnt
    always @(posedge PCLK or negedge rst_n)           
        begin                                        
            if(!rst_n) 
                h_cnt<=0;                                     
            else if(href_r)
                h_cnt<=h_cnt+1;                        
            else 
                h_cnt<=0;    //在行有效信号无效时，将计数器归零                                                 
        end   

assign haddr=h_cnt[($clog2(IMAGE_WIDTH*2))-1: 1];  //行地址标记是行计数器的一半

//===========================
//产生pixel_data，必须用时序逻辑
    always @(posedge PCLK or negedge rst_n)           
        begin                                        
            if(!rst_n) 
                pixel_data<=0;                                     
            else if(h_cnt[0])                                                                                                         
                pixel_data[7:0]<=DVP_data_r;                                                     
            else
                pixel_data[15:8]<=DVP_data_r;                                        
        end   


//=================================================
//产生v_cnt
        always @(posedge PCLK or negedge rst_n)           
        begin                                        
            if(!rst_n) 
                v_cnt<=0;    
            else if(vsync_r)
                v_cnt<=0;                                  
            else if(HREF_Rising_Pulse)
                v_cnt<=v_cnt+1;                        
            else 
                v_cnt<=v_cnt;                                                 
        end  

assign vaddr = v_cnt;      //列地址标记是列计数器

//=================================================
//产生frame_cnt
always @(posedge PCLK or negedge rst_n) begin
    if(!rst_n) 
        frame_cnt <= 0;    
    else if(VSYNC_Rising_Pulse && (frame_cnt < DUMP_FRAMES))
        frame_cnt <= frame_cnt + 1;
end


//=================================================
//产生frame_valid,该信号指示哪些帧是有效的（除去抛弃的前10帧内容，后续都是有效的）
reg frame_valid;
        always @(posedge PCLK or negedge rst_n)           
        begin                                        
            if(!rst_n) 
                frame_valid<=0;    
            else if(frame_cnt==DUMP_FRAMES)     //计数到10后保持不动，此时数据已经稳定
                frame_valid<=1;                                                     
            else 
                frame_valid<=0;                                                 
        end  

//=================================================
// 产生pixel_data_valid（与pixel_data严格对齐）
always @(posedge PCLK or negedge rst_n) begin
    if(!rst_n) 
        pixel_data_valid <= 0;
    else
        pixel_data_valid <= (href_r && h_cnt[0] && frame_valid);
end

//=================================================
//产生frame_rst_state
        always @(posedge PCLK or negedge rst_n)           
        begin                                        
            if(!rst_n) 
                frame_rst_state<=1;    
            else if(vsync_r)     
                frame_rst_state<=0;                                                                                                     
        end     

//=================================================
//产生行同步、场同步信号
    always @(posedge PCLK or negedge rst_n)           
        begin                                        
            if(!rst_n) begin
                pixel_data_hs<=0;
                pixel_data_vs<=0;
            end                                                                              
            else  begin
                pixel_data_hs<=(href_r&&frame_valid);
                pixel_data_vs<=(~vsync_r&&frame_valid);
            end                                   
        end  

endmodule
