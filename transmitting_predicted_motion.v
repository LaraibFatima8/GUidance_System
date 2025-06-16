module missile_predictor_fpga(
    input clk50mhz,
    input uart_rx,
    output reg servo_pwm_out_x,
    output reg servo_pwm_out_y,
    output uart_tx
);

    parameter CLK_FREQ = 50000000;
    parameter BAUD_RATE = 9600;
    parameter BAUD_TICK = CLK_FREQ / BAUD_RATE;

    // UART RX Setup
    reg [12:0] baud_cnt = 0;
    reg [3:0] bit_cnt = 0;
    reg [9:0] rx_shift = 10'b1111111111;
    reg receiving = 0;
    reg [7:0] rx_data = 0;
    reg data_ready = 0;

    reg byte_state = 0;
    reg [7:0] uart_x = 128;
    reg [7:0] uart_y = 128;

    always @(posedge clk50mhz) begin
        data_ready <= 0;
        if (!receiving && uart_rx == 0) begin
            receiving <= 1;
            baud_cnt <= BAUD_TICK / 2;
            bit_cnt <= 0;
        end else if (receiving) begin
            if (baud_cnt == 0) begin
                rx_shift <= {uart_rx, rx_shift[9:1]};
                bit_cnt <= bit_cnt + 1;
                if (bit_cnt == 9) begin
                    receiving <= 0;
                    rx_data <= rx_shift[8:1];
                    data_ready <= 1;
                end
                baud_cnt <= BAUD_TICK - 1;
            end else begin
                baud_cnt <= baud_cnt - 1;
            end
        end
    end

    // History Buffer
    reg signed [8:0] x_history [0:19];
    reg signed [8:0] y_history [0:19];
    integer i;
    reg [4:0] sample_count = 0;

    reg [7:0] last_x = 128, last_y = 128;
    reg [7:0] x_pos = 128, y_pos = 128;

    // Velocity and Prediction
    wire signed [8:0] dx = x_history[19] - x_history[14];
    wire signed [8:0] dy = y_history[19] - y_history[14];

    wire signed [8:0] vx = dx >>> 2;
    wire signed [8:0] vy = dy >>> 2;

    wire signed [8:0] pred_x = x_history[19] + (vx <<< 1);
    wire signed [8:0] pred_y = y_history[19] + (vy <<< 1);

    wire predict_ready = (sample_count >= 20);

    wire [7:0] final_x = predict_ready ? ((pred_x < 0) ? 8'd0 : (pred_x > 255) ? 8'd255 : pred_x[7:0]) : x_pos;
    wire [7:0] final_y = predict_ready ? ((pred_y < 0) ? 8'd0 : (pred_y > 255) ? 8'd255 : pred_y[7:0]) : y_pos;

    wire [7:0] final_vx = (vx < 0) ? 8'd0 : (vx > 255) ? 8'd255 : vx[7:0];
    wire [7:0] final_vy = (vy < 0) ? 8'd0 : (vy > 255) ? 8'd255 : vy[7:0];

    // History Update
    always @(posedge clk50mhz) begin
        if (data_ready) begin
            if (byte_state == 0) begin
                uart_x <= rx_data;
                byte_state <= 1;
            end else begin
                uart_y <= rx_data;
                byte_state <= 0;

                if ((uart_x != last_x) || (uart_y != last_y)) begin
                    last_x <= uart_x;
                    last_y <= uart_y;

                    for (i = 0; i < 19; i = i + 1) begin
                        x_history[i] <= x_history[i+1];
                        y_history[i] <= y_history[i+1];
                    end
                    x_history[19] <= uart_x;
                    y_history[19] <= uart_y;

                    if (sample_count < 20)
                        sample_count <= sample_count + 1;
                end

                if (predict_ready) begin
                    x_pos <= final_x;
                    y_pos <= final_y;
                    sample_count <= 0;

                    for (i = 0; i < 20; i = i + 1) begin
                        x_history[i] <= 0;
                        y_history[i] <= 0;
                    end
                end
            end
        end
    end

    // Servo PWM
    reg [19:0] pwm_cnt = 0;
    always @(posedge clk50mhz)
        pwm_cnt <= (pwm_cnt == 999_999) ? 0 : pwm_cnt + 1;

    wire [19:0] pulse_x = 20'd25000 + x_pos * 20'd294;
    wire [19:0] pulse_y = 20'd25000 + y_pos * 20'd294;

    always @(posedge clk50mhz) begin
        servo_pwm_out_x <= (predict_ready && pwm_cnt < pulse_x);
        servo_pwm_out_y <= (predict_ready && pwm_cnt < pulse_y);
    end

    // UART TX: Send 4 bytes
    reg [2:0] tx_state = 0;
    reg [7:0] tx_data = 0;
    reg tx_start = 0;
    wire tx_busy;

    uart_tx tx_inst (
        .clk(clk50mhz),
        .reset(1'b0),
        .start(tx_start),
        .data_in(tx_data),
        .tx(uart_tx),
        .busy(tx_busy)
    );

    always @(posedge clk50mhz) begin
        tx_start <= 0;
        if (!tx_busy && predict_ready && !tx_start) begin
            case (tx_state)
                0: begin tx_data <= final_y;  tx_start <= 1; tx_state <= 1; end
                1: begin tx_data <= final_x;  tx_start <= 1; tx_state <= 2; end
                2: begin tx_data <= final_vy; tx_start <= 1; tx_state <= 3; end
                3: begin tx_data <= final_vx; tx_start <= 1; tx_state <= 4; end
                4: tx_state <= 0;
            endcase
        end
    end

endmodule

module uart_tx (
    input clk,
    input reset,
    input start,
    input [7:0] data_in,
    output reg tx,
    output reg busy
);

    parameter CLK_FREQ = 50000000;
    parameter BAUD_RATE = 9600;
    parameter BAUD_DIV = CLK_FREQ / BAUD_RATE;

    reg [13:0] baud_cnt = 0;
    reg [3:0] bit_cnt = 0;
    reg [9:0] tx_shift = 10'b1111111111;
    reg sending = 0;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tx <= 1;
            sending <= 0;
            busy <= 0;
            bit_cnt <= 0;
        end else begin
            if (start && !sending) begin
                tx_shift <= {1'b1, data_in, 1'b0};
                sending <= 1;
                busy <= 1;
                baud_cnt <= BAUD_DIV - 1;
                bit_cnt <= 0;
            end else if (sending) begin
                if (baud_cnt == 0) begin
                    tx <= tx_shift[0];
                    tx_shift <= {1'b1, tx_shift[9:1]};
                    bit_cnt <= bit_cnt + 1;
                    baud_cnt <= BAUD_DIV - 1;
                    if (bit_cnt == 9) begin
                        sending <= 0;
                        busy <= 0;
                        tx <= 1;
                    end
                end else begin
                    baud_cnt <= baud_cnt - 1;
                end
            end
        end
    end
endmodule
