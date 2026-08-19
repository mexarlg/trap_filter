--==============================================================================
--  Module:        risetime_capture.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       12/08/2026
--  Last Modified:
--
--  Description:
--  Module that captures the rise time of the filtered output given a trigger with the
--  measured amplitude from trap_ss.
--
--  Dependencies:
--  trap_filter_pkg.vhd
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity risetime_capture is
    generic (
        -- Data parameters
        G_DATA_WIDTH : natural range 8 to 16 := 14; -- Width of raw input data
        -- Rise time parameters
        G_T_RISE_WIDTH   : natural range 8 to 12   := 12; -- Width of rise time counter
        G_T_RISE_TIMEOUT : natural range 60 to 512 := 60  -- Value of timeout in n samples for rise time capture
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
        DATA_I            : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- Input raw data
        TRIG_TOP_MID_I    : in std_logic;                                   -- Trigger when measured amplitude is available
        TRIG_PULSE_END_I  : in std_logic;                                   -- Trigger when trapezoid pulse has ended (timeout of rise time cnt)
        PULSE_AMPLITUDE_I : in std_logic_vector(G_DATA_WIDTH downto 0);     -- Amplitude measured at middle of flat
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        PULSE_T_RISE_O : out std_logic_vector(G_T_RISE_WIDTH - 1 downto 0) -- Captured rise time
    );
end entity risetime_capture;

architecture rtl of risetime_capture is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- multiplication constants for amplitude thresholds
    constant C_FRAC_BITS : natural                        := 10;                                                                      -- number of fractional bits (1024 depth)
    constant C_ROUND     : natural                        := 50;                                                                      -- value to round off (50/1024)
    constant C_MUL_10    : unsigned(C_FRAC_BITS downto 0) := to_unsigned((8 * (2 ** C_FRAC_BITS) + C_ROUND) / 100, C_FRAC_BITS + 1);  -- scaling for 10%
    constant C_MUL_90    : unsigned(C_FRAC_BITS downto 0) := to_unsigned((88 * (2 ** C_FRAC_BITS) + C_ROUND) / 100, C_FRAC_BITS + 1); -- scaling for 90%

    -- time rise counter constants
    constant C_T_RISE_CNT_ONE  : std_logic_vector(G_T_RISE_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, G_T_RISE_WIDTH)); -- unit value of counter in its width
    constant C_T_RISE_CNT_ZERO : std_logic_vector(G_T_RISE_WIDTH - 1 downto 0) := (others => '0');                                  -- zero value of counter in its width

    -- timeout value of counter
    constant C_TIMEOUT_VALUE : std_logic_vector(G_T_RISE_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(G_T_RISE_TIMEOUT, G_T_RISE_WIDTH)); -- timeout counter limit

    ----------------------------------------------------------------------------
    -- Fsm
    ----------------------------------------------------------------------------

    -- fsm states
    type state_t is (S_IDLE, S_WAITING_PULSE, S_UPDATING_TH, S_WAITING_RISE, S_COUNTING, S_STORING);
    signal state      : state_t;
    signal state_next : state_t;

    -- S_IDLE: State in RST_N.
    -- S_WAITING_PULSE: State to wait for incoming pulse.
    -- S_UPDATING_TH: Measured amplitude available, update thresholds.
    -- S_WAITING_RISE: State to wait until pulse land on thresholds, unless new pulse or timeout.
    -- S_COUNTING: State to measure the rise time with a counter while inside thresholds unless new pulse or timeout.
    -- S_STORING: Outside of upper threshold, latch rise time counter and return to waiting.

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output signals
    signal pulse_t_rise : std_logic_vector(G_T_RISE_WIDTH - 1 downto 0); -- rise time value captured

    -- threshold values
    signal amplitude       : unsigned(G_DATA_WIDTH downto 0);         -- amplitude convertion to unsigned for comparison
    signal amplitude_th_90 : std_logic_vector(G_DATA_WIDTH downto 0); -- 90% high amplitude threshold
    signal amplitude_th_10 : std_logic_vector(G_DATA_WIDTH downto 0); -- 10% low amplitude threshold

    -- counter signal
    signal t_rise_cnt       : std_logic_vector(G_T_RISE_WIDTH - 1 downto 0); -- rise time counter
    signal waiting_rise_cnt : std_logic_vector(G_T_RISE_WIDTH - 1 downto 0); -- waiting rise time counter

    -- threshold flag signals
    signal is_inside_th       : std_logic; -- flag of current input data being inside both thresholds
    signal is_above_10        : std_logic; -- flag of current input data being above the 10% threshold
    signal is_below_90        : std_logic; -- flag of current input data being below the 90% threshold
    signal timeout_waiting    : std_logic; -- flag of timeout while on waiting_rise state
    signal thresholds_updated : std_logic; -- flag of thresholds updated

    -- fsm enable state signals
    signal waiting_pulse_en : std_logic; -- current state on S_WAITING_PULSE
    signal waiting_rise_en  : std_logic; -- current state on S_WAITING_RISE
    signal updating_en      : std_logic; -- current state on S_UPDATING
    signal counting_en      : std_logic; -- current state on S_COUNTING
    signal storing_en       : std_logic; -- current state on S_STORING

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output Assignments
    ----------------------------------------------------------------------------

    PULSE_T_RISE_O <= pulse_t_rise;

    ----------------------------------------------------------------------------
    -- Main Combinatory Processes
    ----------------------------------------------------------------------------

    -- condition for inside of threshold
    is_inside_th <= is_above_10 and is_below_90;

    -- amplitude conversion to unsigned with negative saturation
    amplitude <= unsigned(PULSE_AMPLITUDE_I) when (signed(PULSE_AMPLITUDE_I) > 0) else
        (others => '0');

    -- waiting_rise counter arrived to maximum timeout allowable
    timeout_waiting <= '1' when (waiting_rise_cnt = C_TIMEOUT_VALUE) else
        '0';

    -- finite state machine of rise time capture
    p_fsm : process (state, TRIG_TOP_MID_I, is_inside_th, timeout_waiting, TRIG_PULSE_END_I, thresholds_updated)
    begin
        -- initialization
        waiting_pulse_en <= '0';
        waiting_rise_en  <= '0';
        updating_en      <= '0';
        counting_en      <= '0';
        storing_en       <= '0';

        case state is

            when S_IDLE =>
                state_next <= S_WAITING_PULSE;

                -- Wait for a new pulse
            when S_WAITING_PULSE =>
                waiting_pulse_en <= '1';
                if (TRIG_TOP_MID_I = '1') then
                    state_next <= S_UPDATING_TH;
                else
                    state_next <= S_WAITING_PULSE;
                end if;

                -- Amplitude available, compute new thresholds
            when S_UPDATING_TH =>
                updating_en <= '1';
                if (thresholds_updated = '1') then
                    state_next <= S_WAITING_RISE;
                else
                    state_next <= S_UPDATING_TH;
                end if;

                -- Wait until being inside pulse threshold
            when S_WAITING_RISE =>
                waiting_rise_en <= '1';
                -- new pulse > timeout > measuring
                if (TRIG_TOP_MID_I = '1') then
                    state_next <= S_UPDATING_TH;
                elsif (timeout_waiting = '1') then
                    state_next <= S_WAITING_PULSE;
                elsif (is_inside_th = '1') then
                    state_next <= S_COUNTING;
                else
                    state_next <= S_WAITING_RISE;
                end if;

                -- Count the amount of samples inside the pulse threshold
            when S_COUNTING =>
                counting_en <= '1';
                -- new pulse > timeout > storing
                if (TRIG_TOP_MID_I = '1') then
                    state_next <= S_UPDATING_TH;
                elsif (TRIG_PULSE_END_I = '1') then
                    state_next <= S_WAITING_PULSE;
                elsif (is_inside_th = '0') then
                    state_next <= S_STORING;
                else
                    state_next <= S_COUNTING;
                end if;

                -- Rise time latched
            when S_STORING =>
                storing_en <= '1';
                state_next <= S_WAITING_PULSE;

            when others =>
                state_next <= S_IDLE;

        end case;
    end process p_fsm;

    ----------------------------------------------------------------------------
    -- Main Sequential Processes
    ----------------------------------------------------------------------------

    -- next state synchronous
    p_next : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            state <= S_IDLE;
        elsif rising_edge(CLK_I) then
            state <= state_next;
        end if;
    end process p_next;

    -- below 90% threshold flag
    p_is_below_90 : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            is_below_90 <= '0';
        elsif rising_edge(CLK_I) then
            if (unsigned(DATA_I) < unsigned(amplitude_th_90)) then
                is_below_90 <= '1';
            else
                is_below_90 <= '0';
            end if;
        end if;
    end process p_is_below_90;

    -- above 10% threshold flag
    p_is_above_10 : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            is_above_10 <= '0';
        elsif rising_edge(CLK_I) then
            if (unsigned(DATA_I) > unsigned(amplitude_th_10)) then
                is_above_10 <= '1';
            else
                is_above_10 <= '0';
            end if;
        end if;
    end process p_is_above_10;

    -- computation of 10% threshold (multiplication + shift)
    p_th_10 : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            amplitude_th_10    <= (others => '0');
            thresholds_updated <= '0';
        elsif rising_edge(CLK_I) then
            if (updating_en = '1') then
                thresholds_updated <= '1';
                amplitude_th_10    <= std_logic_vector(resize(unsigned(DATA_I), amplitude_th_10'length)
                    + resize(shift_right(amplitude * C_MUL_10, C_FRAC_BITS), amplitude_th_10'length));
            else
                thresholds_updated <= '0';
            end if;
        end if;
    end process p_th_10;

    -- computation of 90% threshold (multiplication + shift)
    p_th_90 : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            amplitude_th_90 <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (updating_en = '1') then
                amplitude_th_90 <= std_logic_vector(resize(unsigned(DATA_I), amplitude_th_90'length)
                    + resize(shift_right(amplitude * C_MUL_90, C_FRAC_BITS), amplitude_th_90'length));
            end if;
        end if;
    end process p_th_90;

    -- timeout for waiting rise
    p_wait_cnt : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            waiting_rise_cnt <= C_T_RISE_CNT_ZERO;
        elsif rising_edge(CLK_I) then
            if (waiting_pulse_en = '1') then
                waiting_rise_cnt <= C_T_RISE_CNT_ZERO;
            elsif (waiting_rise_en = '1') then
                waiting_rise_cnt <= std_logic_vector(unsigned(waiting_rise_cnt) + unsigned(C_T_RISE_CNT_ONE));
            end if;
        end if;
    end process p_wait_cnt;

    -- rise time counter
    p_t_rise_cnt : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            t_rise_cnt <= C_T_RISE_CNT_ZERO;
        elsif rising_edge(CLK_I) then
            if (waiting_pulse_en = '1') then
                t_rise_cnt <= C_T_RISE_CNT_ZERO;
            elsif (counting_en = '1') then
                t_rise_cnt <= std_logic_vector(unsigned(t_rise_cnt) + unsigned(C_T_RISE_CNT_ONE));
            end if;
        end if;
    end process p_t_rise_cnt;

    -- latch the measured rise time plus the latency of fsm
    p_store : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            pulse_t_rise <= C_T_RISE_CNT_ZERO;
        elsif rising_edge(CLK_I) then
            if (storing_en = '1') then
                pulse_t_rise <= t_rise_cnt;
            end if;
        end if;
    end process p_store;

end architecture rtl;