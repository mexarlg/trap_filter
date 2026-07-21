--==============================================================================
--  Testbench:     tb_mov_avg_filter
--  Description:   Testbench for mov_avg_filter
--  Author:        Aldo Lupio
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;
use trap_filter.tb_mov_avg_filter_pkg.all;

entity tb_mov_avg_filter is
end entity;

architecture tb of tb_mov_avg_filter is

    ----------------------------------------------------------------------------
    -- Test configuration
    ----------------------------------------------------------------------------

    -- Moving average configuration
    constant C_DELAY_WIDTH     : natural := 6;                  -- Bit width of delay
    constant C_DELAY_VALUE     : natural := 2 ** C_DELAY_WIDTH; -- Value of delay
    constant C_ADC_WIDTH       : natural := 14;                 -- Bit width of adc (magnitude)
    constant C_ACC_MARGIN_BITS : natural := 2;                  -- Margin bits for accumulator signal (at worst case, 1MB holds 7 extra cycles, 2 MB holds 15 extra cycles)

    -- Sign configuration of input pulse -> Needs to be changed in waveform
    constant C_DATA_I_SIGNED       : natural := 1;                              -- '1' if signed, '0' if unsigned
    constant C_UNSIGNED_PULSE_FILE : string  := "noisy_pulse_14b_unsigned.txt"; -- Name of unsigned input pulse file (and mov avg ref) from python
    constant C_SIGNED_PULSE_FILE   : string  := "noisy_pulse_15b_signed.txt";   -- Name of signed input pulse file (and mov avg ref) from python

    -- Chosen maximum (at sight in waveform) to generate a trigger to capture
    constant C_MAX_TRIGGER : signed := to_signed(-309, C_ADC_WIDTH + C_DATA_I_SIGNED);

    -- Max value of ADC data for overflow check on accumulator (max value of data_n, 0 value of data_d -> addition on each cycle)
    constant C_MAX_VAL  : std_logic_vector(C_ADC_WIDTH + C_DATA_I_SIGNED - 1 downto 0) := std_logic_vector(to_signed(2 ** C_ADC_WIDTH - 1, C_ADC_WIDTH + C_DATA_I_SIGNED)); -- to give to data_n
    constant C_ZERO_VAL : std_logic_vector(C_ADC_WIDTH + C_DATA_I_SIGNED - 1 downto 0) := (others => '0');                                                                  -- to give to data_d
    ----------------------------------------------------------------------------    
    -- DUT Signals
    ----------------------------------------------------------------------------

    -- clk / rst_n
    signal tb_clk   : std_logic := '0';
    signal tb_rst_n : std_logic := '0';

    -- input signal to shift register
    signal tb_ce     : std_logic                                                    := '0';
    signal tb_data_i : std_logic_vector(C_ADC_WIDTH + C_DATA_I_SIGNED - 1 downto 0) := (others => '0');

    -- tb input signals of mov_avg_filter
    signal tb_data_n       : std_logic_vector(C_ADC_WIDTH + C_DATA_I_SIGNED - 1 downto 0) := (others => '0');
    signal tb_data_d       : std_logic_vector(C_ADC_WIDTH + C_DATA_I_SIGNED - 1 downto 0) := (others => '0');
    signal tb_data_d_valid : std_logic                                                    := '0';

    -- tb output signals of mov_avg_filter
    signal tb_data_filtered : std_logic_vector(C_ADC_WIDTH + C_DATA_I_SIGNED - 1 downto 0) := (others => '0');
    signal tb_error_oflow   : std_logic                                                    := '0';

    -- validation signals between python output and filtered data by mov_avg_filter (sync the latency etc)
    signal tb_data_ref    : std_logic_vector(C_ADC_WIDTH + C_DATA_I_SIGNED - 1 downto 0)     := (others => '0'); -- python filtered output
    signal tb_data_ref_q0 : std_logic_vector(C_ADC_WIDTH + C_DATA_I_SIGNED - 1 downto 0)     := (others => '0'); -- python filtered output delayed +1 cycles    
    signal tb_data_ref_q1 : std_logic_vector(C_ADC_WIDTH + C_DATA_I_SIGNED - 1 downto 0)     := (others => '0'); -- python filtered output delayed +2 cycles     
    signal tb_data_diff   : std_logic_vector(C_ADC_WIDTH + C_DATA_I_SIGNED + 1 - 1 downto 0) := (others => '0'); -- error between (delayed +2 cycles) python and filtered output
    signal tb_sync_pulse  : std_logic                                                        := '0';             -- pulse indicating first current sample at n from data_i

begin

    ----------------------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------------------

    tb_clk <= not tb_clk after CLK_PERIOD/2;

    ----------------------------------------------------------------------------
    -- DUT Instantiation
    ----------------------------------------------------------------------------

    dut : entity trap_filter.mov_avg_filter
        generic map(
            G_DATA_WIDTH      => C_ADC_WIDTH,       -- Width of incoming data stream
            G_DELAY_WIDTH     => C_DELAY_WIDTH,     -- Width of delay signal (4b-> delay of 16 samples, 5b->32 and so on)
            G_ACC_MARGIN_BITS => C_ACC_MARGIN_BITS, -- Number of margin bits given to the accumulator
            G_DATA_I_SIGNED   => C_DATA_I_SIGNED    -- Data signed (1) or unsigned (0)
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
            CE_I     => tb_ce,
            DATA_N_I => tb_data_n,
            DATA_D_I => tb_data_d,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            DATA_FILTERED_O => tb_data_filtered,
            ERROR_OFLOW_O   => tb_error_oflow
        );

    sr : entity trap_filter.delay_unit_sr
        generic map(
            G_DATA_WIDTH  => C_ADC_WIDTH,
            G_DELAY_VALUE => C_DELAY_VALUE,
            G_DATA_SIGNED => C_DATA_I_SIGNED
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
            DATA_D_O       => tb_data_d,
            DATA_D_VALID_O => tb_data_d_valid
        );

    ----------------------------------------------------------------------------
    -- Reference vs output validation
    ----------------------------------------------------------------------------

    -- Error between the filtered output and the expected outcome from python
    -- Notice that the difference is made with the delayed (+2 cycles) version of data_ref
    -- since the filter has a latency of 2 cycles
    p_diff : process (tb_clk)
        variable v_diff : signed(tb_data_diff'length - 1 downto 0);
    begin
        if rising_edge(tb_clk) then
            if C_DATA_I_SIGNED = 1 then
                v_diff :=
                    resize(signed(tb_data_ref_q1), v_diff'length) -
                    resize(signed(tb_data_filtered), v_diff'length);
            else
                v_diff :=
                    signed(resize(unsigned(tb_data_ref_q1), v_diff'length)) -
                    signed(resize(unsigned(tb_data_filtered), v_diff'length));
            end if;

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
        if integer(C_DATA_I_SIGNED) = 1 then
            file_open(status, fin, C_SIGNED_PULSE_FILE, read_mode);
        else
            file_open(status, fin, C_UNSIGNED_PULSE_FILE, read_mode);
        end if;

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
                if C_DATA_I_SIGNED = 0 then
                    -- give data_i to shift register
                    tb_data_i   <= std_logic_vector(to_unsigned(v_in, C_ADC_WIDTH + C_DATA_I_SIGNED));
                    tb_data_ref <= std_logic_vector(to_unsigned(v_ref, C_ADC_WIDTH + C_DATA_I_SIGNED));
                    -- Added 2 cycle delay to ref output, filter has 2 cycle latency
                    tb_data_ref_q0 <= tb_data_ref;
                    tb_data_ref_q1 <= tb_data_ref_q0;
                else
                    -- give data_i to shift register
                    tb_data_i   <= std_logic_vector(to_signed(v_in, C_ADC_WIDTH + C_DATA_I_SIGNED));
                    tb_data_ref <= std_logic_vector(to_signed(v_ref, C_ADC_WIDTH + C_DATA_I_SIGNED));
                    -- Added 2 cycle delay to ref output, filter has 2 cycle latency
                    tb_data_ref_q0 <= tb_data_ref;
                    tb_data_ref_q1 <= tb_data_ref_q0;
                end if;
                tb_sync_pulse <= '1' when v_sync = 1 else
                    '0';
                wait until rising_edge(tb_clk);
            end if;
        end loop;

        file_close(fin);

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