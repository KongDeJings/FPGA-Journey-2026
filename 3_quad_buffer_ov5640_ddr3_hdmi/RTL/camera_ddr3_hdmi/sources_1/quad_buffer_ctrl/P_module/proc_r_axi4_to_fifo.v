`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/22 20:03:15
// Design Name: 
// Module Name: proc_r_axi4_to_fifo
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
module proc_r_axi4_to_fifo
#(
    
    // ==================== 地址与数据参数 ====================
    parameter                           BUF_A_BEGIN                 = 32'h0100_0000        ,//缓存A基地址
    parameter                           BUF_B_BEGIN                 = 32'h0120_0000        ,//缓存B基地址
    parameter                           AXI_DATA_WIDTH              = 128                  ,
    parameter                           AXI_ADDR_WIDTH              = 32                   ,
    parameter                           AXI_ID_WIDTH                = 4                    ,
    parameter                           AXI_ID                      = 0                    ,
    parameter                           AXI_BURST_LEN               = 31                   ,
    parameter                           FIFO_ADDR_WIDTH             = 8                    ,

    // ==================== AXI 固定协议参数 ====================
    parameter                           AXI_ARBURST_INCR            = 2'b01                ,
    parameter                           AXI_ARLOCK_NORMAL           = 1'b0                 ,
    parameter                           AXI_ARCACHE_DEVICE_NON_BUF  = 4'b0000              ,
    parameter                           AXI_ARPROT_UNPRIV_SECURE    = 3'b000               ,
    parameter                           AXI_ARQOS_DEFAULT           = 4'b0000              ,
    parameter                           AXI_ARREGION_DEFAULT        = 4'b0000              ,
    parameter                           AXI_RRESP_OKAY              = 2'b00                ,
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

    output reg                          fifo_wrreq                 ,
    output reg           [AXI_DATA_WIDTH-1: 0]fifo_wrdata          ,
    input                               fifo_alfull                ,
    input                [FIFO_ADDR_WIDTH-1: 0]fifo_wr_cnt         ,
//    input                               fifo_rst_busy            ,//同步fifo无此信号

    // ==================== 读地址通道 ====================  
    output         [AXI_ID_WIDTH-1: 0]  m_axi_arid                 ,
    output reg     [AXI_ADDR_WIDTH-1: 0]m_axi_araddr               ,
    output               [   7: 0]      m_axi_arlen                ,
    output               [   2: 0]      m_axi_arsize               ,
    output               [   1: 0]      m_axi_arburst              ,
    output               [   0: 0]      m_axi_arlock               ,
    output               [   3: 0]      m_axi_arcache              ,
    output               [   2: 0]      m_axi_arprot               ,
    output               [   3: 0]      m_axi_arqos                ,
    output               [   3: 0]      m_axi_arregion             ,
    output reg                          m_axi_arvalid              ,
    input                               m_axi_arready              ,

    // ==================== 读数据通道 ==================== 
    input        [AXI_ID_WIDTH-1: 0]    m_axi_rid                  ,
    input        [AXI_DATA_WIDTH-1: 0]  m_axi_rdata                ,
    input                [   1: 0]      m_axi_rresp                ,
    input                               m_axi_rlast                ,
    input                               m_axi_rvalid               ,
    output reg                          m_axi_rready               ,

    //==================== 实验接口 ====================
    output                              r_done                     ,
    input                               rd_enable                  ,
    output  reg                         p_module_ddr3_r_req        ,
    input                               p_r_start_pulse            ,
    output reg                          p_r_burst_done             ,
    // ==================== 双帧缓存切换逻辑信号 ====================
    input                               r_buf                       ,// 0=读帧A, 1=读帧B,默认读B
    input                               r_addr_switch_pulse          //地址切换脉冲，与指针一同出现
    );


//===============================================================================================================   
//本地参数及接口定义、连线

    reg                  [   2: 0]      current_state              ;
    reg                  [   2: 0]      next_state                 ;
    localparam                          S_IDLE                     = 3'b001               ,
                                        S_RD_ADDR                  = 3'b010,
                                        S_RD_RESP                  = 3'b100;

    wire                 [FIFO_ADDR_WIDTH-1: 0]rd_req_cnt_thresh    ;

    localparam                          DATA_SIZE                   = $clog2(AXI_DATA_WIDTH/8)  ;
    localparam                          BURST_BYTE_LEN              = (AXI_BURST_LEN + 1) * (AXI_DATA_WIDTH/8);
    localparam                          FIFO_SAFE_THRESHOLD         = 2**FIFO_ADDR_WIDTH - (AXI_BURST_LEN[7:0]+1'b1); //如果fifo中数据的量大于这个量，那么fifo中剩余的空间就不支持再读一次DDR3了
    localparam                          BURST_COUNT                 = IMAGE_WIDTH*IMAGE_HEIGHT*2/((AXI_BURST_LEN[7:0]+1'b1)*(AXI_DATA_WIDTH/8));//完成一帧操作需要的突发次数
    localparam TOTAL_BEATS =(IMAGE_WIDTH*IMAGE_HEIGHT*2/(AXI_DATA_WIDTH/8)) ;
//===============================================================================================================
//逻辑输出

    assign                              m_axi_arsize                = DATA_SIZE                     ;
    assign                              m_axi_arid                  = AXI_ID                        ;
    assign                              m_axi_arburst               = AXI_ARBURST_INCR              ;
    assign                              m_axi_arlock                = AXI_ARLOCK_NORMAL             ;
    assign                              m_axi_arcache               = AXI_ARCACHE_DEVICE_NON_BUF    ;
    assign                              m_axi_arprot                = AXI_ARPROT_UNPRIV_SECURE      ;
    assign                              m_axi_arqos                 = AXI_ARQOS_DEFAULT             ;
    assign                              m_axi_arregion              = AXI_ARREGION_DEFAULT          ;
    assign                              m_axi_arlen                 = AXI_BURST_LEN                 ;

// ==================== 第一段：状态转移 ====================
always @(posedge clk or posedge reset) begin
    if(reset)
    current_state<=S_IDLE;
    else
    current_state<=next_state;
end

// ==================== 第二段：下一状态逻辑 ====================
always @(*) begin
    if(reset)
    next_state=S_IDLE;
    else
    case (current_state)
        S_IDLE    :begin
            if(p_r_start_pulse)
            next_state=S_RD_ADDR;
            else
            next_state=S_IDLE;
        end
        S_RD_ADDR :begin
            if(m_axi_arvalid&&m_axi_arready)
            next_state=S_RD_RESP;
            else
            next_state=S_RD_ADDR;
        end
        S_RD_RESP :begin
            if(m_axi_rvalid&&m_axi_rready&&m_axi_rlast&&
            (m_axi_rresp==2'b00)&&
            (m_axi_rid==AXI_ID)
            )
            next_state=S_IDLE;   //代表发完一拍数据
            else
            next_state=S_RD_RESP;
        end 
        default: next_state=S_IDLE;
    endcase
end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ==================== 第三段：输出逻辑 ====================
//////////////////////////////////////////////////////////////////////////////////


//=========================m_axi_rready信号怎么产生=======================================//
always @(posedge clk or posedge reset) begin
    if (reset)
        m_axi_rready <= 0;
    else if (~fifo_alfull)
        m_axi_rready <= 1;
end
 //assign m_axi_rready  = 1'b1;

//=========================产生帧激活信号frame_active======================================//
reg  frame_active;    //拉高代表ddr3内已经有数据可用此时开始读，不会产生“垃圾读”

always @(posedge clk or posedge reset) begin
    if (reset)
        frame_active <= 0;
    else if (rd_enable)
        frame_active <= 1;
end

//=========================产生ddr3开始读信号======================================//
assign rd_req_cnt_thresh = FIFO_SAFE_THRESHOLD[FIFO_ADDR_WIDTH-1:0]; //如果fifo中数据的量大于这个量，那么fifo中剩余的空间就不支持再读一次DDR3了
//目的：保证读 DDR 之前，FIFO 一定有足够空间装下整段突发，绝不溢出！

always @(posedge clk or posedge reset) begin
    if (reset)
        p_module_ddr3_r_req <= 0;
    else if ((fifo_wr_cnt < rd_req_cnt_thresh - 2) && frame_active)begin
        if(r_done)
        p_module_ddr3_r_req <= 0;
        else if(rd_enable) 
        p_module_ddr3_r_req <= 1;    
        else
        p_module_ddr3_r_req <=   p_module_ddr3_r_req;        
    end
    else
        p_module_ddr3_r_req <=   p_module_ddr3_r_req;        
end
//================================================================================
//通过计数读突发次数，来标定一帧信号结束
reg [($clog2(BURST_COUNT)-1):0] rd_burst_done_cnt;           // 已完成的读突发数
reg        r_brust_complete;                                  // 帧读完成脉冲


always @(posedge clk or posedge reset) begin
    if (reset) begin
        rd_burst_done_cnt <= 0;
        r_brust_complete <= 0;
        p_r_burst_done<=0;
    end 
    else if (m_axi_rvalid && m_axi_rready && m_axi_rlast &&   // 每完成一个属于自己的读突发，计数+1
            (m_axi_rid == AXI_ID)&&
            frame_active)
             begin
                p_r_burst_done<=1;
            if (rd_burst_done_cnt == BURST_COUNT-1) begin  // 最后一个突发
                r_brust_complete <= 1;
            rd_burst_done_cnt <= 0;
            end
            else begin
                rd_burst_done_cnt <= rd_burst_done_cnt + 1;
                r_brust_complete <= 0;
            end
        end
    else begin 
        r_brust_complete <= 0;    
        p_r_burst_done<=0;        
    end    
end

assign  r_done   =    r_brust_complete;

reg [2:0]r_brust_complete_r;
    always @(posedge clk or posedge reset)           
        begin                                        
            if(reset)                               
                r_brust_complete_r<=0;                                                                       
            else  begin
                r_brust_complete_r[0]<=r_brust_complete;
                r_brust_complete_r[1]<=r_brust_complete_r[0];
                r_brust_complete_r[2]<=r_brust_complete_r[1];    
            end                                    
        end                                          


//================================================================================
//根据地址切换信号，动态更新地址
reg [31:0]dynamic_addr;

    always@(*)begin
            if(r_addr_switch_pulse) begin
               case (r_buf)
                   1: dynamic_addr=BUF_B_BEGIN;
                   0: dynamic_addr=BUF_A_BEGIN;
               endcase      
       end  
    end
    
//===========================如何产生m_axi_araddr信号====================
  always@(posedge clk or posedge reset)
  begin
    if(reset)
      m_axi_araddr <= BUF_B_BEGIN;      //默认读B
    else if(r_brust_complete_r[2])    
      m_axi_araddr <= dynamic_addr;                
    else if((current_state == S_RD_RESP) &&
     m_axi_rready && m_axi_rvalid && m_axi_rlast && 
     (m_axi_rresp == AXI_RRESP_OKAY) &&
      (m_axi_rid == AXI_ID)
      &&frame_active
       )
      m_axi_araddr <= m_axi_araddr +BURST_BYTE_LEN;  
    else
      m_axi_araddr <= m_axi_araddr;
  end

//===========================如何产生m_axi_arvalid信号====================
always @(posedge clk or posedge reset) begin
    if(reset)
    m_axi_arvalid<=0;
    else if((current_state==S_RD_ADDR)&&m_axi_arready && m_axi_arvalid)
    m_axi_arvalid<=0;
    else if((current_state==S_RD_ADDR))
    m_axi_arvalid<=1;
    else
    m_axi_arvalid<=m_axi_arvalid;
end

//===========================如何产生fifo写请求信号====================
    always @(posedge clk or posedge reset) begin
        if(reset)
            fifo_wrreq <= 1'b0;
        else
            fifo_wrreq <= m_axi_rvalid && m_axi_rready&&frame_active &&(m_axi_rid==AXI_ID);
        end

    always @(posedge clk) begin
        if(reset)
            fifo_wrdata <= 0;        
        else if(m_axi_rvalid && m_axi_rready&&frame_active&&(m_axi_rid==AXI_ID))
            fifo_wrdata <= m_axi_rdata;
        end


        
endmodule