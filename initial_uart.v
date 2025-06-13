module uart_servo(
    input clk50mhz,           // 50 MHz system clock
    input uart_rx,            // UART RX input (from PC/USB via M13)
    output reg servo_pwm_out  // PWM output to servo (D7 pin)
);

    // ===== UART Receiver Parameters =====
    parameter CLK_FREQ = 50000000;
    parameter BAUD_RATE = 9600;
    parameter BAUD_TICK = CLK_FREQ / BAUD_RATE;  // 5208 for 9600 baud

    reg [12:0] baud_cnt = 0;
    reg [3:0]  bit_cnt = 0;
    reg [9:0]  rx_shift = 10'b1111111111;
    reg receiving = 0;
    reg [7:0] rx_data = 8'd0;
    reg data_ready = 0;

    // ===== UART Receiver =====
    always @(posedge clk50mhz) begin
        data_ready <= 0;  // default

        if (!receiving) begin
            if (uart_rx == 0) begin  // Start bit
                receiving <= 1;
                baud_cnt <= BAUD_TICK / 2;  // sample in middle
                bit_cnt <= 0;
            end
        end else begin
            if (baud_cnt == 0) begin
                baud_cnt <= BAUD_TICK - 1;
                rx_shift <= {uart_rx, rx_shift[9:1]};
                bit_cnt <= bit_cnt + 1;

                if (bit_cnt == 9) begin
                    receiving <= 0;
                    rx_data <= rx_shift[8:1];  // only 8 data bits
                    data_ready <= 1;
                end
            end else begin
                baud_cnt <= baud_cnt - 1;
            end
        end
    end

    // ===== Servo Position and Smoothing =====
    reg [7:0] x_target = 8'd128;    // Inverted UART input
    reg [7:0] x_position = 8'd128;  // Slowly approaches x_target
    reg [19:0] pwm_cnt = 0;         // For 20ms cycle

    // Update target position when UART receives new byte
    always @(posedge clk50mhz) begin
        if (data_ready)
            x_target <= 8'd255 - rx_data;  // Invert: Left = +90°, Right = -90°
    end

    // Smooth transition toward x_target, once per 20ms cycle
    always @(posedge clk50mhz) begin
        if (pwm_cnt == 0) begin
            if (x_position < x_target)
                x_position <= x_position + 1;
            else if (x_position > x_target)
                x_position <= x_position - 1;
        end
    end

    // ===== PWM Generator (20ms cycle, 1-2ms pulse) =====
    always @(posedge clk50mhz) begin
        if (pwm_cnt >= 20'd999_999)
            pwm_cnt <= 0;
        else
            pwm_cnt <= pwm_cnt + 1;
    end

    // Map x_position to 1ms-2ms pulse width
    wire [19:0] pulse_width = 20'd50000 + x_position * 20'd392;

    always @(posedge clk50mhz) begin
        servo_pwm_out <= (pwm_cnt < pulse_width);
    end

endmodule
