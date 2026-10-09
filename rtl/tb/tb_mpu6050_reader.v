`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////////
// tb_mpu6050_reader.v —— MPU6050 读取模块验证
//
// 这是全工程最后一个没有 testbench 的模块，上板前必须先过。
// 从机模型直接沿用 tb_i2c_master.v（已验证），寄存器文件 s_mem 里
// 预置 0x3B 起 6 字节为 11 22 33 44 55 66，所以期望：
//     ax = 0x1122   ay = 0x3344   az = 0x5566
//
// 检查项：
//   1) 上电配置是否写对，尤其是 ACCEL_CONFIG = 0x18（±16g）
//      —— 写成 ±2g 一敲就爆表，力度全丢，是最致命的坑
//   2) 6 字节是否按"高位在前"正确拼成 ax/ay/az
//   3) 实测采样周期（标称 1000Hz，实际会被 I2C 事务时间拖慢，必须量出来）
////////////////////////////////////////////////////////////////////////////////
module tb_mpu6050_reader;

    localparam CLK_FREQ = 50_000_000;
    localparam DEV      = 7'h68;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #10 clk = ~clk;                 // 50MHz

    wire scl;
    wire sda;
    // I2C 是开漏总线，真实板子上靠上拉电阻拉高。仿真里必须显式建模，
    // 否则主机释放 SDA 后总线是 Z，从机采样到的是 Z 而不是 1（这个坑踩过一次）。
    pullup(scl);
    pullup(sda);
    wire [15:0] ax, ay, az;
    wire        sample_valid, ready;

    mpu6050_reader #(
        .CLK_FREQ    (CLK_FREQ),
        .SAMPLE_RATE (1000)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .scl(scl), .sda(sda),
        .ax(ax), .ay(ay), .az(az),
        .sample_valid(sample_valid), .ready(ready)
    );

    ////////////////////////////////////////////////////////////////////////////
    // 行为级 I2C 从机（与 tb_i2c_master.v 完全相同）
    ////////////////////////////////////////////////////////////////////////////
    reg s_drv = 1'b0;
    assign sda = s_drv ? 1'b0 : 1'bz;

    reg [3:0]  s_bit = 4'd0;
    reg        s_rw = 1'b0, s_addr_done = 1'b0, s_wph = 1'b0, s_nak = 1'b0;
    reg [7:0]  s_rx = 8'd0, s_tx = 8'd0, s_ptr = 8'd0;
    reg [7:0]  s_mem [0:255];
    integer    k;

    wire [7:0] s_mem_rd = s_mem[s_ptr];

    initial begin
        for (k = 0; k < 256; k = k + 1) s_mem[k] = 8'h00;
        s_mem[8'h3B] = 8'h11; s_mem[8'h3C] = 8'h22; s_mem[8'h3D] = 8'h33;
        s_mem[8'h3E] = 8'h44; s_mem[8'h3F] = 8'h55; s_mem[8'h40] = 8'h66;
    end

    integer n_start = 0, n_addrok = 0, n_write = 0, n_read = 0;

    always @(negedge sda) if (scl) begin
        s_bit <= 4'd0; s_addr_done <= 1'b0; s_wph <= 1'b0; s_nak <= 1'b0;
        n_start = n_start + 1;
    end
    always @(posedge sda) if (scl) begin
        s_bit <= 4'd0; s_addr_done <= 1'b0; s_wph <= 1'b0;
    end

    always @(posedge scl) begin
        if (s_bit < 4'd8) begin
            if (!s_rw || !s_addr_done) s_rx <= {s_rx[6:0], sda};
            s_bit <= s_bit + 4'd1;
        end else begin
            if (s_rw && s_addr_done) s_nak <= (sda == 1'b1);
            s_bit <= 4'd0;
        end
    end

    always @(negedge scl) begin
        if (s_bit == 4'd8) begin
            if (!s_addr_done) begin
                if (s_rx[7:1] == DEV) begin
                    s_drv <= 1'b1; s_rw <= s_rx[0]; s_addr_done <= 1'b1;
                    n_addrok = n_addrok + 1;
                end else begin
                    s_drv <= 1'b0; s_addr_done <= 1'b0;
                end
            end else if (s_rw) begin
                s_drv <= 1'b0;
            end else begin
                s_drv <= 1'b1;
                if (!s_wph) begin s_ptr <= s_rx; s_wph <= 1'b1; end
                else begin s_mem[s_ptr] <= s_rx; s_ptr <= s_ptr + 8'd1;
                            n_write = n_write + 1; end
            end
        end else if (s_bit == 4'd0) begin
            s_drv <= 1'b0;
            if (s_rw && s_addr_done && !s_nak) begin
                s_tx  <= s_mem_rd;
                s_ptr <= s_ptr + 8'd1;
                s_drv <= ~s_mem_rd[7];
            end
        end else begin
            if (s_rw && s_addr_done && !s_nak) begin
                s_tx  <= {s_tx[6:0], 1'b0};
                s_drv <= ~s_tx[6];
            end
        end
    end

    ////////////////////////////////////////////////////////////////////////////
    // 激励与检查
    ////////////////////////////////////////////////////////////////////////////
    integer errs = 0;
    integer nsamp = 0;
    real    t1 = 0.0, t2 = 0.0;
    real    period_ns, rate_hz;

    task chk;
        input [8*40-1:0] name;
        input integer cond;
        begin
            if (cond) $display("  [PASS] %0s", name);
            else begin $display("  [FAIL] %0s", name); errs = errs + 1; end
        end
    endtask

    initial begin : main
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;

        // ---- 等初始化完成 ----
        wait (ready === 1'b1);
        $display("=== MPU6050 初始化完成 ===");
        chk("PWR_MGMT_1(0x6B) == 0x00",        s_mem[8'h6B] === 8'h00);
        chk("ACCEL_CONFIG(0x1C) = 0x18 (+-16g)",  s_mem[8'h1C] === 8'h18);
        chk("SMPLRT_DIV(0x19) = 0x01",            s_mem[8'h19] === 8'h01);
        if (s_mem[8'h1C] !== 8'h18)
            $display("  [WARN] ACCEL_CONFIG not 0x18 -> not +-16g, hits will clip!");

        // ---- 取 2 个样本：第 1 个查数据拼接，第 2 个量周期 ----
        t1 = 0.0; t2 = 0.0;
        while (nsamp < 2) begin
            @(posedge sample_valid);
            nsamp = nsamp + 1;
            if (nsamp == 1) begin
                chk("ax == 16'h1122", ax === 16'h1122);
                chk("ay == 16'h3344", ay === 16'h3344);
                chk("az == 16'h5566", az === 16'h5566);
                if (t1 == 0.0) t1 = $time;
            end else begin
                if (t2 == 0.0) t2 = $time;
            end
        end

        if (t1 > 0.0 && t2 > 0.0) begin
            period_ns = t2 - t1;
            rate_hz   = 1.0e9 / period_ns;
            $display("=== 实测采样周期 = %0.0f ns -> %0.1f Hz（标称 1000Hz）===",
                     period_ns, rate_hz);
            chk("实测采样率在 600~1100Hz 之间",
                (rate_hz > 600.0) && (rate_hz < 1100.0));
        end

        #100;
        if (errs == 0) $display("=== tb_mpu6050_reader 全部通过 ===");
        else           $display("=== tb_mpu6050_reader 失败 %0d 项 ===", errs);
        $finish;
    end

    // 保险：跑太久直接结束
    initial begin
        #300_000_000;                       // 300ms 仿真时间上限
        $display("[TIMEOUT] 300ms 内未取到 2 个样本");
        $finish;
    end

endmodule
