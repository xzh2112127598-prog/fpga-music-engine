`timescale 1ns/1ps
//============================================================
// 练习4 仿真文件
// 把 CLK_FREQ 缩小为 1000 -> 只需稳定 10 个时钟拍(200ns)即确认。
// 测试过程：
//   1) 按下抖动：150ns 短脉冲（< 200ns，不应确认）-> 低 -> 稳定高
//   2) 稳定按住 30us：应看到 key_press 单脉冲、key_out 变高
//   3) 释放抖动：150ns 回弹 -> 稳定低，key_out 最终变低
//============================================================
module tb_debounce_fsm;
    reg clk    = 1'b0;
    reg rst_n  = 1'b0;
    reg key_in = 1'b0;
    wire key_out, key_press;

    debounce_fsm #(.CLK_FREQ(1000)) uut (
        .clk(clk), .rst_n(rst_n),
        .key_in(key_in), .key_out(key_out), .key_press(key_press)
    );

    always #10 clk = ~clk;

    initial begin
        #25 rst_n = 1'b1;

        // --- 按下抖动（150ns 短脉冲，不应确认）---
        #50   key_in = 1'b1;
        #150  key_in = 1'b0;
        #1200 key_in = 1'b1;

        // --- 稳定按住 30us，应确认 ---
        #30000;

        // --- 释放抖动（150ns 回弹，不应改变状态）---
        key_in = 1'b0;
        #150  key_in = 1'b1;
        #1200 key_in = 1'b0;

        // --- 稳定释放 30us，key_out 应变低 ---
        #30000 $finish;
    end
endmodule
