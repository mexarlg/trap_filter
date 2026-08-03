--==============================================================================
--  Module:        peak_subsystem.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       03/08/2026
--  Last Modified:
--
--  Description:
--  Subsystem that ensures the accuracy and validity of the pulse amplitude.
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
        -- Data parameters
        G_DATA_WIDTH : natural range 8 to 16 := 15; -- Width of filtered input data
        -- Peak moving average params
        G_MOV_ENABLE          : natural range 0 to 1 := 1; -- Enable the moving average prefilter of the peak
        G_MOV_D_WIDTH         : natural range 2 to 8 := 3; -- Width of samples averaged in the moving average for the peak
        G_MOV_ACC_MARGIN_BITS : natural range 2 to 5 := 2  -- Margin bits given to the accumulator inside the moving average for the peak
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
        VALID_PILEUP_I : in std_logic;                                   -- Pulse is valid regarding pileup
        VALID_DELAY_I  : in std_logic;                                   -- Pulse is valid regarding filled delays
        ERROR_OFLOW_I  : in std_logic_vector(7 downto 0);                -- Overflow errors of trap/trig subsystems
        TRIG_CAPTURE_I : in std_logic;                                   -- Trigger to capture amplitude at middle of flat
        DATA_I         : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Input (filtered) data
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        DATA_O        : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Captured data amplitude at the middle of the top
        VALID_O       : out std_logic;                                   -- Trigger that pulse is valid (pileup, delays, overflow)
        ERROR_OFLOW_O : out std_logic                                    -- Overflow flag for accumulator of moving average
    );
end entity peak_subsystem;

architecture rtl of peak_subsystem is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- delay value for moving average filter
    constant C_MOV_D_DELAY : natural := 2 ** G_MOV_D_WIDTH - 1;

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output signals
    signal valid : std_logic;                                   -- pulse is valid
    signal data  : std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- pulse amplitude latched

    -- intermidiate signals
    signal error_oflow_mov : std_logic;                                   -- overflow flag from peak moving average
    signal data_mov_filt   : std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- data after peak moving average
    signal data_mov_d      : std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- delayed data for peak moving average

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output Assignments
    ----------------------------------------------------------------------------

    DATA_O        <= data;
    VALID_O       <= valid;
    ERROR_OFLOW_O <= error_oflow_mov;

    ----------------------------------------------------------------------------
    -- Main Combinatory Processes
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Main Sequential Processes
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Instantiation
    ----------------------------------------------------------------------------

    -- prefiltering enabled
    g_enable : if G_MOV_ENABLE = 1 generate

        -- delay for moving average
        sr_d_i : entity trap_filter.shift_register
            generic map(
                G_DATA_WIDTH  => G_DATA_WIDTH,
                G_DELAY_VALUE => C_MOV_D_DELAY,
                G_REG_INPUT   => 1
            )
            port map(
                CLK_I    => CLK_I,
                RST_N_I  => RST_N_I,
                DATA_I   => DATA_I,
                DATA_D_O => data_mov_d
            );

        -- moving average for amplitude capture at top
        mov_avg_i : entity trap_filter.mov_avg_filter
            generic map(
                G_DATA_WIDTH      => G_DATA_WIDTH - 1,
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
                -- Inputs
                ------------------------------------------------------------------------
                DATA_N_I => DATA_I,
                DATA_D_I => data_mov_d,
                ------------------------------------------------------------------------
                -- Outputs
                ------------------------------------------------------------------------
                DATA_FILTERED_O => data_mov_filt,
                ERROR_OFLOW_O   => error_oflow_mov
            );

        -- amplitude capture of filtered pulse
        capture_i : entity trap_filter.pulse_capture
            generic map(
                G_DATA_WIDTH => G_DATA_WIDTH
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
                VALID_PILEUP_I => VALID_PILEUP_I,
                VALID_DELAY_I  => VALID_DELAY_I,
                ERROR_OFLOW_I  => ERROR_OFLOW_I & error_oflow_mov,
                TRIG_CAPTURE_I => TRIG_CAPTURE_I,
                DATA_I         => data_mov_filt,
                ------------------------------------------------------------------------
                -- Outputs
                ------------------------------------------------------------------------
                DATA_O  => data,
                VALID_O => valid
            );

    end generate g_enable;

    -- prefiltering disabled
    g_disable : if G_MOV_ENABLE = 0 generate

        -- prefiltering disabled, no overflow
        error_oflow_mov <= '0';

        -- amplitude capture of filtered pulse
        capture_i : entity trap_filter.pulse_capture
            generic map(
                G_DATA_WIDTH => G_DATA_WIDTH
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
                VALID_PILEUP_I => VALID_PILEUP_I,
                VALID_DELAY_I  => VALID_DELAY_I,
                ERROR_OFLOW_I  => ERROR_OFLOW_I & error_oflow_mov,
                TRIG_CAPTURE_I => TRIG_CAPTURE_I,
                DATA_I         => DATA_I,
                ------------------------------------------------------------------------
                -- Outputs
                ------------------------------------------------------------------------
                DATA_O  => data,
                VALID_O => valid
            );

    end generate g_disable;

end architecture rtl;