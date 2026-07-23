--==============================================================================
--  Module:        trap_pulse_shaper_top.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       17/07/2026
--  Last Modified: 
--
--  Description:
--  top wrapper
--
--  Dependencies:
-- 
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity trap_pulse_shaper_top is
    generic (
        -- Data parameters
        G_DATA_WIDTH : natural range 8 to 16 := 14; -- Width of incoming data stream (ADC Magnitude resolution)
        -- Jordanov params
        G_JORD_K_WIDTH          : natural range 2 to 8     := 6;     -- Width of delay needed for rising time (all bits -> '1' for multiple of 2^N)
        G_JORD_M_WIDTH          : natural range 2 to 8     := 8;     -- Width of delay needed for flat top (all bits -> '1' for multiple of 2^N)
        G_JORD_M_EXP_VALUE      : natural range 0 to 65535 := 39992; -- Width of decay exp factor (big "M_exp", 12 bits mag + 4 bits fraction)
        G_JORD_M_EXP_FRAC_WIDTH : natural range 1 to 4     := 4;     -- Width of decay exp factor for its fraction (big "M_exp")
        -- Jordanov fixed point params
        G_JORD_DIFF_MARGIN_BITS : natural range 1 to 3  := 3;  -- Width of margin given to the delayed difference
        G_JORD_ACC1_MARGIN_BITS : natural range 1 to 2  := 2;  -- Width of margin given to the 1st accumulator
        G_JORD_ACC2_MARGIN_BITS : natural range 0 to 1  := 1;  -- Width of margin given to the 2nd accumulator
        G_JORD_OUT_SHIFT_BITS   : natural range 0 to 24 := 17; -- Width of margin given to the 2nd accumulator
        -- Moving average params
        G_MOV_D_WIDTH         : natural range 2 to 8 := 4; -- Width of samples averaged (all bits -> '1' for multiple of 2^N)
        G_MOV_ACC_MARGIN_BITS : natural range 2 to 5 := 2; -- Width of margin given to the accumulator
        -- Detection params
        G_PULSE_DELAY_WIDTH : natural range 4 to 6 := 5 -- Width of delay given from pulse detection subsystem
    );
    port (
        ------------------------------------------------------------------------
        -- Clock / Reset
        ------------------------------------------------------------------------
        CLK_I : in std_logic;
        BTN   : in std_logic
    );
end entity trap_pulse_shaper_top;

architecture rtl of trap_pulse_shaper_top is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- Width needed for N (1025) amount of samples of the input pulse
    constant C_PULSE_SAMPLES_WIDTH : natural := 10;

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    component vio_trap is
        port (
            clk        : in std_logic;
            probe_out0 : out std_logic_vector(0 downto 0) -- spare / soft start
        );
    end component vio_trap;

    for u_vio : vio_trap use entity xil_defaultlib.vio_trap;

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output signals
    signal data_filtered       : std_logic_vector(G_DATA_WIDTH downto 0); -- Trapezoidal output (signed)
    signal data_filtered_valid : std_logic;                               -- Trapezoidal valid
    signal stat_error          : std_logic_vector(5 downto 0);            -- error status

    -- intermidiate data after delays
    signal data_input : std_logic_vector(G_DATA_WIDTH - 1 downto 0);

    signal rst_n  : std_logic;
    signal ce_vio : std_logic_vector(0 downto 0);
    signal ce_int : std_logic;

    -- ILA
    attribute mark_debug                        : string;
    attribute mark_debug of data_input          : signal is "true";
    attribute mark_debug of data_filtered       : signal is "true";
    attribute mark_debug of data_filtered_valid : signal is "true";
    attribute mark_debug of stat_error          : signal is "true";
    attribute mark_debug of ce_int              : signal is "true";

begin

    ce_int <= ce_vio(0);

    u_vio : vio_trap
    port map(
        clk        => CLK_I,
        probe_out0 => ce_vio
    );

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------
    rst_n <= not BTN;
    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    pulse_feed_i : entity trap_filter.pulse_feed
        generic map(
            G_DATA_WIDTH  => G_DATA_WIDTH,
            G_PULSE_WIDTH => C_PULSE_SAMPLES_WIDTH
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => CLK_I,
            RST_N_I => rst_n,
            ------------------------------------------------------------------------
            -- Control Inputs / Outputs
            ------------------------------------------------------------------------
            CE_I         => ce_int,
            DATA_O       => data_input,
            DATA_VALID_O => open
        );

    trap_i : entity trap_filter.trap_subsystem
        generic map(
            -- Jordanov parameters
            G_DATA_WIDTH   => G_DATA_WIDTH,
            G_JORD_K_WIDTH => G_JORD_K_WIDTH,
            -- Exponential decay
            G_JORD_M_WIDTH          => G_JORD_M_WIDTH,
            G_JORD_M_EXP_VALUE      => G_JORD_M_EXP_VALUE,
            G_JORD_M_EXP_FRAC_WIDTH => G_JORD_M_EXP_FRAC_WIDTH,
            -- Fixed point params
            G_JORD_DIFF_MARGIN_BITS => G_JORD_DIFF_MARGIN_BITS,
            G_JORD_ACC1_MARGIN_BITS => G_JORD_ACC1_MARGIN_BITS,
            G_JORD_ACC2_MARGIN_BITS => G_JORD_ACC2_MARGIN_BITS,
            G_JORD_OUT_SHIFT_BITS   => G_JORD_OUT_SHIFT_BITS,
            G_MOV_D_WIDTH           => G_MOV_D_WIDTH,
            G_MOV_ACC_MARGIN_BITS   => G_MOV_ACC_MARGIN_BITS,
            G_PULSE_DELAY_WIDTH     => G_PULSE_DELAY_WIDTH
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => CLK_I,
            RST_N_I => rst_n,
            ------------------------------------------------------------------------
            -- Control Inputs
            ------------------------------------------------------------------------
            CE_I            => ce_int,
            DATA_I          => data_input,
            BASELINE_TRIG_I => '0',
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_FILTERED_O       => data_filtered,
            DATA_FILTERED_VALID_O => data_filtered_valid,
            STAT_ERROR_O          => stat_error
        );

end architecture rtl;