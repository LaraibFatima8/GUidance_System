module missile_predictor_fpga(
    input clk50mhz,
    input uart_rx,
    output reg servo_pwm_out_x,
    output reg servo_pwm_out_y
);

    parameter CLK_FREQ = 50000000;
    parameter BAUD_RATE = 9600;
    parameter BAUD_TICK = CLK_FREQ / BAUD_RATE;

    // UART receiver
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

    // Position history for 20 meaningful frames
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

    // Prediction logic
    wire signed [8:0] dx = x_history[19] - x_history[0];
    wire signed [8:0] dy = y_history[19] - y_history[0];

    wire signed [8:0] vx = dx >>> 4;  // Approx divide by 16
    wire signed [8:0] vy = dy >>> 4;

    wire signed [8:0] pred_x = x_history[19] + vx * 10;
    wire signed [8:0] pred_y = y_history[19] + vy * 10;

    wire [7:0] final_x = (pred_x < 0) ? 0 : (pred_x > 255) ? 255 : pred_x[7:0];
    wire [7:0] final_y = (pred_y < 0) ? 0 : (pred_y > 255) ? 255 : pred_y[7:0];

    // Main control block (handles reset_samples in one place)
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

    // PWM generation for servos
    reg [19:0] pwm_cnt = 0;
    always @(posedge clk50mhz) begin
        if (pwm_cnt >= 20'd999_999)
            pwm_cnt <= 0;
        else
            pwm_cnt <= pwm_cnt + 1;
    end

    wire [19:0] pulse_x = 20'd50000 + x_pos * 20'd196;
    wire [19:0] pulse_y = 20'd50000 + y_pos * 20'd196;

    always @(posedge clk50mhz) begin
        servo_pwm_out_x <= (pwm_cnt < pulse_x);
        servo_pwm_out_y <= (pwm_cnt < pulse_y);
    end

endmodule
