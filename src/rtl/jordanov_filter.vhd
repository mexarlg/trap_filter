--==============================================================================
--  Module:        jordanov_filter.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       15/07/2026
--  Last Modified: 
--
--  Description:
--  Jordanov trapezoidal filter implemented for the pulse shaping transformation. 
--  Designed for unsigned input and signed output with a latency of 6 cycles.
--  Filtered data is valid after: delay_cycles + data_n reg + 6 cycles + 2 cycles of delayed acc1_q1
--
--  Dependencies:
--
--  Moving average equations:
--    
--    diff[n] = v[n] - v_k[n] - v_l[n] + v_kl[n]              (Delayed diff)
--    acc1[n] = acc1[n-1] + diff[n]                           (Running sum 1)
--    Md_full[n] = M_scaled * diff[n]                         (DSP multiplication)
--    Md_full[n] = M_scaled >> X bits                         (Scaling back)
--    acc2[n] = acc2[n-1] + acc1[n] + Md_full[n]              (Running sum 2)
--    y[n]   = acc2[n] >> X bits                              (Normalization at output)
-- 
--  Parameter selection comments:
--  k -> 8 bits, should be 2^N (128 < k < 256)
--  m -> 8 bits, should be 2^N (100 < m < 256)
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity jordanov_filter is
    generic (
        -- Jordanov parameters
        G_DATA_WIDTH   : natural range 8 to 16 := 14; -- Width of incoming data stream (ADC Magnitude resolution)
        G_K_RISE_WIDTH : natural range 2 to 8  := 8;  -- Width of delay needed for rising time (all bits -> '1' for multiple of 2^N)
        -- Exponential decay
        G_M_VALUE      : natural range 0 to 65535 := 39992; -- Width of decay exp factor (big "M_exp", 12 bits mag + 4 bits fraction)
        G_M_FRAC_WIDTH : natural range 1 to 4     := 4;     -- Width of decay exp factor for its fraction (big "M_exp")
        -- Fixed point params
        G_DIFF_MARGIN_BITS : natural range 1 to 3  := 3; -- Width of margin given to the delayed difference
        G_ACC1_MARGIN_BITS : natural range 1 to 2  := 2; -- Width of margin given to the 1st accumulator
        G_ACC2_MARGIN_BITS : natural range 0 to 1  := 1; -- Width of margin given to the 2nd accumulator
        G_OUT_SHIFT        : natural range 0 to 24 := 1  -- Width of margin given to the 2nd accumulator
    );
    port (
        ------------------------------------------------------------------------
        -- Clock / Reset
        ------------------------------------------------------------------------
        CLK_I   : in std_logic;
        RST_N_I : in std_logic;
        ------------------------------------------------------------------------
        -- Control Inputs
        ------------------------------------------------------------------------
        CE_I      : in std_logic;                                   -- Chip enable of jordanov filter (DATA_N_I arrives after 1 cycle of CE)
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

    -- Data output sign bit and decay exp params
    constant C_DATA_O_SIGNED : natural := 1;
    constant C_M_MAG_WIDTH   : natural := 12;                                               -- Magnitude width (12 bits)
    constant C_M_WIDTH       : natural := C_M_MAG_WIDTH + G_M_FRAC_WIDTH + C_DATA_O_SIGNED; -- Width of M_exp (17 bits)

    -- Pipeline signal widths
    constant C_DIFF_WIDTH          : natural := G_DATA_WIDTH + C_DATA_O_SIGNED + G_DIFF_MARGIN_BITS;                  -- diff: adc (14b) + sign (1b) + margin (3b) = 18b (min is 16b)
    constant C_ACC1_WIDTH          : natural := G_DATA_WIDTH + C_DATA_O_SIGNED + G_K_RISE_WIDTH + G_ACC1_MARGIN_BITS; -- acc1: adc (14b) + sign (1b) + integ k (8b) + margin (2b) = 25b (min is 24b) 
    constant C_MDIFF_WIDTH         : natural := C_M_WIDTH + C_DIFF_WIDTH;                                             -- product M*diff: M (17b) * diff (18b) = 35b (min is 33b)
    constant C_MDIFF_SCALED_WIDTH  : natural := C_MDIFF_WIDTH - G_M_FRAC_WIDTH;                                       -- product M*diff after >> M_FRAC: Mdiff (35b) - M_FRAC (4b) = 31b (min is 29b)
    constant C_ACC2_WIDTH          : natural := C_MDIFF_SCALED_WIDTH + G_ACC2_MARGIN_BITS + G_K_RISE_WIDTH;           -- acc2: M*diff_scaled (31b) + acc1 (25b) + margin (1b) + integ k (8b) = 40b (min is 39b)
    constant C_DATA_FILTERED_WIDTH : natural := G_DATA_WIDTH + C_DATA_O_SIGNED;                                       -- filtered data: adc (14b) + sign (1b) = 15b

    -- Decay exp params (M_exp)
    constant C_M_FULL_VALUE : signed(C_M_WIDTH - 1 downto 0)     := to_signed(G_M_VALUE, C_M_WIDTH);                     -- Value of M_exp with C_M_WIDTH bits
    constant C_M_ROUND_LSB  : signed(C_MDIFF_WIDTH - 1 downto 0) := to_signed(2 ** (G_M_FRAC_WIDTH - 1), C_MDIFF_WIDTH); -- Half LSB for rounding

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

    -- Output data signals and overflow error: bit1 (acc1), bit0(acc2)
    signal data_filtered : std_logic_vector(C_DATA_FILTERED_WIDTH - 1 downto 0);
    signal error_oflow   : std_logic_vector(1 downto 0);

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

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
            if (CE_I = '1') then
                -- accumulator runs at 'CE' + 1 cycle
                diff <= std_logic_vector(
                    resize(signed('0' & DATA_N_I), diff'length)
                    - resize(signed('0' & DATA_K_I), diff'length)
                    - resize(signed('0' & DATA_L_I), diff'length)
                    + resize(signed('0' & DATA_KL_I), diff'length));
            end if;
        end if;
    end process p_diff;

    -- STAGE 2: Accumulator 1 (acc1[n] = acc1[n-1] + diff[n])
    p_acc1 : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            acc1 <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- the accumulator runs at 'CE' + 2 cycles
                acc1 <= std_logic_vector(signed(acc1)
                    + resize(signed(diff), acc1'length));
            end if;
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
            if (CE_I = '1') then
                -- multiplier runs at 'CE' + 3 cycles
                Mdiff <= std_logic_vector(signed(C_M_FULL_VALUE) * signed(diff));
            end if;
        end if;
    end process p_mult;

    -- STAGE 4: Rescale M back down (Mdiff_full -> Mdiff_scaled)
    p_rescale : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            Mdiff_scaled <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- rescaler runs at 'CE' + 4 cycles
                if (signed(Mdiff) >= 0) then
                    Mdiff_scaled <= std_logic_vector(resize(
                        shift_right(signed(Mdiff) + C_M_ROUND_LSB, G_M_FRAC_WIDTH), Mdiff_scaled'length));
                else
                    Mdiff_scaled <= std_logic_vector(resize(
                        shift_right(signed(Mdiff) - C_M_ROUND_LSB, G_M_FRAC_WIDTH), Mdiff_scaled'length));
                end if;
            end if;
        end if;
    end process p_rescale;

    -- STAGE 5: Accumulator 2 (acc2[n] = acc2[n-1] + acc1[n] + Mdiff_scaled[n])
    p_acc2 : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            acc2 <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- acc2 runs at 'CE' + 5 cycles
                acc2 <= std_logic_vector(signed(acc2)
                    + resize(signed(acc1_q1), acc2'length)
                    + resize(signed(Mdiff_scaled), acc2'length));
            end if;
        end if;
    end process p_acc2;

    -- STAGE 6: Divide by G_OUT_SHIFT
    p_output : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            data_filtered <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- output shifter runs at 'CE' + 6 cycles
                data_filtered <= std_logic_vector(resize(shift_right(signed(acc2), G_OUT_SHIFT), data_filtered'length));
            end if;
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
            if CE_I = '1' then
                -- Accumulator 1
                if (signed(acc1) >= C_OFLOW1_PLIM_S) or (signed(acc1) <= C_OFLOW1_NLIM_S) then
                    error_oflow                                           <= error_oflow or C_ERROR_OFLOW_ACC1;
                end if;
                -- Accumulator 2
                if (signed(acc2) >= C_OFLOW2_PLIM_S) or (signed(acc2) <= C_OFLOW2_NLIM_S) then
                    error_oflow                                           <= error_oflow or C_ERROR_OFLOW_ACC2;
                end if;
            end if;
        end if;
    end process p_oflow;

end architecture rtl;