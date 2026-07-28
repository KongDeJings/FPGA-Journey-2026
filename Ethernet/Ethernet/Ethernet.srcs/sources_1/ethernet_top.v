`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/07/06 20:14:40
// Design Name: 
// Module Name: ethernet_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 负责桥接rx和tx,解决发送仲裁，解决udp发送使能触发，并解决phy的上电初始化问题
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 代码中禁止出现魔数
//////////////////////////////////////////////////////////////////////////////////


module ethernet_top
#(

//=========================协议重要参数配置=====================
    parameter                           ETH_CLOCK_FREQUENCY             = 125_000_000          ,  // 计数1s所需周期数(时钟频率)  

    parameter                           PC_MAC                      = 48'h00E2_6969_EC7D   ,  // MAC: 00-E2-69-69-EC-7D
    parameter                           PC_IP                       = 32'hC0A8_0003        ,  // IP: 192.168.0.3
//    parameter                           FPGA_MAC                    = 48'h001A_2B3C_4D5E   ,  // MAC 00-1A-2B-3C-4D-5E 自定义
    parameter                           FPGA_MAC                    = 48'h020A_353C_4D5E   ,  // MAC 02-0A-35-3C-4D-5E 这是xilinx专用mac，可被wireshark识别到
    parameter                           FPGA_IP                     = 32'hC0A8_000A        ,  // 192.168.0.10
    parameter                           DST_PORT                    = 16'd54321            ,  // PC   端口
    parameter                           SRC_PORT                    = 16'd54322            ,  // FPGA 端口
    parameter                           PREAMBLE                    = 8'h55                ,
    parameter                           SFD                         = 8'hD5                ,

    parameter                           ETH_TYPE_IPV4               = 16'h0800             ,
    parameter                           ETH_TYPE_ARP                = 16'h0806             ,


    parameter                           IP_MARK                     = 16'h0                ,//标识，PC发的包，这个字段不为0，这个字段取消检查
    parameter                           IP_FRAG_OFFSET              = 16'h0                ,//标志+片偏移
    parameter                           IP_VER                      = 8'h45                ,// 版本+首部长度
    parameter                           IP_SERVICE                  = 8'h00                ,// 服务类型
    parameter                           IP_TTL                      = 8'h80                ,// TTL生存时间

//=========================协议参数定义:发送部分========================

//ARP
    parameter                           ARP_PROTO_TYPE_IPV4         = 16'h0800             ,// IPv4，arp报文独有
    parameter                           ARP_HW_TYPE_ETHERNET        = 16'h0001             ,// 以太网
    parameter                           ARP_HW_SIZE                 = 8'h06                ,// MAC地址长度
    parameter                           ARP_PROTO_SIZE              = 8'h04                ,// IP地址长度
    parameter                           ARP_OPCODE_REQUEST          = 16'h0001             ,// ARP请求
    parameter                           ARP_OPCODE_REPLY            = 16'h0002             ,// ARP响应
//ICMP
    parameter                           ICMP_IP_PROTOCOL            = 8'h01                ,// 上层协议，ICMP固定1
    parameter                           ICMP_TYPE                   = 8'h00                ,// ICMP类型，0-回显应答
    parameter                           ICMP_CODE                   = 8'h00                ,// ICMP代码

//UDP
    parameter                           UDP_IP_PROTOCOL             = 8'h11                ,//上层协议，UDP固定17
    parameter                           UDP_VERC                    = 16'h0                ,//UDP校验和，不做校验，空置为0
    parameter                           UDP_PACKET_BYTE_SIZE        = 512                  ,//UDP单次发送512字节
//IFG
    parameter                           IFG_COUNT                   = 15                   ,//帧间间隔的周期数，96bit时间，要求12个字节，我多留了裕量，15个字节
//=========================协议参数定义:接收部分，arp——cache========================

    parameter                           ARP_LENGTH                  = 52                   ,
    parameter                           CACHE_SIZE                  = 16                   ,
    parameter                           AGING_SEC                   = 60                   ,// 老化时间（秒）
    parameter                           ICMP_ECHO_REQUEST           = 8'h08                ,//收到别人的请求是0x08
    parameter                           ICMP_ECHO_REPLY             = 8'h00                ,//回复别人的请求是00

//PHY上电初始化
    parameter                           SYS_CLK_FREQ                = 50_000_000           ,// 系统时钟频率
    parameter                           PHY_RST_HOLD_MS             = 25                   ,// PHY硬复位保持时间     25ms
    parameter                           PHY_INIT_WAIT_MS            = 100                  ,// PHY复位释放后等待初始化完成时间，模拟校准+RXC锁定   100ms
    parameter                           IP_CHECKSUM_CHECK_VALID     = 0                    ,//UDP和ICMP校验和是否开启信号，0为关闭，1为开启，PC发的包默认关闭，故此参数为0

//UDP回环测试使能
    parameter                           UDP_LOOKBACK_TEST_ENABLE     = 0                    //这个参数决定是否进行UDP回环实验，它改变的是udp_payload的长度  ,默认为0，等于1则为回环逻辑      
)

(
    // ==================== 系统时钟与复位 ====================
    input                               clk_125m                   ,//以太网125MHz时钟
    input                               rst_n                      ,// 低有效复位
    
    // ==================== PHY 接口 ====================
    // GMII 发送接口
    output               [   7: 0]      gmii_txd                   ,
    output                              gmii_tx_en                 ,

    // GMII 接收接口
    input                [   7: 0]      gmii_rxd                   ,
    input                               gmii_rxdv                  ,
    output                              phy_rst_n                  ,
    output               [   7: 0]      led                        ,//观察端口，快速查看是否正常通讯

    // ==================== UDP数据流接口 ====================   
    //以太网接收到的payload,这个fifo在接收模块中，给消费者读接口
    output                              udp_frame_rx_done_valid    ,
    output               [  10: 0]      udp_rx_payload_count_gray_sync,//已同步到消费者时钟域，接收到了多少个payload数据，到时候原样读出
    output                              rd_rst_busy_udp_rx_fifo    ,
    output               [   7: 0]      dout_udp_rx_fifo           ,
    output                              empty_udp_rx_fifo          ,
    input                               rd_en_udp_rx_fifo          ,
    input                               rd_clk_udp_rx_fifo         ,//读取fifo的读时钟

    //应用端写接口，写入fifo，udp发送端通过读fifo，获取payload数据
    input                               wr_clk_udp_tx_fifo         ,//udp发送fifo的写时钟
//    input                [  15: 0]      din_udp_tx_fifo            ,
    input                [  7: 0]      din_udp_tx_fifo            ,
    input                               wr_en_udp_tx_fifo          ,
    output                              full_udp_tx_fifo           ,
//    output               [   9: 0]      wr_data_count_udp_tx_fifo  ,
    output               [  10: 0]      wr_data_count_udp_tx_fifo  ,
    output                              wr_rst_busy_udp_tx_fifo    ,
//发送UDP数据时需要的payload长度及参数
    input                               udp_payload_count_valid    ,//这是一个电平信号，拉高使用外部的payload字节数，为低时，使用参数化的字节数
    input                [  10: 0]      udp_payload_count           
    );
//===============================================================================================================   
//本地参数及接口定义、连线
        //////////////////   源端发送仲裁模块     ///////////////////
//仲裁输出
    wire                                arp_reply_start_pulse      ;
    wire                                icmp_start_pulse_primitive ;
    wire                                udp_start_pulse_primitive  ;
    wire                                arp_request_start_pulse    ;//该逻辑已弃用


    reg                                 arp_tx_reply_req           ;// 电平req，仲裁输出start后拉低
    reg                                 icmp_tx_reply_req          ;// 电平req，仲裁输出start后拉低
    reg                                 udp_tx_req                 ;// 电平req，仲裁输出start后拉低
//    reg                                 arp_tx_request_req         ;//  该逻辑已弃用

        //////////////////    为udp发送提供数据源的fifo    ///////////////////
    wire                                rst_udp_tx_fifo            ;//异步fifo复位信号，需特别关注

    wire                                rd_en_udp_tx_fifo          ;
    wire                 [   7: 0]      dout_udp_tx_fifo           ;
    wire                                empty_udp_tx_fifo          ;
    wire                 [  10: 0]      rd_data_count_udp_tx_fifo  ;
    wire                                rd_rst_busy_udp_tx_fifo    ;

        //////////////////    发送模块       ///////////////////
//背压信号
    wire                                arp_gmii_tx_ready          ;
    wire                                icmp_gmii_tx_ready         ;
    wire                                udp_gmii_tx_ready          ;
//arp模块
    wire                                arp_tx_busy                ;
    wire                                arp_tx_done                ;
//icmp模块
    wire                                icmp_tx_busy               ;
    wire                                icmp_tx_done               ;
//udp 模块
    wire                                udp_tx_busy                ;
    wire                                udp_tx_done                ;
    reg                 [  10: 0]      udp_payload_count_dynamic   ;//根据需要后选择的udp payload数据长度

//关键！从接收模块解析来的pc的mac和ip，这是发送正常工作的必要内容
    reg                  [  47: 0]      pc_mac                     ;
    reg                  [  31: 0]      pc_ip                      ;

    
        //////////////////    接收模块       ///////////////////
    //arp_cache接口  

    //ARP 应答信息输出接口
    wire                                arp_tx_reply_req_pulse     ;
    wire                 [  47: 0]      arp_target_mac             ;
    wire                 [  31: 0]      arp_target_ip              ;

    //解析出的 ICMP 数据,靠它来发送icmp_reply
    wire                 [  15: 0]      icmp_reply_checksum        ;
    wire                                icmp_reply_checksum_valid  ;
    wire                 [  15: 0]      icmp_identifier            ;
    wire                 [  15: 0]      icmp_sequence              ;
    //ICMP PAYLOAD数据接口
    wire                                rd_en_icmp_fifo            ;
    wire                 [   7: 0]      dout_icmp_fifo             ;
    wire                                empty_icmp_fifo            ;
    wire                 [  10: 0]      icmp_payload_count         ;

    wire                                srst_icmp_fifo             ;//同步fifo复位，需特别关照
    //UDP PAYLOAD数据接口
    wire                                rst_udp_rx_fifo            ;//异步fifo复位信号，需特别关注
    wire               [  10: 0]      udp_rx_payload_count         ;//以太网时钟域，用以回环测试，接收到了多少个payload数据，到时候原样读出
    // 以太网所有信息的最终裁决信号 
    wire                                arp_frame_rx_done_valid    ;
    wire                                icmp_frame_rx_done_valid   ;
//  wire                                udp_frame_rx_done_valid    ;//这个信号作为输出，通知应用端取数据

wire [5:0]error_led;

//===============================================================================================================
//逻辑输出

//=================================================================================
//动态产生UDP payload长度逻辑
    always @(posedge clk_125m or negedge rst_n) begin
        if (!rst_n) 
            udp_payload_count_dynamic <= UDP_PACKET_BYTE_SIZE ;
        else if(udp_payload_count_valid)begin
            if(UDP_LOOKBACK_TEST_ENABLE&&udp_frame_rx_done_valid)
            udp_payload_count_dynamic <= udp_rx_payload_count;
            else if(UDP_LOOKBACK_TEST_ENABLE==0)
            udp_payload_count_dynamic <= udp_payload_count;
            else 
            udp_payload_count_dynamic <=udp_payload_count_dynamic;            
        end  
        else
            udp_payload_count_dynamic <=udp_payload_count_dynamic;

        end

//=================================================================================
//有了仲裁后，所有通道时刻准备好

    assign                              arp_gmii_tx_ready           = 1;
    assign                              icmp_gmii_tx_ready          = 1;
    assign                              udp_gmii_tx_ready           = 1;
    assign                              phy_rst_n                   = 1 ;

//=================================================================================
//产生PC MAC和IP逻辑

    always @(posedge clk_125m or negedge rst_n) begin
        if (!rst_n) begin
            pc_mac <= PC_MAC  ;
            pc_ip  <= PC_IP   ;
        end 
        else if(arp_frame_rx_done_valid)  begin
            pc_mac <= arp_target_mac   ;
            pc_ip  <= arp_target_ip    ;
            end
        end


    assign                              rst_udp_tx_fifo             = ~rst_n;
    assign                              srst_icmp_fifo              = ~rst_n;
    assign                              rst_udp_rx_fifo             = ~rst_n;

//=================================================================================
//源端仲裁的req产生逻辑
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
reg udp_tx_pulse;//通过对比fifo中计数器的值，得出什么时候产生发送请求信号
// 条件：1. 当前未在发送UDP（udp_tx_busy为低，避免冲突） 2. 读侧FIFO数据量满足单次UDP发送长度（512字节） 3. 当前UDP发送请求未激活（!udp_tx_req，避免重复触发）

    always @(posedge clk_125m or negedge rst_n) begin
        if (!rst_n) begin
            udp_tx_pulse <= 1'b0;
        end else begin
            if (!udp_tx_busy && 
                    (rd_data_count_udp_tx_fifo >= (udp_payload_count_dynamic-2)) 
//                    (rd_data_count_udp_tx_fifo >= UDP_PACKET_BYTE_SIZE) 
                    &&!udp_tx_req) begin
                udp_tx_pulse <= 1'b1;
            end else begin
                udp_tx_pulse <= 1'b0;
            end
        end
    end


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

//===============================================================================================================
//调用底层模块
//////////////////////////////////////////    接收模块       //////////////////////////////////////////////

ethernet_rx_top#(
//=========================协议重要参数配置=====================

    .PC_MAC                             (PC_MAC                    ),
    .PC_IP                              (PC_IP                     ),
    .FPGA_MAC                           (FPGA_MAC                  ),
    .FPGA_IP                            (FPGA_IP                   ),
    .DST_PORT                           (DST_PORT                  ),
    .SRC_PORT                           (SRC_PORT                  ),
    .CLOCK_FREQUENCY                    (ETH_CLOCK_FREQUENCY       ),
    .PREAMBLE                           (PREAMBLE                  ),
    .SFD                                (SFD                       ),

//=========================协议参数定义========================
    .ETH_TYPE_IPV4                      (ETH_TYPE_IPV4             ),
    .ETH_TYPE_ARP                       (ETH_TYPE_ARP              ),
    .ARP_LENGTH                         (ARP_LENGTH                ),
    .CACHE_SIZE                         (CACHE_SIZE                ),
    .AGING_SEC                          (AGING_SEC                 ),
    .IP_VER                             (IP_VER                    ),
    .IP_SERVICE                         (IP_SERVICE                ),
    .IP_MARK                            (IP_MARK                   ),
    .IP_FRAG_OFFSET                     (IP_FRAG_OFFSET            ),
    .IP_TTL                             (IP_TTL                    ),
    .IP_PROTO_UDP                       (UDP_IP_PROTOCOL           ),
    .IP_PROTO_ICMP                      (ICMP_IP_PROTOCOL          ),
    .ICMP_ECHO_REQUEST                  (ICMP_ECHO_REQUEST         ),
    .ICMP_ECHO_REPLY                    (ICMP_ECHO_REPLY           ),
    .ICMP_CODE                          (ICMP_CODE                 ),
    .UDP_VERC                           (UDP_VERC                  ),
    .IP_CHECKSUM_CHECK_VALID            (IP_CHECKSUM_CHECK_VALID   ) 
)
 u_ethernet_rx_top(
// ==================== 全局信号 ====================
    .clk_125m                           (clk_125m                  ),// (input)
    .rst_n                              (rst_n                     ),// (input)
// ==================== GMII接口 ====================
    .gmii_rxd                           (gmii_rxd                  ),// (input)
    .gmii_rx_dv                         (gmii_rxdv                 ),// (input)
//ARP 应答信息输出接口
    .arp_tx_reply_req_pulse             (arp_tx_reply_req_pulse    ),// (output)
    .arp_target_mac                     (arp_target_mac            ),// (output)
    .arp_target_ip                      (arp_target_ip             ),// (output)

// ========= 解析出的 ICMP 数据,靠它来发送icmp_reply ==============
    .icmp_reply_checksum                (icmp_reply_checksum       ),// (output)
    .icmp_reply_checksum_valid          (icmp_reply_checksum_valid ),// (output)
    .icmp_identifier                    (icmp_identifier           ),// (output)// 标识符
    .icmp_sequence                      (icmp_sequence             ),// (output)// 序列号
// ===================  ICMP PAYLOAD数据接口====================
    .rd_en_icmp_fifo                    (rd_en_icmp_fifo           ),// (input)
    .dout_icmp_fifo                     (dout_icmp_fifo            ),// (output)
    .empty_icmp_fifo                    (empty_icmp_fifo           ),// (output)
    .icmp_payload_count                 (icmp_payload_count        ),// (output)
    .srst_icmp_fifo                     (srst_icmp_fifo            ),// (input)
// ===================  UDP PAYLOAD数据接口====================
    .udp_payload_count_gray_sync        (udp_rx_payload_count_gray_sync),// (output)//已同步到消费者时钟域
    .udp_rx_payload_count               (udp_rx_payload_count      ),// (output)    //以太网时钟域，用以数据回环   
    .rst_udp_fifo                       (rst_udp_rx_fifo           ),// (input)
    .rd_clk_udp_fifo                    (rd_clk_udp_rx_fifo        ),// (input)
    .dout_udp_fifo                      (dout_udp_rx_fifo          ),// (output)
    .rd_en_udp_fifo                     (rd_en_udp_rx_fifo         ),// (input)
    .empty_udp_fifo                     (empty_udp_rx_fifo         ),// (output)
    .rd_rst_busy_udp_fifo               (rd_rst_busy_udp_rx_fifo   ),// (output)
// ===================  临时调试数据接口====================
    .error_led                          (error_led                 ),
// =================== 以太网所有信息的最终裁决信号 ====================
    .arp_frame_rx_done_valid            (arp_frame_rx_done_valid   ),// (output)
    .icmp_frame_rx_done_valid           (icmp_frame_rx_done_valid  ),// (output)
    .udp_frame_rx_done_valid            (udp_frame_rx_done_valid   ) // (output)
);

//////////////////////////////////////////    发送模块       //////////////////////////////////////////////


ethernet_tx_top#(
    //=========================协议重要参数配置=====================
    .PC_MAC                             (PC_MAC                    ),
    .PC_IP                              (PC_IP                     ),
    .FPGA_MAC                           (FPGA_MAC                  ),
    .FPGA_IP                            (FPGA_IP                   ),
    .DST_PORT                           (DST_PORT                  ),
    .SRC_PORT                           (SRC_PORT                  ),
    .PREAMBLE                           (PREAMBLE                  ),
    .SFD                                (SFD                       ),
    .ETH_TYPE                           (ETH_TYPE_IPV4             ),
    .IP_VER                             (IP_VER                    ),
    .IP_SERVICE                         (IP_SERVICE                ),
    .IP_MARK                            (IP_MARK                   ),
    .IP_FRAG_OFFSET                     (IP_FRAG_OFFSET            ),
    .IP_TTL                             (IP_TTL                    ),
    //ARP
    .ARP_ETH_TYPE                       (ETH_TYPE_ARP              ),
    .ARP_HW_TYPE_ETHERNET               (ARP_HW_TYPE_ETHERNET      ),
    .ARP_PROTO_TYPE_IPV4                (ARP_PROTO_TYPE_IPV4       ),
    .ARP_HW_SIZE                        (ARP_HW_SIZE               ),
    .ARP_PROTO_SIZE                     (ARP_PROTO_SIZE            ),
    .ARP_OPCODE_REQUEST                 (ARP_OPCODE_REQUEST        ),
    .ARP_OPCODE_REPLY                   (ARP_OPCODE_REPLY          ),
    //ICMP
    .ICMP_IP_PROTOCOL                   (ICMP_IP_PROTOCOL          ),
    .ICMP_TYPE                          (ICMP_TYPE                 ),
    .ICMP_CODE                          (ICMP_CODE                 ),
    //UDP
    .UDP_IP_PROTOCOL                    (UDP_IP_PROTOCOL           ),
    .UDP_VERC                           (UDP_VERC                  ),
    .UDP_PACKET_BYTE_SIZE               (UDP_PACKET_BYTE_SIZE      ),
//IFG
    .IFG_COUNT                          (IFG_COUNT                 ) //帧间间隔的周期数，96bit时间，要求12个字节，我多留了裕量，15个字节
)
 u_ethernet_tx_top(

// ==================== 全局信号 ====================
    .clk_125m                           (clk_125m                  ),// (input)
    .rst_n                              (rst_n                     ),// (input)
    .gmii_txd                           (gmii_txd                  ),// (output)
    .gmii_tx_en                         (gmii_tx_en                ),// (output)
// ==================== arp发送所需信号 ====================
    .arp_gmii_tx_ready                  (arp_gmii_tx_ready         ),// (input)// 背压信号
// 来自 ARP cache（Request）逻辑已弃用
    .arp_request_start_pulse            (0                         ),// (input)
    .arp_tx_request_ip                  (32'h0                     ),// (input)
    .arp_tx_request_dst_mac             (48'h0                     ),// (input)
//来自 ARP Cache（Reply）
    .arp_reply_start_pulse              (arp_reply_start_pulse     ),// (input)
//    .arp_reply_start_pulse              (tx_go                     ),// (input)
    .arp_target_mac                     (arp_target_mac            ),// (input)
    .arp_target_ip                      (arp_target_ip             ),// (input)
//状态接口
    .arp_tx_busy                        (arp_tx_busy               ),// (output)
    .arp_tx_done                        (arp_tx_done               ),// (output)
// ==================== icmp发送所需信号 ====================
    .icmp_start_pulse_primitive         (icmp_start_pulse_primitive),// (input)
//    .icmp_start_pulse_primitive         (tx_go ),// (input)
    .icmp_gmii_tx_ready                 (icmp_gmii_tx_ready        ),// (input)
    .icmp_reply_checksum                (icmp_reply_checksum       ),// (input)
    .icmp_reply_checksum_valid          (icmp_reply_checksum_valid ),// (input)
    .icmp_identifier                    (icmp_identifier           ),// (input)// 标识符
    .icmp_sequence                      (icmp_sequence             ),// (input)// 序列号
//ICMP PAYLOAD数据接口
    .rd_en_icmp_fifo                    (rd_en_icmp_fifo           ),// (output)
    .dout_icmp_fifo                     (dout_icmp_fifo            ),// (input)
    .empty_icmp_fifo                    (empty_icmp_fifo           ),// (input)
    .icmp_payload_count                 (icmp_payload_count        ),// (input)
//状态接口
    .icmp_tx_busy                       (icmp_tx_busy              ),// (output)
    .icmp_tx_done                       (icmp_tx_done              ),// (output)
// ===================  UDP发送所需信号 ====================
   .udp_start_pulse_primitive          (udp_start_pulse_primitive ),// (input)
  //    .udp_start_pulse_primitive          (tx_go                     ),// (input)
    .udp_gmii_tx_ready                  (udp_gmii_tx_ready         ),// (input)// 背压信号
    .rd_en_udp_tx_fifo                  (rd_en_udp_tx_fifo         ),// (output)
    .dout_udp_tx_fifo                   (dout_udp_tx_fifo          ),// (input)
    .empty_udp_tx_fifo                  (empty_udp_tx_fifo         ),// (input)
    .rd_rst_busy_udp_tx_fifo            (rd_rst_busy_udp_tx_fifo   ),// (input)
// UDP payload字节数
    .udp_payload_count                  (udp_payload_count_dynamic ),// (input)
//状态接口
    .udp_tx_busy                        (udp_tx_busy               ),// (output)
    .udp_tx_done                        (udp_tx_done               ),// (output)
// ===================  PC的IP和MAC ====================
    .pc_mac                             (pc_mac                    ),// (input)
    .pc_ip                              (pc_ip                     ) // (input)
);

//////////////////////////////////////////  源端发送仲裁模块    //////////////////////////////////////////////
ethernet_tx_scheduler u_ethernet_tx_scheduler(
// ==================== 全局信号 ====================
    .clk_125m                           (clk_125m                  ),// (input)
    .rst_n                              (rst_n                     ),// (input)
// ==================== arp发送所需信号 ====================
    .arp_tx_reply_req                   (arp_tx_reply_req          ),// (input)// 电平req，外部保持到start产生后下一拍
    .arp_tx_request_req                 (arp_tx_request_req        ),// (input)// 电平req，外部保持到start产生后下一拍
    .arp_tx_busy                        (arp_tx_busy               ),// (input)// 发送模块忙指示
    .arp_tx_done                        (arp_tx_done               ),// (input)// 未使用，保留端口兼容
// ==================== icmp发送所需信号 ====================
    .icmp_tx_reply_req                  (icmp_tx_reply_req         ),// (input)// 电平req，外部保持到start产生后下一拍
    .icmp_tx_busy                       (icmp_tx_busy              ),// (input)// 发送模块忙指示
    .icmp_tx_done                       (icmp_tx_done              ),// (input)// 未使用，保留端口兼容
// ===================  UDP发送所需信号 ====================
    .udp_tx_req                         (udp_tx_req                ),// (input)// 电平req，外部保持到start产生后下一拍
    .udp_tx_busy                        (udp_tx_busy               ),// (input)// 发送模块忙指示
    .udp_tx_done                        (udp_tx_done               ),// (input)// 未使用，保留端口兼容
// ===================  最终仲裁逻辑信号输出 ====================
    .arp_request_start_pulse            (arp_request_start_pulse   ),// (output)
    .arp_reply_start_pulse              (arp_reply_start_pulse     ),// (output)
    .icmp_start_pulse_primitive         (icmp_start_pulse_primitive),// (output)
    .udp_start_pulse_primitive          (udp_start_pulse_primitive ) // (output)
);

//////////////////////////////////////////   为udp发送提供数据源的fifo      //////////////////////////////////////////////
/*
udp_tx_fifo udp_tx_payload_fifo (
    .rst                                (rst_udp_tx_fifo                       ),// input wire rst

    .wr_clk                             (wr_clk_udp_tx_fifo                    ),// input wire wr_clk
    .din                                (din_udp_tx_fifo                       ),// input wire [15 : 0] din
    .wr_en                              (wr_en_udp_tx_fifo                     ),// input wire wr_en
    .full                               (full_udp_tx_fifo                      ),// output wire full
    .wr_data_count                      (wr_data_count_udp_tx_fifo             ),// output wire [9 : 0] wr_data_count
    .wr_rst_busy                        (wr_rst_busy_udp_tx_fifo               ),// output wire wr_rst_busy

    .rd_clk                             (clk_125m                              ),// input wire rd_clk
    .rd_en                              (rd_en_udp_tx_fifo                     ),// input wire rd_en
    .dout                               (dout_udp_tx_fifo                      ),// output wire [7 : 0] dout
    .empty                              (empty_udp_tx_fifo                     ),// output wire empty
    .rd_data_count                      (rd_data_count_udp_tx_fifo             ),// output wire [10 : 0] rd_data_count
    .rd_rst_busy                        (rd_rst_busy_udp_tx_fifo               ) // output wire rd_rst_busy
);
*/
udp_tx_fifo udp_tx_payload_fifo (
    .rst                                (rst_udp_tx_fifo                       ),// input wire rst

    .wr_clk                             (wr_clk_udp_tx_fifo                    ),// input wire wr_clk
    .din                                (din_udp_tx_fifo                       ),// input wire [7 : 0] din
    .wr_en                              (wr_en_udp_tx_fifo                     ),// input wire wr_en
    .full                               (full_udp_tx_fifo                      ),// output wire full
    .wr_data_count                      (wr_data_count_udp_tx_fifo             ),// output wire [10 : 0] wr_data_count
    .wr_rst_busy                        (wr_rst_busy_udp_tx_fifo               ),// output wire wr_rst_busy

    .rd_clk                             (clk_125m                              ),// input wire rd_clk
    .rd_en                              (rd_en_udp_tx_fifo                     ),// input wire rd_en
    .dout                               (dout_udp_tx_fifo                      ),// output wire [7 : 0] dout
    .empty                              (empty_udp_tx_fifo                     ),// output wire empty
    .rd_data_count                      (rd_data_count_udp_tx_fifo             ),// output wire [10 : 0] rd_data_count
    .rd_rst_busy                        (rd_rst_busy_udp_tx_fifo               ) // output wire rd_rst_busy
);

//=================================================================================
//绑定LED观测信号,调试部分

//     /*
// 临时调试：用 LED0 指示 gmii_rxdv 活动
reg [23:0] stretch_cnt;
reg gmii_rxdv_stretched;
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        stretch_cnt <= 0;
        gmii_rxdv_stretched <= 0;
    end else begin
                                                                     if (gmii_tx_en) begin
            stretch_cnt <= 12_500_000;   // 100ms
            gmii_rxdv_stretched <= 1;
        end else if (stretch_cnt > 0) begin
            stretch_cnt <= stretch_cnt - 1;
            gmii_rxdv_stretched <= 1;
        end else begin
            gmii_rxdv_stretched <= 0;
        end
    end
end
assign led[0] = gmii_rxdv_stretched;
//=================================================
	//发送间隔计数器
	reg [24:0]cnt;
	
	always@(posedge clk_125m or negedge rst_n)
	if(!rst_n)
		cnt <=  0;
		else //计数器自增，不考虑溢出，接受溢出自动清零
		cnt <=  cnt + 1'b1;
	//24位cnt计满一次启动一次发送，该时间大约为134ms
	assign tx_go = (cnt == 25'd1);


reg pulse_single_1;
reg pulse_single_2;
reg pulse_single_3;
reg pulse_single_4;
reg pulse_single_5;
reg pulse_single_6;

    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n)
                pulse_single_1<=0;
                                                               else if(udp_frame_rx_done_valid)        //要观测的第一个脉冲
                pulse_single_1<=1;end

    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n)
                pulse_single_2<=0;
                                                             else if(udp_tx_done)//要观测的第二个脉冲
                pulse_single_2<=1;end

    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n)
                pulse_single_3<=0;
                                                              else if(rd_data_count_udp_tx_fifo[0])//要观测的第二个脉冲
                pulse_single_3<=1;end

    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n)
                pulse_single_4<=0;
                                                             else if(udp_tx_pulse)//要观测的第二个脉冲
                pulse_single_4<=1;end

    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n)
                pulse_single_5<=0;
                                                             else if(udp_tx_req)//要观测的第二个脉冲
                pulse_single_5<=1;end

    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n)
                pulse_single_6<=0;
                                                             else if(udp_start_pulse_primitive)//要观测的第二个脉冲
                pulse_single_6<=1;end
    assign                              led[1]                      = udp_gmii_tx_ready    ;
    assign                              led[2]                      = pulse_single_1       ;
    assign                              led[3]                      = pulse_single_2       ;
    assign                              led[4]                      = pulse_single_3       ;
    assign                              led[5]                      = pulse_single_4       ;
    assign                              led[6]                      = wr_rst_busy_udp_tx_fifo      ;
    assign                              led[7]                      = rd_rst_busy_udp_rx_fifo;


endmodule
