--==============================================================================
--  Module:        top_trap_zedboard_test.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       17/07/2026
--  Last Modified: 
--
--  Description:
--  top wrapper for trap_subsystem with vio instantiation for Digilent Zedboard
--  ila signals are marked as debug
--
--  Dependencies:
-- 
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity top_trap_zedboard_test is
    generic (
        -- Data parameters
        G_DATA_WIDTH         : natural range 8 to 16 := 14; -- Width of incoming data stream (ADC Magnitude resolution)
        G_PULSE_SAMPLE_WIDTH : natural range 8 to 16 := 10; -- Width of memory needed to store incoming data stream (1048 samples -> 10 bits)
        -- Jordanov params
        G_JORD_K_WIDTH          : natural range 2 to 8     := 6;     -- Width of delay needed for rising time
        G_JORD_M_WIDTH          : natural range 2 to 8     := 8;     -- Width of delay needed for flat top
        G_JORD_M_EXP_VALUE      : natural range 0 to 65535 := 39992; -- Width of decay exp factor (12 bits mag + 4 bits fraction)
        G_JORD_M_EXP_FRAC_WIDTH : natural range 1 to 4     := 4;     -- Width of decay exp factor for its fraction (4 bits)
        -- Jordanov fixed point params
        G_JORD_DIFF_MARGIN_BITS : natural range 1 to 3  := 3;  -- Width of margin given to the delayed difference of jordanov
        G_JORD_ACC1_MARGIN_BITS : natural range 1 to 2  := 2;  -- Width of margin given to the 1st accumulator of jordanov
        G_JORD_ACC2_MARGIN_BITS : natural range 0 to 1  := 1;  -- Width of margin given to the 2nd accumulator of jordanov
        G_JORD_OUT_SHIFT_BITS   : natural range 0 to 24 := 17; -- Number of bits that output will be shifted of jordanov
        -- Moving average params
        G_MOV_D_WIDTH         : natural range 2 to 8 := 4; -- Width of samples averaged of mov_avg
        G_MOV_ACC_MARGIN_BITS : natural range 2 to 5 := 2; -- Margin bits given to the accumulator of mov_avg
        -- Pulse detection delay params
        G_PULSE_DELAY_WIDTH : natural range 4 to 6 := 5 -- Width of delay given from pulse detection subsystem
    );
    port (
        ------------------------------------------------------------------------
        -- Clock / Reset
        ------------------------------------------------------------------------
        CLK_I   : in std_logic;
        BTN_RST : in std_logic
    );
end entity top_trap_zedboard_test;

architecture rtl of top_trap_zedboard_test is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    -- Virtual input output to assert internal CE
    component vio_trap is
        port (
            clk        : in std_logic;
            probe_out0 : out std_logic_vector(0 downto 0) -- spare / soft start
        );
    end component vio_trap;

    -- To make sure VIO is found at default library (we are in trap_filter)
    for u_vio : vio_trap use entity xil_defaultlib.vio_trap;

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output signals
    signal data_filtered_o       : std_logic_vector(G_DATA_WIDTH downto 0); -- Trapezoidal output (signed)
    signal data_filtered_valid_o : std_logic;                               -- Trapezoidal valid
    signal stat_error_o          : std_logic_vector(5 downto 0);            -- error status

    -- connection signals
    signal data_i : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal rst_n  : std_logic;
    signal ce_vio : std_logic_vector(0 downto 0);
    signal ce_i   : std_logic;

    -- Mark as debug for ILA
    attribute mark_debug                          : string;
    attribute mark_debug of ce_i                  : signal is "true";
    attribute mark_debug of data_i                : signal is "true";
    attribute mark_debug of data_filtered_o       : signal is "true";
    attribute mark_debug of data_filtered_valid_o : signal is "true";
    attribute mark_debug of stat_error_o          : signal is "true";

begin

    -- VIO
    ce_i <= ce_vio(0);

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

    -- Button is active high, rst_n is active low
    rst_n <= not BTN_RST;

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    -- feeds stored pulse to trap_subsystem
    pulse_feed_i : entity trap_filter.pulse_feed
        generic map(
            G_DATA_WIDTH  => G_DATA_WIDTH,
            G_PULSE_WIDTH => G_PULSE_SAMPLE_WIDTH
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
            CE_I         => ce_i,
            DATA_O       => data_i,
            DATA_VALID_O => open
        );

    -- trap_subsystem instantiation
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
            CE_I            => ce_i,
            DATA_I          => data_i,
            BASELINE_TRIG_I => '0',
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            data_filtered_o       => data_filtered_o,
            data_filtered_valid_o => data_filtered_valid_o,
            stat_error_o          => stat_error_o
        );

end architecture rtl;