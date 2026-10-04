`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////////
// tb_i2c_master.v —— I2C 主机仿真（自带行为级 I2C 从机模型）
//
// 从机模型做这些事（不是原来那个只看位计数的假从机）：
//   - 检测 START / STOP
//   - 地址匹配才 ACK（7'h68），地址不对就 NACK（用来验证 ack_err 通路）
//   - 写方向：第 1 个字节当寄存器指针，后面写进寄存器文件
//   - 读方向：在 SCL 下降沿更新 SDA（真开漏时序），主机在上升沿采样
//   - ACK 槽期间从机拉低 SDA，ACK 槽结束（SCL 低）才释放
//
// 自检内容：3 次正常事务 + 1 次错误地址事务，并测量实际 SCL 频率是否超 400kHz
//
// 跑法（Icarus Verilog）：
//   iverilog -g2012 -o sim.vvp ../src/i2c_master.v tb_i2c_master.v
//   vvp sim.vvp
// 或： bash tools/run_iverilog.sh i2c_master
// 开调试波形：iverilog -DDUMP_I2C ... 然后 gtkwave i2c.vcd
////////////////////////////////////////////////////////////////////////////////
module tb_i2c_master;

    localparam CLK_FREQ = 100_000_000;
    localparam I2C_FREQ = 400_000;
    localparam DEV      = 7'h68;      // MPU6050（AD0 接地）

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;              // 100MHz 系统钟（仿真用，不对应真实板子）

    wire scl;
    wire sda;
    pullup(scl);
    pullup(sda);

    // ---- 主机侧信号 ----
    reg        m_start   = 1'b0;
    reg [6:0]  m_addr    = DEV;
    reg        m_rw      = 1'b0;
    reg [7:0]  m_reg     = 8'h00;
    reg [7:0]  m_wdata   = 8'h00;
    reg [3:0]  m_nbytes  = 4'd1;
    wire [63:0] m_rdata;
    wire       m_done, m_ack_err, m_busy;

    i2c_master #(
        .CLK_FREQ (CLK_FREQ),
        .I2C_FREQ (I2C_FREQ)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .start(m_start), .dev_addr(m_addr), .rw(m_rw),
        .reg_addr(m_reg), .data_wr(m_wdata), .nbytes(m_nbytes),
        .data_rd(m_rdata), .done(m_done), .ack_err(m_ack_err), .busy(m_busy),
        .scl(scl), .sda(sda)
    );

    ////////////////////////////////////////////////////////////////////////////
    // 行为级 I2C 从机
    ////////////////////////////////////////////////////////////////////////////
    reg        s_drv = 1'b0;                 // 1 = 拉低 SDA（开漏）
    assign sda = s_drv ? 1'b0 : 1'bz;

    reg [3:0]  s_bit       = 4'd0;           // 0..7 数据位，8 = ACK 槽
    reg        s_rw        = 1'b0;
    reg        s_addr_done = 1'b0;
    reg [7:0]  s_rx        = 8'd0;
    reg [7:0]  s_tx        = 8'd0;
    reg [7:0]  s_ptr       = 8'd0;
    reg        s_wph       = 1'b0;           // 0=还没拿到寄存器指针 1=已拿到
    reg [7:0]  s_mem [0:255];
    reg        s_nak       = 1'b0;           // 主机对最后一个字节发了 NACK
    integer    k;

    wire [7:0] s_mem_rd = s_mem[s_ptr];      // 组合读，避免对 memory 直接位选

    initial begin
        for (k = 0; k < 256; k = k + 1) s_mem[k] = 8'h00;
        // MPU6050 加速度寄存器 ACCEL_XOUT_H(0x3B) 起 6 字节，放一个可验证的数串
        s_mem[8'h3B] = 8'h11; s_mem[8'h3C] = 8'h22; s_mem[8'h3D] = 8'h33;
        s_mem[8'h3E] = 8'h44; s_mem[8'h3F] = 8'h55; s_mem[8'h40] = 8'h66;
    end

    // START / STOP：SDA 在 SCL 高时跳变
    always @(negedge sda) if (scl) begin
        s_bit <= 4'd0; s_addr_done <= 1'b0; s_wph <= 1'b0; s_nak <= 1'b0;
    end
    always @(posedge sda) if (scl) begin
        s_bit <= 4'd0; s_addr_done <= 1'b0; s_wph <= 1'b0;
    end

    // SCL 上升沿：主机/从机采样 SDA
    always @(posedge scl) begin
        if (s_bit < 4'd8) begin
            if (!s_rw || !s_addr_done) s_rx <= {s_rx[6:0], sda};  // 从机收
            s_bit <= s_bit + 4'd1;
        end else begin
            if (s_rw && s_addr_done) s_nak <= (sda == 1'b1);       // 主机 NACK
            s_bit <= 4'd0;
        end
    end

    // SCL 下降沿：从机更新 SDA（保证上升沿前已稳定）
    always @(negedge scl) begin
        if (s_bit == 4'd8) begin
            // 第 8 位结束 -> 进入 ACK 槽
            if (!s_addr_done) begin
                // 刚收完的是地址字节：地址匹配才 ACK，不匹配就 NACK
                if (s_rx[7:1] == DEV) begin
                    s_drv        <= 1'b1;          // ACK
                    s_rw         <= s_rx[0];
                    s_addr_done  <= 1'b1;
                end else begin
                    s_drv       <= 1'b0;           // NACK（地址不对，保持高阻）
                    s_addr_done <= 1'b0;           // 后续字节继续当地址处理 -> 继续 NACK
                end
            end else if (s_rw) begin
                s_drv <= 1'b0;                     // 从机刚发完，释放给主机应答
            end else begin
                s_drv <= 1'b1;                     // 从机刚收完，拉低 ACK
                if (!s_wph) begin s_ptr <= s_rx; s_wph <= 1'b1; end
                else        begin s_mem[s_ptr] <= s_rx; s_ptr <= s_ptr + 8'd1; end
            end
        end else if (s_bit == 4'd0) begin
            // ACK 槽结束 -> 准备下一个字节
            s_drv <= 1'b0;
            if (s_rw && s_addr_done && !s_nak) begin
                s_tx  <= s_mem_rd;
                s_ptr <= s_ptr + 8'd1;
                s_drv <= ~s_mem_rd[7];                // 组合读当前指针，位选合法
            end
        end else begin
            if (s_rw && s_addr_done && !s_nak) begin
                s_tx  <= {s_tx[6:0], 1'b0};
                s_drv <= ~s_tx[6];
            end
        end
    end

    ////////////////////////////////////////////////////////////////////////////
    // SCL 频率测量（验证分频向上取整后确实不超过 400kHz）
    ////////////////////////////////////////////////////////////////////////////
    reg [31:0] cyc_cnt = 32'd0;
    always @(posedge clk) cyc_cnt <= cyc_cnt + 32'd1;
    // 只在 busy 期间测，避免抓到上电时上拉把 scl 拉高那一下伪边沿
    reg [31:0] p1 = 32'd0, p2 = 32'd0;
    reg        got1 = 1'b0;
    always @(posedge scl) begin
        if (!m_busy) begin got1 <= 1'b0; p1 <= 32'd0; end
        else if (!got1) begin got1 <= 1'b1; p1 <= cyc_cnt; end
        else if (!p2)   begin p2 <= cyc_cnt; end
    end

    ////////////////////////////////////////////////////////////////////////////
    // 激励与自检
    ////////////////////////////////////////////////////////////////////////////
    integer err_n = 0;

    task do_txn;
        input        rw;
        input [6:0]  addr;
        input [7:0]  reg_a;
        input [7:0]  wd;
        input [3:0]  nb;
        begin
            @(posedge clk);
            m_addr   <= addr;
            m_rw     <= rw;
            m_reg    <= reg_a;
            m_wdata  <= wd;
            m_nbytes <= nb;
            m_start  <= 1'b1;
            @(posedge clk);
            m_start  <= 1'b0;
            @(posedge m_done);
            @(posedge clk);
        end
    endtask

    task chk;
        input [255:0] name;
        input         cond;
        begin
            if (cond) $display("  [PASS] %0s", name);
            else      begin $display("  [FAIL] %0s", name); err_n = err_n + 1; end
        end
    endtask

    reg [7:0] v;

    initial begin
        #200 rst_n = 1'b1;
        #200;

        // 1) 写 PWR_MGMT_1(0x6B) = 0x00
        do_txn(1'b0, DEV, 8'h6B, 8'h00, 4'd1);
        $display("[%0t] 事务1 写 0x6B=0x00 : ack_err=%0b", $time, m_ack_err);
        chk("txn1: slave ACK", m_ack_err === 1'b0);
        chk("txn1: reg[0x6B] == 0x00", s_mem[8'h6B] === 8'h00);

        // 2) 写 ACCEL_CONFIG(0x1C) = 0x18 (±16g)
        do_txn(1'b0, DEV, 8'h1C, 8'h18, 4'd1);
        $display("[%0t] 事务2 写 0x1C=0x18 : ack_err=%0b", $time, m_ack_err);
        chk("txn2: slave ACK", m_ack_err === 1'b0);
        chk("txn2: reg[0x1C] == 0x18 (+-16g)", s_mem[8'h1C] === 8'h18);

        // 3) 读 ACCEL_XOUT_H(0x3B) 起 6 字节
        do_txn(1'b1, DEV, 8'h3B, 8'h00, 4'd6);
        $display("[%0t] 事务3 读 0x3B x6 : ack_err=%0b data=%h", $time, m_ack_err, m_rdata);
        chk("txn3: slave ACK", m_ack_err === 1'b0);
        chk("txn3: read 6B == 112233445566",
            m_rdata[47:0] === 48'h11_22_33_44_55_66);

        // 4) 错误地址：应 NACK
        do_txn(1'b0, 7'h69, 8'h00, 8'h00, 4'd1);
        $display("[%0t] 事务4 错误地址 0x69 : ack_err=%0b", $time, m_ack_err);
        chk("txn4: bad addr 0x69 -> ack_err", m_ack_err === 1'b1);

        // ---- SCL 频率 ----
        if (p2 != 0) begin
            $display("SCL 实测周期 = %0d 个系统钟 -> %.1f kHz（上限 400kHz）",
                     p2 - p1, CLK_FREQ / (p2 - p1) / 1000.0);
            chk("SCL freq <= 400kHz limit", (CLK_FREQ / (p2 - p1)) <= 400000);
        end

        #2000;
        if (err_n == 0) $display("=== tb_i2c_master 全部通过 ===");
        else            $display("=== tb_i2c_master 有 %0d 项失败 ===", err_n);
        $finish;
    end

    initial begin
        #3_000_000;
        $display("[ERROR] 超时未完成，状态机可能卡死（state=%0d）", u_dut.state);
        $finish;
    end

`ifdef DUMP_I2C
    initial begin
        $dumpfile("i2c.vcd");
        $dumpvars(0, tb_i2c_master);
    end
`endif

`ifdef DBG_I2C
    // 从机侧探针：每个 SCL 边沿把内部状态打出来
    always @(negedge scl)
        $display("  SLV[%0t] scl_fall bit=%0d rw=%0b adone=%0b wph=%0b ptr=%02h rx=%02h tx=%02h drv=%0b nak=%0b",
                 $time, s_bit, s_rw, s_addr_done, s_wph, s_ptr, s_rx, s_tx, s_drv, s_nak);
    always @(posedge scl)
        $display("  SLV[%0t] scl_rise bit=%0d sda=%0b rx=%02h", $time, s_bit, sda, s_rx);
`endif

endmodule
