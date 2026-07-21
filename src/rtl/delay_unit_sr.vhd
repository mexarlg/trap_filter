--==============================================================================
--  Module:        delay_unit_sr.vhd
--  Project:       trap_filter
--  Author:        aldo lupio
--  Created:       09/07/2026
--  Last Modified: 
--
--  Description:
--  Delay unit that implements shift register logic for the mov_avg_filter delay.
--  For a delay value of = 8 (DELAY_WIDTH = 3), the following timing sequence is issued:
--  At cycle 0 (CE just asserted) -> Input data is registered
--  At cycle 1 -> Data #1 is introduced onto shift register
--  At cycle 8 -> Data #8 is introduced onto shift register (fullfilled!) and data_d_valid is high
--  At cycle 9 (DEPTH + 1) -> Data #9 is introduced onto shift register, Delay #1 (= Data #1) is output along Data #9
--
--  Dependencies:
--  CE asserted high while data is fed sync
-- 
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library trap_filter;
use trap_filter.trap_filter_pkg.all;

entity delay_unit_sr is
    generic (
        G_DATA_WIDTH  : natural range 4 to 16   := 14; -- Width of incoming data stream (ADC Magnitude resolution)
        G_DELAY_VALUE : natural range 2 to 4096 := 8;  -- Value of actual delayed (10 bit max width)
        G_DATA_SIGNED : natural range 0 to 1    := 0   -- Data signed (1) or unsigned (0) -> DATA_OUT_WIDTH = DATA_WIDTH + DATA_SIGNED
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
        CE_I   : in std_logic;                                                   -- Chip enable
        DATA_I : in std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0); -- Input data sync with CE
        ------------------------------------------------------------------------
        -- Outputs
        ------------------------------------------------------------------------
        DATA_D_O       : out std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0); -- Delayed Data for sample N
        DATA_D_VALID_O : out std_logic                                                    -- Valid flag when delayed data is ready (shift reg is full, asserted on last cycle)
    );
end entity delay_unit_sr;

architecture rtl of delay_unit_sr is

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------

    -- Used to extract the required bits needed to represent an unsigned value
    function clog2 (n : natural) return natural is
        variable r        : natural := 0;
        variable v        : natural := n;
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

    -- Value of the delay and its required bit width (to represent 2^N samples, or 0 to 2^N - 1)
    constant C_DELAY_WIDTH : natural := clog2(G_DELAY_VALUE);

    -- Limits for delay valid counter (Need counter flag high on counter = DEPTH (since cycle 0 is not valid) 
    -- so CNT_D_VALID = DELAY_DEPTH - 1 = 15 so flag can be asserted on cycle 16, and delay arrives at cycle 17)
    constant C_CNT_D_MAX  : std_logic_vector(C_DELAY_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(G_DELAY_VALUE - 1, C_DELAY_WIDTH));
    constant C_CNT_D_ONE  : std_logic_vector(C_DELAY_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, C_DELAY_WIDTH));
    constant C_CNT_D_ZERO : std_logic_vector(C_DELAY_WIDTH - 1 downto 0) := (others => '0');

    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------

    -- shift register array
    type sr_t is array (0 to G_DELAY_VALUE - 1) of std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0);
    signal sr : sr_t;

    -- shift register write enable
    signal wr_en : std_logic;

    -- shift register data input
    signal data_n : std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0);

    -- Output signals
    signal data_d       : std_logic_vector(G_DATA_WIDTH + G_DATA_SIGNED - 1 downto 0);
    signal data_d_valid : std_logic;

    -- counter for delayed data valid
    signal cnt_data_d : std_logic_vector(C_DELAY_WIDTH - 1 downto 0);

begin

    ----------------------------------------------------------------------------
    -- Assertions
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Output assignments
    ----------------------------------------------------------------------------

    DATA_D_O       <= data_d;
    DATA_D_VALID_O <= data_d_valid;

    ----------------------------------------------------------------------------
    -- Main Combinatory process
    ----------------------------------------------------------------------------

    -- shift register last tap (data_d)
    data_d <= sr(G_DELAY_VALUE - 1);

    ----------------------------------------------------------------------------
    -- Main sequential process
    ----------------------------------------------------------------------------

    -- shift register inferred for delay (should avoid rst to infer sr?)
    p_sr : process (CLK_I)
    begin
        if rising_edge(CLK_I) then
            if RST_N_I = '0' then
                sr <= (others => (others => '0'));
            elsif wr_en = '1' then
                sr <= data_n & sr(0 to G_DELAY_VALUE - 2);
            end if;
        end if;
    end process p_sr;

    -- registers input data
    p_reg : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            data_n <= (others => '0');
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                data_n <= DATA_I;
            end if;
        end if;
    end process p_reg;

    -- asserts write into sr when CE is high (1 cycle delay)
    p_wr : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            wr_en <= '0';
        elsif rising_edge(CLK_I) then
            wr_en <= CE_I;
        end if;
    end process p_wr;

    -- counter for data_d valid (shift reg has been filled)
    p_cnt : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            cnt_data_d <= C_CNT_D_ZERO;
        elsif rising_edge(CLK_I) then
            if (CE_I = '1') then
                -- Count until DEPTH - 1 (For DEPTH = 16 -> Count until 15, valid aserted on cycle 16, and data_d available on 17)
                if (unsigned(cnt_data_d) < unsigned(C_CNT_D_MAX)) then
                    cnt_data_d <= std_logic_vector(unsigned(cnt_data_d) + unsigned(C_CNT_D_ONE));
                end if;
            end if;
        end if;
    end process p_cnt;

    -- data is valid when CE is high and counter is latched at DEPTH - 1 (asserted at + 1 cycle)
    p_valid : process (CLK_I, RST_N_I)
    begin
        if (RST_N_I = '0') then
            data_d_valid <= '0';
        elsif rising_edge(CLK_I) then
            data_d_valid <= '0';
            if (CE_I = '1') then
                if (cnt_data_d = C_CNT_D_MAX) then
                    data_d_valid <= '1';
                end if;
            end if;
        end if;
    end process p_valid;

end architecture rtl;