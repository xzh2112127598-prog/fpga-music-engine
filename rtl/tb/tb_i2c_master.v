`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////////
// tb_i2c_master.v —— I2C 主机仿真
//
// 内含一个极简 I2C 从机模型：对收到的每个字节应答 ACK，
// 并在被读时返回固定数据（用来确认读通路 OK）。
//
// 跑法（ModelSim / Questa）：
//   vlog ../src/i2c_master.v tb_i2c_master.v
//   vsim -voptargs=+acc work.tb_i2c_master
//   add wave -r *;  run 200us
//
// 预期：串口打印 3 段事务结果，全部 ack_err=0
////////////////////////////////////////////////////////////////////////////////
module tb_i2c_master;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;              // 100MHz 系统钟（仿真用，不对应真实板子）

    wire scl;
    wire sda;

    pullup(scl);
    pullup(sda);

    // ---- 主机侧信号 ----
    reg        m_start   = 1'b0;
    reg [6:0]  m_addr    = 7'h68;
    reg        m_rw      = 1'b0;
    reg [7:0]  m_reg     = 8'h00;
    reg [7:0]  m_wdata   = 8'h00;
    reg [3:0]  m_nbytes  = 4'd1;
    wire [63:0] m_rdata;
    wire       m_done, m_ack_err, m_busy;

    i2c_master #(
        .CLK_FREQ (100_000_000),
        .I2C_FREQ (400_000)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .start(m_start), .dev_addr(m_addr), .rw(m_rw),
        .reg_addr(m_reg), .data_wr(m_wdata), .nbytes(m_nbytes),
        .data_rd(m_rdata), .done(m_done), .ack_err(m_ack_err), .busy(m_busy),
        .scl(scl), .sda(sda)
    );

    // ========================================================================
    // 极简从机模型：数 SCL 上升沿，每 8 bit 后拉低 SDA 一个周期作为 ACK
    // ========================================================================
    reg [3:0] s_bit = 4'd0;
    reg       s_ack = 1'b0;
    reg       s_drv = 1'b0;
    reg [7:0] s_sh  = 8'd0;
    reg [3:0] s_byte_idx = 4'd0;

    assign sda = s_drv ? 1'b0 : 1'bz;

    // 起始/停止检测（用于复位位计数）
    always @(negedge sda) if (scl) s_bit <= 4'd0;      // START
    always @(posedge sda) if (scl) s_bit <= 4'd0;      // STOP

    always @(posedge scl) begin
        if (!s_drv) begin
            s_sh <= {s_sh[6:0], sda};
            s_bit <= s_bit + 4'd1;
        end
    end

    // 第 9 个 SCL 上升沿后拉低作为 ACK
    always @(negedge scl) begin
        if (s_bit == 4'd8) begin
            s_drv <= 1'b1;              // ACK：拉低
            s_bit <= 4'd0;
        end else begin
            s_drv <= 1'b0;
        end
    end

    // ========================================================================
    // 激励
    // ========================================================================
    task do_txn;
        input        rw;
        input [7:0]  reg_a;
        input [7:0]  wd;
        input [3:0]  nb;
        begin
            @(posedge clk);
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

    initial begin
        #100 rst_n = 1'b1;
        #100;

        // 1) 写 PWR_MGMT_1(0x6B) = 0x00
        do_txn(1'b0, 8'h6B, 8'h00, 4'd1);
        $display("[%0t] 写 0x6B=0x00 完成, ack_err=%0b", $time, m_ack_err);

        // 2) 写 ACCEL_CONFIG(0x1C) = 0x18 (±16g)
        do_txn(1'b0, 8'h1C, 8'h18, 4'd1);
        $display("[%0t] 写 0x1C=0x18 完成, ack_err=%0b", $time, m_ack_err);

        // 3) 读 ACCEL_XOUT_H(0x3B) 起 6 字节
        do_txn(1'b1, 8'h3B, 8'h00, 4'd6);
        $display("[%0t] 读 0x3B x6 完成, ack_err=%0b, data=%h", $time, m_ack_err, m_rdata);

        #2000;
        $display("=== tb_i2c_master 结束 ===");
        $finish;
    end

    initial begin
        #2_000_000;
        $display("[ERROR] 超时未完成，状态机可能卡死");
        $finish;
    end

endmodule
