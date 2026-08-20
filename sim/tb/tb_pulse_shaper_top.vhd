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
use trap_filter.pulse_rom_pkg.all;

entity tb_pulse_shaper_top is
end entity;

architecture tb of tb_pulse_shaper_top is

    ----------------------------------------------------------------------------
    -- Test configuration
    ----------------------------------------------------------------------------

    constant CLK_PERIOD : time := 8 ns;

    -- Input data parameters from pulse_rom_pkg
    constant C_ADC_WIDTH : natural range 12 to 15 := ADC_WIDTH; -- Width of the incoming data stream from the adc
    -- Trapezoidal filter parameters
    constant C_SLOW_JORD_K_DELAY     : natural range 16 to 256  := 128;   -- Value of the delay for rising edge of filtered trapezoid
    constant C_SLOW_JORD_M_DELAY     : natural range 16 to 256  := 256;   -- Value of the delay for flat top of filtered trapezoid
    constant C_SLOW_JORD_M_EXP_VALUE : natural range 0 to 65535 := 39992; -- Value of the decay exp coefficient (12 bits mag + 4 bits fraction)
    -- Moving average parameters
    constant C_BASE_MOV_DELAY_WIDTH   : natural range 3 to 5 := 4; -- Width average in baseline
    constant C_PEAK_MOV_DELAY_WIDTH   : natural range 3 to 5 := 3; -- Width average in peak
    constant C_T_RISE_MOV_DELAY_WIDTH : natural range 3 to 5 := 3; -- Width average in peak
    -- Physical parameters
    constant C_BASELINE_THRESHOLD : natural range 10 to 4096   := 1650; -- Threshold level of the fast jordanov output to gate pulse detection
    constant C_PILEUP_DECAY_VALUE : natural range 255 to 65535 := 2500; -- Amount of samples after pulse ended to ensure discrimination of pileups in pulse_valid signal
    -- Logger parameters
    constant C_LOG_ADDR_WIDTH   : natural range 10 to 16 := 10; -- Width of pulse log memory address (N logged pulses = 2^ADDR_WIDTH)
    constant C_PILEUP_CNT_WIDTH : natural range 7 to 16  := 12; -- Counter width of pileup events since RST_N deassertion
    constant C_TIMESTAMP_DIV    : natural range 0 to 6   := 4;  -- Bits shifted in timestamp for higher range at lower precision (at 4, LSB = 128 ns at 125MHz)

    -- time to wait for simulation
    constant C_WINDOW_TIME : time := ROM_DEPTH * CLK_PERIOD;

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
    signal tb_bram_en         : std_logic;                                       -- Enable required
    signal tb_bram_rw         : std_logic;                                       -- Write or read required operation
    signal tb_bram_addr       : std_logic_vector(C_LOG_ADDR_WIDTH - 1 downto 0); -- Required address to read
    signal tb_bram_pulse_data : std_logic_vector(C_LOG_DATA_WIDTH - 1 downto 0); -- Read data from pulse log
    signal tb_bram_time_data  : std_logic_vector(C_LOG_DATA_WIDTH - 1 downto 0); -- Read data from timestamp log

    -- logger bram outputs
    signal tb_log_pulse_data     : std_logic_vector(C_LOG_DATA_WIDTH - 1 downto 0); -- written pulse data from pulse_logger
    signal tb_log_timestamp_data : std_logic_vector(C_LOG_DATA_WIDTH - 1 downto 0); -- written timestamp data from pulse_logger

    -- pulse output signals
    signal tb_pulse_trapezoid : std_logic_vector(C_ADC_WIDTH downto 0);        -- Filtered trapezoidal data output (signed)
    signal tb_pulse_amplitude : std_logic_vector(C_ADC_WIDTH downto 0);        -- Captured amplitude (signed)
    signal tb_pulse_t_rise    : std_logic_vector(C_T_RISE_WIDTH - 1 downto 0); -- Captured time rise
    signal tb_pulse_triggers  : std_logic_vector(C_TRIG_DEPTH downto 0);       -- Trapezoidal pulse stage triggers (baseline, start, top, mid-top, end)
    signal tb_pulse_state     : std_logic_vector(2 downto 0);                  -- Pulse state (All data valid, amplitude valid, rise time valid)

    -- system outputs signals
    signal tb_pileup_event  : std_logic;                                            -- flag of pileup events
    signal tb_pileup_cnt    : std_logic_vector(C_PILEUP_CNT_WIDTH - 1 downto 0);    -- counter of pileup events
    signal tb_timestamp_cnt : std_logic_vector(C_TIMESTAMP_CNT_WIDTH - 1 downto 0); -- Current timestamp counter from rst_n
    signal tb_error_oflow   : std_logic_vector(C_OVERFLOW_FLAGS_DEPTH downto 0);    -- Overflow errors in trap/trig/peak subsystems

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

    dut : entity trap_filter.pulse_shaper_top
        generic map(
            -- Input data parameters
            G_ADC_WIDTH => C_ADC_WIDTH,
            -- Trapezoidal filter parameter
            G_SLOW_JORD_K_DELAY     => C_SLOW_JORD_K_DELAY,
            G_SLOW_JORD_M_DELAY     => C_SLOW_JORD_M_DELAY,
            G_SLOW_JORD_M_EXP_VALUE => C_SLOW_JORD_M_EXP_VALUE,
            -- Moving average parameters
            G_BASE_MOV_DELAY_WIDTH   => C_BASE_MOV_DELAY_WIDTH,
            G_PEAK_MOV_DELAY_WIDTH   => C_PEAK_MOV_DELAY_WIDTH,
            G_T_RISE_MOV_DELAY_WIDTH => C_T_RISE_MOV_DELAY_WIDTH,
            -- Physical parameters
            G_BASELINE_THRESHOLD => C_BASELINE_THRESHOLD,
            G_PILEUP_DECAY_VALUE => C_PILEUP_DECAY_VALUE,
            -- Logger parameters
            G_LOG_ADDR_WIDTH   => C_LOG_ADDR_WIDTH,
            G_PILEUP_CNT_WIDTH => C_PILEUP_CNT_WIDTH,
            G_TIMESTAMP_DIV    => C_TIMESTAMP_DIV
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
            -- Pulse outputs
            PULSE_TRAPEZOID_O => tb_pulse_trapezoid,
            PULSE_AMPLITUDE_O => tb_pulse_amplitude,
            PULSE_T_RISE_O    => tb_pulse_t_rise,
            PULSE_TRIGGERS_O  => tb_pulse_triggers,
            PULSE_STATE_O     => tb_pulse_state,
            -- System outputs
            PILEUP_EVENT_O  => tb_pileup_event,
            PILEUP_CNT_O    => tb_pileup_cnt,
            TIMESTAMP_CNT_O => tb_timestamp_cnt,
            ERROR_OFLOW_O   => tb_error_oflow,
            -- Logger outputs
            LOG_PULSE_DATA_O     => tb_log_pulse_data,
            LOG_TIMESTAMP_DATA_O => tb_log_timestamp_data

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

        wait for C_WINDOW_TIME;

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