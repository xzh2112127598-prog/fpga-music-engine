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
                // 力度曲线：平方。轻敲更轻、重敲明显更响，动态范围大。
                vgain  <= (trig_vel * trig_vel) >> 7;   // 0..126
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

    // ---- 三角波（相位高位折返，无需 ROM）----
    wire [15:0]        tri_u   = phase[31] ? (~phase[30:15]) : phase[30:15];
    wire signed [16:0] tri_s17 = {1'b0, tri_u} - 17'sd32768;    // -32768..32767
    wire signed [15:0] tri_s   = tri_s17[15:0];

    // ---- 白噪声 ----
    wire signed [15:0] noise = {1'b0, lfsr[15:1]} - 16'sd8192;     // -8192..8191

    // ---- 高通噪声（镲的金属嘶声）= 噪声 - 低通 ----
    wire signed [15:0] hp_noise = noise - lp[23:8];

    // ---- 音源选择 ----
    wire signed [15:0] src =
        (type_r == 2'd1) ? tri_s :                                  // 底鼓：三角
        (type_r == 2'd2) ? ((tri_s >>> 1) + (noise >>> 1)) :       // 军鼓：鼓皮+响弦
                           hp_noise;                                 // 镲：高通噪声

    // ---- 幅度 = 音源 × 包络 × 力度 ----
    wire [8:0] env8 = env[18:11];                        // 0..255
    wire [8:0] gain = (env8 * {1'b0, vgain}) >> 8;       // 0..126
    wire signed [24:0] prod = src * {1'b0, gain};
    assign out = prod[23:0];                             // 24bit 有符号

endmodule
