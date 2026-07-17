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
        G_DATA_WIDTH   : natural range 8 to 32 := 15; -- Signed width of both input streams and the output
        G_JORD_LATENCY : natural range 6 to 10 := 6;  -- Jordanov filter latency (in cycles)
        G_MOV_LATENCY  : natural range 2 to 4  := 2   -- Moving average (baseline) latency (in cycles)
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
        CE_I         : in std_logic;                                   -- clock enable
        DATA_JORD_I  : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Trapezoidal filtered stream (signed)
        BASELINE_I   : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Moving average baseline stream (signed)
        LATCH_TRIG_I : in std_logic;                                   -- Freeze baseline trigger
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        DATA_O        : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Baseline restored output (signed)
        ERROR_OFLOW_O : out std_logic                                    -- overflow flag
    );
end entity baseline_restorer;

architecture rtl of baseline_restorer is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- latency difference
    constant C_LATENCY_SKEW : natural := G_JORD_LATENCY - G_MOV_LATENCY;

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- Skew alignment delay line for the Jordanov stream
    type t_skew_arr is array (0 to C_LATENCY_SKEW) of std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal mov_skew : t_skew_arr;

    -- Latched baseline and substracted output
    signal baseline_held : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal diff_ext      : std_logic_vector(G_DATA_WIDTH downto 0);

    -- Output signals
    signal data_out    : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal error_oflow : std_logic;

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    DATA_O        <= data_out;
    ERROR_OFLOW_O <= error_oflow;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Latency alignment between both inputs
    ----------------------------------------------------------------------------

    p_skew : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            mov_skew <= (others => (others => '0'));
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                mov_skew(0) <= std_logic_vector(signed(BASELINE_I));
                for i in 1 to C_LATENCY_SKEW loop
                    mov_skew(i) <= mov_skew(i - 1);
                end loop;
            end if;
        end if;
    end process p_skew;

    ----------------------------------------------------------------------------
    -- Capture the baseline on trigger
    ----------------------------------------------------------------------------

    p_latch : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            baseline_held <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                if (LATCH_TRIG_I = '1') then
                    baseline_held <= std_logic_vector(signed(BASELINE_I));
                end if;
            end if;
        end if;
    end process p_latch;

    ----------------------------------------------------------------------------
    -- Subtract the baseline from the aligned Jordanov data
    ----------------------------------------------------------------------------

    p_restore : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            diff_ext <= (others => '0');
            data_out <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- substract with 1 margin bit 
                diff_ext <= std_logic_vector(resize(signed(mov_skew(C_LATENCY_SKEW)), G_DATA_WIDTH + 1)
                    - resize(signed(baseline_held), G_DATA_WIDTH + 1));
                -- truncate to output width
                data_out <= std_logic_vector(resize(signed(diff_ext), G_DATA_WIDTH));
            end if;
        end if;
    end process p_restore;

    ----------------------------------------------------------------------------
    -- Overflow error handling
    ----------------------------------------------------------------------------

    p_oflow : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            error_oflow <= '0';
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- result did not fit in G_DATA_WIDTH
                if (diff_ext(G_DATA_WIDTH) /= diff_ext(G_DATA_WIDTH - 1)) then
                    error_oflow <= '1';
                end if;
            end if;
        end if;
    end process p_oflow;

end architecture rtl;