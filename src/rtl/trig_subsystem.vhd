--==============================================================================
--  Module:        trig_subsystem.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       17/07/2026
--  Last Modified: 
--
--  Description:
--  Module that detects an incoming pulse and asserts the internal phases in a pulse.
--
--  Dependencies:
-- 
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity trig_subsystem is
    generic (
        -- Data parameters
        G_DATA_WIDTH : natural range 8 to 16 := 14;
        -- Slow jordanov contants
        G_SLOW_JORD_K : natural range 2 to 8 := 6;
        G_SLOW_JORD_M : natural range 2 to 8 := 8;
        -- cfd tuning parameters
        G_CFD_VAL_TH        : natural range 1024 to 4096 := 2048;
        G_CFD_SLOPE_TH      : natural range 50 to 500    := 100;
        G_CFD_TIMEOUT_WIDTH : natural range 5 to 10      := 7
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
        DATA_I : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- input data stream
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        TRIGGER_O     : out std_logic_vector(4 downto 0);
        PULSE_VALID_O : out std_logic;
        ERROR_OFLOW_O : out std_logic_vector(3 downto 0) -- error status
    );
end entity trig_subsystem;

architecture rtl of trig_subsystem is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- pulse detection fixed delays
    constant C_TRIG_TO_BASELINE  : natural := 4;
    constant C_TRIG_TO_START     : natural := 30;
    constant C_START_PULSE_GUARD : natural := 1;
    constant C_END_PULSE_GUARD   : natural := 40;

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- intermidiate signals
    signal trigger     : std_logic_vector(4 downto 0); -- pulse stages trigger
    signal pulse_trig  : std_logic;                    -- pulse detected trigger
    signal pulse_valid : std_logic;                    -- pulse valid trigger

    -- output signals
    signal error_oflow : std_logic_vector(3 downto 0); -- error status

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    TRIGGER_O     <= trigger;
    PULSE_VALID_O <= pulse_valid;
    ERROR_OFLOW_O <= error_oflow;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    pulse_detect_i : entity trap_filter.pulse_detection
        generic map(
            -- Jordanov parameters
            G_DATA_WIDTH => G_DATA_WIDTH,
            -- Cfd tuning parameters
            G_CFD_VAL_TH        => G_CFD_VAL_TH,
            G_CFD_SLOPE_TH      => G_CFD_SLOPE_TH,
            G_CFD_TIMEOUT_WIDTH => G_CFD_TIMEOUT_WIDTH
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => CLK_I,
            RST_N_I => RST_N_I,
            ------------------------------------------------------------------------
            -- Control Inputs
            ------------------------------------------------------------------------
            DATA_I => DATA_I,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            PULSE_TRIG_O  => pulse_trig,
            ERROR_OFLOW_O => error_oflow
        );

    -- asserts the triggers for the stages of the pulse
    trig_gen_i : entity trap_filter.trig_gen
        generic map(
            G_TRIG_TO_BASELINE  => C_TRIG_TO_BASELINE,
            G_TRIG_TO_START     => C_TRIG_TO_START,
            G_JORD_K_WIDTH      => G_SLOW_JORD_K,
            G_JORD_M_WIDTH      => G_SLOW_JORD_M,
            G_START_PULSE_GUARD => C_START_PULSE_GUARD,
            G_END_PULSE_GUARD   => C_END_PULSE_GUARD
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

    --  pileup discrimination
    pileup_detect_i : entity trap_filter.pileup_detection
        generic map(
            G_JORD_K_WIDTH    => G_SLOW_JORD_K,
            G_JORD_M_WIDTH    => G_SLOW_JORD_M,
            G_END_PULSE_GUARD => C_END_PULSE_GUARD
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
            PULSE_END_I  => trigger(0),
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            PULSE_VALID_O => pulse_valid
        );

end architecture rtl;