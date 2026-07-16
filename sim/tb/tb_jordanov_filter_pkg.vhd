--==============================================================================
--  Package:       tb_jordanov_filter_pkg
--  Description:   Testbench utilities for tb_jordanov_filter.vhd
--  Author:        Aldo Lupio
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tb_jordanov_filter_pkg is

    ----------------------------------------------------------------------------
    -- Testbench Constants
    ----------------------------------------------------------------------------

    -- 125 MHz
    constant CLK_PERIOD : time := 8 ns;

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    -- Bits needed to store the value n
    function clog2(n : natural) return natural;

    ----------------------------------------------------------------------------
    -- Procedures
    ----------------------------------------------------------------------------

    procedure clk_wait(signal clk : in std_logic; cycles : natural);

end package tb_jordanov_filter_pkg;

package body tb_jordanov_filter_pkg is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    function clog2(n : natural) return natural is
        variable r       : natural := 0;
        variable v       : natural := n;
    begin
        while v > 0 loop
            v := v / 2;
            r := r + 1;
        end loop;
        return r;
    end function;

    ----------------------------------------------------------------------------
    -- Procedures
    ----------------------------------------------------------------------------

    procedure clk_wait(signal clk : in std_logic; cycles : natural) is
    begin
        for i in 1 to cycles loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

end package body tb_jordanov_filter_pkg;