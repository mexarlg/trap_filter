--==============================================================================
--  Module:        pulse_capture.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       03/08/2026
--  Last Modified:
--
--  Description:
--  Module that captures the amplitude of the filtered output given a trigger on the mid-flat point.
--
--  Dependencies:
--  trap_filter_pkg.vhd
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity pulse_capture is
    generic (
        -- Data parameters
        G_DATA_WIDTH : natural range 8 to 16 := 15 -- Width of input data
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
        TRIG_CAPTURE_I : in std_logic;                                   -- Trigger to capture amplitude at middle of flat
        DATA_I         : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Input (filtered) data
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        DATA_O : out std_logic_vector(G_DATA_WIDTH - 1 downto 0) -- Captured data amplitude at the middle of the top
    );
end entity pulse_capture;

architecture rtl of pulse_capture is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output signals
    signal data : std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- pulse amplitude latched

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output Assignments
    ----------------------------------------------------------------------------

    DATA_O <= data;

    ----------------------------------------------------------------------------
    -- Main Combinatory Processes
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Main Sequential Processes
    ----------------------------------------------------------------------------

    -- latches amplitude if trigger
    p_capture : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            data <= (others => '0');
        elsif rising_edge(CLK_I) then
            -- latch data if trigger is issued
            if (TRIG_CAPTURE_I = '1') then
                data <= DATA_I;
            end if;
        end if;
    end process p_capture;

end architecture rtl;