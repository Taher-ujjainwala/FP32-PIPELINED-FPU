`timescale 1ns / 1ps

module fpu_pre_add (
    // Globals & Control
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire        fadd_nsub_in,

    // Operands
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,

    // Registered Pipeline Outputs to Stage 2
    output reg         valid_out,
    output reg         fadd_nsub_out,
    output reg         is_nan_out,
    output reg         is_inf_out,
    output reg         is_zero_out,
    output reg         sign_a_out,
    output reg         sign_b_out,
    output reg  [7:0]  exp_max_out,
    output reg  [26:0] mant_a_aligned_out,
    output reg  [26:0] mant_b_aligned_out
);

    // --------------------------------------------------------
    // 1. Unpack Fields
    // --------------------------------------------------------
    wire        sign_a   = operand_a[31];
    wire [7:0]  exp_a    = operand_a[30:23];
    wire [22:0] frac_a   = operand_a[22:0];

    wire        sign_b   = operand_b[31];
    wire [7:0]  exp_b    = operand_b[30:23];
    wire [22:0] frac_b   = operand_b[22:0];

    // --------------------------------------------------------
    // 2. Special Case Flag Detection
    // --------------------------------------------------------
    wire zero_a = (exp_a == 8'd0)  && (frac_a == 23'd0);
    wire zero_b = (exp_b == 8'd0)  && (frac_b == 23'd0);
    wire nan_a  = (exp_a == 8'hFF) && (frac_a != 23'd0);
    wire nan_b  = (exp_b == 8'hFF) && (frac_b != 23'd0);
    wire inf_a  = (exp_a == 8'hFF) && (frac_a == 23'd0);
    wire inf_b  = (exp_b == 8'hFF) && (frac_b == 23'd0);

    wire is_nan_comb  = nan_a | nan_b;
    wire is_inf_comb  = inf_a | inf_b;
    wire is_zero_comb = zero_a & zero_b;

    // --------------------------------------------------------
    // 3. Construct Base Mantissas (27-bit format: Hidden + Frac + GRS)
    // --------------------------------------------------------
    // Format: [26] Hidden bit, [25:3] Fraction, [2:0] GRS (initially zero)
    wire [26:0] mant_a_base = {(exp_a != 8'd0), frac_a, 3'b000};
    wire [26:0] mant_b_base = {(exp_b != 8'd0), frac_b, 3'b000};

    // --------------------------------------------------------
    // 4. Exponent Comparison & Alignment Logic
    // --------------------------------------------------------
    reg [7:0]  exp_max_comb;
    reg [26:0] mant_a_aligned_comb;
    reg [26:0] mant_b_aligned_comb;
    reg [7:0]  exp_diff;

    always @(*) begin
        if (exp_a >= exp_b) begin
            exp_max_comb        = exp_a;
            exp_diff            = exp_a - exp_b;
            mant_a_aligned_comb = mant_a_base;

            if (exp_diff >= 8'd27) begin
                // Shifted completely out: collapse mantissa into sticky bit
                mant_b_aligned_comb    = 27'd0;
                mant_b_aligned_comb[0] = (mant_b_base != 27'd0);
            end else begin
                mant_b_aligned_comb    = mant_b_base >> exp_diff;
                // Sticky Bit Preservation: OR shifted-out bits into bit [0]
                if (exp_diff > 0) begin
                    mant_b_aligned_comb[0] = mant_b_aligned_comb[0] | 
                                             (|(mant_b_base & ((27'd1 << exp_diff) - 27'd1)));
                end
            end
        end else begin
            exp_max_comb        = exp_b;
            exp_diff            = exp_b - exp_a;
            mant_b_aligned_comb = mant_b_base;

            if (exp_diff >= 8'd27) begin
                mant_a_aligned_comb    = 27'd0;
                mant_a_aligned_comb[0] = (mant_a_base != 27'd0);
            end else begin
                mant_a_aligned_comb    = mant_a_base >> exp_diff;
                if (exp_diff > 0) begin
                    mant_a_aligned_comb[0] = mant_a_aligned_comb[0] | 
                                             (|(mant_a_base & ((27'd1 << exp_diff) - 27'd1)));
                end
            end
        end
    end

    // --------------------------------------------------------
    // 5. Pipeline Register Stage
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out          <= 1'b0;
            fadd_nsub_out      <= 1'b0;
            is_nan_out         <= 1'b0;
            is_inf_out         <= 1'b0;
            is_zero_out        <= 1'b0;
            sign_a_out         <= 1'b0;
            sign_b_out         <= 1'b0;
            exp_max_out        <= 8'd0;
            mant_a_aligned_out <= 27'd0;
            mant_b_aligned_out <= 27'd0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                fadd_nsub_out      <= fadd_nsub_in;
                is_nan_out         <= is_nan_comb;
                is_inf_out         <= is_inf_comb;
                is_zero_out        <= is_zero_comb;
                sign_a_out         <= sign_a;
                sign_b_out         <= sign_b;
                exp_max_out        <= exp_max_comb;
                mant_a_aligned_out <= mant_a_aligned_comb;
                mant_b_aligned_out <= mant_b_aligned_comb;
            end
        end
    end

endmodule