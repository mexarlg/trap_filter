--==============================================================================
--  Module:        pulse_detection.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       17/07/2026
--  Last Modified: 
--
--  Description:
--  Module that takes the input data and filters it accordingly to issue a
--  trigger that shows if a pulse is incoming.
--  The design features a fast jordanov algorithm + a constant fraction discriminator (cfd) 
--  to detect pulses independently of its offset or pileup (jord) and its amplitude (cfd).
--
--  Dependencies:
--  trap_filter_pkg.vhd, shift_register.vhd, cfd.vhd, delay_module.vhd,
--  jordanov_filter.vhd, trig_gen.vhd
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
        -- Slow jordanov parameters
        G_SLOW_JORD_M_EXP_VALUE : natural range 0 to 65535 := 39992; -- Value of the decay exp coefficient (12 bits mag + 4 bits fraction)
        -- thresholds and expected zero cross timeout for pulse detection
        G_CFD_NOISE_TH      : natural range 10 to 4096 := 1400; -- Threshold level of noise to gate a pulse detection event
        G_CFD_TIMEOUT_WIDTH : natural range 5 to 10    := 7     -- timeout width after thresholds are overcomed for a zero crossing event
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

    -- Fast jordanov delay values to do initial filtering of DATA_I
    constant C_FAST_JORD_L_DELAY  : natural := C_FAST_JORD_K_DELAY + C_FAST_JORD_M_DELAY; -- l  = k + m
    constant C_FAST_JORD_KL_DELAY : natural := C_FAST_JORD_K_DELAY + C_FAST_JORD_L_DELAY; -- k + l = 2k + m

    -- data width after jordanov filter (unsigned to signed)
    constant C_DATA_FILTERED_WIDTH : natural := G_DATA_WIDTH + 1;

    -- Constant fraction discriminator internal width
    constant C_CFD_SIGNAL_WIDTH : natural := C_DATA_FILTERED_WIDTH + C_CFD_DIFF_MARGIN_BITS; -- Bit width of cfd (zero-cross) signal

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output signals
    signal pulse_trig  : std_logic;                    -- pulse has been detected trigger
    signal error_oflow : std_logic_vector(3 downto 0); -- overflow error of jordanov and cfd modules

    -- delayed data
    signal data_n         : std_logic_vector(G_DATA_WIDTH - 1 downto 0);          -- data at sample n
    signal data_jord_k    : std_logic_vector(G_DATA_WIDTH - 1 downto 0);          -- data at sample n - k
    signal data_jord_l    : std_logic_vector(G_DATA_WIDTH - 1 downto 0);          -- data at sample n - l
    signal data_jord_kl   : std_logic_vector(G_DATA_WIDTH - 1 downto 0);          -- data at sample n -kl
    signal data_jord_filt : std_logic_vector(C_DATA_FILTERED_WIDTH - 1 downto 0); -- filtered data after fast jordanov

    -- cfd signals
    signal cfd_signal : std_logic_vector(C_CFD_SIGNAL_WIDTH - 1 downto 0); -- internal cfd signal for zero crossing event

    -- overflow errors
    signal jord_error_oflow : std_logic_vector(1 downto 0); -- overflow error of jordanov
    signal cfd_error_oflow  : std_logic_vector(1 downto 0); -- overflow error of cfd

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
            -- general data
            G_DATA_WIDTH => C_DATA_FILTERED_WIDTH,
            -- delays and coefficients for cfd
            G_CFD_F_WIDTH     => C_CFD_F_WIDTH,
            G_CFD_DELAY       => C_CFD_DELAY,
            G_CFD_SLOPE_DELAY => C_CFD_SLOPE_DELAY,
            -- margins for internal cfd signal
            G_CFD_MARGIN_BITS => C_CFD_DIFF_MARGIN_BITS,
            -- thresholds and expected timeout after th activation
            G_CFD_NOISE_TH      => G_CFD_NOISE_TH,
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

    -- Generates required delays for the fast jordanov filter
    delay_i : entity trap_filter.delay_module
        generic map(
            -- general data
            G_DATA_WIDTH => G_DATA_WIDTH,
            -- common delays and enable
            G_COMMON_DELAY_EN => 0,
            -- jordanov delays and enable
            G_JORD_DELAY_EN => 1,
            G_JORD_K_DELAY  => C_FAST_JORD_K_DELAY,
            G_JORD_L_DELAY  => C_FAST_JORD_L_DELAY,
            G_JORD_KL_DELAY => C_FAST_JORD_KL_DELAY,
            -- moving avg delays and enable
            G_MOV_DELAY_EN => 0
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

    -- jordanov for offset or pileup discrimination
    jord_i : entity trap_filter.jordanov_filter
        generic map(
            -- General parameters
            G_DATA_WIDTH => G_DATA_WIDTH,
            -- Jordanov parameters
            G_K_DELAY     => C_FAST_JORD_K_DELAY,
            G_M_EXP_VALUE => G_SLOW_JORD_M_EXP_VALUE,
            -- Fixed point params
            G_DIFF_MARGIN_BITS => C_FAST_JORD_DIFF_MARGIN_BITS,
            G_ACC1_MARGIN_BITS => C_FAST_JORD_ACC1_MARGIN_BITS,
            G_ACC2_MARGIN_BITS => C_FAST_JORD_ACC2_MARGIN_BITS
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
            ERROR_OFLOW_O   => jord_error_oflow
        );

end architecture rtl;