--==============================================================================
--  Testbench:     tb_trap_subsystem
--  Description:   Testbench for mov_avg_filter
--  Author:        Aldo Lupio
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity tb_trap_subsystem is
end entity;

architecture tb of tb_trap_subsystem is

    ----------------------------------------------------------------------------
    -- Test configuration
    ----------------------------------------------------------------------------

    constant CLK_PERIOD : time := 8 ns;

    -- Jordanov params configuration
    constant C_ADC_WIDTH           : natural := 14;
    constant C_JORD_K_WIDTH        : natural := 6;  -- k  = 2^K_RISE_WIDTH
    constant C_JORD_M_WIDTH        : natural := 7;  -- m  = 2^M_FLAT_WIDTH
    constant C_JORD_OUT_SHIFT_BITS : natural := 17; -- m  = 2^M_FLAT_WIDTH
    constant C_MOV_D_WIDTH         : natural := 4;  -- d  = 2^C_DELAY_WIDTH
    constant C_PULSE_DELAY_WIDTH   : natural := 4;  -- d  = 2^C_PULSE_DELAY_WIDTH

    -- Exp decay
    constant C_M_EXP_VALUE : natural := 39992; -- round(2499.5 * 2^4), M_FRAC = 4

    -- Width needed for N (1025) amount of samples of the input pulse
    constant C_PULSE_SAMPLES_WIDTH : natural := 10;

    ----------------------------------------------------------------------------    
    -- DUT Signals
    ----------------------------------------------------------------------------

    -- clk / rst_n
    signal tb_clk   : std_logic := '0';
    signal tb_rst_n : std_logic := '0';

    -- input signals
    signal tb_ce            : std_logic                                  := '0';
    signal tb_data_i        : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');
    signal tb_baseline_trig : std_logic                                  := '0';

    -- tb output signals
    signal tb_data_filtered       : std_logic_vector(C_ADC_WIDTH downto 0) := (others => '0');
    signal tb_data_filtered_valid : std_logic;
    signal tb_stat_error          : std_logic_vector(5 downto 0) := (others => '0');

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
            G_PULSE_WIDTH => C_PULSE_SAMPLES_WIDTH
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

    dut : entity trap_filter.trap_subsystem
        generic map(
            -- Data parameters
            G_DATA_WIDTH => C_ADC_WIDTH,
            -- Jordanov params
            G_JORD_K_WIDTH          => C_JORD_K_WIDTH,
            G_JORD_M_WIDTH          => C_JORD_M_WIDTH,
            G_JORD_M_EXP_VALUE      => C_M_EXP_VALUE,
            G_JORD_M_EXP_FRAC_WIDTH => 4,
            -- Jordanov fixed point params
            G_JORD_DIFF_MARGIN_BITS => 3,
            G_JORD_ACC1_MARGIN_BITS => 2,
            G_JORD_ACC2_MARGIN_BITS => 1,
            G_JORD_OUT_SHIFT_BITS   => C_JORD_OUT_SHIFT_BITS,
            -- Moving average params
            G_MOV_D_WIDTH         => C_MOV_D_WIDTH,
            G_MOV_ACC_MARGIN_BITS => 2,
            -- Pulse detection params
            G_PULSE_DELAY_WIDTH => C_PULSE_DELAY_WIDTH
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
            CE_I            => tb_ce,
            DATA_I          => tb_data_i,
            BASELINE_TRIG_I => tb_baseline_trig,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_FILTERED_O       => tb_data_filtered,
            DATA_FILTERED_VALID_O => tb_data_filtered_valid,
            STAT_ERROR_O          => tb_stat_error
        );

    ----------------------------------------------------------------------------
    -- Reference vs output validation
    ----------------------------------------------------------------------------

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

        wait for 1000 ns;
        wait until rising_edge(tb_clk);
        tb_baseline_trig <= '1';
        wait until rising_edge(tb_clk);
        tb_baseline_trig <= '0';

        wait for 8000 ns;

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