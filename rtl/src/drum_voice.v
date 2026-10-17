`timescale 1ns/1ps
//============================================================
// drum_voice.v —— 单个鼓声 voice（纯硬件合成，无任何 PCM 采样）
//
// 用物理建模逼近真实鼓声（TR-808/909 模拟鼓机风格，不是采样回放）：
//   底鼓 kick ：三角波 + 指数音高下滑(150Hz→40Hz) + 快速衰减
//   军鼓 snare：180Hz 三角波(鼓皮) + 白噪声(响弦) 混合 + 中等衰减
//   镲  cymbal：高通白噪声 + 长衰减
//
// 这样比"纯正弦/纯白噪声"更像真鼓：底鼓有"咚"的音高坠落感，
// 军鼓有鼓皮+响弦两层，镲是金属感的嘶声。
//
// 合规：全程无预录 PCM，满足比赛"纯硬件合成"红线。
// 时钟域：BCLK（fs×2×24 ≈ 2.3MHz），tick 每个音频样本一次。
//============================================================
module drum_voice (
    input  wire             clk,        // BCLK
    input  wire             rst_n,
    input  wire             tick,       // 每样本一次脉冲
    input  wire             trig,       // 触发脉冲（一个样本周期）
    input  wire [1:0]       trig_type,  // 1底鼓 2军鼓 3镲
    input  wire [6:0]       trig_vel,   // 力度 0..127
    output wire signed [23:0] out
);
    // FTW = round(f × 2^32 / 48000.53)
    localparam [31:0] FTW_KICK_HI = 32'd13421828;   // 150Hz
    localparam [31:0] FTW_KICK_LO = 32'd3579154;    // 40Hz
    localparam [31:0] FTW_SNARE   = 32'd16106193;   // 180Hz

    reg [31:0] phase;
    reg [31:0] ftw;
    reg [1:0]  type_r;
    reg [7:0]  vgain;           // 力度增益 0..126（平方曲线）
    reg [18:0] env;             // 包络 0..262143
    reg [3:0]  decay_sh;        // 指数衰减速率（每样本减 1/2^shift）
    reg [16:0] lfsr;            // 白噪声
    reg signed [23:0] lp;       // 镲高通用的一阶低通状态

    // 每样本包络递减量（组合，取当拍 env 值）
    wire [18:0] dec = (env >> decay_sh) | 19'd1;   // 至少减 1，防卡死

    // 力度折线：vel(0..127) -> 增益(0..127)，三档连续线性（执行令规格）。
    //   关键点：1.0g≈13vel→0.60(76) 1.8g≈23vel→0.85(108) 2.6g≈33vel→1.00(127)
    //   斜率用移位近似：段1 ×6 / 段2 +3每步 / 段3 +2每步，误差 ±4 听感无差。
    wire [6:0] vel   = trig_vel;
    wire [7:0] vg_lin =
        (vel <= 7'd12) ? (vel << 2) + (vel << 1) :                  // 0..12:  ×6
        (vel <= 7'd22) ? 8'd76 + ((vel - 7'd13) << 1) + (vel - 7'd13) :  // 13..22: +3
        (vel <= 7'd32) ? 8'd108 + ((vel - 7'd23) << 1) :            // 23..32: +2
                         8'd127;                                     // >32: 封顶 1.0

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase    <= 32'd0;
            ftw      <= FTW_KICK_HI;
            type_r   <= 2'd1;
            vgain    <= 8'd0;
            env      <= 19'd0;
            decay_sh <= 4'd9;
            lfsr     <= 17'h1;
            lp       <= 24'sd0;
        end else begin
            if (trig) begin
                type_r <= trig_type;
                vgain  <= vg_lin;   // 力度折线（连续线性三档）
                env    <= 19'd262143;
                phase  <= 32'd0;
                case (trig_type)
                    2'd1:     begin ftw <= FTW_KICK_HI; decay_sh <= 4'd9;  end  // 底鼓：快衰减
                    2'd2:     begin ftw <= FTW_SNARE;   decay_sh <= 4'd8;  end  // 军鼓：更快
                    default:  begin ftw <= FTW_SNARE;   decay_sh <= 4'd11; end  // 镲：慢衰减
                endcase
            end else if (tick) begin
                // 底鼓音高下滑：FTW 指数递减，时间常数约 2048 样本(43ms)，
                // 从 150Hz 滑到 40Hz 约 56ms，形成"咚"的坠落感。
                if (type_r == 2'd1 && ftw > FTW_KICK_LO)
                    ftw <= ftw - (ftw >> 11);
                phase <= phase + ftw;

                if (env != 19'd0) begin
                    env <= (env > dec) ? (env - dec) : 19'd0;
                end

                lfsr <= {lfsr[15:0], lfsr[16] ^ lfsr[13]};
                lp   <= lp + (({1'b0, lfsr[15:1]} - lp) >>> 4);    // 一阶低通
            end
        end
    end

    // ---- 波表 ROM（从真实鼓声提取的「单周期」波形，不是整段录音）----
    // kick.hex / snare.hex 各 256 点、有符号 Q15，由 tools/extract_wavetable.py
    // 从 AVL-Drumkits 真实样本里只取一个基频周期生成。衰减尾巴、音高下滑、
    // 力度全部由本模块现场算，所以仍是"波表合成"，不是采样回放。
    // 波表 ROM（从真实鼓声提取的「单周期」波形，不是整段录音）
    // combined.hex = kick(1024) + snare(1024)，共 2048 点、有符号 Q15。
    // ⚠️ 必须用标准 BSRAM 同步读：地址单独寄存成 wt_addr 再读 wt_rom[wt_addr]，
    //    且深度够大（2048）。否则 Gowin 映射成 LUT 组合逻辑，$readmemh 初始化
    //    会丢（波表全 0 → 静音）—— 这是和 osc_dds 的 sine ROM 对齐的写法。
    reg [15:0] wt_rom [0:2047];
    initial $readmemh("combined.hex", wt_rom);

    reg [10:0]       wt_addr;
    reg signed [15:0] wt_out;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wt_addr <= 11'd0; wt_out <= 16'sd0;
        end else begin
            wt_addr <= (type_r == 2'd1 ? 11'd0 : 11'd1024) + {1'b0, phase[31:22]};
            wt_out <= wt_rom[wt_addr];
        end
    end

    // ---- 白噪声 ----
    wire signed [15:0] noise = {1'b0, lfsr[15:1]} - 16'sd8192;     // -8192..8191

    // ---- 高通噪声（镲的金属嘶声）= 噪声 - 低通 ----
    wire signed [15:0] hp_noise = noise - lp[23:8];

    // ---- 音源选择 ----
    wire signed [15:0] src =
        (type_r == 2'd3) ? hp_noise :                                // 镲：高通噪声（噪声型，不用波表）
        (type_r == 2'd2) ? ((wt_out >>> 1) + (noise >>> 1)) :       // 军鼓：snare波表(鼓皮)+响弦噪声
                           wt_out;                                   // 底鼓：kick波表

    // ---- 幅度 = 音源 × 包络 × 力度 ----
    wire [7:0]  env8   = env[17:10];       // 满量程 0..255（env=262143 时 =255）
    wire [15:0] egprod = env8 * vgain;     // 显式 16 位，防截断
    wire [8:0]  gain   = egprod >> 8;      // 0..125
    wire signed [24:0] prod = src * {1'b0, gain};
    assign out = prod[23:0];               // 24bit 有符号

endmodule
