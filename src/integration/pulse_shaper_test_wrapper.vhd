--==============================================================================
--  Module:        pulse_shaper_test_wrapper.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       08/08/2026
--  Last Modified: 
--
--  Description:
--  test top wrapper for the "pulse_shaper_top.vhd" system with added ILA and VIO cores.
--  Aimed for Zedboard Evaluation board.
--
--  Dependencies:
--  All rtl modules and packages
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity pulse_shaper_test_wrapper is
    generic (
        -- Input data parameters
        G_ADC_WIDTH : natural range 12 to 15 := 14; -- Width of the incoming data stream from the adc
        -- Trapezoidal filter parameters
        G_SLOW_JORD_K_DELAY     : natural range 16 to 256  := 128;   -- Value of the delay for rising edge of filtered trapezoid
        G_SLOW_JORD_M_DELAY     : natural range 16 to 256  := 256;   -- Value of the delay for flat top of filtered trapezoid
        G_SLOW_JORD_M_EXP_VALUE : natural range 0 to 65535 := 39992; -- Value of the decay exp coefficient (12 bits mag + 4 bits fraction)
        -- Moving average parameters
        G_BASE_MOV_DELAY_WIDTH   : natural range 2 to 5 := 4; -- Width of samples averaged in moving average for the baseline
        G_PEAK_MOV_DELAY_WIDTH   : natural range 2 to 5 := 3; -- Width of samples averaged in moving average for the peak
        G_T_RISE_MOV_DELAY_WIDTH : natural range 3 to 5 := 3; -- Width of samples averaged in moving average for the rise time
        -- Pulse detection parameters
        G_NOISE_THRESHOLD : natural range 10 to 4096 := 1400; -- Threshold level of noise to gate a pulse detection event
        -- Pileup discrimination parameters
        G_PILEUP_DECAY_VALUE : natural range 255 to 65535 := 2500 -- Amount of samples after pulse ended to ensure discrimination of pileups in pulse_valid signal
    );
    port (
        ------------------------------------------------------------------------
        -- Clock / Reset
        ------------------------------------------------------------------------
        CLK_I   : in std_logic;
        BTN_RST : in std_logic
    );
end entity pulse_shaper_test_wrapper;

architecture rtl of pulse_shaper_test_wrapper is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    -- Assert VIO is found at default library (we are in trap_filter)
    for u_vio : vio_trap use entity xil_defaultlib.vio_trap;

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- Control test signals
    signal rst_n  : std_logic;
    signal ce_i   : std_logic;
    signal ce_vio : std_logic_vector(0 downto 0);

    -- Input data to read Bram logger
    signal data_i          : std_logic_vector(G_ADC_WIDTH - 1 downto 0);
    signal bram_en         : std_logic;                                       -- Enable required
    signal bram_rw         : std_logic;                                       -- Write or read required operation
    signal bram_addr       : std_logic_vector(C_LOG_ADDR_WIDTH - 1 downto 0); -- Required address to read
    signal bram_pulse_data : std_logic_vector(C_LOG_DATA_WIDTH - 1 downto 0); -- Read data from pulse log
    signal bram_time_data  : std_logic_vector(C_LOG_DATA_WIDTH - 1 downto 0); -- Read data from timestamp log

    -- Top pulse output signals
    signal pulse_trapezoid : std_logic_vector(G_ADC_WIDTH downto 0);        -- Filtered trapezoidal data output (signed)
    signal pulse_amplitude : std_logic_vector(G_ADC_WIDTH downto 0);        -- Captured amplitude of trapezoidal data (signed)
    signal pulse_t_rise    : std_logic_vector(C_T_RISE_WIDTH - 1 downto 0); -- Captured rise time of original pulse
    signal pulse_triggers  : std_logic_vector(C_TRIG_DEPTH downto 0);       -- Trapezoidal pulse stage triggers (pulse, baseline, start, top, mid-top, end)
    signal pulse_valid     : std_logic;                                     -- Trapezoidal pulse valid (no pileup, no delays empty, no overflows)

    -- Top system output signals
    signal pileup_event  : std_logic;                                            -- Pileup event pulse
    signal pileup_cnt    : std_logic_vector(C_PILEUP_CNT_WIDTH - 1 downto 0);    -- Counter of pileup events
    signal timestamp_cnt : std_logic_vector(C_TIMESTAMP_CNT_WIDTH - 1 downto 0); -- Current timestamp counter from rst_n
    signal error_oflow   : std_logic_vector(C_OVERFLOW_FLAGS_DEPTH downto 0);    -- Overflow errors in trap/trig/peak subsystems

    -- Top logger output signals
    signal log_pulse_data     : std_logic_vector(C_LOG_DATA_WIDTH - 1 downto 0); -- Written pulse data from pulse_logger
    signal log_timestamp_data : std_logic_vector(C_LOG_DATA_WIDTH - 1 downto 0); -- Written timestamp data from pulse_logger

    -- Mark as debug for ILA
    attribute mark_debug : string;

    -- pulse data
    attribute mark_debug of data_i          : signal is "true";
    attribute mark_debug of pulse_trapezoid : signal is "true";
    attribute mark_debug of pulse_amplitude : signal is "true";
    attribute mark_debug of pulse_t_rise    : signal is "true";
    attribute mark_debug of pulse_triggers  : signal is "true";
    attribute mark_debug of pulse_valid     : signal is "true";

    -- system data
    attribute mark_debug of pileup_event  : signal is "true";
    attribute mark_debug of pileup_cnt    : signal is "true";
    attribute mark_debug of timestamp_cnt : signal is "true";
    attribute mark_debug of error_oflow   : signal is "true";

    -- logger data
    attribute mark_debug of log_pulse_data     : signal is "true";
    attribute mark_debug of log_timestamp_data : signal is "true";

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    -- external
    ce_i  <= ce_vio(0);
    rst_n <= not BTN_RST;

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Instantiation
    ----------------------------------------------------------------------------

    -- virtual input output for ce
    u_vio : vio_trap
    port map(
        clk        => CLK_I,
        probe_out0 => ce_vio
    );

    -- feeds stored pulse from rom
    pulse_feed_i : entity trap_filter.pulse_feed
        generic map(
            -- input pulse parameters
            G_DATA_WIDTH => G_ADC_WIDTH
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => CLK_I,
            RST_N_I => rst_n,
            ------------------------------------------------------------------------
            -- Inputs / Outputs
            ------------------------------------------------------------------------
            CE_I   => ce_i,
            DATA_O => data_i
        );

    -- pulse shaper top
    dut : entity trap_filter.pulse_shaper_top
        generic map(
            -- Input data parameters
            G_ADC_WIDTH => G_ADC_WIDTH,
            -- Trapezoidal filter parameters
            G_SLOW_JORD_K_DELAY     => G_SLOW_JORD_K_DELAY,
            G_SLOW_JORD_M_DELAY     => G_SLOW_JORD_M_DELAY,
            G_SLOW_JORD_M_EXP_VALUE => G_SLOW_JORD_M_EXP_VALUE,
            -- Moving average parameters
            G_BASE_MOV_DELAY_WIDTH   => G_BASE_MOV_DELAY_WIDTH,
            G_PEAK_MOV_DELAY_WIDTH   => G_PEAK_MOV_DELAY_WIDTH,
            G_T_RISE_MOV_DELAY_WIDTH => G_T_RISE_MOV_DELAY_WIDTH,
            -- Pulse detection parameters
            G_NOISE_THRESHOLD => G_NOISE_THRESHOLD,
            -- Pileup discrimination parameters
            G_PILEUP_DECAY_VALUE => G_PILEUP_DECAY_VALUE
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => CLK_I,
            RST_N_I => rst_n,
            ------------------------------------------------------------------------
            -- Inputs
            ------------------------------------------------------------------------
            DATA_I => data_i,
            ------------------------------------------------------------------------
            -- BRAM Port B
            ------------------------------------------------------------------------
            BRAM_B_EN_I         => bram_en,
            BRAM_B_RW_I         => bram_rw,
            BRAM_B_ADDR_I       => bram_addr,
            BRAM_B_PULSE_DATA_O => bram_pulse_data,
            BRAM_B_TIME_DATA_O  => bram_time_data,
            ------------------------------------------------------------------------
            -- Pulse Outputs
            ------------------------------------------------------------------------
            PULSE_TRAPEZOID_O => pulse_trapezoid,
            PULSE_AMPLITUDE_O => pulse_amplitude,
            PULSE_T_RISE_O    => pulse_t_rise,
            PULSE_TRIGGERS_O  => pulse_triggers,
            PULSE_VALID_O     => pulse_valid,
            ------------------------------------------------------------------------
            -- System Outputs
            ------------------------------------------------------------------------
            PILEUP_EVENT_O  => pileup_event,
            PILEUP_CNT_O    => pileup_cnt,
            TIMESTAMP_CNT_O => timestamp_cnt,
            ERROR_OFLOW_O   => error_oflow,
            ------------------------------------------------------------------------
            -- Logger Outputs
            ------------------------------------------------------------------------
            LOG_PULSE_DATA_O     => log_pulse_data,
            LOG_TIMESTAMP_DATA_O => log_timestamp_data
        );

end architecture rtl;