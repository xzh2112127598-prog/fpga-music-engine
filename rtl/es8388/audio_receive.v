//============================================================
// 本文件从指导老师提供的参考工程 voice_changer_phone（安路 EG4S20）
// 原样移植到本项目（高云 GW5A / Tang Primer 25K），逻辑未做改动。
// 来源目录：Desktop/voice_changer_phone/rtl —— 2026-10-10
//============================================================
module audio_receive #(
    parameter WL = 6'd24
)(
    input               rst_n,
    input               aud_bclk,
    input               aud_lrc,
    input               aud_adcdat,
    output reg          rx_done,
    output reg [31:0]   adc_data
);

reg             aud_lrc_d0;
reg [5:0]       rx_cnt;
reg [31:0]      adc_data_t;
wire            lrc_edge;

assign lrc_edge = aud_lrc ^ aud_lrc_d0;

// 延迟一拍保存LRCK，用于检测左右声道切换边沿。
always @(posedge aud_bclk or negedge rst_n) begin
    if(!rst_n)
        aud_lrc_d0 <= 1'b0;
    else
        aud_lrc_d0 <= aud_lrc;
end

// 每次LRCK改变时重新开始统计当前声道的串行音频位数。
always @(posedge aud_bclk or negedge rst_n) begin
    if(!rst_n)
        rx_cnt <= 6'd0;
    else if(lrc_edge)
        rx_cnt <= 6'd0;
    else if(rx_cnt < 6'd35)
        rx_cnt <= rx_cnt + 1'b1;
end

// 按MSB优先方式接收ES8388输出的24位I2S样本。
always @(posedge aud_bclk or negedge rst_n) begin
    if(!rst_n)
        adc_data_t <= 32'd0;
    else if(rx_cnt < WL)
        adc_data_t[WL - 1'b1 - rx_cnt] <= aud_adcdat;
end

// 完成一个声道的24位样本接收后输出一个aud_bclk周期的rx_done脉冲。
always @(posedge aud_bclk or negedge rst_n) begin
    if(!rst_n) begin
        rx_done  <= 1'b0;
        adc_data <= 32'd0;
    end
    else if(rx_cnt == WL) begin
        rx_done  <= 1'b1;
        adc_data <= adc_data_t;
    end
    else begin
        rx_done <= 1'b0;
    end
end

endmodule
