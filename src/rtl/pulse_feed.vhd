--==============================================================================
--  Module:        pulse_feed.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       23/07/2026
--  Last Modified: 
--
--  Description:
--  Module that takes data from a ROM to feed it sequentially with the clk,
--  simulating the feed of adc data to the trap_subsystem
-- 
--  
--
--  Dependencies:
--  pulse_data_pkg
-- 
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;
use trap_filter.pulse_data_pkg.all;

entity pulse_feed is
    generic (
        G_DATA_WIDTH  : natural range 4 to 16 := 14; -- Width of incoming data stream (ADC Magnitude resolution)
        G_PULSE_WIDTH : natural range 7 to 12 := 10  -- Width needed for incoming number of samples
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
        CE_I : in std_logic;
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        DATA_O       : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        DATA_VALID_O : out std_logic
    );
end entity pulse_feed;

architecture rtl of pulse_feed is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- Address limits
    constant C_ADDR_MAX  : std_logic_vector(G_PULSE_WIDTH - 1 downto 0) := (others => '1');
    constant C_ADDR_ONE  : std_logic_vector(G_PULSE_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, G_PULSE_WIDTH));
    constant C_ADDR_ZERO : std_logic_vector(G_PULSE_WIDTH - 1 downto 0) := (others => '0');

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output signals
    signal data       : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_valid : std_logic;

    -- intermidiate signals
    signal rom_pulse : mem_t                                        := C_INIT_PULSE;
    signal addr      : std_logic_vector(G_PULSE_WIDTH - 1 downto 0) := (others => '0');
begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    DATA_O       <= data;
    DATA_VALID_O <= data_valid;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    -- address sequence (locks at last address once its done)
    p_addr : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            addr <= C_ADDR_ZERO;
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                if (unsigned(addr) < unsigned(C_ADDR_MAX)) then
                    addr <= std_logic_vector(unsigned(addr) + unsigned(C_ADDR_ONE));
                end if;
            end if;
        end if;
    end process p_addr;

    -- feeds sequentially with CE the data
    p_feed : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            data <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                data <= rom_pulse(to_integer(unsigned(addr)));
            end if;
        end if;
    end process p_feed;

    -- ff
    p_valid : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            data_valid <= '0';
        elsif rising_edge(CLK_I) then
            data_valid <= CE_I;
        end if;
    end process p_valid;

end architecture rtl;