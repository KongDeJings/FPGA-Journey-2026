//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/05/03 10:10:26
// Design Name: 
// Module Name: vga_ctrl
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: generate HS/VS/DE/RGB_DATA
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
////////////////////////    显示器适配列表   //////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////


//`define Resolution_480x272 1       //需要的时钟：9MHz
//`define Resolution_640x480 1       //需要的时钟：25.175MHz
//`define Resolution_800x480 1       //需要的时钟：33MHz
//`define Resolution_800x600 1       //需要的时钟：40MHz
//`define Resolution_1024x768 1      //需要的时钟：65MHz
// `define Resolution_1280x720 1      //需要的时钟：74.25MHz
//`define Resolution_1920x1080 1     //需要的时钟：148.5MHz
// `define Resolution_256x4 1         //需要的时钟：无所谓，仿真专用
`define Resolution_256x2 1        //需要的时钟：无所谓，仿真专用
// `define Resolution_384x2 1
// `define Resolution_1280x2 1

`ifdef Resolution_480x272    
    `define H_Right_Border 0
    `define H_Front_Porch 2
    `define H_Sync_Time 41
    `define H_Back_Porch 2
    `define H_Left_Border 0
    `define H_Data_Time 480
    `define H_Total_Time 525
    `define V_Bottom_Border 0
    `define V_Front_Porch 2
    `define V_Sync_Time 10
    `define V_Back_Porch 2
    `define V_Top_Border 0
    `define V_Data_Time 272
    `define V_Total_Time 286
    
`elsif Resolution_640x480
	`define H_Total_Time  12'd800
	`define H_Right_Border  12'd8
	`define H_Front_Porch  12'd8
	`define H_Sync_Time  12'd96
	`define H_Data_Time 12'd640
	`define H_Back_Porch  12'd40
	`define H_Left_Border  12'd8
	`define V_Total_Time  12'd525
	`define V_Bottom_Border  12'd8
	`define V_Front_Porch  12'd2
	`define V_Sync_Time  12'd2
	`define V_Data_Time 12'd480
	`define V_Back_Porch  12'd25
	`define V_Top_Border  12'd8
	
`elsif Resolution_800x480
	`define H_Total_Time 12'd1056
	`define H_Right_Border 12'd0
	`define H_Front_Porch 12'd40
	`define H_Sync_Time 12'd128
	`define H_Data_Time 12'd800
	`define H_Back_Porch 12'd88
	`define H_Left_Border 12'd0

	`define V_Total_Time 12'd525
	`define V_Bottom_Border 12'd8
	`define V_Front_Porch 12'd2
	`define V_Sync_Time 12'd2
	`define V_Data_Time 12'd480
	`define V_Back_Porch 12'd25
	`define V_Top_Border 12'd8

`elsif Resolution_800x600
	`define H_Total_Time 12'd1056
	`define H_Right_Border 12'd0
	`define H_Front_Porch 12'd40
	`define H_Sync_Time 12'd128
	`define H_Data_Time 12'd800
	`define H_Back_Porch 12'd88
	`define H_Left_Border 12'd0

	`define V_Total_Time 12'd628
	`define V_Bottom_Border 12'd0
	`define V_Front_Porch 12'd1
	`define V_Sync_Time 12'd4
	`define V_Data_Time 12'd600
	`define V_Back_Porch 12'd23
	`define V_Top_Border 12'd0

`elsif Resolution_1024x768
	`define H_Total_Time 12'd1344
	`define H_Right_Border 12'd0
	`define H_Front_Porch 12'd24
	`define H_Sync_Time 12'd136
	`define H_Data_Time 12'd1024
	`define H_Back_Porch 12'd160
	`define H_Left_Border 12'd0

	`define V_Total_Time 12'd806
	`define V_Bottom_Border 12'd0
	`define V_Front_Porch 12'd3
	`define V_Sync_Time 12'd6
	`define V_Data_Time 12'd768
	`define V_Back_Porch 12'd29
	`define V_Top_Border 12'd0

`elsif Resolution_1280x720
	`define H_Total_Time 12'd1650
	`define H_Right_Border 12'd0
	`define H_Front_Porch 12'd110
	`define H_Sync_Time 12'd40
	`define H_Data_Time 12'd1280
	`define H_Back_Porch 12'd220
	`define H_Left_Border 12'd0

	`define V_Total_Time 12'd750
	`define V_Bottom_Border 12'd0
	`define V_Front_Porch 12'd5
	`define V_Sync_Time 12'd5
	`define V_Data_Time 12'd720
	`define V_Back_Porch 12'd20
	`define V_Top_Border 12'd0
		
`elsif Resolution_1920x1080
	`define H_Total_Time 12'd2200
	`define H_Right_Border 12'd0
	`define H_Front_Porch 12'd88
	`define H_Sync_Time 12'd44
	`define H_Data_Time 12'd1920
	`define H_Back_Porch 12'd148
	`define H_Left_Border 12'd0

	`define V_Total_Time 12'd1125
	`define V_Bottom_Border 12'd0
	`define V_Front_Porch 12'd4
	`define V_Sync_Time 12'd5
	`define V_Data_Time 12'd1080
	`define V_Back_Porch 12'd36
	`define V_Top_Border 12'd0	
	
`elsif Resolution_256x4
    // 仿照 1280x720 比例：水平方向按 256/1280=0.2 缩放，垂直方向保留最小合理消隐
    `define H_Total_Time      330     // 256 + 22(HFP) + 8(HS) + 44(HBP)
    `define H_Right_Border    0
    `define H_Front_Porch     22
    `define H_Sync_Time       8
    `define H_Data_Time       256
    `define H_Back_Porch      44
    `define H_Left_Border     0

    `define V_Total_Time      20      // 4 + 2(VFP) + 2(VS) + 12(VBP)
    `define V_Bottom_Border   0
    `define V_Front_Porch     2
    `define V_Sync_Time       2
    `define V_Data_Time       4
    `define V_Back_Porch      12
    `define V_Top_Border      0

`elsif Resolution_256x2
    // 水平方向：256 + 22 + 8 + 44
    `define H_Total_Time      330
    `define H_Right_Border    0
    `define H_Front_Porch     22
    `define H_Sync_Time       8
    `define H_Data_Time       256
    `define H_Back_Porch      44
    `define H_Left_Border     0

    // 垂直方向：2 + 2 + 2 + 12
    `define V_Total_Time      18
    `define V_Bottom_Border   0
    `define V_Front_Porch     2
    `define V_Sync_Time       2
    `define V_Data_Time       2
    `define V_Back_Porch      12
    `define V_Top_Border      0


`elsif Resolution_384x2
    // 仿照 1280x720 比例：水平方向按 384/1280 = 0.3 缩放
    // H_Sync=40*0.3≈12, H_Back_Porch=220*0.3≈66, H_Front_Porch=110*0.3≈33
    `define H_Total_Time      495     // 384 + 33 + 12 + 66
    `define H_Right_Border    0
    `define H_Front_Porch     33
    `define H_Sync_Time       12
    `define H_Data_Time       384
    `define H_Back_Porch      66
    `define H_Left_Border     0

    // 垂直方向：2 有效行 + 2 + 2 + 12
    `define V_Total_Time      18
    `define V_Bottom_Border   0
    `define V_Front_Porch     2
    `define V_Sync_Time       2
    `define V_Data_Time       2
    `define V_Back_Porch      12
    `define V_Top_Border      0

`elsif Resolution_1280x2
 
    `define H_Total_Time      1650
    `define H_Right_Border    0
    `define H_Front_Porch     110
    `define H_Sync_Time       40
    `define H_Data_Time       1280
    `define H_Back_Porch      220
    `define H_Left_Border     0

    `define V_Total_Time      18
    `define V_Bottom_Border   0
    `define V_Front_Porch     2
    `define V_Sync_Time       2
    `define V_Data_Time       2
    `define V_Back_Porch      12
    `define V_Top_Border      0
`endif




//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////

module vga_ctrl(
    input                               disp_clk                   ,//输入时钟要根据显示分辨率改变
    input                               rst_n                      ,
    input                [  23: 0]      Data_i                     ,//RGB888

    output reg           [  23: 0]      RGB_Data_o                 ,
    output                              HSYNC_o                    ,//行同步
    output                              VSYNC_o                    ,//列同步
    output                              DE_o                       ,//场同步
    output reg           [  11: 0]      h_counter_o                ,//这两个计数器的作用是标定数据显示的位置
    output reg           [  10: 0]      v_counter_o                ,

    output reg                          disp_data_req              ,//显示数据请求信号，用以fifo侧读使能
    output reg                          frame_begin                ,//用以读fifo清零      
    input                               camera_w_done 
    );

    reg                  [  11: 0]      H_cnt                      ;//以显示时钟为基本单位。为满足以最大的1920*1080的标准来准备显示器，行要计数2200次
    reg                  [  10: 0]      V_cnt                      ;//该计数器以行扫描计数器记满为单位计数，控制的是列显示

    reg                                 HSYNC                      ;
    reg                  [   2: 0]      HSYNC_o_r                  ;

    reg                                 VSYNC                      ;
    reg                  [   2: 0]      VSYNC_o_r                  ;

    reg                                 DE                         ;
    reg                  [   2: 0]      DE_o_r                     ;


//-----------------------------------------------------------------------------//

parameter HS_begin     = 0;                             //行同步信号使能变为低电平，这一行用来标定位置，没有实际意义
parameter HS_end       = `H_Sync_Time;                  //行同步信号使能完毕，由低电平变为高电平
parameter H_data_begin = `H_Sync_Time+`H_Back_Porch+`H_Left_Border;                      //显示区域开始显示的时间点
parameter H_data_end   = `H_Sync_Time+`H_Back_Porch+`H_Left_Border+`H_Data_Time;         //显示区域结束的时间位置
parameter HSYNC_end    = `H_Total_Time;                 //行显示最终结束的时间

parameter VS_begin     = 0;                             //场同步信号使能变为低电平
parameter VS_end       = `V_Sync_Time;                  //场同步信号使能完毕，由低电平变为高电平
parameter V_data_begin = `V_Sync_Time + `V_Back_Porch + `V_Top_Border;                         //显示区域开始显示的时间点
parameter V_data_end   = `V_Sync_Time + `V_Back_Porch + `V_Top_Border + `V_Data_Time;          //显示区域结束的时间位置
parameter VSYNC_end    = `V_Total_Time;                 //场显示最终结束的时间




//=================================================
//产生行操作计数器，计数到哪一步H_cnt
    always @(posedge disp_clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                H_cnt<=0;                                           
            else if(H_cnt>=(HSYNC_end-1))                                
                H_cnt<=0;                                             
            else
                H_cnt<=H_cnt+1;                                     
        end                                          

//=================================================
//产生列作计数器，计数到哪一步V_cnt
    always @(posedge disp_clk or negedge rst_n)           
        begin                                        
            if(~rst_n)
                V_cnt<=0;
            else if(H_cnt==(HSYNC_end-1)) begin    //扫描完一行，列计数器才增加
                if(V_cnt>=(VSYNC_end-1))
                    V_cnt<=0;
                else
                    V_cnt<=V_cnt+1;        
            end 
            else
                V_cnt<=V_cnt;                                       
        end    

//=================================================
//输出行扫描信号HSYNC_o

    always @(posedge disp_clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                HSYNC<=1;                                   
            else if(H_cnt<(HS_end-1))
                HSYNC<=0;    //从0计数到行同步信号脉冲那么宽的区间，为0；
            else
                HSYNC<=1;   //默认为0                                                               
        end   

    always @(posedge disp_clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                HSYNC_o_r<=3'b0;                                            
            else begin
                HSYNC_o_r[0] <= HSYNC;
                HSYNC_o_r[1] <= HSYNC_o_r[0];                
                HSYNC_o_r[2] <= HSYNC_o_r[1];   
            end                                                                                                                       
        end                                          

assign HSYNC_o= HSYNC_o_r[2];   //使用寄存器打拍，让HSYNC对齐数据                                      
//=================================================
//输出列扫描信号VSYNC_o

    always @(posedge disp_clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                VSYNC<=1;                                   
            else if(V_cnt<(VS_end-1))
                VSYNC<=0;    //与上同理
            else
                VSYNC<=1;   //默认为0                                                               
        end   

    always @(posedge disp_clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                VSYNC_o_r<=3'b0;                                            
            else begin
                VSYNC_o_r[0] <= VSYNC;
                VSYNC_o_r[1] <= VSYNC_o_r[0];                
                VSYNC_o_r[2] <= VSYNC_o_r[1];   
            end                                                                                                                       
        end 

assign VSYNC_o= VSYNC_o_r[2];  //与上同理

//=================================================
//输出场同步信号DE

    always @(posedge disp_clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                DE<=0;                                              
            else if((H_cnt>=H_data_begin-1)&&
                        (H_cnt<H_data_end-1)&&
                            (V_cnt>=V_data_begin-1)&&
                                (V_cnt<V_data_end-1)
                    )
                DE<=1;                                                                                    
            else 
                DE<=0;                                    
        end                                          

    always @(posedge disp_clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                DE_o_r<=3'b0;                                            
            else begin
                DE_o_r[0] <= DE;
                DE_o_r[1] <= DE_o_r[0];                
                DE_o_r[2] <= DE_o_r[1];   
            end                                                                                                                       
        end 

assign DE_o= DE_o_r[2];  //与上同理

//=================================================
//输出显示的数据RGB_Data_o
    always @(posedge disp_clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                RGB_Data_o<=0;                                               
            else if(DE_o_r[0])                                
                RGB_Data_o<=Data_i;
            else
                RGB_Data_o<=0;                                     
        end                                          

//=================================================
//产生标定数据显示的位置的计数器
    always @(posedge disp_clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                h_counter_o<=0;                                   
            else 
                h_counter_o<=(H_cnt - H_data_begin);                                                                                    
                                
        end                                          

    always @(posedge disp_clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                v_counter_o<=0;                                   
            else 
                v_counter_o<=(V_cnt - V_data_begin);                                                                                                                      
        end   

//=================================================
//frame_begin  
//frame_begin在VSYNC的上升沿产生
    always @(posedge disp_clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                frame_begin<=0;                                              
            else if(VSYNC_o_r[2:1]==2'b01)
                frame_begin<=1;                                                                                    
            else 
                frame_begin<=0;                                    
        end 

//=================================================
//为了防止突发错位，使用camera写完一帧来同步
reg camera_w_done_ready;
    always @(posedge disp_clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                camera_w_done_ready<=0;                                              
            else if(camera_w_done)
                camera_w_done_ready<=1;                                                                                                                      
        end 

reg hdmi_vsync_ready;

    always @(posedge disp_clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                hdmi_vsync_ready<=0;                                              
            else if(camera_w_done_ready)begin
                if(frame_begin)begin
                hdmi_vsync_ready<=1;
                end
            end                                                                                                     
        end 


    always @(posedge disp_clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                disp_data_req<=0;                                              
            else if(camera_w_done_ready&&hdmi_vsync_ready)
                disp_data_req<=DE_o_r[0];                                                               
        end 
endmodule
