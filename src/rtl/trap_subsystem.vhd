--==============================================================================
--  Module:        trap_subsystem.vhd
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

entity trap_subsystem is
    generic (
        -- Data parameters
        G_DATA_WIDTH : natural range 8 to 16 := 14; -- Width of incoming data stream (ADC Magnitude resolution)
        -- Jordanov params
        G_K_RISE_WIDTH : natural range 2 to 8     := 8;     -- Width of delay needed for rising time (all bits -> '1' for multiple of 2^N)
        G_M_FLAT_WIDTH : natural range 2 to 8     := 8;     -- Width of delay needed for flat top (all bits -> '1' for multiple of 2^N)
        G_M_VALUE      : natural range 0 to 65535 := 39992; -- Width of decay exp factor (big "M_exp", 12 bits mag + 4 bits fraction)
        G_M_FRAC_WIDTH : natural range 1 to 4     := 4;     -- Width of decay exp factor for its fraction (big "M_exp")
        -- Jordanov fixed point params
        G_DIFF_MARGIN_BITS : natural range 1 to 3  := 3; -- Width of margin given to the delayed difference
        G_ACC1_MARGIN_BITS : natural range 1 to 2  := 2; -- Width of margin given to the 1st accumulator
        G_ACC2_MARGIN_BITS : natural range 0 to 1  := 1; -- Width of margin given to the 2nd accumulator
        G_OUT_SHIFT        : natural range 0 to 24 := 1; -- Width of margin given to the 2nd accumulator
        -- Moving average params
        G_DELAY_WIDTH     : natural range 0 to 8 := 4; -- Width of samples averaged (all bits -> '1' for multiple of 2^N)
        G_ACC_MARGIN_BITS : natural range 2 to 5 := 2  -- Width of margin given to the accumulator
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
        CE_I            : in std_logic;                                   -- clock enable
        DATA_I          : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- input data stream
        BASELINE_TRIG_I : in std_logic;                                   -- baseline latch trigger
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        DATA_FILTERED_O       : out std_logic_vector(G_DATA_WIDTH downto 0); -- Trapezoidal output (signed)
        DATA_FILTERED_VALID_O : out std_logic;                               -- Trapezoidal valid
        STAT_ERROR_O          : out std_logic_vector(5 downto 0)             -- error status
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
    constant C_K_RISE_DELAY : natural := 2 ** G_K_RISE_WIDTH;             -- k  = 2^K_RISE_WIDTH
    constant C_M_FLAT_DELAY : natural := 2 ** G_M_FLAT_WIDTH;             -- m  = 2^M_FLAT_WIDTH
    constant C_L_DELAY      : natural := C_K_RISE_DELAY + C_M_FLAT_DELAY; -- l  = k + m
    constant C_KL_DELAY     : natural := C_K_RISE_DELAY + C_L_DELAY;      -- k + l = 2k + m
    constant C_D_DELAY      : natural := 2 ** G_DELAY_WIDTH;              -- Value of delay

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output signals
    signal data_filtered       : std_logic_vector(G_DATA_WIDTH downto 0); -- Trapezoidal output (signed)
    signal data_filtered_valid : std_logic;                               -- Trapezoidal valid
    signal stat_error          : std_logic_vector(5 downto 0);            -- error status

    -- intermidiate data after delays
    signal data_n       : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_jord_k  : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_jord_l  : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_jord_kl : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_mov_d   : std_logic_vector(G_DATA_WIDTH - 1 downto 0);

    -- intermidiate data after jordanov and mov avg filters
    signal data_jord_filt : std_logic_vector(G_DATA_WIDTH downto 0);
    signal data_mov_filt  : std_logic_vector(G_DATA_WIDTH - 1 downto 0);

    -- ready signals for delays
    signal delay_jord_ready : std_logic_vector(2 downto 0);
    signal delay_mov_ready  : std_logic;

    -- valid signals
    signal data_jord_valid : std_logic;
    signal data_mov_valid  : std_logic;

    -- overflow and synchronization error signals
    signal error_oflow_jord : std_logic_vector(1 downto 0);
    signal error_oflow_mov  : std_logic;
    signal error_oflow_base : std_logic;
    signal error_sync       : std_logic_vector(1 downto 0);

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    DATA_FILTERED_O       <= data_filtered;
    DATA_FILTERED_VALID_O <= data_filtered_valid;
    STAT_ERROR_O          <= stat_error;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    -- error group
    stat_error(5 downto 4) <= error_oflow_jord;
    stat_error(3)          <= error_oflow_mov;
    stat_error(2)          <= error_oflow_base;
    stat_error(1 downto 0) <= error_sync;

    data_filtered_valid <= data_jord_valid;

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    sr_d_i : entity trap_filter.delay_unit_sr
        generic map(
            G_DATA_WIDTH  => G_DATA_WIDTH,
            G_DELAY_VALUE => C_D_DELAY,
            G_DATA_SIGNED => 0
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
            CE_I   => CE_I,
            DATA_I => DATA_I,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_N_O       => open,
            DATA_D_O       => data_mov_d,
            DATA_D_VALID_O => delay_mov_ready
        );

    sr_k : entity trap_filter.delay_unit_sr
        generic map(
            G_DATA_WIDTH  => G_DATA_WIDTH,
            G_DELAY_VALUE => C_K_RISE_DELAY,
            G_DATA_SIGNED => 0
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
            CE_I   => CE_I,
            DATA_I => DATA_I,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_N_O       => open,
            DATA_D_O       => data_jord_k,
            DATA_D_VALID_O => delay_jord_ready(2)
        );

    sr_l : entity trap_filter.delay_unit_sr
        generic map(
            G_DATA_WIDTH  => G_DATA_WIDTH,
            G_DELAY_VALUE => C_L_DELAY,
            G_DATA_SIGNED => 0
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
            CE_I   => CE_I,
            DATA_I => DATA_I,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_N_O       => open,
            DATA_D_O       => data_jord_l,
            DATA_D_VALID_O => delay_jord_ready(1)
        );

    sr_kl : entity trap_filter.delay_unit_sr
        generic map(
            G_DATA_WIDTH  => G_DATA_WIDTH,
            G_DELAY_VALUE => C_KL_DELAY,
            G_DATA_SIGNED => 0
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
            CE_I   => CE_I,
            DATA_I => DATA_I,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_N_O       => data_n,
            DATA_D_O       => data_jord_kl,
            DATA_D_VALID_O => delay_jord_ready(0)
        );

    u_valid_i : entity trap_filter.valid_tracker
        generic map(
            G_JORD_LATENCY => 6,
            G_JORD_K_WIDTH => G_K_RISE_WIDTH,
            G_JORD_M_WIDTH => G_M_FLAT_WIDTH,
            G_MOV_LATENCY  => 2,
            G_MOV_D_WIDTH  => G_DELAY_WIDTH
        )
        port map(
            CLK_I              => CLK_I,
            RST_N_I            => RST_N_I,
            CE_I               => CE_I,
            DELAY_JORD_READY_I => delay_jord_ready,
            DELAY_MOV_READY_I  => delay_mov_ready,
            DATA_JORD_VALID_O  => data_jord_valid,
            DATA_MOV_VALID_O   => data_mov_valid,
            ERROR_SYNC_O       => error_sync
        );

    mov_avg_i : entity trap_filter.mov_avg_filter
        generic map(
            G_DATA_WIDTH      => G_DATA_WIDTH,
            G_DELAY_WIDTH     => G_DELAY_WIDTH,
            G_ACC_MARGIN_BITS => G_ACC_MARGIN_BITS,
            G_DATA_I_SIGNED   => 0
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
            CE_I     => CE_I,
            DATA_N_I => data_n,
            DATA_D_I => data_mov_d,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_FILTERED_O => data_mov_filt,
            ERROR_OFLOW_O   => error_oflow_mov
        );

    jord_i : entity trap_filter.jordanov_filter
        generic map(
            -- Jordanov parameters
            G_DATA_WIDTH   => G_DATA_WIDTH,
            G_K_RISE_WIDTH => G_K_RISE_WIDTH,
            G_M_FLAT_WIDTH => G_M_FLAT_WIDTH,
            -- Exponential decay
            G_M_VALUE      => G_M_VALUE,
            G_M_FRAC_WIDTH => G_M_FRAC_WIDTH,
            -- Fixed point params
            G_DIFF_MARGIN_BITS => G_DIFF_MARGIN_BITS,
            G_ACC1_MARGIN_BITS => G_ACC1_MARGIN_BITS,
            G_ACC2_MARGIN_BITS => G_ACC2_MARGIN_BITS,
            G_OUT_SHIFT        => G_OUT_SHIFT
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
            CE_I      => CE_I,
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
            ERROR_OFLOW_O => error_oflow_jord
        );

    baseline_i : entity trap_filter.baseline_restorer
        generic map(
            G_DATA_WIDTH   => G_DATA_WIDTH,
            G_JORD_LATENCY => 6,
            G_MOV_LATENCY  => 2
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
            CE_I         => CE_I,
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