//============================================================
// demo_es8388.v —— ES8388 声卡上板验证（Tang Primer 25K）
//
// 目的：打通"纯硬件合成 -> 数字音频 -> 耳机出声"整条链路
//   1) GW5A PLL 产生 MCLK = 12.288136MHz（+11ppm，见 es8388_audio_pll.v）
//   2) I2C(250kHz) 按参考工程 24 寄存器表配置 ES8388
//   3) ES8388 工作在主机模式：BCLK/LRCK 由芯片产生回给 FPGA
//   4) FPGA 用已验证的 osc_dds 在 BCLK 域产生正弦音，24bit I2S 送出
//
// 听到什么：耳机里 440Hz(A4) 正弦音；按 K6 循环切
//   440Hz -> 1000Hz -> 261.6Hz(C4) -> 静音 -> 440Hz ...
//
// LED 含义（板上只有这 2 颗用户灯，L6 不是灯！）：
//   led[0] (D7/丝印LED4)  = PLL 锁定。常亮=MCLK 正常
//   led[1] (E8/丝印LED3)  = 配置中 1Hz 慢闪；常亮=24 个寄存器写完
//     ★ E8 常亮但没声音 -> 查接线/查耳机/查模块上红色电源灯
//
// 接线（全部在 J6 这个 PMOD 上，和 MPU6050 共存，I2C 共用 G5/F5）：
//   模块 J0(TSW-112-07-G-D 2x12 排针，丝印1=方焊盘)
//     模块14脚(I2C_SCL ) -> J6 pin12 (G5)
//     模块16脚(I2C_SDA ) -> J6 pin11 (F5)
//     模块12脚(I2S_MCLK) -> J6 pin5  (H5)
//     模块10脚(I2S_SCLK) -> J6 pin6  (J5)  ←方向：芯片给 FPGA
//     模块 6脚(I2S_LRCK) -> J6 pin7  (H8)  ←方向：芯片给 FPGA
//     模块 8脚(I2S_SDIN ) -> J6 pin8  (H7)
//     模块 4脚(I2S_SDOUT) -> J6 pin9  (G7)
//     模块23脚(3.3V)     -> J6 pin1/2 (3V3)
//     模块24脚或21脚(GND) -> J6 pin3/4 (GND)
//   （模块排针里 15/13/11/9/7/5/3/1 等奇数脚全部悬空，不用管）
//
// 采样率口径：本 demo 的 fs = MCLK/256 = 48000.53Hz（+11ppm）。
//   DDS 频率字按真实 fs 计算：FTW = round(f×2^32/48000.53)。
//============================================================
module demo_es8388 #(
    parameter integer CLK_FREQ = 50_000_000
)(
    input  wire       clk,        // E2, 50MHz
    input  wire       key,        // K6, 低有效（按下=0）
    output wire [1:0] led,        // [0]=D7, [1]=E8
    output wire       aud_mclk,   // H5
    input  wire       aud_bclk,   // J5
    input  wire       aud_lrc,    // H8
    output wire       aud_dacdat, // H7
    input  wire       aud_adcdat, // G7
    output wire       aud_scl,    // G5
    inout  wire       aud_sda     // F5
);
    // ---------- 50MHz 域：上电复位 ----------
    reg [15:0] por_cnt = 16'd0;
    reg        por_rst_n = 1'b0;
    always @(posedge clk)
        if (&por_cnt) por_rst_n <= 1'b1;
        else          por_cnt  <= por_cnt + 1'b1;

    // ---------- PLL：50M -> 12.288M MCLK（精确值）----------
    wire pll_locked;
    es8388_audio_pll u_pll (
        .clkin  (clk),
        .clkout (aud_mclk),
        .locked (pll_locked)
    );
    // 复位要等 PLL 锁定后再释放，保证 I2C 配置开始时芯片已有 MCLK
    wire audio_rst_n = por_rst_n & pll_locked;

    // I2C 配置在 u_ctrl 内部（es8388_ctrl 已含 es8388_config，
    // 不要再单独例化一份，否则 scl/sda 双驱动综合报错）

    // ---------- 按键换挡（50MHz 域）：440 / 1000 / C4 / 静音 ----------
    wire key_dn = ~key;                      // K6 低有效
    wire key_press;
    debounce_fsm #(.CLK_FREQ(CLK_FREQ)) u_db (
        .clk(clk), .rst_n(por_rst_n),
        .key_in(key_dn), .key_out(), .key_press(key_press)
    );
    reg [1:0] sel = 2'd0;                    // 0=A4 1=1k 2=C4 3=静音
    always @(posedge clk or negedge por_rst_n)
        if (!por_rst_n)   sel <= 2'd0;
        else if (key_press) sel <= sel + 2'b01; // 2bit 自然回绕，第4挡即静音

    // ---------- BCLK 域：DDS 出样本 ----------
    // fs = 48000.53Hz（MCLK +11ppm 所致），FTW = round(f×2^32/48000.53)
    localparam [31:0] FTW_A4  = 32'd39370099;  // 440.0000 Hz
    localparam [31:0] FTW_1K  = 32'd89477498;  // 1000.0000 Hz
    localparam [31:0] FTW_C4  = 32'd23409601;  // 261.6256 Hz

    // 2bit 慢变信号打两拍同步进 BCLK 域（换挡瞬间最多响一个样本的杂音）
    reg [1:0] sel_b1, sel_b2;
    always @(posedge aud_bclk or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            sel_b1 <= 2'd0;
            sel_b2 <= 2'd0;
        end else begin
            sel_b1 <= sel;
            sel_b2 <= sel_b1;
        end
    end

    reg [31:0] ftw;
    always @* begin
        case (sel_b2)
            2'd0:    ftw = FTW_A4;
            2'd1:    ftw = FTW_1K;
            2'd2:    ftw = FTW_C4;
            default: ftw = 32'd0;            // 静音（DDS 输出恒 0）
        endcase
    end

    // LRCK 边沿检测：aud_lrc 0->1 是"进入右声道"时刻，此刻产生新样本，
    // 半个样本周期后（进入左声道）audio_send_mono 会来锁存它
    reg lrc_d;
    always @(posedge aud_bclk or negedge audio_rst_n)
        if (!audio_rst_n) lrc_d <= 1'b0;
        else              lrc_d <= aud_lrc;
    wire lrc_edge  = aud_lrc ^ lrc_d;
    wire tick_new  = lrc_edge & aud_lrc;     // 每样本一次

    wire signed [15:0] dds_out;
    osc_dds #(
        .PHASE_W  (32),
        .ADDR_W   (10),
        .DATA_W   (16),
        .IPOLATE  (1),
        .ROM_FILE ("sine_1024.hex")
    ) u_dds (
        .clk      (aud_bclk),
        .rst_n    (audio_rst_n),
        .en       (tick_new),
        .ftw      (ftw),
        .load     (1'b0),
        .phase_i  (32'd0),
        .out      (dds_out),
        .out_valid(),
        .phase_o  ()
    );

    // Q15(16bit) -> 24bit，音量 -12dB：先把符号扩到 24 位（×256），再算术右移 2 位。
    // 结果 = dds_out × 64，正弦满幅 32767 -> 约 1/4 满度，保护耳朵；
    // 要更响可改成 {{8{dds_out[15]}}, dds_out}（0dB，注意别削顶）。
    wire signed [23:0] tone24 = {{10{dds_out[15]}}, dds_out[15:2]};

    // 32bit 接口符号扩展（es8388_ctrl 约定低 24 位有效）
    wire [31:0] dac_data = {{8{tone24[23]}}, tone24};

    // ---------- ES8388 收发控制（内部含 I2C 配置 + I2S 收发）----------
    wire [31:0] adc_data;
    wire        rx_done, tx_done;
    wire        cfg_done;
    es8388_ctrl #(
        .WL (6'd24)
    ) u_ctrl (
        .clk       (clk),
        .rst_n     (audio_rst_n),
        .aud_bclk  (aud_bclk),
        .aud_lrc   (aud_lrc),
        .aud_adcdat(aud_adcdat),
        .aud_dacdat(aud_dacdat),
        .aud_scl   (aud_scl),
        .aud_sda   (aud_sda),
        .adc_data  (adc_data),               // 本 demo 不用回采，留待变声/录音
        .dac_data  (dac_data),
        .rx_done   (rx_done),
        .tx_done   (tx_done),
        .cfg_done  (cfg_done)
    );

    // ---------- LED ----------
    // D7: PLL 锁定
    assign led[0] = pll_locked;
    // E8: 配置中 1Hz 慢闪；配置完成常亮
    reg [25:0] hb_cnt = 26'd0;
    always @(posedge clk) hb_cnt <= hb_cnt + 1'b1;
    assign led[1] = cfg_done ? 1'b1 : hb_cnt[25];

endmodule
