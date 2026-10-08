//============================================================
// 板上整合顶层：3 个 LED 一次演示（Tang Primer 25K / 50MHz）
//   led[0]（L6）：1Hz 闪烁      -> 证明 50MHz 时钟和分频是对的
//   led[1]（D7）：呼吸灯 PWM    -> 证明时序逻辑是对的
//   led[2]（E8）：按一次键翻转   -> 证明消抖是对的（按键扫描的核心）
// 过关标志：本工程能下板运行，3 个灯都有正确现象。
//
// 为什么没有 rst_n 引脚：
//   板载只有 2 个按键，第 2 个的引脚不确定；给 rst_n 留一个悬空引脚，
//   Gowin 会自动给它随便分配一个脚，风险很大。所以改成"内部上电复位"：
//   上电后先把 rst_n 拉低约 1.3ms 再释放，效果一样且不用接任何东西。
//============================================================
module led_top #(
    parameter integer CLK_FREQ = 50_000_000     // Tang Primer 25K 板载 50MHz
)(
    input  wire       clk,        // E2，50MHz 有源晶振
    input  wire       key,        // K6，板载按键，低有效（按下=0）
    output wire [2:0] led         // L6 / D7 / E8，板载 3 个 LED
);
    // ---------- 内部上电复位（不需要外部引脚）----------
    // 上电后计数器从 0 数到全 1（65535 个周期 ≈ 1.3ms），期间 rst_n=0
    reg [15:0] por_cnt = 16'd0;
    reg        rst_n   = 1'b0;
    always @(posedge clk)
        if (&por_cnt) rst_n <= 1'b1;
        else          por_cnt <= por_cnt + 1'b1;

    // 低有效按键 -> 统一成"高=按下"（官方例程里写的是 if(!key)，即按下=0）
    wire key_high = ~key;

    wire tick_48k, tick_1hz;
    wire pwm;
    wire key_out, key_press;

    clk_tick #(.CLK_FREQ(CLK_FREQ)) u_tick (
        .clk(clk), .rst_n(rst_n),
        .tick_48k(tick_48k), .tick_1hz(tick_1hz)
    );

    breath_pwm u_bp (
        .clk(clk), .rst_n(rst_n), .pwm(pwm)
    );

    debounce_fsm #(.CLK_FREQ(CLK_FREQ)) u_db (
        .clk(clk), .rst_n(rst_n), .key_in(key_high),
        .key_out(key_out), .key_press(key_press)
    );

    // led[0]：1Hz 闪烁
    reg flash = 1'b0;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)          flash <= 1'b0;
        else if (tick_1hz)   flash <= ~flash;

    // led[2]：每按一次键翻转一次（验证消抖：抖 10 次也只翻转 1 次）
    reg hold = 1'b0;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)          hold <= 1'b0;
        else if (key_press)  hold <= ~hold;

    assign led[0] = flash;
    assign led[1] = pwm;
    assign led[2] = hold;

    // 想验证"按住时常亮"（key_out）的话，把上一行改成：
    //   assign led[2] = key_out;
endmodule
