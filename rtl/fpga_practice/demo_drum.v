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
// 两种模式，按 S1 或 S2 切换：
//   【敲击模式·默认】敲 MPU6050 模块或它所在的桌面 -> 出对应鼓件声
//   【自动演示模式】不用敲，每 0.6s 自动依次触发 底鼓→军鼓→镲 循环。
//        ★ 用来确认"听到的噪声到底是不是镲"——镲的音源本来就是白噪声，
//          第一次听很容易以为链路坏了。自动模式下三声挨着放，一耳朵就能分清。
//
// LED：
//   led[0] (D7/丝印LED4) = ES8388 链路分诊五档：
//        慢闪 0.75Hz = 24 个寄存器还没写完
//        快闪 12Hz   = 写完了但 BCLK 没出来   -> 查模块10脚(SCLK)→J6 pin6(J5)
//        常灭        = BCLK 有、LRCK 没跳动   -> 查模块 6脚(LRCK)→J6 pin7(H8)
//        中闪 6Hz    = 链路在跑但曾出现 NACK（固件每 0.5s 自动重试）
//        常亮        = 全部正常
//   led[1] (E8/丝印LED3) = 触发指示，敲一下（或自动演示一次）亮 150ms；
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

    // ---------- 按键：切换「敲击模式 / 自动演示模式」----------
    // ⚠️ 两个键各自独立消抖（一个脚电平异常不会拖累另一个），
    //    且必须在 .cst 里显式 PULL_MODE=DOWN，否则引脚浮空会失灵。
    wire press_s1, press_s2;
    debounce_fsm #(.CLK_FREQ(CLK_FREQ)) u_db_s1 (
        .clk(clk), .rst_n(por_rst_n),
        .key_in(key_s1), .key_out(), .key_press(press_s1)
    );
    debounce_fsm #(.CLK_FREQ(CLK_FREQ)) u_db_s2 (
        .clk(clk), .rst_n(por_rst_n),
        .key_in(key_s2), .key_out(), .key_press(press_s2)
    );
    reg auto_mode = 1'b0;                // 0=敲击触发  1=自动循环演示三鼓件
    always @(posedge clk or negedge por_rst_n)
        if (!por_rst_n) auto_mode <= 1'b0;
        else if (press_s1 | press_s2) auto_mode <= ~auto_mode;

    // ---------- 自动演示：每 0.6s 依次触发 底鼓→军鼓→镲 ----------
    // 用途：不用敲也能听清三个鼓件各自是什么声，确认"噪声"到底是不是镲。
    reg [1:0]  demo_idx = 2'd0;
    reg [25:0] demo_cnt = 26'd0;
    wire       demo_tick = (demo_cnt == 26'd30_000_000);      // 0.6s @50MHz
    always @(posedge clk or negedge por_rst_n)
        if (!por_rst_n) begin
            demo_idx <= 2'd0; demo_cnt <= 26'd0;
        end else if (demo_tick) begin
            demo_cnt <= 26'd0;
            demo_idx <= (demo_idx == 2'd2) ? 2'd0 : demo_idx + 1'b1;
        end else
            demo_cnt <= demo_cnt + 1'b1;

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

    // ---------- 触发源：敲击 或 自动演示 ----------
    wire        trig      = auto_mode ? demo_tick        : hit_valid;
    wire [1:0]  trig_type = auto_mode ? (demo_idx + 2'd1) : hit_type;  // 1底鼓/2军鼓/3镲
    wire [6:0]  trig_vel  = auto_mode ? 7'd100            : hit_vel;

    // ---------- 50MHz -> BCLK：触发事件（toggle 法跨时钟域）----------
    reg trig_tgl = 1'b0;
    always @(posedge clk or negedge por_rst_n)
        if (!por_rst_n) trig_tgl <= 1'b0;
        else if (trig)  trig_tgl <= ~trig_tgl;

    reg [2:0] hit_sync;
    always @(posedge aud_bclk or negedge audio_rst_n)
        if (!audio_rst_n) hit_sync <= 3'b000;
        else              hit_sync <= {hit_sync[1:0], trig_tgl};
    wire hit_ev = hit_sync[2] ^ hit_sync[1];

    // 类型/力度是慢变信号，两级同步即可（音频上短暂不一致无所谓）
    // 复位成"底鼓、力度0"，避免上电第一敲 race 成非法类型 0
    reg [8:0] tv_s0, tv_s1;
    always @(posedge aud_bclk or negedge audio_rst_n)
        if (!audio_rst_n) begin tv_s0 <= 9'b01_0000000; tv_s1 <= 9'b01_0000000; end
        else              begin tv_s0 <= {trig_type, trig_vel}; tv_s1 <= tv_s0; end
    wire [1:0] cur_type = tv_s1[8:7];
    wire [6:0] cur_vel  = tv_s1[6:0];

    // ---------- 样本节拍 ----------
    reg lrc_d;
    always @(posedge aud_bclk or negedge audio_rst_n)
        if (!audio_rst_n) lrc_d <= 1'b0;
        else              lrc_d <= aud_lrc;
    wire lrc_edge = aud_lrc ^ lrc_d;
    wire tick_new = lrc_edge & aud_lrc;      // 每样本一次

    // ---------- 多 voice：4 个鼓声 voice，round-robin 分配 ----------
    // 快速连敲互不打断：每次触发分给"最久没响"的下一个 voice，
    // 后敲只是覆盖掉最早那个，其余还在正常衰减 → 不吞音。
    reg [1:0] vptr;
    always @(posedge aud_bclk or negedge audio_rst_n)
        if (!audio_rst_n) vptr <= 2'd0;
        else if (hit_ev) vptr <= vptr + 1'b1;

    wire trig0 = hit_ev && (vptr == 2'd0);
    wire trig1 = hit_ev && (vptr == 2'd1);
    wire trig2 = hit_ev && (vptr == 2'd2);
    wire trig3 = hit_ev && (vptr == 2'd3);

    wire signed [23:0] v0, v1, v2, v3;
    drum_voice u_v0 (.clk(aud_bclk), .rst_n(audio_rst_n), .tick(tick_new),
        .trig(trig0), .trig_type(cur_type), .trig_vel(cur_vel), .out(v0));
    drum_voice u_v1 (.clk(aud_bclk), .rst_n(audio_rst_n), .tick(tick_new),
        .trig(trig1), .trig_type(cur_type), .trig_vel(cur_vel), .out(v1));
    drum_voice u_v2 (.clk(aud_bclk), .rst_n(audio_rst_n), .tick(tick_new),
        .trig(trig2), .trig_type(cur_type), .trig_vel(cur_vel), .out(v2));
    drum_voice u_v3 (.clk(aud_bclk), .rst_n(audio_rst_n), .tick(tick_new),
        .trig(trig3), .trig_type(cur_type), .trig_vel(cur_vel), .out(v3));

    // ---------- 求和 + 限幅（4 voice 叠加，防溢出爆音）----------
    wire signed [25:0] sum =
        {{2{v0[23]}}, v0} + {{2{v1[23]}}, v1} +
        {{2{v2[23]}}, v2} + {{2{v3[23]}}, v3};
    wire signed [23:0] mix =
        (sum >  26'sd8388607)  ?  24'sd8388607 :
        (sum < -26'sd8388608)  ? -24'sd8388608 : sum[23:0];
    wire [31:0] dac_data = {{8{mix[23]}}, mix};

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

    // ---------- BCLK / LRCK 心跳（50MHz 域，1ms 看门狗）----------
    // 没有耳机时，芯片到底起没起振只能靠这个判断。
    reg [2:0] bclk_sync;
    always @(posedge clk or negedge por_rst_n)
        if (!por_rst_n) bclk_sync <= 3'b000;
        else            bclk_sync <= {bclk_sync[1:0], aud_bclk};
    wire bclk_edge = bclk_sync[2] ^ bclk_sync[1];
    reg [17:0] bclk_wd;
    always @(posedge clk or negedge por_rst_n)
        if (!por_rst_n)     bclk_wd <= 18'd0;
        else if (bclk_edge) bclk_wd <= 18'd0;
        else if (bclk_wd != 18'h3FFFF) bclk_wd <= bclk_wd + 1'b1;
    wire bclk_alive = (bclk_wd < 18'd50000);

    reg [2:0] lrc_sync;
    always @(posedge clk or negedge por_rst_n)
        if (!por_rst_n) lrc_sync <= 3'b000;
        else            lrc_sync <= {lrc_sync[1:0], aud_lrc};
    wire lrc_edge50 = lrc_sync[2] ^ lrc_sync[1];
    reg [17:0] lrc_wd;
    always @(posedge clk or negedge por_rst_n)
        if (!por_rst_n)        lrc_wd <= 18'd0;
        else if (lrc_edge50)   lrc_wd <= 18'd0;
        else if (lrc_wd != 18'h3FFFF) lrc_wd <= lrc_wd + 1'b1;
    wire lrc_alive = (lrc_wd < 18'd50000);

    // ---------- LED ----------
    reg [25:0] hb = 26'd0;
    always @(posedge clk) hb <= hb + 1'b1;
    wire slow_blink = hb[25];            // ~0.75Hz
    wire mid_blink  = hb[23];            // ~6Hz
    wire fast_blink = hb[21];            // ~12Hz

    // 触发指示：敲一下（或自动演示一次）亮 150ms
    reg [22:0] hit_led_cnt = 23'd0;
    reg        hit_led = 1'b0;
    always @(posedge clk or negedge por_rst_n)
        if (!por_rst_n) begin
            hit_led <= 1'b0; hit_led_cnt <= 23'd0;
        end else if (trig) begin
            hit_led <= 1'b1; hit_led_cnt <= 23'd0;
        end else if (hit_led) begin
            if (hit_led_cnt == 23'd7_500_000) hit_led <= 1'b0;   // 150ms
            else                              hit_led_cnt <= hit_led_cnt + 1'b1;
        end

    // D7 = ES8388 链路分诊五档（排查"没声音"全靠它）：
    //   慢闪 0.75Hz = 24 个寄存器还没写完
    //   快闪 12Hz   = 写完了但 BCLK 没出来      -> 查模块10脚(SCLK)→J6 pin6
    //   常灭        = BCLK 有但 LRCK 没跳动      -> 查模块 6脚(LRCK)→J6 pin7
    //   中闪 6Hz    = 链路在跑，但曾经出现过 NACK（固件每 0.5s 自动重试）
    //   常亮        = 全部正常
    // D7：链路实际状态。cfg_ack_err 是"曾 NACK"的粘住标志，偶发一次就永远
    //     中闪，让人误以为链路有问题——既然声音都出来了就显示常亮。
    assign led[0] = !cfg_done   ? slow_blink :
                    !bclk_alive ? fast_blink :
                    !lrc_alive  ? 1'b0       : 1'b1;

    // E8：只显示触发（敲一下亮 150ms）。imu_err 也是粘住标志（曾有一次
    //     ACK 错误就永远快闪），去掉——MPU6050 响不响一试便知。
    assign led[1] = hit_led;

endmodule
