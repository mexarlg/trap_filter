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
--  Delay module (DELAY_filt_data_valid_I should be triggered just when all delay data fills 
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
        G_DATA_WIDTH      : integer := 14; -- Width of incoming data stream (ADC Magnitude resolution)
        G_DELAY_WIDTH     : integer := 4;  -- Width of samples averaged (all bits -> '1' for multiple of 2^N)
        G_ACC_MARGIN_BITS : integer := 1;  -- Width of margin given to the accumulator
        G_DATA_SIGNED     : integer := 0   -- Data signed (1) or unsigned (0) -> DATA_OUT_WIDTH = DATA_WIDTH + DATA_SIGNED
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
        CE_I          : in std_logic;                                                   -- Chip enable of moving average filter
        DATA_N_I      : in std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0); -- Input data at sample N
        DATA_D_I      : in std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0); -- Input delayed data at sample (N - delay)
        DELAY_READY_I : in std_logic;                                                   -- Enough samples stored flag in delayed/memory module (asserted when filled)
        SAMPLE_TRIG_I : in std_logic;                                                   -- Trigger to register a filtered data sample as output (will capture at + 1 cycle)
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        FILT_DATA_O           : out std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0); -- Output filtered data stream (delay cycles + 2 latency cycle)
        FILT_DATA_VALID_O     : out std_logic;                                                   -- Filter output is filt_data_valid (delay cycles + 2 latency cycle)
        CAPTURED_DATA_O       : out std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0); -- Latched output data sample (delay cycles + 2 latency cycle + 1 reg cycle)
        CAPTURED_DATA_VALID_O : out std_logic                                                    -- Indicates an output data has been latched
    );
end entity mov_avg_filter;

architecture rtl of mov_avg_filter is

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- Accumulator signal width = sign + data + log2(delay) + margin
    constant C_ACC_WIDTH : integer := G_DATA_SIGNED + G_DATA_WIDTH + G_DELAY_WIDTH + G_ACC_MARGIN_BITS;

    -- Amount of bits to shift for division of (1/N)
    constant C_SHIFT : integer := G_DELAY_WIDTH;

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- accumulator signal
    signal acc_reg : std_logic_vector(C_ACC_WIDTH - 1 downto 0);

    -- Output signals
    signal filt_data           : std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0);
    signal captured_data       : std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0);
    signal captured_data_valid : std_logic;

    -- latency = delay cycles + 2 cycle
    signal filt_data_valid    : std_logic;
    signal filt_data_valid_q0 : std_logic;

begin

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------
    FILT_DATA_O           <= filt_data;
    CAPTURED_DATA_O       <= captured_data;
    CAPTURED_DATA_VALID_O <= captured_data_valid;
    FILT_DATA_VALID_O     <= filt_data_valid_q0;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    -- Accumulator: acc[n] <= acc[n-1] + x[n] - x[n-delay]
    p_acc : process (CLK_I)
    begin
        if rising_edge(CLK_I) then
            if (RST_N_I = '0') then
                acc_reg <= (others => '0');
            elsif (CE_I = '1') then
                -- the accumulator runs at 'CE' + 1 cycle of registering the accumulator
                if G_DATA_SIGNED = 1 then
                    if (DELAY_READY_I = '1') then
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
                    if (DELAY_READY_I = '1') then
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
    p_output : process (CLK_I)
    begin
        if rising_edge(CLK_I) then
            if (RST_N_I = '0') then
                filt_data <= (others => '0');
            elsif (CE_I = '1') then
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
    p_capture : process (CLK_I)
    begin
        if rising_edge(CLK_I) then
            if (RST_N_I = '0') then
                captured_data       <= (others => '0');
                captured_data_valid <= '0';
            elsif (CE_I = '1') then
                captured_data_valid <= '0';
                -- capture data if trigger and delays are filt_data_valid
                if (SAMPLE_TRIG_I = '1') and (filt_data_valid_q0 = '1') then
                    captured_data       <= filt_data;
                    captured_data_valid <= '1';
                end if;
            end if;
        end if;
    end process p_capture;

    -- Filter data is filt_data_valid once the delay storing is completed + 2 cycles
    p_filt_data_valid : process (CLK_I)
    begin
        if rising_edge(CLK_I) then
            if (RST_N_I = '0') then
                filt_data_valid    <= '0';
                filt_data_valid_q0 <= '0';
            elsif (CE_I = '1') then
                filt_data_valid    <= DELAY_READY_I;
                filt_data_valid_q0 <= filt_data_valid;
            end if;
        end if;
    end process p_filt_data_valid;

end architecture rtl;