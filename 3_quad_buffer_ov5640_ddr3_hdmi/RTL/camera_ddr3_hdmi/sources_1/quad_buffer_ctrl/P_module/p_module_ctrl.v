`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/19 17:09:19
// Design Name: 
// Module Name: p_module_ctrl
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 图像处理流水线控制模块（灰度→Sobel→输出）
// Dependencies: rgb_2_gray, sobel_calculate, gray_2_rgb
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 禁止魔数
//////////////////////////////////////////////////////////////////////////////////

module p_module_ctrl
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
    // ==================== 全局信号 ====================
    input                               clk                        ,// 处理时钟
    input                               reset                      ,// 高有效复位

    // ==================== 写地址通道 ====================

    output               [AXI_ID_WIDTH-1: 0]m_axi_p_awid             ,
    output               [AXI_ADDR_WIDTH-1: 0]m_axi_p_awaddr         ,
    output               [   7: 0]      m_axi_p_awlen                ,
    output               [   2: 0]      m_axi_p_awsize               ,
    output               [   1: 0]      m_axi_p_awburst              ,
    output               [   0: 0]      m_axi_p_awlock               ,
    output               [   3: 0]      m_axi_p_awcache              ,
    output               [   2: 0]      m_axi_p_awprot               ,
    output               [   3: 0]      m_axi_p_awqos                ,
    output               [   3: 0]      m_axi_p_awregion             ,
    output                              m_axi_p_awvalid              ,
    input                               m_axi_p_awready              ,

    // ==================== 写数据通道 ====================

    output               [AXI_DATA_WIDTH-1: 0]m_axi_p_wdata          ,
    output               [AXI_DATA_WIDTH/8-1: 0]m_axi_p_wstrb        ,
    output                              m_axi_p_wlast                ,
    output                              m_axi_p_wvalid               ,
    input                               m_axi_p_wready               ,

    // ==================== 写响应通道 ====================    

    input                [AXI_ID_WIDTH-1: 0]m_axi_p_bid              ,
    input                [   1: 0]      m_axi_p_bresp                ,
    input                               m_axi_p_bvalid               ,
    output                              m_axi_p_bready               ,

    // ==================== 读地址通道 ====================  

    output               [AXI_ID_WIDTH-1: 0]m_axi_p_arid             ,
    output               [AXI_ADDR_WIDTH-1: 0]m_axi_p_araddr         ,
    output               [   7: 0]      m_axi_p_arlen                ,
    output               [   2: 0]      m_axi_p_arsize               ,
    output               [   1: 0]      m_axi_p_arburst              ,
    output               [   0: 0]      m_axi_p_arlock               ,
    output               [   3: 0]      m_axi_p_arcache              ,
    output               [   2: 0]      m_axi_p_arprot               ,
    output               [   3: 0]      m_axi_p_arqos                ,
    output               [   3: 0]      m_axi_p_arregion             ,
    output                              m_axi_p_arvalid              ,
    input                               m_axi_p_arready              ,

    // ==================== 读数据通道 ====================  
    
    input                [AXI_ID_WIDTH-1: 0]m_axi_p_rid              ,
    input                [AXI_DATA_WIDTH-1: 0]m_axi_p_rdata          ,
    input                [   1: 0]      m_axi_p_rresp                ,
    input                               m_axi_p_rlast                ,
    input                               m_axi_p_rvalid               ,
    output                              m_axi_p_rready               ,

    // ==================== 缓存控制信号 ==================== 
    output                              p_done                     ,
    output                              p_idle                     ,
    output                              p_w_done                   ,//从F-A输出的写完一帧信号
    output                              p_r_done                   ,//从A-F输出的读完一帧信号
    input                               p_r_rdenable               ,//必须等摄像头写完一帧后才能启动P读

    output                              p_module_ddr3_w_req        ,
    input                               p_w_start_pulse            ,

    output                              p_module_ddr3_r_req        ,
    input                               p_r_start_pulse            ,

    output                              p_w_burst_done             ,
    output                              p_r_burst_done             ,
    // ==================== 缓存切换脉冲和指针输入 ====================
    input                               p_rd_buf                   ,// 当前从哪个读
    input                               p_wr_buf                   ,// 当前往哪个写
    input                               p_switch_pulse             ,// 与p_rd/p_wr同拍变化(P模块同一时间占用两个buf)
    input                               p_bypass                    
);

//===============================================================================================================   
//本地参数及接口定义、连线

    // ==================== proc_r_module_fifo接口 ====================
    wire                                           rd_en_proc_r_fifo          ;
    wire  [ FIFO_USER_DATA_WIDTH-1: 0]             dout_proc_r_fifo           ;
    wire                                           empty_proc_r_fifo          ;
    wire  [R_FIFO_RD_DATA_CNT_WIDTH-1: 0]          rd_data_count_proc_r_fifo  ;
    wire         [AXI_DATA_WIDTH-1: 0]             din_proc_r_fifo            ;
    wire                                           wr_en_proc_r_fifo          ;
    wire                                           full_proc_r_fifo           ;
    wire  [R_FIFO_WR_DATA_CNT_WIDTH-1: 0]          wr_data_count_proc_r_fifo  ;

    // ==================== proc_w_module_fifo接口 ====================

    wire  [ FIFO_USER_DATA_WIDTH-1: 0]               din_proc_w_fifo            ;
    wire                                             wr_en_proc_w_fifo          ;
    wire                                             full_proc_w_fifo           ;
    wire  [W_FIFO_WR_DATA_CNT_WIDTH-1: 0]            wr_data_count_proc_w_fifo  ;
    wire              [AXI_DATA_WIDTH-1: 0]          dout_proc_w_fifo           ;
    wire                                             rd_en_proc_w_fifo          ;
    wire                                             empty_proc_w_fifo          ;
    wire  [W_FIFO_RD_DATA_CNT_WIDTH-1: 0]            rd_data_count_proc_w_fifo  ;



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

    // ==================== 旁路功能 ====================
    wire    [RGB_PIC_DATA_WIDTH-1: 0]    video_data_dynamic                 ;// RGB565数据输出
    wire                                 video_data_out_valid_dynamic       ;// 输出有效
    wire                                 video_data_out_hs_dynamic          ;// 输出行同步
    wire                                 video_data_out_vs_dynamic          ;// 输出场同步
//===============================================================================================================
//逻辑输出
//===================================
//产生p模块空闲信号
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


//===================================
//产生p模块旁路逻辑，p_bypass为1时旁路
assign video_data_dynamic            =p_bypass?video_data       :   video_data_out      ;
assign video_data_out_valid_dynamic  =p_bypass?video_data_valid :   video_data_out_valid;
assign video_data_out_hs_dynamic     =p_bypass?video_data_hs    :   video_data_out_hs   ;
assign video_data_out_vs_dynamic     =p_bypass?video_data_vs    :   video_data_out_vs   ;

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

////////////////////////////////////////// proc_r_axi4_to_fifo  //////////////////////////////////////////////

proc_r_axi4_to_fifo#(
    .BUF_A_BEGIN                        (IN_BUF_0                  ),
    .BUF_B_BEGIN                        (IN_BUF_1                  ),
    .AXI_DATA_WIDTH                     (AXI_DATA_WIDTH            ),
    .AXI_ADDR_WIDTH                     (AXI_ADDR_WIDTH            ),
    .AXI_ID_WIDTH                       (AXI_ID_WIDTH              ),
    .AXI_ID                             (PROC_P_AXI_ID             ),
    .AXI_BURST_LEN                      (AXI_BURST_LEN             ),
    .FIFO_ADDR_WIDTH                    (R_FIFO_WR_DATA_CNT_WIDTH  ),
    .AXI_ARBURST_INCR                   (AXI_ARBURST_INCR          ),
    .AXI_ARLOCK_NORMAL                  (AXI_ARLOCK_NORMAL         ),
    .AXI_ARCACHE_DEVICE_NON_BUF         (AXI_ARCACHE_DEVICE_NON_BUF),
    .AXI_ARPROT_UNPRIV_SECURE           (AXI_ARPROT_UNPRIV_SECURE  ),
    .AXI_ARQOS_DEFAULT                  (AXI_ARQOS_DEFAULT         ),
    .AXI_ARREGION_DEFAULT               (AXI_ARREGION_DEFAULT      ),
    .AXI_RRESP_OKAY                     (AXI_RRESP_OKAY            ),
    .AXI_RESET_POLARITY                 (AXI_RESET_POLARITY        ),
    .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ) 
)
 u_proc_r_axi4_to_fifo(
    .clk                                (clk                       ),// (input)
    .reset                              (reset                     ),// (input)
// ==================== 写FIFO用户写入侧接口 ====================
    .fifo_wrreq                         (wr_en_proc_r_fifo         ),// (output)
    .fifo_wrdata                        (din_proc_r_fifo           ),// (output)
    .fifo_alfull                        (full_proc_r_fifo          ),// (input)
    .fifo_wr_cnt                        (wr_data_count_proc_r_fifo),// (input)
// ==================== 读地址通道 ====================
    .m_axi_arid                         (m_axi_p_arid                ),// (output)
    .m_axi_araddr                       (m_axi_p_araddr              ),// (output)
    .m_axi_arlen                        (m_axi_p_arlen               ),// (output)
    .m_axi_arsize                       (m_axi_p_arsize              ),// (output)
    .m_axi_arburst                      (m_axi_p_arburst             ),// (output)
    .m_axi_arlock                       (m_axi_p_arlock              ),// (output)
    .m_axi_arcache                      (m_axi_p_arcache             ),// (output)
    .m_axi_arprot                       (m_axi_p_arprot              ),// (output)
    .m_axi_arqos                        (m_axi_p_arqos               ),// (output)
    .m_axi_arregion                     (m_axi_p_arregion            ),// (output)
    .m_axi_arvalid                      (m_axi_p_arvalid             ),// (output)
    .m_axi_arready                      (m_axi_p_arready             ),// (input)
// ==================== 读数据通道 ====================
    .m_axi_rid                          (m_axi_p_rid                 ),// (input)
    .m_axi_rdata                        (m_axi_p_rdata               ),// (input)
    .m_axi_rresp                        (m_axi_p_rresp               ),// (input)
    .m_axi_rlast                        (m_axi_p_rlast               ),// (input)
    .m_axi_rvalid                       (m_axi_p_rvalid              ),// (input)
    .m_axi_rready                       (m_axi_p_rready              ),// (output)
//==================== 实验接口 ====================
    .r_done                             (p_r_done                  ),// (output)//内建的一帧读完信号，可靠的前提是，读取也必须精准申请数据
    .rd_enable                          (p_r_rdenable              ),// (input)
    .p_module_ddr3_r_req                (p_module_ddr3_r_req       ),// (output)
    .p_r_start_pulse                    (p_r_start_pulse           ),// (input)
    .p_r_burst_done                     (p_r_burst_done            ),// (output)
// ==================== 缓存切换逻辑信号 ====================
    .r_buf                              (p_rd_buf                  ),// (input)// 0=读帧A, 1=读帧B,默认读B
    .r_addr_switch_pulse                (p_switch_pulse            ) // (input)// 地址切换脉冲，与指针一同出现
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

////////////////////////////////////////// proc_w_fifo_to_axi4  //////////////////////////////////////////////

proc_w_fifo_to_axi4#(
    .BUF_A_BEGIN                        (PROC_BUF_0                ),
    .BUF_B_BEGIN                        (PROC_BUF_1                ),
    .AXI_DATA_WIDTH                     (AXI_DATA_WIDTH            ),
    .AXI_ADDR_WIDTH                     (AXI_ADDR_WIDTH            ),
    .AXI_ID_WIDTH                       (AXI_ID_WIDTH              ),
    .AXI_ID                             (PROC_P_AXI_ID             ),
    .AXI_BURST_LEN                      (AXI_BURST_LEN             ),
    .RD_DATA_CNT_WIDTH                  (W_FIFO_RD_DATA_CNT_WIDTH  ),
    .AXI_AWBURST_INCR                   (AXI_AWBURST_INCR          ),
    .AXI_AWLOCK_NORMAL                  (AXI_AWLOCK_NORMAL         ),
    .AXI_AWCACHE_DEVICE_NON_BUF         (AXI_AWCACHE_DEVICE_NON_BUF),
    .AXI_AWPROT_UNPRIV_SECURE           (AXI_AWPROT_UNPRIV_SECURE  ),
    .AXI_AWQOS_DEFAULT                  (AXI_AWQOS_DEFAULT         ),
    .AXI_AWREGION_DEFAULT               (AXI_AWREGION_DEFAULT      ),
    .AXI_BRESP_OKAY                     (AXI_BRESP_OKAY            ),
    .AXI_WSTRB_ALL_VALID                (AXI_WSTRB_ALL_VALID       ),
    .AXI_RESET_POLARITY                 (AXI_RESET_POLARITY        ),
    .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ) 
)
 u_proc_w_fifo_to_axi4(

    .clk                                (clk                       ),// (input)
    .reset                              (reset                     ),// (input)
// ==================== 写FIFO读取侧接口 ====================
    .fifo_rdreq                         (rd_en_proc_w_fifo         ),// (output)// fifo读请求
    .fifo_rddata                        (dout_proc_w_fifo          ),// (input)// fifo的数据位宽，和AXI4一样
    .fifo_empty                         (empty_proc_w_fifo         ),// (input)
    .fifo_rd_cnt                        (rd_data_count_proc_w_fifo ),// (input)// fifo读cnt，指示fifo中还有多少数据
// ==================== 写地址通道 ====================
    .m_axi_awid                         (m_axi_p_awid              ),// (output)
    .m_axi_awaddr                       (m_axi_p_awaddr            ),// (output)
    .m_axi_awlen                        (m_axi_p_awlen             ),// (output)
    .m_axi_awsize                       (m_axi_p_awsize            ),// (output)
    .m_axi_awburst                      (m_axi_p_awburst           ),// (output)
    .m_axi_awlock                       (m_axi_p_awlock            ),// (output)
    .m_axi_awcache                      (m_axi_p_awcache           ),// (output)
    .m_axi_awprot                       (m_axi_p_awprot            ),// (output)
    .m_axi_awqos                        (m_axi_p_awqos             ),// (output)
    .m_axi_awregion                     (m_axi_p_awregion          ),// (output)
    .m_axi_awvalid                      (m_axi_p_awvalid           ),// (output)
    .m_axi_awready                      (m_axi_p_awready           ),// (input)
// ==================== 写数据通道 ====================
    .m_axi_wdata                        (m_axi_p_wdata             ),// (output)
    .m_axi_wstrb                        (m_axi_p_wstrb             ),// (output)// 指示数据有效,每8位位1组
    .m_axi_wlast                        (m_axi_p_wlast             ),// (output)
    .m_axi_wvalid                       (m_axi_p_wvalid            ),// (output)
    .m_axi_wready                       (m_axi_p_wready            ),// (input)
// ==================== 写响应通道 ====================
    .m_axi_bid                          (m_axi_p_bid               ),// (input)
    .m_axi_bresp                        (m_axi_p_bresp             ),// (input)
    .m_axi_bvalid                       (m_axi_p_bvalid            ),// (input)
    .m_axi_bready                       (m_axi_p_bready            ),// (output)
// ==================== 对外输出的一帧写完信号 ====================
    .p_w_done                           (p_w_done                  ),// (output)// 帧写完成脉冲,真正的写完脉冲，所有数据都进入到ddr3中了
    .p_module_ddr3_w_req                (p_module_ddr3_w_req       ),// (output)
    .p_w_start_pulse                    (p_w_start_pulse           ),// (input)
    .p_w_burst_done                     (p_w_burst_done            ),// (output)
// ==================== 缓存切换逻辑信号 =========================
    .w_buf                              (p_wr_buf                  ),// (input)// 0=写帧A, 1=写帧B默认写A
    .w_addr_switch_pulse                (p_switch_pulse            ) // (input)// 地址切换脉冲，与指针一同出现
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
    .rd_data_count_proc_r_fifo          (rd_data_count_proc_r_fifo ),// (input)此信号无用
// ==================== 对外输出的fifo控制信号 ====================
    .rd_en_proc_r_fifo                  (rd_en_proc_r_fifo         ),// (output)
    .video_data_hcnt                    (video_data_hcnt           ),// (output)
    .video_data_vcnt                    (video_data_vcnt           ),// (output)
// ==================== 对外输出的视频信号 ====================
    .video_data                         (video_data                ),// (output)// RGB565数据输出
    .video_data_valid                   (video_data_valid          ),// (output)// 输出数据有效
    .video_data_hs                      (video_data_hs             ),// (output)// 输出行同步
    .video_data_vs                      (video_data_vs             )// (output)// 输出场同步
// ==================== 对外输出p模块读完信号 ====================
//    .p_r_done                           (p_r_done                  ) // (output)此信号没吊用
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
    .video_data_out                     (video_data_dynamic        ),// (input)// RGB565数据输出
    .video_data_out_valid               (video_data_out_valid_dynamic),// (input)// 输出有效
    .video_data_out_hs                  (video_data_out_hs_dynamic ),// (input)// 输出行同步
    .video_data_out_vs                  (video_data_out_vs_dynamic ),// (input)// 输出场同步
// ==================== 输入的fifo写入信号 ====================.
    .full_proc_w_fifo                   (full_proc_w_fifo          ), // (input)
    .wr_data_count_proc_w_fifo          (wr_data_count_proc_w_fifo ), // (input)此信号无用
    .din_proc_w_fifo                    (din_proc_w_fifo           ), // (output)
    .wr_en_proc_w_fifo                  (wr_en_proc_w_fifo         ), // (output)
    .rd_en_proc_r_fifo                  (rd_en_proc_r_fifo         )// input wire rd_en
// ==================== 对外输出p模块写完信号 ====================
//    .p_w_done                           (                          ) // (output)此信号仅代表所有数据写入fifo完成，fifo内可能还憋着几次突发！如果这时候切，会导致写错缓存
);                                                                    // (output)此信号没吊用
endmodule