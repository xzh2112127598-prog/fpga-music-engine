//============================================================
// 练习3：呼吸灯（PWM 脉冲宽度调制）
// 对应知识点：3(时序逻辑) 6(计数器)
// 原理：
//   pwm_cnt 每时钟 +1（0~255 循环），决定 256 级亮度；
//   duty 是“亮度门限”，pwm_cnt < duty 时灯亮 -> duty 越大灯越亮；
//   duty 在 0~255 之间缓慢往复（三角波），灯就有呼吸效果。
//============================================================
module breath_pwm (
    input  wire clk,
    input  wire rst_n,
    output wire pwm
);
    reg [7:0] pwm_cnt = 8'd0;   // PWM 快计数器
    reg [7:0] duty    = 8'd0;   // 当前亮度门限
    reg       dir     = 1'b1;   // 1=变亮  0=变暗
    reg [8:0] div     = 9'd0;   // 放慢 duty 变化速度

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_cnt <= 8'd0; duty <= 8'd0; dir <= 1'b1; div <= 9'd0;
        end else begin
            pwm_cnt <= pwm_cnt + 1'b1;

            // 每 256 个时钟为一个 PWM 周期
            if (pwm_cnt == 8'd255) begin
                if (div == 9'd365) begin       // 再放慢 366 倍：约 2 秒一个呼吸循环
                    div <= 9'd0;
                    if (dir)
                        duty <= duty + 1'b1;   // 变亮
                    else
                        duty <= duty - 1'b1;   // 变暗

                    if (duty == 8'd254) dir <= 1'b0;  // 接近最亮，准备变暗
                    if (duty == 8'd1)   dir <= 1'b1;  // 接近最暗，准备变亮
                end else begin
                    div <= div + 1'b1;
                end
            end
        end
    end

    assign pwm = (pwm_cnt < duty);
endmodule
