`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/05/15 14:39:57
// Design Name: 
// Module Name: camera_monitor
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 代码不许魔数！
//////////////////////////////////////////////////////////////////////////////////

module camera_monitor
#(
    parameter SYS_CLOCK = 50_000_000,      //系统时钟频率
    parameter FPS_MAX   = 120       ,       //帧率最大值
    parameter DIV_NUM   = 255       ,       //在PCLK下每256次输出一个分频脉冲
    parameter   CNT_BIT    = 24             // 频率计数位宽，24 位可以测量最高 4.3GHz 的时钟频率
    
)
(
    input                               clk                        ,
    input                               rst_n                      ,
    input                               PCLK                       ,
    input                               vsync                      ,

    output reg   [($clog2(FPS_MAX))-1:0]     fps                   ,
    output reg [($clog2(SYS_CLOCK))-1:0] PCLK_measure                
    );
//=================================================
//将vsync打拍
reg [3:0]vsync_r;
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
               vsync_r<=0;                                                                   
            else
               vsync_r<={vsync_r[2:0],vsync};                                      
        end                                          
//=================================================
//计时1秒，用以计算帧率
reg [($clog2(SYS_CLOCK))-1:0] sec_cnt;
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                sec_cnt<=0;                                   
            else if(sec_cnt==SYS_CLOCK-1)//计时1s
                sec_cnt<=0;                                                                 
            else
                sec_cnt<=sec_cnt+1;                                    
        end                                          
//=================================================
//对帧进行计数
reg [($clog2(FPS_MAX))-1:0] fps_cnt;
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                fps_cnt<=0;                                   
            else if(sec_cnt==SYS_CLOCK-1)                                
                fps_cnt<=0;   //计数满1秒，归零                                     
            else if(vsync_r[3:2] == 2'b01)                                    
                fps_cnt<=fps_cnt+1; //vsync出现上升沿，则帧计数器加一
            else
                fps_cnt<=fps_cnt;                                        
        end  
//=================================================
//输出帧率
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                fps<=0;                                       
            else if(sec_cnt==SYS_CLOCK-1)   //计数满1秒，则输出结果                             
                fps<= fps_cnt;                                    
            else   
                fps<=fps;                                  
        end                                          
//=================================================
// PCLK 预分频计数器：从0一直数到255，用来把高速PCLK降速,每256个PCLK周期计数一次
reg [($clog2(DIV_NUM))-1:0] pre_div_cnt;

always @(posedge PCLK or negedge rst_n)
if(!rst_n)
    pre_div_cnt <= 0;         // 复位清零
else
    pre_div_cnt <= pre_div_cnt + 1'd1;  // PCLK 每个周期 +1

//=================================================
//跨时钟域同步：用慢速 clk 采样 PCLK 分频后的信号
//同时打2拍同步，防止亚稳态，检测上升沿
reg [3:0] r_pre256_PCLK; 
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
               r_pre256_PCLK<=0;                                                                   
            else
               r_pre256_PCLK<={r_pre256_PCLK[2:0], pre_div_cnt[7]};                                    
        end         

//=================================================
//PCLK 周期计数器：每秒清零一次，统计 1 秒内，Pclk 经过 256 分频后的周期个数
reg [23:0] pre_PCLK_cnt;

    always @(posedge clk or negedge rst_n)
    if(!rst_n)
        pre_PCLK_cnt <= 0;       
    else if(sec_cnt == SYS_CLOCK - 1)         // 每秒到了，清零重新计数
        pre_PCLK_cnt <= 0;
    else if(r_pre256_PCLK[3:2] == 2'b01)      // 检测到PCLK分频信号上升沿
        pre_PCLK_cnt <= pre_PCLK_cnt + 1'd1;  

//=================================================
//结果 ×256 = 真实 Pclk 频率

always @(posedge clk or negedge rst_n)
if(!rst_n)       
    PCLK_measure <=0;
else if(sec_cnt == SYS_CLOCK - 1)  // 每秒更新一次 PCLK 频率
    PCLK_measure <= {pre_PCLK_cnt, 8'd0};  // 左移8位 = ×256  
else
    PCLK_measure <=PCLK_measure;  

endmodule
