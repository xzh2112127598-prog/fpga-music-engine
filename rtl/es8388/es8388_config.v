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
    output      cfg_done,
    // 移植新增：24 笔写操作里只要有一笔没收到芯片 ACK 就置 1
    output      cfg_ack_err
);

wire        clk_i2c;
wire        i2c_exec;
wire        i2c_done;
wire        ack_err;
wire [15:0] reg_data;

// ---------- NACK 自动重试 ----------
// 只要有任何一笔写没收到 ACK，就每 500ms 把整个 24 寄存器序列从头再跑。
// 这样接线插拔/换位置之后不用重新下载位流，固件自己就能"自愈"。
reg  cfg_ack_err_r;
reg  [18:0] retry_cnt;                   // clk_i2c=1MHz，50 万计数 = 0.5s
wire        retry_tick = cfg_ack_err_r && (retry_cnt == 19'd499_999);
always @(posedge clk_i2c or negedge rst_n) begin
    if (!rst_n) begin
        cfg_ack_err_r <= 1'b0;
        retry_cnt     <= 19'd0;
    end else if (retry_tick) begin
        cfg_ack_err_r <= 1'b0;           // 重试开始，清掉旧错误
        retry_cnt     <= 19'd0;
    end else begin
        if (cfg_ack_err_r) retry_cnt <= retry_cnt + 1'b1;
        if (i2c_done && ack_err) cfg_ack_err_r <= 1'b1;
    end
end
assign cfg_ack_err = cfg_ack_err_r;

// 重试时复位配置序列状态机（i2c_dri 不复位，让在途的一笔写安全跑完）
wire cfg_seq_rst_n = rst_n & ~retry_tick;

// 按固定寄存器表依次配置ES8388的ADC、DAC、I2S格式、48kHz采样率和固定耳机音量。
i2c_reg_cfg #(
    .WL             (WL)
) u_i2c_reg_cfg(
    .clk            (clk_i2c),
    .rst_n          (cfg_seq_rst_n),
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
    .dri_clk        (clk_i2c),
    .ack_err        (ack_err)
);

endmodule
