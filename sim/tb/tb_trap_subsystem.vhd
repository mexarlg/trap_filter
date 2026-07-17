--==============================================================================
--  Testbench:     tb_trap_subsystem
--  Description:   Testbench for mov_avg_filter
--  Author:        Aldo Lupio
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity tb_trap_subsystem is
end entity;

architecture tb of tb_trap_subsystem is

    ----------------------------------------------------------------------------
    -- Test configuration
    ----------------------------------------------------------------------------

    constant CLK_PERIOD : time := 8 ns;

    -- Jordanov params configuration
    constant C_ADC_WIDTH    : natural := 14;
    constant C_K_RISE_WIDTH : natural := 6; -- k  = 2^K_RISE_WIDTH
    constant C_M_FLAT_WIDTH : natural := 7; -- m  = 2^M_FLAT_WIDTH

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

    -- input signals
    signal tb_ce            : std_logic                                  := '0';
    signal tb_data_i        : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');
    signal tb_baseline_trig : std_logic                                  := '0';

    -- tb output signals
    signal tb_data_filtered       : std_logic_vector(C_ADC_WIDTH downto 0) := (others => '0');
    signal tb_data_filtered_valid : std_logic;
    signal tb_stat_error          : std_logic_vector(5 downto 0) := (others => '0');

    -- validation signals between python output and filtered data
    signal tb_data_ref   : std_logic_vector(C_ADC_WIDTH downto 0) := (others => '0'); -- python filtered output
    signal tb_sync_pulse : std_logic                              := '0';             -- pulse indicating first current sample at n from data_i

begin

    ----------------------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------------------

    tb_clk <= not tb_clk after CLK_PERIOD/2;

    ----------------------------------------------------------------------------
    -- DUT Instantiation
    ----------------------------------------------------------------------------

    dut : entity trap_filter.trap_subsystem
        generic map(
            -- Data parameters
            G_DATA_WIDTH => C_ADC_WIDTH,
            -- Jordanov params
            G_K_RISE_WIDTH => C_K_RISE_WIDTH,
            G_M_FLAT_WIDTH => C_M_FLAT_WIDTH,
            G_M_VALUE      => C_M_EXP_VALUE,
            G_M_FRAC_WIDTH => 4,
            -- Jordanov fixed point params
            G_DIFF_MARGIN_BITS => 3,
            G_ACC1_MARGIN_BITS => 2,
            G_ACC2_MARGIN_BITS => 1,
            G_OUT_SHIFT        => 17,
            -- Moving average params
            G_DELAY_WIDTH     => 4,
            G_ACC_MARGIN_BITS => 2
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
            CE_I            => tb_ce,
            DATA_I          => tb_data_i,
            BASELINE_TRIG_I => tb_baseline_trig,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_FILTERED_O       => tb_data_filtered,
            DATA_FILTERED_VALID_O => tb_data_filtered_valid,
            STAT_ERROR_O          => tb_stat_error
        );

    ----------------------------------------------------------------------------
    -- Reference vs output validation
    ----------------------------------------------------------------------------

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
        variable v_cnt  : integer := 0;
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
                -- start of data pulse
                tb_sync_pulse <= '1' when v_sync = 1 else
                    '0';
                tb_baseline_trig <= '1' when v_cnt = 200 else
                    '0';
                wait until rising_edge(tb_clk);
            end if;
            v_cnt := v_cnt + 1;
        end loop;

        file_close(fin);

        wait for 4000 ns;

        -- toggle of CE
        tb_ce <= '0';
        wait for 80 ns;

        ------------------------------------------------------------------------
        -- Simulation done
        ------------------------------------------------------------------------
        wait for 200 ns;
        assert false report "Simulation finished" severity failure;
        wait;
    end process p_stimulus;

end architecture tb;