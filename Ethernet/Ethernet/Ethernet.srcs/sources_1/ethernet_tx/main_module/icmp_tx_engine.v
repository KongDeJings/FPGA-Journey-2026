`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/04 08:14:24
// Design Name: 
// Module Name: icmp_tx_engine
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
//////////////////////////////////////////////////////////////////////////////////

module icmp_tx_engine
#(
    parameter                           PREAMBLE                    = 8'h55                ,// 前导码
    parameter                           SFD                         = 8'hD5                ,// 字节帧起始
    parameter                           ETH_TYPE                    = 16'h0800             ,// 类型、长度域，0800代表IPV4
    parameter                           IP_MARK                     = 16'h0                ,//标识
    parameter                           IP_FRAG_OFFSET              = 16'h0                ,//标志+片偏移
    parameter                           IP_VER                      = 8'h45                ,// 版本+首部长度
    parameter                           IP_SERVICE                  = 8'h00                ,// 服务类型
    parameter                           IP_TTL                      = 8'h80                ,// TTL生存时间
    parameter                           IP_PROTOCOL                 = 8'h01                ,// 上层协议，ICMP固定1
    parameter                           ICMP_TYPE                   = 8'h00                ,// ICMP类型，0-回显应答
    parameter                           ICMP_CODE                   = 8'h00                // ICMP代码
)
(
    // ==================== 全局信号 ====================
    input                               clk_125m                   ,// 主时钟 (125MHz, GMII时钟域)
    input                               rst_n                      ,// 异步低有效复位，同步化后使用
    
    // ==================== 控制接口 ====================
    input                               tx_start                   ,// 脉冲信号，启动一次ICMP发送
    output reg                          tx_done                    ,// 脉冲信号，一次发送完成
    
    // ==================== 协议参数接口 ====================
    // 注意：这些参数在tx_start有效时被锁存，发送过程中保持不变
    input                [  47: 0]      dst_mac                    ,// 目的MAC地址
    input                [  47: 0]      src_mac                    ,// 源MAC地址
    input                [  31: 0]      dst_ip                     ,// 目的IP地址
    input                [  31: 0]      src_ip                     ,// 源IP地址
    input                [  15: 0]      icmp_identifier            ,// ICMP标识符
    input                [  15: 0]      icmp_sequence              ,// ICMP序列号
    input                [  10: 0]      data_length                ,// ICMP数据部分长度（字节）
    input                [  15: 0]      ip_checksum                ,// IP头校验和(提前计算好的)
    input                [  15: 0]      icmp_checksum              ,// ICMP校验和(提前计算好的)
    
    // ==================== 数据源接口(FIFO读侧) ====================
    // 使用同步FIFO，时钟为clk_125m，FIFO必需为FWFT!
    input                [   7: 0]      fifo_data                  ,// FIFO读数据
    input                               fifo_empty                 ,// FIFO空标志(关键背压信号)
    output reg                          fifo_rd_en                 ,// FIFO读使能
    
    // ==================== 物理层接口(GMII) ====================
    output reg           [   7: 0]      gmii_txd                   ,// GMII发送数据
    output reg                          gmii_tx_en                 ,// GMII发送使能,高电平有效信号
    input                               gmii_tx_ready              ,// PHY准备好接收(关键背压信号)
    // ==================== CRC 计算模块接口 ====================
    output reg                          crc_en_icmp                ,
    output reg                          crc_frame_end_icmp         ,
    output reg           [   7: 0]      crc_data_in_icmp           ,
    output reg                          crc_data_valid_icmp        ,
    input                [  31: 0]      crc_result_icmp            ,
    input                               crc_valid_icmp              
);

// ==================== 参数定义 ====================
reg [6:0]   current_state, next_state;

localparam  IDLE           = 7'b000_0001,
            S_PREAMBLE     = 7'b000_0010,    // 前导码和SFD ,8    bytes
            S_MAC_HEADER   = 7'b000_0100,    // MAC头部     ,14   bytes
            S_IP_HEADER    = 7'b000_1000,    // IP头部      ,20   bytes
            S_ICMP_HEADER  = 7'b001_0000,    // ICMP头部    ,8    bytes
            S_PAYLOAD      = 7'b010_0000,    // ICMP数据    ,data_length_reg bytes
            S_FCS          = 7'b100_0000;    // CRC校验     ,4    bytes

localparam  PREAMBLE_BYTES         = 8,      // 各个发送状态的字节数
            MAC_HEADER_BYTES       = 14,
            IP_HEADER_BYTES        = 20,
            ICMP_HEADER_BYTES      = 8,
            CRC_CALC_OFFSET        = 2,//CRC校验和从计算到出数，需要两个周期
            FCS_BYTES              = 4;

//=================================================
// 产生tx_start的上升沿脉冲
wire tx_start_pluse;
reg [1:0] tx_start_reg;
always @(posedge clk_125m or negedge rst_n) begin
    if(!rst_n) begin
        tx_start_reg <= 2'b0;
    end
    else begin
        tx_start_reg[0] <= tx_start;
        tx_start_reg[1] <= tx_start_reg[0];
    end
end
assign tx_start_pluse = (tx_start_reg == 2'b01);

//=================================================
// MAC地址、IP地址、ICMP参数等协议参数的锁存寄存器
reg [47:0] dst_mac_reg;                 // 目的MAC地址
reg [47:0] src_mac_reg;                 // 源MAC地址
reg [31:0] dst_ip_reg;                  // 目的IP地址
reg [31:0] src_ip_reg;                  // 源IP地址
reg [15:0] icmp_identifier_reg;         // ICMP标识符
reg [15:0] icmp_sequence_reg;           // ICMP序列号
reg [15:0] data_length_reg;             // ICMP数据长度(字节数)
reg [15:0] icmp_checksum_reg;           // ICMP校验和

always @(posedge clk_125m or negedge rst_n) begin
    if(!rst_n) begin
        dst_mac_reg          <= dst_mac;
        src_mac_reg          <= 0;
        dst_ip_reg           <= dst_ip;
        src_ip_reg           <= 0;
        icmp_identifier_reg  <= 0;
        icmp_sequence_reg    <= 0;
        data_length_reg      <= 0;
        icmp_checksum_reg    <= 0;
    end
    else if(tx_start_pluse ) begin
        dst_mac_reg          <= dst_mac;
        src_mac_reg          <= src_mac;
        dst_ip_reg           <= dst_ip;
        src_ip_reg           <= src_ip;
        icmp_identifier_reg  <= icmp_identifier;
        icmp_sequence_reg    <= icmp_sequence;
        data_length_reg      <= data_length;
        icmp_checksum_reg    <= icmp_checksum;
    end
end

//=================================================
// 产生IP总长度
reg [15:0] ip_length;
always @(posedge clk_125m or negedge rst_n) begin
    if(!rst_n) begin
        ip_length <= 0;
    end
    else if(tx_start_pluse ) begin
        ip_length <= data_length + IP_HEADER_BYTES + ICMP_HEADER_BYTES;
    end
end

//=================================================
// 时间复用的全局字节计数器，每发送一个字节，计数一次
reg [15:0] byte_cnt;
assign send_condition = (gmii_tx_ready && (current_state != S_PAYLOAD) && (current_state != IDLE));
assign payload_send_condition = (gmii_tx_ready && (current_state == S_PAYLOAD) &&  (~fifo_empty));//在payload状态下，还需要考虑fifo读空这个背压条件

always @(posedge clk_125m or negedge rst_n) begin
    if(!rst_n) begin
        byte_cnt <= 0;
    end
    else if(send_condition||payload_send_condition) begin
        if(current_state != next_state)
            byte_cnt <= 0;                     // 状态要切换了，下个周期从0开始
        else
            byte_cnt <= byte_cnt + 1;          // 状态不变，继续计数
    end
    else begin
        byte_cnt <= byte_cnt;
    end
end

//=================================================
//产生gmii_tx_en,该信号高电平有效，在发送期间均为1，但是当gmii_tx_ready为0时，其必须为0
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                gmii_tx_en<=0;                                   
            else if(gmii_tx_ready==0)
                gmii_tx_en<=0; 
            else if ((current_state==S_FCS )&&(byte_cnt==CRC_CALC_OFFSET+FCS_BYTES))                            
                 gmii_tx_en<=0;    
            else if((current_state==S_PREAMBLE)&&(byte_cnt==CRC_CALC_OFFSET)) 
                gmii_tx_en<=1;                                                
            else  
                 gmii_tx_en<=gmii_tx_en;                                  
        end 

//=================================================
//产生crc_en_icmp,rc_data_valid,该信号高电平有效
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n) begin
                crc_en_icmp<=0;
                crc_data_valid_icmp <=0;                 
            end       
             else if(crc_frame_end_icmp)begin
                    crc_en_icmp<=0;
                    crc_data_valid_icmp <=crc_data_valid_icmp;
            end                                   
            else if(tx_done)begin
                    crc_en_icmp<=crc_en_icmp;
                    crc_data_valid_icmp <=0;
            end
            else if((current_state==S_MAC_HEADER)||
                    (current_state==S_IP_HEADER)||
                    (current_state==S_ICMP_HEADER)||
                    (current_state==S_PAYLOAD)         
                                    ) begin
                    crc_en_icmp<=1;
                    crc_data_valid_icmp <=1;
                                    end                                                                                           
        end        

//=================================================
//利用gmii_txd_pre和gmii_txd完成CRC并行计算延迟两拍的问题
reg [7:0]gmii_txd_pre;
reg [7:0]gmii_txd_r;
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)  begin
                 gmii_txd<=0;
                 gmii_txd_r<=0;
                 tx_done<=0; 
            end                             
            else if((current_state!=S_FCS)) begin
                 gmii_txd_r<=gmii_txd_pre;
                 gmii_txd<=gmii_txd_r;
                 tx_done<=0;    
            end                                                                
            else if((current_state==S_FCS)) begin
                    case (byte_cnt)
                        0:begin
                            gmii_txd_r<=gmii_txd_pre;
                            gmii_txd<=gmii_txd_r;                            
                        end
                        1:begin
                            gmii_txd_r<=gmii_txd_pre;
                            gmii_txd<=gmii_txd_r;
                        end
                        2:  gmii_txd <= crc_result_icmp[7 :0 ];   // 先发低字节
                        3:  gmii_txd <= crc_result_icmp[15:8 ];
                        4:  gmii_txd <= crc_result_icmp[23:16];

                        5:begin  gmii_txd <= crc_result_icmp[31:24]; tx_done<=1;   end// 最后发高字节
                        6:begin  gmii_txd_r <= 0 ; gmii_txd<= 0 ;tx_done<=0; end
                        default:begin gmii_txd<=gmii_txd;   tx_done<=0;   end
                    endcase
            end
            else begin  
                tx_done<=0;
            end

        end  

// ==================== 第一段：状态转移 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if(!rst_n) begin
        current_state <= IDLE;
    end
    else begin
        current_state <= next_state;
    end
end

// ==================== 第二段：下一状态逻辑 ====================
always @(*) begin
    case(current_state)
        IDLE: begin
            if(tx_start_pluse && gmii_tx_ready)
                next_state = S_PREAMBLE;
            else
                next_state = IDLE;
        end
        
        S_PREAMBLE: begin
            if((byte_cnt == PREAMBLE_BYTES - 1) && gmii_tx_ready)
                next_state = S_MAC_HEADER;
            else
                next_state = S_PREAMBLE;
        end
        
        S_MAC_HEADER: begin
            if((byte_cnt == MAC_HEADER_BYTES - 1) && gmii_tx_ready)
                next_state = S_IP_HEADER;
            else
                next_state = S_MAC_HEADER;
        end
        
        S_IP_HEADER: begin
            if((byte_cnt == IP_HEADER_BYTES - 1) && gmii_tx_ready)
                next_state = S_ICMP_HEADER;
            else
                next_state = S_IP_HEADER;
        end
        
        S_ICMP_HEADER: begin
            if((byte_cnt == ICMP_HEADER_BYTES - 1) && gmii_tx_ready) begin
                if(data_length_reg == 0)
                    next_state = S_FCS;                     // 无数据，直接到CRC
                else
                    next_state =S_PAYLOAD;
            end
            else begin
                next_state = S_ICMP_HEADER;
            end
        end
        
        S_PAYLOAD: begin
            if((byte_cnt == data_length_reg - 1) && gmii_tx_ready)
                next_state = S_FCS;
            else
                next_state =S_PAYLOAD;
        end
        
        S_FCS: begin
            if((byte_cnt == (FCS_BYTES+CRC_CALC_OFFSET)) && gmii_tx_ready )
                next_state = IDLE;
            else
                next_state = S_FCS;
        end
        
        default: next_state = IDLE;
    endcase
end

// ==================== 第三段：输出逻辑 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if(!rst_n) begin
        gmii_txd_pre    <= 8'b0;
        fifo_rd_en      <= 0;
        crc_frame_end_icmp   <= 0;
        crc_data_in_icmp     <= 0;
    end
    else begin
        case(current_state)
            IDLE: begin
                gmii_txd_pre  <= 8'b0;
                fifo_rd_en    <= 0;
                crc_frame_end_icmp <= 0;
                crc_data_in_icmp   <= 0;
            end
            
            S_PREAMBLE: begin
                case(byte_cnt)
                    0,1,2,3,4,5,6: gmii_txd_pre <= PREAMBLE;
                    7: gmii_txd_pre <= SFD;
                    default: gmii_txd_pre <= gmii_txd_pre;
                endcase
            end
            
            S_MAC_HEADER: begin
                case(byte_cnt)
                    0:  begin gmii_txd_pre <= dst_mac_reg[47:40]; crc_data_in_icmp <= dst_mac_reg[47:40]; end
                    1:  begin gmii_txd_pre <= dst_mac_reg[39:32]; crc_data_in_icmp <= dst_mac_reg[39:32]; end
                    2:  begin gmii_txd_pre <= dst_mac_reg[31:24]; crc_data_in_icmp <= dst_mac_reg[31:24]; end
                    3:  begin gmii_txd_pre <= dst_mac_reg[23:16]; crc_data_in_icmp <= dst_mac_reg[23:16]; end
                    4:  begin gmii_txd_pre <= dst_mac_reg[15:8];  crc_data_in_icmp <= dst_mac_reg[15:8] ;  end
                    5:  begin gmii_txd_pre <= dst_mac_reg[7:0];   crc_data_in_icmp <= dst_mac_reg[7:0]  ;   end

                    6:  begin gmii_txd_pre <= src_mac_reg[47:40]; crc_data_in_icmp <= src_mac_reg[47:40]; end
                    7:  begin gmii_txd_pre <= src_mac_reg[39:32]; crc_data_in_icmp <= src_mac_reg[39:32]; end
                    8:  begin gmii_txd_pre <= src_mac_reg[31:24]; crc_data_in_icmp <= src_mac_reg[31:24]; end
                    9:  begin gmii_txd_pre <= src_mac_reg[23:16]; crc_data_in_icmp <= src_mac_reg[23:16]; end
                    10: begin gmii_txd_pre <= src_mac_reg[15:8];  crc_data_in_icmp <= src_mac_reg[15:8];  end
                    11: begin gmii_txd_pre <= src_mac_reg[7:0];   crc_data_in_icmp <= src_mac_reg[7:0];   end

                    12: begin gmii_txd_pre <= ETH_TYPE[15:8];     crc_data_in_icmp <= ETH_TYPE[15:8];     end
                    13: begin gmii_txd_pre <= ETH_TYPE[7:0];      crc_data_in_icmp <= ETH_TYPE[7:0];      end
                    default: gmii_txd_pre <= gmii_txd_pre;
                endcase
            end
            
            S_IP_HEADER: begin
                case(byte_cnt)
                    0 :begin gmii_txd_pre<= IP_VER                  ;   crc_data_in_icmp  <= IP_VER                  ;end
                    1 :begin gmii_txd_pre<= IP_SERVICE              ;   crc_data_in_icmp  <= IP_SERVICE              ;end
                    2 :begin gmii_txd_pre<= ip_length[15: 8]        ;   crc_data_in_icmp  <= ip_length[15: 8]        ;end
                    3 :begin gmii_txd_pre<= ip_length[7 : 0]        ;   crc_data_in_icmp  <= ip_length[7 : 0]        ;end
                    4 :begin gmii_txd_pre<= IP_MARK[15: 8]          ;   crc_data_in_icmp  <= IP_MARK[15: 8]          ;end
                    5 :begin gmii_txd_pre<= IP_MARK[7 : 0]          ;   crc_data_in_icmp  <= IP_MARK[7 : 0]          ;end
                    6 :begin gmii_txd_pre<= IP_FRAG_OFFSET[15: 8]   ;   crc_data_in_icmp  <= IP_FRAG_OFFSET[15: 8]   ;end
                    7 :begin gmii_txd_pre<= IP_FRAG_OFFSET[7 : 0]   ;   crc_data_in_icmp  <= IP_FRAG_OFFSET[7 : 0]   ;end
                    8 :begin gmii_txd_pre<= IP_TTL                  ;   crc_data_in_icmp  <= IP_TTL                  ;end
                    9 :begin gmii_txd_pre<= IP_PROTOCOL             ;   crc_data_in_icmp  <= IP_PROTOCOL             ;end
                    10:begin gmii_txd_pre<= ip_checksum[15: 8]      ;   crc_data_in_icmp  <= ip_checksum[15: 8]      ;end
                    11:begin gmii_txd_pre<= ip_checksum[7 : 0]      ;   crc_data_in_icmp  <= ip_checksum[7 : 0]      ;end
                    12:begin gmii_txd_pre<= src_ip_reg[31:24]       ;   crc_data_in_icmp  <= src_ip_reg[31:24]       ;end
                    13:begin gmii_txd_pre<= src_ip_reg[23:16]       ;   crc_data_in_icmp  <= src_ip_reg[23:16]       ;end
                    14:begin gmii_txd_pre<= src_ip_reg[15: 8]       ;   crc_data_in_icmp  <= src_ip_reg[15: 8]       ;end
                    15:begin gmii_txd_pre<= src_ip_reg[7 : 0]       ;   crc_data_in_icmp  <= src_ip_reg[7 : 0]       ;end
                    16:begin gmii_txd_pre<= dst_ip_reg[31:24]       ;   crc_data_in_icmp  <= dst_ip_reg[31:24]       ;end
                    17:begin gmii_txd_pre<= dst_ip_reg[23:16]       ;   crc_data_in_icmp  <= dst_ip_reg[23:16]       ;end
                    18:begin gmii_txd_pre<= dst_ip_reg[15: 8]       ;   crc_data_in_icmp  <= dst_ip_reg[15: 8]       ;end
                    19:begin gmii_txd_pre<= dst_ip_reg[7 : 0]       ;   crc_data_in_icmp  <= dst_ip_reg[7 : 0]       ;end
                    default: gmii_txd_pre <= gmii_txd_pre;
                endcase
            end
            
            S_ICMP_HEADER: begin
                case(byte_cnt)
                    0: begin gmii_txd_pre <= ICMP_TYPE;                   crc_data_in_icmp <= ICMP_TYPE;                   end
                    1: begin gmii_txd_pre <= ICMP_CODE;                   crc_data_in_icmp <= ICMP_CODE;                   end
                    2: begin gmii_txd_pre <= icmp_checksum_reg[15:8];     crc_data_in_icmp <= icmp_checksum_reg[15:8];     end
                    3: begin gmii_txd_pre <= icmp_checksum_reg[7:0];      crc_data_in_icmp <= icmp_checksum_reg[7:0];      end
                    4: begin gmii_txd_pre <= icmp_identifier_reg[15:8];   crc_data_in_icmp <= icmp_identifier_reg[15:8];   end
                    5: begin gmii_txd_pre <= icmp_identifier_reg[7:0];    crc_data_in_icmp <= icmp_identifier_reg[7:0];    end
                    6: begin gmii_txd_pre <= icmp_sequence_reg[15:8];     crc_data_in_icmp <= icmp_sequence_reg[15:8];     end
                    7: begin 
                        gmii_txd_pre <= icmp_sequence_reg[7:0];
                        crc_data_in_icmp  <= icmp_sequence_reg[7:0];
                        fifo_rd_en  <= 1'b1;  // 准备从FIFO读取ICMP数据
                    end
                    default: gmii_txd_pre <= gmii_txd_pre;
                endcase
            end
            
           S_PAYLOAD: begin
                gmii_txd_pre <= fifo_data;      // FWFT特性，立即可用
                crc_data_in_icmp  <= fifo_data;
                if(byte_cnt == data_length_reg - 1) begin//这里的时序要对上，要恰好把dout消耗完
                    fifo_rd_en <= 1'b0;
                end
                else if(byte_cnt == data_length_reg - 1) begin
                    crc_frame_end_icmp <= 1;         // 最后一个数据字节
                end
            end
            
            S_FCS: begin
                case(byte_cnt)
                    0: begin
                        fifo_rd_en    <= 1'b0;
                        crc_frame_end_icmp <= 0;
                        gmii_txd_pre <= 0;
                    end
                    default: begin
                        fifo_rd_en    <= 1'b0;
                        crc_frame_end_icmp <= 0;
                    end
                endcase
            end
            
            default: begin
                gmii_txd_pre  <= gmii_txd_pre;  // 默认保持
                fifo_rd_en    <= 0;
                crc_frame_end_icmp <= 0;
                crc_data_in_icmp   <= 0;
            end
        endcase
    end
end
endmodule
