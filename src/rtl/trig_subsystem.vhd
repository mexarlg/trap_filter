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

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- intermidiate signals
    signal trigger    : std_logic_vector(4 downto 0); -- pulse stages trigger
    signal pulse_trig : std_logic;                    -- pulse detected trigger

    -- output signals
    signal error_oflow : std_logic_vector(3 downto 0); -- error status

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    ERROR_OFLOW_O <= error_oflow;
    TRIGGER_O     <= trigger;

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

    trig_gen_i : entity trap_filter.trig_gen
        generic map(
            G_TRIG_TO_BASELINE  => 4,
            G_TRIG_TO_START     => 22,
            G_JORD_K_WIDTH      => 6,
            G_JORD_M_WIDTH      => 8,
            G_START_PULSE_GUARD => 2,
            G_END_PULSE_GUARD   => 16
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

end architecture rtl;