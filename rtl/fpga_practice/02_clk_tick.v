//============================================================
// 练习2：时钟分频 —— 产生“使能脉冲”
// 对应知识点：6(计数器与分频)
// 【重要设计思想】不要用计数器去“造一个新时钟”再接到别的模块 clk 上，
//  正确做法是所有模块共用同一个 clk，用单周期的“使能脉冲”决定何时动作。
//  tick_48k 就是以后整个音频系统的心跳：每一拍算一个声音样本。
//============================================================
module clk_tick #(
    parameter integer CLK_FREQ = 24_000_000   // !!按实际板子改!!
                                                 // Tang Primer 25K = 50_000_000
                                                 // Tang Primer 25K = 24_000_000
)(
    input  wire clk,
    input  wire rst_n,
    output reg  tick_48k,     // 48kHz 音频心跳
    output reg  tick_1hz      // 1Hz 心跳（LED 闪烁用）
);
    //---------------- 48kHz ----------------
    localparam integer DIV_48K = CLK_FREQ/48_000 - 1;
    localparam integer W_48K   = $clog2(DIV_48K + 1);
    reg [W_48K-1:0] c48;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c48 <= 0; tick_48k <= 1'b0;
        end else if (c48 == DIV_48K) begin
            c48 <= 0; tick_48k <= 1'b1;        // 一拍高电平
        end else begin
            c48 <= c48 + 1'b1; tick_48k <= 1'b0;
        end
    end

    //---------------- 1Hz ----------------
    localparam integer DIV_1HZ = CLK_FREQ - 1;
    localparam integer W_1HZ   = $clog2(CLK_FREQ);
    reg [W_1HZ-1:0] c1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c1 <= 0; tick_1hz <= 1'b0;
        end else if (c1 == DIV_1HZ) begin
            c1 <= 0; tick_1hz <= 1'b1;
        end else begin
            c1 <= c1 + 1'b1; tick_1hz <= 1'b0;
        end
    end
endmodule
