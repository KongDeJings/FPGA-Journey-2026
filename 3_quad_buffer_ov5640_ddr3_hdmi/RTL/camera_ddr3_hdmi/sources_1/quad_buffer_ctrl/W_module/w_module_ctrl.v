`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/22 20:17:40
// Design Name: 
// Module Name: w_module_ctrl
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


module w_module_ctrl
#(
    // ==================== FIFO相关参数 ====================

    parameter                           FIFO_USER_DATA_WIDTH        = 16                   ,  //fifo din/dout的位宽，异步FIFO内部完成 16bit → 128bit 位宽拼接，转到AXI4时为128bit
    parameter                           W_CAM_FIFO_RD_DATA_CNT_WIDTH= 7                    ,
    parameter                           W_CAM_FIFO_WR_DATA_CNT_WIDTH= 10                   ,
    // ==================== 地址与数据参数 ====================
    parameter                           IN_BUF_0                    = 32'h0000_0000        ,//缓存A基地址
    parameter                           IN_BUF_1                    = 32'h0080_0000        ,//缓存B基地址

    parameter                           AXI_DATA_WIDTH              = 128                  ,
    parameter                           AXI_ADDR_WIDTH              = 32                   ,
    parameter                           AXI_BURST_LEN               = 8'd31                ,

    parameter                           AXI_ID_WIDTH                = 4                    ,
    parameter                           CAM_AXI_ID                  = 4'b0001              ,
    // ==================== AXI 固定协议参数 ====================
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
    parameter                           IMAGE_HEIGHT                = 720                  
)
(
    // ==================== 全局信号 ====================
    input                               clk                        , // ui_clk
    input                               reset                      , // ui_clk_sync_rst

    // ==================== 写FIFO用户写入侧接口 ====================

    input                               rst_cam_w_fifo             ,
    input                               wr_clk_cam_w_fifo          ,
    input                               wr_en_cam_w_fifo           ,
    input                [FIFO_USER_DATA_WIDTH-1: 0]din_cam_w_fifo             ,
    output                              full_cam_w_fifo            ,
    output               [W_CAM_FIFO_WR_DATA_CNT_WIDTH-1: 0]wr_data_count_cam_w_fifo   ,
    output                              wr_rst_busy_cam_w_fifo     ,

    // ==================== 写地址通道 ====================

    output               [AXI_ID_WIDTH-1: 0]m_axi_cam_awid             ,
    output               [AXI_ADDR_WIDTH-1: 0]m_axi_cam_awaddr         ,
    output               [   7: 0]      m_axi_cam_awlen                ,
    output               [   2: 0]      m_axi_cam_awsize               ,
    output               [   1: 0]      m_axi_cam_awburst              ,
    output               [   0: 0]      m_axi_cam_awlock               ,
    output               [   3: 0]      m_axi_cam_awcache              ,
    output               [   2: 0]      m_axi_cam_awprot               ,
    output               [   3: 0]      m_axi_cam_awqos                ,
    output               [   3: 0]      m_axi_cam_awregion             ,
    output                              m_axi_cam_awvalid              ,
    input                               m_axi_cam_awready              ,

    // ==================== 写数据通道 ====================

    output               [AXI_DATA_WIDTH-1: 0]m_axi_cam_wdata          ,
    output               [AXI_DATA_WIDTH/8-1: 0]m_axi_cam_wstrb        ,
    output                              m_axi_cam_wlast                ,
    output                              m_axi_cam_wvalid               ,
    input                               m_axi_cam_wready               ,

    // ==================== 写响应通道 ====================    

    input                [AXI_ID_WIDTH-1: 0]m_axi_cam_bid              ,
    input                [   1: 0]      m_axi_cam_bresp                ,
    input                               m_axi_cam_bvalid               ,
    output                              m_axi_cam_bready               ,
    
    // ==================== 对外输出的写完状态信号 ====================    
    output                              camera_w_done              ,
    output                              w_module_ddr3_w_req        ,
    input                               camera_w_start_pulse       ,
    output                              camera_burst_done          ,
    // ==================== 缓存切换逻辑信号 =========================
    input                               w_buf                      ,// 0=写帧A, 1=写帧B默认写A
    input                               w_switch_pulse              //地址切换脉冲，与指针一同出现               
    );


//===============================================================================================================   
//本地参数及接口定义、连线

//cam写fifo侧读取接口
    wire                                rd_en_cam_w_fifo                               ;
    wire                 [AXI_DATA_WIDTH-1: 0]dout_cam_w_fifo                          ;
    wire                                empty_cam_w_fifo                               ;
    wire                 [W_CAM_FIFO_RD_DATA_CNT_WIDTH-1: 0]rd_data_count_cam_w_fifo   ;
    wire                                rd_rst_busy_cam_w_fifo                         ;

//===============================================================================================================
//逻辑输出
//没有逻辑，只是单独的逻辑连线



//===============================================================================================================
//调用底层模块
//////////////////////////////////////////    cam_w_module_fifo    //////////////////////////////////////////////
cam_w_module_fifo cam_w_module_fifo (
    .rst                                (rst_cam_w_fifo            ),// input wire rst

    .wr_clk                             (wr_clk_cam_w_fifo         ),// input wire wr_clk
    .din                                (din_cam_w_fifo            ),// input wire [15 : 0] din
    .wr_en                              (wr_en_cam_w_fifo          ),// input wire wr_en
    .full                               (full_cam_w_fifo           ),// output wire full
    .wr_data_count                      (wr_data_count_cam_w_fifo  ),// output wire [9 : 0] wr_data_count
    .wr_rst_busy                        (wr_rst_busy_cam_w_fifo    ),// output wire wr_rst_busy

    .rd_clk                             (clk                       ),// input wire rd_clk
    .dout                               (dout_cam_w_fifo           ),// output wire [127 : 0] dout
    .rd_en                              (rd_en_cam_w_fifo          ),// input wire rd_en
    .empty                              (empty_cam_w_fifo          ),// output wire empty
    .rd_data_count                      (rd_data_count_cam_w_fifo  ),// output wire [6 : 0] rd_data_count
    .rd_rst_busy                        (rd_rst_busy_cam_w_fifo    ) // output wire rd_rst_busy
);


//////////////////////////////////////////   cam_w_fifo_to_axi4      //////////////////////////////////////////////

cam_w_fifo_to_axi4#(
    .BUF_A_BEGIN                        (IN_BUF_0                   ),
    .BUF_B_BEGIN                        (IN_BUF_1                   ),
    .AXI_DATA_WIDTH                     (AXI_DATA_WIDTH             ),
    .AXI_ADDR_WIDTH                     (AXI_ADDR_WIDTH             ),
    .AXI_ID_WIDTH                       (AXI_ID_WIDTH               ),
    .AXI_ID                             (CAM_AXI_ID                 ),
    .AXI_BURST_LEN                      (AXI_BURST_LEN              ),
    .RD_DATA_CNT_WIDTH                  (W_CAM_FIFO_RD_DATA_CNT_WIDTH),
    .AXI_AWBURST_INCR                   (AXI_AWBURST_INCR           ),
    .AXI_AWLOCK_NORMAL                  (AXI_AWLOCK_NORMAL          ),
    .AXI_AWCACHE_DEVICE_NON_BUF         (AXI_AWCACHE_DEVICE_NON_BUF ),
    .AXI_AWPROT_UNPRIV_SECURE           (AXI_AWPROT_UNPRIV_SECURE   ),
    .AXI_AWQOS_DEFAULT                  (AXI_AWQOS_DEFAULT          ),
    .AXI_AWREGION_DEFAULT               (AXI_AWREGION_DEFAULT       ),
    .AXI_BRESP_OKAY                     (AXI_BRESP_OKAY             ),
    .AXI_WSTRB_ALL_VALID                (AXI_WSTRB_ALL_VALID        ),
    .AXI_RESET_POLARITY                 (AXI_RESET_POLARITY         ),
    .IMAGE_WIDTH                        (IMAGE_WIDTH                ),
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT               ) 
)
 u_cam_w_fifo_to_axi4(
    .clk                                (clk                       ),// (input)
    .reset                              (reset                     ),// (input)
// ==================== 写FIFO读取侧接口 ====================
    .fifo_rdreq                         (rd_en_cam_w_fifo          ),// (output)// fifo读请求
    .fifo_rddata                        (dout_cam_w_fifo           ),// (input)// fifo的数据位宽，和AXI4一样
    .fifo_empty                         (empty_cam_w_fifo          ),// (input)
    .fifo_rd_cnt                        (rd_data_count_cam_w_fifo  ),// (input)// fifo读cnt，指示fifo中还有多少数据
    .fifo_rst_busy                      (rd_rst_busy_cam_w_fifo    ),// (input)// fifo复位忙，为1表示fifo正在复位
// ==================== 写地址通道 ====================
    .m_axi_awid                         (m_axi_cam_awid            ),// (output)
    .m_axi_awaddr                       (m_axi_cam_awaddr          ),// (output)
    .m_axi_awlen                        (m_axi_cam_awlen           ),// (output)
    .m_axi_awsize                       (m_axi_cam_awsize          ),// (output)
    .m_axi_awburst                      (m_axi_cam_awburst         ),// (output)
    .m_axi_awlock                       (m_axi_cam_awlock          ),// (output)
    .m_axi_awcache                      (m_axi_cam_awcache         ),// (output)
    .m_axi_awprot                       (m_axi_cam_awprot          ),// (output)
    .m_axi_awqos                        (m_axi_cam_awqos           ),// (output)
    .m_axi_awregion                     (m_axi_cam_awregion        ),// (output)
    .m_axi_awvalid                      (m_axi_cam_awvalid         ),// (output)
    .m_axi_awready                      (m_axi_cam_awready         ),// (input)
// ==================== 写数据通道 ====================
    .m_axi_wdata                        (m_axi_cam_wdata           ),// (output)
    .m_axi_wstrb                        (m_axi_cam_wstrb           ),// (output)// 指示数据有效,每8位位1组
    .m_axi_wlast                        (m_axi_cam_wlast           ),// (output)
    .m_axi_wvalid                       (m_axi_cam_wvalid          ),// (output)
    .m_axi_wready                       (m_axi_cam_wready          ),// (input)
// ==================== 写响应通道 ====================
    .m_axi_bid                          (m_axi_cam_bid             ),// (input)
    .m_axi_bresp                        (m_axi_cam_bresp           ),// (input)
    .m_axi_bvalid                       (m_axi_cam_bvalid          ),// (input)
    .m_axi_bready                       (m_axi_cam_bready          ),// (output)

// ==================== 对外输出的一帧写完信号 ====================
    .camera_w_done                      (camera_w_done             ),// (output)// 帧写完成脉冲
    .w_module_ddr3_w_req                (w_module_ddr3_w_req       ),// (output)// 模块内部产生的FIFO水位信号
    .camera_w_start_pulse               (camera_w_start_pulse      ),// (input)// 启动一次突发写入信号
    .camera_burst_done                  (camera_burst_done         ),// (output)
// ==================== 双帧缓存切换逻辑信号 ====================
    .w_buf                              (w_buf                     ),// (input)// 0=写帧A, 1=写帧B默认写A
    .w_addr_switch_pulse                (w_switch_pulse            ) // (input)// 地址切换脉冲，与指针一同出现
);


endmodule
