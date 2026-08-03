--==============================================================================
--  Module:        top_trap_zedboard_test.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       17/07/2026
--  Last Modified: 
--
--  Description:
--  top wrapper for the trap_filter system. Added ILA and VIO cores for hw testing.
--
--  Dependencies:
--  All rtl modules and packages
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity top_trap_zedboard_test is
    generic (
        -- Input data parameters
        G_ADC_WIDTH : natural range 8 to 16 := 14; -- Width of the incoming data stream from the adc
        -- Trapezoidal filter parameters
        G_SLOW_JORD_K_WIDTH        : natural range 2 to 8     := 6;     -- Width of the delay for rising edge of filtered trapezoid
        G_SLOW_JORD_M_WIDTH        : natural range 2 to 8     := 8;     -- Width of the delay for flat top of filtered trapezoid
        G_SLOW_JORD_M_EXP_VALUE    : natural range 0 to 65535 := 39992; -- Value of the decay exp coefficient (12 bits mag + 4 bits fraction)
        G_SLOW_JORD_OUT_SHIFT_BITS : natural range 0 to 24    := 17;    -- Number of bits shifted from the 2nd accumulator of jordanov to the width of the output
        -- Pulse detection params
        G_CFD_VAL_TH      : natural range 1024 to 4096 := 2048; -- Threshold level of the fast jordanov output to gate pulse detection
        G_CFD_SLOPE_TH    : natural range 50 to 500    := 100;  -- Threshold slope of the fast jordanov output to gate pulse detection
        G_END_PULSE_GUARD : natural range 0 to 128     := 40    -- Amount of samples after pulse ended to ensure discrimination of pileups in pulse_valid signal
    );
    port (
        ------------------------------------------------------------------------
        -- Clock / Reset
        ------------------------------------------------------------------------
        CLK_I   : in std_logic;
        BTN_RST : in std_logic
    );
end entity top_trap_zedboard_test;

architecture rtl of top_trap_zedboard_test is

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

    -- Assert VIO is found at default library (we are in trap_filter)
    for u_vio : vio_trap use entity xil_defaultlib.vio_trap;

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- Top output signals
    signal pulse_filtered_o : std_logic_vector(G_ADC_WIDTH downto 0); -- Filtered trapezoidal data output (signed)
    signal pulse_captured_o : std_logic_vector(G_ADC_WIDTH downto 0); -- Captured amplitude of trapezoidal data (signed)
    signal error_oflow_o    : std_logic_vector(8 downto 0);           -- Overflow error in trap/trig/peak subsystems
    signal pulse_trigger_o  : std_logic_vector(4 downto 0);           -- Trapezoidal pulse stage triggers (baseline, start, top, mid-top, end)
    signal pulse_valid_o    : std_logic;                              -- Trapezoidal pulse is valid (no pileup, no delays empty, no overflows)

    -- rst_n / ce / data_i signals
    signal rst_n  : std_logic;
    signal ce_vio : std_logic_vector(0 downto 0);
    signal ce_i   : std_logic;
    signal data_i : std_logic_vector(G_ADC_WIDTH - 1 downto 0);

    -- valid intermidiate signals
    signal valid_pileup : std_logic; -- Valid indicating no pileups
    signal valid_delay  : std_logic; -- Valid indicating delay lines have been filled

    -- overflow intermidiate signals
    signal error_trap_oflow : std_logic_vector(3 downto 0); -- Overflow errors in trap_subsystem (b32 jord, b1 mov_avg, b0 baseline substraction)
    signal error_trig_oflow : std_logic_vector(3 downto 0); -- Overflow errors in trig_subsystem (b32 jord, b10 cfd)
    signal error_peak_oflow : std_logic;                    -- Overflow errors in peak_subsystem (b0 mov_avg)

    -- Mark as debug for ILA
    attribute mark_debug                     : string;
    attribute mark_debug of data_i           : signal is "true";
    attribute mark_debug of ce_i             : signal is "true";
    attribute mark_debug of pulse_filtered_o : signal is "true";
    attribute mark_debug of pulse_trigger_o  : signal is "true";
    attribute mark_debug of pulse_captured_o : signal is "true";
    attribute mark_debug of pulse_valid_o    : signal is "true";
    attribute mark_debug of error_oflow_o    : signal is "true";

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

    -- Internal ce
    ce_i <= ce_vio(0);

    -- Button is active high, rst_n is active low
    rst_n <= not BTN_RST;

    -- overflow error of trap/trig/peak subsystems
    error_oflow_o(8 downto 5) <= error_trap_oflow;
    error_oflow_o(4 downto 1) <= error_trig_oflow;
    error_oflow_o(0)          <= error_peak_oflow;

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Instantiation
    ----------------------------------------------------------------------------

    -- asserts ce
    u_vio : vio_trap
    port map(
        clk        => CLK_I,
        probe_out0 => ce_vio
    );

    -- feeds stored pulse in rom to trap_subsystem
    pulse_feed_i : entity trap_filter.pulse_feed
        generic map(
            -- input pulse parameters
            G_DATA_WIDTH  => G_ADC_WIDTH,
            G_PULSE_WIDTH => C_PULSE_SAMPLE_WIDTH
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
            CE_I         => ce_i,
            DATA_O       => data_i,
            DATA_VALID_O => open
        );

    -- issues triggers at different stages of the pulse
    trig_ss_i : entity trap_filter.trig_subsystem
        generic map(
            -- general parameters
            G_DATA_WIDTH => G_ADC_WIDTH,
            -- slow jordanov parameters for timing
            G_SLOW_JORD_K => G_SLOW_JORD_K_WIDTH,
            G_SLOW_JORD_M => G_SLOW_JORD_M_WIDTH,
            -- pulse detection tuning parameters
            G_CFD_VAL_TH      => G_CFD_VAL_TH,
            G_CFD_SLOPE_TH    => G_CFD_SLOPE_TH,
            G_END_PULSE_GUARD => G_END_PULSE_GUARD
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
            DATA_I        => data_i,
            TRIGGER_O     => pulse_trigger_o,
            PULSE_VALID_O => valid_pileup,
            ERROR_OFLOW_O => error_trig_oflow
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
            G_PULSE_DELAY_WIDTH => C_DETECTION_DELAY_WIDTH
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
            DATA_I          => data_i,
            BASELINE_TRIG_I => pulse_trigger_o(4),
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_FILTERED_O => pulse_filtered_o,
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
            RST_N_I => rst_n,
            ------------------------------------------------------------------------
            -- Inputs
            ------------------------------------------------------------------------
            VALID_PILEUP_I => valid_pileup,
            VALID_DELAY_I  => valid_delay,
            ERROR_OFLOW_I  => error_trap_oflow & error_trig_oflow,
            TRIG_CAPTURE_I => pulse_trigger_o(1),
            DATA_I         => pulse_filtered_o,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_O        => pulse_captured_o,
            VALID_O       => pulse_valid_o,
            ERROR_OFLOW_O => error_peak_oflow
        );

    -- tracks most critical delay pipeline to assert valid
    valid_delay_i : entity trap_filter.delay_tracker
        generic map(
            -- Slow jordanov parameters
            G_SLOW_JORD_K_WIDTH => G_SLOW_JORD_K_WIDTH,
            G_SLOW_JORD_M_WIDTH => G_SLOW_JORD_M_WIDTH
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => CLK_I,
            RST_N_I => rst_n,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            VALID_DELAY_O => valid_delay
        );

end architecture rtl;