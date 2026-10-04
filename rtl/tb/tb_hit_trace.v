`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////////
// tb_hit_trace.v —— hit_detector 逐内部状态导出，用于与黄金模型 diff
//
// 输出格式与 tools/ref_hit.py 完全一致：
//   TR <idx> <dx> <dy> <dz> <magsq> <st> <wcnt> <bx> <by> <bz>
// 其中 st / wcnt / bx / by / bz 都是"本样本进入时"的寄存器值（posedge 上读到旧值），
// 与 ref_hit.py 里 state_pre / wcnt_pre / 更新前的基线 口径一致。
//
// 用法（工作目录 rtl/tb，golden/ 需要在下级或用 -D 指定）：
//   iverilog -g2012 -o trace.vvp ../src/isqrt.v ../src/hit_detector.v tb_hit_trace.v
//   cd ../../sim/teamB/drum_sim_matlab && vvp ../../../rtl/tb/trace.vvp > rtl_trace.txt
////////////////////////////////////////////////////////////////////////////////
module tb_hit_trace;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #500 clk = ~clk;                 // 1MHz

    localparam N_SAMP = 2800;
    localparam IMU_RATE = 1000;
    localparam CLK_PER_SAMP = 1_000_000 / IMU_RATE;

    reg [15:0] mem_ax [0:N_SAMP-1];
    reg [15:0] mem_ay [0:N_SAMP-1];
    reg [15:0] mem_az [0:N_SAMP-1];

    integer idx;

    reg sample_valid;
    wire [15:0] ax = mem_ax[idx];
    wire [15:0] ay = mem_ay[idx];
    wire [15:0] az = mem_az[idx];

    wire       hit_valid;
    wire [1:0] hit_type;
    wire [6:0] hit_vel;

    hit_detector #(
        .LSBG(2048), .IMU_RATE(IMU_RATE), .WIN_MS(5), .REFR_MS(100)
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
    end

    // ---- trace：与 ref_hit.py 同格式，末尾附加 primed / 原始输入 / 仿真时间 ----
    always @(posedge clk) if (sample_valid)
        $display("TR %4d %6d %6d %6d %10d %d %d %6d %6d %6d | p=%0d ax=%6d ay=%6d az=%6d t=%0t",
                 idx, u_dut.dx, u_dut.dy, u_dut.dz, u_dut.magsq,
                 u_dut.st, u_dut.wcnt, u_dut.bx, u_dut.by, u_dut.bz,
                 u_dut.primed, ax, ay, az, $time);

    // ---- 事件 ----
    initial begin
        idx = 0;
        sample_valid = 1'b0;
        #2000 rst_n = 1'b1;
        for (idx = 0; idx < N_SAMP; idx = idx + 1) begin
            // ⚠️ 必须用非阻塞赋值：若写成 sample_valid = 1'b1（阻塞），initial 块会在
            // 上一个 repeat 的最后一个 posedge 上就把 sample_valid 拉高，与 DUT 的
            // always 块竞争 —— 结果 DUT 把同一个样本处理了两遍（基线更新两遍、
            // 峰值窗只覆盖一半样本），表现为"检测偏早 + 力度偏小"。
            // 用 NBA 后，拉高发生在当拍末，DUT 当拍仍看到 0，只在下一个 posedge 采到 1。
            sample_valid <= 1'b1;
            @(posedge clk);
            sample_valid <= 1'b0;
            repeat (CLK_PER_SAMP - 1) @(posedge clk);
        end
        $finish;
    end

    always @(posedge clk) if (hit_valid)
        $display("EV idx=%0d type=%0d vel=%0d", idx, hit_type, hit_vel);

endmodule
