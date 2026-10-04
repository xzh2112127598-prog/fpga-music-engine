`timescale 1ns/1ps
//============================================================
// 练习3 仿真文件
// 仿真 50ms 即可看到 duty（亮度门限）开始缓慢变化、pwm 占空比改变。
// 想看完整呼吸循环可 run 2s（仿真器需要跑更久）。
//============================================================
module tb_breath_pwm;
    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    wire pwm;

    breath_pwm uut (.clk(clk), .rst_n(rst_n), .pwm(pwm));

    always #10 clk = ~clk;

    initial begin
        #25 rst_n = 1'b1;
        #50_000_000 $finish;   // 仿真 50ms
    end
endmodule
