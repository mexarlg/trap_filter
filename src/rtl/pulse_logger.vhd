--==============================================================================
--  Module:        pulse_logger.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       04/08/2026
--  Last Modified: 
--
--  Description:
--  Stores and formats the data of an incoming event into a dual port bram.
--
--  Dependencies:
--  trap_filter_pkg
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity pulse_logger is
    generic (
        -- Memory parameters
        G_BRAM_ADDR_WIDTH : natural range 10 to 16 := 10; -- Width of the address of memory (Depth = 2^ADDR_WIDTH)
        G_BRAM_DATA_WIDTH : natural range 28 to 32 := 32; -- Width of single log pulse
        -- Pulse parameters
        G_PULSE_WIDTH  : natural range 9 to 16 := 15; -- Width of the signed captured pulse amplitude
        G_T_RISE_WIDTH : natural range 8 to 12 := 12; -- Width of the unsigned captured pulse rise time
        -- Timestamp parameters
        G_TIMESTAMP_WIDTH : natural range 40 to 48 := 48; -- Width of wide timestamp counter
        G_TIMESTAMP_DIV   : natural range 0 to 6   := 4   -- Bits shifted in timestramp for higher range at lower precision (at 4, LSB = 128 ns at 125MHz)
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
        TRIG_LOG_EVENT_I  : in std_logic;                                     -- Pulse log event
        PULSE_STATE_I     : in std_logic_vector(2 downto 0);                  -- Pulse state (All data valid, amplitude valid, rise time valid)
        PULSE_AMPLITUDE_I : in std_logic_vector(G_PULSE_WIDTH - 1 downto 0);  -- Pulse amplitude
        PULSE_T_RISE_I    : in std_logic_vector(G_T_RISE_WIDTH - 1 downto 0); -- Pulse rise time
        LOG_CLEAR_I       : in std_logic;                                     -- Log Bram restart of pointer
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        BRAM_EN_O             : out std_logic;                                        -- Access enable
        BRAM_RW_O             : out std_logic;                                        -- Write/Read
        BRAM_ADDR_O           : out std_logic_vector(G_BRAM_ADDR_WIDTH - 1 downto 0); -- Address
        BRAM_PULSE_DATA_O     : out std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0); -- Write data
        BRAM_TIMESTAMP_DATA_O : out std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0); -- Write data
        BRAM_FULL_O           : out std_logic;                                        -- BRAM full flag
        TIMESTAMP_CNT_O       : out std_logic_vector(G_TIMESTAMP_WIDTH - 1 downto 0)  -- Timestamp
    );
end entity pulse_logger;

architecture rtl of pulse_logger is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    -- packs the modifiable data outputs into the preallocated pulse log
    function pack_log (
        state : std_logic_vector(2 downto 0);
        amp   : std_logic_vector(G_PULSE_WIDTH - 1 downto 0);
        rise  : std_logic_vector(G_T_RISE_WIDTH - 1 downto 0)
    ) return std_logic_vector is
        variable v : std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0) := (others => '0');
    begin
        -- From rangeable widths to preallocated ones (maximum of allowed range)
        v(C_LOG_AMP_HI downto C_LOG_AMP_LO)       := std_logic_vector(resize(signed(amp), C_LOG_MAX_AMP_WIDTH));
        v(C_LOG_AMP_VALID)                        := state(1);
        v(C_LOG_T_RISE_HI downto C_LOG_T_RISE_LO) := std_logic_vector(resize(unsigned(rise), C_LOG_MAX_T_RISE_WIDTH));
        v(C_LOG_T_RISE_VALID)                     := state(0);
        return v;
    end function pack_log;

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- Maximum pointer value
    constant C_BRAM_PTR_MAX : std_logic_vector(G_BRAM_ADDR_WIDTH - 1 downto 0) := (others => '1');

    -- Counter limits for timestamp
    constant C_TIMESTAMP_CNT_MAX  : std_logic_vector(G_TIMESTAMP_WIDTH - 1 downto 0) := (others => '1');
    constant C_TIMESTAMP_CNT_ZERO : std_logic_vector(G_TIMESTAMP_WIDTH - 1 downto 0) := (others => '0');
    constant C_TIMESTAMP_CNT_ONE  : std_logic_vector(G_TIMESTAMP_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, G_TIMESTAMP_WIDTH));

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- Bram port signals
    signal bram_en             : std_logic;                                        -- enable
    signal bram_rw             : std_logic;                                        -- write (1) / read (0)
    signal bram_addr           : std_logic_vector(G_BRAM_ADDR_WIDTH - 1 downto 0); -- address to write
    signal bram_pulse_data     : std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0); -- pulse data written
    signal bram_full           : std_logic;                                        -- bram fulled flag 
    signal bram_timestamp_data : std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0); -- timestamp data written

    -- delay of + 1 cycle so data is available from capture_system
    signal trig_log_event_i_q : std_logic;

    -- timestamp active since reset
    signal timestamp_cnt : std_logic_vector(G_TIMESTAMP_WIDTH - 1 downto 0); -- wide timestamp counter

    -- pointer inside bram
    signal bram_ptr : unsigned(G_BRAM_ADDR_WIDTH - 1 downto 0); -- pointer of bram

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    BRAM_EN_O             <= bram_en;
    BRAM_RW_O             <= bram_rw;
    BRAM_ADDR_O           <= bram_addr;
    BRAM_PULSE_DATA_O     <= bram_pulse_data;
    BRAM_TIMESTAMP_DATA_O <= bram_timestamp_data;
    BRAM_FULL_O           <= bram_full;
    TIMESTAMP_CNT_O       <= timestamp_cnt;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    -- bram is full
    bram_full <= '1' when bram_ptr = unsigned(C_BRAM_PTR_MAX) else
        '0';

    ----------------------------------------------------------------------------
    -- Main Sequential process
    ----------------------------------------------------------------------------

    -- delay of trig_end_pulse for 2 cycles
    p_reg : process (RST_N_I, CLK_I)
    begin
        if RST_N_I = '0' then
            trig_log_event_i_q <= '0';
        elsif rising_edge(CLK_I) then
            trig_log_event_i_q <= TRIG_LOG_EVENT_I;
        end if;
    end process p_reg;

    -- packs log and issues write
    p_log : process (RST_N_I, CLK_I) is
    begin
        if (RST_N_I = '0') then
            bram_en             <= '0';
            bram_rw             <= '0';
            bram_ptr            <= (others => '0');
            bram_addr           <= (others => '0');
            bram_pulse_data     <= (others => '0');
            bram_timestamp_data <= (others => '0');
        elsif rising_edge(CLK_I) then
            bram_en <= '0';
            bram_rw <= '0';

            -- priority to restart ptr, potential pulse event lost
            if (LOG_CLEAR_I = '1') then
                bram_ptr <= (others => '0');

                -- event to be logged, issue bram enable if not full
            elsif (trig_log_event_i_q = '1') and (bram_full = '0') then
                -- issue write
                bram_en   <= '1';
                bram_rw   <= '1';
                bram_addr <= std_logic_vector(bram_ptr);
                -- data stored
                bram_pulse_data     <= pack_log(PULSE_STATE_I, PULSE_AMPLITUDE_I, PULSE_T_RISE_I);
                bram_timestamp_data <= timestamp_cnt(G_BRAM_DATA_WIDTH + G_TIMESTAMP_DIV - 1 downto G_TIMESTAMP_DIV);
                -- ptr increase
                bram_ptr <= bram_ptr + 1;
            end if;
        end if;
    end process p_log;

    -- timestamp counter that latches at maximum
    p_timestamp : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            timestamp_cnt <= C_TIMESTAMP_CNT_ZERO;
        elsif rising_edge(CLK_I) then
            if (unsigned(timestamp_cnt) < unsigned(C_TIMESTAMP_CNT_MAX)) then
                timestamp_cnt <= std_logic_vector(unsigned(timestamp_cnt) + unsigned(C_TIMESTAMP_CNT_ONE));
            end if;
        end if;
    end process p_timestamp;

end architecture rtl;