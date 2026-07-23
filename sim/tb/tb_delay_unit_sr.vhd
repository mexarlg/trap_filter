--==============================================================================
--  Testbench:     tb_delay_unit_sr
--  Description:   Testbench for delay_unit_sr
--  Author:        Aldo Lupio
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity tb_delay_unit_sr is
end entity;

architecture tb of tb_delay_unit_sr is

    ----------------------------------------------------------------------------
    -- Test configuration
    ----------------------------------------------------------------------------

    -- 125 Mhz
    constant CLK_PERIOD : time := 8 ns;

    -- Moving average configuration
    constant C_DELAY_WIDTH : natural := 3;                  -- Bit width of delay
    constant C_DELAY_VALUE : natural := 2 ** C_DELAY_WIDTH; -- Value of delay
    constant C_ADC_WIDTH   : natural := 14;                 -- Bit width of adc (magnitude)

    -- Sign configuration of input pulse -> Needs to be changed in waveform
    constant C_DATA_SIGNED         : natural := 1;                              -- '1' if signed, '0' if unsigned
    constant C_UNSIGNED_PULSE_FILE : string  := "noisy_pulse_14b_unsigned.txt"; -- Name of unsigned input pulse file (and mov avg ref) from python
    constant C_SIGNED_PULSE_FILE   : string  := "noisy_pulse_15b_signed.txt";   -- Name of signed input pulse file (and mov avg ref) from python

    ----------------------------------------------------------------------------    
    -- DUT Signals
    ----------------------------------------------------------------------------

    -- clk / rst_n
    signal tb_clk   : std_logic := '0';
    signal tb_rst_n : std_logic := '0';

    -- tb signals of delay_unit_sr
    signal tb_ce           : std_logic                                                  := '0';
    signal tb_data_i       : std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED - 1 downto 0) := (others => '0');
    signal tb_data_d       : std_logic_vector(C_ADC_WIDTH + C_DATA_SIGNED - 1 downto 0) := (others => '0');
    signal tb_data_d_valid : std_logic                                                  := '0';

    -- data_i start inpulse
    signal tb_sync_pulse : std_logic := '0';

begin

    ----------------------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------------------

    tb_clk <= not tb_clk after CLK_PERIOD/2;

    ----------------------------------------------------------------------------
    -- DUT Instantiation
    ----------------------------------------------------------------------------

    dut : entity trap_filter.delay_unit_sr
        generic map(
            G_DATA_WIDTH  => C_ADC_WIDTH,
            G_DELAY_VALUE => C_DELAY_VALUE,
            G_DATA_SIGNED => C_DATA_SIGNED
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
            DATA_D_O       => tb_data_d,
            DATA_D_VALID_O => tb_data_d_valid
        );

    ----------------------------------------------------------------------------
    -- Stimulus: reset, enable, then stream samples
    ----------------------------------------------------------------------------

    p_stimulus : process
        -- variables for reading .txt for input pulse
        file fin        : text;
        variable status : file_open_status;
        variable ln     : line;
        variable good   : boolean;
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
            read(ln, v_ref, good);  -- line value, second element value (reference pulse), success flag
            read(ln, v_sync, good); -- line value, second element value (sync pulse), success flag
            if good then
                if C_DATA_SIGNED = 0 then
                    tb_data_i <= std_logic_vector(to_unsigned(v_ref, C_ADC_WIDTH + C_DATA_SIGNED));
                else
                    tb_data_i <= std_logic_vector(to_signed(v_ref, C_ADC_WIDTH + C_DATA_SIGNED));
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