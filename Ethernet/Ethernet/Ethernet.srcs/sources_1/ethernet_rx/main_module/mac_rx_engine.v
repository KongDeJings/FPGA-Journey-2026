`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/05/30 10:45:08
// Design Name: 
// Module Name: mac_rx_engine
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 只做MAC层该做的事
// 1. 检测前导码和SFD
// 2. 解析MAC头部
// 3. 地址过滤
// 4. CRC校验
// 5. 按以太网类型分发
// 6. 如果是UDP或ICMP,则偷看（解析到IP长度），以方便控制CRC计算
//代码中禁止出现魔数
//////////////////////////////////////////////////////////////////////////////////

module mac_rx_engine
#(
    parameter                           PREAMBLE                    = 8'h55                ,
    parameter                           SFD                         = 8'hD5                ,
    parameter                           ETH_TYPE_IPV4               = 16'h0800             ,
    parameter                           FPGA_MAC                    = 48'h020A_353C_4D5E   ,  // MAC 02-0A-35-3C-4D-5E 这是xilinx专用mac，可被wireshark识别到
    parameter                           ETH_TYPE_ARP                = 16'h0806             
    
)
(
    // ==================== 全局信号 ====================
    input                               clk_125m                   ,
    input                               rst_n                      ,
    output                              gmii_rx_dv_fall            ,
    // ==================== GMII接口 ====================
    input                [   7: 0]      gmii_rxd                   ,
    input                               gmii_rx_dv                 ,
    
    // ==================== 配置接口 ====================
    input                [  47: 0]      local_mac                  ,// 本地MAC地址
    
    // ==================== 输出到IP模块 ====================
    output               [   7: 0]      ip_rx_data                 ,
    output                              ip_rx_valid                ,
    output reg                          ip_rx_start                ,// IP包开始
    output               [  15: 0]      ip_byte_cnt                ,//handover_byte_cnt传递到下层模块，实现计数器的复用，同时对齐数据

    // ==================== 输出到ARP模块 ====================
    output               [   7: 0]      arp_rx_data                ,
    output                              arp_rx_valid               ,
    output reg                          arp_rx_start               ,// ARP包开始
    output               [  15: 0]      arp_byte_cnt               ,//handover_byte_cnt传递到下层模块，实现计数器的复用，同时对齐数据
    
    // ==================== 解析到的MAC输出 ====================
    output reg           [  47: 0]      ip_src_mac                 ,// 源MAC
    output reg           [  47: 0]      ip_dst_mac                 ,// 目的MAC

    // ==================== 对外输出的状态信息 ====================   

    output reg                          packet_is_ip               ,
    output reg                          packet_is_arp              ,
    output reg                          frame_rx_done              ,
    output reg                          crc_match                  ,
    output reg                          mac_rx_error               
);

// ==================== 状态机定义 ====================
reg [5:0] current_state, next_state;  // 改为4位
localparam  ST_IDLE        = 6'b000_001,
            ST_PREAMBLE    = 6'b000_010,  // 前导码检测
            ST_MAC_HDR     = 6'b000_100,  // 解析MAC头部
            ST_HANDOVER    = 6'b001_000,  // 转发数据,偷看ip长度（0800）或等待到结束（0806）
            ST_CHECK_CRC   = 6'b010_000,  // 检查CRC
            ST_SKIP_FRAME  = 6'b100_000;  // 跳过不需要的帧

// ==================== 本地参数 ====================
localparam  PREAMBLE_BYTES           = 8     ,
            MAC_HEADER_BYTES         = 14    ,
            IP_HEADER_BYTES          = 20    ,
            UDP_HEADER_BYTES         = 8     ,
            FCS_BYTES                = 4     ,
            ARP_LENGTH               = 52-FCS_BYTES    ,//ARP包长度在用网线连接FPGA和电脑时是固定值
            MIN_FRAME_SIZE           =IP_HEADER_BYTES ,       // 最小帧长度
            MAX_FRAME_SIZE           = 1518  ;       // 最大帧长度
            

// ==================== 内部信号 ====================
reg [47:0] dst_mac_reg      ;                // 目的MAC寄存器
reg [47:0] src_mac_reg      ;                // 源MAC寄存器
reg [15:0] eth_type         ;                // 以太网类型

reg [15:0] ip_length        ;                //这个值的初值较为特殊，先设置为10（实际只需要4就能读到ip_length了）

 reg                          eth_type_error             ;
 reg                          mac_filter_match           ;
 reg                          frame_too_short            ;// 帧过短标志
 reg                          frame_too_long             ; // 帧过长标志 
  
// =======================================================================
//产生gmii_rx_dv的上升沿脉冲和下降沿脉冲，并将下降沿脉冲延后3拍，以适应检测延迟与数据实时性的矛盾
wire gmii_rx_dv_pluse;
reg [1:0]gmii_rx_dv_recv;
reg[2:0]gmii_rx_dv_fall_r;//下降沿脉冲延迟寄存器，延迟3拍
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                                                             
               gmii_rx_dv_recv<=2'b0;                                                  
            else begin
                gmii_rx_dv_recv[0]<=gmii_rx_dv;
                gmii_rx_dv_recv[1]<=gmii_rx_dv_recv[0];
            end                                                 
        end                                          
assign gmii_rx_dv_pluse=(gmii_rx_dv_recv==2'b01);
assign gmii_rx_dv_fall=(gmii_rx_dv_recv==2'b10);

    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                gmii_rx_dv_fall_r<=0;                                           
            else begin   //取[2]作为一帧结束的信号
                gmii_rx_dv_fall_r[0]<=gmii_rx_dv_fall;
                gmii_rx_dv_fall_r[1]<=gmii_rx_dv_fall_r[0];
                gmii_rx_dv_fall_r[2]<=gmii_rx_dv_fall_r[1];                
            end                                     
        end  

// =======================================================================
//做错误统计，产生mac_rx_error,做最终裁决

    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                                                             
               mac_rx_error<=0;                                                  
            else if(gmii_rx_dv_fall) begin
                if(packet_is_ip&&(frame_too_long||frame_too_short))
                     mac_rx_error<=1;
                else if(~mac_filter_match&&packet_is_ip)
                     mac_rx_error<=1;
                else if(eth_type_error)
                     mac_rx_error<=1;
            end 
            else
                mac_rx_error<=0;                                                   
        end  

//=================================================
//添加一级流水，将gmii_rxd延后一拍,解决CRC计算延迟与数据实时性的矛盾
//CRC计算用gmii_rxd,前导码检测用gmii_rxd，其他所有模块用gmii_rxd_r
    reg                                 gmii_rx_dv_r               ;
    reg                  [   7: 0]      gmii_rxd_r                 ;

always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        gmii_rx_dv_r <= 0;
        gmii_rxd_r   <= 8'h0;
    end else begin
        gmii_rxd_r <= gmii_rxd;
        gmii_rx_dv_r <= gmii_rx_dv;
    end
end

assign ip_rx_data = gmii_rxd_r;
assign ip_rx_valid=gmii_rx_dv_r;

assign arp_rx_data  = gmii_rxd_r;
assign arp_rx_valid =gmii_rx_dv_r;

//=================================================
//前导码检测
//只检测连续两拍0x55+0xD5，之前的检测太严格，容易收不到包（7个55加1个d5）
   wire                                 sfd_detected               ;//已经检测到SFD!
    reg                                 sfd_check_en               ;//前导码检测使能，避免在不该检测的时候检测到"前导码"
    reg                  [  15: 0]      preamble_detect            ;//前导码检测移位寄存器
//    reg                                 sfd_error                ;//前导码检测错误，不需要，未检测到等gmii_rx_dv=0就回去了

always @(posedge clk_125m or negedge rst_n) begin    
    if (!rst_n)
        sfd_check_en<=0;
    else if(sfd_detected)
        sfd_check_en<=0;
    else if(gmii_rx_dv_pluse)
        sfd_check_en<=1;
    else    
        sfd_check_en<=sfd_check_en;
end

always @(posedge clk_125m or negedge rst_n) begin    
    if (!rst_n) 
        preamble_detect<=0;
    else if(gmii_rx_dv&&sfd_check_en)
        preamble_detect <= {preamble_detect[7:0], gmii_rxd};
    else
        preamble_detect<=0;

end
assign sfd_detected = (preamble_detect[15:8] == 8'h55) &&
                    (preamble_detect[7:0] == 8'hD5);

//=================================================    
//产生byte_cnt字节计数器，用作操作基础
//第一波只计数到MAC_header结束，计数14
//第二波在ST_CHECK_CRC计数，计数4
    reg  [   3: 0] byte_cnt   ;

    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                byte_cnt<=0;                                              
            else if(gmii_rx_dv)begin 
                    if((current_state == ST_MAC_HDR))begin
                            if(byte_cnt==MAC_HEADER_BYTES-1) 
                                byte_cnt<=0;
                            else
                                byte_cnt<=byte_cnt+1;
                            end
                    else if(current_state == ST_CHECK_CRC)begin
                    if(byte_cnt==(FCS_BYTES-1) )
                        byte_cnt<=0;
                    else
                        byte_cnt<=byte_cnt+1;
                    end
                    else
                        byte_cnt<=0;
            end                                                          
            else
                byte_cnt<=0;                                     
        end  

//=================================================    
//产生 handover_byte_cnt字节计数器，
//在ST_HANDOVER交接状态时开始计数，一直计数到FCS产生
//若为0800，计数值要靠偷看得到（IP_LENGTH）
//若为0806，计数值固定(ARP_LENGTH)
    reg  [ 15: 0] handover_byte_cnt   ;
    
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                handover_byte_cnt<=0;                                              
            else if(gmii_rx_dv)begin 
                    if((current_state == ST_HANDOVER)&&packet_is_ip)begin  //当包为IP时，计数值到ip_length（通过偷看得到）
                            if(handover_byte_cnt==ip_length-1) 
                                handover_byte_cnt<=0;
                            else
                                handover_byte_cnt<=handover_byte_cnt+1;
                            end
                    else if((current_state == ST_HANDOVER)&&packet_is_arp)begin  //当包为ARP包时，长度固定
                    if(handover_byte_cnt==(ARP_LENGTH-1) )
                        handover_byte_cnt<=0;
                    else
                        handover_byte_cnt<=handover_byte_cnt+1;
                    end
                    else
                        handover_byte_cnt<=0;
            end                                                          
            else
                handover_byte_cnt<=0;                                     
        end  

assign ip_byte_cnt = handover_byte_cnt;
assign arp_byte_cnt = handover_byte_cnt;

//=================================================
//连接CRC计算
/*
空闲状态 → en=0 → CRC 寄存器保持不变
前导码(7字节) + SFD(1字节) → en=0 （不计算CRC）
目的MAC(6) + 源MAC(6) + 类型(2) + 数据(...) → en=1 （计算CRC）
CRC字段(4) → en=0 （不计算，这个位置放结果）
帧结束 → 输出最终的 CRC 结果
*/
    wire                 [  31: 0]      calc_crc                   ;//计算得到的CRC
    reg                  [  31: 0]      recv_crc                   ;//接受到的CRC

    reg                                 crc_en                     ;
    reg                                 crc_frame_end              ;
    reg                  [   7: 0]      crc_data_in                ;
    reg                                 crc_data_valid             ;
    wire                                crc_valid                  ;

eth_crc32_parallel rx_eth_crc32_parallel(
    .clk                                (clk_125m                  ),
    .rst_n                              (rst_n                     ),
    .crc_en                             (crc_en                    ),// 帧有效期间为1
    .frame_end                          (crc_frame_end             ),// 最后一个数据字节时为1
    .data_in                            (crc_data_in               ),// MSB-first输入
    .data_valid                         (crc_data_valid            ),
    .crc_out                            (calc_crc                  ),
    .crc_valid                          (crc_valid                 )// CRC结果有效
);  
//=================================================
//产生crc_data_valid和crc_data_in
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n) begin
                crc_data_in   <=0; 
                crc_data_valid<=0; 
            end                              
            else if(!gmii_rx_dv)begin
                crc_data_in   <=crc_data_in; 
                crc_data_valid<=0;
            end
            else if((current_state == ST_HANDOVER)&&
                        ((handover_byte_cnt==ip_length-1)&&packet_is_ip)||
                        ((handover_byte_cnt==(ARP_LENGTH-3))&&packet_is_arp)                      
                                                                )begin//在ST_HANDOVER的最后一个数时，拉低crc_data_valid
                crc_data_in   <=crc_data_in; 
                crc_data_valid<=0;
            end

            else if(sfd_detected||
                        (current_state ==ST_MAC_HDR)||
                           (current_state ==ST_HANDOVER)
                                                                ) begin
                crc_data_in   <=gmii_rxd; 
                crc_data_valid<=1;
            end                                                                                   
        end 
//=================================================
//产生crc_en
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                crc_en<=0;
            else if(!gmii_rx_dv)
                crc_en<=0;
            else if((current_state == ST_HANDOVER)&&
                        ((handover_byte_cnt==ip_length-1)&&packet_is_ip)||
                        ((handover_byte_cnt==(ARP_LENGTH-3))&&packet_is_arp)                      
                                                                )//在ST_HANDOVER的最后一个数时，拉低crc_en
                crc_en<=0;
            else if(sfd_detected)                                
                crc_en<=1;                                     
            else 
                crc_en<=crc_en;                                    
        end                                          
//=================================================
//产生crc_frame_end
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                crc_frame_end<=0;
            else if((current_state == ST_HANDOVER)&&
                        ((handover_byte_cnt==ip_length-2)&&packet_is_ip)||
                        ((handover_byte_cnt==(ARP_LENGTH-4))&&packet_is_arp)                      
                                                                )//在ST_HANDOVER的倒数第2个数时，拉高crc_frame_end
                crc_frame_end<=1; 
            else
                crc_frame_end<=0;  //只拉高一个周期                        
        end   

//=================================================
//将输出的crc_valid打四拍，使其与recv_crc对齐
reg[3:0]crc_valid_r;
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                crc_valid_r<=0;                                   
            else begin
                crc_valid_r[0]<=crc_valid;
                crc_valid_r[1]<=crc_valid_r[0];
                crc_valid_r[2]<=crc_valid_r[1];
                crc_valid_r[3]<=crc_valid_r[2];
            end                                                                  
        end 

//=================================================
//利用输出的crc_valid_r[3]为1的时刻，判断crc_match，产生frame_rx_done
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n) begin
                crc_match<=0;    
            end                                                                   
            else if(crc_valid_r[3]) begin
                if(recv_crc==calc_crc)begin
                    crc_match<=1; 
                end
                else begin
                crc_match<=0;    
            end 
            end
            else begin
                crc_match<=0;    
            end                                                           
        end     

    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n) 
                frame_rx_done<=0;                                 
            else if(gmii_rx_dv_fall) 
                    frame_rx_done<=1;
                else 
                frame_rx_done<=0;
            end                                              
// ==================== 状态机第一段 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n)
        current_state <= ST_IDLE;
    else
        current_state <= next_state;
end

// ==================== 状态机第二段 ====================
always @(*) begin
    case (current_state)
        ST_IDLE: begin
            if (gmii_rx_dv)
                next_state = ST_PREAMBLE;
            else
                next_state = ST_IDLE;
        end
        
        ST_PREAMBLE: begin
            if (!gmii_rx_dv)
                next_state = ST_IDLE;
            else if (sfd_detected)
                next_state = ST_MAC_HDR;
            else
                next_state = ST_PREAMBLE;
        end
        
        ST_MAC_HDR: begin
            if (!gmii_rx_dv)
                next_state = ST_IDLE;
            else if (byte_cnt == MAC_HEADER_BYTES-1)
                next_state = ST_HANDOVER;
            else
                next_state = ST_MAC_HDR;
        end

        
        ST_HANDOVER: begin
            if (!gmii_rx_dv) begin
                next_state = ST_IDLE;
            end
            else if ((handover_byte_cnt==ip_length-1)&&packet_is_ip) begin
                next_state = ST_CHECK_CRC;
            end
            else if ((handover_byte_cnt==(ARP_LENGTH-3))&&packet_is_arp)begin
                next_state = ST_CHECK_CRC;
            end
            else if (frame_too_long||frame_too_short) begin
                // 帧过长或帧过短
                next_state = ST_SKIP_FRAME;
            end
            else begin
                next_state = ST_HANDOVER;
            end
        end
        
        ST_CHECK_CRC: begin
            if (!gmii_rx_dv) begin
                next_state = ST_IDLE;
            end
            else if (byte_cnt==(FCS_BYTES-1)) begin
                next_state = ST_IDLE;
            end
            else begin
                next_state = ST_CHECK_CRC;
            end
        end
               
        ST_SKIP_FRAME: begin
            if (!gmii_rx_dv)
                next_state = ST_IDLE;
            else
                next_state = ST_SKIP_FRAME;
        end
        
        default: next_state = ST_IDLE;
    endcase
end

// ==================== 状态机第三段 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        dst_mac_reg    <=0;
        src_mac_reg    <=0;
        eth_type       <=0;
        packet_is_ip   <=0;
        packet_is_arp  <=0;
        ip_length      <=0;
        frame_too_short<=0;
        frame_too_long <=0;
        ip_rx_start<=0;
        arp_rx_start <=0;
        recv_crc<=0;
        ip_src_mac<=0;
        ip_dst_mac<=FPGA_MAC;
        eth_type_error<=0;
        mac_filter_match<=0;
    end
    else begin
        case (current_state)
            ST_IDLE: begin
             ip_length      <=ip_length;
             frame_too_short<=0;
             frame_too_long <=0;
             ip_rx_start<=0;
             arp_rx_start <=0;
             eth_type_error<=0;
             mac_filter_match<=0;
            end
            
            ST_MAC_HDR: begin

                    // 解析MAC头部
                    case (byte_cnt)
                        0: dst_mac_reg[47:40] <= gmii_rxd_r;
                        1: dst_mac_reg[39:32] <= gmii_rxd_r;
                        2: dst_mac_reg[31:24] <= gmii_rxd_r;
                        3: dst_mac_reg[23:16] <= gmii_rxd_r;
                        4: dst_mac_reg[15:8]  <= gmii_rxd_r;
                        5: dst_mac_reg[7:0]   <= gmii_rxd_r;
                        
                        6: src_mac_reg[47:40] <= gmii_rxd_r;
                        7: src_mac_reg[39:32] <= gmii_rxd_r;
                        8: src_mac_reg[31:24] <= gmii_rxd_r;
                        9: src_mac_reg[23:16] <= gmii_rxd_r;
                        10: src_mac_reg[15:8] <= gmii_rxd_r;
                        11:begin src_mac_reg[7:0]  <= gmii_rxd_r; 
                           eth_type[15:8] <= gmii_rxd;     end
                        12:begin eth_type[7:0]  <= gmii_rxd;         //此处将以太网类型提前提出，方便下一拍给出判断！
                                 ip_rx_start<=1;                     //提前给出开始，先让下一级流水的状态机跳转
                                 arp_rx_start<=1;                    //跳完后再判断（根据packet_is_xx）
                        end
                        13:begin
                             // 根据以太网类型设置包类型标志
                             if((eth_type != ETH_TYPE_IPV4)&&(eth_type != ETH_TYPE_ARP))
                                eth_type_error<=1;//既不是ip,也不是arp，我就判断为错误
                            else if (eth_type == ETH_TYPE_IPV4) begin
                                 packet_is_ip <= 1'b1;
                                 packet_is_arp <= 1'b0;
                                 // 保存MAC地址到IP输出
                                 ip_src_mac <= src_mac_reg;
                                 ip_dst_mac <= dst_mac_reg;
                             end
                             else if (eth_type == ETH_TYPE_ARP) begin
                                 packet_is_ip <= 1'b0;
                                 packet_is_arp <= 1'b1;
                                 // 保存MAC地址到ARP输出
                             end
                             else 
                                eth_type_error<=0;
                        end 
                    endcase
                end

            
            ST_HANDOVER: begin
                 ip_rx_start<=0;  
                 arp_rx_start<=0; 

               if (gmii_rx_dv_r) begin
                    // 解析IP头部关键字段
                    case (handover_byte_cnt)  // IP头部内的偏移
                        2: ip_length[15:8] <= gmii_rxd_r;  // 总长度高位
                        3: ip_length[7:0] <= gmii_rxd_r;   // 总长度低位
                        4: begin
                            if(eth_type == ETH_TYPE_IPV4)begin
                            if(ip_length>MAX_FRAME_SIZE)begin
                                frame_too_long<=1;
                                frame_too_short<=0;
                            end
                            else if(ip_length<MIN_FRAME_SIZE)begin
                                frame_too_long<=0;
                                frame_too_short<=1;
                            end
                             if(ip_dst_mac==local_mac)
                                    mac_filter_match<=1;
                            end
                        end
                        default:begin
                            ip_length<=ip_length;
                        end
                    endcase
                end
            end
            
              
            ST_CHECK_CRC: begin
                if (gmii_rx_dv_r) begin
                    // 接收FCS值
                    case (byte_cnt)
                        0: recv_crc[7:0]   <= gmii_rxd_r;
                        1: recv_crc[15:8]  <= gmii_rxd_r;
                        2: recv_crc[23:16] <= gmii_rxd_r;
                        3: recv_crc[31:24] <= gmii_rxd_r;

                    endcase
                end

            end
            
            ST_SKIP_FRAME: begin
                //什么都不做
            end
            ST_PREAMBLE:begin
                //什么都不做                
            end
            default: begin

            end           
        endcase
    end
end

endmodule