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
    constant C_DELAY_WIDTH     : natural := 3;                  -- Bit width of delay
    constant C_ADC_WIDTH       : natural := 14;                 -- Bit width of adc (magnitude)
    constant C_ACC_MARGIN_BITS : natural := 2;                  -- Margin bits for accumulator signal (at worst case, 1MB holds 7 extra cycles, 2 MB holds 15 extra cycles)
    constant C_WINDOW          : natural := 2 ** C_DELAY_WIDTH; -- Value of the delay (all bits of DELAY_WIDTH => '1')

    -- Sign configuration of input pulse -> Needs to be changed in waveform
    constant C_DATA_SIGNED         : natural := 1;                              -- '1' if signed, '0' if unsigned
    constant C_UNSIGNED_PULSE_FILE : string  := "noisy_pulse_14b_unsigned.txt"; -- Name of unsigned input pulse file (and mov avg ref) from python
    constant C_SIGNED_PULSE_FILE   : string  := "noisy_pulse_15b_signed.txt";   -- Name of signed input pulse file (and mov avg ref) from python

    -- Chosen maximum (at sight in waveform) to generate a trigger to capture
    constant C_MAX_TRIGGER : signed := to_signed(-309, C_ADC_WIDTH + C_DATA_SIGNED);

    -- Max value of ADC data for overflow check on accumulator (max value of data_n, 0 value of data_d -> addition on each cycle)
    constant C_MAX_VAL  : std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED - 1 downto 0) := std_logic_vector(to_signed(2 ** C_ADC_WIDTH - 1, C_ADC_WIDTH + C_DATA_SIGNED)); -- to give to data_n
    constant C_ZERO_VAL : std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED - 1 downto 0) := (others => '0');                                                                -- to give to data_d
    ----------------------------------------------------------------------------    
    -- DUT Signals
    ----------------------------------------------------------------------------

    -- clk / rst_n
    signal tb_clk   : std_logic := '0';
    signal tb_rst_n : std_logic := '0';

    -- tb input signals of mov_avg_filter
    signal tb_ce                : std_logic                                                  := '0';
    signal tb_data_n            : std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED - 1 downto 0) := (others => '0');
    signal tb_data_n_reg        : std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED - 1 downto 0) := (others => '0');
    signal tb_data_d            : std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED - 1 downto 0) := (others => '0');
    signal tb_data_d_valid      : std_logic                                                  := '0';
    signal tb_capture_data_trig : std_logic                                                  := '0';

    -- tb output signals of mov_avg_filter
    signal tb_filt_data          : std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED - 1 downto 0) := (others => '0');
    signal tb_filt_data_valid    : std_logic                                                  := '0';
    signal tb_capture_data       : std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED - 1 downto 0) := (others => '0');
    signal tb_capture_data_valid : std_logic                                                  := '0';

    -- tb status
    signal tb_stat_error : std_logic_vector(3 downto 0) := (others => '0');

    -- verification and synchronization of python pulse
    signal tb_sample_valid : std_logic                                                      := '0';             -- valid flag for delayed simulation of data
    signal tb_data_ref     : std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED - 1 downto 0)     := (others => '0'); -- python filtered output
    signal tb_data_ref_q0  : std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED - 1 downto 0)     := (others => '0'); -- python filtered output delayed +1 cycles    
    signal tb_data_ref_q1  : std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED - 1 downto 0)     := (others => '0'); -- python filtered output delayed +2 cycles     
    signal tb_data_diff    : std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED + 1 - 1 downto 0) := (others => '0'); -- error between (delayed +2 cycles) python and filtered output
    signal tb_sync_pulse   : std_logic                                                      := '0';             -- pulse indicating first current sample at n

    ----------------------------------------------------------------------------
    -- Delay line model
    ----------------------------------------------------------------------------
    type t_delay_line is array (0 to C_WINDOW - 1) of
    std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED - 1 downto 0);
    signal delay_line : t_delay_line := (others => (others => '0'));

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
            G_DATA_SIGNED     => C_DATA_SIGNED      -- Data signed (1) or unsigned (0)
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
            CE_I                => tb_ce,
            DATA_N_I            => tb_data_n_reg,
            DATA_D_I            => tb_data_d,
            DATA_D_VALID_I      => tb_data_d_valid,
            CAPTURE_DATA_TRIG_I => tb_capture_data_trig,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            FILT_DATA_O          => tb_filt_data,          -- (delay_cycles + 2 cycles)
            FILT_DATA_VALID_O    => tb_filt_data_valid,    -- (delay_cycles + 2 cycles)
            CAPTURE_DATA_O       => tb_capture_data,       -- (delay_cycles + 3 cycles)
            CAPTURE_DATA_VALID_O => tb_capture_data_valid, -- (delay_cycles + 3 cycles)
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            STAT_ERROR_O => tb_stat_error -- error signal
        );

    ----------------------------------------------------------------------------
    -- Delay model
    ----------------------------------------------------------------------------

    tb_data_d <= delay_line(C_WINDOW - 1);

    -- Shift registers, simulates the delay
    p_delay_line : process (tb_clk)
        variable fill_count : integer := 0;
    begin
        if rising_edge(tb_clk) then
            if (tb_rst_n = '0') then
                delay_line      <= (others => (others => '0'));
                tb_data_d_valid <= '0';
                fill_count := 0;

            elsif (tb_ce = '1' and tb_sample_valid = '1') then

                -- update delay line from current sample
                delay_line(1 to C_WINDOW - 1) <= delay_line(0 to C_WINDOW - 2);
                delay_line(0)                 <= tb_data_n_reg;

                -- detection of filled delays
                if fill_count < C_WINDOW then
                    fill_count := fill_count + 1;
                end if;

                -- one extra cycle delay for valid
                if fill_count >= C_WINDOW then
                    tb_data_d_valid <= '1';
                end if;
            end if;
        end if;
    end process p_delay_line;

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
            if C_DATA_SIGNED = 1 then
                v_diff :=
                    resize(signed(tb_data_ref_q1), v_diff'length) -
                    resize(signed(tb_filt_data), v_diff'length);
            else
                v_diff :=
                    signed(resize(unsigned(tb_data_ref_q1), v_diff'length)) -
                    signed(resize(unsigned(tb_filt_data), v_diff'length));
            end if;

            tb_data_diff <= std_logic_vector(v_diff);
        end if;
    end process p_diff;

    -- Generate a trigger at the maximum (chosen value at sight) of the input signal (has 1 cycle of latency)
    p_capture_trigg : process (tb_clk)
    begin
        if rising_edge(tb_clk) then
            -- 1 sample before the maximum (either signed or unsigned data, the conversion will make it work)
            if (signed(tb_data_n) = C_MAX_TRIGGER) then
                tb_capture_data_trig <= '1';
            else
                tb_capture_data_trig <= '0';
            end if;
        end if;
    end process p_capture_trigg;

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
        tb_ce           <= '0';
        tb_sample_valid <= '0';
        tb_rst_n        <= '0';
        wait for 50 ns;
        tb_rst_n <= '1';

        wait for 100 ns;
        wait until rising_edge(tb_clk);
        tb_ce <= '1';

        ------------------------------------------------------------------------
        -- Open the stimulus input pulse file
        ------------------------------------------------------------------------
        if integer(C_DATA_SIGNED) = 1 then
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
            read(ln, v_in, good);   -- line value, first element value (input pulse), success flag
            read(ln, v_ref, good);  -- line value, second element value (reference pulse), success flag
            read(ln, v_sync, good); -- line value, second element value (sync pulse), success flag
            if good then
                if C_DATA_SIGNED = 0 then
                    tb_data_n     <= std_logic_vector(to_unsigned(v_in, C_ADC_WIDTH + C_DATA_SIGNED));
                    tb_data_n_reg <= tb_data_n;
                    tb_data_ref   <= std_logic_vector(to_unsigned(v_ref, C_ADC_WIDTH + C_DATA_SIGNED));
                    -- Added 2 cycle delay to ref output, filter has 2 cycle latency
                    tb_data_ref_q0 <= tb_data_ref;
                    tb_data_ref_q1 <= tb_data_ref_q0;
                else
                    tb_data_n     <= std_logic_vector(to_signed(v_in, C_ADC_WIDTH + C_DATA_SIGNED));
                    tb_data_n_reg <= tb_data_n;
                    --tb_data_n   <= C_MAX_VAL; -- for cont overflow test
                    tb_data_ref <= std_logic_vector(to_signed(v_ref, C_ADC_WIDTH + C_DATA_SIGNED));
                    -- Added 2 cycle delay to ref output, filter has 2 cycle latency
                    tb_data_ref_q0 <= tb_data_ref;
                    tb_data_ref_q1 <= tb_data_ref_q0;
                end if;
                -- pulse triggered when first data is sampled (data_n, not delayed version or data_d)
                tb_sync_pulse <= '1' when v_sync = 1 else
                    '0';
                tb_sample_valid <= '1';
                wait until rising_edge(tb_clk);
            end if;
        end loop;

        tb_sample_valid <= '0';
        file_close(fin);

        -- toggle of CE
        tb_ce <= '0';
        wait for 50 ns;
        tb_ce <= '1';
        wait for 50 ns;
        tb_ce <= '0';

        ------------------------------------------------------------------------
        -- Simulation done
        ------------------------------------------------------------------------
        wait for 200 ns;
        assert false report "Simulation finished" severity failure;
        wait;
    end process p_stimulus;

end architecture tb;