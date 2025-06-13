module servo_control(
    input  wire clk50mhz,    // 50 MHz clock input (LOC = C9)
    input  wire reset,       // synchronous reset
    input  wire rot_push,    // rotary encoder center push (FPGA pin V16)
    output reg  servo_pwm_out // PWM output to servo (connected to J4 header pin)
);

    // 50MHz / 20ms = 1,000,000 counts for period
    reg [19:0] cnt;
    reg [7:0] position;   // 0..255 servo position value
    reg direction;        // 1 = increasing, 0 = decreasing
    reg run_flag;         // continuous sweep enable

    // Synchronize and detect push-button edges
    reg rot_sync_0, rot_sync_1, last_push;
    always @(posedge clk50mhz) begin
        rot_sync_0 <= rot_push;
        rot_sync_1 <= rot_sync_0;
    end
    always @(posedge clk50mhz) begin
        if (reset) begin
            last_push <= 1'b0;
            run_flag  <= 1'b0;
        end else begin
            if (rot_sync_1 && !last_push) begin
                run_flag <= ~run_flag; // toggle on rising edge
            end
            last_push <= rot_sync_1;
        end
    end

    // Update position at each 20ms period if sweep is enabled
    always @(posedge clk50mhz) begin
        if (reset) begin
            position  <= 8'd0;
            direction <= 1'b1;
        end else if (cnt == 20'd1000000-1) begin
            // At end of period (20ms), step position if running
            if (run_flag) begin
                if (direction) begin
                    if (position == 8'd255) begin
                        direction <= 1'b0;
                        position  <= position - 8'd1;
                    end else begin
                        position <= position + 8'd1;
                    end
                end else begin
                    if (position == 8'd0) begin
                        direction <= 1'b1;
                        position  <= position + 8'd1;
                    end else begin
                        position <= position - 8'd1;
                    end
                end
            end
        end
    end

    // Main PWM counter and output logic
    always @(posedge clk50mhz) begin
        if (reset) begin
            cnt           <= 20'd0;
            servo_pwm_out <= 1'b0;
        end else begin
            // 20ms period counter
            if (cnt == 20'd1000000-1) begin
                cnt <= 20'd0;
            end else begin
                cnt <= cnt + 20'd1;
            end

            // Calculate pulse width: 1ms + (position/255)*(1ms)
            // Position * 196 ≈ (position/255)*50000
            if (cnt < (20'd50000 + position * 20'd196))
                servo_pwm_out <= 1'b1;
            else
                servo_pwm_out <= 1'b0;
        end
    end

endmodule
