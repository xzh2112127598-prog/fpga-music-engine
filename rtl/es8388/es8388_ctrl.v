//============================================================
// 本文件从指导老师提供的参考工程 voice_changer_phone（安路 EG4S20）
// 原样移植到本项目（高云 GW5A / Tang Primer 25K），逻辑未做改动。
// 来源目录：Desktop/voice_changer_phone/rtl —— 2026-10-10
//============================================================
module es8388_ctrl(
    input               clk,
    input               rst_n,
    input               aud_bclk,
    input               aud_lrc,
    input               aud_adcdat,
    output              aud_dacdat,
    output              aud_scl,
    inout               aud_sda,
    output     [31:0]   adc_data,
    input      [31:0]   dac_data,
    output              rx_done,
    output              tx_done,
    // 移植新增：把 ES8388 配置完成标志引给顶层点灯（原工程没有）
    output              cfg_done,
    // 移植新增：I2C 应答错误（芯片没接 / 线接错 时会置 1）
    output              cfg_ack_err
);

parameter WL = 6'd24;

// 配置ES8388为24位I2S、48kHz采样率和固定耳机输出音量。
es8388_config #(
    .WL             (WL)
) u_es8388_config(
    .clk            (clk),
    .rst_n          (rst_n),
    .aud_scl        (aud_scl),
    .aud_sda        (aud_sda),
    .cfg_done       (cfg_done),
    .cfg_ack_err    (cfg_ack_err)
);

// 从ES8388的ADC串行口接收当前左右声道24位样本。
audio_receive #(
    .WL             (WL)
) u_audio_receive(
    .rst_n          (rst_n),
    .aud_bclk       (aud_bclk),
    .aud_lrc        (aud_lrc),
    .aud_adcdat     (aud_adcdat),
    .rx_done        (rx_done),
    .adc_data       (adc_data)
);

// 把处理后的左声道单声道样本复制到左右两个DAC声道后送回ES8388。
audio_send_mono #(
    .WL             (WL)
) u_audio_send_mono(
    .rst_n          (rst_n),
    .aud_bclk       (aud_bclk),
    .aud_lrc        (aud_lrc),
    .aud_dacdat     (aud_dacdat),
    .dac_data       (dac_data),
    .tx_done        (tx_done)
);

endmodule
