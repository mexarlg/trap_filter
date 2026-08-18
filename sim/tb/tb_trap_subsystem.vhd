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
use trap_filter.pulse_rom_pkg.all;

entity tb_trap_subsystem is
end entity;

architecture tb of tb_trap_subsystem is

    ----------------------------------------------------------------------------
    -- Test configuration
    ----------------------------------------------------------------------------

    constant CLK_PERIOD : time := 8 ns;

    -- Jordanov params configuration
    constant C_ADC_WIDTH            : natural := 14;
    constant C_JORD_K_DELAY         : natural := 256; -- k  
    constant C_JORD_M_DELAY         : natural := 256; -- m  
    constant C_BASE_MOV_DELAY_WIDTH : natural := 4;   -- d  = 2^C_DELAY_WIDTH
    constant C_DETECTION_DELAY      : natural := 64;  -- d

    -- Exp decay
    constant C_M_EXP_VALUE : natural := 39992; -- round(2499.5 * 2^4), M_FRAC = 4

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
    signal tb_data_filtered : std_logic_vector(C_ADC_WIDTH downto 0) := (others => '0');
    signal tb_stat_error    : std_logic_vector(3 downto 0)           := (others => '0');

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
            G_DATA_WIDTH => C_ADC_WIDTH
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
            CE_I   => tb_ce,
            DATA_O => tb_data_i
        );

    dut : entity trap_filter.trap_subsystem
        generic map(
            -- Data parameters
            G_DATA_WIDTH => C_ADC_WIDTH,
            -- Jordanov params
            G_SLOW_JORD_K_DELAY     => C_JORD_K_DELAY,
            G_SLOW_JORD_M_DELAY     => C_JORD_M_DELAY,
            G_SLOW_JORD_M_EXP_VALUE => C_M_EXP_VALUE,
            -- Jordanov fixed point params
            G_SLOW_JORD_DIFF_MARGIN_BITS => 3,
            G_SLOW_JORD_ACC1_MARGIN_BITS => 2,
            G_SLOW_JORD_ACC2_MARGIN_BITS => 1,
            -- Moving average params
            G_BASE_MOV_DELAY_WIDTH     => C_BASE_MOV_DELAY_WIDTH,
            G_BASE_MOV_ACC_MARGIN_BITS => 2,
            -- Pulse detection params
            G_DETECTION_DELAY => C_DETECTION_DELAY
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
            DATA_I          => tb_data_i,
            BASELINE_TRIG_I => tb_baseline_trig,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_FILTERED_O => tb_data_filtered,
            ERROR_OFLOW_O   => tb_stat_error
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

        wait for 16000 ns;

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