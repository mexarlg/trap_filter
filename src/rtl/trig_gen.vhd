--==============================================================================
--  Module:        trig_gen.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       30/07/2026
--  Last Modified: 30/07/2026
--
--  Description:
--  Module that takes the detected pulse trigger and issues triggers at specific
--  stages inside the pulse timeline. Asserted through a pipeline delay.
--  The stages are: Baseline, start of pulse, start of top, center of top, end of pulse.
--
--  Dependencies:
--  trap_filter_pkg.vhd
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity trig_gen is
    generic (
        -- delays from the pulse detected trigger to each stage
        G_TRIG_TO_BASELINE : natural range 2 to 128 := 4;  -- N of samples from trigger to baseline capture
        G_TRIG_TO_START    : natural range 4 to 256 := 30; -- N of samples from trigger to start of pulse
        -- jordanov trapezoid parameters
        G_JORD_K_WIDTH : natural range 2 to 8 := 6; -- Width of slow filtered trapezoid rising edge
        G_JORD_M_WIDTH : natural range 2 to 8 := 8; -- Width of slow filtered trapezoid flat top
        -- margins to decrease and increase the start/end triggers of the filtered pulse
        G_START_PULSE_GUARD : natural range 0 to 16  := 1; -- N of samples to assert earlier the start of the pulse
        G_END_PULSE_GUARD   : natural range 0 to 128 := 40 -- N of samples to assert later the end of the current pulse (pileup discrimination)
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
        PULSE_TRIG_I : in std_logic; -- Trigger of detected pulse
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        TRIGGER_O : out std_logic_vector(4 downto 0) -- Triggers at different stages of a pulse (baseline, start, top, mid-top, end)
    );
end entity trig_gen;

architecture rtl of trig_gen is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- trapezoid specific durations
    constant C_RISE_DELAY      : natural := 2 ** G_JORD_K_WIDTH; -- duration of trapezoid rise
    constant C_FLAT_DELAY      : natural := 2 ** G_JORD_M_WIDTH; -- duration of trapezoid top
    constant C_HALF_FLAT_DELAY : natural := C_FLAT_DELAY / 2;    -- duration of half the trapezoid top

    -- depth for each delay of PULSE_TRIG_I to assert each stage of the pulse
    constant C_BASELINE_DEPTH    : natural := G_TRIG_TO_BASELINE;
    constant C_START_PULSE_DEPTH : natural := G_TRIG_TO_START - G_START_PULSE_GUARD;
    constant C_START_FLAT_DEPTH  : natural := C_START_PULSE_DEPTH + C_RISE_DELAY;
    constant C_MID_FLAT_DEPTH    : natural := C_START_FLAT_DEPTH + C_HALF_FLAT_DELAY;
    constant C_END_PULSE_DEPTH   : natural := C_START_PULSE_DEPTH + 2 * C_RISE_DELAY + C_FLAT_DELAY + G_END_PULSE_GUARD;

    -- separation of baseline from rising edge of pulse
    constant C_BASE_TO_START : natural := C_START_PULSE_DEPTH - C_BASELINE_DEPTH;

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- trigger outputs
    signal trig_baseline    : std_logic;
    signal trig_start_pulse : std_logic;
    signal trig_start_flat  : std_logic;
    signal trig_mid_flat    : std_logic;
    signal trig_end_pulse   : std_logic;

    -- delay pipeline of triggers (longest stage)
    signal delay_line : std_logic_vector(0 to C_END_PULSE_DEPTH - 1);

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    -- baseline capture before start of pulse
    assert (G_TRIG_TO_START > G_TRIG_TO_BASELINE)
    report "trig_gen: G_TRIG_TO_START should be larger than G_TRIG_TO_BASELINE" severity failure;

    -- assert margin allows minimum depth of 2
    assert (G_TRIG_TO_START > G_START_PULSE_GUARD + 1)
    report "trig_gen: G_TRIG_TO_START should be + 2 larger than G_START_PULSE_GUARD" severity failure;

    -- baseline capture has enough margin before rising edge of pulse
    assert (C_BASE_TO_START > 8)
    report "trig_gen: Baseline capture too close to rising edge, decrease C_BASELINE_DEPTH" severity failure;

    ----------------------------------------------------------------------------
    -- Output Assignments
    ----------------------------------------------------------------------------

    TRIGGER_O(4) <= trig_baseline;
    TRIGGER_O(3) <= trig_start_pulse;
    TRIGGER_O(2) <= trig_start_flat;
    TRIGGER_O(1) <= trig_mid_flat;
    TRIGGER_O(0) <= trig_end_pulse;

    ----------------------------------------------------------------------------
    -- Main Combinatory Processes
    ----------------------------------------------------------------------------

    -- each stage of the filtered pulse (easier readibility)
    trig_baseline    <= delay_line(C_BASELINE_DEPTH - 1);
    trig_start_pulse <= delay_line(C_START_PULSE_DEPTH - 1);
    trig_start_flat  <= delay_line(C_START_FLAT_DEPTH - 1);
    trig_mid_flat    <= delay_line(C_MID_FLAT_DEPTH - 1);
    trig_end_pulse   <= delay_line(C_END_PULSE_DEPTH - 1);

    ----------------------------------------------------------------------------
    -- Main Sequential Processes
    ----------------------------------------------------------------------------

    -- delay pipeline for every stage
    p_delay : process (RST_N_I, CLK_I)
    begin
        if RST_N_I = '0' then
            delay_line <= (others => '0');
        elsif rising_edge(CLK_I) then
            delay_line(0)                    <= PULSE_TRIG_I;
            delay_line(1 to delay_line'high) <= delay_line(0 to delay_line'high - 1);
        end if;
    end process p_delay;

end architecture rtl;