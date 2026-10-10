`timescale 1ns/1ps
//============================================================
// tb_sq.v —— 验证 demo_es8388 的"满幅方波"档（不上板）
//
// 这个档位是链路探针：绕开 DDS / ROM / 包络，直接把 ±满量程方波
// 送进 I2S。只要这里看到 dac_data 在 0x7FFFFF / 0x800000 之间跳，
// 上板后耳机就一定有声音（除非硬件接线/插孔有问题）。
//
// 编译（在 rtl/fpga_practice 目录下）：
//   iverilog -g2012 -DSIM_PLL_STUB -o tb_sq.vvp \
//       tb_sq.v demo_es8388.v ../es8388/*.v ../src/osc_dds.v 04_debounce_fsm.v
//   vvp tb_sq.vvp
//============================================================
module tb_sq;

    reg  clk = 1'b0;
    reg  aud_bclk = 1'b0;
    reg  aud_lrc  = 1'b0;
    reg  key_s1 = 1'b0;              // S1=H11 高有效，常态未按
    reg  key_s2 = 1'b0;              // S2=H10 高有效，常态未按
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
    always #8.138 aud_bclk = ~aud_bclk;   // 仿真加速：61.4MHz（真机 2.304MHz）

    // LRCK：每 32 个 BCLK 翻一次
    reg [5:0] bcnt = 6'd0;
    always @(posedge aud_bclk) begin
        bcnt <= bcnt + 1'b1;
        if (bcnt == 6'd31) begin
            bcnt    <= 6'd0;
            aud_lrc <= ~aud_lrc;
        end
    end

    integer toggles = 0;
    always @(aud_dacdat) toggles <= toggles + 1;

    // 只在上电复位释放之后才开始取样（前 1.3ms 是 por 延时）
    integer n = 0;
    integer err = 0;
    always @(posedge aud_bclk) begin
        if (u_dut.audio_rst_n && u_dut.tick_new && (n < 12200) && u_dut.mode_s1 == 2'd0) begin
            if (u_dut.gcnt < 16'd12000) begin
                // 方波段：必须只能是 +满幅 或 -满幅
                if (u_dut.dac_data !== {{8{1'b0}}, 24'h7FFFFF} &&
                    u_dut.dac_data !== {{8{1'b1}}, 24'h800000}) begin
                    err <= err + 1;
                    $display("  !! 异常样本 gcnt=%0d dac=%h", u_dut.gcnt, u_dut.dac_data);
                end
            end else begin
                if (u_dut.dac_data !== 32'd0) begin
                    err <= err + 1;
                    $display("  !! 静音段非 0 gcnt=%0d dac=%h", u_dut.gcnt, u_dut.dac_data);
                end
            end
            // 开头 6 个 + 跨过 12000 边界的 6 个（验证"响->停"切换）
            if (n < 6 || (n >= 11996 && n < 12002))
                $display("样本 %0d: gcnt=%0d sqp=%0d dac=%h", n, u_dut.gcnt, u_dut.sqp, u_dut.dac_data);
            n <= n + 1;
        end
    end

    initial begin
        #30_000_000;
        $display("---- 方波档仿真结束 ----");
        $display("检查样本数 = %0d，异常数 = %0d", n, err);
        $display("dacdat 翻转次数 = %0d（>0 说明 I2S 在发数据）", toggles);
        $display("cfg_done=%b  ack_err=%b  led=%b", u_dut.cfg_done, u_dut.cfg_ack_err, led);
        $finish;
    end

endmodule
