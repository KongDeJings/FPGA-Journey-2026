//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/30 08:34:54
// Design Name: 
// Module Name: fifo_axi4_adapter
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description:  将fifo_axi4，axi4_fifo二者封装到一起
//                      只对外流出fifo读写侧接口、AXI4协议接口
//////////////////////////////////////////////////////////////////////////////////


module fifo_axi4_adapter
#(
    parameter                           FIFO_ADDR_DEPTH             = 64                   ,
    parameter                           FIFO_DW                     = 16                   ,  //fifo din/dout的位宽，异步FIFO内部完成 16bit → 128bit 位宽拼接，转到AXI4时为128bit
    parameter                           FIFO_ADDR_WIDTH             = $clog2(FIFO_ADDR_DEPTH),
    // ==================== 地址与数据参数 ====================
    parameter                           RD_AXI_BYTE_ADDR_BEGIN      = 0                    ,
    parameter                           RD_AXI_BYTE_ADDR_END        = 32768-1              ,

    parameter                           BUF_A_BEGIN                 = 32'h0100_0000        ,//缓存A基地址
    parameter                           BUF_B_BEGIN                 = 32'h0120_0000        ,//缓存B基地址
    parameter                           AXI_DATA_WIDTH              = 128                  ,
    parameter                           AXI_ADDR_WIDTH              = 32                   ,
    parameter                           AXI_ID_WIDTH                = 4                    ,
    parameter                           CAMERA_AXI_ID               = 0                    ,
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
    parameter                           IMAGE_HEIGHT                = 720                  
)
(
    // ==================== 全局信号 ====================

    input                               clk                        ,
    input                               reset                      ,

    // ==================== 写FIFO用户写入侧接口 ====================

    input                               wrfifo_clr                 ,
    input                               wrfifo_clk                 ,
    input                               wrfifo_wren                ,
    input                [FIFO_DW-1: 0] wrfifo_din                 ,
    output                              wrfifo_full                ,
    output               [  15: 0]      wrfifo_wr_cnt              ,

    // ==================== 读FIFO用户侧接口 ====================

    input                               rdfifo_clr                 ,
    input                               rdfifo_clk                 ,
    input                               rdfifo_rden                ,
    output               [FIFO_DW-1: 0] rdfifo_dout                ,
    output                              rdfifo_empty               ,
    output               [  15: 0]      rdfifo_rd_cnt              ,

    // ==================== 写地址通道 ====================

    output               [AXI_ID_WIDTH-1: 0]m_axi_awid             ,
    output               [AXI_ADDR_WIDTH-1: 0]m_axi_awaddr         ,
    output               [   7: 0]      m_axi_awlen                ,
    output               [   2: 0]      m_axi_awsize               ,
    output               [   1: 0]      m_axi_awburst              ,
    output               [   0: 0]      m_axi_awlock               ,
    output               [   3: 0]      m_axi_awcache              ,
    output               [   2: 0]      m_axi_awprot               ,
    output               [   3: 0]      m_axi_awqos                ,
    output               [   3: 0]      m_axi_awregion             ,
    output                              m_axi_awvalid              ,
    input                               m_axi_awready              ,

    // ==================== 写数据通道 ====================

    output               [AXI_DATA_WIDTH-1: 0]m_axi_wdata          ,
    output               [AXI_DATA_WIDTH/8-1: 0]m_axi_wstrb        ,
    output                              m_axi_wlast                ,
    output                              m_axi_wvalid               ,
    input                               m_axi_wready               ,

    // ==================== 写响应通道 ====================    

    input                [AXI_ID_WIDTH-1: 0]m_axi_bid              ,
    input                [   1: 0]      m_axi_bresp                ,
    input                               m_axi_bvalid               ,
    output                              m_axi_bready               ,

    // ==================== 读地址通道 ====================  

    output               [AXI_ID_WIDTH-1: 0]m_axi_arid             ,
    output               [AXI_ADDR_WIDTH-1: 0]m_axi_araddr         ,
    output               [   7: 0]      m_axi_arlen                ,
    output               [   2: 0]      m_axi_arsize               ,
    output               [   1: 0]      m_axi_arburst              ,
    output               [   0: 0]      m_axi_arlock               ,
    output               [   3: 0]      m_axi_arcache              ,
    output               [   2: 0]      m_axi_arprot               ,
    output               [   3: 0]      m_axi_arqos                ,
    output               [   3: 0]      m_axi_arregion             ,
    output                              m_axi_arvalid              ,
    input                               m_axi_arready              ,

    // ==================== 读数据通道 ====================  
    
    input                [AXI_ID_WIDTH-1: 0]m_axi_rid              ,
    input                [AXI_DATA_WIDTH-1: 0]m_axi_rdata          ,
    input                [   1: 0]      m_axi_rresp                ,
    input                               m_axi_rlast                ,
    input                               m_axi_rvalid               ,
    output                              m_axi_rready               ,

    //==================== 实验接口 ====================
    output                              camera_w_done              
    );


//===============================================================================================================   
//本地参数及接口定义、连线


//写fifo侧连线
    wire                                wrfifo_rden                ;
    wire                 [AXI_DATA_WIDTH-1: 0]wrfifo_dout          ;
    wire                 [FIFO_ADDR_WIDTH-1: 0]wrfifo_rd_cnt       ;
    wire                                wrfifo_empty               ;
    wire                                wrfifo_wr_rst_busy         ;
    wire                                wrfifo_rd_rst_busy         ;

//读fifo侧连线
    wire                                rdfifo_wren                ;
    wire                 [AXI_DATA_WIDTH-1: 0]rdfifo_din           ;
    wire                 [FIFO_ADDR_WIDTH-1: 0]rdfifo_wr_cnt       ;
    wire                                rdfifo_full                ;
    wire                                rdfifo_wr_rst_busy         ;
    wire                                rdfifo_rd_rst_busy         ;
//fifo双帧缓存连线

    wire                                w_buf                      ;
    wire                                r_buf                      ;
    wire                                r_addr_switch_pulse        ;
    wire                                w_addr_switch_pulse        ;

//axi4_to_fifo读完一帧信号
    wire                                r_done                     ;

//===============================================================================================================
//逻辑输出




//===============================================================================================================
//调用底层模块
//////////////////////////////////////////    双帧缓存切换逻辑      /////////////////////////////////////////

ddr3_double_buffer_ctrl u_ddr3_double_buffer_ctrl(
// ==================== 全局信号 ====================
    .ui_clk                             (clk                       ),// (input)// ui_clk时钟域时钟
    .reset                              (reset                     ),// (input)
// ==================== 读完、写完信号输入  ====================
    .w_done                             (camera_w_done             ),// (input)// Camera 写完
    .r_done                             (r_done                    ),// (input)// HDMI  读完
// ==================== 帧切换信号输出  ====================
    .w_buf                              (w_buf                     ),// (output)// 0=写帧A, 1=写帧B(camera侧)均为hdmi时钟域,默认写A
    .r_buf                              (r_buf                     ),// (output)// 0=读帧A, 1=读帧B（hdmi侧）均为hdmi时钟域，默认读B
    .r_addr_switch_pulse                (r_addr_switch_pulse       ),// (output)// 地址切换脉冲，与指针一同出现
    .w_addr_switch_pulse                (w_addr_switch_pulse       ) // (output)// 地址切换脉冲，与指针一同出现
);



//////////////////////////////////////////    异步写fifo       //////////////////////////////////////////
wr_ddr3_fifo wr_ddr3_fifo (
    .rst                                (wrfifo_clr                ),// input wire rst
    .wr_clk                             (wrfifo_clk                ),// input wire wr_clk
    .rd_clk                             (clk                       ),// input wire rd_clk
    .din                                (wrfifo_din                ),// input wire [15 : 0] din
    .wr_en                              (wrfifo_wren               ),// input wire wr_en
    .rd_en                              (wrfifo_rden               ),// input wire rd_en
    .dout                               (wrfifo_dout               ),// output wire [127 : 0] dout
    .full                               (wrfifo_full               ),// output wire full
    .empty                              (wrfifo_empty              ),// output wire empty
    .rd_data_count                      (wrfifo_rd_cnt             ),// output wire [5 : 0] rd_data_count
    .wr_data_count                      (wrfifo_wr_cnt             ),// output wire [8 : 0] wr_data_count
    .wr_rst_busy                        (wrfifo_wr_rst_busy        ),// output wire wr_rst_busy
    .rd_rst_busy                        (wrfifo_rd_rst_busy        ) // output wire rd_rst_busy
);

//////////////////////////////////////////    异步读fifo       //////////////////////////////////////////

rd_ddr3_fifo rd_ddr3_fifo (
    .rst                                (rdfifo_clr                ),// input wire rst
    .wr_clk                             (clk                       ),// input wire wr_clk
    .rd_clk                             (rdfifo_clk                ),// input wire rd_clk
    .din                                (rdfifo_din                ),// input wire [127 : 0] din
    .wr_en                              (rdfifo_wren               ),// input wire wr_en
    .rd_en                              (rdfifo_rden               ),// input wire rd_en
    .dout                               (rdfifo_dout               ),// output wire [15 : 0] dout
    .full                               (rdfifo_full               ),// output wire full
    .empty                              (rdfifo_empty              ),// output wire empty
    .rd_data_count                      (rdfifo_rd_cnt             ),// output wire [8 : 0] rd_data_count
    .wr_data_count                      (rdfifo_wr_cnt             ),// output wire [5 : 0] wr_data_count
    .wr_rst_busy                        (rdfifo_wr_rst_busy        ),// output wire wr_rst_busy
    .rd_rst_busy                        (rdfifo_rd_rst_busy        ) // output wire rd_rst_busy
);

//////////////////////////////////////////    fifo接口转axi4接口       //////////////////////////////////////////

fifo_to_axi4
  #(
    .AXI_BYTE_ADDR_BEGIN                (RD_AXI_BYTE_ADDR_BEGIN    ),
    .AXI_BYTE_ADDR_END                  (RD_AXI_BYTE_ADDR_END      ),
    .BUF_A_BEGIN                        (BUF_A_BEGIN               ),
    .BUF_B_BEGIN                        (BUF_B_BEGIN               ),

    .AXI_DATA_WIDTH                     (AXI_DATA_WIDTH            ),
    .AXI_ADDR_WIDTH                     (AXI_ADDR_WIDTH            ),
    .AXI_ID_WIDTH                       (AXI_ID_WIDTH              ),
    .AXI_ID                             (CAMERA_AXI_ID             ),//每个master的ID不同，需要差异化

    .AXI_BURST_LEN                      (AXI_BURST_LEN             ),
    .FIFO_ADDR_WIDTH                    (FIFO_ADDR_WIDTH           ),

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

  )fifo_to_axi4_inst
  (
    //时钟及复位
    .clk                                (clk                       ),
    .reset                              (reset                     ),

    //FIFO
    .fifo_rdreq                         (wrfifo_rden               ),
    .fifo_rddata                        (wrfifo_dout               ),
    .fifo_empty                         (wrfifo_empty              ),
    .fifo_rd_cnt                        (wrfifo_rd_cnt             ),
    .fifo_rst_busy                      (wrfifo_rd_rst_busy        ),

    // Slave 写地址通道
    .m_axi_awid                         (m_axi_awid                ),
    .m_axi_awaddr                       (m_axi_awaddr              ),
    .m_axi_awlen                        (m_axi_awlen               ),
    .m_axi_awsize                       (m_axi_awsize              ),
    .m_axi_awburst                      (m_axi_awburst             ),
    .m_axi_awlock                       (m_axi_awlock              ),
    .m_axi_awcache                      (m_axi_awcache             ),
    .m_axi_awprot                       (m_axi_awprot              ),
    .m_axi_awqos                        (m_axi_awqos               ),
    .m_axi_awregion                     (m_axi_awregion            ),
    .m_axi_awvalid                      (m_axi_awvalid             ),
    .m_axi_awready                      (m_axi_awready             ),

    // Slave 写数据通道
    .m_axi_wdata                        (m_axi_wdata               ),
    .m_axi_wstrb                        (m_axi_wstrb               ),
    .m_axi_wlast                        (m_axi_wlast               ),
    .m_axi_wvalid                       (m_axi_wvalid              ),
    .m_axi_wready                       (m_axi_wready              ),

    // Slave 写响应通道
    .m_axi_bid                          (m_axi_bid                 ),
    .m_axi_bresp                        (m_axi_bresp               ),
    .m_axi_bvalid                       (m_axi_bvalid              ),
    .m_axi_bready                       (m_axi_bready              ),

// ==================== 对外输出的一帧写完信号 ====================
    .camera_w_done                      (camera_w_done             ), // (output)// 帧写完成脉冲
// ==================== 双帧缓存切换逻辑信号 ====================
    .w_buf                              (w_buf                     ), // (input)// 0=写帧A, 1=写帧B(camera侧)均为hdmi时钟域,默认写A
    .w_addr_switch_pulse                (w_addr_switch_pulse       ) // (input)// 地址切换脉冲，与指针一同出现
  );

//////////////////////////////////////////    axi4接口转fifo接口      //////////////////////////////////////////
  axi4_to_fifo
  #(
    .AXI_BYTE_ADDR_BEGIN                (RD_AXI_BYTE_ADDR_BEGIN    ),
    .AXI_BYTE_ADDR_END                  (RD_AXI_BYTE_ADDR_END      ),
    .BUF_A_BEGIN                        (BUF_A_BEGIN               ),
    .BUF_B_BEGIN                        (BUF_B_BEGIN               ),
    .AXI_DATA_WIDTH                     (AXI_DATA_WIDTH            ),
    .AXI_ADDR_WIDTH                     (AXI_ADDR_WIDTH            ),
    .AXI_ID_WIDTH                       (AXI_ID_WIDTH              ),
    .AXI_ID                             (CAMERA_AXI_ID             ),//每个master的ID不同，需要差异化
    .AXI_BURST_LEN                      (AXI_BURST_LEN             ),
    .FIFO_ADDR_WIDTH                    (FIFO_ADDR_WIDTH           ),

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

  )axi4_to_fifo_inst
  (
    //时钟及复位
    .clk                                (clk                       ),
    .reset                              (reset                     ),

    //FIFO
    .fifo_wrreq                         (rdfifo_wren               ),
    .fifo_wrdata                        (rdfifo_din                ),
    .fifo_alfull                        (rdfifo_full               ),
    .fifo_wr_cnt                        (rdfifo_wr_cnt             ),
    .fifo_rst_busy                      (rdfifo_wr_rst_busy        ),

    // Slave 读地址通道
    .m_axi_arid                         (m_axi_arid                ),
    .m_axi_araddr                       (m_axi_araddr              ),
    .m_axi_arlen                        (m_axi_arlen               ),
    .m_axi_arsize                       (m_axi_arsize              ),
    .m_axi_arburst                      (m_axi_arburst             ),
    .m_axi_arlock                       (m_axi_arlock              ),
    .m_axi_arcache                      (m_axi_arcache             ),
    .m_axi_arprot                       (m_axi_arprot              ),
    .m_axi_arqos                        (m_axi_arqos               ),
    .m_axi_arregion                     (m_axi_arregion            ),
    .m_axi_arvalid                      (m_axi_arvalid             ),
    .m_axi_arready                      (m_axi_arready             ),

    // Slave 读数据通道
    .m_axi_rid                          (m_axi_rid                 ),
    .m_axi_rdata                        (m_axi_rdata               ),
    .m_axi_rresp                        (m_axi_rresp               ),
    .m_axi_rlast                        (m_axi_rlast               ),
    .m_axi_rvalid                       (m_axi_rvalid              ),
    .m_axi_rready                       (m_axi_rready              ),

    //实验接口
    .r_done                             (r_done                    ),//output(用于缓存切换)
    .rd_enable                          (camera_w_done            ),
    // ==================== 双帧缓存切换逻辑信号 ====================
    .r_buf                              (r_buf                     ), // (input)// 0=读帧A, 1=读帧B,默认读B
    .r_addr_switch_pulse                (r_addr_switch_pulse       ) // (input)// 地址切换脉冲，与指针一同出现
  );

endmodule


