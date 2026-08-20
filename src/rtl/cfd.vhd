--==============================================================================
--  Module:        cfd.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       29/07/2026
--  Last Modified:
--
--  Description:
--  Module that asserts a trigger if a pulse arrives using a constant fraction discriminar (CFD)
--  algorithm. It allows for discrimination of different pulses due amplitude.
--
--
--  Dependencies:
--  trap_filter_pkg.vhd, shift_register.vhd,
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity cfd is
    generic (
        -- Data parameters
        G_DATA_WIDTH : natural range 8 to 16 := 15; -- Width of incoming data stream (ADC Magnitude resolution)
        -- Cfd parameters
        G_CFD_F_WIDTH     : natural range 1 to 3   := 1;  -- scalar factor f (1 = 0.5; 2 = 0.25; 3 = 0.125)
        G_CFD_DELAY       : natural range 16 to 64 := 32; -- cfd delay (16 for fast, 64 for slow pulses)
        G_CFD_SLOPE_DELAY : natural range 8 to 16  := 8;  -- slope delay used to compute slope of data for gating on rising edges
        G_CFD_MARGIN_BITS : natural range 1 to 3   := 1;  -- Number of bits of margin to internal difference signal
        -- thresholds and expected pulse timeout
        G_CFD_NOISE_TH      : natural range 10 to 4096 := 100; -- Threshold level of noise to gate a pulse detection event
        G_CFD_TIMEOUT_WIDTH : natural range 5 to 10    := 7    -- timeout width after thresholds are overcomed for a zero crossing event
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
        DATA_I : in std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- input data stream
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        CFD_SIGNAL_O      : out std_logic_vector(G_DATA_WIDTH + G_CFD_MARGIN_BITS - 1 downto 0); -- cfd output signal that crosses zero
        CFD_PULSE_TRIG_O  : out std_logic;                                                       -- pulse detected flag (1 cycle pulse)
        CFD_ERROR_OFLOW_O : out std_logic_vector(1 downto 0)                                     -- overflow error status of cfd
    );
end entity cfd;

architecture rtl of cfd is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------

    -- threshold for increasing slope
    constant C_CFD_SLOPE_TH : natural := 100; -- threshold to gate slope of DATA_I

    -- delay values (-1 due REG_INPUT generic asserted on shift_register)
    constant C_CFD_D_DELAY : natural := G_CFD_DELAY - 1;
    constant C_CFD_M_DELAY : natural := G_CFD_SLOPE_DELAY - 1;

    -- internal arithmetic width (data + margin)
    constant C_CFD_WIDTH : natural := G_DATA_WIDTH + G_CFD_MARGIN_BITS;

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- output cfd signals
    signal cfd_pulse_trig  : std_logic;                                  -- pulse detected flag
    signal cfd_error_oflow : std_logic_vector(1 downto 0);               -- error status
    signal cfd_signal      : std_logic_vector(C_CFD_WIDTH - 1 downto 0); -- error status

    -- delayed data
    signal data_del_d    : std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- delayed data with d delay
    signal data_del_d_q0 : std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- registered data d delay
    signal data_del_m    : std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- delayed data with m delay
    signal data_i_q0     : std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- registered data_i (for sync in stages)

    -- intermidiate pipelined data
    signal cfd_fx      : std_logic_vector(C_CFD_WIDTH - 1 downto 0); -- multiplication -> f*x[n]
    signal cfd_diff    : std_logic_vector(C_CFD_WIDTH - 1 downto 0); -- zero cross
    signal cfd_diff_q0 : std_logic_vector(C_CFD_WIDTH - 1 downto 0); -- zero cross registered
    signal data_slope  : std_logic_vector(C_CFD_WIDTH - 1 downto 0); -- slope signal

    -- logic flags for pulse detection
    signal zero_cross_flag : std_logic; -- change of sign in cfd_diff signal
    signal above_th_flag   : std_logic; -- data_i value above threshold
    signal slope_pos_flag  : std_logic; -- data_i slope above threshold

    -- detection flags asserted, pulse incoming
    signal pulse_incoming    : std_logic;                                          -- thresholds overcomed so a pulse is expected, waiting for zero cross
    signal pulse_timeout_cnt : std_logic_vector(G_CFD_TIMEOUT_WIDTH - 1 downto 0); -- timeout counter after overcomed thresholds for a zero cross event to allow detection

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    assert (2 ** G_CFD_TIMEOUT_WIDTH - 1 > C_CFD_D_DELAY)
    report "cfd: timeout window G_CFD_TIMEOUT_WIDTH must be longer than C_CFD_D_DELAY delay" severity failure;

    assert (G_CFD_SLOPE_DELAY < G_CFD_DELAY)
    report "cfd: G_CFD_SLOPE_DELAY exceeds G_CFD_DELAY"
        severity failure;

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    CFD_SIGNAL_O      <= cfd_signal;
    CFD_PULSE_TRIG_O  <= cfd_pulse_trig;
    CFD_ERROR_OFLOW_O <= cfd_error_oflow;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    cfd_error_oflow <= (others => '0');
    cfd_signal      <= cfd_diff;

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- CFD
    ----------------------------------------------------------------------------

    -- Registration for delays
    p_reg : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            data_i_q0     <= (others => '0');
            data_del_d_q0 <= (others => '0');
            cfd_diff_q0   <= (others => '0');
        elsif rising_edge(CLK_I) then
            data_i_q0     <= DATA_I;
            data_del_d_q0 <= data_del_d;
            cfd_diff_q0   <= cfd_diff;
        end if;
    end process p_reg;

    -- STAGE 1: multiply by f (shift)
    p_mult : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            cfd_fx <= (others => '0');
        elsif rising_edge(CLK_I) then
            -- runs at + 1 cycles
            cfd_fx <= std_logic_vector(resize(shift_right(signed(DATA_I), G_CFD_F_WIDTH), C_CFD_WIDTH));
        end if;
    end process p_mult;

    -- STAGE 2: difference f*x[n] - x[n-d]
    p_diff : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            cfd_diff <= (others => '0');
        elsif rising_edge(CLK_I) then
            -- runs at + 2 cycles
            cfd_diff <= std_logic_vector(signed(cfd_fx)
                - resize(signed(data_del_d_q0), C_CFD_WIDTH));
        end if;
    end process p_diff;

    -- STAGE 3: zero cross
    p_cross : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            zero_cross_flag <= '0';
        elsif rising_edge(CLK_I) then
            -- runs at + 3 cycles
            if (signed(cfd_diff_q0) >= 0 and signed(cfd_diff) < 0) then
                zero_cross_flag <= '1';
            else
                zero_cross_flag <= '0';
            end if;
        end if;
    end process p_cross;

    ----------------------------------------------------------------------------
    -- Pulse detection
    ----------------------------------------------------------------------------

    -- Slope computation of input data
    p_slope : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            data_slope <= (others => '0');
        elsif rising_edge(CLK_I) then
            -- runs at + 1 cycles
            data_slope <= std_logic_vector(resize(signed(DATA_I), C_CFD_WIDTH)
                - resize(signed(data_del_m), C_CFD_WIDTH));
        end if;
    end process p_slope;

    -- Pulse value and slope threshold flags 
    p_threshold : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            above_th_flag  <= '0';
            slope_pos_flag <= '0';
        elsif rising_edge(CLK_I) then
            -- runs at + 2 cycles
            if (signed(data_i_q0) > G_CFD_NOISE_TH) then
                above_th_flag <= '1';
            else
                above_th_flag <= '0';
            end if;
            -- runs at + 2 cycles
            if (signed(data_slope) > C_CFD_SLOPE_TH) then
                slope_pos_flag <= '1';
            else
                slope_pos_flag <= '0';
            end if;
        end if;
    end process p_threshold;

    -- Pulse incoming, wait until zero cross or count is finished
    p_detected : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            pulse_incoming    <= '0';
            pulse_timeout_cnt <= (others => '0');
        elsif rising_edge(CLK_I) then
            -- runs at + 3 cycles
            if (above_th_flag = '1' and slope_pos_flag = '1') then
                pulse_incoming    <= '1';
                pulse_timeout_cnt <= (others => '1');
            elsif (zero_cross_flag = '1' or unsigned(pulse_timeout_cnt) = 0) then
                pulse_incoming <= '0';
            else
                pulse_timeout_cnt <= std_logic_vector(unsigned(pulse_timeout_cnt) - 1);
            end if;
        end if;
    end process p_detected;

    -- Assert trigger when pulse_incoming is high and sign change arrives
    p_trigg : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            cfd_pulse_trig <= '0';
        elsif rising_edge(CLK_I) then
            -- asserted at + 4 cycles
            cfd_pulse_trig <= zero_cross_flag and pulse_incoming;
        end if;
    end process p_trigg;

    ----------------------------------------------------------------------------
    -- Delays (shift register inst)
    ----------------------------------------------------------------------------

    -- delay for cfd
    sr_d : entity trap_filter.shift_register
        generic map(
            G_DATA_WIDTH  => G_DATA_WIDTH,
            G_DELAY_VALUE => C_CFD_D_DELAY,
            G_REG_INPUT   => 1
        )
        port map(
            CLK_I    => CLK_I,
            RST_N_I  => RST_N_I,
            DATA_I   => DATA_I,
            DATA_D_O => data_del_d
        );

    -- delay for slope computation
    sr_m : entity trap_filter.shift_register
        generic map(
            G_DATA_WIDTH  => G_DATA_WIDTH,
            G_DELAY_VALUE => C_CFD_M_DELAY,
            G_REG_INPUT   => 1
        )
        port map(
            CLK_I    => CLK_I,
            RST_N_I  => RST_N_I,
            DATA_I   => DATA_I,
            DATA_D_O => data_del_m
        );

end architecture rtl;