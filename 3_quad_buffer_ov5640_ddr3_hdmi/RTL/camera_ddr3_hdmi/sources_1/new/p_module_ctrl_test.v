`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/26 20:14:43
// Design Name: 
// Module Name: p_module_ctrl_test
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


module p_module_ctrl_test
#(

    // ==================== FIFO相关参数 ====================
    parameter                           FIFO_USER_DATA_WIDTH        = 16                   ,  //fifo din/dout的位宽，异步FIFO内部完成 16bit → 128bit 位宽拼接，转到AXI4时为128bit
    parameter                           R_FIFO_RD_DATA_CNT_WIDTH    = 11                   ,
    parameter                           R_FIFO_WR_DATA_CNT_WIDTH    = 8                    ,
    parameter                           W_FIFO_RD_DATA_CNT_WIDTH    = 8                    ,
    parameter                           W_FIFO_WR_DATA_CNT_WIDTH    = 11                   ,
    // ==================== 地址与数据参数 ====================
    parameter                           IN_BUF_0                    = 32'h0000_0000        ,//写入乒乓缓存A基地址，P读与cam写乒乓
    parameter                           IN_BUF_1                    = 32'h0080_0000        ,//写入乒乓缓存B基地址，P读与cam写乒乓
    parameter                           PROC_BUF_0                  = 32'h0100_0000        ,//写入乒乓缓存A基地址，P写与hdmi读乒乓
    parameter                           PROC_BUF_1                  = 32'h0180_0000        ,//写入乒乓缓存B基地址，P写与hdmi读乒乓

    parameter                           AXI_DATA_WIDTH              = 128                  ,
    parameter                           AXI_ADDR_WIDTH              = 32                   ,
    parameter                           AXI_ID_WIDTH                = 4                    ,
    parameter                           PROC_P_AXI_ID               = 4'b0010              ,
    parameter                           AXI_BURST_LEN               = 31                   ,

    // ==================== AXI 固定协议参数 ====================
    parameter                           AXI_ARBURST_INCR            = 2'b01                ,
    parameter                           AXI_ARLOCK_NORMAL           = 1'b0                 ,
    parameter                           AXI_ARCACHE_DEVICE_NON_BUF  = 4'b0000              ,
    parameter                           AXI_ARPROT_UNPRIV_SECURE    = 3'b000               ,
    parameter                           AXI_ARQOS_DEFAULT           = 4'b0000              ,
    parameter                           AXI_ARREGION_DEFAULT        = 4'b0000              ,
    parameter                           AXI_RRESP_OKAY              = 2'b00                ,

    parameter                           AXI_AWBURST_INCR            = 2'b01                ,
    parameter                           AXI_AWLOCK_NORMAL           = 1'b0                 ,
    parameter                           AXI_AWCACHE_DEVICE_NON_BUF  = 4'b0000              ,
    parameter                           AXI_AWPROT_UNPRIV_SECURE    = 3'b000               ,
    parameter                           AXI_AWQOS_DEFAULT           = 4'b0000              ,
    parameter                           AXI_AWREGION_DEFAULT        = 4'b0000              ,
    parameter                           AXI_BRESP_OKAY              = 2'b00                ,
    parameter                           AXI_WSTRB_ALL_VALID         = 1'b1                 ,
    parameter                           AXI_RESET_POLARITY          = 1'b1                 ,

        // ==================== 有关输出的图像信息 ====================
    parameter                           IMAGE_WIDTH                 = 1280                 ,//图片宽度
    parameter                           IMAGE_HEIGHT                = 720                  ,

    // ==================== 有关sobel处理的相关信息 ====================
    parameter                           GRAY_PIC_DATA_WIDTH         = 8                    ,// 灰度图像素位宽
    parameter                           RGB_PIC_DATA_WIDTH          = 16                   ,// 灰度图像素位宽
    parameter                           PROC_TYPE                   = 0                    ,// 0:灰度直出  1:二值化
    parameter                           THRESHOLD                   = 125                  ,// 二值化阈值（仅 PROC_TYPE=1 时有效）
    parameter                           LINE_LEN                    = 1920                  // 行长度，最大 2048，支持 1080p
)
(
    input                               clk                        ,// 处理时钟
    input                               reset                      ,// 高有效复位

    input                       [AXI_DATA_WIDTH-1: 0]        din_proc_r_fifo             ,
    input                                                    wr_en_proc_r_fifo           ,
    output                                                   full_proc_r_fifo            ,
    input           [R_FIFO_WR_DATA_CNT_WIDTH-1: 0]          wr_data_count_proc_r_fifo   ,

    input           p_switch_pulse
    );



//===============================================================================================================   
//本地参数及接口定义、连线


    // ==================== proc_r_module_fifo接口 ====================
    wire                                           rd_en_proc_r_fifo          ;
    wire  [ FIFO_USER_DATA_WIDTH-1: 0]             dout_proc_r_fifo           ;
    wire                                           empty_proc_r_fifo          ;
    wire  [R_FIFO_RD_DATA_CNT_WIDTH-1: 0]          rd_data_count_proc_r_fifo  ;

    // ==================== proc_w_module_fifo接口 ====================

    wire  [ FIFO_USER_DATA_WIDTH-1: 0]               din_proc_w_fifo            ;
    wire                                             wr_en_proc_w_fifo          ;
    wire                                             full_proc_w_fifo           ;
    wire  [W_FIFO_WR_DATA_CNT_WIDTH-1: 0]            wr_data_count_proc_w_fifo  ;
    wire              [AXI_DATA_WIDTH-1: 0]          dout_proc_w_fifo           ;
    wire                                             rd_en_proc_w_fifo          ;
    wire                                             empty_proc_w_fifo          ;
    wire  [W_FIFO_RD_DATA_CNT_WIDTH-1: 0]            rd_data_count_proc_w_fifo  ;

//    // ==================== 输入视频流（RGB565） ====================
//    wire   [RGB_PIC_DATA_WIDTH-1: 0]    video_data_in              ;// RGB565数据输入
//    wire                                video_data_in_valid        ;// 输入有效
//    wire                                video_data_in_hs           ;// 输入行同步
//    wire                                video_data_in_vs           ;// 输入场同步

    // ==================== 输出视频流（RGB565） ====================
    wire    [RGB_PIC_DATA_WIDTH-1: 0]    video_data_out             ;// RGB565数据输出
    wire                                 video_data_out_valid       ;// 输出有效
    wire                                 video_data_out_hs          ;// 输出行同步
    wire                                 video_data_out_vs          ;// 输出场同步

    // ====================rgb_2_gray 输出的灰度数据 ====================

    wire                 [GRAY_PIC_DATA_WIDTH-1: 0]gray_data       ;
    wire                                gray_valid                 ;
    wire                                gray_hs                    ;
    wire                                gray_vs                    ;
    // ====================sobel 输出的灰度数据 ====================
    wire                 [GRAY_PIC_DATA_WIDTH-1: 0]sobel_data      ;
    wire                                sobel_valid                ;
    wire                                sobel_hs                   ;
    wire                                sobel_vs                   ;

    // ==================== pixel_count_request_ctrl输出接口 ====================
    wire       [($clog2(IMAGE_WIDTH))-1: 0]    video_data_hcnt            ;
    wire       [($clog2(IMAGE_HEIGHT))-1: 0]   video_data_vcnt            ;
    wire       [RGB_PIC_DATA_WIDTH-1: 0]       video_data                 ;
    wire                                       video_data_valid           ;
    wire                                       video_data_hs              ;
    wire                                       video_data_vs              ;
    wire                                       p_r_done                   ;


    // ==================== pixel_count_write_ctrl输出接口 ====================   
    wire                                       p_w_done                   ;


reg p_idle_reg;
always @(posedge clk or posedge reset) begin
    if (reset)
        p_idle_reg <= 1;
    else if (p_switch_pulse)
        p_idle_reg <= 0;
    else if (p_w_done)
        p_idle_reg <= 1;
end
assign p_done = p_w_done;
assign p_idle = p_idle_reg;

//===============================================================================================================
//调用底层模块
////////////////////////////////////////// proc_r_module_fifo  //////////////////////////////////////////////
proc_r_module_fifo proc_r_module_fifo (
    .clk                                (clk                       ),// input wire clk
    .srst                               (reset                     ),// input wire srst
    .rd_en                              (rd_en_proc_r_fifo         ),// input wire rd_en
    .dout                               (dout_proc_r_fifo          ),// output wire [15 : 0] dout
    .empty                              (empty_proc_r_fifo         ),// output wire empty
    .rd_data_count                      (rd_data_count_proc_r_fifo ),// output wire [10 : 0] rd_data_count
    .din                                (din_proc_r_fifo           ),// input wire [127 : 0] din
    .wr_en                              (wr_en_proc_r_fifo         ),// input wire wr_en
    .full                               (full_proc_r_fifo          ),// output wire full
    .wr_data_count                      (wr_data_count_proc_r_fifo ) // output wire [7 : 0] wr_data_count
);


////////////////////////////////////////// proc_w_module_fifo  //////////////////////////////////////////////
proc_w_module_fifo proc_w_module_fifo (
    .clk                                (clk                       ),// input wire clk
    .srst                               (reset                     ),// input wire srst
    .din                                (din_proc_w_fifo           ),// input wire [15 : 0] din
    .wr_en                              (wr_en_proc_w_fifo         ),// input wire wr_en
    .full                               (full_proc_w_fifo          ),// output wire full
    .wr_data_count                      (wr_data_count_proc_w_fifo ),// output wire [10 : 0] wr_data_count
    .dout                               (dout_proc_w_fifo          ),// output wire [127 : 0] dout
    .rd_en                              (rd_en_proc_w_fifo         ),// input wire rd_en
    .empty                              (empty_proc_w_fifo         ),// output wire empty
    .rd_data_count                      (rd_data_count_proc_w_fifo ) // output wire [7 : 0] rd_data_count
);



//////////////////////////////////////////    rgb_2_gray      //////////////////////////////////////////////

rgb_2_gray#(
    .DATA_WIDTH                         (GRAY_PIC_DATA_WIDTH       ) 
)
 u_rgb_2_gray(
// ==================== 全局信号 ====================
    .clk                                (clk                       ),// (input)
    .rst                                (reset                     ),// (input)
// ==================== 输入 RGB565 数据 ====================
    .data_in                            (video_data                ),// (input)
    .data_in_valid                      (video_data_valid          ),// (input)
    .data_in_hs                         (video_data_hs             ),// (input)
    .data_in_vs                         (video_data_vs             ),// (input)
// ==================== 输出灰度数据 ====================
    .data_out                           (gray_data                 ),// (output)
    .data_out_valid                     (gray_valid                ),// (output)
    .data_out_hs                        (gray_hs                   ),// (output)
    .data_out_vs                        (gray_vs                   ) // (output)
);

//////////////////////////////////////////    sobel_calculate       //////////////////////////////////////////////

sobel_calculate#(
    .DATA_WIDTH                         (GRAY_PIC_DATA_WIDTH       ),
    .LINE_LEN                           (LINE_LEN                  ) 
)
 u_sobel_calculate(
// ==================== 全局信号 ====================
    .ui_clk                             (clk                       ),// (input) 统一使用 clk
    .ui_clk_sync_rst                    (reset                     ),// (input) 高有效复位
// ==================== 输入灰度图像数据 ====================
    .data_in                            (gray_data                 ),// (input)
    .data_in_valid                      (gray_valid                ),// (input)
    .data_in_hs                         (gray_hs                   ),// (input)
    .data_in_vs                         (gray_vs                   ),// (input)
// ==================== 输出灰度图像数据 ====================
    .data_out                           (sobel_data                ),// (output)
    .data_out_valid                     (sobel_valid               ),// (output)
    .data_out_hs                        (sobel_hs                  ),// (output)
    .data_out_vs                        (sobel_vs                  ) // (output)
);

//////////////////////////////////////////    gray_2_rgb      //////////////////////////////////////////////

gray_2_rgb#(
    .DATA_WIDTH                         (GRAY_PIC_DATA_WIDTH       ),
    .PROC_TYPE                          (PROC_TYPE                 ),
    .THRESHOLD                          (THRESHOLD                 ) 
)
 u_gray_2_rgb(
// ==================== 全局信号 ====================
    .clk                                (clk                       ),// (input)
    .rst                                (reset                     ),// (input)
// ==================== 输入灰度图像数据 ====================
    .data_in                            (sobel_data                ),// (input)
    .data_in_valid                      (sobel_valid               ),// (input)
    .data_in_hs                         (sobel_hs                  ),// (input)
    .data_in_vs                         (sobel_vs                  ),// (input)
// ==================== 输出 RGB565 图像数据 ====================
    .data_out                           (video_data_out            ),// (output)
    .data_out_valid                     (video_data_out_valid      ),// (output)
    .data_out_hs                        (video_data_out_hs         ),// (output)
    .data_out_vs                        (video_data_out_vs         ) // (output)
);


//////////////////////////////////////////  pixel_count_request_ctrl  //////////////////////////////////////////////

pixel_count_request_ctrl#(
    .R_FIFO_RD_DATA_CNT_WIDTH           (R_FIFO_RD_DATA_CNT_WIDTH ),
    .FIFO_USER_DATA_WIDTH               (FIFO_USER_DATA_WIDTH     ),
    .RGB_PIC_DATA_WIDTH                 (RGB_PIC_DATA_WIDTH       ),
    .IMAGE_WIDTH                        (IMAGE_WIDTH              ),
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT             ) 
)
 u_pixel_count_request_ctrl(
// ==================== 有关输出的图像信息 ====================
// ==================== 全局信号 ====================
    .clk                                (clk                       ),// (input)// 处理时钟
    .reset                              (reset                     ),// (input)// 高有效复位
// ==================== 帧启动信号 ====================
    .p_switch_pulse                     (p_switch_pulse            ),// (input)// 四缓冲控制器给的开始脉冲
// ==================== 输入的fifo数据流 ====================
    .dout_proc_r_fifo                   (dout_proc_r_fifo          ),// (input)
    .empty_proc_r_fifo                  (empty_proc_r_fifo         ),// (input)
    .rd_data_count_proc_r_fifo          (rd_data_count_proc_r_fifo ),// (input)
// ==================== 对外输出的fifo控制信号 ====================
    .rd_en_proc_r_fifo                  (rd_en_proc_r_fifo         ),// (output)
    .video_data_hcnt                    (video_data_hcnt           ),// (output)
    .video_data_vcnt                    (video_data_vcnt           ),// (output)
// ==================== 对外输出的视频信号 ====================
    .video_data                         (video_data                ),// (output)// RGB565数据输出
    .video_data_valid                   (video_data_valid          ),// (output)// 输出数据有效
    .video_data_hs                      (video_data_hs             ),// (output)// 输出行同步
    .video_data_vs                      (video_data_vs             ),// (output)// 输出场同步
// ==================== 对外输出p模块读完信号 ====================
    .p_r_done                           (p_r_done                  ) // (output)
);

//////////////////////////////////////////  pixel_count_write_ctrl  //////////////////////////////////////////////

pixel_count_write_ctrl#(
    .W_FIFO_RD_DATA_CNT_WIDTH           (W_FIFO_RD_DATA_CNT_WIDTH  ),
    .FIFO_USER_DATA_WIDTH               (FIFO_USER_DATA_WIDTH      ),
    .RGB_PIC_DATA_WIDTH                 (RGB_PIC_DATA_WIDTH        ),
    .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ) 
)
 u_pixel_count_write_ctrl(
// ==================== 有关输出的图像信息 ====================
// ==================== 全局信号 ====================
    .clk                                (clk                       ), // (input)// 处理时钟
    .reset                              (reset                     ), // (input)// 高有效复位
// ==================== 输入的视频信号 ====================
    .video_data_out                     (video_data_out            ), // (input)// RGB565数据输出
    .video_data_out_valid               (video_data_out_valid      ), // (input)// 输出有效
    .video_data_out_hs                  (video_data_out_hs         ), // (input)// 输出行同步
    .video_data_out_vs                  (video_data_out_vs         ), // (input)// 输出场同步
// ==================== 输入的fifo写入信号 ====================.
    .full_proc_w_fifo                   (full_proc_w_fifo          ), // (input)
    .wr_data_count_proc_w_fifo          (wr_data_count_proc_w_fifo ), // (input)此信号无用
    .din_proc_w_fifo                    (din_proc_w_fifo           ), // (output)
    .wr_en_proc_w_fifo                  (wr_en_proc_w_fifo         ), // (output)
// ==================== 对外输出p模块写完信号 ====================
    .p_w_done                           (p_w_done                  ) // (output)
);
endmodule
