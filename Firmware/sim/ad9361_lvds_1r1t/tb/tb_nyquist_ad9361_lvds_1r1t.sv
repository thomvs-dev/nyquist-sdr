// SPDX-License-Identifier: MIT

`timescale 1ns/1ps

module tb_nyquist_ad9361_lvds_1r1t;

    logic rst = 1'b0;

    logic       rx_clk_p = 1'b0;
    logic       rx_clk_n;
    logic       rx_frame_p = 1'b0;
    logic       rx_frame_n;
    logic [5:0] rx_d_p = 6'd0;
    logic [5:0] rx_d_n;

    logic        rx_sample_valid;
    logic [11:0] rx_i;
    logic [11:0] rx_q;
    logic [31:0] rx_packed;

    logic        tx_sample_valid = 1'b0;
    logic [11:0] tx_i = 12'd0;
    logic [11:0] tx_q = 12'd0;

    logic       tx_clk_p;
    logic       tx_clk_n;
    logic       tx_frame_p;
    logic       tx_frame_n;
    logic [5:0] tx_d_p;
    logic [5:0] tx_d_n;

    logic [31:0] rx_sample_count;
    logic [31:0] tx_sample_count;
    logic [31:0] rx_frame_error_count;
    logic [31:0] rx_diff_error_count;

    logic [1:0]  tx_check_phase = 2'd0;
    logic [11:0] tx_check_i = 12'd0;
    logic [11:0] tx_check_q = 12'd0;
    logic [11:0] expected_tx_i = 12'd0;
    logic [11:0] expected_tx_q = 12'd0;

    integer sample_index;
    integer errors = 0;
    integer checked_rx_samples = 0;
    integer checked_tx_samples = 0;
    integer inject_frame_error;
    reg [8*256-1:0] vcd_file;

    assign rx_clk_n   = ~rx_clk_p;
    assign rx_frame_n = ~rx_frame_p;
    assign rx_d_n     = ~rx_d_p;

    nyquist_ad9361_lvds_1r1t_demo dut (
        .rst,
        .rx_clk_p,
        .rx_clk_n,
        .rx_frame_p,
        .rx_frame_n,
        .rx_d_p,
        .rx_d_n,
        .rx_sample_valid,
        .rx_i,
        .rx_q,
        .rx_packed,
        .tx_sample_valid,
        .tx_i,
        .tx_q,
        .tx_clk_p,
        .tx_clk_n,
        .tx_frame_p,
        .tx_frame_n,
        .tx_d_p,
        .tx_d_n,
        .rx_sample_count,
        .tx_sample_count,
        .rx_frame_error_count,
        .rx_diff_error_count
    );

    task automatic check_tx_edge;
        logic expected_frame;
        begin
            expected_frame = (tx_check_phase < 2);

            if ((tx_clk_n !== ~tx_clk_p) ||
                (tx_frame_n !== ~tx_frame_p) ||
                (tx_d_n !== ~tx_d_p)) begin
                $display("ERROR TX differential complement failure at t=%0t", $time);
                errors = errors + 1;
            end

            if (tx_frame_p !== expected_frame) begin
                $display("ERROR TX frame phase=%0d expected=%0b got=%0b", tx_check_phase,
                    expected_frame, tx_frame_p);
                errors = errors + 1;
            end

            case (tx_check_phase)
                2'd0: tx_check_i[11:6] = tx_d_p;
                2'd1: tx_check_q[11:6] = tx_d_p;
                2'd2: tx_check_i[5:0]  = tx_d_p;
                2'd3: begin
                    tx_check_q[5:0] = tx_d_p;
                    if ((tx_check_i !== expected_tx_i) ||
                        (tx_check_q !== expected_tx_q)) begin
                        $display("ERROR TX sample expected I=%03h Q=%03h got I=%03h Q=%03h",
                            expected_tx_i, expected_tx_q, tx_check_i, tx_check_q);
                        errors = errors + 1;
                    end else begin
                        checked_tx_samples = checked_tx_samples + 1;
                    end
                end
            endcase

            tx_check_phase = tx_check_phase + 1'b1;
        end
    endtask

    task automatic transfer_edge(
        input logic [5:0] lane_data,
        input logic       frame_value
    );
        begin
            rx_d_p = lane_data;
            rx_frame_p = frame_value;
            #4;
            rx_clk_p = ~rx_clk_p;
            #1;
            check_tx_edge();
            #5;
        end
    endtask

    task automatic transfer_sample(
        input logic [11:0] expected_rx_i,
        input logic [11:0] expected_rx_q,
        input logic        corrupt_frame
    );
        logic [31:0] expected_packed;
        begin
            expected_packed = {expected_rx_i, 4'b0000, expected_rx_q, 4'b0000};

            transfer_edge(expected_rx_i[11:6], 1'b1);
            transfer_edge(expected_rx_q[11:6], 1'b1);
            transfer_edge(expected_rx_i[5:0], corrupt_frame ? 1'b1 : 1'b0);
            transfer_edge(expected_rx_q[5:0], 1'b0);

            if (!rx_sample_valid) begin
                $display("ERROR RX sample_valid missing for sample %0d", sample_index);
                errors = errors + 1;
            end
            if ((rx_i !== expected_rx_i) || (rx_q !== expected_rx_q)) begin
                $display("ERROR RX expected I=%03h Q=%03h got I=%03h Q=%03h",
                    expected_rx_i, expected_rx_q, rx_i, rx_q);
                errors = errors + 1;
            end else begin
                checked_rx_samples = checked_rx_samples + 1;
            end
            if (rx_packed !== expected_packed) begin
                $display("ERROR PACK expected=%08h got=%08h", expected_packed, rx_packed);
                errors = errors + 1;
            end

            $display("SAMPLE %02d RX I=%03h Q=%03h PACK=%08h | TX I=%03h Q=%03h",
                sample_index, rx_i, rx_q, rx_packed, expected_tx_i, expected_tx_q);
        end
    endtask

    initial begin
        // Generate a real reset edge so every behavioral state element is
        // initialized in simulators that do not trigger on an initial value.
        rst = 1'b1;
        inject_frame_error = $test$plusargs("INJECT_FRAME_ERROR");
        if (!$value$plusargs("VCD=%s", vcd_file))
            vcd_file = "ad9361_lvds_1r1t.vcd";

        $dumpfile(vcd_file);
        $dumpvars(0, tb_nyquist_ad9361_lvds_1r1t);

        $display("============================================================");
        $display("NYQUIST SDR AD9361 1R1T DDR LVDS INTERFACE SIMULATION");
        $display("Wire order per complex sample: Ihi, Qhi, Ilo, Qlo");
        $display("Frame pattern: 1, 1, 0, 0");
        $display("Fault injection enabled: %0d", inject_frame_error);
        $display("============================================================");

        #12;
        rst = 1'b0;
        tx_sample_valid = 1'b1;

        for (sample_index = 0; sample_index < 16; sample_index = sample_index + 1) begin
            expected_tx_i = 12'h300 + sample_index;
            expected_tx_q = 12'hC00 + sample_index;
            tx_i = expected_tx_i;
            tx_q = expected_tx_q;

            transfer_sample(
                12'h100 + sample_index,
                12'hE00 + sample_index,
                inject_frame_error && (sample_index == 8)
            );
        end

        if (rx_sample_count !== 16 || tx_sample_count !== 16) begin
            $display("ERROR sample counters RX=%0d TX=%0d", rx_sample_count, tx_sample_count);
            errors = errors + 1;
        end
        if (checked_rx_samples != 16 || checked_tx_samples != 16) begin
            $display("ERROR checker counts RX=%0d TX=%0d", checked_rx_samples, checked_tx_samples);
            errors = errors + 1;
        end
        if (rx_diff_error_count !== 0) begin
            $display("ERROR unexpected differential errors=%0d", rx_diff_error_count);
            errors = errors + 1;
        end

        if (inject_frame_error) begin
            if (rx_frame_error_count !== 1) begin
                $display("ERROR expected exactly one frame error, got %0d", rx_frame_error_count);
                errors = errors + 1;
            end else begin
                $display("FAULT-INJECTION PASS: deliberate frame error detected");
            end
        end else if (rx_frame_error_count !== 0) begin
            $display("ERROR unexpected frame errors=%0d", rx_frame_error_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("SIM PASS: RX/TX DDR serialization, frame timing, differential complements,");
            $display("          I/Q reconstruction and UHD 32-bit packing all verified.");
        end else begin
            $fatal(1, "SIM FAIL: %0d checks failed", errors);
        end

        #10;
        $finish;
    end

endmodule
