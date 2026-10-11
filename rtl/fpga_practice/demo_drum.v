//============================================================
// demo_drum.v —— 电子鼓：MPU6050 敲击 -> 鼓件合成 -> ES8388 耳机出声
//
// 这是 demo_es8388（链路验证）之后的真正功能版本：
//   1) MPU6050 以 1000Hz 读三轴加速度（±16g，1g = 2048 LSB）
//   2) hit_detector 检测敲击，给出 hit_type(1底鼓/2军鼓/3镲) + hit_vel(0..127)
//   3) BCLK 域按类型合成鼓声，24bit I2S 送给 ES8388
//
// ★ 为什么要两块 I2C 总线：
//   ES8388(0x10) 和 MPU6050(0x68) 都是 I2C 从机，如果两个主机同时驱动
//   G5/F5 会直接打架。与其做总线仲裁，不如让 MPU6050 搬到旁边空闲的
//   J5 排针（SCL=A10 / SDA=A11），两组 I2C 物理独立，零风险、零逻辑开销。
//
// 接线：
//   ES8388  —— 走 J6（保持 demo_es8388 的接法不变）
//   MPU6050 —— 走 J5：VCC=pin1/2(3V3)  GND=pin3/4  SCL=pin12(A10)  SDA=pin11(A11)
//
// LED：
//   led[0] (D7/丝印LED4) = ES8388 链路。常亮=OK，慢闪=还没配好
//   led[1] (E8/丝印LED3) = 敲击指示，敲一下亮 150ms；
//                          MPU6050 出 ACK 错误时改成快闪
//
// ⚠️ 板载按键必须在 .cst 里显式 PULL_MODE=DOWN（见 demo_drum.cst 注释），
//    只写 IO_LOC 会浮空 -> 按一次有效、之后怎么按都没反应。
//============================================================
module demo_drum #(
    parameter integer CLK_FREQ = 50_000_000
)(
    input  wire       clk,          // E2, 50MHz
    input  wire       key_s1,       // H11 —— 丝印 S1（预留：切换鼓组/灵敏度）
    input  wire       key_s2,       // H10 —— 丝印 S2
    output wire [1:0] led,          // [0]=D7  [1]=E8

    // ---- ES8388：J6 PMOD ----
    output wire       aud_mclk,     // H5  J6 pin5
    input  wire       aud_bclk,     // J5  J6 pin6  （芯片 -> FPGA）
    input  wire       aud_lrc,      // H8  J6 pin7  （芯片 -> FPGA）
    output wire       aud_dacdat,   // H7  J6 pin8
    input  wire       aud_adcdat,   // G7  J6 pin9
    output wire       aud_scl,      // G5  J6 pin12
    inout  wire       aud_sda,      // F5  J6 pin11

    // ---- MPU6050：J5 PMOD（独立 I2C，避开总线仲裁）----
    output wire       imu_scl,      // A10 J5 pin12
    inout  wire       imu_sda       // A11 J5 pin11
);

    // ---------- 上电复位（50MHz 域）----------
    reg [15:0] por_cnt = 16'd0;
    reg        por_rst_n = 1'b0;
    always @(posedge clk)
        if (&por_cnt) por_rst_n <= 1'b1;
        else          por_cnt  <= por_cnt + 1'b1;

    // ---------- PLL：50M -> 12.288M MCLK ----------
    wire pll_locked;
    es8388_audio_pll u_pll (
        .clkin  (clk),
        .clkout (aud_mclk),
        .locked (pll_locked)
    );
    wire audio_rst_n = por_rst_n & pll_locked;

    // ---------- MPU6050（50MHz 域，独立 I2C）----------
    wire [15:0] ax, ay, az;
    wire        imu_valid, imu_ready, imu_err;
    mpu6050_reader #(
        .CLK_FREQ    (CLK_FREQ),
        .SAMPLE_RATE (1000)
    ) u_imu (
        .clk          (clk),
        .rst_n        (por_rst_n),
        .scl          (imu_scl),
        .sda          (imu_sda),
        .ax           (ax),
        .ay           (ay),
        .az           (az),
        .sample_valid (imu_valid),
        .ready        (imu_ready),
        .err          (imu_err)
    );

    // ---------- 敲击检测（50MHz 域）----------
    wire       hit_valid;
    wire [1:0] hit_type;      // 1=底鼓 2=军鼓 3=镲
    wire [6:0] hit_vel;       // 0..127
    hit_detector #(
        .LSBG     (2048),     // ±16g 下 1g = 2048 LSB
        .IMU_RATE (1000),
        .WIN_MS   (5),
        .REFR_MS  (100)
    ) u_hit (
        .clk          (clk),
        .rst_n        (por_rst_n),
        .sample_valid (imu_valid),
        .ax           (ax),
        .ay           (ay),
        .az           (az),
        .hit_valid    (hit_valid),
        .hit_type     (hit_type),
        .hit_vel      (hit_vel)
    );

    // =========================================================
    // 以下全部在 BCLK 域（2.304MHz = 48kHz × 2ch × 24bit）
    // =========================================================

    // ---------- 50MHz -> BCLK：敲击事件（toggle 法跨时钟域）----------
    reg hit_tgl = 1'b0;
    always @(posedge clk or negedge por_rst_n)
        if (!por_rst_n) hit_tgl <= 1'b0;
        else if (hit_valid) hit_tgl <= ~hit_tgl;

    reg [2:0] hit_sync;
    always @(posedge aud_bclk or negedge audio_rst_n)
        if (!audio_rst_n) hit_sync <= 3'b000;
        else              hit_sync <= {hit_sync[1:0], hit_tgl};
    wire hit_ev = hit_sync[2] ^ hit_sync[1];

    // 类型/力度是慢变信号，两级同步即可（音频上短暂不一致无所谓）
    reg [8:0] tv_s0, tv_s1;
    always @(posedge aud_bclk or negedge audio_rst_n)
        if (!audio_rst_n) begin tv_s0 <= 9'd0; tv_s1 <= 9'd0; end
        else              begin tv_s0 <= {hit_type, hit_vel}; tv_s1 <= tv_s0; end
    wire [1:0] cur_type = tv_s1[8:7];
    wire [6:0] cur_vel  = tv_s1[6:0];

    // ---------- 样本节拍 ----------
    reg lrc_d;
    always @(posedge aud_bclk or negedge audio_rst_n)
        if (!audio_rst_n) lrc_d <= 1'b0;
        else              lrc_d <= aud_lrc;
    wire lrc_edge = aud_lrc ^ lrc_d;
    wire tick_new = lrc_edge & aud_lrc;      // 每样本一次

    // ---------- 音源：DDS 正弦 + LFSR 噪声 ----------
    // FTW = round(f × 2^32 / 48000.53)
    localparam [31:0] FTW_KICK  = 32'd5368656;    // 底鼓 60Hz
    localparam [31:0] FTW_SNARE = 32'd16105968;   // 军鼓 180Hz

    reg [31:0] m_ftw;
    always @(posedge aud_bclk or negedge audio_rst_n)
        if (!audio_rst_n) m_ftw <= FTW_KICK;
        else if (hit_ev)  m_ftw <= (cur_type == 2'd2) ? FTW_SNARE : FTW_KICK;

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

    reg [16:0] lfsr = 17'h1;
    always @(posedge aud_bclk or negedge audio_rst_n)
        if (!audio_rst_n)      lfsr <= 17'h1;
        else if (tick_new)     lfsr <= {lfsr[15:0], lfsr[16] ^ lfsr[13]};
    wire signed [15:0] noise = {1'b0, lfsr[15:1]};   // 小幅白噪声

    // ---------- 包络：指数衰减（每样本减 1/2^shift）----------
    //   shift=10 -> tau≈1024 样本≈21ms，衰减到 -40dB 约 200ms（底鼓）
    //   shift=9  -> 军鼓更短促
    //   shift=11 -> 镲更绵长
    reg [16:0] env = 17'd0;
    reg [3:0]  decay_sh = 4'd10;
    wire [16:0] dec = (env >> decay_sh) | 17'd1;     // 至少减 1，否则会卡住不掉
    always @(posedge aud_bclk or negedge audio_rst_n)
        if (!audio_rst_n) begin
            env <= 17'd0; decay_sh <= 4'd10;
        end else if (hit_ev) begin
            env <= 17'd131071;                        // 满幅起音
            case (cur_type)
                2'd1:     decay_sh <= 4'd10;          // 底鼓
                2'd2:     decay_sh <= 4'd9;           // 军鼓
                default:  decay_sh <= 4'd11;          // 镲
            endcase
        end else if (tick_new && env != 0) begin
            env <= (env > dec) ? (env - dec) : 17'd0;
        end

    // ---------- 混合：底鼓纯正弦 / 军鼓正弦+噪声 / 镲纯噪声 ----------
    wire signed [15:0] src = (cur_type == 2'd1) ? dds_out                    :
                             (cur_type == 2'd2) ? (dds_out >>> 1) + (noise >>> 1) :
                                                  (noise >>> 1);

    // ---------- 幅度 = 包络(0..255) × 力度(0..254) ----------
    wire [7:0] env8     = env[16:9];
    wire [8:0] vel_gain = {cur_vel, 1'b0};            // 0..254
    wire [8:0] gain     = (env8 * vel_gain) >> 8;     // 0..253
    wire signed [24:0] prod25 = src * {1'b0, gain};
    wire signed [23:0] tone24 = prod25[23:0];
    wire [31:0] dac_data = {{8{tone24[23]}}, tone24};

    // ---------- ES8388 收发 ----------
    wire [31:0] adc_data;
    wire        rx_done, tx_done, cfg_done, cfg_ack_err;
    es8388_ctrl #(
        .WL (6'd24)
    ) u_ctrl (
        .clk        (clk),
        .rst_n      (audio_rst_n),
        .aud_bclk   (aud_bclk),
        .aud_lrc    (aud_lrc),
        .aud_adcdat (aud_adcdat),
        .aud_dacdat (aud_dacdat),
        .aud_scl    (aud_scl),
        .aud_sda    (aud_sda),
        .adc_data   (adc_data),
        .dac_data   (dac_data),
        .rx_done    (rx_done),
        .tx_done    (tx_done),
        .cfg_done   (cfg_done),
        .cfg_ack_err(cfg_ack_err)
    );

    // ---------- LED ----------
    reg [25:0] hb = 26'd0;
    always @(posedge clk) hb <= hb + 1'b1;
    wire slow_blink = hb[25];            // ~0.75Hz
    wire fast_blink = hb[21];            // ~12Hz

    // 敲击指示：敲一下亮 150ms
    reg [22:0] hit_led_cnt = 23'd0;
    reg        hit_led = 1'b0;
    always @(posedge clk or negedge por_rst_n)
        if (!por_rst_n) begin
            hit_led <= 1'b0; hit_led_cnt <= 23'd0;
        end else if (hit_valid) begin
            hit_led <= 1'b1; hit_led_cnt <= 23'd0;
        end else if (hit_led) begin
            if (hit_led_cnt == 23'd7_500_000) hit_led <= 1'b0;   // 150ms
            else                              hit_led_cnt <= hit_led_cnt + 1'b1;
        end

    wire es_ok = pll_locked & cfg_done & ~cfg_ack_err;
    assign led[0] = es_ok    ? 1'b1        : slow_blink;
    assign led[1] = imu_err  ? fast_blink  : hit_led;

endmodule
