// SPDX-License-Identifier: MIT
//
// Protocol-level AD9361 1R1T DDR LVDS interface demonstration.
//
// IMPORTANT: This module is intentionally simulator-portable. It models both
// clock edges in behavioral SystemVerilog so that the AD9361 wire protocol can
// be demonstrated with Icarus Verilog. It is not the production Artix-7 PHY.
// The production design must instantiate UHD cat_io_lvds_dual_mode, which uses
// Xilinx 7-series ISERDESE2/OSERDESE2/IDELAYE2 primitives.

`timescale 1ns/1ps

module nyquist_ad9361_lvds_1r1t_demo (
    input  logic        rst,

    // AD9361 -> FPGA receive interface
    input  logic        rx_clk_p,
    input  logic        rx_clk_n,
    input  logic        rx_frame_p,
    input  logic        rx_frame_n,
    input  logic [5:0]  rx_d_p,
    input  logic [5:0]  rx_d_n,

    // Reconstructed FPGA receive sample
    output logic        rx_sample_valid,
    output logic [11:0] rx_i,
    output logic [11:0] rx_q,
    output logic [31:0] rx_packed,

    // FPGA transmit sample
    input  logic        tx_sample_valid,
    input  logic [11:0] tx_i,
    input  logic [11:0] tx_q,

    // FPGA -> AD9361 transmit interface
    output logic        tx_clk_p,
    output logic        tx_clk_n,
    output logic        tx_frame_p,
    output logic        tx_frame_n,
    output logic [5:0]  tx_d_p,
    output logic [5:0]  tx_d_n,

    // Demonstration/status counters
    output logic [31:0] rx_sample_count,
    output logic [31:0] tx_sample_count,
    output logic [31:0] rx_frame_error_count,
    output logic [31:0] rx_diff_error_count
);

    logic [1:0] rx_phase;
    logic [1:0] tx_phase;
    logic [11:0] rx_i_work;
    logic [11:0] rx_q_work;
    logic [11:0] tx_i_latched;
    logic [11:0] tx_q_latched;
    logic expected_frame;

    assign rx_packed = {rx_i, 4'b0000, rx_q, 4'b0000};
    assign tx_clk_p  = rx_clk_p;
    assign tx_clk_n  = rx_clk_n;
    assign tx_frame_n = ~tx_frame_p;
    assign tx_d_n     = ~tx_d_p;

    // The AD9361 1R1T LVDS sequence is one six-bit transfer per clock edge:
    //   phase 0: I[11:6], FRAME=1
    //   phase 1: Q[11:6], FRAME=1
    //   phase 2: I[5:0],  FRAME=0
    //   phase 3: Q[5:0],  FRAME=0
    // This behavioral block observes both clock edges for portable simulation.
    always @(posedge rx_clk_p or negedge rx_clk_p or posedge rst) begin
        if (rst) begin
            rx_phase             = 2'd0;
            rx_i_work            = 12'd0;
            rx_q_work            = 12'd0;
            rx_i                 = 12'd0;
            rx_q                 = 12'd0;
            rx_sample_valid      = 1'b0;
            rx_sample_count      = 32'd0;
            rx_frame_error_count = 32'd0;
            rx_diff_error_count  = 32'd0;
        end else begin
            rx_sample_valid = 1'b0;
            expected_frame = (rx_phase < 2);

            if ((rx_clk_n !== ~rx_clk_p) ||
                (rx_frame_n !== ~rx_frame_p) ||
                (rx_d_n !== ~rx_d_p)) begin
                rx_diff_error_count = rx_diff_error_count + 1'b1;
            end

            if (rx_frame_p !== expected_frame) begin
                rx_frame_error_count = rx_frame_error_count + 1'b1;
            end

            case (rx_phase)
                2'd0: rx_i_work[11:6] = rx_d_p;
                2'd1: rx_q_work[11:6] = rx_d_p;
                2'd2: rx_i_work[5:0]  = rx_d_p;
                2'd3: begin
                    rx_q_work[5:0] = rx_d_p;
                    rx_i = rx_i_work;
                    rx_q = rx_q_work;
                    rx_sample_valid = 1'b1;
                    rx_sample_count = rx_sample_count + 1'b1;
                end
            endcase

            rx_phase = rx_phase + 1'b1;
        end
    end

    // Behavioral DDR transmitter. In hardware this function is implemented
    // with OSERDESE2/OBUFDS and source-synchronous forwarded-clock resources.
    always @(posedge rx_clk_p or negedge rx_clk_p or posedge rst) begin
        if (rst) begin
            tx_phase        = 2'd0;
            tx_i_latched    = 12'd0;
            tx_q_latched    = 12'd0;
            tx_frame_p      = 1'b0;
            tx_d_p          = 6'd0;
            tx_sample_count = 32'd0;
        end else begin
            if ((tx_phase == 2'd0) && tx_sample_valid) begin
                tx_i_latched = tx_i;
                tx_q_latched = tx_q;
            end

            case (tx_phase)
                2'd0: begin
                    tx_frame_p = 1'b1;
                    tx_d_p = tx_sample_valid ? tx_i[11:6] : 6'd0;
                end
                2'd1: begin
                    tx_frame_p = 1'b1;
                    tx_d_p = tx_q_latched[11:6];
                end
                2'd2: begin
                    tx_frame_p = 1'b0;
                    tx_d_p = tx_i_latched[5:0];
                end
                2'd3: begin
                    tx_frame_p = 1'b0;
                    tx_d_p = tx_q_latched[5:0];
                    if (tx_sample_valid)
                        tx_sample_count = tx_sample_count + 1'b1;
                end
            endcase

            tx_phase = tx_phase + 1'b1;
        end
    end

endmodule
