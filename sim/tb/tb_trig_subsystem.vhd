--==============================================================================
--  Testbench:     tb_trig_subsystem
--  Description:   Testbench for mov_avg_filter
--  Author:        Aldo Lupio
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity tb_trig_subsystem is
end entity;

architecture tb of tb_trig_subsystem is

    ----------------------------------------------------------------------------
    -- Test configuration
    ----------------------------------------------------------------------------

    constant CLK_PERIOD : time := 8 ns;

    -- Jordanov params configuration
    constant C_ADC_WIDTH : natural := 14;

    ----------------------------------------------------------------------------    
    -- DUT Signals
    ----------------------------------------------------------------------------

    -- clk / rst_n
    signal tb_clk   : std_logic := '0';
    signal tb_rst_n : std_logic := '0';

    -- input signals
    signal tb_ce     : std_logic                                  := '0';
    signal tb_data_i : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');

    -- tb dut output signals
    signal tb_error_oflow : std_logic_vector(3 downto 0) := (others => '0');
    signal tb_trigger     : std_logic_vector(4 downto 0) := (others => '0');
    signal tb_pulse_valid : std_logic;

begin

    ----------------------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------------------

    tb_clk <= not tb_clk after CLK_PERIOD/2;

    ----------------------------------------------------------------------------
    -- DUT Instantiation
    ----------------------------------------------------------------------------

    pulse_feed_i : entity trap_filter.pulse_feed
        generic map(
            G_DATA_WIDTH  => C_ADC_WIDTH,
            G_PULSE_WIDTH => 12
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => tb_clk,
            RST_N_I => tb_rst_n,
            ------------------------------------------------------------------------
            -- Control Inputs / Outputs
            ------------------------------------------------------------------------
            CE_I         => tb_ce,
            DATA_O       => tb_data_i,
            DATA_VALID_O => open
        );

    dut : entity trap_filter.trig_subsystem
        generic map(
            G_DATA_WIDTH        => C_ADC_WIDTH,
            G_CFD_VAL_TH        => 2048,
            G_CFD_SLOPE_TH      => 100,
            G_CFD_TIMEOUT_WIDTH => 7
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => tb_clk,
            RST_N_I => tb_rst_n,
            ------------------------------------------------------------------------
            -- Control Inputs / Outputs
            ------------------------------------------------------------------------
            DATA_I        => tb_data_i,
            TRIGGER_O     => tb_trigger,
            PULSE_VALID_O => tb_pulse_valid,
            ERROR_OFLOW_O => tb_error_oflow
        );

    ----------------------------------------------------------------------------
    -- Stimulus: reset, enable, then stream samples from the file per clock.
    ----------------------------------------------------------------------------

    p_stimulus : process
    begin

        ------------------------------------------------------------------------
        -- Reset / CE
        ------------------------------------------------------------------------

        tb_ce    <= '0';
        tb_rst_n <= '0';
        wait for 50 ns;
        tb_rst_n <= '1';

        wait for 100 ns;
        wait until rising_edge(tb_clk);
        tb_ce <= '1';

        wait for 24000 ns;

        ------------------------------------------------------------------------
        -- Simulation done
        ------------------------------------------------------------------------

        tb_ce    <= '0';
        tb_rst_n <= '0';
        wait for 200 ns;

        assert false report "Simulation finished" severity failure;
        wait;
    end process p_stimulus;

end architecture tb;