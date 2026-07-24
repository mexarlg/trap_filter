--==============================================================================
--  Testbench:     tb_delay_unit_sr
--  Description:   Testbench for delay_unit_sr
--  Author:        Aldo Lupio
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity tb_delay_unit_sr is
end entity;

architecture tb of tb_delay_unit_sr is

    ----------------------------------------------------------------------------
    -- Test configuration
    ----------------------------------------------------------------------------

    -- 125 Mhz
    constant CLK_PERIOD : time := 8 ns;

    -- Moving average configuration
    constant C_DELAY_WIDTH : natural := 3;                  -- Bit width of delay
    constant C_DELAY_VALUE : natural := 2 ** C_DELAY_WIDTH; -- Value of delay
    constant C_ADC_WIDTH   : natural := 14;                 -- Bit width of adc (magnitude)

    -- Sign configuration of input pulse -> Needs to be changed in waveform
    constant C_DATA_SIGNED : natural := 0; -- '1' if signed, '0' if unsigned

    ----------------------------------------------------------------------------    
    -- DUT Signals
    ----------------------------------------------------------------------------

    -- clk / rst_n
    signal tb_clk   : std_logic := '0';
    signal tb_rst_n : std_logic := '0';
    signal tb_ce    : std_logic := '0';

    -- tb signals of delay_unit_sr
    signal tb_data_i  : std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED - 1 downto 0) := (others => '0');
    signal tb_data_d  : std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED - 1 downto 0) := (others => '0');
    signal tb_data_d2 : std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED - 1 downto 0) := (others => '0');

begin

    ----------------------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------------------

    tb_clk <= not tb_clk after CLK_PERIOD/2;

    ----------------------------------------------------------------------------
    -- DUT Instantiation
    ----------------------------------------------------------------------------

    -- input not reg
    dut : entity trap_filter.delay_unit_sr
        generic map(
            G_DATA_WIDTH  => C_ADC_WIDTH,
            G_DELAY_VALUE => C_DELAY_VALUE,
            G_REG_INPUT   => 0
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => tb_clk,
            RST_N_I => tb_rst_n,
            ------------------------------------------------------------------------
            -- Control Inputs
            ------------------------------------------------------------------------
            DATA_I => tb_data_i,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_D_O => tb_data_d
        );

    -- input reg
    dut2 : entity trap_filter.delay_unit_sr
        generic map(
            G_DATA_WIDTH  => C_ADC_WIDTH,
            G_DELAY_VALUE => C_DELAY_VALUE,
            G_REG_INPUT   => 1
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => tb_clk,
            RST_N_I => tb_rst_n,
            ------------------------------------------------------------------------
            -- Control Inputs
            ------------------------------------------------------------------------
            DATA_I => tb_data_i,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_D_O => tb_data_d2
        );

    pulse_feed_i : entity trap_filter.pulse_feed
        generic map(
            G_DATA_WIDTH  => C_ADC_WIDTH,
            G_PULSE_WIDTH => 10
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

    ----------------------------------------------------------------------------
    -- Stimulus: reset, enable, then stream samples
    ----------------------------------------------------------------------------

    p_stimulus : process
    begin

        ------------------------------------------------------------------------
        -- Reset / CE
        ------------------------------------------------------------------------

        tb_rst_n <= '0';
        wait for 50 ns;
        tb_ce    <= '1';
        tb_rst_n <= '1';

        wait for 9000 ns;

        ------------------------------------------------------------------------
        -- Simulation done
        ------------------------------------------------------------------------
        wait for 200 ns;
        assert false report "Simulation finished" severity failure;
        wait;
    end process p_stimulus;

end architecture tb;