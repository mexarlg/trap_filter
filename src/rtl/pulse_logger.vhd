--==============================================================================
--  Module:        pulse_logger.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       04/08/2026
--  Last Modified: 
--
--  Description:
--  Stores and formats the data regarding each valid pulse into a dual port bram.
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
        -- Inputs
        ------------------------------------------------------------------------
        PULSE_VALID_I    : in std_logic;                                     -- Pulse is valid
        PULSE_CAPTURED_I : in std_logic_vector(G_PULSE_WIDTH - 1 downto 0);  -- Pulse amplitude
        PULSE_T_RISE_I   : in std_logic_vector(G_T_RISE_WIDTH - 1 downto 0); -- Pulse rise time
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        BRAM_EN_O             : out std_logic;                                        -- Access enable
        BRAM_RW_O             : out std_logic;                                        -- Write/Read
        BRAM_ADDR_O           : out std_logic_vector(G_BRAM_ADDR_WIDTH - 1 downto 0); -- Address
        BRAM_PULSE_DATA_O     : out std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0); -- Write data
        BRAM_TIMESTAMP_DATA_O : out std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0); -- Write data
        TIMESTAMP_CNT_O       : out std_logic_vector(G_TIMESTAMP_WIDTH - 1 downto 0)  -- Timestamp
    );
end entity pulse_logger;

architecture rtl of pulse_logger is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    -- packs the modifiable data outputs into the preallocated pulse log
    function pack_log (
        amp  : std_logic_vector(G_PULSE_WIDTH - 1 downto 0);
        rise : std_logic_vector(G_T_RISE_WIDTH - 1 downto 0)
    ) return std_logic_vector is
        variable v : std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0) := (others => '0');
    begin
        -- From rangeable widths to preallocated ones (maximum of allowed range)
        v(C_LOG_AMP_HI downto C_LOG_AMP_LO)       := std_logic_vector(resize(signed(amp), C_LOG_MAX_AMP_WIDTH));
        v(C_LOG_T_RISE_HI downto C_LOG_T_RISE_LO) := std_logic_vector(resize(unsigned(rise), C_LOG_MAX_T_RISE_WIDTH));
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
    signal bram_timestamp_data : std_logic_vector(G_BRAM_DATA_WIDTH - 1 downto 0); -- timestamp data written

    -- timestamp active since reset
    signal timestamp_cnt : std_logic_vector(G_TIMESTAMP_WIDTH - 1 downto 0); -- timestamp written

    -- logic signals
    signal bram_ptr  : unsigned(G_BRAM_ADDR_WIDTH - 1 downto 0); -- pointer of bram
    signal bram_full : std_logic;                                -- bram fullfilled 

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

            -- pulse is valid, issue log while there is space
            if (PULSE_VALID_I = '1') and (bram_full = '0') then
                -- issue write
                bram_en   <= '1';
                bram_rw   <= '1';
                bram_addr <= std_logic_vector(bram_ptr);
                -- data stored
                bram_pulse_data     <= pack_log(PULSE_CAPTURED_I, PULSE_T_RISE_I);
                bram_timestamp_data <= timestamp_cnt;
                -- ptr increase
                bram_ptr <= bram_ptr + 1;
            end if;
        end if;
    end process p_log;

    -- timestamp enabled
    g_time_en : if G_TIMESTAMP_EN = 1 generate

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

    end generate g_time_en;

    -- timestamp disabled
    g_time_dis : if G_TIMESTAMP_EN = 0 generate
        timestamp_cnt <= C_TIMESTAMP_CNT_ZERO;
    end generate g_time_dis;

end architecture rtl;