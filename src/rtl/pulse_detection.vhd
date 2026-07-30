--==============================================================================
--  Module:        pulse_detection.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       17/07/2026
--  Last Modified: 
--
--  Description:
--  Module that shapes a pulse into a trapezoid with delay and offset corrections.
--
--  Dependencies:
-- 
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity pulse_detection is
    generic (
        -- Data parameters
        G_DATA_WIDTH : natural range 8 to 16 := 14; -- Width of incoming data stream (ADC Magnitude resolution)
        -- thresholds and expected pulse timeout
        G_CFD_VAL_TH        : natural range 1024 to 4096 := 2048; -- threshold to gate value of DATA_I
        G_CFD_SLOPE_TH      : natural range 50 to 500    := 100;  -- threshold to gate slope of DATA_I
        G_CFD_TIMEOUT_WIDTH : natural range 5 to 10      := 7     -- timeout window width
    );
    port (
        ------------------------------------------------------------------------
        -- Clock / Reset
        ------------------------------------------------------------------------
        CLK_I   : in std_logic;
        RST_N_I : in std_logic;
        ------------------------------------------------------------------------
        -- Control Inputs
        ------------------------------------------------------------------------
        DATA_I : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- input data stream
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        PULSE_TRIG_O  : out std_logic;                   -- pulse detected flag (1 cycle pulse)
        ERROR_OFLOW_O : out std_logic_vector(3 downto 0) -- error status
    );
end entity pulse_detection;

architecture rtl of pulse_detection is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- Jordanov fixed point params for pulse detection
    constant C_JORD_K_WIDTH          : natural := 4;
    constant C_JORD_M_WIDTH          : natural := 4;
    constant C_JORD_M_EXP_VALUE      : natural := 39992; -- Width of decay exp factor (big "M_exp", 12 bits mag + 4 bits fraction)
    constant C_JORD_M_EXP_FRAC_WIDTH : natural := 4;     -- Width of decay exp factor for its fraction (big "M_exp")
    constant C_JORD_DIFF_MARGIN_BITS : natural := 3;     -- Width of margin given to the delayed difference
    constant C_JORD_ACC1_MARGIN_BITS : natural := 2;     -- Width of margin given to the 1st accumulator
    constant C_JORD_ACC2_MARGIN_BITS : natural := 1;     -- Width of margin given to the 2nd accumulator
    constant C_JORD_OUT_SHIFT_BITS   : natural := 17;    -- Number of bits to shift output

    -- Jordanov delay values
    constant C_JORD_K_DELAY  : natural := 2 ** C_JORD_K_WIDTH;             -- k  = 2^JORD_K_WIDTH
    constant C_JORD_M_DELAY  : natural := 2 ** C_JORD_M_WIDTH;             -- m  = 2^JORD_M_WIDTH
    constant C_JORD_L_DELAY  : natural := C_JORD_K_DELAY + C_JORD_M_DELAY; -- l  = k + m
    constant C_JORD_KL_DELAY : natural := C_JORD_K_DELAY + C_JORD_L_DELAY; -- k + l = 2k + m

    -- CFD fixed point parameters
    constant C_CFD_F_WIDTH      : natural := 2;                                    -- Bit width of scalar f -> * (1/f)
    constant C_CFD_D_WIDTH      : natural := 5;                                    -- Bit width of delay d for cfd
    constant C_CFD_M_WIDTH      : natural := 3;                                    -- Bit width of delay m for slope
    constant C_CFD_MARGIN_BITS  : natural := 1;                                    -- Margin bits for difference signal
    constant C_CFD_DATA_WIDTH   : natural := G_DATA_WIDTH + 1;                     -- CFD data width (ADC_WIDTH + 1)
    constant C_CFD_SIGNAL_WIDTH : natural := C_CFD_DATA_WIDTH + C_CFD_MARGIN_BITS; -- Bit width of cfd (zero-cross) signal

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output signals
    signal pulse_trig  : std_logic;                    -- pulse detected flag
    signal error_oflow : std_logic_vector(3 downto 0); -- error status

    -- delayed data
    signal data_n         : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_jord_k    : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_jord_l    : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_jord_kl   : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_jord_filt : std_logic_vector(G_DATA_WIDTH downto 0);

    -- cfd signals
    signal cfd_signal : std_logic_vector(C_CFD_SIGNAL_WIDTH - 1 downto 0);

    -- overflow errors
    signal jord_error_oflow : std_logic_vector(1 downto 0);
    signal cfd_error_oflow  : std_logic_vector(1 downto 0);

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    PULSE_TRIG_O  <= pulse_trig;
    ERROR_OFLOW_O <= error_oflow;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    error_oflow(3 downto 2) <= jord_error_oflow;
    error_oflow(1 downto 0) <= cfd_error_oflow;

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    -- cfd algorithm for amplitude discrimination
    cfd_i : entity trap_filter.cfd
        generic map(
            G_DATA_WIDTH        => C_CFD_DATA_WIDTH,
            G_CFD_F_WIDTH       => C_CFD_F_WIDTH,
            G_CFD_D_WIDTH       => C_CFD_D_WIDTH,
            G_CFD_M_WIDTH       => C_CFD_M_WIDTH,
            G_CFD_MARGIN_BITS   => C_CFD_MARGIN_BITS,
            G_CFD_VAL_TH        => G_CFD_VAL_TH,
            G_CFD_SLOPE_TH      => G_CFD_SLOPE_TH,
            G_CFD_TIMEOUT_WIDTH => G_CFD_TIMEOUT_WIDTH
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
            DATA_I => data_jord_filt,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            CFD_SIGNAL_O      => cfd_signal,
            CFD_PULSE_TRIG_O  => pulse_trig,
            CFD_ERROR_OFLOW_O => cfd_error_oflow
        );

    -- delay module for jordanov
    delay_i : entity trap_filter.delay_module
        generic map(
            G_DATA_WIDTH      => G_DATA_WIDTH,
            G_COMMON_DELAY_EN => 0,
            G_JORD_DELAY_EN   => 1,
            G_JORD_K_DELAY    => C_JORD_K_DELAY,
            G_JORD_L_DELAY    => C_JORD_L_DELAY,
            G_JORD_KL_DELAY   => C_JORD_KL_DELAY,
            G_MOV_DELAY_EN    => 0
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => CLK_I,
            RST_N_I => RST_N_I,
            ------------------------------------------------------------------------
            -- Control Inputs
            ------------------------------------------------------------------------
            DATA_I           => DATA_I,
            DATA_JORD_FILT_I => data_jord_filt,
            ------------------------------------------------------------------------
            -- Delayed data outputs
            ------------------------------------------------------------------------
            DATA_N_O     => data_n,
            DATA_K_O     => data_jord_k,
            DATA_L_O     => data_jord_l,
            DATA_KL_O    => data_jord_kl,
            DATA_MOV_D_O => open
        );

    -- jordanov for pileup discrimination (amplitude sensitive)
    jord_i : entity trap_filter.jordanov_filter
        generic map(
            -- Jordanov parameters
            G_DATA_WIDTH   => G_DATA_WIDTH,
            G_K_RISE_WIDTH => C_JORD_K_WIDTH,
            -- Exponential decay
            G_M_VALUE      => C_JORD_M_EXP_VALUE,
            G_M_FRAC_WIDTH => C_JORD_M_EXP_FRAC_WIDTH,
            -- Fixed point params
            G_DIFF_MARGIN_BITS => C_JORD_DIFF_MARGIN_BITS,
            G_ACC1_MARGIN_BITS => C_JORD_ACC1_MARGIN_BITS,
            G_ACC2_MARGIN_BITS => C_JORD_ACC2_MARGIN_BITS,
            G_OUT_SHIFT        => C_JORD_OUT_SHIFT_BITS
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => CLK_I,
            RST_N_I => RST_N_I,
            ------------------------------------------------------------------------
            -- Control Inputs
            ------------------------------------------------------------------------
            DATA_N_I  => data_n,
            DATA_K_I  => data_jord_k,
            DATA_L_I  => data_jord_l,
            DATA_KL_I => data_jord_kl,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_FILTERED_O => data_jord_filt,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            ERROR_OFLOW_O => jord_error_oflow
        );

end architecture rtl;