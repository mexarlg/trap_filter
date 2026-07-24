--==============================================================================
--  Module:        delay_unit_sr.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       09/07/2026
--  Last Modified: 
--
--  Description:
--  Delay unit that implements shift register logic for the mov_avg_filter delay.
--  Free running so data shifts every clock cycle. Validity is tracked externally.
--  With G_REG_INPUT = 1 the total delay is G_DELAY_VALUE + 1 cycles.
--  With G_REG_INPUT = 0 the total delay is G_DELAY_VALUE cycles.
--
--  Dependencies:
--  Data fed sync with CLK_I
-- 
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity delay_unit_sr is
    generic (
        G_DATA_WIDTH  : natural range 4 to 16   := 14; -- Width of incoming data stream (ADC Magnitude resolution)
        G_DELAY_VALUE : natural range 4 to 4096 := 8;  -- Value of actual delayed (10 bit max width)
        G_REG_INPUT   : natural range 0 to 1    := 1   -- Register input (1) for standalone or first link, pass through (0) when chained
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
        DATA_I : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Input data sync with CLK
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        DATA_D_O : out std_logic_vector(G_DATA_WIDTH - 1 downto 0) -- Delayed Data for sample N
    );
end entity delay_unit_sr;

architecture rtl of delay_unit_sr is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- shift register array
    type sr_t is array (0 to G_DELAY_VALUE - 1) of std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal sr : sr_t := (others => (others => '0'));

    -- shift register data input
    signal data_n : std_logic_vector(G_DATA_WIDTH - 1 downto 0);

    -- Output signals
    signal data_d : std_logic_vector(G_DATA_WIDTH - 1 downto 0);

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    DATA_D_O <= data_d;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    -- shift register last tap (data_d)
    data_d <= sr(G_DELAY_VALUE - 1);

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    -- shift register inferred for delay
    p_sr : process (CLK_I)
    begin
        if rising_edge(CLK_I) then
            sr <= data_n & sr(0 to G_DELAY_VALUE - 2);
        end if;
    end process p_sr;

    g_reg_in : if G_REG_INPUT = 1 generate

        -- registers input data
        p_reg : process (CLK_I, RST_N_I)
        begin
            if (RST_N_I = '0') then
                data_n <= (others => '0');
            elsif rising_edge(CLK_I) then
                data_n <= DATA_I;
            end if;
        end process p_reg;

    end generate g_reg_in;

    g_no_reg_in : if G_REG_INPUT = 0 generate

        data_n <= DATA_I;

    end generate g_no_reg_in;

end architecture rtl;