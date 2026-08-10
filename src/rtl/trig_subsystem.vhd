--==============================================================================
--  Module:        trig_subsystem.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       17/07/2026
--  Last Modified: 
--
--  Description:
--  Module that detects an incoming pulse and asserts the internal phases of the filtered pulse.
--  The triggers allow the capture of the baseline, the amplitude and the discrimination of pileups.
--
--  Dependencies:
--  trap_filter_pkg.vhd, shift_register.vhd, cfd.vhd, trig_gen.vhd, pulse_detection.vhd,
--  pileup_detection.vhd, delay_module.vhd, jordanov_filter.vhd
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity trig_subsystem is
    generic (
        -- Data parameters
        G_DATA_WIDTH : natural range 8 to 16 := 14; -- Width of streamed input data (adc)
        -- Slow jordanov parameters
        G_SLOW_M_EXP_VALUE : natural range 0 to 65535 := 39992; -- Value of the decay exp coefficient (12 bits mag + 4 bits fraction)
        G_SLOW_JORD_K      : natural range 2 to 8     := 6;     -- Width of delay for rising edge of slow trapezoid for trigger timing
        G_SLOW_JORD_M      : natural range 2 to 8     := 8;     -- Width of delay for flat top of slow trapezoid for trigger timing
        -- pulse detection tuning parameters
        G_CFD_VAL_TH   : natural range 1024 to 4096 := 2048; -- Threshold level of the fast jordanov output to gate pulse detection
        G_CFD_SLOPE_TH : natural range 50 to 500    := 100;  -- Threshold slope of the fast jordanov output to gate pulse detection
        -- pulse and pileup parameters
        G_PILEUP_DECAY_VALUE : natural range 255 to 65535 := 4095; -- Value in N samples of the pulse decay time constant
        G_PILEUP_CNT_WIDTH   : natural range 7 to 12      := 12    -- Width of counter for pileup events
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
        DATA_I : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Input data stream from ADC
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        PULSE_TRIGGERS_O : out std_logic_vector(C_TRIG_DEPTH downto 0);           -- Triggers of filtered pulse at each stage (baseline, start, top, mid-top, end)
        PULSE_CLEAN_O    : out std_logic;                                         -- Filtered pulse is valid (no pilepus, asserted after end of pulse)
        PILEUP_EVENT_O   : out std_logic;                                         -- Pileup event flag
        PILEUP_CNT_O     : out std_logic_vector(G_PILEUP_CNT_WIDTH - 1 downto 0); -- Pileup event counter
        ERROR_OFLOW_O    : out std_logic_vector(3 downto 0)                       -- Overflow error status of trig_subsystem
    );
end entity trig_subsystem;

architecture rtl of trig_subsystem is

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

    -- output signals
    signal pulse_triggers : std_logic_vector(C_TRIG_DEPTH downto 0);           -- triggers of filtered pulse at each stage (baseline, start, top, mid-top, end)
    signal pulse_clean    : std_logic;                                         -- trigger that a filtered pulse is valid (no pileups, asserted after pulse ended)
    signal pileup_event   : std_logic;                                         -- pileup event pulse
    signal pileup_cnt     : std_logic_vector(G_PILEUP_CNT_WIDTH - 1 downto 0); -- counter of pileup events
    signal error_oflow    : std_logic_vector(3 downto 0);                      -- overflow error of trig_subsystem

    -- intermidiate signals
    signal trigger        : std_logic_vector(C_TRIG_DEPTH - 1 downto 0); -- triggers of filtered pulse at each stage (baseline, start, top, mid-top, end)
    signal pulse_trig     : std_logic;                                   -- trigger that a pulse has been detected
    signal pulse_end_trig : std_logic;                                   -- trigger at the end of a pulse

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    PULSE_TRIGGERS_O <= pulse_triggers;
    PULSE_CLEAN_O    <= pulse_clean;
    PILEUP_EVENT_O   <= pileup_event;
    PILEUP_CNT_O     <= pileup_cnt;
    ERROR_OFLOW_O    <= error_oflow;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    -- better readibility
    pulse_triggers <= pulse_trig & trigger;
    pulse_end_trig <= trigger(0);

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    -- Detects an incoming pulse
    pulse_detect_i : entity trap_filter.pulse_detection
        generic map(
            -- General parameters
            G_DATA_WIDTH => G_DATA_WIDTH,
            -- Slow jordanov parameters
            G_SLOW_M_EXP_VALUE => G_SLOW_M_EXP_VALUE,
            -- Cfd tuning parameters for pulse detection
            G_CFD_VAL_TH        => G_CFD_VAL_TH,
            G_CFD_SLOPE_TH      => G_CFD_SLOPE_TH,
            G_CFD_TIMEOUT_WIDTH => C_CFD_ZERO_TIMEOUT_WIDTH
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => CLK_I,
            RST_N_I => RST_N_I,
            ------------------------------------------------------------------------
            -- Inputs
            ------------------------------------------------------------------------
            DATA_I => DATA_I,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            PULSE_TRIG_O  => pulse_trig,
            ERROR_OFLOW_O => error_oflow
        );

    -- Asserts the triggers for each of the stages of the filtered pulse
    trig_gen_i : entity trap_filter.trig_gen
        generic map(
            -- Delays from pulse detected trigger to baseline and start of filtered pulse
            G_TRIG_DELAY_BASELINE => C_TRIG_DELAY_BASELINE,
            G_TRIG_DELAY_START    => C_TRIG_DELAY_START,
            -- Slow jordanov parameters for knowing the filtered pulse timing
            G_JORD_K_WIDTH => G_SLOW_JORD_K,
            G_JORD_M_WIDTH => G_SLOW_JORD_M
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => CLK_I,
            RST_N_I => RST_N_I,
            ------------------------------------------------------------------------
            -- Inputs
            ------------------------------------------------------------------------
            PULSE_TRIG_I => pulse_trig,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            TRIGGER_O => trigger
        );

    --  Asserts if a filtered pulse is valid regarding pileup discrimination
    pileup_detect_i : entity trap_filter.pileup_detection
        generic map(
            -- Pileup parameters
            G_PILEUP_DECAY_VALUE => G_PILEUP_DECAY_VALUE,
            G_PILEUP_CNT_WIDTH   => G_PILEUP_CNT_WIDTH
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => CLK_I,
            RST_N_I => RST_N_I,
            ------------------------------------------------------------------------
            -- Inputs
            ------------------------------------------------------------------------
            PULSE_TRIG_I     => pulse_trig,
            PULSE_END_TRIG_I => pulse_end_trig,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            PULSE_CLEAN_O  => pulse_clean,
            PILEUP_EVENT_O => pileup_event,
            PILEUP_CNT_O   => pileup_cnt
        );

end architecture rtl;