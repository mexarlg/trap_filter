--==============================================================================
--  Module:        logger_subsystem.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       03/08/2026
--  Last Modified:
--
--  Description:
--  Subsystem that logs the output data of a valid pulse into a BRAM.
--
--  Dependencies:
--  trap_filter_pkg.vhd, bram_dp.vhd, pulse_logger.vhd
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity logger_subsystem is
    generic (
        -- Memory parameters
        G_BRAM_ADDR_WIDTH : natural range 10 to 16 := 10; -- Width of the address of memory (Depth = 2^ADDR_WIDTH)
        G_BRAM_DATA_WIDTH : natural range 28 to 32 := 32; -- Width of single log pulse
        -- Pulse parameters
        G_PULSE_WIDTH  : natural range 9 to 16 := 15; -- Width of the signed captured pulse amplitude
        G_T_RISE_WIDTH : natural range 8 to 12 := 12; -- Width of the unsigned captured pulse rise time
        -- Timestamp parameters
        G_TIMESTAMP_EN    : natural range 0 to 1   := 1; -- Enable of timestamp
        G_TIMESTAMP_WIDTH : natural range 24 to 32 := 32 -- Width of timestamp
    );
    port (
        ------------------------------------------------------------------------
        -- Clock / Reset
        ------------------------------------------------------------------------
        CLK_I   : in std_logic;
        RST_N_I : in std_logic;
        ------------------------------------------------------------------------
        -- Pulse inputs
        ------------------------------------------------------------------------
        PULSE_VALID_I    : in std_logic;                                     -- Pulse is valid
        PULSE_CAPTURED_I : in std_logic_vector(G_PULSE_WIDTH - 1 downto 0);  -- Pulse amplitude
        PULSE_T_RISE_I   : in std_logic_vector(G_T_RISE_WIDTH - 1 downto 0); -- Pulse rise time
        ------------------------------------------------------------------------
        -- Memory inputs
        ------------------------------------------------------------------------
        BRAM_B_EN_I   : in std_logic;                                        -- Port B enable
        BRAM_B_RW_I   : in std_logic;                                        -- Port B read/write
        BRAM_B_ADDR_I : in std_logic_vector(G_BRAM_ADDR_WIDTH - 1 downto 0); -- Port B address
        ------------------------------------------------------------------------
        -- Memory Outputs
        ------------------------------------------------------------------------
        BRAM_B_PULSE_DATA_O : out std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0); -- Pulse Bram port B read data
        BRAM_B_TIME_DATA_O  : out std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0); -- Timestamp Bram port B read data
        TIME_CNT_O          : out std_logic_vector(G_TIMESTAMP_WIDTH - 1 downto 0)  -- Timestamp counter
    );
end entity logger_subsystem;

architecture rtl of logger_subsystem is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- logger to bram port A connection signals
    signal bram_a_en                  : std_logic;                                        -- enable write for port A of Brams
    signal bram_a_rw                  : std_logic;                                        -- write operation for port A of Brams
    signal bram_a_addr                : std_logic_vector(G_BRAM_ADDR_WIDTH - 1 downto 0); -- address to log data in Brams
    signal bram_a_pulse_data_wr       : std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0); -- logger to pulse bram port A written data
    signal bram_a_timestamp_data_wr   : std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0); -- logger to time bram port A written data
    signal bram_a_pulse_data_open     : std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0); -- unused pulse bram port A read data
    signal bram_a_timestamp_data_open : std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0); -- unused time bram port A read data

    -- port B Bram connection signals
    signal bram_b_data_open         : std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0); -- unused write data from port B
    signal bram_b_pulse_data_rd     : std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0); -- data read from port B of pulse bram
    signal bram_b_timestamp_data_rd : std_logic_vector(G_TIMESTAMP_WIDTH - 1 downto 0); -- data read from port B of time bram

    -- output timestamp
    signal timestamp_cnt : std_logic_vector(G_TIMESTAMP_WIDTH - 1 downto 0); -- stream of timestamp counter

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output Assignments
    ----------------------------------------------------------------------------

    BRAM_B_PULSE_DATA_O <= bram_b_pulse_data_rd;
    BRAM_B_TIME_DATA_O  <= bram_b_timestamp_data_rd;
    TIME_CNT_O          <= timestamp_cnt;

    ----------------------------------------------------------------------------
    -- Main Combinatory Processes
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Main Sequential Processes
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Instantiation
    ----------------------------------------------------------------------------

    -- formats data into bram signals
    logger_i : entity trap_filter.pulse_logger
        generic map(
            -- Memory parameters
            G_BRAM_ADDR_WIDTH => G_BRAM_ADDR_WIDTH,
            G_BRAM_DATA_WIDTH => G_BRAM_DATA_WIDTH,
            -- Pulse parameters
            G_PULSE_WIDTH  => G_PULSE_WIDTH,
            G_T_RISE_WIDTH => G_T_RISE_WIDTH,
            -- Timestamp parameters
            G_TIMESTAMP_EN    => G_TIMESTAMP_EN,
            G_TIMESTAMP_WIDTH => G_TIMESTAMP_WIDTH
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
            PULSE_VALID_I    => PULSE_VALID_I,
            PULSE_CAPTURED_I => PULSE_CAPTURED_I,
            PULSE_T_RISE_I   => PULSE_T_RISE_I,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            BRAM_EN_O             => bram_a_en,
            BRAM_RW_O             => bram_a_rw,
            BRAM_ADDR_O           => bram_a_addr,
            BRAM_PULSE_DATA_O     => bram_a_pulse_data_wr,
            BRAM_TIMESTAMP_DATA_O => bram_a_timestamp_data_wr,
            TIMESTAMP_CNT_O       => timestamp_cnt
        );

    -- Dual Port BRAM for pulse data logger
    pulse_bram_i : entity trap_filter.bram_dp
        generic map(
            -- Memory parameters
            G_ADDR_WIDTH    => G_BRAM_ADDR_WIDTH,
            G_DATA_WIDTH    => G_BRAM_DATA_WIDTH,
            G_OUTREG_ENABLE => True
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I => CLK_I,
            ------------------------------------------------------------------------
            -- Port A (pulse_logger writes)
            ------------------------------------------------------------------------
            EN_A_I   => bram_a_en,
            RW_A_I   => bram_a_rw,
            ADDR_A_I => bram_a_addr,
            DATA_A_I => bram_a_pulse_data_wr,
            DATA_A_O => bram_a_pulse_data_open,
            ------------------------------------------------------------------------
            -- Port B (external reads)
            ------------------------------------------------------------------------
            EN_B_I   => BRAM_B_EN_I,
            RW_B_I   => BRAM_B_RW_I,
            ADDR_B_I => BRAM_B_ADDR_I,
            DATA_B_I => bram_b_data_open,
            DATA_B_O => bram_b_pulse_data_rd
        );

    -- timestamp enabled
    g_time_en : if G_TIMESTAMP_EN = 1 generate

        -- Timestamp log Dual Port BRAM
        time_bram_i : entity trap_filter.bram_dp
            generic map(
                -- Memory parameters
                G_ADDR_WIDTH    => G_BRAM_ADDR_WIDTH,
                G_DATA_WIDTH    => G_TIMESTAMP_WIDTH,
                G_OUTREG_ENABLE => True
            )
            port map(
                ------------------------------------------------------------------------
                -- Clock / Reset
                ------------------------------------------------------------------------
                CLK_I => CLK_I,
                ------------------------------------------------------------------------
                -- Port A (pulse_logger writes)
                ------------------------------------------------------------------------
                EN_A_I   => bram_a_en,
                RW_A_I   => bram_a_rw,
                ADDR_A_I => bram_a_addr,
                DATA_A_I => bram_a_timestamp_data_wr,
                DATA_A_O => bram_a_timestamp_data_open,
                ------------------------------------------------------------------------
                -- Port B (external reads)
                ------------------------------------------------------------------------
                EN_B_I   => BRAM_B_EN_I,
                RW_B_I   => BRAM_B_RW_I,
                ADDR_B_I => BRAM_B_ADDR_I,
                DATA_B_I => bram_b_data_open,
                DATA_B_O => bram_b_timestamp_data_rd
            );

    end generate g_time_en;

end architecture rtl;