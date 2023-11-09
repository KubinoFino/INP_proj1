-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2023 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): jmeno <login AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
   DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

  -- PC (ukazatel do pamate programu)
  signal PC_addr : std_logic_vector(12 downto 0);
  signal PC_inc : std_logic;
  signal PC_dec : std_logic;

  -- PTR (ukazatel do pamate dat)
  signal PTR_addr : std_logic_vector(12 downto 0);
  signal PTR_inc : std_logic;
  signal PTR_dec : std_logic;

  --CNT (while counter)
  signal CNT_data : std_logic_vector(12 downto 0);
  signal CNT_inc : std_logic;
  signal CNT_dec : std_logic;
  signal CNT_one : std_logic;

  -- MX1
  signal MX1 : std_logic_vector(0 downto 0) := "0";
  -- 0 adresa programu
  -- 1 adresa dat

  -- MX2
  signal MX2 : std_logic_vector(1 downto 0) := "00";
  -- 00 hodnota zo vstupu
  -- 01 hodnota z aktualnej bunky +1
  -- 10 hodnota z aktualnej bunky -1
  -- 11 posledna citana hodnota z pamate

  -- FSM
  type fsm_states is (
    start,
    fetch,
    decode,
    increment_ptr,
    decrement_ptr,
    increment_val,
    end_increment_val,
    decrement_val,
    end_decrement_val,
    while_start,
    while_end,
    break,
    put_char,
    get_char,
    sreturn,
    sothers
  );
  signal state : fsm_states := start;
  signal next_state : fsm_states := start;

begin

 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --      - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --      - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly. 

  pc: process(CLK, RESET) 
  begin
        if (RESET = '1') then
          PC_addr <= (others => '0');
        elsif (CLK'event) and (CLK = '1') then
          if (PC_inc = '1') then
            PC_addr <= PC_addr + 1;
          elsif (PC_dec = '1') then
            PC_addr <= PC_addr - 1;
          end if;
        end if;
  end process;

  ptr: process(CLK, RESET)
  begin 
        if (RESET = '1') then
          PTR_addr <= "1000000000000";
        elsif (CLK'event) and (CLK = '1') then
          if (PTR_inc = '1') then
            PTR_addr <= PTR_addr + 1;
          elsif (PTR_dec = '1') then
            PTR_addr <= PTR_addr - 1;
          end if;
        end if;
  end process;

  cnt: process(CLK, RESET)
  begin
        if (RESET = '1') then
          CNT_data <= (others => '0');
        elsif (CLK'event) and (CLK = '1') then
          if (CNT_inc = '1') then
            CNT_data <= CNT_data + 1;
          elsif (CNT_dec = '1') then
            CNT_data <= CNT_data - 1;
          elsif (CNT_one = '1') then
            CNT_data <= "0000000000001";
          end if;
        end if;
  end process;

  DATA_ADDR <= PC_addr when MX1 = "0" else PTR_addr;

  DATA_WDATA <= IN_DATA when MX2 = "00" else
                DATA_RDATA + 1 when MX2 = "01" else
                DATA_RDATA - 1 when MX2 = "10" else
                DATA_RDATA when MX2 = "11";

  fsm: process(CLK, RESET)
  begin
        if (RESET = '1') then
          state <= start;
        elsif (CLK'event and CLK = '1') then
          state <= next_state;
        end if;
  end process;

  fsm_next: process(state, EN, DATA_RDATA, IN_VLD, OUT_BUSY, DATA_RDATA)
  begin 
          PC_inc <= '0';
          PC_dec <= '0';

          PTR_inc <= '0';
          PTR_dec <= '0';
          READY <= '1';
          DONE <= '0'; 
          
          CNT_inc <= '0';
          CNT_dec <= '0';
          CNT_one <= '0';

          DATA_RDWR <= '0';
          DATA_EN <= '0';

          IN_REQ <= '0';
          OUT_WE <= '0';

          case state is 
            when start =>
              next_state <= fetch;

            when fetch =>
              DATA_EN <= '1';
              next_state <= decode;

            when decode =>
              case DATA_RDATA is
                when X"3E" => 
                    next_state <= increment_ptr;
                when X"3C" =>
                    next_state <= decrement_ptr;
                when X"2B" =>
                    next_state <= increment_val;
                when X"2D" =>
                    next_state <= decrement_val;
                when X"5B" =>
                    next_state <= while_start;
                when X"5D" => 
                    next_state <= while_end;
                when X"7E" =>
                    next_state <= break;
                when X"2E" =>
                    next_state <= put_char;
                when X"2C" =>
                    next_state <= get_char;
                when X"40" =>
                    next_state <= sreturn;
                when others =>
                    next_state <= sothers;
            end case;
            
            when increment_ptr =>
                ptr_inc <= '1';
                pc_inc <= '1';
                next_state <= fetch;

            when decrement_ptr =>
                ptr_dec <= '1';
                pc_inc <= '1';
                next_state <= fetch;

            when increment_val =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                MX1 <= "1";
                next_state <= end_increment_val;

            when end_increment_val =>
                MX2 <= "01";
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                pc_inc <= '1';
                next_state <= fetch;

            when decrement_val =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                MX1 <= "1";
                next_state <= end_decrement_val;

            when end_decrement_val =>
                MX2 <= "10";
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                pc_inc <= '1';
                next_state <= fetch;

            when while_start =>
                data_en <= '1';
                data_rdwr <= '0';
                mx1 <= "1";
                mx2 <= "00";
                if (DATA_RDATA = "000000000000") then
                  next_state <= while_end;
                else
                  next_state <= fetch;
                end if;

            when while_end =>
                data_en <= '1';
                data_rdwr <= '0';
                mx1 <= "1";
                mx2 <= "00";
                if (DATA_RDATA = "000000000000") then
                  next_state <= fetch;
                else
                  next_state <= while_start;
                end if;

            when break =>
                data_en <= '1';
                data_rdwr <= '0';
                mx1 <= "1";
                mx2 <= "00";
                next_state <= fetch;

            when put_char =>
                out_we <= '1';
                out_data <= DATA_RDATA;
                if (OUT_BUSY = '0') then
                  next_state <= fetch;
                else
                  next_state <= put_char;
                end if;

            when get_char =>
                in_req <= '1';
                if (IN_VLD = '1') then
                  data_en <= '1';
                  data_rdwr <= '1';
                  mx1 <= "1";
                  mx2 <= "00";
                  next_state <= fetch;
                else
                  next_state <= get_char;
                end if;

            when sreturn =>
                pc_dec <= '1';
                next_state <= fetch;

            when sothers =>
                next_state <= fetch;

            when others =>
                next_state <= fetch;
          end case;
  end process;


end behavioral;

