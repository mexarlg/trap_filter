--==============================================================================
--  Module:        delay_tracker.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       03/08/2026
--  Last Modified:
--
--  Description:
--  Module that issues a valid signal once the longest delay register has been completed.
--
--  Dependencies:
--  trap_filter_pkg.vhd
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity delay_tracker is
    generic (
        -- Slow jordanov trapezoid parameters
        G_SLOW_JORD_K_WIDTH : natural range 2 to 8 := 6; -- Width of slow filtered trapezoid rising edge
        G_SLOW_JORD_M_WIDTH : natural range 2 to 8 := 8  -- Width of slow filtered trapezoid flat top
    );
    port (
        ------------------------------------------------------------------------
        -- Clock / Reset
        ------------------------------------------------------------------------
        CLK_I   : in std_logic;
        RST_N_I : in std_logic;
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        VALID_DELAY_O : out std_logic -- Valid signal for delays
    );
end entity delay_tracker;

architecture rtl of delay_tracker is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- Delay values (most critical is kl)
    constant C_JORD_K_DELAY  : natural := 2 ** G_SLOW_JORD_K_WIDTH;        -- k  = 2^K_WIDTH
    constant C_JORD_M_DELAY  : natural := 2 ** G_SLOW_JORD_M_WIDTH;        -- m  = 2^M_WIDTH
    constant C_JORD_L_DELAY  : natural := C_JORD_K_DELAY + C_JORD_M_DELAY; -- l  = k + m
    constant C_JORD_KL_DELAY : natural := C_JORD_K_DELAY + C_JORD_L_DELAY; -- k + l = 2k + m

    -- counter limits
    constant C_CNT_WIDTH : natural                                    := 10;                                                          -- maximum possible width assumming both k and m as 8 bits width
    constant C_CNT_MAX   : std_logic_vector(C_CNT_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(C_JORD_KL_DELAY, C_CNT_WIDTH)); -- value of max delay in cnt width
    constant C_CNT_ONE   : std_logic_vector(C_CNT_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, C_CNT_WIDTH));               -- value of 1 in cnt width
    constant C_CNT_ZERO  : std_logic_vector(C_CNT_WIDTH - 1 downto 0) := (others => '0');                                             -- value of 0 in cnt width

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- Output signals
    signal valid_delay : std_logic;

    -- counter of maximum delay
    signal cnt_delay : std_logic_vector(C_CNT_WIDTH - 1 downto 0);

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output Assignments
    ----------------------------------------------------------------------------

    VALID_DELAY_O <= valid_delay;

    ----------------------------------------------------------------------------
    -- Main Combinatory Processes
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Main Sequential Processes
    ----------------------------------------------------------------------------

    -- counter for delay
    p_cnt : process (RST_N_I, CLK_I)
    begin
        if RST_N_I = '0' then
            cnt_delay <= C_CNT_ZERO;
        elsif rising_edge(CLK_I) then
            if (unsigned(cnt_delay) < unsigned(C_CNT_MAX)) then
                cnt_delay <= std_logic_vector(unsigned(cnt_delay) + unsigned(C_CNT_ONE));
            end if;
        end if;
    end process p_cnt;

    -- valid asserted when counter reaches delay
    p_valid : process (RST_N_I, CLK_I)
    begin
        if RST_N_I = '0' then
            valid_delay <= '0';
        elsif rising_edge(CLK_I) then
            if (cnt_delay = C_CNT_MAX) then
                valid_delay <= '1';
            end if;
        end if;
    end process p_valid;

end architecture rtl;