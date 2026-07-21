--==============================================================================
--  Module:        delay_trap.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       21/07/2026
--  Last Modified:
--
--  Description:
--  Top wrapper for the delay shift registers of the trapezoidal subsystem.
--  Instantiates the delay units in parallel, all fed from the same input timeline.
--  Moving average delay is fed from trapezoidal output.
--
--      data_n  = DATA_I delayed by C_PULSE_DELAY
--      data_k  = DATA_I delayed by k + C_PULSE_DELAY
--      data_l  = DATA_I delayed by l + C_PULSE_DELAY
--      data_kl = DATA_I delayed by (k+l) + C_PULSE_DELAY
--      data_mov_d = DATA_JORD_FILT_I delayed by d
--
--  Dependencies:
--  CE asserted high while data is fed sync.
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
        CE_I             : in std_logic;                                   -- Chip enable
        DATA_I           : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Raw unsigned input
        DATA_JORD_FILT_I : in std_logic_vector(G_DATA_WIDTH downto 0);     -- Signed trapezoidal stream
        ------------------------------------------------------------------------
        -- Delayed data outputs
        ------------------------------------------------------------------------
        DATA_N_O     : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Pulse delayed input (to filters)
        DATA_K_O     : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- v[n-k]  (+ pulse delay)
        DATA_L_O     : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- v[n-l]  (+ pulse delay)
        DATA_KL_O    : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- v[n-k-l](+ pulse delay)
        DATA_MOV_D_O : out std_logic_vector(G_DATA_WIDTH downto 0);     -- Signed mov avg delay (from jord filter)
        ------------------------------------------------------------------------
        -- Ready flags
        ------------------------------------------------------------------------
        DELAY_JORD_READY_O : out std_logic_vector(2 downto 0); -- Filled ready signal: bit2 = k, bit1 = l, bit0 = kl
        DELAY_MOV_READY_O  : out std_logic
    );
end entity delay_trap;

architecture rtl of delay_trap is

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
    -- Constants
    ----------------------------------------------------------------------------

    -- Jordanov taps carry the common pulse delay so all share one timeline
    constant C_K_TOTAL  : natural := G_JORD_K_DELAY + G_PULSE_DELAY;
    constant C_L_TOTAL  : natural := G_JORD_L_DELAY + G_PULSE_DELAY;
    constant C_KL_TOTAL : natural := G_JORD_KL_DELAY + G_PULSE_DELAY;

    -- Arming counter limits (common pulse detection delay before counting)
    constant C_ARM_CNT_WIDTH : natural                                        := clog2(G_PULSE_DELAY);
    constant C_ARM_CNT_MAX   : std_logic_vector(C_ARM_CNT_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(G_PULSE_DELAY - 1, C_ARM_CNT_WIDTH));
    constant C_ARM_CNT_ONE   : std_logic_vector(C_ARM_CNT_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, C_ARM_CNT_WIDTH));
    constant C_ARM_CNT_ZERO  : std_logic_vector(C_ARM_CNT_WIDTH - 1 downto 0) := (others => '0');

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- delayed outputs (mov avg is signed)
    signal data_n   : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_k   : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_l   : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_kl  : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal data_mov : std_logic_vector(G_DATA_WIDTH downto 0);

    -- memory fullfilled signals (asserted on same cycle as fullfilled)
    signal jord_ready : std_logic_vector(2 downto 0);
    signal mov_ready  : std_logic;

    -- Gate the mov avg ready until the pulse detection delay line has filled
    signal cnt_arm : std_logic_vector(C_ARM_CNT_WIDTH - 1 downto 0);
    signal armed   : std_logic;
    signal sr_d_ce : std_logic;

begin

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    DATA_N_O     <= data_n;
    DATA_K_O     <= data_k;
    DATA_L_O     <= data_l;
    DATA_KL_O    <= data_kl;
    DATA_MOV_D_O <= data_mov;

    DELAY_JORD_READY_O <= jord_ready;
    DELAY_MOV_READY_O  <= mov_ready;

    ----------------------------------------------------------------------------
    -- Pulse delayed input (common delay D)
    ----------------------------------------------------------------------------

    sr_n : entity trap_filter.delay_unit_sr
        generic map(
            G_DATA_WIDTH  => G_DATA_WIDTH,
            G_DELAY_VALUE => G_PULSE_DELAY,
            G_DATA_SIGNED => 0
        )
        port map(
            CLK_I          => CLK_I,
            RST_N_I        => RST_N_I,
            CE_I           => CE_I,
            DATA_I         => DATA_I,
            DATA_D_O       => data_n,
            DATA_D_VALID_O => open
        );

    ----------------------------------------------------------------------------
    -- Jordanov delay taps
    ----------------------------------------------------------------------------

    sr_k : entity trap_filter.delay_unit_sr
        generic map(
            G_DATA_WIDTH  => G_DATA_WIDTH,
            G_DELAY_VALUE => C_K_TOTAL,
            G_DATA_SIGNED => 0
        )
        port map(
            CLK_I          => CLK_I,
            RST_N_I        => RST_N_I,
            CE_I           => CE_I,
            DATA_I         => DATA_I,
            DATA_D_O       => data_k,
            DATA_D_VALID_O => jord_ready(2)
        );

    sr_l : entity trap_filter.delay_unit_sr
        generic map(
            G_DATA_WIDTH  => G_DATA_WIDTH,
            G_DELAY_VALUE => C_L_TOTAL,
            G_DATA_SIGNED => 0
        )
        port map(
            CLK_I          => CLK_I,
            RST_N_I        => RST_N_I,
            CE_I           => CE_I,
            DATA_I         => DATA_I,
            DATA_D_O       => data_l,
            DATA_D_VALID_O => jord_ready(1)
        );

    sr_kl : entity trap_filter.delay_unit_sr
        generic map(
            G_DATA_WIDTH  => G_DATA_WIDTH,
            G_DELAY_VALUE => C_KL_TOTAL,
            G_DATA_SIGNED => 0
        )
        port map(
            CLK_I          => CLK_I,
            RST_N_I        => RST_N_I,
            CE_I           => CE_I,
            DATA_I         => DATA_I,
            DATA_D_O       => data_kl,
            DATA_D_VALID_O => jord_ready(0)
        );

    ----------------------------------------------------------------------------
    -- Moving average baseline delay
    ----------------------------------------------------------------------------

    sr_d : entity trap_filter.delay_unit_sr
        generic map(
            G_DATA_WIDTH  => G_DATA_WIDTH,
            G_DELAY_VALUE => G_MOV_D_DELAY,
            G_DATA_SIGNED => 1
        )
        port map(
            CLK_I          => CLK_I,
            RST_N_I        => RST_N_I,
            CE_I           => sr_d_ce,
            DATA_I         => DATA_JORD_FILT_I,
            DATA_D_O       => data_mov,
            DATA_D_VALID_O => mov_ready
        );

    -- sr_d only counts once the pulse delayed trapezoidal stream is valid
    sr_d_ce <= CE_I and armed;

    p_arm : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            cnt_arm <= C_ARM_CNT_ZERO;
            armed   <= '0';
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                if (unsigned(cnt_arm) < unsigned(C_ARM_CNT_MAX)) then
                    cnt_arm <= std_logic_vector(unsigned(cnt_arm) + unsigned(C_ARM_CNT_ONE));
                else
                    armed <= '1';
                end if;
            end if;
        end if;
    end process p_arm;

end architecture rtl;