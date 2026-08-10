--==============================================================================
--  Testbench:     tb_pulse_shaper_top
--  Description:   Testbench for top wrapper
--  Author:        Aldo Lupio
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity tb_pulse_shaper_top is
end entity;

architecture tb of tb_pulse_shaper_top is

    ----------------------------------------------------------------------------
    -- Test configuration
    ----------------------------------------------------------------------------

    constant CLK_PERIOD : time := 8 ns;

    -- Input data parameters
    constant C_ADC_WIDTH    : natural range 12 to 15     := 14;   -- Width of the incoming data stream from the adc
    constant C_SAMPLE_DEPTH : natural range 255 to 65535 := 2048; -- Depth of input pulse
    -- Trapezoidal filter parameters
    constant C_SLOW_JORD_K_WIDTH        : natural range 2 to 8     := 8;     -- Width of the delay for rising edge of filtered trapezoid
    constant C_SLOW_JORD_M_WIDTH        : natural range 2 to 8     := 8;     -- Width of the delay for flat top of filtered trapezoid
    constant C_SLOW_JORD_M_EXP_VALUE    : natural range 0 to 65535 := 39992; -- Value of the decay exp coefficient (12 bits mag + 4 bits fraction)
    constant C_SLOW_JORD_OUT_SHIFT_BITS : natural range 0 to 24    := 19;    -- Number of bits shifted from the 2nd accumulator of jordanov to the width of the output
    -- Pulse detection parameters
    constant C_CFD_VAL_TH   : natural range 1024 to 4096 := 2048; -- Threshold level of the fast jordanov output to gate pulse detection
    constant C_CFD_SLOPE_TH : natural range 50 to 500    := 100;  -- Threshold slope of the fast jordanov output to gate pulse detection
    -- Pileup discrimination parameters
    constant C_PILEUP_DECAY_VALUE : natural range 255 to 65535 := 4095; -- Amount of samples after pulse ended to ensure discrimination of pileups in pulse_valid signal

    ----------------------------------------------------------------------------    
    -- DUT Signals
    ----------------------------------------------------------------------------

    -- clk / rst_n
    signal tb_clk   : std_logic := '0';
    signal tb_rst_n : std_logic := '0';

    -- input signals
    signal tb_ce     : std_logic                                  := '0';
    signal tb_data_i : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');

    -- input port b bram signals
    signal tb_bram_en         : std_logic;                                            -- Enable required
    signal tb_bram_rw         : std_logic;                                            -- Write or read required operation
    signal tb_bram_addr       : std_logic_vector(C_LOG_ADDR_WIDTH - 1 downto 0);      -- Required address to read
    signal tb_bram_pulse_data : std_logic_vector(C_LOG_DATA_WIDTH - 1 downto 0);      -- Read data from pulse log
    signal tb_bram_time_data  : std_logic_vector(C_LOG_TIMESTAMP_WIDTH - 1 downto 0); -- Read data from timestamp log

    -- Top output signals
    signal tb_trap_data      : std_logic_vector(C_ADC_WIDTH downto 0);               -- Filtered trapezoidal data output (signed)
    signal tb_pulse_triggers : std_logic_vector(C_TRIG_DEPTH downto 0);              -- Trapezoidal pulse stage triggers (baseline, start, top, mid-top, end)
    signal tb_pulse_valid    : std_logic;                                            -- Trapezoidal pulse valid (no pileup, no delays empty, no overflows)
    signal tb_overflow_flags : std_logic_vector(C_OVERFLOW_FLAGS_DEPTH downto 0);    -- Overflow errors in trap/trig/peak subsystems
    signal tb_time_cnt       : std_logic_vector(C_LOG_TIMESTAMP_WIDTH - 1 downto 0); -- Current timestamp counter from rst_n
    signal tb_pileup_cnt     : std_logic_vector(C_PILEUP_CNT_WIDTH - 1 downto 0);    -- counter of pileup events

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
            G_PULSE_DEPTH => C_SAMPLE_DEPTH
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

    dut : entity trap_filter.pulse_shaper_top
        generic map(
            -- Input data parameters
            G_ADC_WIDTH => C_ADC_WIDTH,
            -- Trapezoidal filter parameters
            G_SLOW_JORD_K_WIDTH        => C_SLOW_JORD_K_WIDTH,
            G_SLOW_JORD_M_WIDTH        => C_SLOW_JORD_M_WIDTH,
            G_SLOW_JORD_M_EXP_VALUE    => C_SLOW_JORD_M_EXP_VALUE,
            G_SLOW_JORD_OUT_SHIFT_BITS => C_SLOW_JORD_OUT_SHIFT_BITS,
            -- Pulse detection parameters
            G_CFD_VAL_TH   => C_CFD_VAL_TH,
            G_CFD_SLOPE_TH => C_CFD_SLOPE_TH,
            -- Pileup discrimination parameters
            G_PILEUP_DECAY_VALUE => C_PILEUP_DECAY_VALUE
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => tb_clk,
            RST_N_I => tb_rst_n,
            ------------------------------------------------------------------------
            -- Inputs
            ------------------------------------------------------------------------
            DATA_I => tb_data_i,
            ------------------------------------------------------------------------
            -- BRAM Port B
            ------------------------------------------------------------------------
            BRAM_B_EN_I         => tb_bram_en,
            BRAM_B_RW_I         => tb_bram_rw,
            BRAM_B_ADDR_I       => tb_bram_addr,
            BRAM_B_PULSE_DATA_O => tb_bram_pulse_data,
            BRAM_B_TIME_DATA_O  => tb_bram_time_data,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            TRAP_DATA_O      => tb_trap_data,
            PULSE_TRIGGERS_O => tb_pulse_triggers,
            PULSE_VALID_O    => tb_pulse_valid,
            OVERFLOW_FLAGS_O => tb_overflow_flags,
            PILEUP_CNT_O     => tb_pileup_cnt,
            TIME_CNT_O       => tb_time_cnt
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

        wait for 30000 ns;

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