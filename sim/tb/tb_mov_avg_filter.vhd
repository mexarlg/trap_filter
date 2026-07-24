--==============================================================================
--  Testbench:     tb_mov_avg_filter
--  Description:   Testbench for mov_avg_filter
--  Author:        Aldo Lupio
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;
use trap_filter.tb_mov_avg_filter_pkg.all;

entity tb_mov_avg_filter is
end entity;

architecture tb of tb_mov_avg_filter is

    ----------------------------------------------------------------------------
    -- Test configuration
    ----------------------------------------------------------------------------

    -- Moving average configuration
    constant C_DELAY_WIDTH     : natural := 6;                  -- Bit width of delay
    constant C_DELAY_VALUE     : natural := 2 ** C_DELAY_WIDTH; -- Value of delay
    constant C_ADC_WIDTH       : natural := 14;                 -- Bit width of adc (magnitude)
    constant C_ACC_MARGIN_BITS : natural := 2;                  -- Margin bits for accumulator signal (at worst case, 1MB holds 7 extra cycles, 2 MB holds 15 extra cycles)

    -- Sign configuration of input pulse -> Needs to be changed in waveform
    constant C_DATA_I_SIGNED : natural := 0; -- '1' if signed, '0' if unsigned

    ----------------------------------------------------------------------------    
    -- DUT Signals
    ----------------------------------------------------------------------------

    -- clk / rst_n
    signal tb_clk   : std_logic := '0';
    signal tb_rst_n : std_logic := '0';

    -- input signal to shift register
    signal tb_ce     : std_logic                                                    := '0';
    signal tb_data_i : std_logic_vector(C_ADC_WIDTH + C_DATA_I_SIGNED - 1 downto 0) := (others => '0');

    -- tb input signals of mov_avg_filter
    signal tb_data_d : std_logic_vector(C_ADC_WIDTH + C_DATA_I_SIGNED - 1 downto 0) := (others => '0');

    -- tb output signals of mov_avg_filter
    signal tb_data_filtered : std_logic_vector(C_ADC_WIDTH + C_DATA_I_SIGNED - 1 downto 0) := (others => '0');
    signal tb_error_oflow   : std_logic                                                    := '0';

begin

    ----------------------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------------------

    tb_clk <= not tb_clk after CLK_PERIOD/2;

    ----------------------------------------------------------------------------
    -- DUT Instantiation
    ----------------------------------------------------------------------------

    dut : entity trap_filter.mov_avg_filter
        generic map(
            G_DATA_WIDTH      => C_ADC_WIDTH,       -- Width of incoming data stream
            G_DELAY_WIDTH     => C_DELAY_WIDTH,     -- Width of delay signal (4b-> delay of 16 samples, 5b->32 and so on)
            G_ACC_MARGIN_BITS => C_ACC_MARGIN_BITS, -- Number of margin bits given to the accumulator
            G_DATA_I_SIGNED   => C_DATA_I_SIGNED    -- Data signed (1) or unsigned (0)
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
            CE_I     => tb_ce,
            DATA_N_I => tb_data_i,
            DATA_D_I => tb_data_d,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_FILTERED_O => tb_data_filtered,
            ERROR_OFLOW_O   => tb_error_oflow
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

    sr : entity trap_filter.delay_unit_sr
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

        wait for 9000 ns;

        ------------------------------------------------------------------------
        -- Simulation done
        ------------------------------------------------------------------------
        wait for 200 ns;
        assert false report "Simulation finished" severity failure;
        wait;
    end process p_stimulus;

end architecture tb;