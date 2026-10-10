`timescale 1ns/1ps
//============================================================
// tb_melody.v —— 验证 demo_es8388 的旋律播放器时序（不上板）
//
// 思路：ES8388 在板子上是主机，会自己吐 BCLK/LRCK。仿真里没有芯片，
// 就用"假时钟源"喂给 DUT：
//   aud_bclk = 3.072MHz（MCLK/4），aud_lrc 每 32 个 bclk 翻一次（=48kHz）
// 然后看：音符有没有按时推进、DDS 有没有出声、I2S 数据线有没有跳。
//============================================================
module tb_melody;

    reg  clk = 1'b0;
    reg  aud_bclk = 1'b0;
    reg  aud_lrc  = 1'b0;
    reg  key = 1'b1;                 // 低有效，常态未按
    reg  aud_adcdat = 1'b0;
    wire [1:0] led;
    wire aud_mclk, aud_dacdat, aud_scl;
    wire aud_sda;

    pullup(aud_sda);                 // 模拟总线上的上拉电阻

    demo_es8388 u_dut (
        .clk        (clk),
        .key        (key),
        .led        (led),
        .aud_mclk   (aud_mclk),
        .aud_bclk   (aud_bclk),
        .aud_lrc    (aud_lrc),
        .aud_dacdat (aud_dacdat),
        .aud_adcdat (aud_adcdat),
        .aud_scl    (aud_scl),
        .aud_sda    (aud_sda)
    );

    // 50MHz 系统钟
    always #10 clk = ~clk;
    // 仿真加速：BCLK 用 61.4MHz（真实是 3.072MHz）。
    // 音符推进只数样本个数，与绝对频率无关，所以加速 20 倍能省 20 倍仿真时间。
    always #8.138 aud_bclk = ~aud_bclk;

    // LRCK：每 32 个 BCLK 翻一次 -> 48kHz
    integer i;
    reg [5:0] bcnt = 6'd0;
    always @(posedge aud_bclk) begin
        bcnt <= bcnt + 1'b1;
        if (bcnt == 6'd31) begin
            bcnt    <= 6'd0;
            aud_lrc <= ~aud_lrc;
        end
    end

    // 观察：音符号 / 当前频率字 / 包络 / 样本值
    integer last_note = -1;
    integer toggles = 0;
    initial begin
        $dumpfile("tb_melody.vcd");
        $dumpvars(0, tb_melody);
        // 加速后一个四分音符 = 25ms，跑 200ms 能看到 8 个音
        #200_000_000;
        $display("---- 仿真结束 ----");
        $display("dacdat 翻转次数 = %0d（>0 说明 I2S 在发数据）", toggles);
        $finish;
    end

    always @(posedge aud_bclk) begin
        if (u_dut.note_idx !== last_note) begin
            last_note = u_dut.note_idx;
            $display("t=%0.1fms  note=%0d  ftw=%0d  dur=%0d",
                     $time/1e6, u_dut.note_idx, u_dut.m_ftw, u_dut.dur);
        end
        if (u_dut.tick_new && (u_dut.note_idx == 6'd4))
            $display("       样本值=%0d  包络=%0d  note=%0d",
                 u_dut.dds_out, u_dut.gain, u_dut.note_idx);
    end

    always @(aud_dacdat) toggles <= toggles + 1;

    // 只打印前 40 条样本值，避免刷屏
    integer pcnt = 0;
    always @(posedge aud_bclk) begin
        if (u_dut.tick_new && (u_dut.note_idx == 6'd4) && (pcnt < 40)) begin
            pcnt <= pcnt + 1;
        end
    end

endmodule
