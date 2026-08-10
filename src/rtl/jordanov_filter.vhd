--==============================================================================
--  Module:        jordanov_filter.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       15/07/2026
--  Last Modified: 10/08/2026
--
--  Description:
--  Jordanov trapezoidal filter implemented for the pulse shaping transformation. 
--  Designed for unsigned input and signed output with a latency of 9 cycles.
--
--  Recursive jordanov equations:
--    
--    Filtering:
--    diff[n] = v[n] - v_k[n] - v_l[n] + v_kl[n]              (+1 cycles: Delayed diff)
--    acc1[n] = acc1[n-1] + diff[n]                           (+2 cycles: Running sum 1)
--    Md_full[n] = M_scaled * diff[n]                         (+3 cycles: DSP multiplication)
--    Md_full[n] = M_scaled >> X bits                         (+4 cycles: Scaling back)
--    acc2[n] = acc2[n-1] + acc1[n] + Md_full[n]              (+5 cycles: Running sum 2)
--
--    Normalization:
--    acc2_shift[n] = acc2[n] << C_NORM_SHIFT                 (+6 cycles: Shift to DSP width)
--    norm_prod[n] = acc2_shift[n] * C_NORM_COEF              (+7 cycles: Divide by scale factor G)
--    norm_round[n] = round(norm_prod)                        (+8 cycles: Round output)
--    y[n]   = saturate (norm_round)                          (+9 cycles: Saturate output)
-- 
--  Parameter selection comments:
--  k -> max 8 bits, recommended (128 < 2^k_width < 256)
--  M_exp -> represented in 16 bits (12 magnitude, 4 fraction)
--
--  Dependencies:
--  trap_filter_pkg.vhd, shift_register.vhd, delay_module.vhd,
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity jordanov_filter is
    generic (
        -- General parameters
        G_DATA_WIDTH : natural range 8 to 16 := 14; -- Width of incoming data stream (ADC Magnitude resolution)
        -- Jordanov parameters
        G_K_WIDTH     : natural range 2 to 8     := 8;     -- Width of the delay for rising edge of filtered trapezoid
        G_M_EXP_VALUE : natural range 0 to 65535 := 39992; -- Value of the decay exp coefficient (12 bits mag + 4 bits fraction)
        -- Fixed point params
        G_DIFF_MARGIN_BITS : natural range 1 to 3 := 3; -- Bits of margin given to the delayed difference
        G_ACC1_MARGIN_BITS : natural range 1 to 2 := 2; -- Bits of margin given to the 1st accumulator
        G_ACC2_MARGIN_BITS : natural range 0 to 1 := 1  -- Bits of margin given to the 2nd accumulator
    );
    port (
        ------------------------------------------------------------------------
        -- Clock / Reset
        ------------------------------------------------------------------------
        CLK_I   : in std_logic;
        RST_N_I : in std_logic;
        ------------------------------------------------------------------------
        -- Inputs
        ------------------------------------------------------------------------
        DATA_N_I  : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Input data at sample N
        DATA_K_I  : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Input delayed data at sample (N - k delay)
        DATA_L_I  : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Input delayed data at sample (N - l delay = N - k - m delay)
        DATA_KL_I : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Input delayed data at sample (N - k - l delay = N - 2k - m delay)
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        DATA_FILTERED_O : out std_logic_vector(G_DATA_WIDTH downto 0); -- Output filtered data stream (delay cycles + N latency cycle)
        ERROR_OFLOW_O   : out std_logic_vector(1 downto 0)             -- Indicates an overflow error: bit1 (acc1), bit0(acc2)
    );
end entity jordanov_filter;

architecture rtl of jordanov_filter is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- Width of exponential decay factor M_exp
    constant C_DATA_OUT_SIGN    : natural := 1;                                                        -- Sign bit of output
    constant C_M_EXP_MAG_WIDTH  : natural := 12;                                                       -- Magnitude width of M_exp (12 bits)
    constant C_M_EXP_FRAC_WIDTH : natural := 4;                                                        -- Fraction width of M_exp (4 bits)
    constant C_M_EXP_WIDTH      : natural := C_M_EXP_MAG_WIDTH + C_M_EXP_FRAC_WIDTH + C_DATA_OUT_SIGN; -- Width of M_exp (17 bits)

    -- Pipeline signal widths
    constant C_DIFF_WIDTH          : natural := G_DATA_WIDTH + C_DATA_OUT_SIGN + G_DIFF_MARGIN_BITS;             -- diff: adc (14b) + sign (1b) + margin (3b) = 18b (min is 16b)
    constant C_ACC1_WIDTH          : natural := G_DATA_WIDTH + C_DATA_OUT_SIGN + G_K_WIDTH + G_ACC1_MARGIN_BITS; -- acc1: adc (14b) + sign (1b) + integ k (8b) + margin (2b) = 25b (min is 24b) 
    constant C_MDIFF_WIDTH         : natural := C_M_EXP_WIDTH + C_DIFF_WIDTH;                                    -- product M*diff: M (17b) * diff (18b) = 35b (min is 33b)
    constant C_MDIFF_SCALED_WIDTH  : natural := C_MDIFF_WIDTH - C_M_EXP_FRAC_WIDTH;                              -- product M*diff after >> M_FRAC: Mdiff (35b) - M_FRAC (4b) = 31b (min is 29b)
    constant C_ACC2_WIDTH          : natural := C_MDIFF_SCALED_WIDTH + G_ACC2_MARGIN_BITS + G_K_WIDTH;           -- acc2: M*diff_scaled (31b) + acc1 (25b) + margin (1b) + integ k (8b) = 40b (min is 39b)
    constant C_DATA_FILTERED_WIDTH : natural := G_DATA_WIDTH + C_DATA_OUT_SIGN;                                  -- filtered data: adc (14b) + sign (1b) = 15b

    -- Decay exponential coefficient as signed (M_exp)
    constant C_M_EXP_FULL_VALUE : signed(C_M_EXP_WIDTH - 1 downto 0) := to_signed(G_M_EXP_VALUE, C_M_EXP_WIDTH);                 -- Value of M_exp as signed
    constant C_M_EXP_ROUND_LSB  : signed(C_MDIFF_WIDTH - 1 downto 0) := to_signed(2 ** (C_M_EXP_FRAC_WIDTH - 1), C_MDIFF_WIDTH); -- Half LSB for rounding

    -- DSP operand limits
    constant C_DSP_A_WIDTH : natural := 25; -- Widest signed operand in multiplier DSP A
    constant C_DSP_B_WIDTH : natural := 18; -- Widest signed operand in multiplier DSP B

    -- Gain of the filter: G = k * (1 + M_exp) = k * (2^M_FRAC + M_VALUE) / 2^M_FRAC
    constant C_K_VALUE          : natural := 2 ** G_K_WIDTH;                                   -- Value of delay k
    constant C_M_EXP_FRAC_VALUE : natural := 2 ** C_M_EXP_FRAC_WIDTH;                          -- M_exp fractional scaling factor, to not admit those bits
    constant C_GAIN_NUM         : natural := C_K_VALUE * (C_M_EXP_FRAC_VALUE + G_M_EXP_VALUE); -- Gain as exact integer (natural)
    constant C_GAIN_REAL        : real    := real(C_GAIN_NUM) / real(C_M_EXP_FRAC_VALUE);      -- Gain as a real in compilation (divided by scaling from fraction)

    -- Normalization: out = ((acc2 >> NORM_SHIFT) * NORM_COEF + half LSB) >> NORM_FRAC ~= acc2 / G
    constant C_NORM_SHIFT    : natural := f_max(0, C_ACC2_WIDTH - C_DSP_A_WIDTH); -- N bits to shift acc2 into the DSP A port (assert ACC2_WIDTH > DSP_A_WIDTH)
    constant C_NORM_A_WIDTH  : natural := C_ACC2_WIDTH - C_NORM_SHIFT;            -- Width of the shifted acc2 (below DSP_A_WIDTH)
    constant C_NORM_COEF_MAX : real    := real(2 ** (C_DSP_B_WIDTH - 1) - 1);     -- Largest value of DSP B as real

    -- Largest fractional width keeping the reciprocal coefficient inside the DSP B port
    constant C_NORM_FRAC : natural                            := f_log2_floor(C_NORM_COEF_MAX * C_GAIN_REAL / 2.0 ** C_NORM_SHIFT); -- Bits needed for reciprocal
    constant C_NORM_COEF : signed(C_DSP_B_WIDTH - 1 downto 0) :=
    to_signed(integer(2.0 ** C_NORM_FRAC * 2.0 ** C_NORM_SHIFT / C_GAIN_REAL), C_DSP_B_WIDTH); -- Reciprocal coefficient

    -- Normalization pipeline widths
    constant C_NORM_PROD_WIDTH  : natural                                 := C_NORM_A_WIDTH + C_DSP_B_WIDTH;                        -- Product width
    constant C_NORM_ROUND_WIDTH : natural                                 := C_NORM_PROD_WIDTH + 1;                                 -- Product width with addition margin (+ 1 bit)
    constant C_NORM_ROUND_LSB   : signed(C_NORM_ROUND_WIDTH - 1 downto 0) := to_signed(2 ** (C_NORM_FRAC - 1), C_NORM_ROUND_WIDTH); -- Half LSB for rounding

    -- Limits for accumulator1 (signed) overflow error at the last (top) margin bit
    constant C_OFLOW1_PLIM_S : signed(C_ACC1_WIDTH - 1 downto 0) := to_signed(2 ** (C_ACC1_WIDTH - 1 - G_ACC1_MARGIN_BITS) - 1, C_ACC1_WIDTH);
    constant C_OFLOW1_NLIM_S : signed(C_ACC1_WIDTH - 1 downto 0) := - to_signed(2 ** (C_ACC1_WIDTH - 1 - G_ACC1_MARGIN_BITS), C_ACC1_WIDTH);

    -- Limits for accumulator2 (signed) overflow error at the last (top) margin bit
    constant C_OFLOW2_PLIM_S : signed(C_ACC2_WIDTH - 1 downto 0) := (C_ACC2_WIDTH - 1 downto C_ACC2_WIDTH - 1 - G_ACC2_MARGIN_BITS => '0', others => '1');
    constant C_OFLOW2_NLIM_S : signed(C_ACC2_WIDTH - 1 downto 0) := (C_ACC2_WIDTH - 1 downto C_ACC2_WIDTH - 1 - G_ACC2_MARGIN_BITS => '1', others => '0');

    -- overflow error types
    constant C_ERROR_OFLOW_CORRECT : std_logic_vector(1 downto 0) := "00";
    constant C_ERROR_OFLOW_ACC1    : std_logic_vector(1 downto 0) := "10";
    constant C_ERROR_OFLOW_ACC2    : std_logic_vector(1 downto 0) := "01";

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- jordanov pipeline signals
    signal diff         : std_logic_vector(C_DIFF_WIDTH - 1 downto 0);         -- delayed difference
    signal Mdiff        : std_logic_vector(C_MDIFF_WIDTH - 1 downto 0);        -- M*diff (raw)
    signal Mdiff_scaled : std_logic_vector(C_MDIFF_SCALED_WIDTH - 1 downto 0); -- M*diff (scaled)
    signal acc1         : std_logic_vector(C_ACC1_WIDTH - 1 downto 0);         -- Accumulator 1
    signal acc1_q0      : std_logic_vector(C_ACC1_WIDTH - 1 downto 0);         -- Accumulator 1 + 1 cycle
    signal acc1_q1      : std_logic_vector(C_ACC1_WIDTH - 1 downto 0);         -- Accumulator 1 + 2 cycles
    signal acc2         : std_logic_vector(C_ACC2_WIDTH - 1 downto 0);         -- Accumulator 2

    -- normalization pipeline signals
    signal acc2_shift      : std_logic_vector(C_NORM_A_WIDTH - 1 downto 0);     -- Accumulator 2 after the coarse shift
    signal norm_prod       : std_logic_vector(C_NORM_PROD_WIDTH - 1 downto 0);  -- acc2_shift * NORM_COEF
    signal norm_prod_round : std_logic_vector(C_NORM_ROUND_WIDTH - 1 downto 0); -- product + half LSB

    -- Output data signals and overflow error: bit1 (acc1), bit0(acc2)
    signal data_filtered : std_logic_vector(C_DATA_FILTERED_WIDTH - 1 downto 0);
    signal error_oflow   : std_logic_vector(1 downto 0);

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    -- The shifted accumulator must fit the DSP multiplier A port
    assert (C_NORM_A_WIDTH <= C_DSP_A_WIDTH)
    report "jordanov_filter: normalization operand exceeds the DSP A port width"
        severity failure;

    -- The reciprocal coefficient must fit the DSP multiplier B port
    assert (C_NORM_COEF > 0) and (C_NORM_COEF <= to_signed(2 ** (C_DSP_B_WIDTH - 1) - 1, C_DSP_B_WIDTH + 1))
    report "jordanov_filter: normalization coefficient exceeds the DSP B port width"
        severity failure;

    -- At least one fractional bit is needed to build the half LSB rounding constant
    assert (C_NORM_FRAC >= 1)
    report "jordanov_filter: normalization fractional width is too small"
        severity failure;

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    DATA_FILTERED_O <= data_filtered;
    ERROR_OFLOW_O   <= error_oflow;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Filter
    ----------------------------------------------------------------------------

    -- STAGE 1: Delayed difference (diff[n] = v[n] - v_k[n] - v_l[n] + v_kl[n])
    p_diff : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            diff <= (others => '0');
        elsif rising_edge(CLK_I) then
            -- accumulator runs at + 1 cycle
            diff <= std_logic_vector(
                resize(signed('0' & DATA_N_I), diff'length)
                - resize(signed('0' & DATA_K_I), diff'length)
                - resize(signed('0' & DATA_L_I), diff'length)
                + resize(signed('0' & DATA_KL_I), diff'length));
        end if;
    end process p_diff;

    -- STAGE 2: Accumulator 1 (acc1[n] = acc1[n-1] + diff[n])
    p_acc1 : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            acc1 <= (others => '0');
        elsif rising_edge(CLK_I) then
            -- the accumulator runs at + 2 cycles
            acc1 <= std_logic_vector(signed(acc1)
                + resize(signed(diff), acc1'length));
        end if;
    end process p_acc1;

    -- Delay of acc1 of 2 cycles from STAGE 2 (STAGE 3 when asserted) to STAGE 5
    p_reg : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            acc1_q0 <= (others => '0');
            acc1_q1 <= (others => '0');
        elsif rising_edge(CLK_I) then
            acc1_q0 <= acc1;
            acc1_q1 <= acc1_q0;
        end if;
    end process p_reg;

    -- STAGE 3: Pole zero multiply (Mdiff_full = M_full * diff)
    p_mult : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            Mdiff <= (others => '0');
        elsif rising_edge(CLK_I) then
            -- multiplier runs at + 3 cycles
            Mdiff <= std_logic_vector(C_M_EXP_FULL_VALUE * signed(diff));
        end if;
    end process p_mult;

    -- STAGE 4: Rescale M back down (Mdiff_full -> Mdiff_scaled)
    p_rescale : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            Mdiff_scaled <= (others => '0');
        elsif rising_edge(CLK_I) then
            -- rescaler runs at + 4 cycles
            if (signed(Mdiff) >= 0) then
                Mdiff_scaled <= std_logic_vector(resize(
                    shift_right(signed(Mdiff) + C_M_EXP_ROUND_LSB, C_M_EXP_FRAC_WIDTH), Mdiff_scaled'length));
            else
                Mdiff_scaled <= std_logic_vector(resize(
                    shift_right(signed(Mdiff) - C_M_EXP_ROUND_LSB, C_M_EXP_FRAC_WIDTH), Mdiff_scaled'length));
            end if;
        end if;
    end process p_rescale;

    -- STAGE 5: Accumulator 2 (acc2[n] = acc2[n-1] + acc1[n] + Mdiff_scaled[n])
    p_acc2 : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            acc2 <= (others => '0');
        elsif rising_edge(CLK_I) then
            -- acc2 runs at + 5 cycles
            acc2 <= std_logic_vector(signed(acc2)
                + resize(signed(acc1_q1), acc2'length)
                + resize(signed(Mdiff_scaled), acc2'length));
        end if;
    end process p_acc2;

    ----------------------------------------------------------------------------
    -- Normalization: unity gain from the ADC input to the filtered output
    ----------------------------------------------------------------------------

    -- STAGE 6: Shift of acc2 down to the DSP A port width
    p_norm_shift : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            acc2_shift <= (others => '0');
        elsif rising_edge(CLK_I) then
            -- shifter runs at + 6 cycles
            acc2_shift <= std_logic_vector(resize(
                shift_right(signed(acc2), C_NORM_SHIFT), acc2_shift'length));
        end if;
    end process p_norm_shift;

    -- STAGE 7: Gain multiply (norm_prod = acc2_shift * NORM_COEF)
    p_norm_mult : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            norm_prod <= (others => '0');
        elsif rising_edge(CLK_I) then
            -- multiplier runs at + 7 cycles
            norm_prod <= std_logic_vector(signed(acc2_shift) * C_NORM_COEF);
        end if;
    end process p_norm_mult;

    -- STAGE 8: Add the half LSB used for the fine shift
    p_norm_round : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            norm_prod_round <= (others => '0');
        elsif rising_edge(CLK_I) then
            -- rounder runs at + 8 cycles
            norm_prod_round <= std_logic_vector(
                resize(signed(norm_prod), norm_prod_round'length) + C_NORM_ROUND_LSB);
        end if;
    end process p_norm_round;

    -- STAGE 9: Fine shift (saturated) back to the output width
    p_output : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            data_filtered <= (others => '0');
        elsif rising_edge(CLK_I) then
            -- output shifter runs at + 9 cycles
            data_filtered <= std_logic_vector(f_sat_resize(
                shift_right(signed(norm_prod_round), C_NORM_FRAC), data_filtered'length));
        end if;
    end process p_output;

    ----------------------------------------------------------------------------
    -- Error handling: Overflow
    ----------------------------------------------------------------------------

    -- raise overflow flag when any of accumulators are to be overflowed (margin bits used)
    p_oflow : process (CLK_I, RST_N_I)
    begin
        if RST_N_I = '0' then
            error_oflow <= C_ERROR_OFLOW_CORRECT;
        elsif rising_edge(CLK_I) then
            -- Accumulator 1
            if (signed(acc1) >= C_OFLOW1_PLIM_S) or (signed(acc1) <= C_OFLOW1_NLIM_S) then
                error_oflow                                           <= error_oflow or C_ERROR_OFLOW_ACC1;
            end if;
            -- Accumulator 2
            if (signed(acc2) >= C_OFLOW2_PLIM_S) or (signed(acc2) <= C_OFLOW2_NLIM_S) then
                error_oflow                                           <= error_oflow or C_ERROR_OFLOW_ACC2;
            end if;
        end if;
    end process p_oflow;

end architecture rtl;