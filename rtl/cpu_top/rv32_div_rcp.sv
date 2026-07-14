// Exact RV32 DIV/DIVU/REM/REMU using a normalized reciprocal seed and one
// Goldschmidt correction.  The ROM and all arithmetic are shared by signed
// and unsigned operations; signedness is handled at the input/output edges.
module rv32_div_rcp #(
    parameter integer F = 40,
    parameter integer ROM_ADDR_WIDTH = 16,
    parameter string ROM_FILE = "rtl/cpu_top/rv32_recip_lut_f40.mem"
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        cancel,
    input  logic        req_valid,
    input  logic [31:0] dividend,
    input  logic [31:0] divisor,
    input  logic        signed_div,
    input  logic        want_remainder,
    output logic        req_ready,
    output logic        busy,
    output logic        done,
    output logic [31:0] quotient,
    output logic [31:0] remainder,
    output logic [31:0] result
);

    localparam integer P_WIDTH = 32 + F;
    localparam integer E_WIDTH = F + 1;
    localparam integer C_WIDTH = P_WIDTH + E_WIDTH;
    localparam integer DELTA_WIDTH = F - ROM_ADDR_WIDTH;
    localparam integer DELTA_MAG_WIDTH = DELTA_WIDTH - 1;
    localparam integer DELTA_MAG_PRODUCT_WIDTH = P_WIDTH + DELTA_MAG_WIDTH;
    localparam integer B_LO_WIDTH = P_WIDTH / 2;
    localparam integer B_HI_WIDTH = P_WIDTH - B_LO_WIDTH;
    localparam integer DELTA_PART_PRODUCT_WIDTH = B_HI_WIDTH + DELTA_MAG_WIDTH;

    initial begin
        if (!(((F == 40) && (ROM_ADDR_WIDTH == 16)) ||
              ((F == 52) && (ROM_ADDR_WIDTH == 15))))
            $fatal(1, "Unsupported reciprocal divider configuration F=%0d ROM_ADDR_WIDTH=%0d",
                   F, ROM_ADDR_WIDTH);
    end

    typedef enum logic [4:0] {
        ST_IDLE    = 5'd0,
        ST_SETUP   = 5'd1,
        ST_NORMALIZE = 5'd2,
        ST_LOOKUP  = 5'd3,
        ST_SEED    = 5'd4,
        ST_PRODUCT = 5'd5,
        ST_REFINE  = 5'd6,
        ST_COMBINE = 5'd7,
        ST_DELTA_SUM = 5'd8,
        ST_ACCUMULATE = 5'd9,
        ST_QUOT    = 5'd10,
        ST_QPROD   = 5'd11,
        ST_REMAINDER = 5'd12,
        ST_CORRECT = 5'd13,
        ST_SIGN    = 5'd14,
        ST_SPECIAL = 5'd15
    } state_t;

    state_t state;

    logic [31:0] raw_dividend_reg;
    logic [31:0] raw_divisor_reg;
    logic        raw_signed_div_reg;
    logic        raw_want_remainder_reg;
    logic [31:0] n_reg;
    logic [31:0] d_reg;
    logic [31:0] x_reg;
    logic [5:0]  shift_reg;
    logic [ROM_ADDR_WIDTH-1:0] rom_addr_reg;
    logic [F-1:0] seed_reg;
    logic [P_WIDTH-1:0] p_xr_reg;
    logic [P_WIDTH-1:0] b_nr_reg;
    // Separate the first product from the narrow delta multipliers.  The
    // extra register uses the existing REFINE cycle and keeps the DSP input
    // path from spanning the product and partial-product stages.
    (* KEEP = "TRUE" *) logic [P_WIDTH-1:0] b_nr_pipe_reg;
    logic [E_WIDTH-1:0] e_reg;
    logic [C_WIDTH-1:0] c_reg;
    logic [31:0] q_est_reg;
    logic [63:0] q_product_reg;
    logic [63:0] rem_pre_reg;
    logic [31:0] q_magnitude_reg;
    logic [31:0] r_magnitude_reg;
    logic        quotient_negative_reg;
    logic        remainder_negative_reg;
    logic        want_remainder_reg;
    logic [31:0] special_quotient_reg;
    logic [31:0] special_remainder_reg;

    logic [F-1:0] r0_rom_data;

    logic [31:0] dividend_abs;
    logic [31:0] divisor_abs;
    logic [5:0]  normalized_lz_comb;
    logic [31:0] normalized_divisor_comb;
    logic [ROM_ADDR_WIDTH-1:0] normalized_rom_addr_comb;

    logic [P_WIDTH-1:0] product_xr_comb;
    logic [P_WIDTH-1:0] product_nr_comb;
    logic [F:0]         product_floor_comb;
    logic               product_sticky_comb;
    logic [F+1:0]       product_ceil_ext_comb;
    logic [F+1:0]       correction_factor_ext_comb;
    logic [E_WIDTH-1:0] correction_factor_comb;
    logic signed [DELTA_WIDTH-1:0] correction_delta_comb;
    logic               delta_negative_comb;
    logic               delta_negative_reg;
    logic [DELTA_MAG_WIDTH-1:0] delta_magnitude_comb;
    logic [DELTA_MAG_WIDTH-1:0] delta_magnitude_reg;
    logic [DELTA_PART_PRODUCT_WIDTH-1:0] delta_product_lo_comb;
    logic [DELTA_PART_PRODUCT_WIDTH-1:0] delta_product_hi_comb;
    logic [DELTA_PART_PRODUCT_WIDTH-1:0] delta_product_lo_reg;
    logic [DELTA_PART_PRODUCT_WIDTH-1:0] delta_product_hi_reg;
    logic [DELTA_MAG_PRODUCT_WIDTH-1:0] delta_product_lo_ext_comb;
    logic [DELTA_MAG_PRODUCT_WIDTH-1:0] delta_product_hi_ext_comb;
    logic [DELTA_MAG_PRODUCT_WIDTH-1:0] delta_product_mag_sum_comb;
    logic [DELTA_MAG_PRODUCT_WIDTH-1:0] delta_product_mag_reg;
    logic [C_WIDTH-1:0] base_product_ext_comb;
    logic [C_WIDTH-1:0] delta_product_mag_ext_comb;
    logic [C_WIDTH-1:0] product_be_comb;
    logic [31:0]        quotient_est_comb;
    logic [63:0]        quotient_product_comb;
    logic [31:0]        signed_quotient_comb;
    logic [31:0]        signed_remainder_comb;

    function automatic [5:0] leading_zero_count(input logic [31:0] value);
        integer i;
        begin
            leading_zero_count = 6'd32;
            for (i = 31; i >= 0; i = i - 1) begin
                if (value[i] && (leading_zero_count == 6'd32))
                    leading_zero_count = 31 - i;
            end
        end
    endfunction

    always_comb begin
        dividend_abs = (raw_signed_div_reg && raw_dividend_reg[31]) ?
                       (~raw_dividend_reg + 32'd1) : raw_dividend_reg;
        divisor_abs  = (raw_signed_div_reg && raw_divisor_reg[31]) ?
                       (~raw_divisor_reg + 32'd1) : raw_divisor_reg;
        // The normalization network starts from the registered absolute
        // divisor.  Keeping it out of ST_SETUP breaks the raw input -> barrel
        // shifter path that limited the 160 MHz OOC result.
        normalized_lz_comb = leading_zero_count(d_reg);
        normalized_divisor_comb = d_reg << normalized_lz_comb;
        normalized_rom_addr_comb = normalized_divisor_comb[30 -: ROM_ADDR_WIDTH];

        product_xr_comb = x_reg * seed_reg;
        product_nr_comb = n_reg * seed_reg;
        product_floor_comb = p_xr_reg[P_WIDTH-1:31];
        product_sticky_comb = |p_xr_reg[30:0];
        product_ceil_ext_comb = {1'b0, product_floor_comb} +
                                {{(F+1){1'b0}}, product_sticky_comb};
        correction_factor_ext_comb = {1'b1, {(F+1){1'b0}}} - product_ceil_ext_comb;
        correction_factor_comb = correction_factor_ext_comb[F:0];

        // E is tightly bounded around 2^F for the two proven table
        // configurations.  Its low DELTA_WIDTH bits are the exact signed
        // delta in E = 2^F + delta, which narrows the second multiplier.
        correction_delta_comb = $signed(correction_factor_comb[DELTA_WIDTH-1:0]);
        delta_negative_comb = correction_delta_comb[DELTA_WIDTH-1];
        delta_magnitude_comb = delta_negative_comb ?
                               (~correction_delta_comb[DELTA_MAG_WIDTH-1:0] + 1'b1) :
                               correction_delta_comb[DELTA_MAG_WIDTH-1:0];
        delta_product_lo_comb = b_nr_pipe_reg[B_LO_WIDTH-1:0] * delta_magnitude_reg;
        delta_product_hi_comb = b_nr_pipe_reg[P_WIDTH-1:B_LO_WIDTH] * delta_magnitude_reg;
        delta_product_lo_ext_comb =
            {{(DELTA_MAG_PRODUCT_WIDTH-DELTA_PART_PRODUCT_WIDTH){1'b0}},
             delta_product_lo_reg};
        delta_product_hi_ext_comb =
            {{(DELTA_MAG_PRODUCT_WIDTH-DELTA_PART_PRODUCT_WIDTH){1'b0}},
             delta_product_hi_reg} << B_LO_WIDTH;
        delta_product_mag_sum_comb = delta_product_hi_ext_comb +
                                     delta_product_lo_ext_comb;
        base_product_ext_comb = {1'b0, b_nr_reg, {F{1'b0}}};
        delta_product_mag_ext_comb =
            {{(C_WIDTH-DELTA_MAG_PRODUCT_WIDTH){1'b0}}, delta_product_mag_reg};
        product_be_comb = delta_negative_reg ?
                          (base_product_ext_comb - delta_product_mag_ext_comb) :
                          (base_product_ext_comb + delta_product_mag_ext_comb);

        quotient_est_comb = c_reg >> ((2 * F + 31) - shift_reg);
        quotient_product_comb = q_est_reg * d_reg;
        signed_quotient_comb = quotient_negative_reg ?
                               (~q_magnitude_reg + 32'd1) : q_magnitude_reg;
        signed_remainder_comb = remainder_negative_reg ?
                                (~r_magnitude_reg + 32'd1) : r_magnitude_reg;
    end

    assign req_ready = (state == ST_IDLE);
    assign busy = (state != ST_IDLE);

    // No asynchronous reset here: the FSM reads each register only after its
    // preceding state has written it, and this lets Vivado use DSP output regs.
    always_ff @(posedge clk) begin
        if (state == ST_PRODUCT) begin
            p_xr_reg <= product_xr_comb;
            b_nr_reg <= product_nr_comb;
        end
        if (state == ST_REFINE) begin
            b_nr_pipe_reg <= b_nr_reg;
            delta_magnitude_reg <= delta_magnitude_comb;
            delta_negative_reg <= delta_negative_comb;
        end
        if (state == ST_COMBINE) begin
            delta_product_lo_reg <= delta_product_lo_comb;
            delta_product_hi_reg <= delta_product_hi_comb;
        end else if (state == ST_DELTA_SUM) begin
            delta_product_mag_reg <= delta_product_mag_sum_comb;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            done <= 1'b0;
            quotient <= 32'b0;
            remainder <= 32'b0;
            result <= 32'b0;
            raw_dividend_reg <= 32'b0;
            raw_divisor_reg <= 32'b0;
            raw_signed_div_reg <= 1'b0;
            raw_want_remainder_reg <= 1'b0;
            n_reg <= 32'b0;
            d_reg <= 32'b0;
            x_reg <= 32'b0;
            shift_reg <= 6'b0;
            rom_addr_reg <= '0;
            seed_reg <= '0;
            e_reg <= '0;
            c_reg <= '0;
            q_est_reg <= '0;
            q_product_reg <= '0;
            rem_pre_reg <= '0;
            q_magnitude_reg <= '0;
            r_magnitude_reg <= '0;
            quotient_negative_reg <= 1'b0;
            remainder_negative_reg <= 1'b0;
            want_remainder_reg <= 1'b0;
            special_quotient_reg <= 32'b0;
            special_remainder_reg <= 32'b0;
        end else if (cancel) begin
            // A flushed EX resident must not leave a completion pulse that a
            // younger request could mistake for its own result.
            state <= ST_IDLE;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (req_valid) begin
                        raw_dividend_reg <= dividend;
                        raw_divisor_reg <= divisor;
                        raw_signed_div_reg <= signed_div;
                        raw_want_remainder_reg <= want_remainder;
                        state <= ST_SETUP;
                    end
                end

                // Explicit input/setup stage.  It isolates the external
                // operand pins from the leading-zero/normalization network.
                ST_SETUP: begin
                    want_remainder_reg <= raw_want_remainder_reg;
                    if (raw_divisor_reg == 32'b0) begin
                        special_quotient_reg <= 32'hffff_ffff;
                        special_remainder_reg <= raw_dividend_reg;
                        state <= ST_SPECIAL;
                    end else if (raw_signed_div_reg &&
                                 (raw_dividend_reg == 32'h8000_0000) &&
                                 (raw_divisor_reg == 32'hffff_ffff)) begin
                        special_quotient_reg <= 32'h8000_0000;
                        special_remainder_reg <= 32'b0;
                        state <= ST_SPECIAL;
                    end else begin
                        quotient_negative_reg <= raw_signed_div_reg &&
                                                 (raw_dividend_reg[31] ^ raw_divisor_reg[31]);
                        remainder_negative_reg <= raw_signed_div_reg &&
                                                  raw_dividend_reg[31];
                        n_reg <= dividend_abs;
                        d_reg <= divisor_abs;
                        state <= ST_NORMALIZE;
                    end
                end

                // Normalize the registered absolute divisor in its own
                // cycle.  This is the input pipeline stage requested for
                // the divider and keeps LZC/shift routing off the raw pins.
                ST_NORMALIZE: begin
                    x_reg <= normalized_divisor_comb;
                    shift_reg <= normalized_lz_comb;
                    rom_addr_reg <= normalized_rom_addr_comb;
                    state <= ST_LOOKUP;
                end

                // Registered ROM read.  The generated table is the midpoint
                // reciprocal seed for the normalized divisor interval.
                ST_LOOKUP: begin
                    state <= ST_SEED;
                end

                ST_SEED: begin
                    seed_reg <= r0_rom_data;
                    state <= ST_PRODUCT;
                end

                // These two products are independent and form the first
                // Goldschmidt stage.
                ST_PRODUCT: begin
                    state <= ST_REFINE;
                end

                // ceil(X*R0/2^31) is intentional: it keeps the following
                // correction factor on the conservative side of 2-X*R0.
                ST_REFINE: begin
                    e_reg <= correction_factor_comb;
                    state <= ST_COMBINE;
                end

                // Register two narrow partial products before summing them.
                ST_COMBINE: begin
                    state <= ST_DELTA_SUM;
                end

                ST_DELTA_SUM: begin
                    state <= ST_ACCUMULATE;
                end

                // The reconstructed product directly approximates N/X.
                ST_ACCUMULATE: begin
                    c_reg <= product_be_comb;
                    state <= ST_QUOT;
                end

                ST_QUOT: begin
                    q_est_reg <= quotient_est_comb;
                    state <= ST_QPROD;
                end

                ST_QPROD: begin
                    q_product_reg <= quotient_product_comb;
                    state <= ST_REMAINDER;
                end

                ST_REMAINDER: begin
                    rem_pre_reg <= {32'b0, n_reg} - q_product_reg;
                    state <= ST_CORRECT;
                end

                ST_CORRECT: begin
                    if (rem_pre_reg >= {32'b0, d_reg}) begin
                        q_magnitude_reg <= q_est_reg + 32'd1;
                        r_magnitude_reg <= rem_pre_reg[31:0] - d_reg;
                    end else begin
                        q_magnitude_reg <= q_est_reg;
                        r_magnitude_reg <= rem_pre_reg[31:0];
                    end
                    state <= ST_SIGN;
                end

                ST_SIGN: begin
                    quotient <= signed_quotient_comb;
                    remainder <= signed_remainder_comb;
                    result <= want_remainder_reg ? signed_remainder_comb :
                                                   signed_quotient_comb;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                ST_SPECIAL: begin
                    quotient <= special_quotient_reg;
                    remainder <= special_remainder_reg;
                    result <= want_remainder_reg ? special_remainder_reg :
                                                   special_quotient_reg;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    rv32_recip_rom #(
        .ADDR_WIDTH(ROM_ADDR_WIDTH),
        .DATA_WIDTH(F),
        .MEM_FILE(ROM_FILE)
    ) u_recip_rom (
        .clk(clk),
        .en(state == ST_LOOKUP),
        .addr(rom_addr_reg),
        .data(r0_rom_data)
    );

endmodule
