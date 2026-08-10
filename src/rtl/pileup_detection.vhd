--==============================================================================
--  Module:        pileup_detection.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       30/07/2026
--  Last Modified: 07/08/2026
--
--  Description:
--  Module that asserts if a pulse is clean, which happens if no pileup has occured
--  while it was being processed or if no previous pileup residues affected it.
--  This is done through a fsm, which counts as well the amount of pileup events.

--  Dependencies:
--  trap_filter_pkg.vhd
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity pileup_detection is
    generic (
        -- Pulse and pileup parameters
        G_PILEUP_DECAY_VALUE : natural range 255 to 65535 := 4095; -- Value in N samples of the pulse decay time constant
        G_PILEUP_CNT_WIDTH   : natural range 7 to 12      := 12    -- Width of counter for N of pileup events
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
        PULSE_TRIG_I     : in std_logic; -- Trigger of detected pulse
        PULSE_END_TRIG_I : in std_logic; -- Trigger of ended pulse
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        PULSE_CLEAN_O  : out std_logic;                                        -- Trigger of clean pulse without pileup effects
        PILEUP_EVENT_O : out std_logic;                                        -- Trigger of a pileup event
        PILEUP_CNT_O   : out std_logic_vector(G_PILEUP_CNT_WIDTH - 1 downto 0) -- Counter of pileup events
    );
end entity pileup_detection;

architecture rtl of pileup_detection is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- Counter limits for the decay time counter
    constant C_CNT_DECAY_WIDTH : natural                                          := f_value_to_width(G_PILEUP_DECAY_VALUE);
    constant C_CNT_DECAY_MAX   : std_logic_vector(C_CNT_DECAY_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(G_PILEUP_DECAY_VALUE, C_CNT_DECAY_WIDTH));
    constant C_CNT_DECAY_ONE   : std_logic_vector(C_CNT_DECAY_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, C_CNT_DECAY_WIDTH));
    constant C_CNT_DECAY_ZERO  : std_logic_vector(C_CNT_DECAY_WIDTH - 1 downto 0) := (others => '0');

    -- Counter limits for the pileup counter
    constant C_CNT_PILEUP_MAX  : std_logic_vector(G_PILEUP_CNT_WIDTH - 1 downto 0) := (others => '1');
    constant C_CNT_PILEUP_ONE  : std_logic_vector(G_PILEUP_CNT_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, G_PILEUP_CNT_WIDTH));
    constant C_CNT_PILEUP_ZERO : std_logic_vector(G_PILEUP_CNT_WIDTH - 1 downto 0) := (others => '0');

    ----------------------------------------------------------------------------
    -- Fsm
    ----------------------------------------------------------------------------

    -- fsm states
    type state_t is (S_IDLE, S_WAITING, S_MEASURING, S_CLASSIFYING, S_PILEUP, S_SETTLING);
    signal state      : state_t;
    signal state_next : state_t;

    -- S_IDLE: State in RST_N.
    -- S_WAITING: State that waits for a pulse event (dirty flag = 0).
    -- S_MEASURING: Pulse arrived, wait for the correct measurement of the pulse without pileup.
    -- S_CLASSIFYING: No pileup occurred while measuring. Issue clean pulse if dirty flag = 0.
    -- S_PILEUP: Pileup occurs if pulse arrives in a state different than waiting. Pileup counter increases and dirty flag = 1
    -- S_SETTLING: State to wait for the decay of the pulse. If no pileup occurs we go to waiting state to reset dirty flag.

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output signals
    signal pulse_clean : std_logic;                                         -- pulse completed without pileup effects
    signal pileup_cnt  : std_logic_vector(G_PILEUP_CNT_WIDTH - 1 downto 0); -- counter of pileup events
    signal pileup_en   : std_logic;                                         -- pileup event (pulse arrival while processing current pulse)

    -- countdown of pulse decay time constant restarted after a new pulse event
    signal cnt_decay  : std_logic_vector(C_CNT_DECAY_WIDTH - 1 downto 0); -- decay counter
    signal decay_done : std_logic;                                        -- flag asserting full decay has been completed

    -- pulse affected by pileup flag
    signal pulse_dirty : std_logic;

    -- current state enable signals
    signal waiting_en     : std_logic; -- current state = waiting, for restart of dirty flag
    signal classifying_en : std_logic; -- current state = classifying, for assertion of pulse clean

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output Assignments
    ----------------------------------------------------------------------------

    PULSE_CLEAN_O  <= pulse_clean;
    PILEUP_EVENT_O <= pileup_en;
    PILEUP_CNT_O   <= pileup_cnt;

    ----------------------------------------------------------------------------
    -- Main Combinatory Processes
    ----------------------------------------------------------------------------

    -- free of pileup when counter reaches the decay time constant
    decay_done <= '1' when cnt_decay = C_CNT_DECAY_ZERO else
        '0';

    -- finite state machine of pileup detection
    p_fsm : process (state, PULSE_TRIG_I, PULSE_END_TRIG_I, decay_done)
    begin
        -- initialization
        waiting_en     <= '0';
        classifying_en <= '0';
        pileup_en      <= '0';

        case state is

            when S_IDLE =>
                state_next <= S_WAITING;

            when S_WAITING =>
                waiting_en <= '1';
                if (PULSE_TRIG_I = '1') then
                    state_next <= S_MEASURING;
                else
                    state_next <= S_WAITING;
                end if;

            when S_MEASURING =>
                if (PULSE_TRIG_I = '1') then
                    state_next <= S_PILEUP;
                elsif (PULSE_END_TRIG_I = '1') then
                    state_next <= S_CLASSIFYING;
                else
                    state_next <= S_MEASURING;
                end if;

            when S_CLASSIFYING =>
                classifying_en <= '1';
                if (PULSE_TRIG_I = '1') then
                    state_next <= S_PILEUP;
                else
                    state_next <= S_SETTLING;
                end if;

            when S_PILEUP =>
                pileup_en  <= '1';
                state_next <= S_MEASURING;

            when S_SETTLING =>
                if (PULSE_TRIG_I = '1') then
                    state_next <= S_PILEUP;
                elsif (decay_done = '1') then
                    state_next <= S_WAITING;
                else
                    state_next <= S_SETTLING;
                end if;

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

    -- pulse is dirty until state goes back to waiting state
    p_dirty : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            pulse_dirty <= '0';
        elsif rising_edge(CLK_I) then
            -- if pileup, need to go through S_WAITING to deassert pulse_dirty
            if (pileup_en = '1') then
                pulse_dirty <= '1';
            elsif (waiting_en = '1') then
                pulse_dirty <= '0';
            end if;
        end if;
    end process p_dirty;

    -- decay counter restarted every new trigger
    p_decay_cnt : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            cnt_decay <= C_CNT_DECAY_ZERO;
        elsif rising_edge(CLK_I) then
            -- restart counter on pulse trigger
            if (PULSE_TRIG_I = '1') then
                cnt_decay <= C_CNT_DECAY_MAX;
                -- pulse triggered counter to maximum, start decay countdown
            elsif (cnt_decay /= C_CNT_DECAY_ZERO) then
                cnt_decay <= std_logic_vector(unsigned(cnt_decay) - unsigned(C_CNT_DECAY_ONE));
            end if;
        end if;
    end process p_decay_cnt;

    -- increases the pileup event and its counter
    p_decay : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            pileup_cnt <= C_CNT_PILEUP_ZERO;
        elsif rising_edge(CLK_I) then
            -- add pileup event to counter
            if (pileup_en = '1') then
                -- if counter is not full
                if (unsigned(pileup_cnt) < unsigned(C_CNT_PILEUP_MAX)) then
                    pileup_cnt <= std_logic_vector(unsigned(pileup_cnt) + unsigned(C_CNT_PILEUP_ONE));
                end if;
            end if;
        end if;
    end process p_decay;

    -- checks if the pulse is clean (valid) or dirty (pileup)
    p_clean : process (RST_N_I, CLK_I)
    begin
        if (RST_N_I = '0') then
            pulse_clean <= '0';
        elsif rising_edge(CLK_I) then
            pulse_clean <= '0';
            -- pulse able to be measured
            if (classifying_en = '1') then
                -- pulse clean trigger, not affected by current or previous pileup
                if (pulse_dirty = '0') then
                    pulse_clean <= '1';
                end if;
            end if;
        end if;
    end process p_clean;

end architecture rtl;