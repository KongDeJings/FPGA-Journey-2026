`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/06/02 16:03:20
// Design Name: 
// Module Name: arp_cache
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 代码中禁止出现魔数
//////////////////////////////////////////////////////////////////////////////////


module arp_cache
#(
    parameter                           PC_MAC                      = 48'h00E2_6969_EC7D   ,  // MAC: 00-E2-69-69-EC-7D
    parameter                           PC_IP                       = 32'hC0A8_0003        ,  // IP: 192.168.0.3
    parameter                           CACHE_SIZE                  = 16                   ,
    parameter                           AGING_SEC                   = 60                   ,   // 老化时间（秒）
    parameter                           CLOCK_FREQUENCY             = 125_000_000          ,    // 计数1s所需周期数(时钟频率)    
    parameter                           BROADCAST_MAC               = 48'hFF_FF_FF_FF_FF_FF

)
(
    input                               clk_125m                   ,
    input                               rst_n                      ,

    // ==================== ARP 接收 ====================
    input                               arp_frame_rx_done          ,
    input                [  47: 0]      arp_src_mac                ,
    input                [  31: 0]      arp_src_ip                 ,
    input                [  47: 0]      arp_dst_mac                ,
    input                [  31: 0]      arp_dst_ip                 ,
    input                [  15: 0]      arp_opcode                 ,// 1:请求 2:回复
    // ==================== ARP 应答 ====================
    output reg                          arp_tx_reply_req_pulse     ,
    output reg           [  47: 0]      arp_target_mac             ,
    output reg           [  31: 0]      arp_target_ip              ,

    // ==================== 本地配置 ====================
    input                [  31: 0]      local_ip                        

//   // ==================== 查询接口 ====================该逻辑已弃用，保留接口
//   input                [  31: 0]      query_ip                   ,// 查询的ip
//   output reg           [  47: 0]      query_mac                  ,// 查询的mac
//   output reg                          query_hit                  ,// 查询命中
//   // ==================== ARP 主动请求 ==================== 该逻辑已弃用，保留接口
//   output reg                          arp_tx_request_req_pulse   ,
//   output reg           [  31: 0]      arp_tx_request_ip          ,
//   output reg           [  47: 0]      arp_tx_request_dst_mac     ,//广播 FF:FF:FF:FF:FF:FF
//   output reg                          arp_request_done           // 请求完成，这个时候可以取用query_mac，同时告诉arp_requester可不必等待了

);
localparam ARP_OP_REQUEST = 16'h0001;  // ARP请求
localparam ARP_OP_REPLY   = 16'h0002;  // ARP回复

//===================================================
//产生arp应答相关信号
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        arp_tx_reply_req_pulse <= 0;
            arp_target_mac <=PC_MAC;
            arp_target_ip  <=PC_IP ;
    end

    else if (arp_frame_rx_done && arp_opcode == ARP_OP_REQUEST && arp_dst_ip == local_ip) begin   //收到请求我的mac,我给个回复
            arp_tx_reply_req_pulse  <= 1;
            arp_target_mac <= arp_src_mac;
            arp_target_ip  <= arp_src_ip;
        end
    else if(arp_frame_rx_done && arp_opcode == ARP_OP_REPLY) begin//收到回复我的arp，我只更新pc_ip/mac
            arp_tx_reply_req_pulse  <= 0;
            arp_target_mac <= arp_src_mac;
            arp_target_ip  <= arp_src_ip;
    end
    else begin
            arp_tx_reply_req_pulse <= 0;
            arp_target_mac <= arp_target_mac;
            arp_target_ip  <= arp_target_ip ;
    end
    end
endmodule











































































/*
//////////////////////////////////////////////弃用的旧逻辑
//弃用原因：FPGA的通讯对象只有PC，ARP_cache设计的目的是为了回复pc的arp_request！完全没必要自建缓存逻辑和老化机制，完全脱裤子放屁！

// ==================== 缓存表 ====================
    reg                  [  31: 0]      cache_ip[0:CACHE_SIZE-1]  ;
    reg                  [  47: 0]      cache_mac[0:CACHE_SIZE-1]  ;
    reg                                 cache_valid[0:CACHE_SIZE-1]  ;
    reg                  [   5: 0]      cache_age[0:CACHE_SIZE-1]  ;
    reg                  [   3: 0]      cache_ptr                  ;


// ==================== 1 秒时基 ====================
reg [26:0] tick_cnt;
wire       tick_1s;

always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n)
        tick_cnt <= 0;
    else if (tick_cnt == CLOCK_FREQUENCY - 1)
        tick_cnt <= 0;
    else
        tick_cnt <= tick_cnt + 1;
end

assign tick_1s = (tick_cnt == CLOCK_FREQUENCY - 1);


// ==================== 查询命中辅助信号 ====================
reg [3:0] query_hit_entry_idx;
reg       query_hit_pulse;

// ==================== 主动请求相关 ====================
reg [31:0] pending_ip;

// ==================== 缓存初始化与主逻辑 ====================
integer i;
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < CACHE_SIZE; i = i + 1) begin
            cache_ip[i]    <= 0;
            cache_mac[i]   <= 0;
            cache_valid[i] <= 0;
            cache_age[i]   <= 0;
        end
        cache_ptr     <= 0;
        arp_tx_reply_req_pulse <= 0;
        arp_target_mac<= 0;
        arp_target_ip <= 0;
    end
    else begin
        arp_tx_reply_req_pulse <= 0;

        // ================== 每秒老化 ==================
        if (tick_1s) begin
            for (i = 0; i < CACHE_SIZE; i = i + 1) begin
                if (cache_valid[i]) begin
                    if (cache_age[i] >= AGING_SEC)
                        cache_valid[i] <= 0;
                    else
                        cache_age[i] <= cache_age[i] + 1;
                end
            end
        end

        // ================== 收到 ARP 请求（问我） ==================
        if (arp_frame_rx_done && arp_opcode == 2'b01 && arp_dst_ip == local_ip) begin
            arp_tx_reply_req_pulse  <= 1;
            arp_target_mac <= arp_src_mac;
            arp_target_ip  <= arp_src_ip;

            // ===== 先删旧 IP =====
            for (i = 0; i < CACHE_SIZE; i = i + 1) begin
                if (cache_valid[i] && cache_ip[i] == arp_src_ip)
                    cache_valid[i] <= 0;
            end

            // ===== 再写新 =====
            cache_ip[cache_ptr]    <= arp_src_ip;
            cache_mac[cache_ptr]   <= arp_src_mac;
            cache_valid[cache_ptr] <= 1;
            cache_age[cache_ptr]   <= 0;

            cache_ptr <= (cache_ptr == CACHE_SIZE-1) ? 0 : cache_ptr + 1;
        end

        // ================== 收到 ARP 应答（回答我） ==================
        if (arp_frame_rx_done && arp_opcode == 2'b10) begin
            // ===== 先删旧 IP =====
            for (i = 0; i < CACHE_SIZE; i = i + 1) begin
                if (cache_valid[i] && cache_ip[i] == arp_src_ip)
                    cache_valid[i] <= 0;
            end

            // ===== 再写新 =====
            cache_ip[cache_ptr]    <= arp_src_ip;
            cache_mac[cache_ptr]   <= arp_src_mac;
            cache_valid[cache_ptr] <= 1;
            cache_age[cache_ptr]   <= 0;

            cache_ptr <= (cache_ptr == CACHE_SIZE-1) ? 0 : cache_ptr + 1;
        end

        // ================== 查询命中续命 ==================
        if (query_hit_pulse) begin
            cache_age[query_hit_entry_idx] <= 0;
        end
    end
end


// ==================== 查询（命中即续命） ====================
integer j;
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        query_hit           <= 0;
        query_mac           <= 0;
        query_hit_entry_idx <= 0;
        query_hit_pulse     <= 0;
    end
    else begin
        query_hit       <= 0;
        query_hit_pulse <= 0;

        for (j = 0; j < CACHE_SIZE; j = j + 1) begin
            if (cache_valid[j] && (cache_ip[j] == query_ip)) begin
                query_hit           <= 1;
                query_mac           <= cache_mac[j];
                query_hit_entry_idx <= j;
                query_hit_pulse     <= 1;
            end
        end
    end
end


// ==================== 主动请求 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        arp_tx_request_req_pulse    <=0;
        arp_tx_request_ip     <=0;
        arp_tx_request_dst_mac  <=0;
        pending_ip      <= 0;  //正在查询中的ip，通过它来核对
    end
    else begin
        arp_tx_request_req_pulse <= 0;

        if ((query_ip != 0 )&& !query_hit) begin
            arp_tx_request_req_pulse     <= 1;
            arp_tx_request_ip      <= query_ip;
            arp_tx_request_dst_mac <= BROADCAST_MAC;
            pending_ip      <= query_ip;
        end

        if (query_ip == 0) begin
            pending_ip <= 0;
        end
    end
end


// ==================== ARP 解析完成事件 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        arp_request_done <= 0;
    end
    else begin
        arp_request_done <= 0;
        if (arp_frame_rx_done ) begin
            if (arp_src_ip == pending_ip) begin         //修改逻辑，防止竞争，假设reply抢占了发包，只要是PC发来的，无论是request还是reply，都能学习到缓存
                arp_request_done <= 1;

//        arp_request_done <= 0;
//        if (arp_frame_rx_done ) begin
//            if (arp_src_ip == pending_ip&& (arp_opcode == 2'b10)) begin
//                arp_request_done <= 1;
//            end
//            else if(query_hit)             //修改逻辑，防止竞争，假设reply抢占了发包，只要是PC发来的，无论是request还是reply，都能学习到缓存
//                arp_request_done <= 1;
//        end
            end
        end
    end 
end


*/