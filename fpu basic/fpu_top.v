`timescale 1ns / 1ps

module fpu_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire        fadd_nsub,  // 1 = Addition, 0 = Subtraction
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,

    output wire        valid_out,
    output wire [31:0] result_out
);

    // --------------------------------------------------------
    // Inter-stage Pipeline Wires
    // --------------------------------------------------------
    
    // Stage 1 -> Stage 2 Wires
    wire        s1_valid;
    wire        s1_fadd_nsub;
    wire        s1_is_nan;
    wire        s1_is_inf;
    wire        s1_is_zero;
    wire        s1_sign_a;
    wire        s1_sign_b;
    wire [7:0]  s1_exp_max;
    wire [26:0] s1_mant_a_aligned;
    wire [26:0] s1_mant_b_aligned;

    // Stage 2 -> Stage 3 Wires
    wire        s2_valid;
    wire        s2_sign;
    wire [7:0]  s2_exp;
    wire [27:0] s2_mant_sum;
    wire        s2_is_nan;
    wire        s2_is_inf;
    wire        s2_is_zero;

    // Stage 3 -> Stage 4 Wires
    wire        s3_valid;
    wire        s3_sign;
    wire [7:0]  s3_exp_norm;
    wire [26:0] s3_mant_norm;
    wire        s3_is_nan;
    wire        s3_is_inf;
    wire        s3_is_zero;

    // --------------------------------------------------------
    // Module Instantiations
    // --------------------------------------------------------

    // Stage 1: Pre-Addition & Alignment
    fpu_pre_add u_stage1 (
        .clk               (clk),
        .rst_n             (rst_n),
        .valid_in          (valid_in),
        .fadd_nsub_in      (fadd_nsub),
        .operand_a         (operand_a),
        .operand_b         (operand_b),
        .valid_out         (s1_valid),
        .fadd_nsub_out     (s1_fadd_nsub),
        .is_nan_out        (s1_is_nan),
        .is_inf_out        (s1_is_inf),
        .is_zero_out       (s1_is_zero),
        .sign_a_out        (s1_sign_a),
        .sign_b_out        (s1_sign_b),
        .exp_max_out       (s1_exp_max),
        .mant_a_aligned_out(s1_mant_a_aligned),
        .mant_b_aligned_out(s1_mant_b_aligned)
    );

    // Stage 2: Integer Addition/Subtraction
    fpu_add_int u_stage2 (
        .clk             (clk),
        .rst_n           (rst_n),
        .valid_in        (s1_valid),
        .fadd_nsub_in    (s1_fadd_nsub),
        .is_nan_in       (s1_is_nan),
        .is_inf_in       (s1_is_inf),
        .is_zero_in      (s1_is_zero),
        .sign_a          (s1_sign_a),
        .sign_b          (s1_sign_b),
        .exp_max         (s1_exp_max),
        .mant_a_aligned  (s1_mant_a_aligned),
        .mant_b_aligned  (s1_mant_b_aligned),
        .valid_out       (s2_valid),
        .result_sign_out (s2_sign),
        .exp_out         (s2_exp),
        .mant_sum_out    (s2_mant_sum),
        .is_nan_out      (s2_is_nan),
        .is_inf_out      (s2_is_inf),
        .is_zero_out     (s2_is_zero)
    );

    // Stage 3: Normalization & LZC
    fpu_normalize u_stage3 (
        .clk             (clk),
        .rst_n           (rst_n),
        .valid_in        (s2_valid),
        .result_sign_in  (s2_sign),
        .exp_in          (s2_exp),
        .mant_sum_in     (s2_mant_sum),
        .is_nan_in       (s2_is_nan),
        .is_inf_in       (s2_is_inf),
        .is_zero_in      (s2_is_zero),
        .valid_out       (s3_valid),
        .result_sign_out (s3_sign),
        .exp_norm_out    (s3_exp_norm),
        .mant_norm_out   (s3_mant_norm),
        .is_nan_out      (s3_is_nan),
        .is_inf_out      (s3_is_inf),
        .is_zero_out     (s3_is_zero)
    );

    // Stage 4: Rounding & Packing
    fpu_round u_stage4 (
        .clk            (clk),
        .rst_n          (rst_n),
        .valid_in       (s3_valid),
        .result_sign_in (s3_sign),
        .exp_norm_in    (s3_exp_norm),
        .mant_norm_in   (s3_mant_norm),
        .is_nan_in      (s3_is_nan),
        .is_inf_in      (s3_is_inf),
        .is_zero_in     (s3_is_zero),
        .valid_out      (valid_out),
        .result_out     (result_out)
    );

endmodule