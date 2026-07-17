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
        G_DELAY_WIDTH     : natural range 0 to 8  := 4;  -- Width of samples averaged (all bits -> '1' for multiple of 2^N)
        G_ACC_MARGIN_BITS : natural range 2 to 5  := 2;  -- Width of margin given to the accumulator
        G_DATA_I_SIGNED   : natural range 0 to 1  := 0   -- Data signed (1) or unsigned (0) -> DATA_OUT_WIDTH = DATA_WIDTH + DATA_I_SIGNED
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
        CE_I     : in std_logic;                                                     -- Chip enable of moving average filter
        DATA_N_I : in std_logic_vector(G_DATA_WIDTH + G_DATA_I_SIGNED - 1 downto 0); -- Input data at sample N
        DATA_D_I : in std_logic_vector(G_DATA_WIDTH + G_DATA_I_SIGNED - 1 downto 0); -- Input delayed data at sample (N - delay)
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        DATA_FILTERED_O : out std_logic_vector(G_DATA_WIDTH + G_DATA_I_SIGNED - 1 downto 0); -- Output filtered data stream (delay cycles + 2 latency cycle)                                                   -- Indicates an output data has been latched
        ERROR_OFLOW_O   : out std_logic                                                      -- Indicates an error: bit3 (general error), bit2 (type overflow), bit1 (type delay), bit0(type seu)
    );
end entity mov_avg_filter;

architecture rtl of mov_avg_filter is

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- Accumulator signal width = sign + data + log2(delay) + margin
    constant C_ACC_WIDTH : natural := G_DATA_I_SIGNED + G_DATA_WIDTH + G_DELAY_WIDTH + G_ACC_MARGIN_BITS;

    -- Limits for accumulator overflow error at the last (top) margin bit
    constant C_OFLOW_TOP_BIT : natural                            := G_DATA_WIDTH + G_DELAY_WIDTH + G_ACC_MARGIN_BITS - 1;
    constant C_OFLOW_PLIM_U  : unsigned(C_ACC_WIDTH - 1 downto 0) := to_unsigned(2 ** C_OFLOW_TOP_BIT, C_ACC_WIDTH);
    constant C_OFLOW_PLIM_S  : signed(C_ACC_WIDTH - 1 downto 0)   := to_signed(2 ** C_OFLOW_TOP_BIT, C_ACC_WIDTH);
    constant C_OFLOW_NLIM_S  : signed(C_ACC_WIDTH - 1 downto 0)   := to_signed( - (2 ** C_OFLOW_TOP_BIT), C_ACC_WIDTH);

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- accumulator signal
    signal acc_reg : std_logic_vector(C_ACC_WIDTH - 1 downto 0);

    -- Output signals
    signal data_filtered : std_logic_vector(G_DATA_WIDTH + G_DATA_I_SIGNED - 1 downto 0);

    -- Overflow error signals
    signal error_oflow : std_logic;

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

    -- Accumulator: acc[n] <= acc[n-1] + x[n] - x[n-delay]
    p_acc : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            acc_reg <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- the accumulator runs at 'CE' + 1 cycle of registering the accumulator
                if G_DATA_I_SIGNED = 1 then
                    acc_reg <= std_logic_vector(signed(acc_reg)
                        + resize(signed(DATA_N_I), acc_reg'length)
                        - resize(signed(DATA_D_I), acc_reg'length));
                else
                    acc_reg <= std_logic_vector(unsigned(acc_reg)
                        + resize(unsigned(DATA_N_I), acc_reg'length)
                        - resize(unsigned(DATA_D_I), acc_reg'length));
                end if;
            end if;
        end if;
    end process p_acc;

    -- Divide by N (arithmetic or logical shift since N is proportional to 2^N)
    p_output : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            data_filtered <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- shifter runs at 'CE' + 1 cycle of accumulator + 1 cycle of registering the shift
                if G_DATA_I_SIGNED = 1 then
                    -- arithmetic shift
                    data_filtered <= std_logic_vector(
                        resize(shift_right(signed(acc_reg), G_DELAY_WIDTH), data_filtered'length));
                else
                    -- logic shift
                    data_filtered <= std_logic_vector(
                        resize(shift_right(unsigned(acc_reg), G_DELAY_WIDTH), data_filtered'length));
                end if;
            end if;
        end if;
    end process p_output;

    ----------------------------------------------------------------------------
    -- Error status: Overflow
    ----------------------------------------------------------------------------

    -- raise overflow flag when margin bits are being used
    p_margin : process (CLK_I, RST_N_I)
    begin
        if RST_N_I = '0' then
            error_oflow <= '0';
        elsif rising_edge(CLK_I) then
            if CE_I = '1' then
                if G_DATA_I_SIGNED = 1 then
                    if (signed(acc_reg) >= C_OFLOW_PLIM_S) or (signed(acc_reg) <= C_OFLOW_NLIM_S) then
                        error_oflow                                                <= '1';
                    end if;
                else
                    if unsigned(acc_reg) >= C_OFLOW_PLIM_U then
                        error_oflow <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;