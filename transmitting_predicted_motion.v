
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

    // UART Receiver Signals
    reg [12:0] baud_cnt = 0;
    reg [3:0] bit_cnt = 0;
    reg [9:0] rx_shift = 10'b1111111111;
    reg receiving = 0;
    reg [7:0] rx_data = 0;
    reg data_ready = 0;

    reg byte_state = 0;
    reg [7:0] uart_x = 128;
    reg [7:0] uart_y = 128;

    // UART Receiver Logic
    always @(posedge clk50mhz) begin
        data_ready <= 0;
        if (!receiving) begin
            if (uart_rx == 0) begin
                receiving <= 1;
                baud_cnt <= BAUD_TICK / 2;
                bit_cnt <= 0;
            end
        end else begin
            if (baud_cnt == 0) begin
                baud_cnt <= BAUD_TICK - 1;
                rx_shift <= {uart_rx, rx_shift[9:1]};
                bit_cnt <= bit_cnt + 1;
                if (bit_cnt == 9) begin
                    receiving <= 0;
                    rx_data <= rx_shift[8:1];
                    data_ready <= 1;
                end
            end else begin
                baud_cnt <= baud_cnt - 1;
            end
        end
    end

    // Position History Buffers
    reg [7:0] x_history [0:19];
    reg [7:0] y_history [0:19];
    integer i;

    reg [4:0] sample_count = 0;
    reg [7:0] last_x = 128;
    reg [7:0] last_y = 128;

    reg [3:0] predict_counter = 0;
    reg [7:0] x_pos = 128;
    reg [7:0] y_pos = 128;

    reg reset_samples = 0;

    // Velocity Calculation
    wire signed [8:0] dx = x_history[19] - x_history[17];
    wire signed [8:0] dy = y_history[19] - y_history[17];

    wire signed [8:0] vx = dx >>> 4;  // approx divide by 16
    wire signed [8:0] vy = dy >>> 4;

    wire signed [8:0] pred_x = x_history[19] + (vx <<< 2);  // vx * 4
    wire signed [8:0] pred_y = y_history[19] + (vy <<< 2);  // vy * 4

    // Only predict if movement is meaningful
    wire predict_valid = (vx > 1 || vx < -1 || vy > 1 || vy < -1);

    // Final safe X/Y values (clamped between 0-255)
    wire [7:0] final_x = predict_valid ?
        ((pred_x < 0) ? 0 : (pred_x > 255) ? 255 : pred_x[7:0]) :
        x_history[19];

    wire [7:0] final_y = predict_valid ?
        ((pred_y < 0) ? 0 : (pred_y > 255) ? 255 : pred_y[7:0]) :
        y_history[19];

    // History Update & Prediction Trigger
    always @(posedge clk50mhz) begin
        if (reset_samples) begin
            sample_count <= 0;
            reset_samples <= 0;
        end

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

                    if (sample_count < 20)
                        sample_count <= sample_count + 1;

                    for (i = 0; i < 19; i = i + 1) begin
                        x_history[i] <= x_history[i+1];
                        y_history[i] <= y_history[i+1];
                    end
                    x_history[19] <= uart_x;
                    y_history[19] <= uart_y;
                end
            end
        end

        if (data_ready && byte_state == 0 && sample_count == 20) begin
            predict_counter <= predict_counter + 1;
            if (predict_counter == 10) begin
                x_pos <= final_x;
                y_pos <= final_y;
                predict_counter <= 0;
                reset_samples <= 1;
            end
        end
    end

    // Servo PWM Generation
    reg [19:0] pwm_cnt = 0;
    always @(posedge clk50mhz) begin
        if (pwm_cnt >= 20'd999_999)
            pwm_cnt <= 0;
        else
            pwm_cnt <= pwm_cnt + 1;
    end

    wire [19:0] pulse_x = 20'd25000 + x_pos * 20'd294;
    wire [19:0] pulse_y = 20'd50000 + y_pos * 20'd294;

    always @(posedge clk50mhz) begin
        servo_pwm_out_x <= (pwm_cnt < pulse_x);
        servo_pwm_out_y <= (pwm_cnt < pulse_y);
    end

    // UART TX for predicted X/Y feedback
    reg [7:0] tx_data;
    reg tx_start = 0;
    wire tx_busy;
    reg [1:0] tx_state = 0;

    uart_tx tx_module (
        .clk(clk50mhz),
        .reset(1'b0),
        .start(tx_start),
        .data_in(tx_data),
        .tx(uart_tx),
        .busy(tx_busy)
    );

    always @(posedge clk50mhz) begin
        tx_start <= 0;
        if (!tx_busy && !tx_start) begin
            case (tx_state)
                0: begin
                    tx_data <= final_y;
                    tx_start <= 1;
                    tx_state <= 1;
                end
                1: begin
                    tx_data <= final_x;
                    tx_start <= 1;
                    tx_state <= 2;
                end
                2: tx_state <= 0;
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
            baud_cnt <= 0;
            bit_cnt <= 0;
            sending <= 0;
            busy <= 0;
        end else begin
            if (start && !sending) begin
                tx_shift <= {1'b1, data_in, 1'b0};  // Stop, data, start
                sending <= 1;
                baud_cnt <= 0;
                bit_cnt <= 0;
                busy <= 1;
            end else if (sending) begin
                if (baud_cnt == 0) begin
                    tx <= tx_shift[0];
                    tx_shift <= {1'b1, tx_shift[9:1]};
                    bit_cnt <= bit_cnt + 1;
                    if (bit_cnt == 9) begin
                        sending <= 0;
                        busy <= 0;
                    end
                    baud_cnt <= BAUD_DIV - 1;
                end else begin
                    baud_cnt <= baud_cnt - 1;
                end
            end
        end
    end

endmodule
