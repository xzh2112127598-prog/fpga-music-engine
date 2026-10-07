`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////////
// tb_osc_dds.v —— DDS 与 MATLAB 黄金向量逐样本比对
//
// 同时例化两份 osc_dds：
//   u_ip : IPOLATE=1  -> 比 golden/dds_440_ip_out.txt（插值版，误差 2 LSB）
//   u_no : IPOLATE=0  -> 比 golden/dds_440_out.txt   （直接查表版，误差 6 LSB）
// 两份共用同一个 en / ftw，所以还能顺带验证"插值确实更准"。
//
// 激励：440Hz，FTW = round(440 × 2^32 / 48000) = 39370534 = 0x0258BF26，跑 1 秒。
// 期望文件是 MATLAB writematrix 出的十进制文本，用 $fscanf("%d") 逐行读。
//
// 跑法：工作目录必须是 golden/ 所在目录（ROM 与期望文件都用相对路径）
//   bash tools/run_iverilog.sh osc_dds
////////////////////////////////////////////////////////////////////////////////
module tb_osc_dds;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #500 clk = ~clk;                 // 1MHz 系统钟

    localparam N_SAMP       = 48000;        // 1 秒 @48kHz
    localparam N_NOISE      = 24000;        // 噪声黄金向量只有 0.5 秒
    localparam CLK_PER_SAMP = 20;           // 只为加快仿真；DDS 输出只取决于 en 的顺序
    localparam FTW          = 32'd39370534; // 440Hz @32bit/48kHz
    localparam FTW_NOISE    = 32'd524288;   // 2^(32-13)：8192 点噪声表，每样本地址 +1

    reg en = 1'b0;
    reg en_nz = 1'b0;

    wire signed [15:0] out_ip, out_no, out_nz;
    wire               vip, vno, vnz;

    osc_dds #(
        .PHASE_W(32), .ADDR_W(10), .DATA_W(16),
        .IPOLATE(1), .ROM_FILE("golden/sine_1024.hex")
    ) u_ip (
        .clk(clk), .rst_n(rst_n), .en(en), .ftw(FTW),
        .load(1'b0), .phase_i(32'd0),
        .out(out_ip), .out_valid(vip), .phase_o()
    );

    osc_dds #(
        .PHASE_W(32), .ADDR_W(10), .DATA_W(16),
        .IPOLATE(0), .ROM_FILE("golden/sine_1024.hex")
    ) u_no (
        .clk(clk), .rst_n(rst_n), .en(en), .ftw(FTW),
        .load(1'b0), .phase_i(32'd0),
        .out(out_no), .out_valid(vno), .phase_o()
    );

    // 噪声源：同一个 osc_dds，只是换成 8192 点噪声表、地址位宽 13
    // 走相位累加器读表（不是裸 LFSR 直出），所以能算一个独立振荡器
    osc_dds #(
        .PHASE_W(32), .ADDR_W(13), .DATA_W(16),
        .IPOLATE(0), .ROM_FILE("golden/noise_8192.hex")
    ) u_nz (
        .clk(clk), .rst_n(rst_n), .en(en_nz), .ftw(FTW_NOISE),
        .load(1'b0), .phase_i(32'd0),
        .out(out_nz), .out_valid(vnz), .phase_o()
    );

    integer fip, fno, fnz;
    integer exp_ip, exp_no, exp_nz;
    integer n_ip, n_no, n_nz, err_ip, err_no, err_nz, i;
    integer maxe_ip, maxe_no, maxe_nz;
    integer d;

    // 采样：与黄金向量逐个比对
    always @(posedge clk) begin
        if (vip) begin
            if ($fscanf(fip, "%d", exp_ip) != 1) begin
                $display("[FAIL] 插值版：DUT 输出多出来了（期望文件已读完）");
                err_ip = err_ip + 1;
            end else begin
                d = (exp_ip > out_ip) ? (exp_ip - out_ip) : (out_ip - exp_ip);
                if (d > maxe_ip) maxe_ip = d;
                if (out_ip !== exp_ip) begin
                    if (err_ip < 5)
                        $display("[FAIL] 插值版 第 %0d 个样本: 期望 %0d 实际 %0d",
                                 n_ip, exp_ip, out_ip);
                    err_ip = err_ip + 1;
                end
                n_ip = n_ip + 1;
            end
        end
        if (vno) begin
            if ($fscanf(fno, "%d", exp_no) != 1) begin
                $display("[FAIL] 查表版：DUT 输出多出来了（期望文件已读完）");
                err_no = err_no + 1;
            end else begin
                d = (exp_no > out_no) ? (exp_no - out_no) : (out_no - exp_no);
                if (d > maxe_no) maxe_no = d;
                if (out_no !== exp_no) begin
                    if (err_no < 5)
                        $display("[FAIL] 查表版 第 %0d 个样本: 期望 %0d 实际 %0d",
                                 n_no, exp_no, out_no);
                    err_no = err_no + 1;
                end
                n_no = n_no + 1;
            end
        end
        if (vnz) begin
            if ($fscanf(fnz, "%d", exp_nz) != 1) begin
                $display("[FAIL] 噪声源：DUT 输出多出来了（期望文件已读完）");
                err_nz = err_nz + 1;
            end else begin
                d = (exp_nz > out_nz) ? (exp_nz - out_nz) : (out_nz - exp_nz);
                if (d > maxe_nz) maxe_nz = d;
                if (out_nz !== exp_nz) begin
                    if (err_nz < 5)
                        $display("[FAIL] 噪声源 第 %0d 个样本: 期望 %0d 实际 %0d",
                                 n_nz, exp_nz, out_nz);
                    err_nz = err_nz + 1;
                end
                n_nz = n_nz + 1;
            end
        end
    end

    initial begin
        n_ip = 0; n_no = 0; n_nz = 0;
        err_ip = 0; err_no = 0; err_nz = 0;
        maxe_ip = 0; maxe_no = 0; maxe_nz = 0;
        fip = $fopen("golden/dds_440_ip_out.txt", "r");
        fno = $fopen("golden/dds_440_out.txt",    "r");
        fnz = $fopen("golden/noise_out.txt",      "r");
        if (fip == 0 || fno == 0 || fnz == 0) begin
            $display("[ERROR] 打不开期望文件，工作目录要在 golden/ 的上一级");
            $finish;
        end

        #2000 rst_n = 1'b1;

        for (i = 0; i < N_SAMP; i = i + 1) begin
            en    <= 1'b1;
            en_nz <= (i < N_NOISE);          // 噪声黄金向量只跑了 0.5 秒
            @(posedge clk);
            en    <= 1'b0;
            en_nz <= 1'b0;
            repeat (CLK_PER_SAMP - 1) @(posedge clk);
        end
        // 等流水线排空（3 拍）
        repeat (10) @(posedge clk);

        $display("插值版: 比对 %0d 个样本，不一致 %0d，最大偏差 %0d LSB", n_ip, err_ip, maxe_ip);
        $display("查表版: 比对 %0d 个样本，不一致 %0d，最大偏差 %0d LSB", n_no, err_no, maxe_no);
        $display("噪声源: 比对 %0d 个样本，不一致 %0d，最大偏差 %0d LSB", n_nz, err_nz, maxe_nz);

        if (n_ip != N_SAMP || n_no != N_SAMP || n_nz != N_NOISE) begin
            $display("[FAIL] 样本数不对：期望 插值/查表 %0d、噪声 %0d；实得 %0d/%0d/%0d",
                     N_SAMP, N_NOISE, n_ip, n_no, n_nz);
            err_ip = err_ip + 1;
        end

        if (err_ip == 0 && err_no == 0 && err_nz == 0)
            $display("=== 全部通过：RTL DDS 与 MATLAB 黄金模型逐样本一致 ===");
        else
            $display("=== 有 %0d 处不一致 ===", err_ip + err_no + err_nz);
        $fclose(fip); $fclose(fno); $fclose(fnz);
        $finish;
    end

endmodule
