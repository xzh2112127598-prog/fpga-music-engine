`timescale 1ns/1ps
//============================================================
// demo_mpu.v —— MPU6050（GY-521）上板验证：I2C 链路 + 加速度读数
//
// 接线（Dock 上边缘最左的 PMOD = J6，pin1 是方形焊盘）：
//   VCC -> pin1 或 pin2 (3V3)
//   GND -> pin3 或 pin4
//   SCL -> pin12  (FPGA 球号 G5)
//   SDA -> pin11  (FPGA 球号 F5)
//   XDA/XCL/AD0/INT 全部悬空不接
//
// 现象（不用串口，只看板上 3 个 LED）：
//   led[1] (D7) 【最重要，已确认会亮的灯】综合状态：
//        常亮   = 一切正常（静止时合加速度 ≈ 1g）          <- 你要的结果
//        1Hz 慢闪 = I2C 起来了但读数不对（全 0/全 1，或量程错）
//        8Hz 快闪 = 出现过 ACK 错误（接线/电源/地址问题）
//        全灭   = 还在上电初始化（100ms 内）
//   led[0] (L6) 心跳：ready 之后 1Hz 闪，证明 1kHz 采样在持续进行
//   led[2] (E8) 晃动/敲击：有突变就亮 150ms，敲一下闪一下
//        按住 S2(key2)：改成显示 X 轴倾斜方向（ax 符号位），确认单轴真在变
//        按住 S1(key) ：阈值降到 1/4，更灵敏
//
// 判读顺序：D7 常亮 -> 敲桌子 E8 闪 -> 按住 S2 转模块 E8 跟着翻。
// 三步全过，说明 MPU6050 + I2C + 采样率 这条链路完全打通。
//============================================================
module demo_mpu #(
    parameter integer CLK_FREQ    = 50_000_000,   // Tang Primer 25K 板载 50MHz
    parameter integer SAMPLE_RATE = 1000,         // 加速度采样率
    // ±16g 量程下 1g = 2048 LSB。静止时三轴绝对值之和在 2048~3547 之间
    // （2048 = 正好对齐某一轴，3547 = 与三轴各成 54.7°），取宽松边界
    parameter integer MAG_LO      = 1500,
    parameter integer MAG_HI      = 3800,
    parameter integer TAP_TH      = 1200          // 三轴变化量之和的阈值（LSB）
)(
    input  wire       clk,      // E2, 50MHz
    input  wire       key,      // K6, 低有效（按下=0）-> 高灵敏度
    input  wire       key2,     // H11, 高有效（按下=1）-> 倾斜显示模式
    output wire [2:0] led,      // L6 / D7 / E8
    output wire       scl,      // J6 pin12 = G5
    inout  wire       sda       // J6 pin11 = F5
);

    localparam integer STRETCH = CLK_FREQ / 1000 * 150;   // 敲击指示展宽 150ms

    // ---------- 内部上电复位 ----------
    reg [19:0] por_cnt = 20'd0;
    reg        rst_n   = 1'b0;
    always @(posedge clk) begin
        if (&por_cnt) rst_n <= 1'b1;
        else begin por_cnt <= por_cnt + 20'd1; rst_n <= 1'b0; end
    end

    // ---------- MPU6050 驱动 ----------
    wire [15:0] ax, ay, az;
    wire        sample_valid, ready, ack_err;

    mpu6050_reader #(
        .CLK_FREQ    (CLK_FREQ),
        .SAMPLE_RATE (SAMPLE_RATE)
    ) u_mpu (
        .clk          (clk),
        .rst_n        (rst_n),
        .scl          (scl),
        .sda          (sda),
        .ax           (ax),
        .ay           (ay),
        .az           (az),
        .sample_valid (sample_valid),
        .ready        (ready),
        .err          (ack_err)
    );

    // ---------- 锁存当前值与上一拍值，算变化量 ----------
    reg signed [15:0] ax_r, ay_r, az_r;
    reg signed [15:0] ax_p, ay_p, az_p;
    reg               d_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ax_r <= 16'sd0; ay_r <= 16'sd0; az_r <= 16'sd0;
            ax_p <= 16'sd0; ay_p <= 16'sd0; az_p <= 16'sd0;
            d_valid <= 1'b0;
        end else begin
            d_valid <= sample_valid;              // 延后一拍，此时 *_r / *_p 都已稳定
            if (sample_valid) begin
                ax_p <= ax_r; ay_p <= ay_r; az_p <= az_r;
                ax_r <= ax;   ay_r <= ay;   az_r <= az;
            end
        end
    end

    function [15:0] absv;
        input signed [15:0] v;
        begin
            absv = v[15] ? -v : v;
        end
    endfunction

    wire [17:0] mag  = absv(ax_r) + absv(ay_r) + absv(az_r);
    wire [17:0] dsum = absv(ax_r - ax_p) + absv(ay_r - ay_p) + absv(az_r - az_p);

    // ---------- led[1]：静止时合加速度 ≈ 1g ----------
    wire level_ok = (mag >= MAG_LO) && (mag <= MAG_HI);

    // ---------- led[2]：敲击指示（展宽 150ms 便于肉眼观察）----------
    wire key_pressed  = ~key;                     // K6 低有效
    wire [17:0] th    = key_pressed ? TAP_TH/4 : TAP_TH;
    wire        tap_hit = (dsum >= th);

    reg [23:0] tap_cnt = 24'd0;
    reg        tap_led = 1'b0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tap_cnt <= 24'd0; tap_led <= 1'b0;
        end else if (d_valid && tap_hit) begin
            tap_cnt <= STRETCH[23:0];
            tap_led <= 1'b1;
        end else if (tap_cnt != 24'd0) begin
            tap_cnt <= tap_cnt - 24'd1;
            if (tap_cnt == 24'd1) tap_led <= 1'b0;
        end
    end

    // ---------- 两个闪烁基准：fast = 8Hz（报警），slow = 1Hz（心跳）----------
    // 基准 tick = 16Hz：fast 每 tick 翻一次 -> 8Hz 闪；slow 每 8 个 tick 翻一次 -> 1Hz 闪
    reg [24:0] tick_cnt = 25'd0;
    reg [2:0]  div8     = 3'd0;
    reg        fast     = 1'b0;
    reg        slow     = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_cnt <= 25'd0; div8 <= 3'd0; fast <= 1'b0; slow <= 1'b0;
        end else if (tick_cnt >= CLK_FREQ/16 - 25'd1) begin
            tick_cnt <= 25'd0;
            fast     <= ~fast;
            div8     <= div8 + 3'd1;
            if (div8 == 3'd7) slow <= ~slow;
        end else begin
            tick_cnt <= tick_cnt + 25'd1;
        end
    end

    // ---------- LED 输出 ----------
    // 关键状态全部压到 led[1](D7)：这是已经确认会亮的那个灯
    //   !ready  -> 灭（还在上电初始化）
    //   有 ACK 错误 -> 8Hz 快闪（接线/电源/地址问题）
    //   数据不合理 -> 1Hz 慢闪（读到全 0 / 全 1，或量程不对）
    //   一切正常   -> 常亮（静止时合加速度 ≈ 1g）
    assign led[0] = ready ? slow : 1'b0;                                  // 1Hz 心跳
    assign led[1] = !ready  ? 1'b0 :                                      // 综合状态
                    ack_err ? fast :
                    level_ok ? 1'b1 : slow;
    assign led[2] = key2 ? ax_r[15] : tap_led;                            // 倾斜 / 敲击

endmodule
