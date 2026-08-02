//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/03 14:43:17
// Design Name: 
// Module Name: hdmi_over_dvi_encode
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description:   output HDMI signals！
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module hdmi_over_dvi_encode(
    input                               clk                        ,
    input                               clk_5x                     ,
    input                               rst_n                      ,

//VGA_signals
    input                [  23: 0]      RGB_data                   ,
    input                               HSYNC                      ,
    input                               VSYNC                      ,
    input                               DE                         ,

//  HDMI_signals
//tmds_data0 → 蓝通道  tmds_data1 → 绿通道  tmds_data2 → 红通道
    output               [   2: 0]      TMDS_Data_p                ,
    output               [   2: 0]      TMDS_Data_n                ,

    output                              tmds_clk_p                 ,
    output                              tmds_clk_n                  
    );


//=================================================
//第一步，将R/G/B通道的数据及其控制信号送入TMDS模块编码

wire [9:0]Blue_tmds_data;
wire [9:0]Green_tmds_data;
wire [9:0]Red_tmds_data;

tmds_encode Blue_tmds_data_encode(
    .clk                                (clk                       ),// 像素时钟输入
    .rst_n                              (rst_n                     ),// 异步复位
    .din                                (RGB_data[ 7: 0]           ),// 蓝色8位数据信号
    .c0                                 (HSYNC                     ),// c0 输入
    .c1                                 (VSYNC                     ),// c1 输入
    .DE                                 (DE                        ),// 数据使能，输入
    .dout                               (Blue_tmds_data            )// 数据输出
);

tmds_encode Green_tmds_data_encode(
    .clk                                (clk                       ),// 像素时钟输入
    .rst_n                              (rst_n                     ),// 异步复位
    .din                                (RGB_data[15: 8]           ),// 绿色8位数据信号
    .c0                                 (0                         ),// c0 输入
    .c1                                 (0                         ),// c1 输入
    .DE                                 (DE                        ),// 数据使能，输入
    .dout                               (Green_tmds_data           )// 数据输出
);

tmds_encode Red_tmds_data_encode(
    .clk                                (clk                       ),// 像素时钟输入
    .rst_n                              (rst_n                     ),// 异步复位
    .din                                (RGB_data[23:16]           ),// 红色8位数据信号
    .c0                                 (0                         ),// c0 输入
    .c1                                 (0                         ),// c1 输入
    .DE                                 (DE                        ),// 数据使能，输入
    .dout                               (Red_tmds_data             )// 数据输出
);


//=================================================
//第二步，按照same edge模式，将tmds_data转为ODDR的D1/D2信号，并将ODDR输出的串行信号转为差分信号输出

reg [2:0]op_cnt;//same edge 计数器
    always @(posedge clk_5x or negedge rst_n)           
        begin                                        
            if(~rst_n )                               
                op_cnt<=0;                                   
            else if(op_cnt>=4)
                op_cnt<=0;                                                                     
            else
                op_cnt<=op_cnt+1;                                     
        end                                          


//按照SAME EDGE将10位从TMDS送出的数据重新排列为高、低位
//wire [4:0] TMDS_XX_l = {9,7,5,3,1};
//wire [4:0] TMDS_xx_h = {8,6,4,2,0};

wire [4:0] TMDS_Blue_l = {Blue_tmds_data[9],Blue_tmds_data[7],Blue_tmds_data[5],Blue_tmds_data[3],Blue_tmds_data[1]};
wire [4:0] TMDS_Blue_h = {Blue_tmds_data[8],Blue_tmds_data[6],Blue_tmds_data[4],Blue_tmds_data[2],Blue_tmds_data[0]};
wire [4:0] TMDS_Green_l = {Green_tmds_data[9],Green_tmds_data[7],Green_tmds_data[5],Green_tmds_data[3],Green_tmds_data[1]};
wire [4:0] TMDS_Green_h = {Green_tmds_data[8],Green_tmds_data[6],Green_tmds_data[4],Green_tmds_data[2],Green_tmds_data[0]};
wire [4:0] TMDS_Red_l = {Red_tmds_data[9],Red_tmds_data[7],Red_tmds_data[5],Red_tmds_data[3],Red_tmds_data[1]};
wire [4:0] TMDS_Red_h = {Red_tmds_data[8],Red_tmds_data[6],Red_tmds_data[4],Red_tmds_data[2],Red_tmds_data[0]};
//channel4固定输出
wire[9:0] Clock_tmds_data;
assign Clock_tmds_data=10'b11111_00000;  
wire [4:0] TMDS_Clock_l = {Clock_tmds_data[9],Clock_tmds_data[7],Clock_tmds_data[5],Clock_tmds_data[3],Clock_tmds_data[1]};
wire [4:0] TMDS_Clock_h = {Clock_tmds_data[8],Clock_tmds_data[6],Clock_tmds_data[4],Clock_tmds_data[2],Clock_tmds_data[0]};


reg[4:0]TMDS_shift_Blue_h;
reg[4:0]TMDS_shift_Blue_l;
reg[4:0]TMDS_shift_Green_h;
reg[4:0]TMDS_shift_Green_l;
reg[4:0]TMDS_shift_Red_h;
reg[4:0]TMDS_shift_Red_l;
reg[4:0]TMDS_shift_Clock_h;
reg[4:0]TMDS_shift_Clock_l;

always @(posedge clk_5x or negedge rst_n)           
    begin                                        
        if(~rst_n ) begin
TMDS_shift_Blue_h   <=5'b0;
TMDS_shift_Blue_l   <=5'b0;
TMDS_shift_Green_h  <=5'b0;            
TMDS_shift_Green_l  <=5'b0;
TMDS_shift_Red_h    <=5'b0;
TMDS_shift_Red_l    <=5'b0;
TMDS_shift_Clock_h  <=5'b0;
TMDS_shift_Clock_l  <=5'b0;
        end                                                               
        else if(op_cnt==4)begin
            TMDS_shift_Blue_l   <=TMDS_Blue_l  ;
            TMDS_shift_Blue_h   <=TMDS_Blue_h  ;
            TMDS_shift_Green_l  <=TMDS_Green_l ;
            TMDS_shift_Green_h  <=TMDS_Green_h ;
            TMDS_shift_Red_l    <=TMDS_Red_l   ;
            TMDS_shift_Red_h    <=TMDS_Red_h   ;
            TMDS_shift_Clock_l  <=TMDS_Clock_l ;
            TMDS_shift_Clock_h  <=TMDS_Clock_h ;
        end                                                                                  
        else begin
            TMDS_shift_Blue_l   <=TMDS_shift_Blue_l        >> 1;//右移，取D1/D2为移位寄存器最低位[0]，先送出去的是低位数据，符合ODDR要求
            TMDS_shift_Blue_h   <=TMDS_shift_Blue_h        >> 1;
            TMDS_shift_Green_l  <=TMDS_shift_Green_l       >> 1;
            TMDS_shift_Green_h  <=TMDS_shift_Green_h       >> 1;
            TMDS_shift_Red_l    <=TMDS_shift_Red_l         >> 1;
            TMDS_shift_Red_h    <=TMDS_shift_Red_h         >> 1;
            TMDS_shift_Clock_l  <= TMDS_shift_Clock_l      >> 1;
            TMDS_shift_Clock_h  <= TMDS_shift_Clock_h      >> 1;  
        end
    end                                          

//将ODDR输出的串行数据与OBUFDS连线
wire Blue_data_out;
wire Green_data_out;
wire Red_data_out;
wire Clock_data_out;

//=================================================蓝色通道
ODDR #(
   .DDR_CLK_EDGE("SAME_EDGE"), // "OPPOSITE_EDGE" or "SAME_EDGE" 
   .INIT(1'b0),    // Initial value of Q: 1'b0 or 1'b1
   .SRTYPE("SYNC") // Set/Reset type: "SYNC" or "ASYNC" 
) 
Blue_ODDR (
    .Q                                  (Blue_data_out             ),// 1-bit DDR output
    .C                                  (clk_5x                    ),// 1-bit clock input
    .CE                                 (1'b1                      ),// 1-bit clock enable input
    .D1                                 (TMDS_shift_Blue_h[0]      ),// 1-bit data input (positive edge)
    .D2                                 (TMDS_shift_Blue_l[0]      ),// 1-bit data input (negative edge)
    .R                                  (1'b0                      ),// 1-bit reset
    .S                                  (1'b0                      ) // 1-bit set
);
//--------------------
OBUFDS #(
  .IOSTANDARD("DEFAULT"), // Specify the output I/O standard
  .SLEW("SLOW")           // Specify the output slew rate
) Blue_OBUFDS (
    .O                                  (TMDS_Data_p[0]            ),// Diff_p output (connect directly to top-level port)
    .OB                                 (TMDS_Data_n[0]            ),// Diff_n output (connect directly to top-level port)
    .I                                  (Blue_data_out             ) // Buffer input
);




//=================================================绿色通道
ODDR #(
   .DDR_CLK_EDGE("SAME_EDGE"),    .INIT(1'b0),       .SRTYPE("SYNC") ) 
Green_ODDR (
    .Q                                  (Green_data_out            ),
    .C                                  (clk_5x                    ),
    .CE                                 (1'b1                      ),
    .D1                                 (TMDS_shift_Green_h[0]     ),
    .D2                                 (TMDS_shift_Green_l[0]     ),
    .R                                  (1'b0                      ),
    .S                                  (1'b0                      ) 
);
//--------------------
OBUFDS #(  .IOSTANDARD("DEFAULT"),  .SLEW("SLOW") ) 
Green_OBUFDS 
(
    .O                                  (TMDS_Data_p[1]            ),
    .OB                                 (TMDS_Data_n[1]            ),
    .I                                  (Green_data_out            ) 
);




//=================================================红色通道
ODDR #(
   .DDR_CLK_EDGE("SAME_EDGE"),    .INIT(1'b0),       .SRTYPE("SYNC") ) 
Red_ODDR (
    .Q                                  (Red_data_out              ),
    .C                                  (clk_5x                    ),
    .CE                                 (1'b1                      ),
    .D1                                 (TMDS_shift_Red_h[0]       ),
    .D2                                 (TMDS_shift_Red_l[0]       ),
    .R                                  (1'b0                      ),
    .S                                  (1'b0                      ) 
);
//--------------------
OBUFDS #(  .IOSTANDARD("DEFAULT"),  .SLEW("SLOW") ) 
Red_OBUFDS 
(
    .O                                  (TMDS_Data_p[2]            ),
    .OB                                 (TMDS_Data_n[2]            ),
    .I                                  (Red_data_out              ) 
);




//=================================================时钟通道
ODDR #(
   .DDR_CLK_EDGE("SAME_EDGE"),    .INIT(1'b0),       .SRTYPE("SYNC") ) 
clock_ODDR (
    .Q                                  (Clock_data_out            ),
    .C                                  (clk_5x                    ),
    .CE                                 (1'b1                      ),
    .D1                                 (TMDS_shift_Clock_h[0]     ),
    .D2                                 (TMDS_shift_Clock_l[0]     ),
    .R                                  (1'b0                      ),
    .S                                  (1'b0                      ) 
);
//--------------------
OBUFDS #(  .IOSTANDARD("DEFAULT"),  .SLEW("SLOW") ) 
Clock_OBUFDS 
(
    .O                                  (tmds_clk_p                ),
    .OB                                 (tmds_clk_n                ),
    .I                                  (Clock_data_out            ) 
);

endmodule
