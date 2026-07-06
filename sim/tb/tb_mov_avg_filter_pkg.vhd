--==============================================================================
--  Package:       tb_mov_avg_filter_pkg
--  Description:   Testbench utilities for tb_mov_avg_filter.vhd
--  Author:        Aldo Lupio
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tb_mov_avg_filter_pkg is

    ----------------------------------------------------------------------------
    -- Testbench Constants
    ----------------------------------------------------------------------------

    -- 125 MHz
    constant CLK_PERIOD : time := 8 ns;

    ----------------------------------------------------------------------------
    -- Procedures
    ----------------------------------------------------------------------------

    procedure clk_wait(signal clk : in std_logic; cycles : natural);

end package tb_mov_avg_filter_pkg;

package body tb_mov_avg_filter_pkg is

    ----------------------------------------------------------------------------
    -- Procedures
    ----------------------------------------------------------------------------

    procedure clk_wait(signal clk : in std_logic; cycles : natural) is
    begin
        for i in 1 to cycles loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

end package body tb_mov_avg_filter_pkg;