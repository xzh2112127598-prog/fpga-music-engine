//============================================================
// 板上整合顶层：4 种 LED 效果一次演示
//   led[0]：1Hz 闪烁
//   led[1]：呼吸灯
//   led[2]：每按一次键翻转（保持）
//   led[3]：按住时常亮
// 过关标志：本工程能下板运行，且 4 个练习都在 ModelSim 中看过波形
//============================================================
module led_top #(
    parameter integer CLK_FREQ = 24_000_000     // !!按板子改：Nano 20K=27_000_000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       key,        // 板载按键，多数 Tang 板为“低有效”
    output wire [3:0] led
);
    // 低有效按键 -> 统一成“高=按下”；若你的按键高有效，删掉下面取反
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
        if (!rst_n) flash <= 1'b0;
        else if (tick_1hz) flash <= ~flash;

    // led[2]：按键一次翻转一次
    reg hold = 1'b0;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) hold <= 1'b0;
        else if (key_press) hold <= ~hold;

    assign led[0] = flash;
    assign led[1] = pwm;
    assign led[2] = hold;
    assign led[3] = key_out;
endmodule
