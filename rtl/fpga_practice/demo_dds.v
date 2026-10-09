//============================================================
// demo_dds.v —— 把已验证的 DDS 振荡器搬上板（Tang Primer 25K）
//
// 目的：验证两件必须确认的事
//   1) 正弦波表能否被 Gowin 推断进 BSRAM
//      （GW5A Version A 没有分布式 RAM，ROM 只能放块 RAM）
//   2) DDS 频率字在真实 50MHz 时钟下是否准确
//
// 现象（不用任何外设，只看板上 3 个 LED）：
//   led[0]（L6）: DDS 输出的符号位 -> 精确按 1/2/3/4 Hz 闪烁
//                每按一次键换一档。闪烁得准 = DDS 和 ROM 都对
//   led[1]（D7）: 呼吸灯（时钟心跳，证明系统活着）
//   led[2]（E8）: 消抖后的按键电平（按住变、松开回，用来找按键）
//
// 两个按键都能用：K6（低有效）和 H11（高有效），按任意一个即可。
//============================================================
module demo_dds #(
    parameter integer CLK_FREQ = 50_000_000
)(
    input  wire       clk,      // E2, 50MHz
    input  wire       key,      // K6, 低有效（按下=0）
    input  wire       key2,     // H11, 高有效（按下=1）
    output wire [2:0] led
);
    // ---------- 内部上电复位 ----------
    reg [15:0] por_cnt = 16'd0;
    reg        rst_n   = 1'b0;
    always @(posedge clk)
        if (&por_cnt) rst_n <= 1'b1;
        else          por_cnt <= por_cnt + 1'b1;

    // ---------- 48kHz 采样节拍 ----------
    wire tick_48k, tick_1hz;
    clk_tick #(.CLK_FREQ(CLK_FREQ)) u_tick (
        .clk(clk), .rst_n(rst_n),
        .tick_48k(tick_48k), .tick_1hz(tick_1hz)
    );

    // ---------- 按键：两个并联，任意一个按下都算按下 ----------
    // K6 低有效取反；H11 高有效直接用
    wire trig_raw = (~key) | key2;

    wire db_out, db_press;
    debounce_fsm #(.CLK_FREQ(CLK_FREQ)) u_db (
        .clk(clk), .rst_n(rst_n), .key_in(trig_raw),
        .key_out(db_out), .key_press(db_press)
    );

    // ---------- 频率档位：每次按键换一档 ----------
    // FTW = round(f × 2^32 / 48000)
    //   1Hz -> 89478    2Hz -> 178957
    //   3Hz -> 268435   4Hz -> 357914
    localparam [31:0] FTW_1HZ = 32'd89478;
    localparam [31:0] FTW_2HZ = 32'd178957;
    localparam [31:0] FTW_3HZ = 32'd268435;
    localparam [31:0] FTW_4HZ = 32'd357914;

    reg [1:0] sel = 2'd0;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)        sel <= 2'd0;
        else if (db_press) sel <= sel + 2'd1;

    reg [31:0] ftw;
    always @* begin
        case (sel)
            2'd0:    ftw = FTW_1HZ;
            2'd1:    ftw = FTW_2HZ;
            2'd2:    ftw = FTW_3HZ;
            default: ftw = FTW_4HZ;
        endcase
    end

    // ---------- DDS 振荡器（与 MATLAB 黄金模型逐位一致的那个）----------
    wire signed [15:0] dds_out;
    wire               dds_v;

    osc_dds #(
        .PHASE_W  (32),
        .ADDR_W   (10),
        .DATA_W   (16),
        .IPOLATE  (1),
        .ROM_FILE ("sine_1024.hex")
    ) u_dds (
        .clk      (clk),
        .rst_n    (rst_n),
        .en       (tick_48k),
        .ftw      (ftw),
        .load     (1'b0),
        .phase_i  (32'd0),
        .out      (dds_out),
        .out_valid(dds_v),
        .phase_o  ()
    );

    // ---------- LED ----------
    // led[0]: 正弦波符号位 -> 50% 占空比方波，频率 = 设定频率
    reg dds_sign = 1'b0;
    always @(posedge clk)
        if (dds_v) dds_sign <= dds_out[15];

    // led[1]: 呼吸灯
    wire pwm;
    breath_pwm u_bp (.clk(clk), .rst_n(rst_n), .pwm(pwm));

    assign led[0] = dds_sign;   // 1/2/3/4 Hz 闪烁
    assign led[1] = pwm;        // 呼吸
    assign led[2] = db_out;     // 按住变、松开回

endmodule
