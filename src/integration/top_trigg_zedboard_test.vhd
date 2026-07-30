--==============================================================================
--  Module:        top_trigg_zedboard_test.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       27/07/2026
--  Last Modified: 
--
--  Description:
--  top wrapper for trigg_subsystem with vio instantiation for Digilent Zedboard
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

entity top_trigg_zedboard_test is
    generic (
        -- Data parameters
        G_DATA_WIDTH         : natural range 8 to 16 := 14; -- Width of incoming data stream (ADC Magnitude resolution)
        G_PULSE_SAMPLE_WIDTH : natural range 8 to 16 := 10
    );
    port (
        ------------------------------------------------------------------------
        -- Clock / Reset
        ------------------------------------------------------------------------
        CLK_I   : in std_logic;
        BTN_RST : in std_logic
    );
end entity top_trigg_zedboard_test;

architecture rtl of top_trigg_zedboard_test is

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

    -- connection signals
    signal data_i : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal rst_n  : std_logic;
    signal ce_vio : std_logic_vector(0 downto 0);
    signal ce_i   : std_logic;

    -- output signals
    signal trigger_o     : std_logic_vector(4 downto 0);
    signal error_oflow_o : std_logic_vector(3 downto 0);

    -- Mark as debug for ILA
    attribute mark_debug                  : string;
    attribute mark_debug of ce_i          : signal is "true";
    attribute mark_debug of data_i        : signal is "true";
    attribute mark_debug of trigger_o     : signal is "true";
    attribute mark_debug of error_oflow_o : signal is "true";

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
    trap_i : entity trap_filter.trig_subsystem
        generic map(
            -- Jordanov parameters
            G_DATA_WIDTH => G_DATA_WIDTH
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
            DATA_I => data_i,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            TRIGGER_O     => trigger_o,
            error_oflow_o => error_oflow_o
        );

end architecture rtl;