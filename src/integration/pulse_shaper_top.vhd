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
        G_SLOW_JORD_K_WIDTH        : natural range 2 to 8     := 6;     -- Width of the delay for rising edge of filtered trapezoid
        G_SLOW_JORD_M_WIDTH        : natural range 2 to 8     := 8;     -- Width of the delay for flat top of filtered trapezoid
        G_SLOW_JORD_M_EXP_VALUE    : natural range 0 to 65535 := 39992; -- Value of the decay exp coefficient (12 bits mag + 4 bits fraction)
        G_SLOW_JORD_OUT_SHIFT_BITS : natural range 0 to 24    := 17;    -- Number of bits shifted from the 2nd accumulator of jordanov to the width of the output
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
        BRAM_B_EN_I         : in std_logic;                                             -- Port B enable
        BRAM_B_RW_I         : in std_logic;                                             -- Port B read/write
        BRAM_B_ADDR_I       : in std_logic_vector(C_LOG_ADDR_WIDTH - 1 downto 0);       -- Port B address
        BRAM_B_PULSE_DATA_O : out std_logic_vector(C_LOG_DATA_WIDTH - 1 downto 0);      -- Pulse Bram port B read data
        BRAM_B_TIME_DATA_O  : out std_logic_vector(C_LOG_TIMESTAMP_WIDTH - 1 downto 0); -- Timestamp Bram port B read data
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        DATA_O : out std_logic_vector(G_ADC_WIDTH downto 0) -- Timestamp Bram port B read data
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

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output Signals
    ----------------------------------------------------------------------------

    -- Top output signals
    signal trap_data_o       : std_logic_vector(G_ADC_WIDTH downto 0);               -- Filtered trapezoidal data output (signed)
    signal pulse_amplitude_o : std_logic_vector(G_ADC_WIDTH downto 0);               -- Captured amplitude of trapezoidal data (signed)
    signal pulse_t_rise_o    : std_logic_vector(C_LOG_T_RISE_WIDTH - 1 downto 0);    -- Captured rise time of original pulse
    signal pulse_triggers_o  : std_logic_vector(4 downto 0);                         -- Trapezoidal pulse stage triggers (baseline, start, top, mid-top, end)
    signal pulse_valid_o     : std_logic;                                            -- Trapezoidal pulse valid (no pileup, no delays empty, no overflows)
    signal overflow_flags_o  : std_logic_vector(8 downto 0);                         -- Overflow errors in trap/trig/peak subsystems
    signal log_pulse_o       : std_logic_vector(C_LOG_DATA_WIDTH - 1 downto 0);      -- written pulse data from pulse_logger
    signal log_time_o        : std_logic_vector(C_LOG_TIMESTAMP_WIDTH - 1 downto 0); -- written timestamp data from pulse_logger
    signal time_cnt_o        : std_logic_vector(C_LOG_TIMESTAMP_WIDTH - 1 downto 0); -- Current timestamp counter from rst_n

    ----------------------------------------------------------------------------
    -- Internal Signals
    ----------------------------------------------------------------------------

    -- triggers at stages of the pulse
    signal trig_baseline   : std_logic; -- trigger to capture baseline
    signal trig_top_center : std_logic; -- trigger to capture amplitude

    -- pulse completed without pileup
    signal pulse_clean  : std_logic;                                         -- Completed pulse with no pileups
    signal pileup_event : std_logic;                                         -- pileup event pulse
    signal pileup_cnt   : std_logic_vector(C_PILEUP_CNT_WIDTH - 1 downto 0); -- counter of pileup events

    -- overflow intermidiate signals
    signal error_trap_oflow : std_logic_vector(3 downto 0); -- Overflow errors in trap_subsystem (b32 jord, b1 mov_avg, b0 baseline substraction)
    signal error_trig_oflow : std_logic_vector(3 downto 0); -- Overflow errors in trig_subsystem (b32 jord, b10 cfd)
    signal error_peak_oflow : std_logic;                    -- Overflow errors in peak_subsystem (b0 mov_avg)

    -- Mark as debug for ILA
    attribute mark_debug                      : string;
    attribute mark_debug of trap_data_o       : signal is "true";
    attribute mark_debug of pulse_triggers_o  : signal is "true";
    attribute mark_debug of pulse_amplitude_o : signal is "true";
    attribute mark_debug of pulse_valid_o     : signal is "true";
    attribute mark_debug of log_pulse_o       : signal is "true";
    attribute mark_debug of log_time_o        : signal is "true";

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    DATA_O <= trap_data_o;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    -- overflow error of trap/trig/peak subsystems
    overflow_flags_o(8 downto 5) <= error_trap_oflow;
    overflow_flags_o(4 downto 1) <= error_trig_oflow;
    overflow_flags_o(0)          <= error_peak_oflow;

    -- triggers
    pulse_triggers_o(4) <= trig_baseline;
    pulse_triggers_o(1) <= trig_top_center;

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
            G_SLOW_JORD_K => G_SLOW_JORD_K_WIDTH,
            G_SLOW_JORD_M => G_SLOW_JORD_M_WIDTH,
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
            TRIGGER_O      => pulse_triggers_o,
            PILEUP_EVENT_O => pileup_event,
            PILEUP_CNT_O   => pileup_cnt,
            PULSE_CLEAN_O  => pulse_clean,
            ERROR_OFLOW_O  => error_trig_oflow
        );

    -- generates the filtered trapezoid signal
    trap_ss_ii : entity trap_filter.trap_subsystem
        generic map(
            -- General parameters
            G_DATA_WIDTH => G_ADC_WIDTH,
            -- Slow jordanov parameters
            G_JORD_K_WIDTH          => G_SLOW_JORD_K_WIDTH,
            G_JORD_M_WIDTH          => G_SLOW_JORD_M_WIDTH,
            G_JORD_M_EXP_VALUE      => G_SLOW_JORD_M_EXP_VALUE,
            G_JORD_M_EXP_FRAC_WIDTH => C_SLOW_JORD_M_EXP_FRAC_WIDTH,
            -- Slow jordanov fixed point parameters
            G_JORD_DIFF_MARGIN_BITS => C_SLOW_JORD_DIFF_MARGIN_BITS,
            G_JORD_ACC1_MARGIN_BITS => C_SLOW_JORD_ACC1_MARGIN_BITS,
            G_JORD_ACC2_MARGIN_BITS => C_SLOW_JORD_ACC2_MARGIN_BITS,
            G_JORD_OUT_SHIFT_BITS   => G_SLOW_JORD_OUT_SHIFT_BITS,
            -- Baseline moving average parameters
            G_MOV_D_WIDTH         => C_BASE_MOV_D_WIDTH,
            G_MOV_ACC_MARGIN_BITS => C_BASE_MOV_ACC_MARGIN_BITS,
            -- Trap_subsystem general due pulse detection
            G_TRAP_DELAY_WIDTH => C_TRIG_DELAY_TRAP_WIDTH
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
            DATA_FILTERED_O => trap_data_o,
            error_oflow_o   => error_trap_oflow
        );

    -- captures and validates the filtered amplitude at the top
    peak_ss_i : entity trap_filter.peak_subsystem
        generic map(
            -- General paramaters
            G_DATA_WIDTH => C_DATA_FILTERED_WIDTH,
            -- Peak moving average parameters
            G_MOV_ENABLE          => C_PEAK_MOV_ENABLE,
            G_MOV_D_WIDTH         => C_PEAK_MOV_D_WIDTH,
            G_MOV_ACC_MARGIN_BITS => C_PEAK_MOV_ACC_MARGIN_BITS
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
            TRIG_CAPTURE_I => trig_top_center,
            DATA_I         => trap_data_o,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_O        => pulse_amplitude_o,
            ERROR_OFLOW_O => error_peak_oflow
        );

    -- asserts validity of a pulse if all conditions are met
    valid_ss_i : entity trap_filter.valid_subsystem
        generic map(
            -- Slow jordanov parameters for timing of delays
            G_SLOW_JORD_K_WIDTH => G_SLOW_JORD_K_WIDTH,
            G_SLOW_JORD_M_WIDTH => G_SLOW_JORD_M_WIDTH
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
            ERROR_OFLOW_I => overflow_flags_o,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            VALID_O => pulse_valid_o
        );

    -- logs the captured data of a pulse
    logger_ss_i : entity trap_filter.logger_subsystem
        generic map(
            -- Memory parameters
            G_BRAM_ADDR_WIDTH => C_LOG_ADDR_WIDTH,
            G_BRAM_DATA_WIDTH => C_LOG_DATA_WIDTH,
            -- Pulse parameters
            G_PULSE_WIDTH  => C_DATA_FILTERED_WIDTH,
            G_T_RISE_WIDTH => C_LOG_T_RISE_WIDTH,
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
            PULSE_VALID_I    => pulse_valid_o,
            PULSE_CAPTURED_I => pulse_amplitude_o,
            PULSE_T_RISE_I   => pulse_t_rise_o,
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
            TIME_DATA_O  => log_time_o,
            PULSE_DATA_O => log_pulse_o,
            TIME_CNT_O   => time_cnt_o
        );

end architecture rtl;