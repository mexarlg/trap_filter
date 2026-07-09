--==============================================================================
--  Module:        delay_unit_sr.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       09/07/2026
--  Last Modified: 
--
--  Description:
--  Delay unit that implements shift register logic for the mov_avg_filter delay
--
--  Dependencies:
--  None
-- 
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity delay_unit_sr is
    generic (
        G_DATA_WIDTH  : natural range 4 to 16 := 14; -- Width of incoming data stream (ADC Magnitude resolution)
        G_DELAY_WIDTH : natural range 0 to 10 := 4;  -- Width of samples averaged (all bits -> '1' for multiple of 2^N)
        G_DATA_SIGNED : natural range 0 to 1  := 0   -- Data signed (1) or unsigned (0) -> DATA_OUT_WIDTH = DATA_WIDTH + DATA_SIGNED
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
        CE_I     : in std_logic;                                                   -- Chip enable of delay unit
        DATA_N_I : in std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0); -- Input data at sample N
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        DATA_N_O             : out std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0); -- Output data at sample N
        DATA_DELAYED_O       : out std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0); -- Output delayed data for current data_n
        DATA_DELAYED_VALID_O : out std_logic                                                    -- Delayed data is valid (completely filled)
    );
end entity delay_unit_sr;

architecture rtl of delay_unit_sr is

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- Value of delay in clk samples
    constant C_DELAY_VALUE : integer := 2 ** G_DELAY_WIDTH;

    -- Expected limits for a possible delay count saveguard (1 bit more of delay width)
    constant C_CNT_DEL_MAX  : std_logic_vector(G_DELAY_WIDTH - 1 downto 0) := (others => '1');
    constant C_CNT_DEL_ONE  : std_logic_vector(G_DELAY_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, G_DELAY_WIDTH));
    constant C_CNT_DEL_ZERO : std_logic_vector(G_DELAY_WIDTH - 1 downto 0) := (others => '0');

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- Output signals
    signal data_n             : std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0);
    signal data_delayed       : std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0);
    signal data_delayed_valid : std_logic;

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    DATA_N_O             <= data_n;
    DATA_DELAYED_O       <= data_delayed;
    DATA_DELAYED_VALID_O <= data_delayed_valid;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

end architecture rtl;