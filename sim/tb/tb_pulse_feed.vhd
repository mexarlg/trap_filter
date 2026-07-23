--==============================================================================
--  Testbench:     tb_pulse_feed
--  Description:   Testbench for delay_unit_sr
--  Author:        Aldo Lupio
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;
use trap_filter.pulse_data_pkg.all;

entity tb_pulse_feed is
end entity;

architecture tb of tb_pulse_feed is

    ----------------------------------------------------------------------------
    -- Test configuration
    ----------------------------------------------------------------------------

    -- 125 Mhz
    constant CLK_PERIOD : time := 8 ns;

    -- Moving average configuration
    constant C_ADC_WIDTH   : natural := 14; -- Bit width of adc data
    constant C_PULSE_WIDTH : natural := 10; -- Bit width of N samples

    ----------------------------------------------------------------------------    
    -- DUT Signals
    ----------------------------------------------------------------------------

    -- clk / rst_n
    signal tb_clk   : std_logic := '0';
    signal tb_rst_n : std_logic := '0';

    -- tb signals of dut
    signal tb_ce         : std_logic                                  := '0';
    signal tb_data       : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');
    signal tb_data_valid : std_logic                                  := '0';

begin

    ----------------------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------------------

    tb_clk <= not tb_clk after CLK_PERIOD/2;

    ----------------------------------------------------------------------------
    -- DUT Instantiation
    ----------------------------------------------------------------------------

    dut : entity trap_filter.pulse_feed
        generic map(
            G_DATA_WIDTH  => C_ADC_WIDTH,
            G_PULSE_WIDTH => C_PULSE_WIDTH
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
            DATA_O       => tb_data,
            DATA_VALID_O => tb_data_valid
        );

    ----------------------------------------------------------------------------
    -- Stimulus: reset, enable, then stream samples
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

        ------------------------------------------------------------------------
        -- Simulation done
        ------------------------------------------------------------------------

        wait for 9000 ns;
        assert false report "Simulation finished" severity failure;
        wait;
    end process p_stimulus;

end architecture tb;