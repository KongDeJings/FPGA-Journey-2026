`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/22 20:03:15
// Design Name: 
// Module Name: proc_w_fifo_to_axi4
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


module proc_w_fifo_to_axi4
#(
    // ==================== 地址与数据参数 ====================
    parameter                           BUF_A_BEGIN                 = 32'h0100_0000        ,//缓存A基地址
    parameter                           BUF_B_BEGIN                 = 32'h0120_0000        ,//缓存B基地址

    parameter                           AXI_DATA_WIDTH              = 128                  ,
    parameter                           AXI_ADDR_WIDTH              = 32                   ,
    parameter                           AXI_ID_WIDTH                = 4                    ,
    parameter                           AXI_ID                      = 4'b0000              ,
    parameter                           AXI_BURST_LEN               = 8'd31                ,
    parameter                           RD_DATA_CNT_WIDTH           = 8                    ,

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
    input                               clk                        ,
    input                               reset                      ,

    // ==================== 写FIFO用户写入侧接口 ====================

    output reg                          fifo_rdreq                 ,//fifo读请求
    input      [AXI_DATA_WIDTH-1: 0]    fifo_rddata                ,//fifo的数据位宽，和AXI4一样
    input                               fifo_empty                 ,
    input      [RD_DATA_CNT_WIDTH-1: 0]  fifo_rd_cnt               ,//fifo读cnt，指示fifo中还有多少数据
//    input                               fifo_rst_busy              ,//fifo复位忙，为1表示fifo正在复位

    // ==================== 写地址通道 ====================

    output        [AXI_ID_WIDTH-1: 0]   m_axi_awid                 ,
    output reg     [AXI_ADDR_WIDTH-1: 0]m_axi_awaddr               ,
    output               [   7: 0]      m_axi_awlen                ,
    output               [   2: 0]      m_axi_awsize               ,
    output               [   1: 0]      m_axi_awburst              ,
    output               [   0: 0]      m_axi_awlock               ,
    output               [   3: 0]      m_axi_awcache              ,
    output               [   2: 0]      m_axi_awprot               ,
    output               [   3: 0]      m_axi_awqos                ,
    output               [   3: 0]      m_axi_awregion             ,
    output reg                          m_axi_awvalid              ,
    input                               m_axi_awready              ,

    // ==================== 写数据通道 ====================

    output         [AXI_DATA_WIDTH-1: 0]m_axi_wdata                ,
    output         [AXI_DATA_WIDTH/8-1: 0]m_axi_wstrb              ,//指示数据有效,每8位位1组
    output reg                          m_axi_wlast                ,
    output reg                          m_axi_wvalid               ,
    input                               m_axi_wready               ,

    // ==================== 写响应通道 ====================
  
    input        [AXI_ID_WIDTH-1: 0]    m_axi_bid                  ,
    input                [   1: 0]      m_axi_bresp                ,
    input                               m_axi_bvalid               ,
    output                              m_axi_bready               ,

    // ==================== 对外输出的一帧写完信号 ====================
    output                              p_w_done                   ,// 帧写完成脉冲
    output reg                          p_module_ddr3_w_req        ,
    input                               p_w_start_pulse            ,
    output reg                          p_w_burst_done             ,
    // ==================== 双帧缓存切换逻辑信号 ====================
    input                               w_buf                      ,// 0=写帧A, 1=写帧B默认写A
    input                               w_addr_switch_pulse         //地址切换脉冲，与指针一同出现                

    );


//===============================================================================================================   


    localparam                          DATA_SIZE               = $clog2(AXI_DATA_WIDTH/8);
    localparam                          BURST_BYTE_LEN          = (AXI_BURST_LEN + 1) * (AXI_DATA_WIDTH/8);
    localparam                          WR_REQ_THRESHOLD         = AXI_BURST_LEN + 1;
    localparam                          BURST_COUNT                 = IMAGE_WIDTH*IMAGE_HEIGHT*2/((AXI_BURST_LEN[7:0]+1'b1)*(AXI_DATA_WIDTH/8));//完成一帧操作需要的突发次数

    reg                  [   4: 0]      current_state              ;
    reg                  [   4: 0]      next_state                 ;
    localparam                          S_IDLE                      = 1,
                                        S_WR_ADDR                   =2 ,
                                        S_WR_DATA_PRE               = 3,
                                        S_WR_DATA                   = 4,
                                        S_WR_RESP                   =5 ;
//5'b00001
//5'b00010
//5'b00100
//5'b01000
//5'b10000
//本地参数及接口定义、连线
    wire    [$clog2((AXI_BURST_LEN + 1) ): 0]  wr_req_cnt_thresh          ;//写请求计数器阈值信号
    reg                                 fifo_rddata_valid          ;//fifo数据有效信号，这个信号延后于fifo_rddata一拍
    reg     [AXI_DATA_WIDTH-1: 0]       fifo_rddata_latch          ;
    reg     [$clog2((AXI_BURST_LEN + 1) ): 0]  wr_data_cnt                ;
    reg     [$clog2(BURST_COUNT)-1: 0]  w_burst_done_cnt           ;// 已完成的读突发数
    reg                                 w_brust_complete                 ;// 帧读完成脉冲


//===============================================================================================================
//逻辑输出

    assign                              m_axi_awid                  = AXI_ID                        ;
    assign                              m_axi_awsize                = DATA_SIZE                     ;
    assign                              m_axi_awburst               = AXI_AWBURST_INCR              ;
    assign                              m_axi_awlock                = AXI_AWLOCK_NORMAL             ;
    assign                              m_axi_awcache               = AXI_AWCACHE_DEVICE_NON_BUF    ;
    assign                              m_axi_awprot                = AXI_AWPROT_UNPRIV_SECURE      ;
    assign                              m_axi_awqos                 = AXI_AWQOS_DEFAULT             ;
    assign                              m_axi_awregion              = AXI_AWREGION_DEFAULT          ;
    assign                              m_axi_awlen                 = AXI_BURST_LEN                 ;
    assign                              m_axi_wstrb                 = {(AXI_DATA_WIDTH/8){AXI_WSTRB_ALL_VALID}};

    assign                              p_w_done               = w_brust_complete           ;
//===============================================================================================================
//三段式状态机

// ==================== 第一段：状态转移 ====================

always @(posedge clk or posedge reset) begin
    if(reset)
    current_state<=S_IDLE;
    else
    current_state<=next_state;
end

// ==================== 第二段：下一状态逻辑 ====================
always @(*) begin
    case (current_state)
        S_IDLE        :begin
            if(p_w_start_pulse)
            next_state=S_WR_ADDR;
            else
            next_state=S_IDLE;
        end

        S_WR_ADDR     :begin
            if(m_axi_awready && m_axi_awvalid)
              next_state = S_WR_DATA_PRE;
            else
              next_state = S_WR_ADDR;            
        end

        S_WR_DATA_PRE :begin
            next_state = S_WR_DATA;  //作为冷启动状态机
        end

        S_WR_DATA     :begin
            if(m_axi_wready && m_axi_wvalid && m_axi_wlast)//突发一次的数据已经传完
              next_state = S_WR_RESP;
//            else if(m_axi_wready && m_axi_wvalid)     //不必返回,冷状态热流水
//              next_state = S_WR_DATA_PRE;
            else
          next_state = S_WR_DATA;            
        end
        S_WR_RESP     :begin
            if(m_axi_bready && m_axi_bvalid &&(m_axi_bresp == AXI_BRESP_OKAY)&& (m_axi_bid == AXI_ID))
              next_state = S_IDLE;
            else
              next_state = S_WR_RESP;            
            end  
        default: next_state=S_IDLE;
    endcase
end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ==================== 第三段：输出逻辑 ====================
//////////////////////////////////////////////////////////////////////////////////


//=========================   m_axi_bready信号如何产生   =================================//
  assign m_axi_bready  = 1'b1;         //!bready直接置1！


//=========================ddr3_req信号怎么得出=======================================//
    assign wr_req_cnt_thresh = WR_REQ_THRESHOLD;
    always @(*) begin
        if((fifo_rd_cnt>=wr_req_cnt_thresh)&&
            (~fifo_empty)
//            &&(fifo_rst_busy==0)     
            )
            p_module_ddr3_w_req=1;
        else
            p_module_ddr3_w_req=0;
        end
//=========================通过计数突发次数，判断是否写完一帧=======================================//
    always @(posedge clk or posedge reset) begin
        if(reset)begin
            w_burst_done_cnt<=0;
            w_brust_complete<=0;    
            p_w_burst_done<=0;   
        end

        else if(m_axi_bready && m_axi_bvalid &&(m_axi_bresp == AXI_BRESP_OKAY)&& (m_axi_bid == AXI_ID))begin
            p_w_burst_done<=1;
                    if (w_burst_done_cnt == BURST_COUNT -1) begin  // 最后一个突发
                            w_burst_done_cnt<=0;
                            w_brust_complete      <=1;  
                    end
                    else begin
                        w_burst_done_cnt<=w_burst_done_cnt+1;
                        w_brust_complete      <=0;
                    end
                end
        else begin
        w_brust_complete<=0; 
        p_w_burst_done<=0;         
        end 
        end

reg [2:0]w_brust_complete_r;
    always @(posedge clk or posedge reset)           
        begin                                        
            if(reset)                               
                w_brust_complete_r<=0;                                                                       
            else  begin
                w_brust_complete_r[0]<=w_brust_complete;
                w_brust_complete_r[1]<=w_brust_complete_r[0];
                w_brust_complete_r[2]<=w_brust_complete_r[1];    
            end                                    
        end     





//================================================================================
//
reg stop_sing;
    reg     [$clog2(BURST_COUNT)-1: 0]  w_burst_done_cnt_reg           ;// 已完成的读突发数
    always @(posedge clk or posedge reset)           
        begin                                        
            if(reset)                               
                w_burst_done_cnt_reg<=4000;                                                                       
            else if(p_w_start_pulse)     
                w_burst_done_cnt_reg<=w_burst_done_cnt;                         
        end         

    always @(posedge clk or posedge reset)           
        begin                                        
            if(reset)                               
                stop_sing<=0;                                                                       
            else if(p_w_start_pulse)     
                stop_sing<=(w_burst_done_cnt==w_burst_done_cnt_reg);                         
        end     


ila_0 your_instance_name (
    .clk                                (clk                       ),// input wire clk


    .probe0                             (w_burst_done_cnt          ),// input wire [11:0]  probe0  
    .probe1                             (stop_sing              ),// input wire [0:0]  probe1 
    .probe2                             (w_brust_complete          ),// input wire [0:0]  probe2 
    .probe3                             (p_w_burst_done            ),// input wire [0:0]  probe3 
    .probe4                             (w_addr_switch_pulse       ),// input wire [0:0]  probe4 
    .probe5                             ({p_w_start_pulse,p_module_ddr3_w_req}),// input wire [1:0]  probe5 
    .probe6                             (m_axi_bid                 ),// input wire [3:0]  probe6 
    .probe7                             (current_state             ) // input wire [4:0]  probe7
);

//================================================================================
//根据地址切换信号，动态更新地址
reg [31:0]dynamic_addr;

    always@(*)begin
            if(w_addr_switch_pulse) begin
               case (w_buf)
                   1: dynamic_addr=BUF_B_BEGIN;
                   0: dynamic_addr=BUF_A_BEGIN;
               endcase      
       end  
    end


//=========================产生m_axi_awaddr信号=======================================//
    always @(posedge clk or posedge reset) begin
        if(reset)
           m_axi_awaddr <= BUF_A_BEGIN;       //默认写A  
        else if(w_brust_complete_r[2])
           m_axi_awaddr <= dynamic_addr;           
        else if(m_axi_bvalid&&m_axi_bready&&(m_axi_bresp==AXI_BRESP_OKAY)&&(current_state == S_WR_RESP)&&(m_axi_bid == AXI_ID))
            m_axi_awaddr <= m_axi_awaddr+BURST_BYTE_LEN;
        else
            m_axi_awaddr <= m_axi_awaddr;
        end

//=========================产生m_axi_awvalid信号=======================================//
    always @(posedge clk or posedge reset) begin
        if(reset)
            m_axi_awvalid <= 0;
        else if(((current_state == S_WR_ADDR))&&m_axi_awvalid&&m_axi_awready)
            m_axi_awvalid <= 0;
        else if (current_state == S_WR_ADDR)
            m_axi_awvalid <= 1;//一进入写地址态就置1
        else
            m_axi_awvalid <= m_axi_awvalid;
            
        end

//=========================产生fifo读请求信号=======================================//
    always@(posedge clk or posedge reset)begin
        if(reset)
            fifo_rdreq <= 0;
        else if(((current_state == S_WR_ADDR))&&m_axi_awvalid&&m_axi_awready)
            fifo_rdreq <= 1;//冷启动
        else if(((current_state == S_WR_DATA))&&m_axi_wvalid&&m_axi_wready&&(~m_axi_wlast))
            fifo_rdreq <= 1;//热流水
        else
            fifo_rdreq <= 0;
        end

//=====基于读FIFO延迟一拍的特性，将输出的数据锁存，让他与WVALID和WREADY对齐==========================//
    always @(posedge clk) begin
        fifo_rddata_valid <= fifo_rdreq;
    end

    always @(posedge clk or posedge reset) begin
        if(reset)
            fifo_rddata_latch <= {AXI_DATA_WIDTH{1'b0}};
        else if(fifo_rddata_valid)
            fifo_rddata_latch <= fifo_rddata;//fifo读出的数据此时才送到锁存器端口
        end

assign m_axi_wdata =fifo_rddata_latch;


//=========================产生m_axi_wvalid信号=======================================//
    always @(posedge clk or posedge reset) begin
        if(reset)
            m_axi_wvalid <= 0;
        else if(
            (current_state == S_WR_DATA)&&
            m_axi_wvalid&&m_axi_wready
//            &&m_axi_wlast
            )
            m_axi_wvalid <= 0;
        else if (fifo_rddata_valid)
            m_axi_wvalid <= 1;//与fifo_rddata_latch信号产生在同一拍
        else
            m_axi_wvalid <= m_axi_wvalid;
        end

//=========================产生m_axi_wlast信号=======================================//
    always @(posedge clk or posedge reset) begin
        if(reset)
            m_axi_wlast <= 0;
        else if((current_state == S_WR_DATA)&&m_axi_wvalid&&m_axi_wready&&m_axi_wlast)
            m_axi_wlast <= 0;
        else if((wr_data_cnt==(AXI_BURST_LEN-1))&&m_axi_wvalid&&m_axi_wready)
            m_axi_wlast <= 1;
        else
            m_axi_wlast <= m_axi_wlast;
        end

//产生wlast信号所需的wr_data_cnt
    always @(posedge clk or posedge reset) begin
        if(reset)
            wr_data_cnt <= 0;
        else if(current_state == S_IDLE)
            wr_data_cnt <= 0;
        else if(m_axi_wready && m_axi_wvalid)
            wr_data_cnt <= 1+wr_data_cnt;
        else
            wr_data_cnt <= wr_data_cnt;
        end

endmodule
