--==============================================================================
--  Module:        baseline_restorer.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       09/07/2026
--  Last Modified: 
--
--  Description:
--  Module that takes the filtered data from jordanov and extracts the baseline offset.
--  A latency synchronization is asserted by delaying the fast data (baseline), 
--  while having overflow error control
--
--  Dependencies:
-- 
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity baseline_restorer is
    generic (
        G_DATA_WIDTH   : natural range 8 to 32 := 14; -- Signed width of both input streams and the output
        G_LATENCY_SKEW : natural range 2 to 4  := 2   -- Moving average (baseline) latency (in cycles)
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
        CE_I         : in std_logic;                               -- clock enable
        DATA_JORD_I  : in std_logic_vector(G_DATA_WIDTH downto 0); -- Trapezoidal filtered stream (signed)
        BASELINE_I   : in std_logic_vector(G_DATA_WIDTH downto 0); -- Moving average baseline stream (signed)
        LATCH_TRIG_I : in std_logic;                               -- Freeze baseline trigger
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        DATA_O        : out std_logic_vector(G_DATA_WIDTH downto 0); -- Baseline restored output (signed)
        ERROR_OFLOW_O : out std_logic                                -- overflow flag
    );
end entity baseline_restorer;

architecture rtl of baseline_restorer is

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- Skew line carries the (unsigned) baseline, aligned to the Jordanov stream
    type t_skew_arr is array (0 to G_LATENCY_SKEW) of std_logic_vector(G_DATA_WIDTH downto 0);
    signal delayed_skew : t_skew_arr;

    -- Latched baseline (captured from the aligned stream) and subtraction
    signal baseline_held : std_logic_vector(G_DATA_WIDTH downto 0);
    signal diff_ext      : signed(G_DATA_WIDTH + 1 downto 0); -- 1 guard bit above the 15-bit result

    signal data_out    : std_logic_vector(G_DATA_WIDTH downto 0); -- 15-bit signed
    signal error_oflow : std_logic;

begin

    DATA_O        <= data_out;
    ERROR_OFLOW_O <= error_oflow;

    ----------------------------------------------------------------------------
    -- Skew: delay the faster baseline stream to align with the Jordanov stream
    ----------------------------------------------------------------------------

    p_skew : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            delayed_skew <= (others => (others => '0'));
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                delayed_skew(0) <= DATA_JORD_I;
                for i in 1 to G_LATENCY_SKEW loop
                    delayed_skew(i) <= delayed_skew(i - 1);
                end loop;
            end if;
        end if;
    end process p_skew;

    ----------------------------------------------------------------------------
    -- Latch the baseline on trigger
    ----------------------------------------------------------------------------

    p_latch : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            baseline_held <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                if (LATCH_TRIG_I = '1') then
                    baseline_held <= BASELINE_I;
                end if;
            end if;
        end if;
    end process p_latch;

    ----------------------------------------------------------------------------
    -- Jordanov - baseline offset
    ----------------------------------------------------------------------------

    p_restore : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            diff_ext <= (others => '0');
            data_out <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                diff_ext <= resize(signed(delayed_skew(G_LATENCY_SKEW)), G_DATA_WIDTH + 2)
                    - resize(signed(baseline_held), G_DATA_WIDTH + 2);
                -- truncate back to 15-bit signed output
                data_out <= std_logic_vector(resize(diff_ext, G_DATA_WIDTH + 1));
            end if;
        end if;
    end process p_restore;

    ----------------------------------------------------------------------------
    -- Overflow error
    ----------------------------------------------------------------------------

    p_oflow : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            error_oflow <= '0';
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                if (diff_ext(G_DATA_WIDTH + 1) /= diff_ext(G_DATA_WIDTH)) then
                    error_oflow <= '1';
                end if;
            end if;
        end if;
    end process p_oflow;

end architecture rtl;