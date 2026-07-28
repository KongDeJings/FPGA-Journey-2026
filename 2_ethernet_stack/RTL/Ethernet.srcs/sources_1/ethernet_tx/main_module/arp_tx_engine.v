`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/06/03 14:35:00
// Design Name: 
// Module Name: arp_tx_engine
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// 代码中禁止出现魔数！
//////////////////////////////////////////////////////////////////////////////////

module arp_tx_engine
#(
    parameter                           PREAMBLE                    = 8'h55                ,
    parameter                           SFD                         = 8'hD5                ,
    parameter                           ETH_TYPE_ARP                = 16'h0806             ,// ARP类型
    parameter                           HW_TYPE_ETHERNET            = 16'h0001             ,// 以太网
    parameter                           PROTO_TYPE_IPV4             = 16'h0800             ,// IPv4
    parameter                           HW_SIZE                     = 8'h06                ,// MAC地址长度
    parameter                           PROTO_SIZE                  = 8'h04                ,// IP地址长度
    parameter                           OPCODE_REQUEST              = 16'h0001             ,// ARP请求
    parameter                           OPCODE_REPLY                = 16'h0002              // ARP响应
)
(
    input                               clk_125m                   ,
    input                               rst_n                      ,

    // ==================== 来自 ARP Cache（Reply） ====================
    input                               arp_reply_req              ,// 需要回 Reply
    input                [  47: 0]      arp_target_mac             ,// 对方 MAC
    input                [  31: 0]      arp_target_ip              ,// 对方 IP

    // ==================== 来自 ARP cache（Request） ====================
    input                               arp_tx_req                 ,// 需要发 Request
    input                [  31: 0]      arp_tx_ip                  ,// 要解析的 IP
    input                [  47: 0]      arp_tx_dst_mac             ,// 目的 MAC（广播）

    // ==================== 直接到 PHY ====================
    output reg           [   7: 0]      gmii_txd                   ,// GMII发送数据
    output reg                          gmii_tx_en                 ,// GMII发送使能,高电平有效信号
    input                               gmii_tx_ready              ,// PHY准备好接收(关键背压信号)

    // ==================== 本地配置 ====================
    input                [  47: 0]      local_mac                  ,
    input                [  31: 0]      local_ip                   ,

    // ==================== 控制接口 ====================
    output reg                          arp_tx_done                ,// 脉冲信号，一次发送完成 
    // ==================== CRC 计算模块接口 ====================
    output reg                          crc_en_arp                 ,
    output reg                          crc_frame_end_arp          ,
    output reg           [   7: 0]      crc_data_in_arp            ,
    output reg                          crc_data_valid_arp         ,
    input                [  31: 0]      crc_result_arp             ,
    input                               crc_valid_arp                   
);

// ==================== 状态机定义 ====================
reg [5:0]   current_state, next_state;
localparam  IDLE           = 6'b00_0001,
            S_PREAMBLE     = 6'b00_0010,    // 前导码+SFD
            S_MAC_HEADER   = 6'b00_0100,    // 以太网头
            S_ARP_HEADER   = 6'b00_1000,    // ARP头部
            S_PAYLAOD      = 6'b01_0000,    // ARP数据,全部填0
            S_FCS          = 6'b10_0000;    // CRC

localparam  PREAMBLE_BYTES     = 8  ,
            MAC_HEADER_BYTES   = 14 ,
            ARP_HEADER_BYTES   = 28 , 
            ARP_PAYLOAD_BYTES  = 18 , //  数据载荷长度
            CRC_CALC_OFFSET    = 2  ,//CRC校验和从计算到出数，需要两个周期
            FCS_BYTES          = 4  ;


// ==================== 参数锁存 ====================
reg [15:0]  arp_opcode_reg;
reg [47:0]  src_mac_reg;
reg [31:0]  src_ip_reg;
reg [47:0]  target_mac_reg;
reg [31:0]  target_ip_reg;
reg [47:0]  broadcast_mac = 48'hFF_FF_FF_FF_FF_FF;



//=================================================
//产生tx_start的上升沿脉冲
wire reply_arp_tx_start_pluse;         //回复
wire request_arp_tx_start_pluse;       //请求
wire arp_tx_start_pluse;
assign arp_tx_start_pluse=(reply_arp_tx_start_pluse||request_arp_tx_start_pluse);//二者任意一个都可以,均可驱动状态机启动

reg [1:0]reply_start_reg;
reg [1:0]request_start_reg;

    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n) begin                                                            
                reply_start_reg<=2'b0;
                request_start_reg<=2'b0;
            end                                           
            else begin
                reply_start_reg[0]<=arp_reply_req;
                reply_start_reg[1]<=reply_start_reg[0];

                request_start_reg[0]<=arp_tx_req;
                request_start_reg[1]<=request_start_reg[0];                
            end                                                 
        end             

assign reply_arp_tx_start_pluse  =(reply_start_reg==2'b01);
assign request_arp_tx_start_pluse=(request_start_reg==2'b01);

// ==================== 参数锁存 ====================

always @(posedge clk_125m or negedge rst_n) begin
    if(!rst_n) begin
        arp_opcode_reg <= 0;
        src_mac_reg <= 0;
        src_ip_reg <= 0;
        target_mac_reg <= 0;
        target_ip_reg <= 0;
    end
    else if(reply_arp_tx_start_pluse ) begin   //回复时
        arp_opcode_reg    <=        OPCODE_REPLY     ;
        src_mac_reg       <=       local_mac         ;
        src_ip_reg        <=       local_ip          ;
        target_mac_reg    <=    arp_target_mac       ;
        target_ip_reg     <=    arp_target_ip        ;
    end
    else if(request_arp_tx_start_pluse)begin    //请求时
        arp_opcode_reg    <=     OPCODE_REQUEST      ;
        src_mac_reg       <=        local_mac        ;
        src_ip_reg        <=        local_ip         ;
        target_mac_reg    <=    arp_tx_dst_mac       ;           // 目的 MAC（广播）
        target_ip_reg     <=     arp_tx_ip           ;
    end
//默认条件保持不变
end

// ==================== 字节计数器 ====================
    reg                  [   6: 0]      byte_cnt                   ;//ARP长64，为了多留余量，位宽多取了一位
wire send_condition = (gmii_tx_ready && (current_state != IDLE));
always @(posedge clk_125m or negedge rst_n) begin
    if(!rst_n)
        byte_cnt <= 0;
    else if(send_condition) begin
        if(current_state != next_state)
            byte_cnt <= 0;
        else
            byte_cnt <= byte_cnt + 1;
    end
    else
        byte_cnt <= byte_cnt;
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
//产生crc_en_arp,crc_data_valid_arp,该信号高电平有效
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n) begin
                crc_en_arp<=0;
                crc_data_valid_arp <=0;                 
            end       
             else if(crc_frame_end_arp)begin
                    crc_en_arp<=0;
                    crc_data_valid_arp <=crc_data_valid_arp;
            end                                   
            else if(arp_tx_done)begin
                    crc_en_arp<=crc_en_arp;
                    crc_data_valid_arp <=0;
            end
            else if((current_state==S_MAC_HEADER)||
                    (current_state==S_MAC_HEADER)||
                    (current_state==S_ARP_HEADER)||
                    (current_state==S_PAYLAOD   )         
                                    ) begin
                    crc_en_arp<=1;
                    crc_data_valid_arp <=1;
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
                 arp_tx_done<=0; 
            end                             
            else if((current_state!=S_FCS)) begin
                 gmii_txd_r<=gmii_txd_pre;
                 gmii_txd<=gmii_txd_r;
                 arp_tx_done<=0;    
            end                                                                
            else if((current_state==S_FCS)) begin
                    case (byte_cnt)
                        2:  gmii_txd <= 8'h66;   // 先发低字节
                        3:  gmii_txd <= 8'hf4;
                        4:  gmii_txd <=  8'h2f;
                        5:begin  gmii_txd <= 8'h15; arp_tx_done<=1;   end// 最后发高字节
//                        2:  gmii_txd <= crc_result_arp[7 :0 ];   // 先发低字节
//                        3:  gmii_txd <= crc_result_arp[15:8 ];
//                        4:  gmii_txd <= crc_result_arp[23:16];
//                        5:begin  gmii_txd <= crc_result_arp[31:24]; arp_tx_done<=1;   end// 最后发高字节
                        6:begin  gmii_txd_r <= 0 ; gmii_txd<= 0 ;arp_tx_done<=0; end
                        default:begin gmii_txd<=gmii_txd;   arp_tx_done<=0;   end
                    endcase
            end
            else begin  
                arp_tx_done<=0;
            end

        end  


// ==================== 状态机第一段 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if(!rst_n)
        current_state <= IDLE;
    else
        current_state <= next_state;
end

// ==================== 状态机第二段 ====================
always @(*) begin
    case(current_state)
        IDLE: begin
            if(arp_tx_start_pluse && gmii_tx_ready)
                next_state = S_PREAMBLE;
            else
                next_state = IDLE;
        end
        
        S_PREAMBLE: begin
            if(byte_cnt == PREAMBLE_BYTES-1 && gmii_tx_ready)
                next_state = S_MAC_HEADER;
            else
                next_state = S_PREAMBLE;
        end
        
        S_MAC_HEADER: begin
            if(byte_cnt == MAC_HEADER_BYTES-1 && gmii_tx_ready)
                next_state = S_ARP_HEADER;
            else
                next_state = S_MAC_HEADER;
        end
        
        S_ARP_HEADER: begin
            if(byte_cnt == ARP_HEADER_BYTES-1 && gmii_tx_ready)
                next_state = S_PAYLAOD;
            else
                next_state = S_ARP_HEADER;
        end
        
        S_PAYLAOD: begin
            if(byte_cnt == ARP_PAYLOAD_BYTES-1 && gmii_tx_ready)
                next_state = S_FCS;
            else
                next_state = S_PAYLAOD;
        end
        
        S_FCS: begin
            if(byte_cnt == (FCS_BYTES+CRC_CALC_OFFSET) && gmii_tx_ready)
                next_state = IDLE;
            else
                next_state = S_FCS;
        end
        
        default: next_state = IDLE;
    endcase
end

// ==================== 状态机第三段 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if(!rst_n) begin
        gmii_txd_pre <= 0;
        crc_frame_end_arp <= 0;
        crc_data_in_arp <= 0;
    end
    else begin
        case(current_state)
            IDLE: begin
                gmii_txd_pre <= 0;
                crc_frame_end_arp <= 0;
                crc_data_in_arp <= 0;
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
                    0 :begin gmii_txd_pre<=target_mac_reg[47:40];  crc_data_in_arp    <=target_mac_reg[47:40];   end
                    1 :begin gmii_txd_pre<=target_mac_reg[39:32];  crc_data_in_arp    <=target_mac_reg[39:32];   end
                    2 :begin gmii_txd_pre<=target_mac_reg[31:24];  crc_data_in_arp    <=target_mac_reg[31:24];   end
                    3 :begin gmii_txd_pre<=target_mac_reg[23:16];  crc_data_in_arp    <=target_mac_reg[23:16];   end
                    4 :begin gmii_txd_pre<=target_mac_reg[15: 8];  crc_data_in_arp    <=target_mac_reg[15: 8];   end
                    5 :begin gmii_txd_pre<=target_mac_reg[7 : 0];  crc_data_in_arp    <=target_mac_reg[7 : 0];   end

                    6 :begin gmii_txd_pre<=src_mac_reg[47:40];  crc_data_in_arp    <=src_mac_reg[47:40];   end
                    7 :begin gmii_txd_pre<=src_mac_reg[39:32];  crc_data_in_arp    <=src_mac_reg[39:32];   end
                    8 :begin gmii_txd_pre<=src_mac_reg[31:24];  crc_data_in_arp    <=src_mac_reg[31:24];   end
                    9 :begin gmii_txd_pre<=src_mac_reg[23:16];  crc_data_in_arp    <=src_mac_reg[23:16];   end
                    10:begin gmii_txd_pre<=src_mac_reg[15: 8];  crc_data_in_arp    <=src_mac_reg[15: 8];   end
                    11:begin gmii_txd_pre<=src_mac_reg[7 : 0];  crc_data_in_arp    <=src_mac_reg[7 : 0];   end
                    
                    // 以太网类型
                    12:begin gmii_txd_pre <= ETH_TYPE_ARP[15:8]; crc_data_in_arp <= ETH_TYPE_ARP[15:8]; end
                    13:begin gmii_txd_pre <= ETH_TYPE_ARP[7:0];  crc_data_in_arp <= ETH_TYPE_ARP[7:0];  end
                    default: gmii_txd_pre <= gmii_txd_pre;
                endcase
            end
            
            S_ARP_HEADER: begin
                case(byte_cnt)
                    // 硬件类型
                    0: begin gmii_txd_pre <= HW_TYPE_ETHERNET[15:8]; crc_data_in_arp <= HW_TYPE_ETHERNET[15:8]; end
                    1: begin gmii_txd_pre <= HW_TYPE_ETHERNET[7:0];  crc_data_in_arp <= HW_TYPE_ETHERNET[7:0];  end
                    
                    // 协议类型
                    2: begin gmii_txd_pre <= PROTO_TYPE_IPV4[15:8]; crc_data_in_arp <= PROTO_TYPE_IPV4[15:8]; end
                    3: begin gmii_txd_pre <= PROTO_TYPE_IPV4[7:0];  crc_data_in_arp <= PROTO_TYPE_IPV4[7:0];  end
                    
                    // 硬件地址长度
                    4: begin gmii_txd_pre <= HW_SIZE; crc_data_in_arp <= HW_SIZE; end
                    
                    // 协议地址长度
                    5: begin gmii_txd_pre <= PROTO_SIZE; crc_data_in_arp <= PROTO_SIZE; end
                    
                    // 操作码
                    6: begin 
                        gmii_txd_pre <= arp_opcode_reg[15:8];
                        crc_data_in_arp <= arp_opcode_reg[15:8] ;
                       end
                    7: begin 
                        gmii_txd_pre <= arp_opcode_reg[7:0];
                        crc_data_in_arp <= arp_opcode_reg[7:0] ;
                       end

                    // 发送方MAC地址
                    8: begin gmii_txd_pre <= src_mac_reg[47:40]; crc_data_in_arp <= src_mac_reg[47:40]; end
                    9: begin gmii_txd_pre <= src_mac_reg[39:32]; crc_data_in_arp <= src_mac_reg[39:32]; end
                    10: begin gmii_txd_pre <= src_mac_reg[31:24]; crc_data_in_arp <= src_mac_reg[31:24]; end
                    11: begin gmii_txd_pre <= src_mac_reg[23:16]; crc_data_in_arp <= src_mac_reg[23:16]; end
                    12: begin gmii_txd_pre <= src_mac_reg[15:8];  crc_data_in_arp <= src_mac_reg[15:8];  end
                    13: begin gmii_txd_pre <= src_mac_reg[7:0];   crc_data_in_arp <= src_mac_reg[7:0];   end
                    
                    // 发送方IP地址
                    14: begin gmii_txd_pre <= src_ip_reg[31:24]; crc_data_in_arp <= src_ip_reg[31:24]; end
                    15: begin gmii_txd_pre <= src_ip_reg[23:16]; crc_data_in_arp <= src_ip_reg[23:16]; end
                    16: begin gmii_txd_pre <= src_ip_reg[15:8];  crc_data_in_arp <= src_ip_reg[15:8];  end
                    17: begin gmii_txd_pre <= src_ip_reg[7:0];   crc_data_in_arp <= src_ip_reg[7:0];   end
                    
                    // 目标MAC地址
                    18: begin 
                        gmii_txd_pre <= ( arp_opcode_reg[0] ?  8'h00:target_mac_reg[47:40]);
                        crc_data_in_arp <= (  arp_opcode_reg[0] ?  8'h00:target_mac_reg[47:40]);
                    end
                    19: begin 
                        gmii_txd_pre <= ( arp_opcode_reg[0] ?8'h00 : target_mac_reg[39:32]  );
                        crc_data_in_arp <= (  arp_opcode_reg[0] ?8'h00 : target_mac_reg[39:32]  );
                    end
                    20: begin 
                        gmii_txd_pre <= ( arp_opcode_reg[0] ?8'h00 : target_mac_reg[31:24] );
                        crc_data_in_arp <= (  arp_opcode_reg[0] ?8'h00 : target_mac_reg[31:24] );
                    end
                    21: begin 
                        gmii_txd_pre <= ( arp_opcode_reg[0] ?8'h00 : target_mac_reg[23:16]);
                        crc_data_in_arp <= (  arp_opcode_reg[0] ?8'h00 : target_mac_reg[23:16]);
                    end
                    22: begin 
                        gmii_txd_pre <= ( arp_opcode_reg[0]  ?8'h00 :  target_mac_reg[15:8] );
                        crc_data_in_arp <= (  arp_opcode_reg[0]  ?8'h00 :  target_mac_reg[15:8] );
                    end
                    23: begin 
                        gmii_txd_pre <= ( arp_opcode_reg[0]  ?8'h00 :  target_mac_reg[7:0] );
                        crc_data_in_arp <= (  arp_opcode_reg[0]  ?8'h00 :  target_mac_reg[7:0] );
                    end
                    
                    // 目标IP地址
                    24: begin gmii_txd_pre <= target_ip_reg[31:24]; crc_data_in_arp <= target_ip_reg[31:24]; end
                    25: begin gmii_txd_pre <= target_ip_reg[23:16]; crc_data_in_arp <= target_ip_reg[23:16]; end
                    26: begin gmii_txd_pre <= target_ip_reg[15:8];  crc_data_in_arp <= target_ip_reg[15:8];  end
                    27: begin gmii_txd_pre <= target_ip_reg[7:0];   crc_data_in_arp <= target_ip_reg[7:0];

                    end
                    default: gmii_txd_pre <= gmii_txd_pre;
                endcase
            end
            
            S_PAYLAOD: begin
                if(byte_cnt<=(ARP_PAYLOAD_BYTES-1))begin
                    gmii_txd_pre <=8'h00;
                    crc_data_in_arp <= 0;
                end

                if(byte_cnt==(ARP_PAYLOAD_BYTES-1))
                    crc_frame_end_arp <= 1;  // ARP数据结束
            end
            
            S_FCS: begin
                case (byte_cnt)
                    0: begin
                        crc_frame_end_arp<=0;  
                        gmii_txd_pre <= 0;
                    end 
                    //为了防止产生mulit_driver，其他crc_result_arp在上面产生！
                    default: begin
                        crc_frame_end_arp<=0;                   
                    end
                endcase   
            end
            
            default: begin
                gmii_txd_pre <= gmii_txd_pre;
                crc_frame_end_arp <= 0;
                crc_data_in_arp <= 0;
            end
        endcase
    end
end

endmodule
