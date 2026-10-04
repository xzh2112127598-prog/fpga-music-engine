`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////////
// tb_hit_detector.v —— 敲击检测与 MATLAB 黄金模型逐拍比对
//
// 激励：golden/imu_ax.hex / imu_ay.hex / imu_az.hex（由 MATLAB 生成）
// 期望：golden/imu_expect.hex  第 0 行=事件数，之后 {索引[31:16],类型[15:8],力度[7:0]}
//
// 跑法（ModelSim / Questa，工作目录设为 rtl/tb）：
//   vlog ../src/isqrt.v ../src/hit_detector.v tb_hit_detector.v
//   vsim -voptargs=+acc work.tb_hit_detector
//   run 5ms
//
// 说明：这里用 1MHz 系统钟 + 1kHz 采样（每 1000 周期一个样本），
//       只为加快仿真；真实板子是 27MHz 钟 + 500~1000Hz 采样，逻辑完全一致。
//       8 个敲击 x 2.8s = 2800 个样本 -> 2.8M 周期。
////////////////////////////////////////////////////////////////////////////////
module tb_hit_detector;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #500 clk = ~clk;                 // 1MHz

    localparam N_SAMP = 2800;              // 与 golden/*.hex 行数一致（2.8s @1kHz）
    localparam IMU_RATE = 1000;
    localparam CLK_PER_SAMP = 1_000_000 / IMU_RATE;   // 1000

    reg [15:0] mem_ax [0:N_SAMP-1];
    reg [15:0] mem_ay [0:N_SAMP-1];
    reg [15:0] mem_az [0:N_SAMP-1];
    reg [31:0] mem_exp [0:8];   // 第0行=事件数，其后每个事件一行；文件只有 9 行，别开成 [0:63]

    integer idx;
    integer cyc;
    integer exp_n;
    integer exp_i;
    integer got_n;
    integer err_n;

    reg sample_valid;
    wire [15:0] ax = mem_ax[idx];
    wire [15:0] ay = mem_ay[idx];
    wire [15:0] az = mem_az[idx];

    wire hit_valid;
    wire [1:0] hit_type;
    wire [6:0] hit_vel;

    hit_detector #(
        .LSBG     (2048),
        .IMU_RATE (IMU_RATE),
        .WIN_MS   (5),
        .REFR_MS  (100)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .sample_valid(sample_valid),
        .ax(ax), .ay(ay), .az(az),
        .hit_valid(hit_valid), .hit_type(hit_type), .hit_vel(hit_vel)
    );

    initial begin
        $readmemh("golden/imu_ax.hex", mem_ax);
        $readmemh("golden/imu_ay.hex", mem_ay);
        $readmemh("golden/imu_az.hex", mem_az);
        $readmemh("golden/imu_expect.hex", mem_exp);
    end

    // 记录检测到的事件
    reg [31:0] got [0:63];
    always @(posedge clk) begin
        if (hit_valid) begin
            // 与 imu_expect.hex 同格式：[31:16]=索引 [15:8]=类型 [7:0]=力度
            got[got_n] <= {idx[15:0], 6'd0, hit_type[1:0], 1'b0, hit_vel[6:0]};
            got_n <= got_n + 1;
        end
    end

    initial begin
        idx = 0; cyc = 0; got_n = 0; err_n = 0;
        sample_valid = 1'b0;
        #2000 rst_n = 1'b1;

        for (idx = 0; idx < N_SAMP; idx = idx + 1) begin
            // ⚠️ sample_valid 必须用非阻塞赋值。用阻塞赋值会和 DUT 的 always 块竞争：
            // initial 块在上一个 repeat 的最后一个 posedge 上就把 sample_valid 拉高，
            // 若它先于 DUT 执行，DUT 会把同一个样本处理两遍（基线更新两遍、峰值窗
            // 只覆盖一半样本），表现为"检测偏早 6 个样本 + 力度明显偏小"。
            // NBA 下当拍 DUT 仍看到 0，只在下一个 posedge 采到 1，脉冲干净。
            sample_valid <= 1'b1;
            @(posedge clk);
            sample_valid <= 1'b0;
            // 等到下一个样本时刻
            repeat (CLK_PER_SAMP - 1) @(posedge clk);
        end

        // ---- 比对 ----
        exp_n = mem_exp[0];
        $display("期望事件 %0d 个，实际检测 %0d 个", exp_n, got_n);

        // 容量自检：MATLAB 重新生成后若事件数变多，这里会先报错而不是 silently 少比
        if (exp_n > 8) begin
            $display("[ERROR] mem_exp 容量不足（%0d > 8），请把 mem_exp 声明改大", exp_n);
            err_n = err_n + 1;
        end

        if (got_n != exp_n) begin
            $display("[FAIL] 事件数不一致");
            err_n = err_n + 1;
        end

        for (exp_i = 0; exp_i < (exp_n < got_n ? exp_n : got_n); exp_i = exp_i + 1) begin
            if (got[exp_i] !== mem_exp[exp_i + 1]) begin
                $display("[FAIL] 第 %0d 个事件: 期望 %08h 实际 %08h",
                         exp_i, mem_exp[exp_i + 1], got[exp_i]);
                err_n = err_n + 1;
            end else begin
                $display("[PASS] 第 %0d 个事件: idx=%0d type=%0d vel=%0d",
                         exp_i, got[exp_i][31:16], got[exp_i][9:8], got[exp_i][7:0]);
            end
        end

        if (err_n == 0) $display("=== 全部通过：RTL 与 MATLAB 黄金模型一致 ===");
        else            $display("=== 有 %0d 处不一致 ===", err_n);
        $finish;
    end

endmodule
