--==============================================================================
--  Module:        peak_subsystem.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       03/08/2026
--  Last Modified:
--
--  Description:
--  Subsystem that applies a moving average filter if required and captures 
--  the pulse amplitude and its rise time from triggers.
--
--  Dependencies:
--  trap_filter_pkg.vhd, shift_register.vhd, mov_avg_filter.vhd, pulse_capture.vhd
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity peak_subsystem is
    generic (
        -- Data width parameters
        G_DATA_WIDTH          : natural range 8 to 16 := 14; -- Width of filtered input data
        G_DATA_FILTERED_WIDTH : natural range 9 to 17 := 15; -- Width of filtered data
        -- Time rise parameters
        G_T_RISE_WIDTH           : natural range 8 to 12     := 12;  -- Width of rise time counter
        G_T_RISE_TIMEOUT         : natural range 100 to 4095 := 100; -- Timeout for threshold
        G_T_RISE_DELAY           : natural range 64 to 512   := 300; -- Delay of input data for rise time capture
        G_T_RISE_MOV_DELAY_WIDTH : natural range 3 to 5      := 4;   -- Width of samples averaged for rise time mov avg
        -- Peak moving average params
        G_PEAK_MOV_ENABLE          : natural range 0 to 1 := 1; -- Enable the moving average prefilter of the peak
        G_PEAK_MOV_DELAY_WIDTH     : natural range 3 to 5 := 3; -- Width of samples averaged in the moving average for the peak
        G_PEAK_MOV_ACC_MARGIN_BITS : natural range 2 to 5 := 2  -- Margin bits given to the accumulator inside the moving average for the peak
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
        DATA_I          : in std_logic_vector(G_DATA_WIDTH - 1 downto 0);          -- Input (raw) data
        TRIG_TOP_MID_I  : in std_logic;                                            -- Trigger to capture amplitude at middle of top
        DATA_FILTERED_I : in std_logic_vector(G_DATA_FILTERED_WIDTH - 1 downto 0); -- Input (filtered) data
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        PULSE_AMPLITUDE_O : out std_logic_vector(G_DATA_FILTERED_WIDTH - 1 downto 0); -- Captured data amplitude at the middle of the top
        PULSE_T_RISE_O    : out std_logic_vector(G_T_RISE_WIDTH - 1 downto 0);        -- Captured rise time
        ERROR_OFLOW_O     : out std_logic_vector(1 downto 0)                          -- Overflow flag for accumulator of both moving average filters
    );
end entity peak_subsystem;

architecture rtl of peak_subsystem is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- delay value for peak given to shift register
    constant C_PEAK_MOV_DELAY : natural := 2 ** G_PEAK_MOV_DELAY_WIDTH - 1;

    -- delays for rise time given to shift registers
    constant C_T_RISE_DELAY     : natural := G_T_RISE_DELAY - 1;
    constant C_T_RISE_MOV_DELAY : natural := 2 ** G_T_RISE_MOV_DELAY_WIDTH - 1;

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output signals
    signal pulse_amplitude : std_logic_vector(G_DATA_FILTERED_WIDTH - 1 downto 0); -- pulse amplitude latched
    signal pulse_t_rise    : std_logic_vector(G_T_RISE_WIDTH - 1 downto 0);        -- pulse rise time
    signal error_oflow     : std_logic_vector(1 downto 0);                         -- overflow error of peak subsystem

    -- intermidiate signals for amplitude capture
    signal error_oflow_peak_mov : std_logic;                                            -- overflow flag from peak moving average
    signal data_mov_filt        : std_logic_vector(G_DATA_FILTERED_WIDTH - 1 downto 0); -- data after peak moving average
    signal data_mov_d           : std_logic_vector(G_DATA_FILTERED_WIDTH - 1 downto 0); -- delayed data for peak moving average

    -- intermidiate signals for rise time capture
    signal data_i_d               : std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- delayed input data for rise time
    signal data_i_mov_d           : std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- delayed input data for rise time + moving average delay
    signal data_i_t_rise          : std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- delayed input data averaged for rise time
    signal error_oflow_t_rise_mov : std_logic;                                   -- overflow flag from t_rise moving average

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output Assignments
    ----------------------------------------------------------------------------

    PULSE_AMPLITUDE_O <= pulse_amplitude;
    PULSE_T_RISE_O    <= pulse_t_rise;
    ERROR_OFLOW_O     <= error_oflow;

    ----------------------------------------------------------------------------
    -- Main Combinatory Processes
    ----------------------------------------------------------------------------

    error_oflow <= error_oflow_peak_mov & error_oflow_t_rise_mov;

    ----------------------------------------------------------------------------
    -- Main Sequential Processes
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Instantiation
    ----------------------------------------------------------------------------

    ------------------------------------------------------------------------
    -- Amplitude capture
    ------------------------------------------------------------------------

    -- prefiltering enabled
    g_enable : if G_PEAK_MOV_ENABLE = 1 generate

        -- delay for moving average
        sr_d_i : entity trap_filter.shift_register
            generic map(
                G_DATA_WIDTH  => G_DATA_FILTERED_WIDTH,
                G_DELAY_VALUE => C_PEAK_MOV_DELAY,
                G_REG_INPUT   => 1
            )
            port map(
                CLK_I    => CLK_I,
                RST_N_I  => RST_N_I,
                DATA_I   => DATA_FILTERED_I,
                DATA_D_O => data_mov_d
            );

        -- moving average for amplitude capture at top
        mov_avg_i : entity trap_filter.mov_avg_filter
            generic map(
                -- General parameters
                G_DATA_WIDTH => G_DATA_WIDTH,
                -- Rise time parameters
                G_DELAY_WIDTH     => G_PEAK_MOV_DELAY_WIDTH,
                G_ACC_MARGIN_BITS => G_PEAK_MOV_ACC_MARGIN_BITS,
                G_DATA_I_SIGNED   => 1
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
                DATA_N_I => DATA_FILTERED_I,
                DATA_D_I => data_mov_d,
                ------------------------------------------------------------------------
                -- Outputs
                ------------------------------------------------------------------------
                DATA_FILTERED_O => data_mov_filt,
                ERROR_OFLOW_O   => error_oflow_peak_mov
            );

        -- amplitude capture of filtered pulse
        capture_i : entity trap_filter.pulse_capture
            generic map(
                G_DATA_WIDTH => G_DATA_FILTERED_WIDTH
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
                TRIG_CAPTURE_I => TRIG_TOP_MID_I,
                DATA_I         => data_mov_filt,
                ------------------------------------------------------------------------
                -- Outputs
                ------------------------------------------------------------------------
                DATA_O => pulse_amplitude
            );

    end generate g_enable;

    -- prefiltering disabled
    g_disable : if G_PEAK_MOV_ENABLE = 0 generate

        -- prefiltering disabled, no overflow
        error_oflow_peak_mov <= '0';

        -- amplitude capture of filtered pulse
        capture_i : entity trap_filter.pulse_capture
            generic map(
                G_DATA_WIDTH => G_DATA_FILTERED_WIDTH
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
                TRIG_CAPTURE_I => TRIG_TOP_MID_I,
                DATA_I         => DATA_FILTERED_I,
                ------------------------------------------------------------------------
                -- Outputs
                ------------------------------------------------------------------------
                DATA_O => pulse_amplitude
            );

    end generate g_disable;

    ------------------------------------------------------------------------
    -- Rise time capture
    ------------------------------------------------------------------------

    -- delay of raw pulse for synchronization with measured amplitude
    sr_t_rise_i : entity trap_filter.shift_register
        generic map(
            G_DATA_WIDTH  => G_DATA_WIDTH,
            G_DELAY_VALUE => C_T_RISE_DELAY,
            G_REG_INPUT   => 1
        )
        port map(
            CLK_I    => CLK_I,
            RST_N_I  => RST_N_I,
            DATA_I   => DATA_I,
            DATA_D_O => data_i_d
        );

    -- delay of raw pulse for moving average
    sr_d_t_rise_i : entity trap_filter.shift_register
        generic map(
            G_DATA_WIDTH  => G_DATA_WIDTH,
            G_DELAY_VALUE => C_T_RISE_MOV_DELAY,
            G_REG_INPUT   => 1
        )
        port map(
            CLK_I    => CLK_I,
            RST_N_I  => RST_N_I,
            DATA_I   => data_i_d,
            DATA_D_O => data_i_mov_d
        );

    -- moving average for rise time capture
    mov_avg_t_rise_i : entity trap_filter.mov_avg_filter
        generic map(
            -- General parameters
            G_DATA_WIDTH => G_DATA_WIDTH,
            -- Moving average parameters
            G_DELAY_WIDTH     => G_T_RISE_MOV_DELAY_WIDTH,
            G_ACC_MARGIN_BITS => G_PEAK_MOV_ACC_MARGIN_BITS,
            G_DATA_I_SIGNED   => 0
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
            DATA_N_I => data_i_d,
            DATA_D_I => data_i_mov_d,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_FILTERED_O => data_i_t_rise,
            ERROR_OFLOW_O   => error_oflow_t_rise_mov
        );

    -- rise time capture
    rise_capture_i : entity trap_filter.risetime_capture
        generic map(
            -- General parameters
            G_DATA_WIDTH => G_DATA_WIDTH,
            -- Rise time parameters
            G_T_RISE_WIDTH   => G_T_RISE_WIDTH,
            G_T_RISE_TIMEOUT => G_T_RISE_TIMEOUT
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
            DATA_I            => data_i_t_rise,
            TRIG_TOP_MID_I    => TRIG_TOP_MID_I,
            PULSE_AMPLITUDE_I => pulse_amplitude,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            PULSE_T_RISE_O => pulse_t_rise
        );

end architecture rtl;