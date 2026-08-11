--==============================================================================
--  Module:        pulse_shaper_test_wrapper.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       08/08/2026
--  Last Modified: 
--
--  Description:
--  test top wrapper for the trap_filter system with added ILA and VIO cores.
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
        G_SLOW_JORD_K_DELAY     : natural range 16 to 256  := 256;   -- Value of the delay for rising edge of filtered trapezoid
        G_SLOW_JORD_M_DELAY     : natural range 16 to 256  := 256;   -- Value of the delay for flat top of filtered trapezoid
        G_SLOW_JORD_M_EXP_VALUE : natural range 0 to 65535 := 39992; -- Value of the decay exp coefficient (12 bits mag + 4 bits fraction)
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

    -- Top output signals
    signal trap_data      : std_logic_vector(G_ADC_WIDTH downto 0);               -- Filtered trapezoidal data output (signed)
    signal pulse_triggers : std_logic_vector(C_TRIG_DEPTH downto 0);              -- Trapezoidal pulse stage triggers (pulse, baseline, start, top, mid-top, end)
    signal pulse_valid    : std_logic;                                            -- Trapezoidal pulse valid (no pileup, no delays empty, no overflows)
    signal overflow_flags : std_logic_vector(C_OVERFLOW_FLAGS_DEPTH downto 0);    -- Overflow errors in trap/trig/peak subsystems
    signal time_cnt       : std_logic_vector(C_LOG_TIMESTAMP_WIDTH - 1 downto 0); -- Current timestamp counter from rst_n
    signal pileup_cnt     : std_logic_vector(C_PILEUP_CNT_WIDTH - 1 downto 0);    -- counter of pileup events

    -- Mark as debug for ILA
    attribute mark_debug                   : string;
    attribute mark_debug of trap_data      : signal is "true";
    attribute mark_debug of pulse_triggers : signal is "true";
    attribute mark_debug of pulse_valid    : signal is "true";
    attribute mark_debug of overflow_flags : signal is "true";
    attribute mark_debug of time_cnt       : signal is "true";
    attribute mark_debug of pileup_cnt     : signal is "true";

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
            G_DATA_WIDTH  => G_ADC_WIDTH,
            G_PULSE_DEPTH => C_PULSE_SAMPLE_DEPTH
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
            -- Pulse detection parameters
            G_CFD_VAL_TH   => G_CFD_VAL_TH,
            G_CFD_SLOPE_TH => G_CFD_SLOPE_TH,
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
            -- Outputs
            ------------------------------------------------------------------------
            TRAP_DATA_O      => trap_data,
            PULSE_TRIGGERS_O => pulse_triggers,
            PULSE_VALID_O    => pulse_valid,
            OVERFLOW_FLAGS_O => overflow_flags,
            PILEUP_CNT_O     => pileup_cnt,
            TIME_CNT_O       => time_cnt
        );

end architecture rtl;