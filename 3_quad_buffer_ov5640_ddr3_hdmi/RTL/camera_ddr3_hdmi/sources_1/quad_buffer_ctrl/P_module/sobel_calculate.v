`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/06/19 17:09:19
// Design Name: 
// Module Name: sobel_calculate
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 根据输入的灰度图像数据，计算Sobel边缘
// 
// Revision:
// Revision 0.02 - 将行缓存改为参数化line_buffer，支持最高1080p
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module sobel_calculate
#(
    parameter DATA_WIDTH = 8,           // 灰度图像数据固定为8位
    parameter LINE_LEN   = 1920         // 图像行宽（像素数），可按需修改
)
(
    // ==================== 全局信号 ====================
    input                               ui_clk                     ,//mig控制器的ui_clk时钟
    input                               ui_clk_sync_rst            ,

    // ==================== 输入灰度图像数据 ====================
    input                [DATA_WIDTH-1:0] data_in                  ,//需输入8位灰度图像数据
    input                               data_in_valid              ,
    input                               data_in_hs                 ,
    input                               data_in_vs                 ,

    // ==================== 输出灰度图像数据 ====================
    output reg           [DATA_WIDTH-1:0] data_out                 ,//输出的8位灰度数据
    output reg                           data_out_valid             ,
    output reg                           data_out_hs                ,
    output reg                           data_out_vs                 
);

//===============================================================================================================   
//本地参数及接口定义、连线

//行数据
    wire                 [DATA_WIDTH-1:0] line0_data;
    wire                 [DATA_WIDTH-1:0] line1_data;
    wire                 [DATA_WIDTH-1:0] line2_data;

//参与计算Sobel的像素3*3矩阵
    reg  [DATA_WIDTH-1:0] row0_col0;    reg  [DATA_WIDTH-1:0] row1_col0;    reg  [DATA_WIDTH-1:0] row2_col0;
    reg  [DATA_WIDTH-1:0] row0_col1;    reg  [DATA_WIDTH-1:0] row1_col1;    reg  [DATA_WIDTH-1:0] row2_col1;
    reg  [DATA_WIDTH-1:0] row0_col2;    reg  [DATA_WIDTH-1:0] row1_col2;    reg  [DATA_WIDTH-1:0] row2_col2;

//与Gx/Gy卷积核相乘后得到的是正数还是负数
    wire                                Gx_is_positive;
    wire                                Gy_is_positive;

//=================================================
//将输入延迟三拍，用以屏蔽空白边界并匹配流水线延迟
    reg           [2:0]                 data_in_valid_dly;
    reg           [2:0]                 data_in_hs_dly;
    reg           [2:0]                 data_in_vs_dly;

always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
  if (ui_clk_sync_rst) begin
    data_in_valid_dly <= 3'd0;
    data_in_hs_dly    <= 3'd0;
    data_in_vs_dly    <= 3'd0;
  end else begin
    data_in_valid_dly <= {data_in_valid_dly[1:0], data_in_valid};
    data_in_hs_dly    <= {data_in_hs_dly[1:0], data_in_hs};
    data_in_vs_dly    <= {data_in_vs_dly[1:0], data_in_vs};
  end
end

//=================================================
//两行缓存：利用 Block RAM 实现参数化行延迟
// line1_data: 延迟一行（上一行）
// line0_data: 延迟两行（上上行）
image_line_shift_cache #(
    .DATA_WIDTH                         (DATA_WIDTH                ),
    .LINE_LEN                           (LINE_LEN                  ) 
) buf_line1 (
    .clk                                (ui_clk                    ),
    .rst                                (ui_clk_sync_rst           ),
    .data_in_valid                      (data_in_valid             ),
    .data_in                            (data_in                   ),
    .data_out                           (line1_data                ) 
);

image_line_shift_cache #(
    .DATA_WIDTH                         (DATA_WIDTH                ),
    .LINE_LEN                           (LINE_LEN                  ) 
) buf_line0 (
    .clk                                (ui_clk                    ),
    .rst                                (ui_clk_sync_rst           ),
    .data_in_valid                      (data_in_valid             ),
    .data_in                            (line1_data                ),
    .data_out                           (line0_data                ) 
);

assign line2_data = data_in;

//=================================================
// 利用移位寄存器的特性，每新进入一个像素，就将3*3窗口滑动一个像素，重新计算一次卷积
always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
  if(ui_clk_sync_rst) begin
    row0_col0 <= 0;      row1_col0 <= 0;       row2_col0 <= 0;
    row0_col1 <= 0;      row1_col1 <= 0;       row2_col1 <= 0;
    row0_col2 <= 0;      row1_col2 <= 0;       row2_col2 <= 0;
  end
  else if(data_in_hs && data_in_vs)
    if(data_in_valid) begin
      row0_col2 <= line0_data;      row1_col2 <= line1_data;      row2_col2 <= line2_data;
      row0_col1 <= row0_col2;       row1_col1 <= row1_col2;       row2_col1 <= row2_col2;
      row0_col0 <= row0_col1;       row1_col0 <= row1_col1;       row2_col0 <= row2_col1;
    end
    else begin
      row0_col2 <= row0_col2;      row1_col2 <= row1_col2;      row2_col2 <= row2_col2;
      row0_col1 <= row0_col1;      row1_col1 <= row1_col1;      row2_col1 <= row2_col1;
      row0_col0 <= row0_col0;      row1_col0 <= row1_col0;      row2_col0 <= row2_col0;
    end
  else begin
    row0_col0 <= 0;      row1_col0 <= 0;       row2_col0 <= 0;
    row0_col1 <= 0;      row1_col1 <= 0;       row2_col1 <= 0;
    row0_col2 <= 0;      row1_col2 <= 0;       row2_col2 <= 0;
  end
end

//=================================================
// 水平方向变化，检测垂直边缘Gx       垂直方向变化，检测水平边缘Gy                                  
//[-1,0,1]                          [ 1, 2, 1]       
//[-2,0,2]                          [ 0, 0, 0]       
//[-1,0,1]                          [-1,-2,-1]   
//=================================================
//3*3像素矩阵与Gx/Gy卷积核相乘，先判断正负，再计算其绝对值

    reg                  [DATA_WIDTH+1:0] Gx_absolute;  //row0 + row1×2 + row2 每一项最大 255 + 510 + 255 = 1020
    reg                  [DATA_WIDTH+1:0] Gy_absolute;  //1020 需要用 10 位表示，即 DATA_WIDTH + 2 位

assign Gx_is_positive = (row0_col2 + row1_col2*2 + row2_col2) >= (row0_col0 + row1_col0*2 + row2_col0);
assign Gy_is_positive = (row0_col0 + row0_col1*2 + row0_col2) >= (row2_col0 + row2_col1*2 + row2_col2);

always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
  if(ui_clk_sync_rst)
    Gx_absolute <= 0;
  else if(data_in_valid_dly[0]) begin
    if(Gx_is_positive)
      Gx_absolute <= (row0_col2 + row1_col2*2 + row2_col2) - (row0_col0 + row1_col0*2 + row2_col0);
    else
      Gx_absolute <= (row0_col0 + row1_col0*2 + row2_col0) - (row0_col2 + row1_col2*2 + row2_col2);
  end
end

always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
  if(ui_clk_sync_rst)
    Gy_absolute <= 0;
  else if(data_in_valid_dly[0]) begin
    if(Gy_is_positive)
      Gy_absolute <= (row0_col0 + row0_col1*2 + row0_col2) - (row2_col0 + row2_col1*2 + row2_col2);
    else
      Gy_absolute <= (row2_col0 + row2_col1*2 + row2_col2) - (row0_col0 + row0_col1*2 + row0_col2);
  end
end

//=================================================
//输出计算结果

reg [DATA_WIDTH+2:0] gradient_sum_r;

always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
  if (ui_clk_sync_rst)
    gradient_sum_r <= 0;
  else if (data_in_valid_dly[1])
    gradient_sum_r <= Gx_absolute + Gy_absolute;
end

always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
  if(ui_clk_sync_rst)
    data_out <= 0;
  else if(data_in_valid_dly[2]) begin
        if (gradient_sum_r > 255)      // 对于边缘强度超大的值，直接设置为255
          data_out <= 255;
        else
          data_out <= gradient_sum_r[7:0];
        end
end

always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
  if (ui_clk_sync_rst) begin
    data_out_valid <= 1'b0;
    data_out_hs    <= 1'b0;
    data_out_vs    <= 1'b0;
  end else begin
    data_out_valid <= data_in_valid_dly[2];
    data_out_hs    <= data_in_hs_dly[2];
    data_out_vs    <= data_in_vs_dly[2];
  end
end

endmodule