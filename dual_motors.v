module dual_servo_uart(
    input clk50mhz,
    input uart_rx,
    output reg servo_pwm_out_a, // Motor A
    output reg servo_pwm_out_b  // Motor B (mirrored)
);

    parameter CLK_FREQ = 50000000;
    parameter BAUD_RATE = 9600;
    parameter BAUD_TICK = CLK_FREQ / BAUD_RATE;

    reg [12:0] baud_cnt = 0;
    reg [3:0] bit_cnt = 0;
    reg [9:0] rx_shift = 10'b1111111111;
    reg receiving = 0;
    reg [7:0] rx_data = 8'd0;
    reg data_ready = 0;

    // UART Receiver
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

    // Smooth position
    reg [7:0] x_position = 8'd128;
    reg [19:0] pwm_cnt = 0;

    always @(posedge clk50mhz) begin
        if (data_ready) begin
            // DO NOT invert for main direction logic
            if (rx_data < 8'd255)
                x_position <= rx_data;
        end
    end

    // PWM Counter
    always @(posedge clk50mhz) begin
        if (pwm_cnt >= 20'd999_999)
            pwm_cnt <= 0;
        else
            pwm_cnt <= pwm_cnt + 1;
    end

    // Motor A: standard
    wire [19:0] pulse_width_a = 20'd50000 + x_position * 20'd196;

    // Motor B: mirrored direction (255 - x)
    wire [19:0] pulse_width_b = 20'd50000 + (8'd255 - x_position) * 20'd196;

    // Output PWM to both servos
    always @(posedge clk50mhz) begin
        servo_pwm_out_a <= (pwm_cnt < pulse_width_a);
        servo_pwm_out_b <= (pwm_cnt < pulse_width_b);
    end

endmodule
