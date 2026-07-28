`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/07 10:13:26
                //2026/05/28    修复crc_en_udp拉低时间滞后导致的不能连续crc校验问题（连续发UDP包）
// Design Name: 
// Module Name: udp_tx_engine
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: UDP发送模块，负责根据输入的协议参数和数据，从FIFO读取数据并通过GMII接口发送UDP报文
// 
// 代码禁止魔数出现！
//////////////////////////////////////////////////////////////////////////////////
module udp_tx_engine
#(
    parameter                           PREAMBLE                    = 8'h55                ,//前导码
    parameter                           SFD                         = 8'hD5                ,//字节帧起始
    parameter                           ETH_TYPE                    = 16'h0800             ,//类型、长度域，08000代表IPV4
    parameter                           IP_VER                      = 8'h45                ,//版本+首部长度
    parameter                           IP_SERVICE                  = 8'h0                 ,//服务类型
    parameter                           IP_MARK                     = 16'h0                ,//标识
    parameter                           IP_FRAG_OFFSET              = 16'h0                ,//标志+片偏移
    parameter                           IP_TTL                      = 8'h80                 ,//TTL生存时间
    parameter                           IP_PROTOCOL                 = 8'h11                ,//上层协议，UDP固定17
    parameter                           UDP_VERC                    = 16'h0                 //UDP校验和，不做校验，空置为0
)

 (
    // ==================== 全局信号 ====================
    input                               clk_125m                   ,// 主时钟 (125MHz, GMII时钟域)
    input                               rst_n                      ,// 异步低有效复位，同步化后使用
    
    // ==================== 控制接口 ====================
    input                               tx_start                   ,// 脉冲信号，启动一次UDP发送
    output reg                          tx_done                    ,// 脉冲信号，一次发送完成
    
    // ==================== 协议参数接口 ====================
    // 注意：这些参数在tx_start有效时被锁存，发送过程中保持不变
    input                [  47: 0]      dst_mac                    ,// 目的MAC地址
    input                [  47: 0]      src_mac                    ,// 源MAC地址
    input                [  31: 0]      dst_ip                     ,// 目的IP地址
    input                [  31: 0]      src_ip                     ,// 源IP地址
    input                [  15: 0]      dst_port                   ,// 目的UDP端口
    input                [  15: 0]      src_port                   ,// 源UDP端口
    input                [  15: 0]      data_length                ,// 注意，这里指的是纯数据长度，不含IP头和UDP头
    input                [  15: 0]      ip_checksum                ,// IP头校验和(提前计算好的)
    
    // ==================== 数据源接口(FIFO读侧) ====================
    // 使用异步FIFO，读侧时钟为clk_125m，FIFO必需为FWFT!
    input                [   7: 0]      fifo_data                  ,// FIFO读数据
    input                               fifo_empty                 ,// FIFO空标志(关键背压信号)
    output reg                          fifo_rd_en                 ,// FIFO读使能
    input                               rd_rst_busy_udp_tx_fifo    ,
    
    // ==================== 物理层接口(GMII) ====================
    output reg           [   7: 0]      gmii_txd                   ,// GMII发送数据
    output reg                          gmii_tx_en                 ,// GMII发送使能,高电平有效信号
    input                               gmii_tx_ready              ,// PHY准备好接收(关键背压信号)
    // ==================== CRC 计算模块接口 ====================
    output reg                          crc_en_udp                 ,
    output reg                          crc_frame_end_udp          ,
    output reg           [   7: 0]      crc_data_in_udp            ,
    output reg                          crc_data_valid_udp         ,
    input                [  31: 0]      crc_result_udp             ,
    input                               crc_valid_udp               
);



// ==================== 参数定义 ====================
reg [6:0]   current_state, next_state;

localparam  IDLE           = 7'b000_0001,
            S_PREAMBLE     = 7'b000_0010,    // 前导码和SFD ,8    bytes
            S_MAC_HEADER   = 7'b000_0100,    // MAC头部     ,14   bytes
            S_IP_HEADER    = 7'b000_1000,    // IP头部      ,20   bytes
            S_UDP_HEADER   = 7'b001_0000,    // UDP头部     ,8    bytes
            S_PAYLOAD      = 7'b010_0000,    // 数据        ,data_length_reg  bytes
            S_FCS          = 7'b100_0000;    // CRC校验     ,4    bytes

localparam  PREAMBLE_BYTES         = 8  ,//各个发送状态的字节数
            MAC_HEADER_BYTES       = 14 ,
            IP_HEADER_BYTES        = 20 ,
            UDP_HEADER_BYTES       = 8  ,
            CRC_CALC_OFFSET        = 2  ,//CRC校验和从计算到出数，需要两个周期
            FCS_BYTES              = 4  ;

//=================================================
//产生tx_start的上升沿脉冲
wire tx_start_pluse;
reg [1:0]tx_start_reg;
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                                                             
               tx_start_reg<=2'b0;                                                  
            else begin
                tx_start_reg[0]<=tx_start;
                tx_start_reg[1]<=tx_start_reg[0];
            end                                                 
        end                                          
assign tx_start_pluse=(tx_start_reg==2'b01);

                                         
//=================================================
//MAC地址、IP地址、端口等协议参数的锁存寄存器,在tx_start_pluse后锁存，发送过程保持不变

    reg                  [  47: 0]      dst_mac_reg                ;// 目的MAC地址
    reg                  [  47: 0]      src_mac_reg                ;// 源MAC地址
    reg                  [  31: 0]      dst_ip_reg                 ;// 目的IP地址
    reg                  [  31: 0]      src_ip_reg                 ;// 源IP地址
    reg                  [  15: 0]      dst_port_reg               ;// 目的UDP端口
    reg                  [  15: 0]      src_port_reg               ;// 源UDP端口
    reg                  [  15: 0]      data_length_reg            ;// UDP数据长度(字节数，不包括UDP头8字节)

    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n) begin
                dst_mac_reg     <= dst_mac;
                src_mac_reg     <= 0;
                dst_ip_reg      <=dst_ip;
                src_ip_reg      <= 0;
                dst_port_reg    <=dst_port ;
                src_port_reg    <=src_port ;
                data_length_reg <= 0;
            end
            else if(tx_start_pluse)begin
                dst_mac_reg     <= dst_mac      ;
                src_mac_reg     <= src_mac      ;
                dst_ip_reg      <= dst_ip       ;
                src_ip_reg      <= src_ip       ;
                dst_port_reg    <= dst_port     ;
                src_port_reg    <= src_port     ;
                data_length_reg <= data_length  ;
            end
        end

//=================================================
//产生IP总长度和UDP总长度
reg [15:0] ip_length ;
reg [15:0] udp_length;
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n) begin
                ip_length <=0;
                udp_length<=0;
            end                                                                                
            else if(tx_start_pluse)begin
                ip_length <=data_length+IP_HEADER_BYTES+UDP_HEADER_BYTES;
                udp_length<=data_length+UDP_HEADER_BYTES; 
            end                                                                       
        end                                          

//=================================================
//时间复用的全局字节计数器，每发送一个字节，计数一次
reg [7:0] byte_cnt; 

assign send_condition=(gmii_tx_ready&& (current_state!=S_PAYLOAD)&&(current_state!=IDLE));//反压条件

//always @(posedge clk_125m or negedge rst_n) begin
//    if (!rst_n) begin
//        byte_cnt <= 0;
//    end
//    else if (send_condition) begin
//        if (current_state != next_state) // 状态要切换了，下个周期从0开始
//            byte_cnt <= 0;        
//        else 
//            byte_cnt <= byte_cnt + 1;// 状态不变，继续计数
//    end
//    else    
//        byte_cnt <= byte_cnt;
//end
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n)
        byte_cnt <= 0;
    else if (current_state != next_state) 
        byte_cnt <= 0;
    else if (send_condition)
        byte_cnt <= byte_cnt + 1;
    else
        byte_cnt <= byte_cnt;
end

//=================================================
//发送UDP数据产生载荷长度计数器 ，每发送一个字节，计数一次
reg [15:0]payload_remain_cnt;

assign send_payload_condition=(gmii_tx_ready&& (current_state==S_PAYLOAD));//反压条件

always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        payload_remain_cnt <= 0;
    end
    else if (current_state != S_PAYLOAD)
        payload_remain_cnt <= 0;
    else if (send_payload_condition) begin
        if (payload_remain_cnt>=data_length_reg-1) 
            payload_remain_cnt <= 0;        
        else 
            payload_remain_cnt <= payload_remain_cnt + 1;
    end
    else    
        payload_remain_cnt <= payload_remain_cnt;
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
//产生crc_en_udp,crc_data_valid,该信号高电平有效
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n) begin
                crc_en_udp<=0;
                crc_data_valid_udp <=0;                 
            end       
             else if(crc_frame_end_udp)begin
                    crc_en_udp<=0;
                    crc_data_valid_udp <=crc_data_valid_udp;
            end                                   
            else if(tx_done)begin
                    crc_en_udp<=crc_en_udp;
                    crc_data_valid_udp <=0;
            end
            else if((current_state==S_MAC_HEADER)||
                    (current_state==S_IP_HEADER)||
                    (current_state==S_UDP_HEADER)||
                    (current_state==S_PAYLOAD)         
                                    ) begin
                    crc_en_udp<=1;
                    crc_data_valid_udp <=1;
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
                        2:  gmii_txd <= crc_result_udp[7 :0 ];   // 先发低字节
                        3:  gmii_txd <= crc_result_udp[15:8 ];
                        4:  gmii_txd <= crc_result_udp[23:16];

                        5:begin  gmii_txd <= crc_result_udp[31:24]; tx_done<=1;   end// 最后发高字节
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
    if (!rst_n) begin
        current_state <= IDLE;
    end else begin
        current_state <= next_state;
    end
end

// ==================== 第二段：下一状态逻辑 ====================
always @(*) begin
    case (current_state)
        IDLE          :begin
            if(tx_start_pluse&&gmii_tx_ready)
                next_state = S_PREAMBLE;
            else
                next_state = IDLE;
        end
        S_PREAMBLE    :begin
            if((byte_cnt==PREAMBLE_BYTES-1)&&gmii_tx_ready)
                next_state = S_MAC_HEADER;
            else
                next_state = S_PREAMBLE;
        end
        S_MAC_HEADER  :begin
            if((byte_cnt==MAC_HEADER_BYTES-1)&&gmii_tx_ready)
                next_state = S_IP_HEADER;
            else
                next_state = S_MAC_HEADER;
        end
        S_IP_HEADER   :begin
            if((byte_cnt==IP_HEADER_BYTES-1)&&gmii_tx_ready)
                next_state = S_UDP_HEADER;
            else
                next_state = S_IP_HEADER;
        end
        S_UDP_HEADER  :begin
            if ((byte_cnt == UDP_HEADER_BYTES-1)&&gmii_tx_ready)
             begin
                if (data_length_reg == 0)
                    next_state = S_FCS;  // 无数据，直接到CRC
                else
                    next_state = S_PAYLOAD;
            end
            else
                next_state = S_UDP_HEADER;
        end
        S_PAYLOAD     :begin
            if((payload_remain_cnt==data_length_reg-1)&&gmii_tx_ready)
                next_state = S_FCS;
            else
                next_state = S_PAYLOAD;            
        end
        S_FCS         :begin
            if((byte_cnt==(FCS_BYTES+CRC_CALC_OFFSET))&&gmii_tx_ready)//多计数一拍，赶上CRC32的延迟，在1->4区间发送crc_result_udp
                next_state = IDLE;
            else
                next_state = S_FCS;            
        end    
        
        default: next_state = IDLE;
    endcase
end

// ==================== 第三段：输出逻辑 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        // 复位所有寄存器            
            gmii_txd_pre<=8'b0;
            fifo_rd_en<=0;
            crc_frame_end_udp  <=0; 
            crc_data_in_udp    <=0; 

    end else begin    
        case (current_state)
        IDLE          :begin            
            gmii_txd_pre<=8'b0;
            fifo_rd_en<=0;

            crc_frame_end_udp  <=0; 
            crc_data_in_udp    <=0;             
        end
        S_PREAMBLE    :begin
            case (byte_cnt)
                0:gmii_txd_pre<=PREAMBLE;
                1:gmii_txd_pre<=PREAMBLE;
                2:gmii_txd_pre<=PREAMBLE;
                3:gmii_txd_pre<=PREAMBLE;
                4:gmii_txd_pre<=PREAMBLE;
                5:gmii_txd_pre<=PREAMBLE;
                6:gmii_txd_pre<=PREAMBLE;

                7:gmii_txd_pre<=SFD;
                default: gmii_txd_pre<=gmii_txd_pre; 
            endcase
        end
        S_MAC_HEADER  :begin  //CRC校验从此处开始计算
            case (byte_cnt)
            0 :begin gmii_txd_pre<=dst_mac_reg[47:40];  crc_data_in_udp    <=dst_mac_reg[47:40];   end
            1 :begin gmii_txd_pre<=dst_mac_reg[39:32];  crc_data_in_udp    <=dst_mac_reg[39:32];   end
            2 :begin gmii_txd_pre<=dst_mac_reg[31:24];  crc_data_in_udp    <=dst_mac_reg[31:24];   end
            3 :begin gmii_txd_pre<=dst_mac_reg[23:16];  crc_data_in_udp    <=dst_mac_reg[23:16];   end
            4 :begin gmii_txd_pre<=dst_mac_reg[15: 8];  crc_data_in_udp    <=dst_mac_reg[15: 8];   end
            5 :begin gmii_txd_pre<=dst_mac_reg[7 : 0];  crc_data_in_udp    <=dst_mac_reg[7 : 0];   end
            6 :begin gmii_txd_pre<=src_mac_reg[47:40];  crc_data_in_udp    <=src_mac_reg[47:40];   end
            7 :begin gmii_txd_pre<=src_mac_reg[39:32];  crc_data_in_udp    <=src_mac_reg[39:32];   end
            8 :begin gmii_txd_pre<=src_mac_reg[31:24];  crc_data_in_udp    <=src_mac_reg[31:24];   end
            9 :begin gmii_txd_pre<=src_mac_reg[23:16];  crc_data_in_udp    <=src_mac_reg[23:16];   end
            10:begin gmii_txd_pre<=src_mac_reg[15: 8];  crc_data_in_udp    <=src_mac_reg[15: 8];   end
            11:begin gmii_txd_pre<=src_mac_reg[7 : 0];  crc_data_in_udp    <=src_mac_reg[7 : 0];   end
            12:begin gmii_txd_pre<=   ETH_TYPE[15: 8];  crc_data_in_udp    <=   ETH_TYPE[15: 8];   end
            13:begin gmii_txd_pre<=   ETH_TYPE[7 : 0];  crc_data_in_udp    <=   ETH_TYPE[7 : 0];   end                  
            default:gmii_txd_pre<=gmii_txd_pre;
            endcase
        end
        S_IP_HEADER   :begin
            case (byte_cnt)
            0 :begin gmii_txd_pre<= IP_VER                  ;   crc_data_in_udp  <= IP_VER                  ;end
            1 :begin gmii_txd_pre<= IP_SERVICE              ;   crc_data_in_udp  <= IP_SERVICE              ;end
            2 :begin gmii_txd_pre<= ip_length[15: 8]        ;   crc_data_in_udp  <= ip_length[15: 8]        ;end
            3 :begin gmii_txd_pre<= ip_length[7 : 0]        ;   crc_data_in_udp  <= ip_length[7 : 0]        ;end
            4 :begin gmii_txd_pre<= IP_MARK[15: 8]          ;   crc_data_in_udp  <= IP_MARK[15: 8]          ;end
            5 :begin gmii_txd_pre<= IP_MARK[7 : 0]          ;   crc_data_in_udp  <= IP_MARK[7 : 0]          ;end
            6 :begin gmii_txd_pre<= IP_FRAG_OFFSET[15: 8]   ;   crc_data_in_udp  <= IP_FRAG_OFFSET[15: 8]   ;end
            7 :begin gmii_txd_pre<= IP_FRAG_OFFSET[7 : 0]   ;   crc_data_in_udp  <= IP_FRAG_OFFSET[7 : 0]   ;end
            8 :begin gmii_txd_pre<= IP_TTL                  ;   crc_data_in_udp  <= IP_TTL                  ;end
            9 :begin gmii_txd_pre<= IP_PROTOCOL             ;   crc_data_in_udp  <= IP_PROTOCOL             ;end
            10:begin gmii_txd_pre<= ip_checksum[15: 8]  ;   crc_data_in_udp  <= ip_checksum[15: 8]  ;end
            11:begin gmii_txd_pre<= ip_checksum[7 : 0]  ;   crc_data_in_udp  <= ip_checksum[7 : 0]  ;end
            12:begin gmii_txd_pre<= src_ip_reg[31:24]       ;   crc_data_in_udp  <= src_ip_reg[31:24]       ;end
            13:begin gmii_txd_pre<= src_ip_reg[23:16]       ;   crc_data_in_udp  <= src_ip_reg[23:16]       ;end
            14:begin gmii_txd_pre<= src_ip_reg[15: 8]       ;   crc_data_in_udp  <= src_ip_reg[15: 8]       ;end
            15:begin gmii_txd_pre<= src_ip_reg[7 : 0]       ;   crc_data_in_udp  <= src_ip_reg[7 : 0]       ;end
            16:begin gmii_txd_pre<= dst_ip_reg[31:24]       ;   crc_data_in_udp  <= dst_ip_reg[31:24]       ;end
            17:begin gmii_txd_pre<= dst_ip_reg[23:16]       ;   crc_data_in_udp  <= dst_ip_reg[23:16]       ;end
            18:begin gmii_txd_pre<= dst_ip_reg[15: 8]       ;   crc_data_in_udp  <= dst_ip_reg[15: 8]       ;end
            19:begin gmii_txd_pre<= dst_ip_reg[7 : 0]       ;   crc_data_in_udp  <= dst_ip_reg[7 : 0]       ;end

                default:gmii_txd_pre<=gmii_txd_pre;
            endcase            
        end
        S_UDP_HEADER  :begin
            case (byte_cnt)
                0:begin gmii_txd_pre<= src_port_reg[15: 8]      ;  crc_data_in_udp  <= src_port_reg[15: 8]  ;end
                1:begin gmii_txd_pre<= src_port_reg[7 : 0]      ;  crc_data_in_udp  <= src_port_reg[7 : 0]  ;end
                2:begin gmii_txd_pre<= dst_port_reg[15: 8]      ;  crc_data_in_udp  <= dst_port_reg[15: 8]  ;end
                3:begin gmii_txd_pre<= dst_port_reg[7 : 0]      ;  crc_data_in_udp  <= dst_port_reg[7 : 0]  ;end
                4:begin gmii_txd_pre<= udp_length[15: 8]        ;  crc_data_in_udp  <= udp_length[15: 8]    ;end
                5:begin gmii_txd_pre<= udp_length[7 : 0]        ;  crc_data_in_udp  <= udp_length[7 : 0]    ;end
                6:begin gmii_txd_pre<= UDP_VERC[15: 8]          ;  crc_data_in_udp  <= UDP_VERC[15: 8]      ;end
                7:begin gmii_txd_pre<= UDP_VERC[7 : 0]          ;  crc_data_in_udp  <= UDP_VERC[7 : 0]      ;     fifo_rd_en <= 1'b1;end
                default: gmii_txd_pre<=gmii_txd_pre;
            endcase            
        end
        S_PAYLOAD     :begin           
               gmii_txd_pre <= fifo_data;      // FWFT特性，立即可用
               crc_data_in_udp<= fifo_data;
                 if(payload_remain_cnt==data_length_reg-1)begin
                crc_frame_end_udp<=1;       
                fifo_rd_en <= 1'b0;         
               end

        end
        S_FCS         :begin
            case (byte_cnt)
                0: begin 
                    fifo_rd_en <= 1'b0;
                    crc_frame_end_udp<=0;     
                    gmii_txd_pre <= 0;end 
                default: begin
                    fifo_rd_en <= 1'b0;
                    crc_frame_end_udp<=0;                   
                end
            endcase             
        end  
        default: begin           
            gmii_txd_pre<=gmii_txd_pre;//默认保持
            fifo_rd_en<=0;

            crc_frame_end_udp  <=0; 
            crc_data_in_udp    <=0; 
        end
        endcase
    end
end
endmodule
