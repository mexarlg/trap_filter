--==============================================================================
--  Module:        trap_subsystem.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       17/07/2026
--  Last Modified: 
--
--  Description:
--  System that filters an input pulse into a trapezoid shape with delay
--  synchronization and baseline corrections through a continuous streaming behaviour. 
--
--  Dependencies:
--  trap_filter_pkg.vhd, shift_register.vhd, mov_avg_filter.vhd,
--  baseline_restorer.vhd, delay_module.vhd, jordanov_filter.vhd
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity trap_subsystem is
    generic (
        -- Data parameters
        G_DATA_WIDTH : natural range 8 to 16 := 14; -- Width of incoming data stream (ADC Magnitude resolution)
        -- Slow jordanov params
        G_JORD_K_WIDTH          : natural range 2 to 8     := 6;     -- Width of the delay for rising edge of filtered trapezoid
        G_JORD_M_WIDTH          : natural range 2 to 8     := 8;     -- Width of the delay for flat top of filtered trapezoid
        G_JORD_M_EXP_VALUE      : natural range 0 to 65535 := 39992; -- Value of the decay exp coefficient (12 bits mag + 4 bits fraction)
        G_JORD_M_EXP_FRAC_WIDTH : natural range 1 to 4     := 4;     -- Number of bits selected for the fraction part of the coefficient M_exp
        -- Slow jordanov fixed point params
        G_JORD_DIFF_MARGIN_BITS : natural range 1 to 3  := 3;  -- Bits of margin given to the delayed difference
        G_JORD_ACC1_MARGIN_BITS : natural range 1 to 2  := 2;  -- Bits of margin given to the 1st accumulator
        G_JORD_ACC2_MARGIN_BITS : natural range 0 to 1  := 1;  -- Bits of margin given to the 2nd accumulator
        G_JORD_OUT_SHIFT_BITS   : natural range 0 to 24 := 17; -- Number of bits to shift the 2nd accumulator to the jordanov output (depends on k, M_exp)
        -- Baseline moving average params
        G_MOV_D_WIDTH         : natural range 2 to 8 := 4; -- Width of samples averaged in the moving average for the baseline
        G_MOV_ACC_MARGIN_BITS : natural range 2 to 5 := 2; -- Margin bits given to the accumulator inside the moving average for the baseline
        -- Common delay due to pulse detection system
        G_TRAP_DELAY_WIDTH : natural range 4 to 6 := 5 -- Width of delay given to trap_system to account for the pulse detection latency
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
        DATA_I          : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Input data stream
        BASELINE_TRIG_I : in std_logic;                                   -- Trigger to capture the baseline
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        DATA_FILTERED_O : out std_logic_vector(G_DATA_WIDTH downto 0); -- Filtered trapezoidal output (signed)
        ERROR_OFLOW_O   : out std_logic_vector(3 downto 0)             -- Trapezoidal overflow error
    );
end entity trap_subsystem;

architecture rtl of trap_subsystem is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- Delay values
    constant C_JORD_K_DELAY  : natural := 2 ** G_JORD_K_WIDTH;             -- k  = 2^K_RISE_WIDTH
    constant C_JORD_M_DELAY  : natural := 2 ** G_JORD_M_WIDTH;             -- m  = 2^M_FLAT_WIDTH
    constant C_JORD_L_DELAY  : natural := C_JORD_K_DELAY + C_JORD_M_DELAY; -- l  = k + m
    constant C_JORD_KL_DELAY : natural := C_JORD_K_DELAY + C_JORD_L_DELAY; -- k + l = 2k + m
    constant C_MOV_D_DELAY   : natural := 2 ** G_MOV_D_WIDTH;              -- Value of delay for mov avg
    constant C_PULSE_DELAY   : natural := 2 ** G_TRAP_DELAY_WIDTH;         -- Value of delay for both paths

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output signals
    signal data_filtered : std_logic_vector(G_DATA_WIDTH downto 0); -- Trapezoidal output (signed)
    signal error_oflow   : std_logic_vector(3 downto 0);            -- error status

    -- intermidiate data after delays
    signal data_n       : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_jord_k  : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_jord_l  : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_jord_kl : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_mov_d   : std_logic_vector(G_DATA_WIDTH downto 0);

    -- intermidiate data after jordanov and mov avg filters
    signal data_jord_filt : std_logic_vector(G_DATA_WIDTH downto 0);
    signal data_mov_filt  : std_logic_vector(G_DATA_WIDTH downto 0);

    -- overflow error signals
    signal error_oflow_jord : std_logic_vector(1 downto 0);
    signal error_oflow_mov  : std_logic;
    signal error_oflow_base : std_logic;

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    DATA_FILTERED_O <= data_filtered;
    ERROR_OFLOW_O   <= error_oflow;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    -- error group
    error_oflow(3 downto 2) <= error_oflow_jord;
    error_oflow(1)          <= error_oflow_mov;
    error_oflow(0)          <= error_oflow_base;

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    -- Generates necessary delays for slow jordanov
    delay_module_i : entity trap_filter.delay_module
        generic map(
            G_DATA_WIDTH      => G_DATA_WIDTH,
            G_COMMON_DELAY_EN => 1,
            G_COMMON_DELAY    => C_PULSE_DELAY,
            G_JORD_DELAY_EN   => 1,
            G_JORD_K_DELAY    => C_JORD_K_DELAY,
            G_JORD_L_DELAY    => C_JORD_L_DELAY,
            G_JORD_KL_DELAY   => C_JORD_KL_DELAY,
            G_MOV_DELAY_EN    => 1,
            G_MOV_D_DELAY     => C_MOV_D_DELAY
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
            DATA_MOV_D_O => data_mov_d
        );

    -- Averages the filtered data for baseline substraction
    mov_avg_i : entity trap_filter.mov_avg_filter
        generic map(
            G_DATA_WIDTH      => G_DATA_WIDTH,
            G_DELAY_WIDTH     => G_MOV_D_WIDTH,
            G_ACC_MARGIN_BITS => G_MOV_ACC_MARGIN_BITS,
            G_DATA_I_SIGNED   => 1
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
            DATA_N_I => data_jord_filt,
            DATA_D_I => data_mov_d,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_FILTERED_O => data_mov_filt,
            ERROR_OFLOW_O   => error_oflow_mov
        );

    -- filters input data to trapezoidal shape
    jord_i : entity trap_filter.jordanov_filter
        generic map(
            -- Jordanov parameters
            G_DATA_WIDTH   => G_DATA_WIDTH,
            G_K_RISE_WIDTH => G_JORD_K_WIDTH,
            -- Exponential decay
            G_M_VALUE      => G_JORD_M_EXP_VALUE,
            G_M_FRAC_WIDTH => G_JORD_M_EXP_FRAC_WIDTH,
            -- Fixed point params
            G_DIFF_MARGIN_BITS => G_JORD_DIFF_MARGIN_BITS,
            G_ACC1_MARGIN_BITS => G_JORD_ACC1_MARGIN_BITS,
            G_ACC2_MARGIN_BITS => G_JORD_ACC2_MARGIN_BITS,
            G_OUT_SHIFT        => G_JORD_OUT_SHIFT_BITS
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
            ERROR_OFLOW_O   => error_oflow_jord
        );

    -- substracts the baseline from the jordanov filtered output
    baseline_i : entity trap_filter.baseline_restorer
        generic map(
            G_DATA_WIDTH   => G_DATA_WIDTH,
            G_LATENCY_SKEW => C_BASE_MOV_LATENCY
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
            DATA_JORD_I  => data_jord_filt,
            BASELINE_I   => data_mov_filt,
            LATCH_TRIG_I => BASELINE_TRIG_I,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_O        => data_filtered,
            ERROR_OFLOW_O => error_oflow_base
        );

end architecture rtl;