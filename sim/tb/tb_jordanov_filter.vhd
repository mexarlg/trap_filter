--==============================================================================
--  Testbench:     tb_jordanov_filter
--  Description:   Testbench for mov_avg_filter
--  Author:        Aldo Lupio
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;
use trap_filter.tb_jordanov_filter_pkg.all;

entity tb_jordanov_filter is
end entity;

architecture tb of tb_jordanov_filter is

    ----------------------------------------------------------------------------
    -- Test configuration
    ----------------------------------------------------------------------------

    -- Jordanov params configuration
    constant C_ADC_WIDTH    : natural := 14;
    constant C_K_RISE_WIDTH : natural := 6; -- k  = 2^K_RISE_WIDTH
    constant C_M_FLAT_WIDTH : natural := 7; -- m  = 2^M_FLAT_WIDTH

    -- Delay values
    constant C_K_RISE_DELAY : natural := 2 ** C_K_RISE_WIDTH;             -- k  = 2^K_RISE_WIDTH
    constant C_M_FLAT_DELAY : natural := 2 ** C_M_FLAT_WIDTH;             -- m  = 2^M_FLAT_WIDTH
    constant C_L_DELAY      : natural := C_K_RISE_DELAY + C_M_FLAT_DELAY; -- l  = k + m
    constant C_KL_DELAY     : natural := C_K_RISE_DELAY + C_L_DELAY;      -- k + l = 2k + m

    -- Exp decay
    constant C_M_EXP_VALUE : natural := 39992; -- round(2499.5 * 2^4), M_FRAC = 4

    -- Sign configuration of input pulse -> Needs to be changed in waveform
    constant C_UNSIGNED_PULSE_FILE : string := "noisy_pulse_14b_unsigned_jord.txt"; -- Name of unsigned input pulse file (and mov avg ref) from python

    ----------------------------------------------------------------------------    
    -- DUT Signals
    ----------------------------------------------------------------------------

    -- clk / rst_n
    signal tb_clk   : std_logic := '0';
    signal tb_rst_n : std_logic := '0';

    -- input signal to shift register
    signal tb_ce     : std_logic                                  := '0';
    signal tb_data_i : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');

    -- tb input signals of jordanov_filter
    signal tb_data_n  : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');
    signal tb_data_k  : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');
    signal tb_data_l  : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');
    signal tb_data_kl : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');

    -- tb signals of synchronizer
    signal tb_delay_jord_ready : std_logic_vector(2 downto 0) := (others => '0');
    signal tb_data_jord_valid  : std_logic                    := '0';
    signal tb_error_sync       : std_logic_vector(1 downto 0) := (others => '0');

    -- tb output signals of mov_avg_filter
    signal tb_data_filtered : std_logic_vector(C_ADC_WIDTH downto 0) := (others => '0');
    signal tb_error_oflow   : std_logic_vector(1 downto 0)           := (others => '0');

    -- validation signals between python output and filtered data by mov_avg_filter (sync the latency etc)
    signal tb_data_ref    : std_logic_vector(C_ADC_WIDTH downto 0) := (others => '0'); -- python filtered output
    signal tb_data_ref_q0 : std_logic_vector(C_ADC_WIDTH downto 0) := (others => '0'); -- python filtered output delayed +1 cycles    
    signal tb_data_ref_q1 : std_logic_vector(C_ADC_WIDTH downto 0) := (others => '0'); -- python filtered output delayed +2 cycles     

    signal tb_data_diff  : std_logic_vector(C_ADC_WIDTH + 1 downto 0) := (others => '0'); -- error between delayed python and filtered output
    signal tb_sync_pulse : std_logic                                  := '0';             -- pulse indicating first current sample at n from data_i

begin

    ----------------------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------------------

    tb_clk <= not tb_clk after CLK_PERIOD/2;

    ----------------------------------------------------------------------------
    -- DUT Instantiation
    ----------------------------------------------------------------------------

    dut : entity trap_filter.jordanov_filter
        generic map(
            -- Jordanov parameters
            G_DATA_WIDTH   => C_ADC_WIDTH,
            G_K_RISE_WIDTH => C_K_RISE_WIDTH,
            -- Exponential decay
            G_M_VALUE      => C_M_EXP_VALUE,
            G_M_FRAC_WIDTH => 4,
            -- Fixed point params
            G_DIFF_MARGIN_BITS => 3,
            G_ACC1_MARGIN_BITS => 2,
            G_ACC2_MARGIN_BITS => 1,
            G_OUT_SHIFT        => 17
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => tb_clk,
            RST_N_I => tb_rst_n,
            ------------------------------------------------------------------------
            -- Control Inputs
            ------------------------------------------------------------------------
            CE_I      => tb_ce,
            DATA_N_I  => tb_data_n,
            DATA_K_I  => tb_data_k,
            DATA_L_I  => tb_data_l,
            DATA_KL_I => tb_data_kl,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_FILTERED_O => tb_data_filtered,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            ERROR_OFLOW_O => tb_error_oflow
        );

    u_synchronizer : entity trap_filter.valid_tracker
        generic map(
            G_JORD_LATENCY => 6,
            G_JORD_K_WIDTH => C_K_RISE_WIDTH,
            G_JORD_M_WIDTH => C_M_FLAT_WIDTH,
            G_MOV_LATENCY  => 2,
            G_MOV_D_WIDTH  => 4
        )
        port map(
            CLK_I              => tb_clk,
            RST_N_I            => tb_rst_n,
            CE_I               => tb_ce,
            DELAY_JORD_READY_I => tb_delay_jord_ready,
            DELAY_MOV_READY_I  => '0',
            DATA_JORD_VALID_O  => tb_data_jord_valid,
            DATA_MOV_VALID_O   => open,
            ERROR_SYNC_O       => tb_error_sync
        );

    sr_k : entity trap_filter.delay_unit_sr
        generic map(
            G_DATA_WIDTH  => C_ADC_WIDTH,
            G_DELAY_VALUE => C_K_RISE_DELAY,
            G_DATA_SIGNED => 0
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => tb_clk,
            RST_N_I => tb_rst_n,
            ------------------------------------------------------------------------
            -- Control Inputs
            ------------------------------------------------------------------------
            CE_I   => tb_ce,
            DATA_I => tb_data_i,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_N_O       => open,
            DATA_D_O       => tb_data_k,
            DATA_D_VALID_O => tb_delay_jord_ready(2)
        );

    sr_l : entity trap_filter.delay_unit_sr
        generic map(
            G_DATA_WIDTH  => C_ADC_WIDTH,
            G_DELAY_VALUE => C_L_DELAY,
            G_DATA_SIGNED => 0
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => tb_clk,
            RST_N_I => tb_rst_n,
            ------------------------------------------------------------------------
            -- Control Inputs
            ------------------------------------------------------------------------
            CE_I   => tb_ce,
            DATA_I => tb_data_i,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_N_O       => open,
            DATA_D_O       => tb_data_l,
            DATA_D_VALID_O => tb_delay_jord_ready(1)
        );

    sr_kl : entity trap_filter.delay_unit_sr
        generic map(
            G_DATA_WIDTH  => C_ADC_WIDTH,
            G_DELAY_VALUE => C_KL_DELAY,
            G_DATA_SIGNED => 0
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I   => tb_clk,
            RST_N_I => tb_rst_n,
            ------------------------------------------------------------------------
            -- Control Inputs
            ------------------------------------------------------------------------
            CE_I   => tb_ce,
            DATA_I => tb_data_i,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_N_O       => tb_data_n,
            DATA_D_O       => tb_data_kl,
            DATA_D_VALID_O => tb_delay_jord_ready(0)
        );

    ----------------------------------------------------------------------------
    -- Reference vs output validation
    ----------------------------------------------------------------------------

    p_diff : process (tb_clk)
        variable v_diff : signed(tb_data_diff'length - 1 downto 0);
    begin
        if rising_edge(tb_clk) then
            v_diff :=
                signed(resize(unsigned(tb_data_ref_q1), v_diff'length)) -
                signed(resize(unsigned(tb_data_filtered), v_diff'length));
            tb_data_diff <= std_logic_vector(v_diff);
        end if;
    end process p_diff;

    ----------------------------------------------------------------------------
    -- Stimulus: reset, enable, then stream samples from the file per clock.
    ----------------------------------------------------------------------------

    p_stimulus : process
        -- variables for reading .txt for input pulse
        file fin        : text;
        variable status : file_open_status;
        variable ln     : line;
        variable good   : boolean;
        variable v_in   : integer;
        variable v_ref  : integer;
        variable v_sync : integer;
    begin

        ------------------------------------------------------------------------
        -- Reset / CE
        ------------------------------------------------------------------------

        tb_ce    <= '0';
        tb_rst_n <= '0';
        wait for 50 ns;
        tb_rst_n <= '1';

        wait for 100 ns;
        wait until rising_edge(tb_clk);
        tb_ce <= '1';

        ------------------------------------------------------------------------
        -- Open the stimulus input pulse file
        ------------------------------------------------------------------------

        file_open(status, fin, C_UNSIGNED_PULSE_FILE, read_mode);
        if status /= open_ok then
            report "Could not open stimulus file."
                severity failure;
        end if;

        ------------------------------------------------------------------------
        -- Stream one sample per clock
        ------------------------------------------------------------------------
        while not endfile(fin) loop
            readline(fin, ln);      -- read line
            read(ln, v_in, good);   -- line value, second element value (input pulse), success flag
            read(ln, v_ref, good);  -- line value, second element value (reference pulse), success flag
            read(ln, v_sync, good); -- line value, second element value (sync pulse), success flag
            if good then
                -- give data_i to shift register
                tb_data_i   <= std_logic_vector(to_unsigned(v_in, C_ADC_WIDTH));
                tb_data_ref <= std_logic_vector(to_signed(v_ref, C_ADC_WIDTH + 1));
                -- added 2 cycle delay to ref output, filter has 2 cycle latency
                tb_data_ref_q0 <= tb_data_ref;
                -- start of data pulse
                tb_sync_pulse <= '1' when v_sync = 1 else
                    '0';
                wait until rising_edge(tb_clk);
            end if;
        end loop;

        file_close(fin);

        wait for 4000 ns;

        -- toggle of CE
        tb_ce <= '0';
        wait for 80 ns;
        tb_ce <= '1';
        wait for 80 ns;
        tb_ce <= '0';

        ------------------------------------------------------------------------
        -- Simulation done
        ------------------------------------------------------------------------
        wait for 200 ns;
        assert false report "Simulation finished" severity failure;
        wait;
    end process p_stimulus;

end architecture tb;