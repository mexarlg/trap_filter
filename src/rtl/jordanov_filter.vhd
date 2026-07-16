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
--  Delay module (DATA_KL_VALID_I should be triggered just when all delay data fills 
--  so accumulator can access delays at next cycle. KL is the limiting delay, the largest)
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
        G_M_FLAT_WIDTH : natural range 2 to 8  := 8;  -- Width of delay needed for flat top (all bits -> '1' for multiple of 2^N)
        -- Exponential decay
        G_M_VALUE      : natural range 0 to 65535 := 4096; -- Width of decay exp factor (big "M_exp", 12 bits mag + 4 bits fraction)
        G_M_FRAC_WIDTH : natural range 1 to 4     := 4;    -- Width of decay exp factor for its fraction (big "M_exp")
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
        CE_I            : in std_logic;                                   -- Chip enable of jordanov filter (DATA_N_I arrives after 1 cycle of CE)
        DATA_N_I        : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Input data at sample N
        DATA_K_I        : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Input delayed data at sample (N - k delay)
        DATA_L_I        : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Input delayed data at sample (N - l delay = N - k - m delay)
        DATA_KL_I       : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Input delayed data at sample (N - k - l delay = N - 2k - m delay)
        DATA_K_VALID_I  : in std_logic;                                   -- Enough samples stored flag in k delayed/memory module (asserted when filled)
        DATA_L_VALID_I  : in std_logic;                                   -- Enough samples stored flag in l delayed/memory module (asserted when filled)
        DATA_KL_VALID_I : in std_logic;                                   -- Enough samples stored flag in kl delayed/memory module (asserted when filled)
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        FILT_DATA_O       : out std_logic_vector(G_DATA_WIDTH downto 0); -- Output filtered data stream (delay cycles + N latency cycle)
        FILT_DATA_VALID_O : out std_logic;                               -- Filter output is filt_data_valid (delay cycles + N latency cycle)
        ------------------------------------------------------------------------
        -- Status
        ------------------------------------------------------------------------
        STAT_ERROR_O : out std_logic_vector(3 downto 0) -- Indicates an error: bit3 (general error), bit2 (type overflow), bit1 (type delay), bit0(type seu?)
    );
end entity jordanov_filter;

architecture rtl of jordanov_filter is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    function clog2(n : natural) return natural is
        variable r       : natural := 0;
        variable v       : natural := n;
    begin
        while v > 0 loop
            v := v / 2;
            r := r + 1;
        end loop;
        return r;
    end function;

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- Data output sign bit
    constant C_DATA_O_SIGNED : natural := 1;

    -- Decay exponent params (M_exp)
    constant C_M_MAG_WIDTH : natural := 12;                                               -- Magnitude width (12 bits)
    constant C_M_WIDTH     : natural := C_M_MAG_WIDTH + G_M_FRAC_WIDTH + C_DATA_O_SIGNED; -- Width of M_exp (17 bits)

    -- Pipeline signal widths
    constant C_DIFF_WIDTH         : natural := G_DATA_WIDTH + C_DATA_O_SIGNED + G_DIFF_MARGIN_BITS;                  -- diff: adc (14b) + sign (1b) + margin (3b) = 18b (min is 16b)
    constant C_ACC1_WIDTH         : natural := G_DATA_WIDTH + C_DATA_O_SIGNED + G_K_RISE_WIDTH + G_ACC1_MARGIN_BITS; -- acc1: adc (14b) + sign (1b) + integ k (8b) + margin (2b) = 25b (min is 24b) 
    constant C_MDIFF_WIDTH        : natural := C_M_WIDTH + C_DIFF_WIDTH;                                             -- product M*diff: M (17b) * diff (18b) = 35b (min is 33b)
    constant C_MDIFF_SCALED_WIDTH : natural := C_MDIFF_WIDTH - G_M_FRAC_WIDTH;                                       -- product M*diff after >> M_FRAC: Mdiff (35b) - M_FRAC (4b) = 31b (min is 29b)
    constant C_ACC2_WIDTH         : natural := C_MDIFF_SCALED_WIDTH + G_ACC2_MARGIN_BITS + G_K_RISE_WIDTH;           -- acc2: M*diff_scaled (31b) + acc1 (25b) + margin (1b) + integ k (8b) = 40b (min is 39b)
    constant C_FILT_DATA_WIDTH    : natural := G_DATA_WIDTH + C_DATA_O_SIGNED;                                       -- filtered data: adc (14b) + sign (1b) = 15b

    -- Decay exp params (M_exp)
    constant C_M_FULL_VALUE : signed(C_M_WIDTH - 1 downto 0)     := to_signed(G_M_VALUE, C_M_WIDTH);                     -- Value of M_exp with C_M_WIDTH bits
    constant C_M_ROUND_LSB  : signed(C_MDIFF_WIDTH - 1 downto 0) := to_signed(2 ** (G_M_FRAC_WIDTH - 1), C_MDIFF_WIDTH); -- Half LSB for rounding

    -- Delay values for k, m, l = k + m, k + m = 2k + m
    constant C_CNT_K_DELAY  : natural := 2 ** G_K_RISE_WIDTH;
    constant C_CNT_M_DELAY  : natural := 2 ** G_M_FLAT_WIDTH;
    constant C_CNT_L_DELAY  : natural := C_CNT_K_DELAY + C_CNT_M_DELAY;
    constant C_CNT_KL_DELAY : natural := C_CNT_L_DELAY + C_CNT_K_DELAY;

    -- Expected limits for counter of K inner delay to be valid
    constant C_CNT_K_MAX  : std_logic_vector(G_K_RISE_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(C_CNT_K_DELAY - 1, G_K_RISE_WIDTH));
    constant C_CNT_K_ONE  : std_logic_vector(G_K_RISE_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, G_K_RISE_WIDTH));
    constant C_CNT_K_ZERO : std_logic_vector(G_K_RISE_WIDTH - 1 downto 0) := (others => '0');

    -- Expected limits for counter of L inner delay to be valid
    constant C_CNT_L_WIDTH : natural                                      := clog2(C_CNT_L_DELAY);
    constant C_CNT_L_MAX   : std_logic_vector(C_CNT_L_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(C_CNT_L_DELAY - 1, C_CNT_L_WIDTH));
    constant C_CNT_L_ONE   : std_logic_vector(C_CNT_L_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, C_CNT_L_WIDTH));
    constant C_CNT_L_ZERO  : std_logic_vector(C_CNT_L_WIDTH - 1 downto 0) := (others => '0');

    -- Expected limits for counter of KL inner delay to be valid
    constant C_CNT_KL_WIDTH : natural                                       := clog2(C_CNT_KL_DELAY);
    constant C_CNT_KL_MAX   : std_logic_vector(C_CNT_KL_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(C_CNT_KL_DELAY - 1, C_CNT_KL_WIDTH));
    constant C_CNT_KL_ONE   : std_logic_vector(C_CNT_KL_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, C_CNT_KL_WIDTH));
    constant C_CNT_KL_ZERO  : std_logic_vector(C_CNT_KL_WIDTH - 1 downto 0) := (others => '0');

    -- Limits for accumulator1 (signed) overflow error at the last (top) margin bit
    constant C_OFLOW1_TOP_BIT : natural                           := C_ACC1_WIDTH - 1;
    constant C_OFLOW1_PLIM_S  : signed(C_ACC1_WIDTH - 1 downto 0) := to_signed(2 ** (C_ACC1_WIDTH - 1 - G_ACC1_MARGIN_BITS) - 1, C_ACC1_WIDTH);
    constant C_OFLOW1_NLIM_S  : signed(C_ACC1_WIDTH - 1 downto 0) := - to_signed(2 ** (C_ACC1_WIDTH - 1 - G_ACC1_MARGIN_BITS), C_ACC1_WIDTH);

    -- Limits for accumulator2 (signed) overflow error at the last (top) margin bit
    constant C_OFLOW2_TOP_BIT : natural                           := C_ACC2_WIDTH - 1;
    constant C_OFLOW2_PLIM_S  : signed(C_ACC2_WIDTH - 1 downto 0) := (C_ACC2_WIDTH - 1 downto C_ACC2_WIDTH - 1 - G_ACC2_MARGIN_BITS => '0', others => '1');
    constant C_OFLOW2_NLIM_S  : signed(C_ACC2_WIDTH - 1 downto 0) := (C_ACC2_WIDTH - 1 downto C_ACC2_WIDTH - 1 - G_ACC2_MARGIN_BITS => '1', others => '0');

    -- Error types
    constant C_STAT_NO_ERROR    : std_logic_vector(3 downto 0) := "0000"; -- no error
    constant C_STAT_DELAY_ERROR : std_logic_vector(3 downto 0) := "1010"; -- delayed data not synchronized
    constant C_STAT_OFLOW_ERROR : std_logic_vector(3 downto 0) := "1100"; -- accumulator about to overflow
    constant C_STAT_SEU_ERROR   : std_logic_vector(3 downto 0) := "1001"; -- seu (future)

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- jordanov pipelined signals
    signal diff_reg         : std_logic_vector(C_DIFF_WIDTH - 1 downto 0);         -- delayed difference
    signal Mdiff_reg        : std_logic_vector(C_MDIFF_WIDTH - 1 downto 0);        -- M*diff (raw)
    signal Mdiff_scaled_reg : std_logic_vector(C_MDIFF_SCALED_WIDTH - 1 downto 0); -- M*diff (scaled)
    signal acc1_reg         : std_logic_vector(C_ACC1_WIDTH - 1 downto 0);         -- Accumulator 1
    signal acc1_reg_q0      : std_logic_vector(C_ACC1_WIDTH - 1 downto 0);         -- Accumulator 1 + 1 cycle
    signal acc1_reg_q1      : std_logic_vector(C_ACC1_WIDTH - 1 downto 0);         -- Accumulator 1 + 2 cycles
    signal acc2_reg         : std_logic_vector(C_ACC2_WIDTH - 1 downto 0);         -- Accumulator 2

    -- Output data signals
    signal filt_data       : std_logic_vector(C_FILT_DATA_WIDTH - 1 downto 0);
    signal filt_data_valid : std_logic;

    -- registered data_valid to account for pipeline delay
    signal filt_data_valid_q0 : std_logic;
    signal filt_data_valid_q1 : std_logic;
    signal filt_data_valid_q2 : std_logic;
    signal filt_data_valid_q3 : std_logic;
    signal filt_data_valid_q4 : std_logic;
    signal filt_data_valid_q5 : std_logic;
    signal filt_data_valid_q6 : std_logic;
    signal filt_data_valid_q7 : std_logic;

    -- output error signal -> bit3 (general error), bit2 (type overflow), bit1 (type delay), bit0(type seu)
    signal stat_error             : std_logic_vector(3 downto 0);
    signal data_delays_error_cond : std_logic;
    signal acc_oflow_error_cond   : std_logic;

    -- Delay error for k synchronization signals
    signal cnt_k             : std_logic_vector(G_K_RISE_WIDTH - 1 downto 0);
    signal data_k_valid_trig : std_logic;
    signal data_k_error_cond : std_logic;

    -- Delay error for l synchronization signals
    signal cnt_l             : std_logic_vector(C_CNT_L_WIDTH - 1 downto 0);
    signal data_l_valid_trig : std_logic;
    signal data_l_error_cond : std_logic;

    -- Delay error for kl synchronization signals
    signal cnt_kl             : std_logic_vector(C_CNT_KL_WIDTH - 1 downto 0);
    signal data_kl_valid_trig : std_logic;
    signal data_kl_error_cond : std_logic;

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------
    FILT_DATA_O       <= filt_data;
    FILT_DATA_VALID_O <= filt_data_valid_q5;
    STAT_ERROR_O      <= stat_error;

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
            diff_reg <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- accumulator runs at 'CE' + 1 cycle
                if (data_kl_valid_trig = '1') then
                    -- all delays ready, full delayed difference
                    diff_reg <= std_logic_vector(
                        resize(signed('0' & DATA_N_I), diff_reg'length)
                        - resize(signed('0' & DATA_K_I), diff_reg'length)
                        - resize(signed('0' & DATA_L_I), diff_reg'length)
                        + resize(signed('0' & DATA_KL_I), diff_reg'length));
                else
                    -- no delays ready, difference asserted to 0
                    --diff_reg <= (others => '0');
                end if;
            end if;
        end if;
    end process p_diff;

    -- STAGE 2: Accumulator 1 (acc1[n] = acc1[n-1] + diff[n])
    p_acc1 : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            acc1_reg <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- the accumulator runs at 'CE' + 2 cycles
                acc1_reg <= std_logic_vector(signed(acc1_reg)
                    + resize(signed(diff_reg), acc1_reg'length));
            end if;
        end if;
    end process p_acc1;

    -- Delay of acc1 of 2 cycles from STAGE 2 (STAGE 3 when asserted) to STAGE 5
    p_reg : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            acc1_reg_q0 <= (others => '0');
            acc1_reg_q1 <= (others => '0');
        elsif rising_edge(CLK_I) then
            acc1_reg_q0 <= acc1_reg;
            acc1_reg_q1 <= acc1_reg_q0;
        end if;
    end process p_reg;

    -- STAGE 3: Pole zero multiply (Mdiff_full = M_full * diff)
    p_mult : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            Mdiff_reg <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- multiplier runs at 'CE' + 3 cycles
                Mdiff_reg <= std_logic_vector(signed(C_M_FULL_VALUE) * signed(diff_reg));
            end if;
        end if;
    end process p_mult;

    -- STAGE 4: Rescale M back down (Mdiff_full -> Mdiff_scaled)
    p_rescale : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            Mdiff_scaled_reg <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- rescaler runs at 'CE' + 4 cycles
                if (signed(Mdiff_reg) >= 0) then
                    Mdiff_scaled_reg <= std_logic_vector(resize(
                        shift_right(signed(Mdiff_reg) + C_M_ROUND_LSB, G_M_FRAC_WIDTH), Mdiff_scaled_reg'length));
                else
                    Mdiff_scaled_reg <= std_logic_vector(resize(
                        shift_right(signed(Mdiff_reg) - C_M_ROUND_LSB, G_M_FRAC_WIDTH), Mdiff_scaled_reg'length));
                end if;
            end if;
        end if;
    end process p_rescale;

    -- STAGE 5: Accumulator 2 (acc2[n] = acc2[n-1] + acc1[n] + Mdiff_scaled[n])
    p_acc2 : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            acc2_reg <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- acc2 runs at 'CE' + 5 cycles
                acc2_reg <= std_logic_vector(signed(acc2_reg)
                    + resize(signed(acc1_reg_q1), acc2_reg'length)
                    + resize(signed(Mdiff_scaled_reg), acc2_reg'length));
            end if;
        end if;
    end process p_acc2;

    -- STAGE 6: Divide by G_OUT_SHIFT
    p_output : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            filt_data <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- output shifter runs at 'CE' + 6 cycles
                filt_data <= std_logic_vector(resize(shift_right(signed(acc2_reg), G_OUT_SHIFT), filt_data'length));
            end if;
        end if;
    end process p_output;

    -- Filter data is ready once the delay storing is completed + 6 cycles (temporal)
    p_ready : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            filt_data_valid    <= '0';
            filt_data_valid_q0 <= '0';
            filt_data_valid_q1 <= '0';
            filt_data_valid_q2 <= '0';
            filt_data_valid_q3 <= '0';
            filt_data_valid_q4 <= '0';
            filt_data_valid_q5 <= '0';
            filt_data_valid_q6 <= '0';
            filt_data_valid_q7 <= '0';
        elsif rising_edge(CLK_I) then
            if (CE_I = '1' and (stat_error = C_STAT_NO_ERROR)) then
                -- we ensure 6 cycle delay valid for latency at start and after a CE restart
                filt_data_valid    <= data_kl_valid_trig;
                filt_data_valid_q0 <= filt_data_valid;
                filt_data_valid_q1 <= filt_data_valid_q0;
                filt_data_valid_q2 <= filt_data_valid_q1;
                filt_data_valid_q3 <= filt_data_valid_q2;
                filt_data_valid_q4 <= filt_data_valid_q3;
                filt_data_valid_q5 <= filt_data_valid_q4;
                filt_data_valid_q6 <= filt_data_valid_q5;
                filt_data_valid_q7 <= filt_data_valid_q6;
            else
                filt_data_valid_q7 <= '0';
            end if;
        end if;
    end process p_ready;

    ----------------------------------------------------------------------------
    -- Error handling
    ----------------------------------------------------------------------------

    p_err : process (CLK_I, RST_N_I)
    begin
        if RST_N_I = '0' then
            stat_error <= C_STAT_NO_ERROR;
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- delays latched sync error
                if data_delays_error_cond = '1' then
                    stat_error <= stat_error or C_STAT_DELAY_ERROR;
                end if;
                -- accumulator overflow prevention latched error
                if acc_oflow_error_cond = '1' then
                    stat_error <= stat_error or C_STAT_OFLOW_ERROR;
                end if;
            end if;
        end if;
    end process p_err;

    ----------------------------------------------------------------------------
    -- Error status: Delays not synchronized
    ----------------------------------------------------------------------------

    -- counters that time-out at maximum of each of the delays
    p_cnt_k : process (CLK_I, RST_N_I)
    begin
        if RST_N_I = '0' then
            cnt_k  <= C_CNT_K_ZERO;
            cnt_l  <= C_CNT_L_ZERO;
            cnt_kl <= C_CNT_KL_ZERO;
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                if (unsigned(cnt_k) < unsigned(C_CNT_K_MAX)) then
                    cnt_k <= std_logic_vector(unsigned(cnt_k) + unsigned(C_CNT_K_ONE));
                end if;
                if (unsigned(cnt_l) < unsigned(C_CNT_L_MAX)) then
                    cnt_l <= std_logic_vector(unsigned(cnt_l) + unsigned(C_CNT_L_ONE));
                end if;
                if (unsigned(cnt_kl) < unsigned(C_CNT_KL_MAX)) then
                    cnt_kl <= std_logic_vector(unsigned(cnt_kl) + unsigned(C_CNT_KL_ONE));
                end if;
            end if;
        end if;
    end process p_cnt_k;

    -- Assert internal delay valid in case external delays are not properly asserted
    p_valid_trig : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            data_k_valid_trig  <= '0';
            data_l_valid_trig  <= '0';
            data_kl_valid_trig <= '0';
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                if (cnt_k = C_CNT_K_MAX) then
                    data_k_valid_trig <= '1';
                end if;
                if (cnt_l = C_CNT_L_MAX) then
                    data_l_valid_trig <= '1';
                end if;
                if (cnt_kl = C_CNT_KL_MAX) then
                    data_kl_valid_trig <= '1';
                end if;
            end if;
        end if;
    end process p_valid_trig;

    -- Delay sync error condition for delay k
    data_k_error_cond <= '1' when (DATA_K_VALID_I /= data_k_valid_trig) and (CE_I = '1') else
        '0';

    -- Delay sync error condition for delay l
    data_l_error_cond <= '1' when (DATA_L_VALID_I /= data_l_valid_trig) and (CE_I = '1') else
        '0';

    -- Delay sync error condition for delay kl
    data_kl_error_cond <= '1' when (DATA_KL_VALID_I /= data_kl_valid_trig) and (CE_I = '1') else
        '0';

    -- Global delays sync error condition
    data_delays_error_cond <= data_k_error_cond or data_l_error_cond or data_kl_error_cond;

    ----------------------------------------------------------------------------
    -- Error status: Overflow of accumulators
    ----------------------------------------------------------------------------

    -- raise overflow flag when any of accumulators are to be overflowed (margin bits used)
    p_margin : process (CLK_I, RST_N_I)
    begin
        if RST_N_I = '0' then
            acc_oflow_error_cond <= '0';
        elsif rising_edge(CLK_I) then
            if CE_I = '1' then
                -- Accumulator 1
                if (signed(acc1_reg) >= C_OFLOW1_PLIM_S) or (signed(acc1_reg) <= C_OFLOW1_NLIM_S) then
                    acc_oflow_error_cond                                          <= '1';
                end if;
                -- Accumulator 2
                if (signed(acc2_reg) >= C_OFLOW2_PLIM_S) or (signed(acc2_reg) <= C_OFLOW2_NLIM_S) then
                    acc_oflow_error_cond                                          <= '1';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;