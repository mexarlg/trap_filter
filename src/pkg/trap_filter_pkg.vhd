--==============================================================================
--  Package:       trap_filter_pkg
--  Project:       trap_filter
--  Author:        Aldo Lupio
--  Created:       06/07/2026
--  Last Modified: 
--
--  Description:
--  Package containing types, constants, and component declarations
--  for the trap_filter system
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package trap_filter_pkg is

    ----------------------------------------------------------------------------
    -- Version / Metadata
    ----------------------------------------------------------------------------

    constant SYSTEM_VERSION : string := "1.1";

    ----------------------------------------------------------------------------
    -- General Parameters
    ----------------------------------------------------------------------------

    -- Configurable
    constant C_PULSE_SAMPLE_WIDTH : natural range 8 to 16 := 11; -- Bit width needed for the sample depth of the stored input pulse

    ----------------------------------------------------------------------------
    -- Slow Jordanov Parameters
    ----------------------------------------------------------------------------

    -- Configurable (Margin for internal signals of slow jordanov)
    constant C_SLOW_JORD_DIFF_MARGIN_BITS : natural range 1 to 3 := 3; -- Bits of margin given to the delayed difference of the slow jordanov
    constant C_SLOW_JORD_ACC1_MARGIN_BITS : natural range 1 to 2 := 2; -- Bits of margin given to the 1st accumulator of the slow jordanov
    constant C_SLOW_JORD_ACC2_MARGIN_BITS : natural range 0 to 1 := 1; -- Bits of margin given to the 2nd accumulator of the slow jordanov

    -- Fixed
    constant C_SLOW_JORD_M_EXP_FRAC_WIDTH : natural := 4; -- Number of bits for the fraction part of exponential coefficient M_exp in the slow jordanov

    ----------------------------------------------------------------------------
    -- Baseline Moving Average Parameters
    ----------------------------------------------------------------------------

    -- Configurable (Moving average parameters for baseline substraction)
    constant C_BASE_MOV_D_WIDTH         : natural range 2 to 8 := 4; -- Width of samples averaged in the moving average for the baseline (16 samples)
    constant C_BASE_MOV_ACC_MARGIN_BITS : natural range 2 to 5 := 2; -- Margin bits given to the accumulator inside the moving average for the baseline

    -- fixed
    constant C_BASE_MOV_LATENCY : natural := 2; -- latency in number of cycles from the baseline moving average filter

    ----------------------------------------------------------------------------
    -- Pulse Detection Parameters
    ----------------------------------------------------------------------------

    -- Fixed (jordanov parameters of fast jordanov for pulse detection)
    constant C_FAST_JORD_K_WIDTH          : natural := 4;     -- Width of delay for the rising edge of the trapezoid (16 samples)
    constant C_FAST_JORD_M_WIDTH          : natural := 4;     -- Width of delay for the flat top of the trapezoid (16 samples)
    constant C_FAST_JORD_M_EXP_VALUE      : natural := 39992; -- Value of decay exponential factor ("M_exp", selected for slowest possible expected pulse)
    constant C_FAST_JORD_M_EXP_FRAC_WIDTH : natural := 4;     -- Number of bits selected for the fraction part of the coefficient M_exp
    constant C_FAST_JORD_DIFF_MARGIN_BITS : natural := 3;     -- Bits of margin given to the delayed difference
    constant C_FAST_JORD_ACC1_MARGIN_BITS : natural := 2;     -- Bits of margin given to the 1st accumulator
    constant C_FAST_JORD_ACC2_MARGIN_BITS : natural := 1;     -- Bits of margin given to the 2nd accumulator
    constant C_FAST_JORD_OUT_SHIFT_BITS   : natural := 17;    -- Number of bits to shift the 2nd accumulator to the jordanov output (depends on k, M_exp)

    -- Fixed (constant fraction discriminator parameters for pulse detection)
    constant C_CFD_F_WIDTH            : natural := 2; -- Bit width of the value that scales the input data inside the cfd algorithm -> f = 2^CFD_F_WIDTH* 
    constant C_CFD_D_WIDTH            : natural := 5; -- Bit width of the delay d inside the cfd algorithm
    constant C_CFD_M_WIDTH            : natural := 3; -- Bit width of the delay m needed for the slope of the data to ensure pulse detection allowable if rising edge
    constant C_CFD_DIFF_MARGIN_BITS   : natural := 1; -- Bits of margin given to the difference signal in the cfd algorithm
    constant C_CFD_ZERO_TIMEOUT_WIDTH : natural := 7; -- Bit width of samples expected by cfd algorithm for a zero crossing event once thresholds are overcomed (timeout = 2^Timeout_width)

    -- Configurable (delays from detection trigger to stages of filtered pulse)
    constant C_TRIG_TO_BASELINE  : natural range 2 to 128 := 4;  -- N of samples from a pulse detected trigger to the baseline capture of the filtered pulse
    constant C_TRIG_TO_START     : natural range 4 to 256 := 30; -- N of samples from a pulse detected trigger to the rising edge of the filtered pulse
    constant C_START_PULSE_GUARD : natural range 0 to 16  := 1;  -- N of samples to assert earlier the rising edge of the filtered pulse

    -- Fixed
    constant C_DETECTION_DELAY_WIDTH : natural := 6; -- Width of delay given to trap_system to account for the pulse detection latency

    ----------------------------------------------------------------------------
    -- Peak Moving Average Parameters
    ----------------------------------------------------------------------------

    -- Configurable (Moving average parameters for pulse amplitude capture)
    constant C_PEAK_MOV_ENABLE          : natural range 0 to 1 := 1; -- Enable the moving average prefilter on the top of the filtered trapezoid
    constant C_PEAK_MOV_D_WIDTH         : natural range 2 to 8 := 4; -- Width of samples averaged in the moving average for the peak (16 samples)
    constant C_PEAK_MOV_ACC_MARGIN_BITS : natural range 2 to 5 := 2; -- Margin bits given to the accumulator inside the moving average for the peak

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    -- unconstrained rom memory type for the input pulse
    type mem_t is array (natural range <>) of std_logic_vector;

    ----------------------------------------------------------------------------
    -- Records
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Component Declaration
    ----------------------------------------------------------------------------

    -- VIO in top wrapper to assert internal CE
    component vio_trap is
        port (
            clk        : in std_logic;
            probe_out0 : out std_logic_vector(0 downto 0)
        );
    end component vio_trap;

end package trap_filter_pkg;

package body trap_filter_pkg is

    ----------------------------------------------------------------------------
    -- Package Body (functions if needed)
    ----------------------------------------------------------------------------

end package body trap_filter_pkg;