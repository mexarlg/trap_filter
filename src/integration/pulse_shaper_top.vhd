--==============================================================================
--  Module:        pulse_shaper_top.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       17/07/2026
--  Last Modified: 
--
--  Description:
--  top wrapper for the trap_filter system.
--
--  Dependencies:
--  All rtl modules and packages
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity pulse_shaper_top is
    generic (
        -- Input data parameters
        G_ADC_WIDTH : natural range 12 to 15 := 14; -- Width of the incoming data stream from the adc
        -- Trapezoidal filter parameters
        G_SLOW_JORD_K_DELAY     : natural range 16 to 256  := 256;   -- Value of the delay for rising edge of filtered trapezoid
        G_SLOW_JORD_M_DELAY     : natural range 16 to 256  := 256;   -- Value of the delay for flat top of filtered trapezoid
        G_SLOW_JORD_M_EXP_VALUE : natural range 0 to 65535 := 39992; -- Value of the decay exp coefficient (12 bits mag + 4 bits fraction)
        -- Moving average parameters
        G_BASE_MOV_DELAY_WIDTH   : natural range 3 to 5 := 4; -- Width of samples averaged in moving average for the baseline
        G_PEAK_MOV_EN            : natural range 0 to 1 := 1; -- Moving average enable for the peak
        G_PEAK_MOV_DELAY_WIDTH   : natural range 3 to 5 := 3; -- Width of samples averaged in moving average for the peak
        G_T_RISE_MOV_DELAY_WIDTH : natural range 3 to 5 := 3; -- Width of samples averaged in moving average for the rise time
        -- Pulse detection parameters
        G_CFD_VAL_TH   : natural range 1024 to 4096 := 2048; -- Threshold level of the fast jordanov output to gate pulse detection
        G_CFD_SLOPE_TH : natural range 50 to 500    := 100;  -- Threshold slope of the fast jordanov output to gate pulse detection
        -- Pileup discrimination parameters
        G_PILEUP_DECAY_VALUE : natural range 255 to 65535 := 4095 -- Amount of samples after pulse ended to ensure discrimination of pileups in pulse_valid signal
    );
    port (
        ------------------------------------------------------------------------
        -- Clock / Reset
        ------------------------------------------------------------------------
        CLK_I   : in std_logic;
        RST_N_I : in std_logic;
        ------------------------------------------------------------------------
        -- Inputs
        ------------------------------------------------------------------------
        DATA_I : in std_logic_vector(G_ADC_WIDTH - 1 downto 0);
        ------------------------------------------------------------------------
        -- BRAM Port B
        ------------------------------------------------------------------------
        BRAM_B_EN_I         : in std_logic;                                        -- Port B enable
        BRAM_B_RW_I         : in std_logic;                                        -- Port B read/write
        BRAM_B_ADDR_I       : in std_logic_vector(C_LOG_ADDR_WIDTH - 1 downto 0);  -- Port B address
        BRAM_B_PULSE_DATA_O : out std_logic_vector(C_LOG_DATA_WIDTH - 1 downto 0); -- Pulse Bram port B read data
        BRAM_B_TIME_DATA_O  : out std_logic_vector(C_LOG_DATA_WIDTH - 1 downto 0); -- Timestamp Bram port B read data
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        PULSE_TRAPEZOID_O : out std_logic_vector(G_ADC_WIDTH downto 0);              -- Trapezoid filtered output
        PULSE_TRIGGERS_O  : out std_logic_vector(C_TRIG_DEPTH downto 0);             -- Trapezoidal pulse stage triggers
        PULSE_VALID_O     : out std_logic;                                           -- Trapezoidal pulse valid (no pileup, no delays empty, no overflows)
        OVERFLOW_FLAGS_O  : out std_logic_vector(C_OVERFLOW_FLAGS_DEPTH downto 0);   -- Overflow errors in trap/trig/peak subsystems
        PILEUP_CNT_O      : out std_logic_vector(C_PILEUP_CNT_WIDTH - 1 downto 0);   -- Counter of pileup events
        TIME_CNT_O        : out std_logic_vector(C_LOG_TIMESTAMP_WIDTH - 1 downto 0) -- Counter of timestamp from rst_n
    );
end entity pulse_shaper_top;

architecture rtl of pulse_shaper_top is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- width of data after trap_subsystem filter
    constant C_DATA_FILTERED_WIDTH : natural := G_ADC_WIDTH + 1;

    -- delay given to trap_ss due pulse detection
    constant C_FAST_JORD_KL_DELAY : natural := C_FAST_JORD_K_DELAY + C_FAST_JORD_M_DELAY;                               -- delay from fast jordanov
    constant C_DETECTION_DELAY    : natural := C_FAST_JORD_KL_DELAY + C_CFD_DELAY + C_JORDANOV_LATENCY + C_CFD_LATENCY; -- total delay in N of samples

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output Signals
    ----------------------------------------------------------------------------

    -- Top output signals
    signal pulse_trapezoid : std_logic_vector(C_DATA_FILTERED_WIDTH - 1 downto 0); -- Filtered trapezoidal data output (signed)
    signal pulse_triggers  : std_logic_vector(C_TRIG_DEPTH downto 0);              -- Trapezoidal pulse stage triggers (pulse, baseline, start, top, mid-top, end)
    signal pulse_valid     : std_logic;                                            -- Trapezoidal pulse valid (no pileup, no delays empty, no overflows)
    signal overflow_flags  : std_logic_vector(C_OVERFLOW_FLAGS_DEPTH downto 0);    -- Overflow errors in trap/trig/peak subsystems
    signal time_cnt        : std_logic_vector(C_LOG_TIMESTAMP_WIDTH - 1 downto 0); -- Current timestamp counter from rst_n
    signal pileup_cnt      : std_logic_vector(C_PILEUP_CNT_WIDTH - 1 downto 0);    -- counter of pileup events

    ----------------------------------------------------------------------------
    -- Internal Signals
    ----------------------------------------------------------------------------

    -- triggers connections from trig_ss to trap_ss and peak_ss
    signal trig_pulse_detected : std_logic; -- trigger of pulse event
    signal trig_baseline       : std_logic; -- trigger to capture baseline
    signal trig_pulse_start    : std_logic; -- trigger to start of rising_edge
    signal trig_top_start      : std_logic; -- trigger to start of flat top
    signal trig_top_mid        : std_logic; -- trigger to capture amplitude
    signal trig_pulse_end      : std_logic; -- trigger of pulse end

    -- pileup information from trig_ss
    signal pulse_clean  : std_logic; -- Completed pulse with no pileups
    signal pileup_event : std_logic; -- pileup event pulse

    -- individual overflow flags from each subsystem
    signal error_trap_ss_oflow : std_logic_vector(3 downto 0); -- Overflow errors in trap_subsystem (b32 jord, b1 mov_avg, b0 baseline substraction)
    signal error_trig_ss_oflow : std_logic_vector(3 downto 0); -- Overflow errors in trig_subsystem (b32 jord, b10 cfd)
    signal error_peak_ss_oflow : std_logic_vector(1 downto 0); -- Overflow errors in peak_subsystem (b1 peak mov_avg, b2 t_rise mov_avg)

    -- logger formated data issued to bram
    signal log_pulse : std_logic_vector(C_LOG_DATA_WIDTH - 1 downto 0); -- written pulse data from pulse_logger
    signal log_time  : std_logic_vector(C_LOG_DATA_WIDTH - 1 downto 0); -- written timestamp data from pulse_logger

    -- Measured data from pulse given to logger
    signal pulse_amplitude : std_logic_vector(C_DATA_FILTERED_WIDTH - 1 downto 0); -- Captured amplitude of trapezoidal data (signed)
    signal pulse_t_rise    : std_logic_vector(C_T_RISE_WIDTH - 1 downto 0);        -- Captured rise time of original pulse

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    PULSE_TRAPEZOID_O <= pulse_trapezoid;
    PULSE_TRIGGERS_O  <= pulse_triggers;
    PULSE_VALID_O     <= pulse_valid;
    OVERFLOW_FLAGS_O  <= overflow_flags;
    PILEUP_CNT_O      <= pileup_cnt;
    TIME_CNT_O        <= time_cnt;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    -- overflow errors mux
    overflow_flags(9 downto 6) <= error_trap_ss_oflow;
    overflow_flags(5 downto 2) <= error_trig_ss_oflow;
    overflow_flags(1 downto 0) <= error_peak_ss_oflow;

    -- triggers demux
    trig_pulse_detected <= pulse_triggers(5);
    trig_baseline       <= pulse_triggers(4);
    trig_pulse_start    <= pulse_triggers(3);
    trig_top_start      <= pulse_triggers(2);
    trig_top_mid        <= pulse_triggers(1);
    trig_pulse_end      <= pulse_triggers(0);

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Instantiation
    ----------------------------------------------------------------------------

    -- issues triggers at different stages of the pulse
    trig_ss_i : entity trap_filter.trig_subsystem
        generic map(
            -- general parameters
            G_DATA_WIDTH => G_ADC_WIDTH,
            -- slow jordanov parameters for timing
            G_SLOW_JORD_M_EXP_VALUE => G_SLOW_JORD_M_EXP_VALUE,
            G_SLOW_JORD_K_DELAY     => G_SLOW_JORD_K_DELAY,
            G_SLOW_JORD_M_DELAY     => G_SLOW_JORD_M_DELAY,
            -- pulse detection tuning parameters
            G_CFD_VAL_TH   => G_CFD_VAL_TH,
            G_CFD_SLOPE_TH => G_CFD_SLOPE_TH,
            -- pileup discrimination parameters
            G_PILEUP_DECAY_VALUE => G_PILEUP_DECAY_VALUE,
            G_PILEUP_CNT_WIDTH   => C_PILEUP_CNT_WIDTH
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => CLK_I,
            RST_N_I => RST_N_I,
            ------------------------------------------------------------------------
            -- Inputs
            ------------------------------------------------------------------------
            DATA_I => DATA_I,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            PULSE_TRIGGERS_O => pulse_triggers,
            PILEUP_EVENT_O   => pileup_event,
            PILEUP_CNT_O     => pileup_cnt,
            PULSE_CLEAN_O    => pulse_clean,
            ERROR_OFLOW_O    => error_trig_ss_oflow
        );

    -- generates the filtered trapezoid signal
    trap_ss_i : entity trap_filter.trap_subsystem
        generic map(
            -- General parameters
            G_DATA_WIDTH => G_ADC_WIDTH,
            -- Slow jordanov parameters
            G_SLOW_JORD_K_DELAY     => G_SLOW_JORD_K_DELAY,
            G_SLOW_JORD_M_DELAY     => G_SLOW_JORD_M_DELAY,
            G_SLOW_JORD_M_EXP_VALUE => G_SLOW_JORD_M_EXP_VALUE,
            -- Slow jordanov fixed point parameters
            G_SLOW_JORD_DIFF_MARGIN_BITS => C_SLOW_JORD_DIFF_MARGIN_BITS,
            G_SLOW_JORD_ACC1_MARGIN_BITS => C_SLOW_JORD_ACC1_MARGIN_BITS,
            G_SLOW_JORD_ACC2_MARGIN_BITS => C_SLOW_JORD_ACC2_MARGIN_BITS,
            -- Baseline moving average parameters
            G_BASE_MOV_DELAY_WIDTH     => G_BASE_MOV_DELAY_WIDTH,
            G_BASE_MOV_ACC_MARGIN_BITS => C_BASE_MOV_ACC_MARGIN_BITS,
            -- Trap_subsystem common delay due to pulse detection
            G_DETECTION_DELAY => C_DETECTION_DELAY
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => CLK_I,
            RST_N_I => RST_N_I,
            ------------------------------------------------------------------------
            -- Inputs
            ------------------------------------------------------------------------
            DATA_I          => DATA_I,
            BASELINE_TRIG_I => trig_baseline,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_FILTERED_O => pulse_trapezoid,
            error_oflow_o   => error_trap_ss_oflow
        );

    -- captures and validates the filtered amplitude at the top
    peak_ss_i : entity trap_filter.peak_subsystem
        generic map(
            -- Data width paramaters
            G_DATA_WIDTH          => G_ADC_WIDTH,
            G_DATA_FILTERED_WIDTH => C_DATA_FILTERED_WIDTH,
            -- Time rise parameters
            G_T_RISE_WIDTH           => C_T_RISE_WIDTH,
            G_T_RISE_TIMEOUT         => C_T_RISE_TIMEOUT,
            G_T_RISE_DELAY           => C_T_RISE_DELAY,
            G_T_RISE_MOV_DELAY_WIDTH => G_T_RISE_MOV_DELAY_WIDTH,
            -- Peak moving average parameters
            G_PEAK_MOV_ENABLE          => G_PEAK_MOV_EN,
            G_PEAK_MOV_DELAY_WIDTH     => G_PEAK_MOV_DELAY_WIDTH,
            G_PEAK_MOV_ACC_MARGIN_BITS => C_PEAK_MOV_ACC_MARGIN_BITS
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => CLK_I,
            RST_N_I => RST_N_I,
            ------------------------------------------------------------------------
            -- Inputs
            ------------------------------------------------------------------------
            DATA_I          => DATA_I,
            TRIG_TOP_MID_I  => trig_top_mid,
            DATA_FILTERED_I => pulse_trapezoid,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            PULSE_AMPLITUDE_O => pulse_amplitude,
            PULSE_T_RISE_O    => pulse_t_rise,
            ERROR_OFLOW_O     => error_peak_ss_oflow
        );

    -- asserts validity of a pulse if all conditions are met
    valid_ss_i : entity trap_filter.valid_subsystem
        generic map(
            -- Trap_ss general delay
            G_DETECTION_DELAY => C_DETECTION_DELAY,
            -- Slow jordanov parameters for timing of delays
            G_SLOW_JORD_K_DELAY => G_SLOW_JORD_K_DELAY,
            G_SLOW_JORD_M_DELAY => G_SLOW_JORD_M_DELAY,
            G_SLOW_JORD_LATENCY => C_JORDANOV_LATENCY
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => CLK_I,
            RST_N_I => RST_N_I,
            ------------------------------------------------------------------------
            -- Inputs
            ------------------------------------------------------------------------
            PULSE_CLEAN_I => pulse_clean,
            ERROR_OFLOW_I => overflow_flags,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            VALID_O => pulse_valid
        );

    -- logs the captured data of a pulse
    logger_ss_i : entity trap_filter.logger_subsystem
        generic map(
            -- Memory parameters
            G_BRAM_ADDR_WIDTH => C_LOG_ADDR_WIDTH,
            G_BRAM_DATA_WIDTH => C_LOG_DATA_WIDTH,
            -- Pulse parameters
            G_PULSE_WIDTH  => C_DATA_FILTERED_WIDTH,
            G_T_RISE_WIDTH => C_T_RISE_WIDTH,
            -- Timestamp parameters
            G_TIMESTAMP_EN    => C_LOG_TIMESTAMP_EN,
            G_TIMESTAMP_WIDTH => C_LOG_TIMESTAMP_WIDTH
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => CLK_I,
            RST_N_I => RST_N_I,
            ------------------------------------------------------------------------
            -- Pulse log inputs
            ------------------------------------------------------------------------
            PULSE_VALID_I    => pulse_valid,
            PULSE_CAPTURED_I => pulse_amplitude,
            PULSE_T_RISE_I   => pulse_t_rise,
            ------------------------------------------------------------------------
            -- Bram Port B external read
            ------------------------------------------------------------------------
            BRAM_B_EN_I         => BRAM_B_EN_I,
            BRAM_B_RW_I         => BRAM_B_RW_I,
            BRAM_B_ADDR_I       => BRAM_B_ADDR_I,
            BRAM_B_PULSE_DATA_O => BRAM_B_PULSE_DATA_O,
            BRAM_B_TIME_DATA_O  => BRAM_B_TIME_DATA_O,
            ------------------------------------------------------------------------
            -- Bram Port A Outputs / Timestamp Stream
            ------------------------------------------------------------------------
            TIME_DATA_O  => log_time,
            PULSE_DATA_O => log_pulse,
            TIME_CNT_O   => time_cnt
        );

end architecture rtl;