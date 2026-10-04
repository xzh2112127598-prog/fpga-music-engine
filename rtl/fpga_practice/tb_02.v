`timescale 1ns/1ps
//============================================================
// 练习2 仿真文件
// 为了仿真快，把“系统时钟频率”参数缩小为 480_000：
//   tick_48k 每 10 个时钟拍出现一次；
//   tick_1hz 每 480_000 拍出现一次（仿真时间约 9.6ms）。
// 跑 10ms：run 10ms，应看到 tick_1hz 出现 1 次。
//============================================================
module tb_clk_tick;
    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    wire tick_48k, tick_1hz;

    clk_tick #(.CLK_FREQ(480_000)) uut (
        .clk(clk), .rst_n(rst_n),
        .tick_48k(tick_48k), .tick_1hz(tick_1hz)
    );

    always #10 clk = ~clk;       // 50MHz 仿真时钟

    initial begin
        #25  rst_n = 1'b1;
        #10_000_000 $finish;    // 共仿真 10ms
    end
endmodule
