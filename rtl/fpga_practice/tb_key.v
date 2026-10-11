`timescale 1ns/1ps
//============================================================
// tb_key.v —— 验证按键换挡能不能一直循环（0 方波 -> 1 旋律 -> 2 静音 -> 0）
//
// 用户实测到"按 S2 静音之后，再按什么键都没作用"，所以专门跑这个：
// 连按 4 次 S1，看 mode 会不会 0->1->2->0->1 正常绕回来。
//
// 加速手段：por 结束后直接 force boot_gate=1，跳过那 0.2s 上电屏蔽，
// 省掉 200ms 仿真时间（boot_gate 只是个简单计数器，已在别处验证）。
//
// 编译（在 rtl/fpga_practice 目录下）：
//   iverilog -g2012 -DSIM_PLL_STUB -o tb_key.vvp tb_key.v demo_es8388.v \
//       ../es8388/*.v ../src/osc_dds.v 04_debounce_fsm.v
//   vvp tb_key.vvp
//============================================================
module tb_key;

    reg  clk = 1'b0;
    reg  aud_bclk = 1'b0;
    reg  aud_lrc  = 1'b0;
    reg  key_s1 = 1'b0;              // S1=H11 高有效
    reg  key_s2 = 1'b0;              // S2=H10 高有效（推测）
    reg  aud_adcdat = 1'b0;
    wire [1:0] led;
    wire aud_mclk, aud_dacdat, aud_scl;
    wire aud_sda;

    pullup(aud_sda);

    demo_es8388 u_dut (
        .clk        (clk),
        .key_s1     (key_s1),
        .key_s2     (key_s2),
        .led        (led),
        .aud_mclk   (aud_mclk),
        .aud_bclk   (aud_bclk),
        .aud_lrc    (aud_lrc),
        .aud_dacdat (aud_dacdat),
        .aud_adcdat (aud_adcdat),
        .aud_scl    (aud_scl),
        .aud_sda    (aud_sda)
    );

    always #10    clk      = ~clk;        // 50MHz
    always #8.138 aud_bclk = ~aud_bclk;   // 仿真加速：61.4MHz

    reg [5:0] bcnt = 6'd0;
    always @(posedge aud_bclk) begin
        bcnt <= bcnt + 1'b1;
        if (bcnt == 6'd31) begin
            bcnt    <= 6'd0;
            aud_lrc <= ~aud_lrc;
        end
    end

    integer last_mode = -1;
    always @(posedge clk) begin
        if (u_dut.mode !== last_mode) begin
            last_mode = u_dut.mode;
            $display("  t=%0.2fms  mode=%0d  (boot_gate=%b press_s1=%b press_s2=%b)",
                     $time/1e6, u_dut.mode, u_dut.boot_gate,
                     u_dut.press_s1, u_dut.press_s2);
        end
    end

    initial begin
        #5_000_000;                        // 等 por 释放（1.31ms）
        force u_dut.boot_gate = 1'b1;      // 跳过 0.2s 上电屏蔽
        #1_000_000;
        $display("---- 开始连按 S1 四次（每次按住 15ms / 松开 25ms）----");
        repeat (4) begin
            key_s1 = 1'b1; #15_000_000;
            key_s1 = 1'b0; #25_000_000;
        end
        #5_000_000;
        $display("---- 结束 ----");
        if (u_dut.mode == 2'd1)
            $display("✅ 档位循环正常：0->1->2->0->1，mode=%0d", u_dut.mode);
        else
            $display("❌ 档位循环异常，最终 mode=%0d（期望 1）", u_dut.mode);
        $finish;
    end

endmodule
