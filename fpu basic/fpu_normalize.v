`timescale 1ns / 1ps
// =============================================================================
// Module  : fpu_normalize
// Stage   : 3 of 4  - Normalization & Leading-Zero Count (LZC)
// Purpose : Adjusts the mantissa so the hidden bit is in position 26,
//           updates the exponent to match, and forwards a 27-bit normalized
//           mantissa (bit 26 = hidden 1, bits 2:0 = G/R/S) to Stage 4.
// Fixes   :
//   [F1] Exponent underflow guard: if shift_amount >= exp_in the result is
//        forced to zero (flush-to-zero for subnormals) instead of wrapping.
//   [F2] LZC integer index cast: `i` is a signed integer; explicitly cast
//        to 5-bit unsigned before the subtraction to avoid tool warnings.
//   [F3] is_zero_comb is OR'd into is_zero_out inside the sequential block
//        (was already done) - confirmed correct; no change needed.
// =============================================================================

module fpu_normalize (
    // Globals & Control
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,

    // Inputs from Stage 2
    input  wire        result_sign_in,
    input  wire [7:0]  exp_in,
    input  wire [27:0] mant_sum_in,    // 28-bit (bit 27 = carry-out)
    input  wire        is_nan_in,
    input  wire        is_inf_in,
    input  wire        is_zero_in,

    // Registered outputs to Stage 4
    output reg         valid_out,
    output reg         result_sign_out,
    output reg  [7:0]  exp_norm_out,
    output reg  [26:0] mant_norm_out,  // bit 26 = hidden 1 (normalized)
    output reg         is_nan_out,
    output reg         is_inf_out,
    output reg         is_zero_out
);

    // -------------------------------------------------------------------------
    // 1. Combinational Wires & Registers
    // -------------------------------------------------------------------------
    reg [26:0] mant_norm_comb;
    reg [7:0]  exp_norm_comb;
    reg        is_zero_comb;

    reg [4:0]  shift_amount;
    reg        found_one;
    reg [4:0]  i;             // 5-bit unsigned - avoids signed-integer warnings

    // -------------------------------------------------------------------------
    // 2. Combinational Normalization
    // -------------------------------------------------------------------------
    always @(*) begin
        // ── Default assignments (prevents synthesis latches) ─────────────────
        mant_norm_comb = 27'd0;
        exp_norm_comb  = exp_in;
        is_zero_comb   = 1'b0;
        shift_amount   = 5'd0;
        found_one      = 1'b0;

        // ── CASE 1 : Result is zero ───────────────────────────────────────────
        if (mant_sum_in == 28'd0) begin
            is_zero_comb   = 1'b1;
            exp_norm_comb  = 8'd0;
            mant_norm_comb = 27'd0;

        // ── CASE 2 : Carry-out overflow (bit 27 set) ─────────────────────────
        // Right-shift by 1, OR the evicted LSB into the sticky bit.
        end else if (mant_sum_in[27] == 1'b1) begin
            mant_norm_comb    = mant_sum_in[27:1];
            mant_norm_comb[0] = mant_sum_in[1] | mant_sum_in[0]; // sticky
            exp_norm_comb     = exp_in + 8'd1;

        // ── CASE 3 : Cancellation / leading zeros (bit 26 = 0) ───────────────
        // Find the leading 1 and left-shift it into position 26.
        end else if (mant_sum_in[26] == 1'b0) begin
            // LZC: scan bits 26..0 from MSB downward.
            // Loop uses i != 5'd31 as the wrap-around sentinel because
            // a 5-bit unsigned i=0 decremented gives 31, not -1.
            for (i = 5'd26; i != 5'd31; i = i - 5'd1) begin
                if (mant_sum_in[i] == 1'b1 && !found_one) begin
                    shift_amount = 5'd26 - i;   // both 5-bit unsigned: no issues
                    found_one    = 1'b1;
                end
            end

            // [F1] Exponent underflow guard
            // If shifting would push exp below zero, flush to zero.
            if ({3'b0, shift_amount} >= exp_in) begin
                // Flush-to-zero (conservative; full subnormal support is
                // a planned upgrade - see project roadmap).
                is_zero_comb   = 1'b1;
                exp_norm_comb  = 8'd0;
                mant_norm_comb = 27'd0;
            end else begin
                mant_norm_comb = mant_sum_in[26:0] << shift_amount;
                exp_norm_comb  = exp_in - {3'b0, shift_amount};
            end

        // ── CASE 4 : Already normalized (bit 26 = 1, no carry) ───────────────
        end else begin
            mant_norm_comb = mant_sum_in[26:0];
            exp_norm_comb  = exp_in;
        end
    end

    // -------------------------------------------------------------------------
    // 3. Pipeline Registers
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out       <= 1'b0;
            result_sign_out <= 1'b0;
            exp_norm_out    <= 8'd0;
            mant_norm_out   <= 27'd0;
            is_nan_out      <= 1'b0;
            is_inf_out      <= 1'b0;
            is_zero_out     <= 1'b0;
        end else begin
            valid_out <= valid_in;

            if (valid_in) begin
                mant_norm_out   <= mant_norm_comb;
                exp_norm_out    <= exp_norm_comb;
                result_sign_out <= result_sign_in;
                is_nan_out      <= is_nan_in;
                is_inf_out      <= is_inf_in;
                // Merge upstream zero flag with cancellation zero flag
                is_zero_out     <= is_zero_in | is_zero_comb;
            end
        end
    end

endmodule