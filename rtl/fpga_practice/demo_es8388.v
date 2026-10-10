//============================================================
// demo_es8388.v —— ES8388 声卡上板验证（Tang Primer 25K）
//
// 目的：打通"纯硬件合成 -> 数字音频 -> 耳机出声"整条链路
//   1) GW5A PLL 产生 MCLK = 12.288136MHz（+11ppm，见 es8388_audio_pll.v）
//   2) I2C(250kHz) 按参考工程 24 寄存器表配置 ES8388
//   3) ES8388 工作在主机模式：BCLK/LRCK 由芯片产生回给 FPGA
//   4) FPGA 用已验证的 osc_dds 在 BCLK 域产生正弦音，24bit I2S 送出
//
// 听到什么（上电默认第 0 档，按 S1 循环切换）：
//   档 0【满幅方波】1kHz 方波打到满量程(±0x7FFFFF)，滴滴滴：响 0.25s 停 0.75s。
//        ★ 这一档完全绕开 DDS / ROM / 包络，只证明"数字音频能不能到耳朵"。
//          如果这一档都听不到，那就是硬件（接线 / 插孔 / 编解码器），跟代码无关。
//   档 1【小星星】循环播放《一闪一闪亮晶晶》（C 大调，120BPM，42 音 / 48 拍 = 24 秒
//       一轮），带起音收尾包络，像八音盒。
//   档 2【静音】送全 0，用来对比"到底是不是真的有声音"。
//
// LED 含义（板上只有这 2 颗用户灯，L6 不是灯！第 3 个亮的是 POWER 电源灯）：
//   led[0] (D7/丝印LED4)  = PLL 锁定。常亮=MCLK 正常
//   led[1] (E8/丝印LED3)  = 链路状态，见下面三档：
//        慢闪 1Hz  = 24 个寄存器还没写完
//        快闪 12Hz = 写完了但 I2C 没收到 ACK，或芯片没吐 BCLK/LRCK
//        常亮      = 24 字节全部 ACK 正常 + BCLK 有跳动 → 耳机应有 440Hz
//     ★ 注意：参考工程的 I2C 驱动原本完全不看 ACK，所以"没接芯片"和
//       "配置成功"表现一样。本工程已补上 ACK 采样，灯才是可信的。
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

    // ---------- 按键换挡（50MHz 域）：方波 / 小星星 / 静音 ----------
    wire key_dn = ~key;                      // K6 低有效
    wire key_press;
    debounce_fsm #(.CLK_FREQ(CLK_FREQ)) u_db (
        .clk(clk), .rst_n(por_rst_n),
        .key_in(key_dn), .key_out(), .key_press(key_press)
    );
    // 上电先给最好辨认的满幅方波，确认链路后再按 S1 换小星星
    reg [1:0] mode = 2'd0;                   // 0=方波 1=小星星 2=静音
    always @(posedge clk or negedge por_rst_n)
        if (!por_rst_n)     mode <= 2'd0;
        else if (key_press) mode <= (mode == 2'd2) ? 2'd0 : mode + 1'b1;

    // mode 跨时钟域到 BCLK 域（慢速人手信号，两级同步足够）
    reg [1:0] mode_s0, mode_s1;
    always @(posedge aud_bclk or negedge audio_rst_n)
        if (!audio_rst_n) begin mode_s0 <= 2'd0; mode_s1 <= 2'd0; end
        else              begin mode_s0 <= mode; mode_s1 <= mode_s0; end

    // ---------- BCLK 域：《一闪一闪亮晶晶》旋律播放器 ----------
    // fs = 48000.53Hz；120 BPM 下四分音符 0.5s = 24000 个样本。
    // 全曲 42 个音 / 48 拍 = 24 秒，播完自动循环。
    localparam [15:0] BEAT     = 16'd24000;   // 四分音符
    localparam [15:0] TWO_BEAT = 16'd48000;   // 二分音符
    localparam [15:0] ATT      = 16'd256;     // 起音 ~5.3ms（去爆音）
    localparam [15:0] REL      = 16'd1024;    // 收尾 ~21ms
    localparam [5:0]  NLAST    = 6'd41;       // 索引 0~41

    // 音高频率字（FTW = round(f × 2^32 / 48000.53)）
    localparam [31:0] FTW_C = 32'd23409601;   // C4 261.63Hz
    localparam [31:0] FTW_D = 32'd26276389;   // D4 293.66Hz
    localparam [31:0] FTW_E = 32'd29494249;   // E4 329.63Hz
    localparam [31:0] FTW_F = 32'd31248068;   // F4 349.23Hz
    localparam [31:0] FTW_G = 32'd35074771;   // G4 392.00Hz
    localparam [31:0] FTW_A = 32'd39370099;   // A4 440.00Hz

    // LRCK 边沿检测：aud_lrc 0->1 是"进入右声道"时刻，此刻产生新样本，
    // 半个样本周期后（进入左声道）audio_send_mono 会来锁存它
    reg lrc_d;
    always @(posedge aud_bclk or negedge audio_rst_n)
        if (!audio_rst_n) lrc_d <= 1'b0;
        else              lrc_d <= aud_lrc;
    wire lrc_edge  = aud_lrc ^ lrc_d;
    wire tick_new  = lrc_edge & aud_lrc;     // 每样本一次

    // 音符表：音高 + 时长
    reg [5:0]  note_idx;
    reg [16:0] scnt;                         // 当前音已持续的样本数
    reg [31:0] m_ftw;
    reg [15:0] dur;
    always @* begin
        case (note_idx)
            6'd0 : begin m_ftw = FTW_C; dur = BEAT; end
            6'd1 : begin m_ftw = FTW_C; dur = BEAT; end
            6'd2 : begin m_ftw = FTW_G; dur = BEAT; end
            6'd3 : begin m_ftw = FTW_G; dur = BEAT; end
            6'd4 : begin m_ftw = FTW_A; dur = BEAT; end
            6'd5 : begin m_ftw = FTW_A; dur = BEAT; end
            6'd6 : begin m_ftw = FTW_G; dur = TWO_BEAT; end
            6'd7 : begin m_ftw = FTW_F; dur = BEAT; end
            6'd8 : begin m_ftw = FTW_F; dur = BEAT; end
            6'd9 : begin m_ftw = FTW_E; dur = BEAT; end
            6'd10: begin m_ftw = FTW_E; dur = BEAT; end
            6'd11: begin m_ftw = FTW_D; dur = BEAT; end
            6'd12: begin m_ftw = FTW_D; dur = BEAT; end
            6'd13: begin m_ftw = FTW_C; dur = TWO_BEAT; end
            6'd14: begin m_ftw = FTW_G; dur = BEAT; end
            6'd15: begin m_ftw = FTW_G; dur = BEAT; end
            6'd16: begin m_ftw = FTW_F; dur = BEAT; end
            6'd17: begin m_ftw = FTW_F; dur = BEAT; end
            6'd18: begin m_ftw = FTW_E; dur = BEAT; end
            6'd19: begin m_ftw = FTW_E; dur = BEAT; end
            6'd20: begin m_ftw = FTW_D; dur = TWO_BEAT; end
            6'd21: begin m_ftw = FTW_G; dur = BEAT; end
            6'd22: begin m_ftw = FTW_G; dur = BEAT; end
            6'd23: begin m_ftw = FTW_F; dur = BEAT; end
            6'd24: begin m_ftw = FTW_F; dur = BEAT; end
            6'd25: begin m_ftw = FTW_E; dur = BEAT; end
            6'd26: begin m_ftw = FTW_E; dur = BEAT; end
            6'd27: begin m_ftw = FTW_D; dur = TWO_BEAT; end
            6'd28: begin m_ftw = FTW_C; dur = BEAT; end
            6'd29: begin m_ftw = FTW_C; dur = BEAT; end
            6'd30: begin m_ftw = FTW_G; dur = BEAT; end
            6'd31: begin m_ftw = FTW_G; dur = BEAT; end
            6'd32: begin m_ftw = FTW_A; dur = BEAT; end
            6'd33: begin m_ftw = FTW_A; dur = BEAT; end
            6'd34: begin m_ftw = FTW_G; dur = TWO_BEAT; end
            6'd35: begin m_ftw = FTW_F; dur = BEAT; end
            6'd36: begin m_ftw = FTW_F; dur = BEAT; end
            6'd37: begin m_ftw = FTW_E; dur = BEAT; end
            6'd38: begin m_ftw = FTW_E; dur = BEAT; end
            6'd39: begin m_ftw = FTW_D; dur = BEAT; end
            6'd40: begin m_ftw = FTW_D; dur = BEAT; end
            6'd41: begin m_ftw = FTW_C; dur = TWO_BEAT; end
            default: begin m_ftw = FTW_C; dur = BEAT; end
        endcase
    end

    // 音符推进：当前音的样本数走满就换下一个音，最后一个音后回到开头
    always @(posedge aud_bclk or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            note_idx <= 6'd0;
            scnt     <= 17'd0;
        end else if (tick_new) begin
            if (scnt + 1'b1 >= dur) begin
                scnt     <= 17'd0;
                note_idx <= (note_idx == NLAST) ? 6'd0 : note_idx + 1'b1;
            end else
                scnt <= scnt + 1'b1;
        end
    end

    // 包络：起音渐强 / 收尾渐弱，全部用移位实现（不引除法器）
    wire [16:0] rel_left = dur - scnt;
    reg  [8:0]  env;                         // 0~128
    always @* begin
        if      (scnt < ATT)      env = {1'b0, scnt[7:1]};      // 渐强
        else if (rel_left < REL)  env = {1'b0, rel_left[9:3]};  // 渐弱
        else                      env = 9'd128;                 // 保持
    end

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
        .ftw      (m_ftw),
        .load     (1'b0),
        .phase_i  (32'd0),
        .out      (dds_out),
        .out_valid(),
        .phase_o  ()
    );

    // Q15(16bit) × 包络(0~128) -> 24bit I2S。
    // 满幅 32767×128 ≈ 4.19e6 / 8.39e6 = 约 -6dB，够响又不炸耳。
    wire signed [8:0]  gain_s = {1'b0, env};
    wire signed [24:0] prod25 = dds_out * gain_s;
    wire signed [23:0] tone24 = prod25[23:0];
    wire [31:0] dac_mel = {{8{tone24[23]}}, tone24};   // 符号扩展到 32bit

    // ---------- 档 0：满幅 1kHz 方波（绕开 DDS/ROM/包络的"链路探针"）----------
    // 48000 样本为一轮：前 12000(0.25s) 出方波，后 36000(0.75s) 出 0。
    // 方波半周期 24 个样本 -> f = 48000/48 = 1000Hz。
    reg [5:0]  sqp;                          // 0..47
    reg [15:0] gcnt;                         // 0..47999
    always @(posedge aud_bclk or negedge audio_rst_n)
        if (!audio_rst_n) begin sqp <= 6'd0; gcnt <= 16'd0; end
        else if (tick_new) begin
            sqp  <= (sqp  == 6'd47)     ? 6'd0  : sqp  + 1'b1;
            gcnt <= (gcnt == 16'd47999) ? 16'd0 : gcnt + 1'b1;
        end
    wire [23:0] sq24 = (gcnt < 16'd12000)
                     ? ((sqp < 6'd24) ? 24'h7FFFFF : 24'h800000)
                     : 24'h000000;
    wire [31:0] dac_sq = {{8{sq24[23]}}, sq24};

    // ---------- 三档选择 ----------
    wire [31:0] dac_data = (mode_s1 == 2'd0) ? dac_sq  :   // 满幅方波（默认）
                           (mode_s1 == 2'd1) ? dac_mel :   // 小星星
                                               32'd0;      // 静音

    // ---------- ES8388 收发控制（内部含 I2C 配置 + I2S 收发）----------
    wire [31:0] adc_data;
    wire        rx_done, tx_done;
    wire        cfg_done;
    wire        cfg_ack_err;
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
        .cfg_done  (cfg_done),
        .cfg_ack_err(cfg_ack_err)
    );

    // ---------- BCLK 心跳检测（50MHz 域）----------
    // ES8388 是主机：配置成功后它必须自己吐出 BCLK（3.073MHz）。
    // 没有耳机时，"芯片有没有在跑"只能靠这个来判断。
    reg [2:0] bclk_sync;
    always @(posedge clk or negedge por_rst_n)
        if (!por_rst_n) bclk_sync <= 3'b000;
        else            bclk_sync <= {bclk_sync[1:0], aud_bclk};
    wire bclk_edge = bclk_sync[2] ^ bclk_sync[1];

    // 看门狗：1ms 内没有任何 BCLK 翻转就判定"芯片没起振"
    reg [17:0] bclk_wd;
    always @(posedge clk or negedge por_rst_n)
        if (!por_rst_n)        bclk_wd <= 18'd0;
        else if (bclk_edge)    bclk_wd <= 18'd0;
        else if (bclk_wd != 18'h3FFFF) bclk_wd <= bclk_wd + 1'b1;
    wire bclk_alive = (bclk_wd < 18'd50000);      // 50MHz 下 50000 = 1ms

    // ---------- LED ----------
    // D7（丝印 LED4）：PLL 锁定，常亮 = MCLK 12.288MHz 已产生
    assign led[0] = pll_locked;

    // E8（丝印 LED3）：链路分诊，四档（排查问题时全靠它）
    //   慢闪 ~1.5Hz = 24 个寄存器还没写完（正常只出现一两秒）
    //   中闪 ~6Hz   = 芯片没应答（ACK 错，固件每 0.5s 自动重试）
    //                 → 查 3.3V/GND、SCL/SDA 是否接反或接触不良
    //   快闪 ~24Hz  = 芯片应答了、寄存器写进去了，但 BCLK 没出来
    //                 → 查模块 10 脚(SCLK)到 J6 pin6 的线
    //   常亮        = 全 ACK 正常 + BCLK 有跳动 → 耳机应有《小星星》
    wire slow_blink = hb_cnt[25];            // ~1.5Hz
    wire mid_blink  = hb_cnt[23];            // ~6Hz
    wire fast_blink = hb_cnt[21];            // ~24Hz
    assign led[1] = !cfg_done     ? slow_blink :
                    cfg_ack_err   ? mid_blink  :
                    !bclk_alive   ? fast_blink : 1'b1;

    reg [25:0] hb_cnt = 26'd0;
    always @(posedge clk) hb_cnt <= hb_cnt + 1'b1;

endmodule
