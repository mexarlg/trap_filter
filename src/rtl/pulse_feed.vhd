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
use trap_filter.pulse_rom_pkg.all;

entity pulse_feed is
    generic (
        G_DATA_WIDTH : natural range 4 to 16 := 14 -- Width of incoming data stream
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
        DATA_O : out std_logic_vector(G_DATA_WIDTH - 1 downto 0)
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
    constant C_PULSE_WIDTH : natural                                      := f_depth_to_width(ROM_DEPTH);
    constant C_ADDR_MAX    : std_logic_vector(C_PULSE_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(ROM_DEPTH - 1, C_PULSE_WIDTH));
    constant C_ADDR_ONE    : std_logic_vector(C_PULSE_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, C_PULSE_WIDTH));
    constant C_ADDR_ZERO   : std_logic_vector(C_PULSE_WIDTH - 1 downto 0) := (others => '0');

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output signals
    signal data : std_logic_vector(G_DATA_WIDTH - 1 downto 0);

    -- intermidiate signals (choose pulse data from pkg constants)
    signal rom_pulse : pulse_rom_t                                  := PULSE_ROM;
    signal addr      : std_logic_vector(C_PULSE_WIDTH - 1 downto 0) := (others => '0');

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    DATA_O <= data;

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
                else
                    addr <= C_ADDR_MAX;
                end if;
            else
                addr <= C_ADDR_ZERO;
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
                data <= std_logic_vector(to_unsigned(rom_pulse(to_integer(unsigned(addr))), G_DATA_WIDTH));
            end if;
        end if;
    end process p_feed;

end architecture rtl;