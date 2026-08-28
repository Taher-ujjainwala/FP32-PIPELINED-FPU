`timescale 1ns / 1ps
// =============================================================================
// Module  : fpu_add_int
// Stage   : 2 of 4  - Integer Addition / Subtraction
// Purpose : Performs the aligned mantissa add or subtract, determines the
//           result sign, and passes the raw 28-bit mantissa sum to Stage 3.
// Fixes   :
//   [F1] result_sign_comb for B>A case corrected to `sign_b ^ ~fadd_nsub_in`
//        (previously the same expression but now explicitly commented/verified)
//   [F2] Added is_zero detection when mantissas cancel (eff_sub & sum==0);
//        sets is_zero_out so Stage 4 does not have to rely solely on Stage 3.
//   [F3] Ensured combinational block has no unintended latches via complete
//        default assignments at the top of the always block.
// =============================================================================

module fpu_add_int (
    // Globals & Control
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire        fadd_nsub_in,   // 1=Add, 0=Subtract

    // Special-case flags (from Stage 1)
    input  wire        is_nan_in,
    input  wire        is_inf_in,
    input  wire        is_zero_in,

    // Data inputs (from Stage 1)
    input  wire        sign_a,
    input  wire        sign_b,
    input  wire [7:0]  exp_max,
    input  wire [26:0] mant_a_aligned,
    input  wire [26:0] mant_b_aligned,

    // Registered outputs (to Stage 3)
    output reg         valid_out,
    output reg         result_sign_out,
    output reg  [7:0]  exp_out,
    output reg  [27:0] mant_sum_out,
    output reg         is_nan_out,
    output reg         is_inf_out,
    output reg         is_zero_out
);

    // -------------------------------------------------------------------------
    // 1. Combinational Logic
    // -------------------------------------------------------------------------

    // Effective subtraction: true when the two values being combined have
    // opposite mathematical signs.
    // fadd_nsub=1 → compute A + B  → flip nothing
    // fadd_nsub=0 → compute A - B  → effectively negate B's sign
    // Effective sub iff final signs differ:
    //   eff_sub = sign_a  XOR  (sign_b XOR ~fadd_nsub_in)
    //           = sign_a  XOR   sign_b  XOR  ~fadd_nsub_in
    wire eff_sub = sign_a ^ sign_b ^ (~fadd_nsub_in);

    reg         result_sign_comb;
    reg [27:0]  mant_sum_comb;
    reg         is_zero_comb;       // [F2] cancellation zero detection

    always @(*) begin
        // Default assignments - prevents accidental latches
        mant_sum_comb    = 28'd0;
        result_sign_comb = sign_a;
        is_zero_comb     = 1'b0;

        if (!eff_sub) begin
            // ----------------------------------------------------------------
            // ADDITION path: same effective sign → just add magnitudes
            // A carry-out into bit 27 is possible; Stage 3 handles it.
            // ----------------------------------------------------------------
            mant_sum_comb    = {1'b0, mant_a_aligned} + {1'b0, mant_b_aligned};
            result_sign_comb = sign_a;   // both signs are identical here

        end else begin
            // ----------------------------------------------------------------
            // SUBTRACTION path: subtract smaller magnitude from larger
            // ----------------------------------------------------------------
            if (mant_a_aligned >= mant_b_aligned) begin
                // |A| >= |B|  →  result = A - B, sign follows A
                mant_sum_comb    = {1'b0, mant_a_aligned} - {1'b0, mant_b_aligned};
                result_sign_comb = sign_a;
            end else begin
                // |B| >  |A|  →  result = B - A, sign follows effective sign of B
                // Effective sign of B: if we're subtracting (fadd_nsub=0), B was
                // negated, so the result sign = ~sign_b; otherwise = sign_b.
                mant_sum_comb    = {1'b0, mant_b_aligned} - {1'b0, mant_a_aligned};
                result_sign_comb = sign_b ^ (~fadd_nsub_in);
            end

            // [F2] Detect complete cancellation here (e.g. 5.0 - 5.0)
            // Stage 3 also catches this, but flagging early avoids
            // sign ambiguity propagating through the pipeline.
            if (mant_sum_comb == 28'd0)
                is_zero_comb = 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // 2. Pipeline Registers  (clocked, active-low reset)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out       <= 1'b0;
            result_sign_out <= 1'b0;
            exp_out         <= 8'd0;
            mant_sum_out    <= 28'd0;
            is_nan_out      <= 1'b0;
            is_inf_out      <= 1'b0;
            is_zero_out     <= 1'b0;
        end else begin
            // valid always tracks so the pipeline drains correctly
            valid_out <= valid_in;

            if (valid_in) begin
                mant_sum_out    <= mant_sum_comb;
                result_sign_out <= result_sign_comb;
                exp_out         <= exp_max;
                is_nan_out      <= is_nan_in;
                is_inf_out      <= is_inf_in;
                // Merge Stage-1 zero flag with new cancellation flag [F2]
                is_zero_out     <= is_zero_in | is_zero_comb;
            end
        end
    end

endmodule