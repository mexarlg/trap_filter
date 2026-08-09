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

    constant SYSTEM_VERSION : string := "1.2";

    ----------------------------------------------------------------------------
    -- General Parameters
    ----------------------------------------------------------------------------

    -- Configurable
    constant C_PULSE_SAMPLE_WIDTH : natural range 8 to 16 := 11; -- Bit width needed for the sample depth of the stored input pulse

    -- Fixed
    constant C_OVERFLOW_FLAGS_DEPTH : natural := 8; -- Amount of bits required for all overflow flags of the system

    ----------------------------------------------------------------------------
    -- Trap Subsystem: Slow Jordanov Parameters
    ----------------------------------------------------------------------------

    -- Configurable (Margin for internal signals of slow jordanov)
    constant C_SLOW_JORD_DIFF_MARGIN_BITS : natural range 1 to 3 := 3; -- Bits of margin given to the delayed difference of the slow jordanov
    constant C_SLOW_JORD_ACC1_MARGIN_BITS : natural range 1 to 2 := 2; -- Bits of margin given to the 1st accumulator of the slow jordanov
    constant C_SLOW_JORD_ACC2_MARGIN_BITS : natural range 0 to 1 := 1; -- Bits of margin given to the 2nd accumulator of the slow jordanov

    -- Fixed
    constant C_SLOW_JORD_M_EXP_FRAC_WIDTH : natural := 4; -- Number of bits for the fraction part of exponential coefficient M_exp in the slow jordanov

    ----------------------------------------------------------------------------
    -- Trap Subsystem: Baseline Moving Average Parameters
    ----------------------------------------------------------------------------

    -- Configurable (Moving average parameters for baseline substraction)
    constant C_BASE_MOV_D_WIDTH         : natural range 2 to 8 := 4; -- Width of samples averaged in the moving average for the baseline (16 samples)
    constant C_BASE_MOV_ACC_MARGIN_BITS : natural range 2 to 5 := 2; -- Margin bits given to the accumulator inside the moving average for the baseline

    -- fixed
    constant C_BASE_MOV_LATENCY : natural := 2; -- latency in number of cycles from the baseline moving average filter

    ----------------------------------------------------------------------------
    -- Trig Subsystem: Pulse Detection Parameters
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
    constant C_TRIG_DELAY_BASELINE   : natural range 2 to 128 := 4;  -- N of samples from a pulse detected trigger to the baseline capture of the filtered pulse
    constant C_TRIG_DELAY_START      : natural range 4 to 256 := 30; -- N of samples from a pulse detected trigger to the rising edge of the filtered pulse
    constant C_TRIG_DELAY_TRAP_WIDTH : natural range 4 to 6   := 6;  -- Width of delay given to trap_system to account for the pulse detection latency

    -- Fixed (Amount of triggers)
    constant C_TRIG_DEPTH : natural := 5; -- Depth / Amount of trigger pulses describing the stages of a pulse

    -- Configurable (pileup parameters)
    constant C_PILEUP_CNT_WIDTH : natural range 7 to 12 := 12; -- Counter of pileup events from RST_N deassertion

    ----------------------------------------------------------------------------
    -- Peak Subsystem: Moving Average Parameters
    ----------------------------------------------------------------------------

    -- Configurable (Moving average parameters for pulse amplitude capture)
    constant C_PEAK_MOV_ENABLE          : natural range 0 to 1 := 1; -- Enable the moving average prefilter on the top of the filtered trapezoid
    constant C_PEAK_MOV_D_WIDTH         : natural range 2 to 8 := 4; -- Width of samples averaged in the moving average for the peak
    constant C_PEAK_MOV_ACC_MARGIN_BITS : natural range 2 to 5 := 2; -- Margin bits given to the accumulator inside the moving average for the peak

    ----------------------------------------------------------------------------
    -- Logger Subsystem: Logger Parameters
    ----------------------------------------------------------------------------

    -- configurable (width of log addresses and bit allocation of log data)
    constant C_LOG_ADDR_WIDTH      : natural range 10 to 16 := 10; -- Width of pulse log memory address (N logged pulses = depth = 2^ADDR_WIDTH)
    constant C_LOG_TIMESTAMP_EN    : natural range 0 to 1   := 1;  -- Enable of timestamp 
    constant C_LOG_TIMESTAMP_WIDTH : natural range 28 to 32 := 32; -- Width of timestamp (counter from rst_n deassertion)
    constant C_LOG_T_RISE_WIDTH    : natural range 8 to 12  := 12; -- Width of rise time

    -- Fixed (Max allowable widths for pulse logger)
    constant C_LOG_DATA_WIDTH       : natural := 32; -- Width of a single pulse log
    constant C_LOG_MAX_AMP_WIDTH    : natural := 16; -- Maximum width of the amplitude for bit preallocation (+1 of max adc_width)
    constant C_LOG_MAX_T_RISE_WIDTH : natural := 12; -- Maximum width of the rise time for bit preallocation

    -- Fixed (limit bits of amplitude and rise time inside a pulse log)
    constant C_LOG_AMP_HI    : natural := C_LOG_DATA_WIDTH - 1;                   -- Highest bit of amplitude in log
    constant C_LOG_AMP_LO    : natural := C_LOG_DATA_WIDTH - C_LOG_MAX_AMP_WIDTH; -- Lowest bit of amplitude in log
    constant C_LOG_T_RISE_HI : natural := C_LOG_MAX_T_RISE_WIDTH - 1;             -- Highest bit of rise time in log
    constant C_LOG_T_RISE_LO : natural := 0;                                      -- Lowest bit of amplitude in log

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    -- unconstrained rom memory type for the input pulse
    type mem_t is array (natural range <>) of std_logic_vector;

    ----------------------------------------------------------------------------
    -- Records
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    -- helpers to get required width
    function value_to_width (v : natural) return positive;
    function depth_to_width (n : positive) return positive;

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

    -- Computes width needed to store value
    function value_to_width (v : natural) return positive is
        variable w                 : positive := 1;
        variable m                 : natural  := v;
    begin
        while m > 1 loop
            m := m / 2;
            w := w + 1;
        end loop;
        return w;
    end function;

    -- Computes width needed to store depth
    function depth_to_width (n : positive) return positive is
        variable w                 : natural  := 0;
        variable c                 : positive := 1;
    begin
        while c < n loop
            c := c * 2;
            w := w + 1;
        end loop;
        if w = 0 then
            return 1;
        end if;
        return w;
    end function;

end package body trap_filter_pkg;