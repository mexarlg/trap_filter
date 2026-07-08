--==============================================================================
--  Module:        mov_avg_filter.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       06/07/2026
--  Last Modified: 
--
--  Description:
--  Moving average filter implemented for the baseline reduction and the height extraction. 
--  Designed for both unsigned and signed inputs with a latency of 2 cycles.
--  Filtered data is valid after: delay_cycles + 2 cycles (captured data at delay_cycles + 3 cycles)
--
--  Dependencies:
--  Delay module (DATA_D_VALID_I should be triggered just when all delay data fills 
--  so accumulator can access v_d at next cycle)
--
--  Moving average equations:
-- 
--    acc[n] = acc[n-1] + v[n] - v[n-d]     (running sum)
--    y[n]   = acc[n] >> log2(d)            (normalization at output)
-- 
--  Latency comments:
--  Latency (x[n] -> y[n]) = delay cycles + 2 latency cycle = 130 cycles (if delay of 128)
--  Latency (x[n] -> y[n] -> y_captured[n]) = delay cycles + 2 latency cycle + 1 reg cycle = 131 cycles (if delay of 128)
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity mov_avg_filter is
    generic (
        G_DATA_WIDTH      : natural range 4 to 16 := 14; -- Width of incoming data stream (ADC Magnitude resolution)
        G_DELAY_WIDTH     : natural range 0 to 10 := 4;  -- Width of samples averaged (all bits -> '1' for multiple of 2^N)
        G_ACC_MARGIN_BITS : natural range 2 to 5  := 2;  -- Width of margin given to the accumulator
        G_DATA_SIGNED     : natural range 0 to 1  := 0   -- Data signed (1) or unsigned (0) -> DATA_OUT_WIDTH = DATA_WIDTH + DATA_SIGNED
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
        CE_I                : in std_logic;                                                   -- Chip enable of moving average filter
        DATA_N_I            : in std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0); -- Input data at sample N
        DATA_D_I            : in std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0); -- Input delayed data at sample (N - delay)
        DATA_D_VALID_I      : in std_logic;                                                   -- Enough samples stored flag in delayed/memory module (asserted when filled)
        CAPTURE_DATA_TRIG_I : in std_logic;                                                   -- Trigger to register a filtered data sample as output (will capture at + 1 cycle)
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        FILT_DATA_O          : out std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0); -- Output filtered data stream (delay cycles + 2 latency cycle)
        FILT_DATA_VALID_O    : out std_logic;                                                   -- Filter output is filt_data_valid (delay cycles + 2 latency cycle)
        CAPTURE_DATA_O       : out std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0); -- Latched output data sample (delay cycles + 2 latency cycle + 1 reg cycle)
        CAPTURE_DATA_VALID_O : out std_logic;                                                   -- Indicates an output data has been latched
        ------------------------------------------------------------------------
        -- Status
        ------------------------------------------------------------------------
        STAT_ERROR_O : out std_logic_vector(3 downto 0) -- Indicates an error: bit3 (general error), bit2 (type overflow), bit1 (type delay), bit0(type seu)
    );
end entity mov_avg_filter;

architecture rtl of mov_avg_filter is

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- Accumulator signal width = sign + data + log2(delay) + margin
    constant C_ACC_WIDTH : natural := G_DATA_SIGNED + G_DATA_WIDTH + G_DELAY_WIDTH + G_ACC_MARGIN_BITS;

    -- Amount of bits to shift for division of (1/N)
    constant C_SHIFT : natural := G_DELAY_WIDTH;

    -- Value of delay in clk samples
    constant C_DELAY_VALUE : integer := 2 ** G_DELAY_WIDTH;

    -- Expected limits for a possible delay count saveguard (1 bit more of delay width)
    constant C_CNT_DEL_MAX  : std_logic_vector(G_DELAY_WIDTH - 1 downto 0) := (others => '1');
    constant C_CNT_DEL_ONE  : std_logic_vector(G_DELAY_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, G_DELAY_WIDTH));
    constant C_CNT_DEL_ZERO : std_logic_vector(G_DELAY_WIDTH - 1 downto 0) := (others => '0');

    -- Limits for accumulator overflow error at the last (top) margin bit
    constant C_OFLOW_TOP_BIT : natural := G_DATA_WIDTH + G_DELAY_WIDTH + G_ACC_MARGIN_BITS - 1;

    -- Signed and unsigned positive and negative limits
    constant C_OFLOW_PLIM_U : unsigned(C_ACC_WIDTH - 1 downto 0) := to_unsigned(2 ** C_OFLOW_TOP_BIT, C_ACC_WIDTH);
    constant C_OFLOW_PLIM_S : signed(C_ACC_WIDTH - 1 downto 0)   := to_signed(2 ** C_OFLOW_TOP_BIT, C_ACC_WIDTH);
    constant C_OFLOW_NLIM_S : signed(C_ACC_WIDTH - 1 downto 0)   := to_signed( - (2 ** C_OFLOW_TOP_BIT), C_ACC_WIDTH);

    -- Error types
    constant C_STAT_NO_ERROR    : std_logic_vector(3 downto 0) := "0000"; -- no error
    constant C_STAT_DELAY_ERROR : std_logic_vector(3 downto 0) := "1010"; -- delayed data not synchronized
    constant C_STAT_OFLOW_ERROR : std_logic_vector(3 downto 0) := "1100"; -- accumulator about to overflow
    constant C_STAT_SEU_ERROR   : std_logic_vector(3 downto 0) := "1001"; -- seu?

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- accumulator signal
    signal acc_reg : std_logic_vector(C_ACC_WIDTH - 1 downto 0);

    -- Output signals
    signal filt_data          : std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0);
    signal capture_data       : std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0);
    signal capture_data_valid : std_logic;

    -- latency = delay cycles + 2 cycle
    signal filt_data_valid    : std_logic;
    signal filt_data_valid_q0 : std_logic;

    -- Delay error synchronization signals
    signal cnt_del           : std_logic_vector(G_DELAY_WIDTH - 1 downto 0);
    signal data_d_valid_trig : std_logic;
    signal data_d_error_cond : std_logic;

    -- Overflow error signals
    signal acc_oflow_error_cond : std_logic;

    -- output error signal -> bit3 (general error), bit2 (type overflow), bit1 (type delay), bit0(type seu)
    signal stat_error : std_logic_vector(3 downto 0);

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------
    FILT_DATA_O          <= filt_data;
    CAPTURE_DATA_O       <= capture_data;
    CAPTURE_DATA_VALID_O <= capture_data_valid;
    FILT_DATA_VALID_O    <= filt_data_valid_q0;
    STAT_ERROR_O         <= stat_error;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Filter
    ----------------------------------------------------------------------------

    -- Accumulator: acc[n] <= acc[n-1] + x[n] - x[n-delay]
    p_acc : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            acc_reg <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- the accumulator runs at 'CE' + 1 cycle of registering the accumulator
                if G_DATA_SIGNED = 1 then
                    if (data_d_valid_trig = '1') then
                        -- nominal, add the delayed data substraction
                        acc_reg <= std_logic_vector(signed(acc_reg)
                            + resize(signed(DATA_N_I), acc_reg'length)
                            - resize(signed(DATA_D_I), acc_reg'length));
                    else
                        -- delays not filled, only accumulate vn
                        acc_reg <= std_logic_vector(signed(acc_reg)
                            + resize(signed(DATA_N_I), acc_reg'length));
                    end if;
                else
                    -- nominal, add the delayed data substraction
                    if (data_d_valid_trig = '1') then
                        acc_reg <= std_logic_vector(unsigned(acc_reg)
                            + resize(unsigned(DATA_N_I), acc_reg'length)
                            - resize(unsigned(DATA_D_I), acc_reg'length));
                    else
                        -- delays not filled, only accumulate vn
                        acc_reg <= std_logic_vector(unsigned(acc_reg)
                            + resize(unsigned(DATA_N_I), acc_reg'length));
                    end if;
                end if;
            end if;
        end if;
    end process p_acc;

    -- Divide by N (arithmetic or logical shift since N is proportional to 2^N)
    p_output : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            filt_data <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- shifter runs at 'CE' + 1 cycle of accumulator + 1 cycle of registering the shift
                if G_DATA_SIGNED = 1 then
                    -- arithmetic shift
                    filt_data <= std_logic_vector(
                        resize(shift_right(signed(acc_reg), C_SHIFT), filt_data'length));
                else
                    -- logic shift
                    filt_data <= std_logic_vector(
                        resize(shift_right(unsigned(acc_reg), C_SHIFT), filt_data'length));
                end if;
            end if;
        end if;
    end process p_output;

    -- Latch a filtered sample on trigger (delay_cycles + 2 cycles latency + 1 reg cycle)
    p_capture : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            capture_data       <= (others => '0');
            capture_data_valid <= '0';
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                capture_data_valid <= '0'; -- capture_data_valid is a strobe
                -- always capture data if trigger (but capture_data_valid is only asserted if no errors)
                if (CAPTURE_DATA_TRIG_I = '1') then
                    capture_data <= filt_data;
                    if (stat_error = C_STAT_NO_ERROR) then
                        capture_data_valid <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process p_capture;

    -- Filter data is ready once the delay storing is completed + 2 cycles
    p_ready : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            filt_data_valid    <= '0';
            filt_data_valid_q0 <= '0';
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- Output data even if error (valid not asserted)
                if (stat_error = C_STAT_NO_ERROR) then
                    filt_data_valid    <= data_d_valid_trig;
                    filt_data_valid_q0 <= filt_data_valid;
                else
                    filt_data_valid_q0 <= '0';
                end if;
            end if;
        end if;
    end process p_ready;

    -- status error flags
    p_err : process (CLK_I, RST_N_I)
    begin
        if RST_N_I = '0' then
            stat_error <= C_STAT_NO_ERROR;
        elsif rising_edge(CLK_I) then
            -- data_d_valid latched sync error
            if data_d_error_cond = '1' then
                stat_error <= stat_error or C_STAT_DELAY_ERROR;
            end if;
            -- accumulator overflow prevention latched error
            if acc_oflow_error_cond = '1' then
                stat_error <= stat_error or C_STAT_OFLOW_ERROR;
            end if;
        end if;
    end process p_err;

    ----------------------------------------------------------------------------
    -- Error status: Delay not sync
    ----------------------------------------------------------------------------

    -- Assert internal delay valid in case external DATA_D_VALID is not properly asserted
    data_d_valid_trig <= '1' when cnt_del = C_CNT_DEL_MAX else
        '0';
    -- Delay sync error condition (when both data_valid are different)
    data_d_error_cond <= '1' when (data_d_valid_trig /= DATA_D_VALID_I) and (CE_I = '1') else
        '0';

    -- counter that times-out at maximum (when data_d_valid should be triggered)
    p_cnt : process (CLK_I, RST_N_I)
    begin
        if RST_N_I = '0' then
            cnt_del <= C_CNT_DEL_ZERO;
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                if (unsigned(cnt_del) < unsigned(C_CNT_DEL_MAX)) then
                    cnt_del <= std_logic_vector(unsigned(cnt_del) + unsigned(C_CNT_DEL_ONE));
                end if;
            end if;
        end if;
    end process p_cnt;

    ----------------------------------------------------------------------------
    -- Error status: Overflow
    ----------------------------------------------------------------------------

    -- raise overflow flag when margin bits are being used
    p_margin : process (CLK_I, RST_N_I)
    begin
        if RST_N_I = '0' then
            acc_oflow_error_cond <= '0';
        elsif rising_edge(CLK_I) then
            if CE_I = '1' then
                if G_DATA_SIGNED = 1 then
                    if (signed(acc_reg) >= C_OFLOW_PLIM_S) or (signed(acc_reg) <= C_OFLOW_NLIM_S) then
                        acc_oflow_error_cond                                       <= '1';
                    end if;
                else
                    if unsigned(acc_reg) >= C_OFLOW_PLIM_U then
                        acc_oflow_error_cond <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;