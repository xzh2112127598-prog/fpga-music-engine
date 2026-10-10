//============================================================
// 本文件从指导老师提供的参考工程 voice_changer_phone（安路 EG4S20）
// 原样移植到本项目（高云 GW5A / Tang Primer 25K），逻辑未做改动。
// 来源目录：Desktop/voice_changer_phone/rtl —— 2026-10-10
//============================================================
module audio_send_mono #(
    parameter WL = 6'd24
)(
    input               rst_n,
    input               aud_bclk,
    input               aud_lrc,
    output reg          aud_dacdat,
    input      [31:0]   dac_data,
    output reg          tx_done
);

reg             aud_lrc_d0;
reg [5:0]       tx_cnt;
reg [31:0]      dac_data_t;
wire            lrc_edge;

assign lrc_edge = aud_lrc ^ aud_lrc_d0;

// 延迟一拍保存LRCK，用于检测左右声道切换边沿。
always @(posedge aud_bclk or negedge rst_n) begin
    if(!rst_n)
        aud_lrc_d0 <= 1'b0;
    else
        aud_lrc_d0 <= aud_lrc;
end

// 每次LRCK改变时重新开始统计当前声道的串行输出位数。
always @(posedge aud_bclk or negedge rst_n) begin
    if(!rst_n)
        tx_cnt <= 6'd0;
    else if(lrc_edge)
        tx_cnt <= 6'd0;
    else if(tx_cnt < 6'd35)
        tx_cnt <= tx_cnt + 1'b1;
end

// 仅在进入左声道时锁存新的单声道样本；进入右声道时保持同一份样本，从而实现左右耳机复制输出。
always @(posedge aud_bclk or negedge rst_n) begin
    if(!rst_n)
        dac_data_t <= 32'd0;
    else if(lrc_edge && (aud_lrc == 1'b0))
        dac_data_t <= dac_data;
end

// 发送完一个声道的24位数据后给出一个aud_bclk周期的tx_done脉冲。
always @(posedge aud_bclk or negedge rst_n) begin
    if(!rst_n)
        tx_done <= 1'b0;
    else if(tx_cnt == WL)
        tx_done <= 1'b1;
    else
        tx_done <= 1'b0;
end

// 在BCLK下降沿改变DAC串行数据，使ES8388能够在后续上升沿稳定采样。
always @(negedge aud_bclk or negedge rst_n) begin
    if(!rst_n)
        aud_dacdat <= 1'b0;
    else if(tx_cnt < WL)
        aud_dacdat <= dac_data_t[WL - 1'b1 - tx_cnt];
    else
        aud_dacdat <= 1'b0;
end

endmodule
