--==============================================================================
--  Module:        trigg_subsystem.vhd
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

entity trigg_subsystem is
    generic (
        -- Data parameters
        G_DATA_WIDTH : natural range 8 to 16 := 14; -- Width of incoming data stream (ADC Magnitude resolution)
        -- Jordanov params
        G_JORD_K_WIDTH          : natural range 2 to 8     := 6;     -- Width of delay needed for rising time (all bits -> '1' for multiple of 2^N)
        G_JORD_M_WIDTH          : natural range 2 to 8     := 8;     -- Width of delay needed for flat top (all bits -> '1' for multiple of 2^N)
        G_JORD_M_EXP_VALUE      : natural range 0 to 65535 := 39992; -- Width of decay exp factor (big "M_exp", 12 bits mag + 4 bits fraction)
        G_JORD_M_EXP_FRAC_WIDTH : natural range 1 to 4     := 4;     -- Width of decay exp factor for its fraction (big "M_exp")
        -- Jordanov fixed point params
        G_JORD_DIFF_MARGIN_BITS : natural range 1 to 3  := 3; -- Width of margin given to the delayed difference
        G_JORD_ACC1_MARGIN_BITS : natural range 1 to 2  := 2; -- Width of margin given to the 1st accumulator
        G_JORD_ACC2_MARGIN_BITS : natural range 0 to 1  := 1; -- Width of margin given to the 2nd accumulator
        G_JORD_OUT_SHIFT_BITS   : natural range 0 to 24 := 17 -- Width of margin given to the 2nd accumulator
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
        CE_I   : in std_logic;                                   -- clock enable
        DATA_I : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- input data stream
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        TRIGGER_O     : out std_logic_vector(3 downto 0);
        ERROR_OFLOW_O : out std_logic_vector(1 downto 0) -- error status
    );
end entity trigg_subsystem;

architecture rtl of trigg_subsystem is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- Delay values
    constant C_JORD_K_DELAY  : natural := 2 ** G_JORD_K_WIDTH;             -- k  = 2^K_RISE_WIDTH
    constant C_JORD_M_DELAY  : natural := 2 ** G_JORD_M_WIDTH;             -- m  = 2^M_FLAT_WIDTH
    constant C_JORD_L_DELAY  : natural := C_JORD_K_DELAY + C_JORD_M_DELAY; -- l  = k + m
    constant C_JORD_KL_DELAY : natural := C_JORD_K_DELAY + C_JORD_L_DELAY; -- k + l = 2k + m

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- intermidiate signals
    signal pulse_detected : std_logic; -- pulse detected flag

    -- output signals
    signal trigger     : std_logic_vector(3 downto 0); -- trigger outputs
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
            G_DATA_WIDTH   => G_DATA_WIDTH,
            G_JORD_K_WIDTH => G_JORD_K_WIDTH,
            -- Exponential decay
            G_JORD_M_EXP_VALUE      => G_JORD_M_EXP_VALUE,
            G_JORD_M_EXP_FRAC_WIDTH => G_JORD_M_EXP_FRAC_WIDTH,
            -- Fixed point params
            G_JORD_DIFF_MARGIN_BITS => G_JORD_DIFF_MARGIN_BITS,
            G_JORD_ACC1_MARGIN_BITS => G_JORD_ACC1_MARGIN_BITS,
            G_JORD_ACC2_MARGIN_BITS => G_JORD_ACC2_MARGIN_BITS,
            G_JORD_OUT_SHIFT_BITS   => G_JORD_OUT_SHIFT_BITS
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
            PULSE_DETECTED_O => pulse_detected,
            ERROR_OFLOW_O    => error_oflow
        );

end architecture rtl;