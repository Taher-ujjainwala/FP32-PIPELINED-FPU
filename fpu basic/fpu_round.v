`timescale 1ns / 1ps

module fpu_round (
    // Globals & Control
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,

    // Inputs from Stage 3
    input  wire        result_sign_in,
    input  wire [7:0]  exp_norm_in,
    input  wire [26:0] mant_norm_in,
    input  wire        is_nan_in,
    input  wire        is_inf_in,
    input  wire        is_zero_in,

    // Final Output
    output reg         valid_out,
    output reg  [31:0] result_out
);

    // --------------------------------------------------------
    // 1. Combinational Rounding Wires
    // --------------------------------------------------------
    wire lsb, guard, round_bit, sticky;
    wire round_up;
    
    reg [24:0] mant_rounded; // 25 bits to catch post-rounding carry
    reg [7:0]  exp_final;
    reg [22:0] frac_final;
    reg [31:0] result_comb;

    // Bit extractions
    assign lsb       = mant_norm_in[3];
    assign guard     = mant_norm_in[2];
    assign round_bit = mant_norm_in[1];
    assign sticky    = mant_norm_in[0];

    // TODO 1: Assign round_up using the RNE equation
     assign round_up = (guard &(lsb | round_bit | sticky) ) ;
      
    // --------------------------------------------------------
    // 2. Combinational Processing Block
    // --------------------------------------------------------
    always @(*) begin
        // Perform rounding addition
        if (round_up)
            mant_rounded = {1'b0, mant_norm_in[26:3]} + 1'b1;
        else
            mant_rounded = {1'b0, mant_norm_in[26:3]};

        // TODO 2: Check for post-rounding overflow (mant_rounded[24] == 1)
        // If overflowed: shift right by 1, increment exp_norm_in, extract fraction mant_rounded[23:1]
        // Else: keep exp_norm_in, extract fraction mant_rounded[22:0]
          if(mant_rounded[24]==1)
          begin
          exp_final  = exp_norm_in + 8'd1;
            frac_final = mant_rounded[23:1];
          end
          else
           begin 
          exp_final  = exp_norm_in;
            frac_final = mant_rounded[22:0];
          end
        // TODO 3: Construct result_comb with special cases handling
        // Handle NaN, Infinity, Overflow (exp >= 255), Zero, and Normal Packing
    
    if (is_nan_in) begin
            // Canonical Quiet NaN
            result_comb = 32'h7FC00000;
        end 
        else if (is_inf_in || exp_final >= 8'd255) begin
            // Infinity / Overflow to Infinity
            result_comb = {result_sign_in, 8'hFF, 23'b0};
        end 
        else if (is_zero_in) begin
            // Signed Zero
            result_comb = {result_sign_in, 31'b0};
        end 
        else begin
            // Standard IEEE 754 Single-Precision Format
            result_comb = {result_sign_in, exp_final, frac_final};
        end
    end

    // --------------------------------------------------------
    // 3. Sequential Output Register
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out  <= 1'b0;
            result_out <= 32'b0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                result_out <= result_comb;
            end
        end
    end

endmodule