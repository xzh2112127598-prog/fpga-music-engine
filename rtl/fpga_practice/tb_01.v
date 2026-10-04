`timescale 1ns/1ps
//============================================================
// 练习1 仿真文件（testbench）
// 用法：ModelSim 中 compile 两个文件 -> simulate tb_counter ->
//      把 clk/rst_n/cnt/tick 加入波形 -> run 250ns
//============================================================
module tb_counter;
    reg        clk   = 1'b0;
    reg        rst_n = 1'b0;
    wire [3:0] cnt;
    wire       tick;

    // 例化被测模块，MAX 改成 9（数 0~9 循环）
    counter #(.MAX(9)) uut (
        .clk(clk), .rst_n(rst_n), .cnt(cnt), .tick(tick)
    );

    // 每 10ns 翻转一次 -> 周期 20ns = 50MHz 仿真时钟
    always #10 clk = ~clk;

    initial begin
        #25  rst_n = 1'b1;     // 25ns 后释放复位
        #250 $finish;          // 跑到 275ns 结束
    end
endmodule
