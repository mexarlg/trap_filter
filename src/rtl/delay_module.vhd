--==============================================================================
--  Module:        delay_module.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       21/07/2026
--  Last Modified:
--
--  Description:
--  Top wrapper for the delay shift registers of the trapezoidal subsystem.
--  Jordanov delays are chained in series, all sharing one input timeline, which is registered along the taps.
--  Each registration has an overhead of 1 cycle, and these are accounted for in the delays of the shift_register modules
--  Moving average delay is fed from trapezoidal output.
--
--      data_n  = DATA_I delayed by C_PULSE_DELAY
--      data_k  = DATA_I delayed by k + C_PULSE_DELAY
--      data_l  = DATA_I delayed by l + C_PULSE_DELAY
--      data_kl = DATA_I delayed by (k+l) + C_PULSE_DELAY
--      data_mov_d = DATA_JORD_FILT_I delayed by d
--
--  Dependencies:
--  trap_filter_pkg.vhd, shift_register.vhd
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity delay_module is
    generic (
        G_DATA_WIDTH : natural range 4 to 16 := 14; -- input data width (unsigned)
        -- Enable and common delay
        G_COMMON_DELAY_EN : natural range 0 to 1    := 0;  -- Enables a common delay
        G_COMMON_DELAY    : natural range 4 to 4096 := 16; -- Common delay (pulse detection)
        -- Enable and jordanov specific delays
        G_JORD_DELAY_EN : natural range 0 to 1    := 0;   -- Enables jordanov specific delays
        G_JORD_K_DELAY  : natural range 4 to 4096 := 64;  -- k  = 2^k_w
        G_JORD_L_DELAY  : natural range 4 to 4096 := 192; -- l  = k + m
        G_JORD_KL_DELAY : natural range 4 to 4096 := 256; -- kl = k + l
        -- Enable and mov avg delay from jordanov data
        G_MOV_DELAY_EN : natural range 0 to 1    := 0; -- Enables moving average specific delay
        G_MOV_D_DELAY  : natural range 4 to 4096 := 16 -- Moving average depth
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
        DATA_I           : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Raw unsigned input
        DATA_JORD_FILT_I : in std_logic_vector(G_DATA_WIDTH downto 0);     -- Signed trapezoidal stream
        ------------------------------------------------------------------------
        -- Delayed Data Outputs
        ------------------------------------------------------------------------
        DATA_N_O     : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Pulse delayed input (to filters)
        DATA_K_O     : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- v[n-k]  (+ pulse delay)
        DATA_L_O     : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- v[n-l]  (+ pulse delay)
        DATA_KL_O    : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- v[n-k-l](+ pulse delay)
        DATA_MOV_D_O : out std_logic_vector(G_DATA_WIDTH downto 0)      -- Signed mov avg delay (from jord filter)
    );
end entity delay_module;

architecture rtl of delay_module is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- delay values taking into account shift register latency
    constant C_PULSE_DELAY   : natural := G_COMMON_DELAY - 1;
    constant C_JORD_DELAY_K  : natural := G_JORD_K_DELAY - 1;
    constant C_JORD_DELAY_L  : natural := G_JORD_L_DELAY - G_JORD_K_DELAY - 1;
    constant C_JORD_DELAY_KL : natural := G_JORD_KL_DELAY - G_JORD_L_DELAY - 1;
    constant C_MOV_DELAY_D   : natural := G_MOV_D_DELAY - 1;

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- delayed outputs (mov avg is signed)
    signal data_n   : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_k   : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_l   : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_kl  : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_mov : std_logic_vector(G_DATA_WIDTH downto 0);

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    assert (G_JORD_L_DELAY > G_JORD_K_DELAY + 1) and (G_JORD_KL_DELAY > G_JORD_L_DELAY + 1)
    report "delay_module: Jordanov tap spacing must exceed 1 cycle for chained segments"
        severity failure;

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    DATA_N_O     <= data_n;
    DATA_K_O     <= data_k;
    DATA_L_O     <= data_l;
    DATA_KL_O    <= data_kl;
    DATA_MOV_D_O <= data_mov;

    ----------------------------------------------------------------------------
    -- Pulse delayed input (common delay D)
    ----------------------------------------------------------------------------

    g_common_en : if G_COMMON_DELAY_EN = 1 generate

        sr_n : entity trap_filter.shift_register
            generic map(
                G_DATA_WIDTH  => G_DATA_WIDTH,
                G_DELAY_VALUE => C_PULSE_DELAY,
                G_REG_INPUT   => 1
            )
            port map(
                CLK_I    => CLK_I,
                RST_N_I  => RST_N_I,
                DATA_I   => DATA_I,
                DATA_D_O => data_n
            );

    end generate g_common_en;

    g_common_dis : if G_COMMON_DELAY_EN = 0 generate

        data_n <= DATA_I;

    end generate g_common_dis;

    ----------------------------------------------------------------------------
    -- Jordanov delays: data_n -> [k] -> [l - k] -> [kl - l]
    ----------------------------------------------------------------------------

    g_jord_en : if G_JORD_DELAY_EN = 1 generate

        sr_k : entity trap_filter.shift_register
            generic map(
                G_DATA_WIDTH  => G_DATA_WIDTH,
                G_DELAY_VALUE => C_JORD_DELAY_K,
                G_REG_INPUT   => 1
            )
            port map(
                CLK_I    => CLK_I,
                RST_N_I  => RST_N_I,
                DATA_I   => data_n,
                DATA_D_O => data_k
            );

        sr_l : entity trap_filter.shift_register
            generic map(
                G_DATA_WIDTH  => G_DATA_WIDTH,
                G_DELAY_VALUE => C_JORD_DELAY_L,
                G_REG_INPUT   => 1
            )
            port map(
                CLK_I    => CLK_I,
                RST_N_I  => RST_N_I,
                DATA_I   => data_k,
                DATA_D_O => data_l
            );

        sr_kl : entity trap_filter.shift_register
            generic map(
                G_DATA_WIDTH  => G_DATA_WIDTH,
                G_DELAY_VALUE => C_JORD_DELAY_KL,
                G_REG_INPUT   => 1
            )
            port map(
                CLK_I    => CLK_I,
                RST_N_I  => RST_N_I,
                DATA_I   => data_l,
                DATA_D_O => data_kl
            );

    end generate g_jord_en;

    g_jord_dis : if G_JORD_DELAY_EN = 0 generate

        data_k  <= DATA_I;
        data_l  <= DATA_I;
        data_kl <= DATA_I;

    end generate g_jord_dis;

    ----------------------------------------------------------------------------
    -- Moving average baseline delay
    ----------------------------------------------------------------------------

    g_mov_en : if G_MOV_DELAY_EN = 1 generate

        sr_d : entity trap_filter.shift_register
            generic map(
                G_DATA_WIDTH  => G_DATA_WIDTH + 1,
                G_DELAY_VALUE => C_MOV_DELAY_D,
                G_REG_INPUT   => 1
            )
            port map(
                CLK_I    => CLK_I,
                RST_N_I  => RST_N_I,
                DATA_I   => DATA_JORD_FILT_I,
                DATA_D_O => data_mov
            );

    end generate g_mov_en;

    g_mov_dis : if G_MOV_DELAY_EN = 0 generate

        data_mov <= DATA_JORD_FILT_I;

    end generate g_mov_dis;

end architecture rtl;