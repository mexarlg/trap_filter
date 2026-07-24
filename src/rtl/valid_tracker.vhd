--==============================================================================
--  Module:        valid_tracker.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       17/07/2026
--  Last Modified: 
--
--  Description:
--  Module that tracks the required number of samples for the delays of both jordanov
--  and moving average filters. If the ready signal of the delays do not agree, a
--  synchronization error is asserted. Once the delays are ready, the latency is tracked to
--  issue the validity of the filtered data for both filters.
--
--  Dependencies:
--  Delay ready signal has to arrive when memory is fullfilled (count starts at 'CE' + 1)
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity valid_tracker is
    generic (
        -- Jordanov parameters
        G_JORD_LATENCY : natural range 6 to 10 := 6; -- Latency of Jordanov filter in cycles
        G_JORD_K_WIDTH : natural range 2 to 8  := 8; -- Width of delay needed for rising time (all bits -> '1' for multiple of 2^N)
        G_JORD_M_WIDTH : natural range 2 to 8  := 8; -- Width of delay needed for flat top (all bits -> '1' for multiple of 2^N)
        -- Mov avg parameters
        G_MOV_LATENCY       : natural range 2 to 4 := 2; -- Latency of Moving average filter in cycles
        G_MOV_D_WIDTH       : natural range 2 to 8 := 4; -- Width of samples averaged (all bits -> '1' for multiple of 2^N)
        G_PULSE_DELAY_WIDTH : natural range 4 to 6 := 4  -- Width of delay given from pulse detection subsystem (D = 2^N)
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
        CE_I : in std_logic; -- Chip enable of jordanov filter (DATA_N_I arrives after 1 cycle of CE)
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        DATA_JORD_VALID_O : out std_logic; -- Filter Jordanov output is valid (delay cycles + N latency cycle)
        DATA_MOV_VALID_O  : out std_logic  -- Filter Mov avg output is valid (delay cycles + N latency cycle)
    );
end entity valid_tracker;

architecture rtl of valid_tracker is

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

    -- Values of delays from k, m, l, kl (Jordanov) and d (Mov avg) 
    constant C_JORD_K_VALUE  : natural := 2 ** G_JORD_K_WIDTH;
    constant C_JORD_M_VALUE  : natural := 2 ** G_JORD_M_WIDTH;
    constant C_JORD_L_VALUE  : natural := C_JORD_K_VALUE + C_JORD_M_VALUE;
    constant C_JORD_KL_VALUE : natural := C_JORD_L_VALUE + C_JORD_K_VALUE;
    constant C_MOV_D_VALUE   : natural := 2 ** G_MOV_D_WIDTH;

    -- Pulse detection delay (common to both filters)
    constant C_PULSE_DELAY_VALUE : natural := 2 ** G_PULSE_DELAY_WIDTH;

    -- Expected limits for Jordanov delays counter (max delay of the 3 is KL)
    constant C_JORD_CNT_WIDTH  : natural                                         := clog2(C_JORD_KL_VALUE);
    constant C_JORD_CNT_ONE    : std_logic_vector(C_JORD_CNT_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, C_JORD_CNT_WIDTH));
    constant C_JORD_CNT_ZERO   : std_logic_vector(C_JORD_CNT_WIDTH - 1 downto 0) := (others => '0');
    constant C_JORD_CNT_KL_MAX : std_logic_vector(C_JORD_CNT_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(C_JORD_KL_VALUE - 1, C_JORD_CNT_WIDTH));
    constant C_JORD_CNT_K_MAX  : std_logic_vector(C_JORD_CNT_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(C_JORD_K_VALUE - 1, C_JORD_CNT_WIDTH));
    constant C_JORD_CNT_L_MAX  : std_logic_vector(C_JORD_CNT_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(C_JORD_L_VALUE - 1, C_JORD_CNT_WIDTH));

    -- Expected limits for Moving average delay counters
    constant C_MOV_CNT_D_MAX  : std_logic_vector(G_MOV_D_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(C_MOV_D_VALUE - 1, G_MOV_D_WIDTH));
    constant C_MOV_CNT_D_ONE  : std_logic_vector(G_MOV_D_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, G_MOV_D_WIDTH));
    constant C_MOV_CNT_D_ZERO : std_logic_vector(G_MOV_D_WIDTH - 1 downto 0) := (others => '0');

    -- Arming counter limits (common pulse detection delay before counting)
    constant C_ARM_CNT_WIDTH : natural                                        := G_PULSE_DELAY_WIDTH + 1;
    constant C_ARM_CNT_MAX   : std_logic_vector(C_ARM_CNT_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(C_PULSE_DELAY_VALUE - 1, C_ARM_CNT_WIDTH));
    constant C_ARM_CNT_ONE   : std_logic_vector(C_ARM_CNT_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, C_ARM_CNT_WIDTH));
    constant C_ARM_CNT_ZERO  : std_logic_vector(C_ARM_CNT_WIDTH - 1 downto 0) := (others => '0');

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- Output data signals
    signal data_jord_valid : std_logic;
    signal data_mov_valid  : std_logic;

    -- Gate the filter counters until the pulse detection delay line has filled
    signal cnt_arm : std_logic_vector(C_ARM_CNT_WIDTH - 1 downto 0);
    signal armed   : std_logic;

    -- Jordanov counter
    signal cnt_delay_jord : std_logic_vector(C_JORD_CNT_WIDTH - 1 downto 0);

    -- Jordanov: internal ready signals for delays
    signal delay_kl_ready_trig : std_logic;
    signal delay_l_ready_trig  : std_logic;
    signal delay_k_ready_trig  : std_logic;

    -- Moving avg: counter and delay error synchronization signals
    signal cnt_delay_mov      : std_logic_vector(G_MOV_D_WIDTH - 1 downto 0);
    signal delay_d_ready_trig : std_logic;

    -- Valid of filtered data (delays ready + latency) -> delay_ready_trig arrive 1 cycle before completed
    signal jord_valid_pipe : std_logic_vector(G_JORD_LATENCY - 1 downto 0);
    signal mov_valid_pipe  : std_logic_vector(G_MOV_LATENCY - 1 downto 0);

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    DATA_JORD_VALID_O <= data_jord_valid;
    DATA_MOV_VALID_O  <= data_mov_valid;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Common delay due pulse detection
    ----------------------------------------------------------------------------

    -- Pulse detection delay
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

    ----------------------------------------------------------------------------
    -- Align valid signals due latency
    ----------------------------------------------------------------------------

    -- Jordanov: delay the KL ready trigger by the filter pipeline latency to align valid
    p_jord_valid : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            jord_valid_pipe <= (others => '0');
            data_jord_valid <= '0';
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- shift the ready trigger through G_JORD_LATENCY stages
                jord_valid_pipe <= jord_valid_pipe(jord_valid_pipe'high - 1 downto 0) & delay_kl_ready_trig;
                data_jord_valid <= jord_valid_pipe(jord_valid_pipe'high);
            end if;
        end if;
    end process p_jord_valid;

    -- Moving average: delay the D ready trigger by the filter pipeline latency to align valid
    p_mov_valid : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            mov_valid_pipe <= (others => '0');
            data_mov_valid <= '0';
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                mov_valid_pipe <= mov_valid_pipe(mov_valid_pipe'high - 1 downto 0) & delay_d_ready_trig;
                data_mov_valid <= mov_valid_pipe(mov_valid_pipe'high);
            end if;
        end if;
    end process p_mov_valid;

    ----------------------------------------------------------------------------
    -- Mov avg filter
    ----------------------------------------------------------------------------

    -- Assert internal delay valid in case external ready is not properly asserted
    p_mov_ready : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            delay_d_ready_trig <= '0';
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                if (cnt_delay_mov = C_MOV_CNT_D_MAX) then
                    delay_d_ready_trig <= '1';
                end if;
            end if;
        end if;
    end process p_mov_ready;

    -- counter that times-out at maximum (when data_d_valid should be triggered) -> gated by arming
    p_mov_cnt : process (CLK_I, RST_N_I)
    begin
        if RST_N_I = '0' then
            cnt_delay_mov <= C_MOV_CNT_D_ZERO;
        elsif rising_edge(CLK_I) then
            if (CE_I = '1' and armed = '1') then
                if (unsigned(cnt_delay_mov) < unsigned(C_MOV_CNT_D_MAX)) then
                    cnt_delay_mov <= std_logic_vector(unsigned(cnt_delay_mov) + unsigned(C_MOV_CNT_D_ONE));
                end if;
            end if;
        end if;
    end process p_mov_cnt;

    ----------------------------------------------------------------------------
    -- Jordanov filter
    ----------------------------------------------------------------------------

    -- counters that time-out at maximum of each of the delays -> gated by arming
    p_jord_cnt : process (CLK_I, RST_N_I)
    begin
        if RST_N_I = '0' then
            cnt_delay_jord <= C_JORD_CNT_ZERO;
        elsif rising_edge(CLK_I) then
            if (CE_I = '1' and armed = '1') then
                if (unsigned(cnt_delay_jord) < unsigned(C_JORD_CNT_KL_MAX)) then
                    cnt_delay_jord <= std_logic_vector(unsigned(cnt_delay_jord) + unsigned(C_JORD_CNT_ONE));
                end if;
            end if;
        end if;
    end process p_jord_cnt;

    -- Assert internal delay valid in case external delays are not properly asserted
    p_jord_ready : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            delay_k_ready_trig  <= '0';
            delay_l_ready_trig  <= '0';
            delay_kl_ready_trig <= '0';
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                if (cnt_delay_jord >= C_JORD_CNT_K_MAX) then
                    delay_k_ready_trig <= '1';
                end if;
                if (cnt_delay_jord >= C_JORD_CNT_L_MAX) then
                    delay_l_ready_trig <= '1';
                end if;
                if (cnt_delay_jord = C_JORD_CNT_KL_MAX) then
                    delay_kl_ready_trig <= '1';
                end if;
            end if;
        end if;
    end process p_jord_ready;

end architecture rtl;