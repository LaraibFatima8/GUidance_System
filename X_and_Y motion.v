module dual_axis_servo_uart_single_rx(
    input clk50mhz,
    input uart_rx,
    output reg servo_pwm_out_x,
    output reg servo_pwm_out_y
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

    reg [7:0] x_target = 8'd128;
    reg [7:0] y_target = 8'd128;
    reg [7:0] x_position = 8'd128;
    reg [7:0] y_position = 8'd128;
    reg [15:0] smooth_cnt = 0;
    reg [19:0] pwm_cnt = 0;

    reg toggle_axis = 0;  // 0 = next byte is X, 1 = next is Y

    // UART RX logic
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

    // Assign incoming byte alternately to x or y
    always @(posedge clk50mhz) begin
        if (data_ready) begin
            if (toggle_axis == 0) begin
                x_target <= rx_data;
            end else begin
                y_target <= rx_data;
            end
            toggle_axis <= ~toggle_axis;
        end
    end

    // Smooth transition logic
    always @(posedge clk50mhz) begin
        if (smooth_cnt >= 16'd25000) begin
            smooth_cnt <= 0;

            if (x_position < x_target)
                x_position <= x_position + 1;
            else if (x_position > x_target)
                x_position <= x_position - 1;

            if (y_position < y_target)
                y_position <= y_position + 1;
            else if (y_position > y_target)
                y_position <= y_position - 1;
        end else begin
            smooth_cnt <= smooth_cnt + 1;
        end
    end

    // PWM counter (20 ms)
    always @(posedge clk50mhz) begin
        if (pwm_cnt >= 20'd999_999)
            pwm_cnt <= 0;
        else
            pwm_cnt <= pwm_cnt + 1;
    end

    // Pulse widths (1ms - 2ms)
    wire [19:0] pulse_width_x = 20'd50000 + x_position * 20'd196;
    wire [19:0] pulse_width_y = 20'd50000 + y_position * 20'd196;

    // PWM outputs
    always @(posedge clk50mhz) begin
        servo_pwm_out_x <= (pwm_cnt < pulse_width_x);
        servo_pwm_out_y <= (pwm_cnt < pulse_width_y);
    end

endmodule
