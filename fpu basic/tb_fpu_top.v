`timescale 1ns / 1ps
// =============================================================================
// Module  : tb_fpu_top
// Purpose : Self-checking testbench for the 4-stage FP32 adder pipeline.
// Fixes   :
//   [F1] Inter-batch wait increased from #40 to #80 (8 clock cycles) to
//        ensure the 4-cycle deep pipeline fully drains before the next
//        stimulus batch is applied.  With a 10 ns clock: 4 stages + margin
//        = at least 5 cycles = 50 ns.  80 ns gives comfortable headroom.
//   [F2] Final flush wait increased from #100 to #120 so the last pair of
//        special-case vectors (Tests 10-11) fully propagate before $finish.
//   [F3] Added a display showing the pipeline latency so the log is clear.
// =============================================================================

module tb_fpu_top;

    // -------------------------------------------------------------------------
    // 1. Testbench Signals
    // -------------------------------------------------------------------------
    reg        clk;
    reg        rst_n;
    reg        valid_in;
    reg        fadd_nsub;
    reg [31:0] operand_a;
    reg [31:0] operand_b;

    wire        valid_out;
    wire [31:0] result_out;

    // Self-checking FIFO (depth 64 is plenty for 11 tests)
    reg [31:0] expected_fifo [0:63];
    integer fifo_wr   = 0;
    integer fifo_rd   = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    // -------------------------------------------------------------------------
    // 2. UUT Instantiation
    // -------------------------------------------------------------------------
    fpu_top uut (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (valid_in),
        .fadd_nsub (fadd_nsub),
        .operand_a (operand_a),
        .operand_b (operand_b),
        .valid_out (valid_out),
        .result_out(result_out)
    );

    // -------------------------------------------------------------------------
    // 3. Clock - 100 MHz (10 ns period)
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // 4. Task: Push One Test Vector
    // -------------------------------------------------------------------------
    task send_vector (
        input [31:0] a,
        input [31:0] b,
        input        op,        // 1=Add, 0=Sub
        input [31:0] expected
    );
        begin
            @(posedge clk);
            #1; // small hold after clock edge (setup margin)
            valid_in           = 1'b1;
            operand_a          = a;
            operand_b          = b;
            fadd_nsub          = op;
            expected_fifo[fifo_wr] = expected;
            fifo_wr = fifo_wr + 1;
        end
    endtask

    // Task: de-assert valid for one cycle (idle bubble)
    task clear_valid ();
        begin
            @(posedge clk);
            #1;
            valid_in = 1'b0;
        end
    endtask

    // -------------------------------------------------------------------------
    // 5. Self-Checking Monitor
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (valid_out) begin
            test_num = test_num + 1;
            if (result_out === expected_fifo[fifo_rd]) begin
                $display("[PASS] Test %02d | t=%0t ns | Result: 32'h%08h",
                          test_num, $time, result_out);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Test %02d | t=%0t ns | Got: 32'h%08h | Expected: 32'h%08h",
                          test_num, $time, result_out, expected_fifo[fifo_rd]);
                fail_count = fail_count + 1;
            end
            fifo_rd = fifo_rd + 1;
        end
    end

    // -------------------------------------------------------------------------
    // 6. Stimulus
    // -------------------------------------------------------------------------
    initial begin
        // Initialise
        clk       = 0;
        rst_n     = 0;
        valid_in  = 0;
        fadd_nsub = 0;
        operand_a = 0;
        operand_b = 0;

        // Reset for 3 cycles
        repeat(3) @(posedge clk);
        #1; rst_n = 1;
        repeat(2) @(posedge clk); // settle

        $display("===========================================================");
        $display("   IEEE 754 FP32 ADDER - PIPELINE TESTBENCH (4-stage)      ");
        $display("   Pipeline latency = 4 clock cycles (40 ns @ 100 MHz)     ");
        $display("===========================================================");

        // -------------------------------------------------------------------
        // SECTION 1 - Basic Operations (tests 1-5, one per cycle)
        // -------------------------------------------------------------------
        $display("\n--- Section 1: Basic Operations ---");

        // T1: 1.0 + 1.0 = 2.0
        send_vector(32'h3F80_0000, 32'h3F80_0000, 1'b1, 32'h4000_0000);

        // T2: 2.5 + 3.25 = 5.75
        send_vector(32'h4020_0000, 32'h4050_0000, 1'b1, 32'h40B8_0000);

        // T3: 10.0 - 3.5 = 6.5
        send_vector(32'h4120_0000, 32'h4060_0000, 1'b0, 32'h40D0_0000);

        // T4: 2.0 - 5.0 = -3.0
        send_vector(32'h4000_0000, 32'h40A0_0000, 1'b0, 32'hC040_0000);

        // T5: 5.0 - 5.0 = +0.0  (IEEE 754 RNE → +0, NOT -0)
        send_vector(32'h40A0_0000, 32'h40A0_0000, 1'b0, 32'h0000_0000);

        clear_valid();

        // [F1] Wait 8 cycles (80 ns) so the 4-stage pipeline fully drains
        // before the next batch arrives and the FIFO checker stays in sync.
        #80;

        // -------------------------------------------------------------------
        // SECTION 2 - Back-to-Back Full-Throughput (tests 6-9)
        // -------------------------------------------------------------------
        $display("\n--- Section 2: Back-to-Back Pipelining ---");

        // T6: 0.5 + 0.5 = 1.0
        send_vector(32'h3F00_0000, 32'h3F00_0000, 1'b1, 32'h3F80_0000);

        // T7: 4.0 - 1.0 = 3.0
        send_vector(32'h4080_0000, 32'h3F80_0000, 1'b0, 32'h4040_0000);

        // T8: 100.0 + 25.0 = 125.0
        send_vector(32'h42C8_0000, 32'h41C8_0000, 1'b1, 32'h42FA_0000);

        // T9: 1.5 + 1.5 = 3.0
        send_vector(32'h3FC0_0000, 32'h3FC0_0000, 1'b1, 32'h4040_0000);

        clear_valid();
        #80;

        // -------------------------------------------------------------------
        // SECTION 3 - Special Cases (tests 10-11)
        // -------------------------------------------------------------------
        $display("\n--- Section 3: Special Cases ---");

        // T10: +Inf + 1.0 = +Inf
        send_vector(32'h7F80_0000, 32'h3F80_0000, 1'b1, 32'h7F80_0000);

        // T11: QNaN + 1.0 = QNaN
        send_vector(32'h7FC0_0000, 32'h3F80_0000, 1'b1, 32'h7FC0_0000);

        clear_valid();

        // [F2] Wait long enough for last tests to complete (4 cycles + margin)
        #120;

        // -------------------------------------------------------------------
        // Summary
        // -------------------------------------------------------------------
        $display("\n===========================================================");
        $display("                    SIMULATION SUMMARY                      ");
        $display("===========================================================");
        $display(" Total tests : %0d", test_num);
        $display(" PASSED      : %0d", pass_count);
        $display(" FAILED      : %0d", fail_count);
        $display("===========================================================");
        if (fail_count == 0)
            $display(">>> ALL TESTS PASSED <<<");
        else
            $display(">>> %0d TEST(S) FAILED - see mismatches above <<<", fail_count);

        $finish;
    end

endmodule