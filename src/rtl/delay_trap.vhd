--==============================================================================
--  Module:        delay_trap.vhd
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
--  data fed sync with CLK_I. Validity handled externally.
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity delay_trap is
    generic (
        G_DATA_WIDTH    : natural range 4 to 16 := 14;  -- Raw ADC data width (unsigned)
        G_PULSE_DELAY   : natural               := 16;  -- Common delay (pulse detection)
        G_JORD_K_DELAY  : natural               := 64;  -- k  = 2^k_w
        G_JORD_L_DELAY  : natural               := 192; -- l  = k + m
        G_JORD_KL_DELAY : natural               := 256; -- kl = k + l
        G_MOV_D_DELAY   : natural               := 16   -- Moving average depth
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
        DATA_I           : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Raw unsigned input
        DATA_JORD_FILT_I : in std_logic_vector(G_DATA_WIDTH downto 0);     -- Signed trapezoidal stream
        ------------------------------------------------------------------------
        -- Delayed data outputs
        ------------------------------------------------------------------------
        DATA_N_O     : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Pulse delayed input (to filters)
        DATA_K_O     : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- v[n-k]  (+ pulse delay)
        DATA_L_O     : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- v[n-l]  (+ pulse delay)
        DATA_KL_O    : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- v[n-k-l](+ pulse delay)
        DATA_MOV_D_O : out std_logic_vector(G_DATA_WIDTH downto 0)      -- Signed mov avg delay (from jord filter)
    );
end entity delay_trap;

architecture rtl of delay_trap is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- delay values taking into account shift register latency
    constant C_PULSE_DELAY   : natural := G_PULSE_DELAY - 1;                    -- 16      -> data_n at 17
    constant C_JORD_DELAY_K  : natural := G_JORD_K_DELAY - 1;                   -- 63      -> data_k at 81 (k - n = 64)
    constant C_JORD_DELAY_L  : natural := G_JORD_L_DELAY - G_JORD_K_DELAY - 1;  -- 127     -> data_l at 209 (l - k = 128)
    constant C_JORD_DELAY_KL : natural := G_JORD_KL_DELAY - G_JORD_L_DELAY - 1; -- 63
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
    report "delay_trap: Jordanov tap spacing must exceed 1 cycle for chained segments"
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

    sr_n : entity trap_filter.delay_unit_sr
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

    ----------------------------------------------------------------------------
    -- Jordanov delay: data_n -> [k] -> k -> [l - k] -> l -> [kl - l] -> kl
    ----------------------------------------------------------------------------

    sr_k : entity trap_filter.delay_unit_sr
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

    sr_l : entity trap_filter.delay_unit_sr
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

    sr_kl : entity trap_filter.delay_unit_sr
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

    ----------------------------------------------------------------------------
    -- Moving average baseline delay
    ----------------------------------------------------------------------------

    sr_d : entity trap_filter.delay_unit_sr
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

end architecture rtl;