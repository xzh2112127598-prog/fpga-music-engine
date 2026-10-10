//============================================================
// 本文件从指导老师提供的参考工程 voice_changer_phone（安路 EG4S20）
// 原样移植到本项目（高云 GW5A / Tang Primer 25K），逻辑未做改动。
// 来源目录：Desktop/voice_changer_phone/rtl —— 2026-10-10
//============================================================
`timescale 1ns/1ns

module es8388_config #(
    parameter SLAVE_ADDR = 7'h10,
    parameter WL         = 6'd24,
    parameter BIT_CTRL   = 1'b0,
    parameter CLK_FREQ   = 26'd50_000_000,
    parameter I2C_FREQ   = 18'd250_000
)(
    input       clk,
    input       rst_n,
    output      aud_scl,
    inout       aud_sda,
    // 移植新增：把配置完成标志引出来给顶层点灯（原工程没有）
    output      cfg_done
);

wire        clk_i2c;
wire        i2c_exec;
wire        i2c_done;
wire [15:0] reg_data;

// 按固定寄存器表依次配置ES8388的ADC、DAC、I2S格式、48kHz采样率和固定耳机音量。
i2c_reg_cfg #(
    .WL             (WL)
) u_i2c_reg_cfg(
    .clk            (clk_i2c),
    .rst_n          (rst_n),
    .i2c_done       (i2c_done),
    .i2c_exec       (i2c_exec),
    .cfg_done       (cfg_done),
    .i2c_data       (reg_data)
);

// 使用250kHz I2C总线把寄存器表写入ES8388。
i2c_dri #(
    .SLAVE_ADDR     (SLAVE_ADDR),
    .CLK_FREQ       (CLK_FREQ),
    .I2C_FREQ       (I2C_FREQ)
) u_i2c_dri(
    .clk            (clk),
    .rst_n          (rst_n),
    .i2c_exec       (i2c_exec),
    .bit_ctrl       (BIT_CTRL),
    .i2c_rh_wl      (1'b0),
    .i2c_addr       (reg_data[15:8]),
    .i2c_data_w     (reg_data[7:0]),
    .i2c_data_r     (),
    .i2c_done       (i2c_done),
    .scl            (aud_scl),
    .sda            (aud_sda),
    .dri_clk        (clk_i2c)
);

endmodule
