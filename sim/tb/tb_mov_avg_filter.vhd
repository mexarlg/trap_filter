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

    constant C_DELAY_WIDTH : integer := 3;                  -- Bit width of delay
    constant C_ADC_WIDTH   : integer := 14;                 -- Bit width of adc
    constant C_WINDOW      : integer := 2 ** C_DELAY_WIDTH; -- Value of delay (all => '1')
    constant C_PULSE_FILE  : string  := "stimulus.txt";     -- Name of input pulse file from python

    ----------------------------------------------------------------------------
    -- DUT Signals
    ----------------------------------------------------------------------------

    signal tb_clk   : std_logic := '0';
    signal tb_rst_n : std_logic := '0';

    -- tb input signals
    signal tb_ce          : std_logic                                  := '0';
    signal tb_data_n      : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');
    signal tb_data_d      : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');
    signal tb_delay_ready : std_logic                                  := '0';
    signal tb_sample_trig : std_logic                                  := '0';

    -- tb output signals
    signal tb_filt_data     : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');
    signal tb_captured_data : std_logic_vector(C_ADC_WIDTH - 1 downto 0) := (others => '0');
    signal tb_captured_trig : std_logic                                  := '0';
    signal tb_ready         : std_logic                                  := '0';

    -- verification
    signal tb_sample_valid : std_logic := '0';

    ----------------------------------------------------------------------------
    -- Delay line model: reproduces the memory module that would provide
    ----------------------------------------------------------------------------

    type t_delay_line is array (0 to C_WINDOW - 1) of
    std_logic_vector(C_ADC_WIDTH - 1 downto 0);
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
            G_DATA_WIDTH      => C_ADC_WIDTH,   -- Width of incoming data stream
            G_DELAY_WIDTH     => C_DELAY_WIDTH, -- Width of delay signal (4b-> delay of 16 samples, 5b->32 and so on)
            G_ACC_MARGIN_BITS => 1,             -- Number of margin bits given to the accumulator
            G_DATA_SIGNED     => 0              -- Data signed (1) or unsigned (0)
        )
        port map(
            ------------------------------------------------------------------------
            -- Clock / Reset
            ------------------------------------------------------------------------
            CLK_I => tb_clk,
            RST_N => tb_rst_n,
            ------------------------------------------------------------------------
            -- Control Inputs
            ------------------------------------------------------------------------
            CE_I          => tb_ce,
            DATA_N_I      => tb_data_n,
            DATA_D_I      => tb_data_d,
            DELAY_READY   => tb_delay_ready,
            SAMPLE_TRIG_I => tb_sample_trig,
            ------------------------------------------------------------------------
            -- Outputs
            ------------------------------------------------------------------------
            FILT_DATA_O     => tb_filt_data,     -- (delay cycles + 1 cycle)
            CAPTURED_DATA_O => tb_captured_data, -- (delay cycles + 2 cycles)
            CAPTURED_TRIG_O => tb_captured_trig,
            READY_O         => tb_ready
        );

    ----------------------------------------------------------------------------
    -- Delay model
    ----------------------------------------------------------------------------

    p_delay_line : process (tb_clk)
        variable fill_count : integer := 0;
    begin
        if rising_edge(tb_clk) then
            if (tb_rst_n = '0') then
                delay_line     <= (others => (others => '0'));
                tb_data_d      <= (others => '0');
                tb_delay_ready <= '0';
                fill_count := 0;
            elsif (tb_ce = '1' and tb_sample_valid = '1') then
                -- oldest sample drives DATA_D_I
                tb_data_d <= delay_line(C_WINDOW - 1);

                -- shift newest at index 0
                delay_line(1 to C_WINDOW - 1) <= delay_line(0 to C_WINDOW - 2);
                delay_line(0)                 <= tb_data_n;

                -- buffer filled detection
                if fill_count < C_WINDOW then
                    fill_count := fill_count + 1;
                end if;
                if fill_count >= C_WINDOW then
                    tb_delay_ready <= '1';
                end if;
            end if;
        end if;
    end process p_delay_line;

    -- Generate a trigger at the maximum of the input signal (1 cycle before)
    p_capture_trigg : process (tb_clk)
    begin
        if rising_edge(tb_clk) then
            -- 1 sample before the maximum
            if (unsigned(tb_data_n) = to_unsigned(8924, tb_data_n'length)) then
                tb_sample_trig <= '1';
            else
                tb_sample_trig <= '0';
            end if;
        end if;
    end process p_capture_trigg;

    ----------------------------------------------------------------------------
    -- Stimulus: reset, enable, then stream samples from the file per clock.
    ----------------------------------------------------------------------------

    p_stimulus : process
        file fin        : text;
        variable status : file_open_status;
        variable ln     : line;
        variable good   : boolean;
        variable v_in   : integer;
    begin
        ------------------------------------------------------------------------
        -- Reset
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
        file_open(status, fin, C_PULSE_FILE, read_mode);
        if status /= open_ok then
            report "Could not open stimulus file: " & C_PULSE_FILE
                severity failure;
        end if;

        ------------------------------------------------------------------------
        -- Stream one sample per clock
        ------------------------------------------------------------------------
        while not endfile(fin) loop
            readline(fin, ln);
            read(ln, v_in, good); -- first token as integer
            if good then
                tb_data_n       <= std_logic_vector(to_unsigned(v_in, C_ADC_WIDTH));
                tb_sample_valid <= '1';
                wait until rising_edge(tb_clk);
            end if;
        end loop;

        tb_sample_valid <= '0';
        file_close(fin);

        ------------------------------------------------------------------------
        -- Simulation done
        ------------------------------------------------------------------------
        wait for 200 ns;
        assert false report "Simulation finished" severity failure;
        wait;
    end process p_stimulus;

end architecture tb;