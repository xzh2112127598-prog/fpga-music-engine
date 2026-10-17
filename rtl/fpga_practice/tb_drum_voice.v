`timescale 1ns/1ps
//============================================================
// tb_drum_voice.v —— 单独验证 drum_voice 是否有声音输出
// 编译：iverilog -g2012 -o tb_drum_voice.vvp tb_drum_voice.v ../src/drum_voice.v
//============================================================
module tb_drum_voice;

    reg        clk = 0, rst_n = 0, tick = 0, trig = 0;
    reg [1:0]  trig_type = 2'd1;      // 底鼓
    reg [6:0]  trig_vel  = 7'd100;    // 中等力度
    wire signed [23:0] out;

    drum_voice u (
        .clk(clk), .rst_n(rst_n), .tick(tick), .trig(trig),
        .trig_type(trig_type), .trig_vel(trig_vel), .out(out)
    );

    always #5 clk = ~clk;              // 100MHz（任意，只驱动状态机）

    // 每 48 个 clk 一个 tick（模拟 48 BCLK = 1 个音频样本）
    reg [5:0] tcnt = 0;
    always @(posedge clk) begin
        if (tcnt == 47) begin tcnt <= 0; tick <= 1; end
        else            begin tcnt <= tcnt + 1; tick <= 0; end
    end

    integer nonzero = 0, peak = 0, peak_t = 0;
    always @(posedge clk) begin
        if (out != 0) begin
            nonzero = nonzero + 1;
            if (out > peak)  begin peak = out;  peak_t = $time; end
            if (-out > peak) begin peak = -out; peak_t = $time; end
        end
    end

    // 打印前若干样本的 out（在每个 tick 后的下一个 clk 看）
    integer n = 0;
    always @(posedge clk) begin
        if (tick && n < 10) begin
            $display("sample %0d: out=%0d  env=%0d  env8=%0d  vgain=%0d  gain=%0d  type=%0d",
                     n, out, u.env, u.env8, u.vgain, u.gain, u.type_r);
            n = n + 1;
        end
    end

    initial begin
        #10 rst_n = 1;
        // 等第一个 tick 触发
        #200;                 // 20 个 clk，tcnt 接近触发点
        trig = 1; #10; trig = 0;
        #3_000_000;           // 跑 ~3ms（约 1300 样本）
        $display("==== 结果 ====");
        $display("非零样本数 = %0d", nonzero);
        $display("峰值 = %0d @ t=%0dns", peak, peak_t);
        if (nonzero > 10) $display("✅ 有声音输出");
        else              $display("❌ 几乎没有输出，找 bug");
        $finish;
    end

endmodule
