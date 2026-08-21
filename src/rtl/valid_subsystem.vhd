--==============================================================================
--  Module:        valid_subsystem.vhd
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

entity valid_subsystem is
    generic (
        -- Pulse detection common delay
        G_DETECTION_DELAY : natural range 64 to 256 := 64;
        -- Slow jordanov delay
        G_SLOW_JORD_K_DELAY : natural range 16 to 256 := 256; -- Value of slow filtered trapezoid rising edge
        G_SLOW_JORD_M_DELAY : natural range 16 to 256 := 256; -- Value of slow filtered trapezoid flat top
        G_SLOW_JORD_LATENCY : natural range 8 to 9    := 8    -- Latency of jordanov filter

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
        TRIG_LOG_EVENT_I        : in std_logic;                                         -- Trigger to log pulse event
        PULSE_AMPLITUDE_CLEAN_I : in std_logic;                                         -- Trigger if pulse amplitude is clean
        PULSE_T_RISE_CLEAN_I    : in std_logic;                                         -- Trigger if risetime is clean
        ERROR_OFLOW_I           : in std_logic_vector(C_OVERFLOW_FLAGS_DEPTH downto 0); -- Overflow errors of trap/trig/peak subsystems
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        PULSE_STATE_O : out std_logic_vector(2 downto 0) -- Pulse state (All data valid, amplitude valid, rise time valid)
    );
end entity valid_subsystem;

architecture rtl of valid_subsystem is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- Total delay for jordanov algorithm 
    constant C_SLOW_JORD_L_DELAY  : natural := G_SLOW_JORD_K_DELAY + G_SLOW_JORD_M_DELAY; -- l  = k + m
    constant C_SLOW_JORD_KL_DELAY : natural := G_SLOW_JORD_K_DELAY + C_SLOW_JORD_L_DELAY; -- k + l = 2k + m

    -- Margin cycles for any extra latency for redundancy
    constant C_MARGIN_DELAY : natural := 30;

    -- Total delay until a pulse is valid (Filling of slow jordanov shift regs + delay of detection system + 1 trapezoid of valid signal latency + 1 pileup decay for sudden offset pulse)
    constant C_TOTAL_DELAY : natural := 2 * C_SLOW_JORD_KL_DELAY + G_DETECTION_DELAY + G_SLOW_JORD_LATENCY + C_MARGIN_DELAY;

    -- Counter limits
    constant C_CNT_WIDTH : natural                                    := f_value_to_width(C_TOTAL_DELAY);                           -- maximum possible width assumming both k and m as 8 bits width
    constant C_CNT_MAX   : std_logic_vector(C_CNT_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(C_TOTAL_DELAY, C_CNT_WIDTH)); -- value of max delay in cnt width
    constant C_CNT_ONE   : std_logic_vector(C_CNT_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, C_CNT_WIDTH));             -- value of 1 in cnt width

    -- State when no overflow error exists
    constant C_OFLOW_NO_ERROR : std_logic_vector(C_OVERFLOW_FLAGS_DEPTH downto 0) := (others => '0');

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- Output signals
    signal pulse_amplitude_valid : std_logic;
    signal pulse_t_rise_valid    : std_logic;
    signal pulse_state           : std_logic_vector(2 downto 0);

    -- Intermidiate signals
    signal cnt_delay    : std_logic_vector(C_CNT_WIDTH - 1 downto 0); -- counter of maximum delay
    signal delays_ready : std_logic;                                  -- most critical (longest) delay pipeline filled
    signal overflow     : std_logic;                                  -- no overflow from rest of subsystems

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output Assignments
    ----------------------------------------------------------------------------

    PULSE_STATE_O <= pulse_state;

    ----------------------------------------------------------------------------
    -- Main Combinatory Processes
    ----------------------------------------------------------------------------

    -- asserts data is not corrupted by overflow
    overflow <= '0' when (ERROR_OFLOW_I = C_OFLOW_NO_ERROR) else
        '1';

    -- amplitude valid if there is no pileup, delays are filled, and there is no overflow
    pulse_amplitude_valid <= PULSE_AMPLITUDE_CLEAN_I and delays_ready and not overflow;

    -- valid if there is time rise count is unaffected by timeout and amplitude is clean
    pulse_t_rise_valid <= PULSE_T_RISE_CLEAN_I and pulse_amplitude_valid;

    ----------------------------------------------------------------------------
    -- Main Sequential Processes
    ----------------------------------------------------------------------------

    -- counter for delay
    p_cnt : process (RST_N_I, CLK_I)
    begin
        if RST_N_I = '0' then
            cnt_delay <= (others => '0');
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
            delays_ready <= '0';
        elsif rising_edge(CLK_I) then
            if (cnt_delay = C_CNT_MAX) then
                delays_ready <= '1';
            end if;
        end if;
    end process p_valid;

    -- state of pulse
    p_state : process (RST_N_I, CLK_I)
    begin
        if RST_N_I = '0' then
            pulse_state <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (TRIG_LOG_EVENT_I = '1') then
                pulse_state(2) <= pulse_amplitude_valid and pulse_t_rise_valid;
                pulse_state(1) <= pulse_amplitude_valid;
                pulse_state(0) <= pulse_t_rise_valid;
            end if;
        end if;
    end process p_state;

end architecture rtl;