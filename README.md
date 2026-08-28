# FP32 Pipelined Adder/Subtractor — IEEE 754 Compliant

A fully pipelined, 4-stage floating-point addition/subtraction unit written in Verilog, compliant with the **IEEE 754-2008 single-precision (FP32)** standard.

Designed as a self-contained RTL core with a self-checking testbench. Handles all special cases including NaN, Infinity, signed zero, and complete cancellation.

---

## Pipeline Architecture

```
         Stage 1              Stage 2            Stage 3           Stage 4
    ┌─────────────────┐  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐
    │   fpu_pre_add   │  │ fpu_add_int │  │fpu_normalize │  │  fpu_round  │
    │                 │  │             │  │              │  │             │
    │ • Unpack fields │→ │ • Effective │→ │ • Detect     │→ │ • RNE       │
    │ • Detect NaN /  │  │   add/sub   │  │   carry-out  │  │   rounding  │
    │   Inf / Zero    │  │ • Determine │  │ • LZC + left │  │ • Post-round│
    │ • Compare exps  │  │   result    │  │   shift      │  │   overflow  │
    │ • Align         │  │   sign      │  │ • Exp adjust │  │ • IEEE pack │
    │   mantissas     │  │             │  │              │  │             │
    └─────────────────┘  └─────────────┘  └──────────────┘  └─────────────┘
          Reg                  Reg               Reg               Output
    (1 cycle latency per stage — 4 cycle total pipeline latency @ 100 MHz)
```

---

## Features

| Feature                          | Status |
|----------------------------------|--------|
| IEEE 754-2008 FP32 compliant     | ✅     |
| 4-stage fully pipelined          | ✅     |
| Full throughput (1 result/cycle) | ✅     |
| Round-to-Nearest-Even (RNE)      | ✅     |
| Guard / Round / Sticky bits      | ✅     |
| NaN propagation (Quiet NaN)      | ✅     |
| Infinity handling                | ✅     |
| Signed zero (+0 for RNE)         | ✅     |
| Complete cancellation detection  | ✅     |
| Exponent underflow guard         | ✅     |
| Post-rounding overflow detection | ✅     |
| Self-checking testbench          | ✅     |

---

## File Structure

```
fp32-pipelined-fpu/
│
├── fpu_top.v          # Top-level module — wires all 4 stages together
├── fpu_pre_add.v      # Stage 1 — Unpack, special case detect, alignment
├── fpu_add_int.v      # Stage 2 — Integer mantissa add / subtract
├── fpu_normalize.v    # Stage 3 — Normalization & Leading Zero Count (LZC)
├── fpu_round.v        # Stage 4 — RNE rounding & IEEE 754 packing
├── tb_fpu_top.v       # Self-checking testbench (11 directed test vectors)
└── README.md
```

---

## Mantissa Format (Internal)

The pipeline uses a **27-bit internal mantissa** format:

```
 Bit 26      Bits 25:3       Bit 2    Bit 1    Bit 0
┌────────┬──────────────────┬───────┬─────────┬────────┐
│Hidden 1│  23-bit Fraction │ Guard │  Round  │ Sticky │
└────────┴──────────────────┴───────┴─────────┴────────┘
```

- **Hidden bit** — the implicit leading 1 of a normalized IEEE 754 number  
- **Guard / Round / Sticky** — extra precision bits used for correct RNE rounding

---

## How to Simulate

### Using Icarus Verilog (free, open-source)

**Install:**
```bash
# Ubuntu / Debian
sudo apt install iverilog

# macOS
brew install icarus-verilog
```

**Compile & Run:**
```bash
iverilog -o fpu_sim \
    fpu_top.v fpu_pre_add.v fpu_add_int.v fpu_normalize.v fpu_round.v \
    tb_fpu_top.v

vvp fpu_sim
```

**Expected Output:**
```
===========================================================
   IEEE 754 FP32 ADDER — PIPELINE TESTBENCH (4-stage)
   Pipeline latency = 4 clock cycles (40 ns @ 100 MHz)
===========================================================

--- Section 1: Basic Operations ---
[PASS] Test 01 | Result: 32'h40000000   (1.0 + 1.0 = 2.0)
[PASS] Test 02 | Result: 32'h40b80000   (2.5 + 3.25 = 5.75)
[PASS] Test 03 | Result: 32'h40d00000   (10.0 - 3.5 = 6.5)
[PASS] Test 04 | Result: 32'hc0400000   (2.0 - 5.0 = -3.0)
[PASS] Test 05 | Result: 32'h00000000   (5.0 - 5.0 = +0.0)
...
>>> ALL TESTS PASSED <<<
```

### Using ModelSim / Questa
```bash
vlog fpu_top.v fpu_pre_add.v fpu_add_int.v fpu_normalize.v fpu_round.v tb_fpu_top.v
vsim tb_fpu_top
run -all
```

---

## Test Vectors

| # | Operation        | A (hex)      | B (hex)      | Expected (hex) | Notes                    |
|---|-----------------|--------------|--------------|----------------|--------------------------|
| 1 | 1.0 + 1.0       | `3F800000`   | `3F800000`   | `40000000`     | Basic add                |
| 2 | 2.5 + 3.25      | `40200000`   | `40500000`   | `40B80000`     | Unequal exponents        |
| 3 | 10.0 − 3.5      | `41200000`   | `40600000`   | `40D00000`     | Basic subtract           |
| 4 | 2.0 − 5.0       | `40000000`   | `40A00000`   | `C0400000`     | Negative result          |
| 5 | 5.0 − 5.0       | `40A00000`   | `40A00000`   | `00000000`     | Complete cancellation    |
| 6 | 0.5 + 0.5       | `3F000000`   | `3F000000`   | `3F800000`     | Back-to-back pipelining  |
| 7 | 4.0 − 1.0       | `40800000`   | `3F800000`   | `40400000`     | Back-to-back pipelining  |
| 8 | 100.0 + 25.0    | `42C80000`   | `41C80000`   | `42FA0000`     | Large values             |
| 9 | 1.5 + 1.5       | `3FC00000`   | `3FC00000`   | `40400000`     | Back-to-back pipelining  |
|10 | +Inf + 1.0      | `7F800000`   | `3F800000`   | `7F800000`     | Infinity passthrough     |
|11 | QNaN + 1.0      | `7FC00000`   | `3F800000`   | `7FC00000`     | NaN propagation          |

---

## Key Design Decisions & Bug Fixes

### 1. Signed Zero (IEEE 754-2008 §6.3)
Complete cancellation (e.g. `5.0 − 5.0`) must produce `+0` in Round-to-Nearest-Even mode, not `−0`. The sign bit is explicitly forced to `0` in Stage 4 when `is_zero` is asserted.

### 2. Exponent Underflow Guard (Stage 3)
After large cancellations, the Leading Zero Count can exceed the current exponent value. Without a guard, the exponent wraps around silently (e.g. `3 − 5 = 254` in 8-bit unsigned). The normalizer flushes the result to zero when `shift_amount >= exp_in`.

### 3. LZC Loop — Unsigned Wrap-Around
The loop variable for Leading Zero Counting uses a `reg [4:0]` (unsigned) instead of `integer`. A 5-bit unsigned counter decremented past `0` wraps to `31`, so the termination condition is `i != 5'd31` rather than `i >= 0`.

### 4. Sticky Bit Preservation (Stage 1)
When the exponent difference is large and the smaller mantissa is shifted right, the bits shifted out are OR'd into the sticky bit. This ensures correct rounding even when precision is lost during alignment.

### 5. Cancellation Detection in Stage 2
`is_zero` is flagged in Stage 2 (not just Stage 3) when effective subtraction produces a zero mantissa sum. This prevents an ambiguous sign bit from propagating into the normalizer.

---

## Planned Improvements

- [ ] All 4 IEEE 754 rounding modes: RTZ, RUP, RDN, RNE (currently only RNE)
- [ ] Exception flags: `inexact`, `underflow`, `overflow`, `invalid`, `divide_by_zero`
- [ ] Subnormal (denormal) number support — gradual underflow
- [ ] Formal verification using SystemVerilog Assertions (SVA)
- [ ] FPGA synthesis report (Xilinx Artix-7 — Fmax, LUT/FF count)
- [ ] Parameterized design (`EXP_BITS`, `MANT_BITS`) for FP64 support
- [ ] Fused Multiply-Add (FMA) unit extension

---

## References

- IEEE 754-2008 Standard for Floating-Point Arithmetic
- Oberman, S.F. & Flynn, M.J. — *Design Issues in Division and Other Floating-Point Operations* (1997)
- Patterson & Hennessy — *Computer Organization and Design* (Appendix B)

---

## Author

**Taher Ujjainwala**  
B.Tech / M.Tech — Electronics & Communication / VLSI  

[LinkedIn](https://www.linkedin.com/in/taher-ujjainwala-a24a07349?utm_source=share_via&utm_content=profile&utm_medium=member_android)· [GitHub](https://github.com/Taher-ujjainwala)
