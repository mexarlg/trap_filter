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

    constant SYSTEM_VERSION : string := "1.3";

    ----------------------------------------------------------------------------
    -- General Parameters
    ----------------------------------------------------------------------------

    -- Configurable
    constant C_PULSE_SAMPLE_DEPTH : natural range 255 to 65535 := 2048; -- Sample depth of the stored input pulse

    -- Fixed (latencies and number of overflow flags)
    constant C_OVERFLOW_FLAGS_DEPTH : natural := 8; -- Amount of bits required for all overflow flags of the system
    constant C_JORDANOV_LATENCY     : natural := 9;
    constant C_MOVING_AVG_LATENCY   : natural := 2; -- latency in number of cycles of the baseline moving average filter

    ----------------------------------------------------------------------------
    -- Trap Subsystem: Slow Jordanov Parameters
    ----------------------------------------------------------------------------

    -- Configurable (Margin for internal signals of slow jordanov)
    constant C_SLOW_JORD_DIFF_MARGIN_BITS : natural range 1 to 3 := 3; -- Bits of margin given to the delayed difference of the slow jordanov
    constant C_SLOW_JORD_ACC1_MARGIN_BITS : natural range 1 to 2 := 2; -- Bits of margin given to the 1st accumulator of the slow jordanov
    constant C_SLOW_JORD_ACC2_MARGIN_BITS : natural range 0 to 1 := 1; -- Bits of margin given to the 2nd accumulator of the slow jordanov

    ----------------------------------------------------------------------------
    -- Trap Subsystem: Baseline Moving Average Parameters
    ----------------------------------------------------------------------------

    -- Configurable (Moving average parameters for baseline substraction)
    constant C_BASE_MOV_DELAY_WIDTH     : natural range 2 to 8 := 4; -- Width of samples averaged in the moving average for the baseline (16 samples)
    constant C_BASE_MOV_ACC_MARGIN_BITS : natural range 2 to 5 := 2; -- Margin bits given to the accumulator inside the moving average for the baseline

    ----------------------------------------------------------------------------
    -- Trig Subsystem: Pulse Detection Parameters
    ----------------------------------------------------------------------------

    -- Fixed (jordanov parameters of fast jordanov for pulse detection)
    constant C_FAST_JORD_K_DELAY          : natural := 16; -- Width of delay for the rising edge of the trapezoid (16 samples)
    constant C_FAST_JORD_M_DELAY          : natural := 16; -- Width of delay for the flat top of the trapezoid (16 samples)
    constant C_FAST_JORD_DIFF_MARGIN_BITS : natural := 3;  -- Bits of margin given to the delayed difference
    constant C_FAST_JORD_ACC1_MARGIN_BITS : natural := 2;  -- Bits of margin given to the 1st accumulator
    constant C_FAST_JORD_ACC2_MARGIN_BITS : natural := 1;  -- Bits of margin given to the 2nd accumulator

    -- Fixed (constant fraction discriminator parameters for pulse detection)
    constant C_CFD_F_WIDTH            : natural := 2; -- Bit width of the value that scales the input data inside the cfd algorithm -> f = 2^CFD_F_WIDTH* 
    constant C_CFD_D_WIDTH            : natural := 5; -- Bit width of the delay d inside the cfd algorithm
    constant C_CFD_M_WIDTH            : natural := 3; -- Bit width of the delay m needed for the slope of the data to ensure pulse detection allowable if rising edge
    constant C_CFD_DIFF_MARGIN_BITS   : natural := 1; -- Bits of margin given to the difference signal in the cfd algorithm
    constant C_CFD_ZERO_TIMEOUT_WIDTH : natural := 7; -- Bit width of samples expected by cfd algorithm for a zero crossing event once thresholds are overcomed

    -- Configurable (delays from detection trigger to stages of filtered pulse)
    constant C_TRIG_DELAY_BASELINE : natural range 2 to 128 := 4;  -- N of samples from a pulse detected trigger to the baseline capture of the filtered pulse
    constant C_TRIG_DELAY_START    : natural range 4 to 256 := 20; -- N of samples from a pulse detected trigger to the rising edge of the filtered pulse

    -- Fixed (Amount of triggers)
    constant C_TRIG_DEPTH : natural := 5; -- Depth / Amount of trigger pulses describing the stages of a pulse

    -- Configurable (pileup parameters)
    constant C_PILEUP_CNT_WIDTH : natural range 7 to 12 := 12; -- Counter of pileup events from RST_N deassertion

    ----------------------------------------------------------------------------
    -- Peak Subsystem: Moving Average Parameters
    ----------------------------------------------------------------------------

    -- Configurable (Moving average parameters for pulse amplitude capture)
    constant C_PEAK_MOV_ENABLE          : natural range 0 to 1 := 1; -- Enable the moving average prefilter on the top of the filtered trapezoid
    constant C_PEAK_MOV_DELAY_WIDTH     : natural range 2 to 8 := 4; -- Width of samples averaged in the moving average for the peak
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
    function f_value_to_width (v : natural) return positive;
    function f_depth_to_width (n : positive) return positive;

    -- helpers for jordanov
    function f_log2_floor (arg : real) return natural;
    function f_max (a : integer; b : integer) return integer;
    function f_sat_resize (arg : signed; new_width : natural) return signed;

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
    function f_value_to_width (v : natural) return positive is
        variable w                   : positive := 1;
        variable m                   : natural  := v;
    begin
        while m > 1 loop
            m := m / 2;
            w := w + 1;
        end loop;
        return w;
    end function;

    -- Computes width needed to store depth
    function f_depth_to_width (n : positive) return positive is
        variable w                   : natural  := 0;
        variable c                   : positive := 1;
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

    -- Computes floor(log2(x))
    function f_log2_floor (arg : real) return natural is
        variable v_val             : real    := arg;
        variable v_res             : natural := 0;
    begin
        while v_val >= 2.0 loop
            v_val := v_val / 2.0;
            v_res := v_res + 1;
        end loop;
        return v_res;
    end function f_log2_floor;

    -- Computes the larger of two integers
    function f_max (a : integer; b : integer) return integer is
    begin
        if (a > b) then
            return a;
        else
            return b;
        end if;
    end function f_max;

    -- Computes a signed resize with saturation
    function f_sat_resize (arg : signed; new_width : natural) return signed is
        constant C_ARG : signed(arg'length - 1 downto 0) := arg;
        constant C_HI  : signed(new_width - 1 downto 0)  := (new_width - 1 => '0', others => '1');
        constant C_LO  : signed(new_width - 1 downto 0)  := (new_width - 1 => '1', others => '0');
        variable v_top : signed(C_ARG'length - new_width downto 0);
    begin
        if (C_ARG'length <= new_width) then
            return resize(C_ARG, new_width);
        end if;
        -- bits discarded by the narrowing
        v_top := C_ARG(C_ARG'length - 1 downto new_width - 1);
        if (v_top = 0) or (v_top =- 1) then
            return resize(C_ARG, new_width);
        elsif (C_ARG(C_ARG'length - 1) = '0') then
            return C_HI;
        else
            return C_LO;
        end if;
    end function f_sat_resize;

end package body trap_filter_pkg;