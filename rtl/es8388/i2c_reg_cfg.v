//============================================================
// 本文件从指导老师提供的参考工程 voice_changer_phone（安路 EG4S20）
// 原样移植到本项目（高云 GW5A / Tang Primer 25K），逻辑未做改动。
// 来源目录：Desktop/voice_changer_phone/rtl —— 2026-10-10
//============================================================
module i2c_reg_cfg #(
    parameter WL = 6'd24
)(
    input               clk,
    input               rst_n,
    input               i2c_done,
    output reg          i2c_exec,
    output reg          cfg_done,
    output reg [15:0]   i2c_data
);

localparam REG_NUM = 5'd24;

reg [7:0]   start_init_cnt;
reg [4:0]   init_reg_cnt;

// 上电或复位后保留固定初始化延时，再开始第一笔I2C配置。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        start_init_cnt <= 8'd0;
    else if(start_init_cnt < 8'hff)
        start_init_cnt <= start_init_cnt + 1'b1;
end

// 第一笔配置由启动延时结束触发，之后每笔配置由上一笔I2C完成信号继续触发。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        i2c_exec <= 1'b0;
    else if((init_reg_cnt == 5'd0) && (start_init_cnt == 8'hfe))
        i2c_exec <= 1'b1;
    else if(i2c_done && (init_reg_cnt < REG_NUM))
        i2c_exec <= 1'b1;
    else
        i2c_exec <= 1'b0;
end

// 每发起一次I2C寄存器写操作就进入下一项配置。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        init_reg_cnt <= 5'd0;
    else if(i2c_exec)
        init_reg_cnt <= init_reg_cnt + 1'b1;
end

// 最后一项寄存器写入完成后保持cfg_done为高电平。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        cfg_done <= 1'b0;
    else if(i2c_done && (init_reg_cnt == REG_NUM))
        cfg_done <= 1'b1;
end

// 依次给出ES8388的寄存器地址和8位配置数据。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        i2c_data <= 16'd0;
    else begin
        case(init_reg_cnt)
            // R0：ADC与DAC使用相同采样率，并使能VREF和VMID。
            5'd0:  i2c_data <= {8'h00, 8'h16};
            // R1：打开模拟电源相关模块。
            5'd1:  i2c_data <= {8'h01, 8'h00};
            // R2：打开ADC、DAC数字电源和参考电源。
            5'd2:  i2c_data <= {8'h02, 8'h00};
            // R3：打开ADC模拟输入、ADC和麦克风偏置相关电源。
            5'd3:  i2c_data <= {8'h03, 8'h00};
            // R4：打开左右DAC和LOUT1/ROUT1/LOUT2/ROUT2输出。
            5'd4:  i2c_data <= {8'h04, 8'h3c};
            // R8：ES8388工作在主模式，BCLK由芯片按照采样率表自动产生。
            5'd5:  i2c_data <= {8'h08, 8'h80};
            // R9：左右麦克风PGA均设置为+6dB。
            5'd6:  i2c_data <= {8'h09, 8'h22};
            // R12：ADC使用24位I2S格式。
            5'd7:  i2c_data <= {8'h0c, 8'h00};
            // R13：保持原工程Normal Mode，MCLK/256约等于48kHz，比例编码为00010。
            5'd8:  i2c_data <= {8'h0d, 8'h02};
            // R16：左ADC数字音量0dB。
            5'd9:  i2c_data <= {8'h10, 8'h00};
            // R17：右ADC数字音量0dB。
            5'd10: i2c_data <= {8'h11, 8'h00};
            // R18：保持原工程ALC和PGA增益范围设置。
            5'd11: i2c_data <= {8'h12, 8'hf8};
            // R23：DAC使用24位I2S格式。
            5'd12: i2c_data <= {8'h17, 8'h00};
            // R24：保持原工程Normal Mode，MCLK/256约等于48kHz，比例编码为00010。
            5'd13: i2c_data <= {8'h18, 8'h02};
            // R26：左DAC数字音量0dB。
            5'd14: i2c_data <= {8'h1a, 8'h00};
            // R27：右DAC数字音量0dB。
            5'd15: i2c_data <= {8'h1b, 8'h00};
            // R39：使能左DAC到左输出混音器的数字通路。
            5'd16: i2c_data <= {8'h27, 8'hb8};
            // R42：使能右DAC到右输出混音器的数字通路。
            5'd17: i2c_data <= {8'h2a, 8'hb8};
            // R43：ADC和DAC共用同一个LRCK。
            5'd18: i2c_data <= {8'h2b, 8'h80};
            // R46：LOUT1固定使用原工程0x1A输出音量。
            5'd19: i2c_data <= {8'h2e, 8'h1a};
            // R47：ROUT1固定使用原工程0x1A输出音量。
            5'd20: i2c_data <= {8'h2f, 8'h1a};
            // R48：LOUT2固定使用原工程0x1A输出音量。
            5'd21: i2c_data <= {8'h30, 8'h1a};
            // R49：ROUT2固定使用原工程0x1A输出音量。
            5'd22: i2c_data <= {8'h31, 8'h1a};
            // R10：选择第一组麦克风模拟输入作为ADC输入。
            5'd23: i2c_data <= {8'h0a, 8'h00};
            default: i2c_data <= i2c_data;
        endcase
    end
end

endmodule
