--==============================================================================
--  Module:        bram_dp.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       04/08/2026
--  Last Modified: 
--
--  Description:
--  Dual Port BRAM inferrence for output pulse logging.
--
--  Dependencies:
--  trap_filter_pkg
-- 
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity bram_dp is
    generic (
        -- General parameters
        G_ADDR_WIDTH    : natural; -- Width of address
        G_DATA_WIDTH    : natural; -- Width of data
        G_OUTREG_ENABLE : boolean  -- Enable output register
    );
    port (
        ------------------------------------------------------------------------
        -- Clock / Reset
        ------------------------------------------------------------------------
        CLK_I : in std_logic;
        ------------------------------------------------------------------------
        -- Port A
        ------------------------------------------------------------------------
        EN_A_I   : in std_logic;                                    -- Access enable
        RW_A_I   : in std_logic;                                    -- Write/Read
        ADDR_A_I : in std_logic_vector(G_ADDR_WIDTH - 1 downto 0);  -- Address
        DATA_A_I : in std_logic_vector(G_DATA_WIDTH - 1 downto 0);  -- Write data
        DATA_A_O : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Read data
        ------------------------------------------------------------------------
        -- Port B
        ------------------------------------------------------------------------
        EN_B_I   : in std_logic;                                   -- Access enable
        RW_B_I   : in std_logic;                                   -- Write/Read
        ADDR_B_I : in std_logic_vector(G_ADDR_WIDTH - 1 downto 0); -- Address
        DATA_B_I : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Write data
        DATA_B_O : out std_logic_vector(G_DATA_WIDTH - 1 downto 0) -- Read data
    );
end bram_dp;

architecture rtl of bram_dp is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output read data signals
    signal rdata_a : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal rdata_b : std_logic_vector(G_DATA_WIDTH - 1 downto 0);

    -- memory type
    type ram_t is array ((2 ** G_ADDR_WIDTH) - 1 downto 0) of std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal dpram : ram_t;

    -- force Block RAM instead of distributed RAM
    attribute ram_style          : string;
    attribute ram_style of dpram : signal is "block";

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output Assignments
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Main Combinatory Processes
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Main Sequential Processes
    ----------------------------------------------------------------------------

    -- Memory Core Port A
    port_a_access :
    if (G_ADDR_WIDTH > 0) generate
        port_a_core : process (clk_i)
        begin
            if rising_edge(clk_i) then
                -- write
                if (en_a_i = '1') and (rw_a_i = '1') then
                    dpram(to_integer(unsigned(addr_a_i))) <= data_a_i;
                end if;
                -- read
                if (en_a_i = '1') and (rw_a_i = '0') then
                    rdata_a <= dpram(to_integer(unsigned(addr_a_i)));
                end if;
            end if;
        end process port_a_core;
    end generate;

    -- Memory Core Port B
    port_b_access :
    if (G_ADDR_WIDTH > 0) generate
        port_b_core : process (clk_i)
        begin
            if rising_edge(clk_i) then
                -- write
                if (en_b_i = '1') and (rw_b_i = '1') then
                    dpram(to_integer(unsigned(addr_b_i))) <= data_b_i;
                end if;
                -- read
                if (en_b_i = '1') and (rw_b_i = '0') then
                    rdata_b <= dpram(to_integer(unsigned(addr_b_i)));
                end if;
            end if;
        end process port_b_core;
    end generate;

    -- Output register port A enabled
    output_register_a_enabled :
    if (G_OUTREG_ENABLE) generate
        read_outreg_a : process (clk_i)
        begin
            if rising_edge(clk_i) then
                DATA_A_O <= rdata_a;
            end if;
        end process read_outreg_a;
    end generate;

    -- Output register port A disabled
    output_register_a_disabled :
    if (not G_OUTREG_ENABLE) generate
        DATA_A_O <= rdata_a;
    end generate;

    -- Output register port B enabled
    output_register_b_enabled :
    if (G_OUTREG_ENABLE) generate
        read_outreg_b : process (clk_i)
        begin
            if rising_edge(clk_i) then
                DATA_B_O <= rdata_b;
            end if;
        end process read_outreg_b;
    end generate;

    -- Output register port B disabled
    output_register_b_disabled :
    if (not G_OUTREG_ENABLE) generate
        DATA_B_O <= rdata_b;
    end generate;

end rtl;