--==============================================================================
--  Module:        pulse_capture.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       03/08/2026
--  Last Modified:
--
--  Description:
--  Module that captures the amplitude of the filtered output given a trigger on the mid-flat point.
--  Depending if all elements are ready and no errors are found, the amplitude will be output with
--  a valid signal
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
        VALID_PILEUP_I : in std_logic;                                   -- Pulse is valid regarding pileup
        VALID_DELAY_I  : in std_logic;                                   -- Pulse is valid regarding delays
        ERROR_OFLOW_I  : in std_logic_vector(8 downto 0);                -- Overflow errors of trap/trig/peak subsystems
        TRIG_CAPTURE_I : in std_logic;                                   -- Trigger to capture amplitude at middle of flat
        DATA_I         : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Input (filtered) data
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        DATA_O  : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Captured data amplitude at the middle of the top
        VALID_O : out std_logic                                    -- Trigger that pulse is valid (pileup, delays, overflow)
    );
end entity pulse_capture;

architecture rtl of pulse_capture is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- state when no overflow error exists
    constant C_OFLOW_NO_ERROR : std_logic_vector(8 downto 0) := (others => '0');

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output signals
    signal valid : std_logic;                                   -- pulse is valid
    signal data  : std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- pulse amplitude latched

    -- intermidiate signals
    signal no_overflow : std_logic; -- no overflow from rest of subsystems

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output Assignments
    ----------------------------------------------------------------------------

    DATA_O  <= data;
    VALID_O <= valid;

    ----------------------------------------------------------------------------
    -- Main Combinatory Processes
    ----------------------------------------------------------------------------

    -- asserts data is not corrupted by overflow
    no_overflow <= '1' when (ERROR_OFLOW_I = C_OFLOW_NO_ERROR) else
        '0';

    -- valid if there is no pileup, delays are filled, and there is no overflow
    valid <= VALID_PILEUP_I and VALID_DELAY_I and no_overflow;

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