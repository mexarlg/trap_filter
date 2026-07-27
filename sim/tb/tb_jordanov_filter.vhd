--==============================================================================
--  Testbench:     tb_jordanov_filter
--  Description:   Testbench for mov_avg_filter
--  Author:        Aldo Lupio
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;
use trap_filter.tb_jordanov_filter_pkg.all;

entity tb_jordanov_filter is
end entity;

architecture tb of tb_jordanov_filter is

    ----------------------------------------------------------------------------
    -- Test configuration
    ----------------------------------------------------------------------------

    -- Jordanov params configuration
    constant C_ADC_WIDTH    : natural := 14;
    constant C_K_RISE_WIDTH : natural := 6; -- k  = 2^K_RISE_WIDTH
    constant C_M_FLAT_WIDTH : natural := 7; -- m  = 2^M_FLAT_WIDTH

    -- Delay values
    constant C_K_RISE_DELAY : natural := 2 ** C_K_RISE_WIDTH;             -- k  = 2^K_RISE_WIDTH
    constant C_M_FLAT_DELAY : natural := 2 ** C_M_FLAT_WIDTH;             -- m  = 2^M_FLAT_WIDTH
    constant C_L_DELAY      : natural := C_K_RISE_DELAY + C_M_FLAT_DELAY; -- l  = k + m
    constant C_KL_DELAY     : natural := C_K_RISE_DELAY + C_L_DELAY;      -- k + l = 2k + m

    -- Exp decay
    constant C_M_EXP_VALUE : natural := 39992; -- round(2499.5 * 2^4), M_FRAC = 4

    ----------------------------------------------------------------------------    
    -- DUT Signals
    ----------------------------------------------------------------------------

    -- clk / rst_n
    signal tb_clk   : std_logic := '0';
    signal tb_rst_n : std_logic := '0';

    -- input signal to shift register
    signal tb_ce     : std_logic                                  := '0';
    signal tb_data_i : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');

    -- tb input signals of jordanov_filter
    signal tb_data_n  : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');
    signal tb_data_k  : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');
    signal tb_data_l  : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');
    signal tb_data_kl : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');
    signal tb_data_d  : std_logic_vector(C_ADC_WIDTH downto 0)     := (others => '0');

    -- tb output signals of mov_avg_filter
    signal tb_data_filtered : std_logic_vector(C_ADC_WIDTH downto 0) := (others => '0');
    signal tb_error_oflow   : std_logic_vector(1 downto 0)           := (others => '0');

begin

    ----------------------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------------------

    tb_clk <= not tb_clk after CLK_PERIOD/2;

    ----------------------------------------------------------------------------
    -- DUT Instantiation
    ----------------------------------------------------------------------------

    dut : entity trap_filter.jordanov_filter
        generic map(
            -- Jordanov parameters
            G_DATA_WIDTH   => C_ADC_WIDTH,
            G_K_RISE_WIDTH => C_K_RISE_WIDTH,
            -- Exponential decay
            G_M_VALUE      => C_M_EXP_VALUE,
            G_M_FRAC_WIDTH => 4,
            -- Fixed point params
            G_DIFF_MARGIN_BITS => 3,
            G_ACC1_MARGIN_BITS => 2,
            G_ACC2_MARGIN_BITS => 1,
            G_OUT_SHIFT        => 17
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
            DATA_N_I  => tb_data_n,
            DATA_K_I  => tb_data_k,
            DATA_L_I  => tb_data_l,
            DATA_KL_I => tb_data_kl,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_FILTERED_O => tb_data_filtered,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            ERROR_OFLOW_O => tb_error_oflow
        );

    delay_trap_i : entity trap_filter.delay_module
        generic map(
            G_DATA_WIDTH      => C_ADC_WIDTH,
            G_COMMON_DELAY_EN => 1,
            G_COMMON_DELAY    => 8,
            G_JORD_DELAY_EN   => 1,
            G_JORD_K_DELAY    => C_K_RISE_DELAY,
            G_JORD_L_DELAY    => C_L_DELAY,
            G_JORD_KL_DELAY   => C_KL_DELAY,
            G_MOV_DELAY_EN    => 1,
            G_MOV_D_DELAY     => 8
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
            DATA_I           => tb_data_i,
            DATA_JORD_FILT_I => tb_data_filtered,
            ------------------------------------------------------------------------
            -- Delayed data outputs
            ------------------------------------------------------------------------
            DATA_N_O     => tb_data_n,
            DATA_K_O     => tb_data_k,
            DATA_L_O     => tb_data_l,
            DATA_KL_O    => tb_data_kl,
            DATA_MOV_D_O => tb_data_d
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

        -- toggle of CE
        tb_ce <= '0';
        wait for 80 ns;
        tb_ce <= '1';
        wait for 80 ns;
        tb_ce <= '0';

        ------------------------------------------------------------------------
        -- Simulation done
        ------------------------------------------------------------------------
        wait for 200 ns;
        assert false report "Simulation finished" severity failure;
        wait;
    end process p_stimulus;

end architecture tb;