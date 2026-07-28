
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/07 19:00:45
// Design Name: 
// Module Name: ethernet_tx_top_tb
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


module ethernet_tx_top_tb();
//===============================================================================================================   
//本地参数定义
    // ==================== 全局信号 ====================
    reg                               clk_125m                   ;
    reg                               clk_50m                    ;  // 新增：50MHz写时钟
    reg                               rst_n                      ;

    // ==================== arp发送所需信号 ====================
    reg                               arp_gmii_tx_ready          ;//背压信号
        // 来自 ARP cache（Request）
    wire                               arp_request_start_pulse    ;
    reg                [  31: 0]      arp_tx_request_ip          ;
    reg                [  47: 0]      arp_tx_request_dst_mac     ;
        //来自 ARP Cache（Reply）
    wire                               arp_reply_start_pulse      ;
    reg                [  47: 0]      arp_target_mac             ;
    reg                [  31: 0]      arp_target_ip              ;
        //状态接口 
    wire                              arp_tx_busy                ;
    wire                              arp_tx_done                ;
    // ==================== icmp发送所需信号 ====================  
    wire                               icmp_start_pulse_primitive ;
    reg                               icmp_gmii_tx_ready         ;
    reg                [  15: 0]      icmp_reply_checksum        ;
    reg                               icmp_reply_checksum_valid  ;
    reg                [  15: 0]      icmp_identifier            ;// 标识符
    reg                [  15: 0]      icmp_sequence              ;// 序列号
        //ICMP PAYLOAD数据接口
    wire                              rd_en_icmp_fifo            ;
    wire               [   7: 0]      dout_icmp_fifo             ;
    wire                              empty_icmp_fifo            ;
    reg                [  10: 0]      icmp_payload_count         ;
        //状态接口 
    wire                              icmp_tx_busy               ;
    wire                              icmp_tx_done               ;
    // ===================  UDP发送所需信号 ====================
    wire                               udp_start_pulse_primitive  ;
    reg                               udp_gmii_tx_ready          ;//背压信号

    wire                              rd_en_udp_tx_fifo          ;
    wire               [   7: 0]      dout_udp_tx_fifo           ;
    wire                              empty_udp_tx_fifo          ;
    wire                              rd_rst_busy_udp_tx_fifo    ;
    // UDP payload字节数
    reg                [  10: 0]      udp_payload_count          ;
        //状态接口 
    wire                              udp_tx_busy                ;
    wire                              udp_tx_done                ;
    // ===================  PC的IP和MAC ====================
    reg                [  47: 0]      pc_mac                     ;
    reg                [  31: 0]      pc_ip                      ;

    // ==================== icmp payload fifo ====================  
    reg                                 srst_icmp_fifo             ;
    reg                  [   7: 0]      din_icmp_fifo              ;
    reg                                 wr_en_icmp_fifo            ;
    wire                                full_icmp_fifo             ;

    // ==================== udp payload fifo ==================== 
    reg                                 rst_udp_fifo               ;
    reg                  [   7: 0]      din_udp_fifo               ;
    reg                                 wr_en_udp_fifo             ;
    wire                                full_udp_fifo              ;
    wire                                wr_rst_busy_udp_fifo       ;
    //FIFO计数信号   用于UDP自动触发判断
    wire               [  10: 0]      wr_data_count_udp_tx_fifo  ;  // 写侧计数（50M域）
    wire               [  10: 0]      rd_data_count_udp_tx_fifo  ;  // 读侧计数（125M域）

//发送仲裁模块所需


    // ==================== arp发送所需信号 ====================    
    reg                               arp_tx_reply_req           ;  // 电平req，外部保持到start产生后下一拍
    reg                               arp_tx_request_req         ;  // 电平req，外部保持到start产生后下一拍

    // ==================== icmp发送所需信号 ====================  
    reg                               icmp_tx_reply_req          ;  // 电平req，外部保持到start产生后下一拍

    // ===================  UDP发送所需信号 ====================   
    reg                               udp_tx_req                 ;  // 电平req，外部保持到start产生后下一拍


//===============================================================================================================   
//本地参数初始化

initial begin

                // ==================== 全局信号 ====================
            clk_125m              =  0                   ;
            clk_50m               =  0                   ;  // 初始化50MHz时钟
            rst_n                 =  0                   ;

                // ==================== arp发送所需信号 ====================
            arp_gmii_tx_ready     =  1                   ;//背压信号
                    // 来自 ARP cache（Request）

            arp_tx_request_ip     = 32'hC0A8_0003        ;
            arp_tx_request_dst_mac= 48'hFFFF_FFFF_FFFF   ;
                    //来自 ARP Cache（Reply）

            arp_target_mac        = 48'h00E2_6969_EC7D   ;
            arp_target_ip         = 32'hC0A8_0003        ;

                // ==================== icmp发送所需信号 ====================  

            icmp_gmii_tx_ready    =  1                   ;
            icmp_reply_checksum   = 16'hb5ae                   ;
            icmp_reply_checksum_valid=  0                   ;
            icmp_identifier       =  16'h0400                 ;// 标识符
            icmp_sequence         =  16'h0500                  ;// 序列号
                    //ICMP PAYLOAD数据接口

            icmp_payload_count    =  11'd32         ;     
                // ===================  UDP发送所需信号 ====================
            udp_gmii_tx_ready     =  1                   ;//背压信号
                // UDP payload字节数
            udp_payload_count     = 11'd32                   ;

                // ===================  PC的IP和MAC ====================
            pc_mac                =   48'h00E2_6969_EC7D   ;
            pc_ip                 =   32'hC0A8_0003        ;

    // ==================== icmp payload fifo ====================  
            srst_icmp_fifo        =  0                   ;
            din_icmp_fifo         =  0                   ;
            wr_en_icmp_fifo       =  0                   ;

    // ==================== udp payload fifo ====================  
            rst_udp_fifo          =  1                   ;  // 初始复位
            din_udp_fifo          =  0                   ;
            wr_en_udp_fifo        =  0                   ;

end


//===============================================================================================================   
//仿真主逻辑
always #10 clk_125m = ~clk_125m;  // 125MHz: 周期20ns，半周期10ns
always #20 clk_50m  = ~clk_50m;   // 50MHz: 周期40ns，半周期20ns

//=====================================================
// ICMP FIFO循环写入逻辑（125M域，永不停止）
reg [7:0] fifo_wr_data;
initial begin

    fifo_wr_data     = 8'd5;
    srst_icmp_fifo   = 0;
    din_icmp_fifo    = 0;
    wr_en_icmp_fifo  = 0;

    @(posedge rst_n);
    #100;

    forever begin
        @(posedge clk_125m);
        if (!full_icmp_fifo) begin
            // 写5-36循环数据
            din_icmp_fifo   = fifo_wr_data;
            wr_en_icmp_fifo = 1'b1;
            if (fifo_wr_data == 8'd36)
                fifo_wr_data = 8'd5;
            else
                fifo_wr_data = fifo_wr_data + 1'b1;
        end else begin
            // FIFO满了就停写，等读侧腾出空间后自动恢复
            wr_en_icmp_fifo = 1'b0;
        end
        @(posedge clk_125m);
        wr_en_icmp_fifo = 1'b0;
    end
end


//=====================================================
// UDP FIFO循环写入逻辑（50M域，永不停止）
reg [7:0] udp_fifo_wr_data;
initial begin
    udp_fifo_wr_data   = 8'd5;
    rst_udp_fifo       = 1'b1;
    din_udp_fifo       = 8'd0;
    wr_en_udp_fifo     = 1'b0;
    
    @(posedge rst_n);
    #100;
    rst_udp_fifo = 1'b0;
    @(negedge wr_rst_busy_udp_fifo);
    #100;
    

    forever begin
        @(posedge clk_50m);
        if (!full_udp_fifo) begin
            // 写5-36循环数据
            din_udp_fifo   = udp_fifo_wr_data;
            wr_en_udp_fifo = 1'b1;
            if (udp_fifo_wr_data == 8'd36)
                udp_fifo_wr_data = 8'd5;
            else
                udp_fifo_wr_data = udp_fifo_wr_data + 1'b1;
        end else begin
            // FIFO满了就停写，等读侧腾出空间后自动恢复
            wr_en_udp_fifo = 1'b0;
        end
        @(posedge clk_50m);
        wr_en_udp_fifo = 1'b0;
    end
end

//=====================================================
//源端仲裁的req产生逻辑，源头是
reg arp_tx_reply_req_pulse    ;
reg arp_tx_request_req_pulse  ; 
reg icmp_frame_rx_done_valid  ; 
reg udp_tx_pulse              ;    


always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        udp_tx_pulse <= 1'b0;
    end else begin
        // 条件：1. UDP不忙 2. FIFO内有至少32字节数据 3. 当前未发起UDP请求
        if (!udp_tx_busy && (rd_data_count_udp_tx_fifo >= udp_payload_count) && !udp_tx_req) begin
            udp_tx_pulse <= 1'b1;
        end else begin
            udp_tx_pulse <= 1'b0;
        end
    end
end


//arp reply
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                arp_tx_reply_req<=0;                                           
            else if(arp_reply_start_pulse)
                arp_tx_reply_req<=0;
            else if(arp_tx_reply_req_pulse)
                arp_tx_reply_req<=1;                                       
            else                          
                arp_tx_reply_req<=arp_tx_reply_req; 
         end  
//arp request
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                arp_tx_request_req<=0;                                           
            else if(arp_request_start_pulse)
                arp_tx_request_req<=0;
            else if(arp_tx_request_req_pulse)
                arp_tx_request_req<=1;                                       
            else                          
                arp_tx_request_req<=arp_tx_request_req; 
         end  

//icmp
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                icmp_tx_reply_req<=0;                                           
            else if(icmp_start_pulse_primitive)
                icmp_tx_reply_req<=0;
            else if(icmp_frame_rx_done_valid)
                icmp_tx_reply_req<=1;                                       
            else                          
                icmp_tx_reply_req<=icmp_tx_reply_req; 
         end 
//udp
     always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                udp_tx_req<=0;                                           
            else if(udp_start_pulse_primitive)
                udp_tx_req<=0;
            else if(udp_tx_pulse)
                udp_tx_req<=1;                                       
            else                          
                udp_tx_req<=udp_tx_req; 
         end         
//=====================================================
// 发送模块主逻辑,主要就是产生这四个脉冲信号
initial begin
arp_tx_reply_req_pulse  =0  ;
arp_tx_request_req_pulse=0  ;
icmp_frame_rx_done_valid=0  ;

   #10 rst_n = 0;
    #805 rst_n = 1;
    #335;  // 等待复位完成，FIFO开始写入数据

    // 等待FIFO都写完（ICMP写32字节需640ns，UDP写32字节需1280ns，留足够余量）
    #1500;
    $display("\n====================== 阶段1：单包顺序发送测试 ======================");

    // 1. 触发ARP Reply请求
    $display("[Time %0t] 触发ARP Reply请求", $time);
    arp_tx_reply_req_pulse = 1'b1;
    @(posedge clk_125m); #2;
    arp_tx_reply_req_pulse = 1'b0;

    // 等待ARP Reply发送完成
    @(posedge arp_tx_done); #100;

    // 2. 触发ARP Request请求
    $display("[Time %0t] ARP Reply完成，触发ARP Request请求", $time);
    arp_tx_request_req_pulse = 1'b1;
    @(posedge clk_125m); #2;
    arp_tx_request_req_pulse = 1'b0;

    // 等待ARP Request发送完成
    @(posedge arp_tx_done); #100;

    // 3. 触发ICMP请求
    $display("[Time %0t] ARP Request完成，触发ICMP请求", $time);
    icmp_frame_rx_done_valid = 1'b1;
    @(posedge clk_125m); #2;
    icmp_frame_rx_done_valid = 1'b0;

    // 等待ICMP发送完成，此时UDP FIFO早已写满，会自动触发UDP请求
    @(posedge icmp_tx_done); #100;
    $display("[Time %0t] ICMP完成，等待UDP自动触发发送", $time);

    // 等待UDP发送完成
    @(posedge udp_tx_done); #100;
    $display("\n====================== 阶段2：优先级仲裁测试 ======================");

    // 4. 同时触发三个请求，验证优先级：ARP Request > ICMP > UDP
    // 先等上一次UDP请求拉低
    @(negedge udp_tx_req); #20;
    $display("[Time %0t] 同时拉高ARP Request、ICMP、UDP请求，验证优先级", $time);
    arp_tx_request_req_pulse = 1'b1;
    icmp_frame_rx_done_valid = 1'b1;
    // UDP请求由udp_tx_pulse自动拉高，无需手动触发

    // 等待三个包全部发送完成
    repeat(3) @(posedge clk_125m); // 简单等待，实际可通过done信号判断
    #2000;

    $display("\n====================== 所有测试完成，仿真结束 ======================");
    $stop;
end




//===============================================================================================================
//调用底层模块

ethernet_tx_scheduler u_ethernet_tx_scheduler(
// ==================== 全局信号 ====================
    .clk_125m                           (clk_125m                  ), // (input)
    .rst_n                              (rst_n                     ), // (input)
// ==================== arp发送所需信号 ====================
    .arp_tx_reply_req                   (arp_tx_reply_req          ), // (input)
    .arp_tx_request_req                 (arp_tx_request_req        ), // (input)
    .arp_tx_busy                        (arp_tx_busy               ), // (input)
    .arp_tx_done                        (arp_tx_done               ), // (input)
// ==================== icmp发送所需信号 ====================
    .icmp_tx_reply_req                  (icmp_tx_reply_req         ), // (input)
    .icmp_tx_busy                       (icmp_tx_busy              ), // (input)
    .icmp_tx_done                       (icmp_tx_done              ), // (input)
// ===================  UDP发送所需信号 ====================
    .udp_tx_req                         (udp_tx_req                ), // (input)
    .udp_tx_busy                        (udp_tx_busy               ), // (input)
    .udp_tx_done                        (udp_tx_done               ), // (input)
// ===================  最终仲裁逻辑信号输出 ====================
    .arp_request_start_pulse            (arp_request_start_pulse   ), // (output)
    .arp_reply_start_pulse              (arp_reply_start_pulse     ), // (output)
    .icmp_start_pulse_primitive         (icmp_start_pulse_primitive), // (output)
    .udp_start_pulse_primitive          (udp_start_pulse_primitive ) // (output)

);



//===========================
//配套的icmp_payload_fifo,FWFT
icmp_payload_fifo icmp_payload_fifo_TEST (
    .clk                                (clk_125m                  ),// input wire clk
    .srst                               (srst_icmp_fifo            ),// input wire srst
    .din                                (din_icmp_fifo             ),// input wire [7 : 0] din
    .wr_en                              (wr_en_icmp_fifo           ),// input wire wr_en
    .full                               (full_icmp_fifo            ),// output wire full

    .dout                               (dout_icmp_fifo            ),// output wire [7 : 0] dout
    .rd_en                              (rd_en_icmp_fifo           ),// input wire rd_en
    .empty                              (empty_icmp_fifo           ),// output wire empty
    .data_count                         (                          ) // output wire [9 : 0] data_count   //调试用，实际不使用
);


//===========================
//配套的udp_payload_fifo,FWFT,异步fifo
udp_payload_fifo udp_payload_fifo_test (
    .rst                                (rst_udp_fifo              ),// input wire rst
    .wr_clk                             (clk_50m                   ),// input wire wr_clk - 修改为50MHz时钟
    .din                                (din_udp_fifo              ),// input wire [7 : 0] din
    .wr_en                              (wr_en_udp_fifo            ),// input wire wr_en
    .full                               (full_udp_fifo             ),// output wire full
    .wr_data_count                      (wr_data_count_udp_tx_fifo),// output wire [10 : 0] wr_data_count
    .wr_rst_busy                        (wr_rst_busy_udp_fifo      ),// output wire wr_rst_busy

    .rd_clk                             (clk_125m                  ),// input wire rd_clk - 保持125MHz
    .dout                               (dout_udp_tx_fifo          ),// output wire [7 : 0] dout
    .rd_en                              (rd_en_udp_tx_fifo         ),// input wire rd_en
    .empty                              (empty_udp_tx_fifo         ),// output wire empty
    .rd_data_count                      (rd_data_count_udp_tx_fifo ),// output wire [10 : 0] rd_data_count
    .rd_rst_busy                        (rd_rst_busy_udp_tx_fifo   ) // output wire rd_rst_busy
);

//////////////////////////////////////////    发送模块       //////////////////////////////////////////////
ethernet_tx_top#(
    .PC_MAC                             (48'h00E2_6969_EC7D        ),
    .PC_IP                              (32'hC0A8_0003             ),
    .FPGA_MAC                           (48'h001A_2B3C_4D5E        ),
    .FPGA_IP                            (32'hC0A8_000A             ),
    .DST_PORT                           (16'd54321                 ),
    .SRC_PORT                           (16'd54322                 ),
    .PREAMBLE                           (8'h55                     ),
    .SFD                                (8'hD5                     ),
    .ETH_TYPE                           (16'h0800                  ),
    .IP_VER                             (8'h45                     ),
    .IP_SERVICE                         (8'h00                     ),
    .IP_MARK                            (16'h0                     ),
    .IP_FRAG_OFFSET                     (16'h0                     ),
    .IP_TTL                             (8'h80                     ),
    .ARP_ETH_TYPE                       (16'h0806                  ),
    .ARP_HW_TYPE_ETHERNET               (16'h0001                  ),
    .ARP_PROTO_TYPE_IPV4                (16'h0800                  ),
    .ARP_HW_SIZE                        (8'h06                     ),
    .ARP_PROTO_SIZE                     (8'h04                     ),
    .ARP_OPCODE_REQUEST                 (16'h0001                  ),
    .ARP_OPCODE_REPLY                   (16'h0002                  ),
    .ICMP_IP_PROTOCOL                   (8'h01                     ),
    .ICMP_TYPE                          (8'h00                     ),
    .ICMP_CODE                          (8'h00                     ),
    .UDP_IP_PROTOCOL                    (8'h11                     ),
    .UDP_VERC                           (16'h0                     ) 
)
 u_ethernet_tx_top(
//=========================协议重要参数配置=====================
//ARP
//ICMP
//UDP
// ==================== 全局信号 ====================
    .clk_125m                           (clk_125m                  ), // (input)
    .rst_n                              (rst_n                     ), // (input)
// ==================== arp发送所需信号 ====================
    .arp_gmii_tx_ready                  (arp_gmii_tx_ready         ), // (input)// 背压信号
// 来自 ARP cache（Request）
    .arp_request_start_pulse            (arp_request_start_pulse   ), // (input)
    .arp_tx_request_ip                  (arp_tx_request_ip         ), // (input)
    .arp_tx_request_dst_mac             (arp_tx_request_dst_mac    ), // (input)
//来自 ARP Cache（Reply）
    .arp_reply_start_pulse              (arp_reply_start_pulse     ), // (input)
    .arp_target_mac                     (arp_target_mac            ), // (input)
    .arp_target_ip                      (arp_target_ip             ), // (input)
//状态接口
    .arp_tx_busy                        (arp_tx_busy               ), // (output)
    .arp_tx_done                        (arp_tx_done               ), // (output)
// ==================== icmp发送所需信号 ====================
    .icmp_start_pulse_primitive         (icmp_start_pulse_primitive), // (input)
    .icmp_gmii_tx_ready                 (icmp_gmii_tx_ready        ), // (input)
    .icmp_reply_checksum                (icmp_reply_checksum       ), // (input)
    .icmp_reply_checksum_valid          (icmp_reply_checksum_valid ), // (input)
    .icmp_identifier                    (icmp_identifier           ), // (input)// 标识符
    .icmp_sequence                      (icmp_sequence             ), // (input)// 序列号
//ICMP PAYLOAD数据接口
    .rd_en_icmp_fifo                    (rd_en_icmp_fifo           ), // (output)
    .dout_icmp_fifo                     (dout_icmp_fifo            ), // (input)
    .empty_icmp_fifo                    (empty_icmp_fifo           ), // (input)
    .icmp_payload_count                 (icmp_payload_count        ), // (input)
//状态接口
    .icmp_tx_busy                       (icmp_tx_busy              ), // (output)
    .icmp_tx_done                       (icmp_tx_done              ), // (output)
// ===================  UDP发送所需信号 ====================
    .udp_start_pulse_primitive          (udp_start_pulse_primitive ), // (input)
    .udp_gmii_tx_ready                  (udp_gmii_tx_ready         ), // (input)// 背压信号
    .rd_en_udp_tx_fifo                  (rd_en_udp_tx_fifo         ), // (output)
    .dout_udp_tx_fifo                   (dout_udp_tx_fifo          ), // (input)
    .empty_udp_tx_fifo                  (empty_udp_tx_fifo         ), // (input)
    .rd_rst_busy_udp_tx_fifo            (rd_rst_busy_udp_tx_fifo   ), // (input)
// UDP payload字节数
    .udp_payload_count                  (udp_payload_count         ), // (input)
//状态接口
    .udp_tx_busy                        (udp_tx_busy               ), // (output)
    .udp_tx_done                        (udp_tx_done               ), // (output)
// ===================  PC的IP和MAC ====================
    .pc_mac                             (pc_mac                    ), // (input)
    .pc_ip                              (pc_ip                     ) // (input)
);

endmodule

