--==============================================================================
--  Module:        pileup_detection.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       30/07/2026
--  Last Modified: 30/07/2026
--
--  Description:
--  Module that asserts valid flag if the current pulse is not affected by incoming pulses.
--
--  Dependencies:
--  none
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity pileup_detection is
    generic (
        -- jordanov trapezoid parameters
        G_JORD_K_WIDTH : natural range 2 to 8 := 6; -- Width of trapezoid rising edge
        G_JORD_M_WIDTH : natural range 2 to 8 := 8; -- Width of trapezoid flat top
        -- real trapezoidal guards
        G_END_PULSE_GUARD : natural range 0 to 128 := 40 -- N of samples to assert later the end of the pulse
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
        PULSE_TRIG_I : in std_logic; -- Trigger of pulse detection
        PULSE_END_I  : in std_logic; -- Trigger of pulse end
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        PULSE_VALID_O : out std_logic -- Trigger of valid pulse
    );
end entity pileup_detection;

architecture rtl of pileup_detection is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- Need trapezoid size and its margin to know the total duration of pulse
    constant C_RISE_DELAY      : natural := 2 ** G_JORD_K_WIDTH;                                 -- duration of trapezoid rise
    constant C_FLAT_DELAY      : natural := 2 ** G_JORD_M_WIDTH;                                 -- duration of trapezoid top
    constant C_END_PULSE_DEPTH : natural := 2 * C_RISE_DELAY + C_FLAT_DELAY + G_END_PULSE_GUARD; -- duration of trapezoid + end guard

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output signal
    signal pulse_valid : std_logic;

    -- cycles left of the last triggered window
    signal cnt_end_pulse : natural range 0 to C_END_PULSE_DEPTH;

    -- a pulse is being processed
    signal pulse_ongoing : std_logic;

    -- pulse hit by another trigger
    signal pileup : std_logic;

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output Assignments
    ----------------------------------------------------------------------------

    PULSE_VALID_O <= pulse_valid;

    ----------------------------------------------------------------------------
    -- Main Combinatory Processes
    ----------------------------------------------------------------------------

    -- if counter moves, there is a pulse
    pulse_ongoing <= '0' when (cnt_end_pulse = 0) else
        '1';

    -- valid conditions
    pulse_valid <= PULSE_END_I and not pulse_ongoing and not pileup;

    ----------------------------------------------------------------------------
    -- Main Sequential Processes
    ----------------------------------------------------------------------------

    -- starts cnt when a pulse trigger has been asserted
    p_cnt : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            cnt_end_pulse <= 0;
        elsif rising_edge(CLK_I) then
            if (PULSE_TRIG_I = '1') then
                cnt_end_pulse <= C_END_PULSE_DEPTH - 1;
            elsif (cnt_end_pulse /= 0) then
                cnt_end_pulse <= cnt_end_pulse - 1;
            end if;
        end if;
    end process p_cnt;

    -- asserts pileup if pulse trigger is incoming and the counter is active (current pulse pulse_ongoing)
    p_pileup : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            pileup <= '0';
        elsif rising_edge(CLK_I) then
            if (PULSE_TRIG_I = '1') then
                pileup <= pulse_ongoing;
            end if;
        end if;
    end process p_pileup;

end architecture rtl;