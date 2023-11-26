-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2023 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): xkacka00 <login AT stud.fit.vutbr.cz>
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
  signal PC_first : std_logic;

  -- PTR (ukazatel do pamate dat)
  signal PTR_addr : std_logic_vector(12 downto 0);
  signal PTR_inc : std_logic;
  signal PTR_dec : std_logic;

  --CNT (while counter)
  signal CNT_data : std_logic_vector(12 downto 0) := (others => '0');
  signal CNT_inc : std_logic;
  signal CNT_dec : std_logic;
  signal CNT_one : std_logic;

  -- flag if @ was found in code
  signal found : std_logic;

  -- MX1_sel
  signal MX1_sel : std_logic;
  -- 0 adresa programu
  -- 1 adresa dat

  -- MX2
  signal MX2_sel : std_logic_vector(1 downto 0);
  -- 00 hodnota zo vstupu
  -- 01 hodnota z aktualnej bunky +1
  -- 10 hodnota z aktualnej bunky -1
  -- 11 posledna citana hodnota z pamate

  -- FSM
  type fsm_states is (
    waiting,
    start, start2,
    fetch,
    decode,
    increment_ptr,
    decrement_ptr,
    increment_val,
    end_increment_val,
    decrement_val,
    end_decrement_val,
    while_start, while_start2, while_start3, 
    while_end, while_end2, while_end3, while_end4,
    break, break2, break3,
    put_char, put_char_end,
    get_char,
    sreturn,
    sothers
  );
  signal state : fsm_states := start;
  signal next_state : fsm_states;

begin

 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --      - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --      - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly. 

  pc: process(CLK, RESET, PC_inc, PC_dec) 
  begin
        if (RESET = '1' or PC_first = '1') then
          PC_addr <= (others => '0');
        elsif (rising_edge(CLK)) then
          if (PC_inc = '1') then
            PC_addr <= PC_addr + 1;
          elsif (PC_dec = '1') then
            PC_addr <= PC_addr - 1;
          end if;
        end if;
  end process;

  ptr: process(CLK, RESET, PTR_inc, PTR_dec)
  begin 
        if (RESET = '1') then
          PTR_addr <= (others => '0');
        elsif (rising_edge(CLK)) then
          if (PTR_inc = '1') then
            PTR_addr <= PTR_addr + 1;
          elsif (PTR_dec = '1') then
            PTR_addr <= PTR_addr - 1;
          end if;
        end if;
  end process;

  cnt: process(CLK, RESET, CNT_inc, CNT_dec, CNT_one)
  begin
        if (rising_edge(CLK)) then
          if (CNT_inc = '1') then
            CNT_data <= CNT_data + 1;
          elsif (CNT_dec = '1') then
            CNT_data <= CNT_data - 1;
          elsif (CNT_one = '1') then
            CNT_data <= "0000000000001";
          end if;
        end if;
  end process;

  MX1 : process (PC_addr, PTR_addr, MX1_sel)
     begin
          case MX1_sel is
               when '0'    => DATA_ADDR <= PC_addr;
               when '1'    => DATA_ADDR <= PTR_addr;
               when others => null;
          end case;
    end process;

  -- MX1: process(MX1_sel)
  -- begin
  --       case MX1_sel is
  --         when '0' =>
  --           DATA_ADDR <= PC_addr;
  --         when '1' =>
  --           DATA_ADDR <= PTR_addr;
  --         when others =>
  --           PTR_addr <= PTR_addr;
  --       end case;
  -- end process;

  --DATA_ADDR <= PC_addr when MX1_sel = '0' else PTR_addr;

  MX2 : process (IN_DATA, DATA_RDATA, MX2_sel)
     begin
          case MX2_sel is
               when "00"   => DATA_WDATA <= IN_DATA;
               when "01"   => DATA_WDATA <= DATA_RDATA;
               when "10"   => DATA_WDATA <= DATA_RDATA - 1;
               when "11"   => DATA_WDATA <= DATA_RDATA + 1;
               when others => null;
          end case;
     end process;

  --MX2: process(CLK, RESET)
  -- DATA_WDATA <= IN_DATA when MX2_sel = "00" else  -- input
  --               DATA_RDATA + 1 when MX2_sel = "01" else -- aktualna bunka -1
  --               DATA_RDATA - 1 when MX2_sel = "10" else -- aktualna bunka +1
  --               DATA_RDATA when MX2_sel = "11";  -- posledna citana hodnota z pamate
  
  fsm: process(CLK, RESET)
  begin
        if (RESET = '1') then
          state <= start;
        elsif (rising_edge(CLK)) then
          if (RESET = '0' and EN = '1') then
            state <= next_state;
          end if;
        end if;
  end process;

  fsm_next_logic: process(state, EN, DATA_RDATA, IN_VLD, OUT_BUSY)
  begin 
          PC_inc <= '0';
          PC_dec <= '0';
          PC_first <= '0';
          --PC_addr <= '0';

          found <= '0';
          PTR_inc <= '0';
          PTR_dec <= '0';
          DONE <= '0';

          CNT_inc <= '0';
          CNT_dec <= '0';
          CNT_one <= '0';

          DATA_RDWR <= '0';
          DATA_EN <= '0';

          IN_REQ <= '0';
          OUT_WE <= '0';
          OUT_DATA <= X"00";
          --CNT_data <= (others => '0');

          MX1_sel <= '0';
          MX2_sel <= "00";

          case state is 

            -- when waiting =>
            --   if (EN = '1') then     
            --     MX1_sel <= '0';  
            --     DATA_EN <= '1';
            --     DATA_RDWR <= '0';         
            --     next_state <= start;
            --   else
            --     next_state <= waiting;
            --   end if;

            when start =>
              -- DATA_EN <= '1';
              -- DATA_RDWR <= '0';
              -- MX1_sel <= '0';
              -- if ((DATA_RDATA = "000000000000") and (found = '1')) then
              --   PC_inc <= '1';
              --   PTR_inc <= '1';
              --   next_state <= fetch;
              -- end if;

              -- -- if ((DATA_RDATA /= "000000000000") and (found = '1')) then
              -- --   next_state <= fetch;
              -- -- end if;

              -- if (DATA_RDATA = X"40") then
              --   found <= '1';
              --   DATA_EN <= '1';
              --   READY <= '1';
              --   PTR_inc <= '1';
              --   PC_addr <= (others => '0');
              --   next_state <= start;
              -- else
              --   READY <= '0';
              --   PTR_inc <= '1';
              --   PC_inc <= '1';
              --   next_state <= start2;
              -- end if;

              DATA_EN <= '1';
              DATA_RDWR <= '0';
              MX1_sel <= '0';

              if (DATA_RDATA = X"40") then 
                DATA_EN <= '0';
                READY <= '1';
                --PTR_inc <= '1';
                PC_first <= '1';
                next_state <= fetch;
              else 
                READY <= '0';
                PTR_inc <= '1';
                PC_inc <= '1';
                next_state <= start;
              end if;

            when start2 =>
                next_state <= start;

            when fetch =>
              DATA_EN <= '1';
              next_state <= decode;

            when decode =>
              case (DATA_RDATA) is
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
                --DATA_EN <= '1';
                PTR_inc <= '1';
                PC_inc <= '1';
                next_state <= fetch;

            when decrement_ptr =>
                ptr_dec <= '1';
                PC_inc <= '1';
                next_state <= fetch;

            when increment_val =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                MX1_sel <= '1';
                next_state <= end_increment_val;

            when end_increment_val =>
                MX1_sel <= '1';
                MX2_sel <= "11";
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                PC_inc <= '1';
                next_state <= fetch;

            when decrement_val =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                MX1_sel <= '1';
                next_state <= end_decrement_val;

            when end_decrement_val =>
                MX1_sel <= '1';
                MX2_sel <= "10";
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                PC_inc <= '1';
                next_state <= fetch;

            when while_start =>
              PC_inc <= '1'; -- posun na dalsiu instrukciu
              MX1_sel <= '1'; -- vyber pamate dat
              DATA_EN <= '1'; -- povolenie citania
              DATA_RDWR <= '0'; -- citanie
              next_state <= while_start2; 

            when while_start2 =>
                if (DATA_RDATA = (DATA_RDATA'range => '0')) then
                  CNT_inc <= '1'; -- inkrementuj pocitadlo
                  MX1_sel <= '0'; -- vyber pamate programu
                  DATA_EN <= '1'; -- povolenie citania
                  DATA_RDWR <= '0'; -- citanie
                  next_state <= while_start3; 
                else
                  next_state <= fetch; -- ak je hodnota v pamati rozna od 0, posun na dalsiu instrukciu
                end if;
                            
            when while_start3 =>
                if (CNT_data /= (CNT_data'range => '0')) then 
                  if (DATA_RDATA = X"5B") then -- ak je hodnota v pamati 5B, inkrementuj pocitadlo
                    CNT_inc <= '1'; 
                  elsif (DATA_RDATA = X"5D") then -- ak je hodnota v pamati 5D, dekrementuj pocitadlo
                    CNT_dec <= '1'; 
                  end if;
                  PC_inc <= '1'; -- posun na dalsiu instrukciu
                  MX1_sel <= '0'; -- vyber pamate programu
                  DATA_EN <= '1'; -- povolenie citania
                  DATA_RDWR <= '0'; -- citanie
                  next_state <= while_start3; 
                else
                  --PC_inc <= '1'; -- posun na dalsiu instrukciu
                  next_state <= fetch; -- ak je pocitadlo 0, posun na dalsiu instrukciu
                end if;
             
            when while_end =>
                MX1_sel <= '1'; -- vyber pamate dat
                DATA_EN <= '1'; -- povolenie citania
                DATA_RDWR <= '0'; -- citanie 
                next_state <= while_end2; 

            when while_end2 =>
                if (DATA_RDATA = (DATA_RDATA'range => '0')) then -- ak je hodnota v pamati 0, posun na dalsiu instrukciu
                  PC_inc <= '1'; 
                  next_state <= fetch; 
                else 
                  CNT_one <= '1'; -- ak je hodnota v pamati rozna od 0, nastav pocitadlo na 1
                  PC_dec <= '1'; -- posun na predchadzajucu instrukciu
                  next_state <= while_end3; 
                end if;
                
            when while_end3 =>
                MX1_sel <= '0'; -- vyber pamate programu
                DATA_EN <= '1'; -- povolenie citania
                DATA_RDWR <= '0'; -- citanie
                if (CNT_data = (CNT_data'range => '0')) then  
                  next_state <= fetch;
                else 
                  if (DATA_RDATA = X"5B") then -- ak je hodnota v pamati 5B, dekrementuj pocitadlo
                      CNT_dec <= '1';
                  elsif (DATA_RDATA = X"5D") then -- ak je hodnota v pamati 5D, inkrementuj pocitadlo
                      CNT_inc <= '1';
                  end if;
                    next_state <= while_end4;  
                end if;

            when while_end4 =>  
                if (CNT_data = (CNT_data'range => '0')) then -- ak je pocitadlo 0, posun na dalsiu instrukciu ak nie posun na predchadzajucu
                  PC_inc <= '1';
                else
                  PC_dec <= '1';
                end if;
                next_state <= while_end3;

            when break =>
                if (CNT_data = (CNT_data'range => '0')) then 
                  PC_inc <= '1';
                  MX1_sel <= '0';
                  DATA_EN <= '1';
                  DATA_RDWR <= '0';
                  next_state <= break2;
                else 
                  PC_inc <= '1';
                  MX1_sel <= '0';
                  next_state <= break3;
                end if;

            when break2 =>
                if (DATA_RDATA = X"5B") then -- ak je hodnota v pamati 5B, inkrementuj pocitadlo
                  CNT_inc <= '1';
                  --PC_inc <= '1';

                  next_state <= break2;
                elsif (DATA_RDATA = X"5D") then -- ak je hodnota v pamati 5D, dekrementuj pocitadlo
                  --PC_inc <= '1';
                  if (CNT_data = (CNT_data'range => '0')) then

                    next_state <= fetch;
                  else
                    CNT_dec <= '1';
                    next_state <= break2;
                  end if;
                else
                  PC_inc <= '1';
                  next_state <= break;
                end if;

            when break3 =>
                if (DATA_RDATA = X"5B") then -- ak je hodnota v pamati 5B, inkrementuj pocitadlo
                CNT_inc <= '1';
                --PC_inc <= '1';
                next_state <= break;
                elsif (DATA_RDATA = X"5D") then -- ak je hodnota v pamati 5D, dekrementuj pocitadlo
                  PC_inc <= '1';
                  CNT_dec <= '1';
                  next_state <= fetch;
                else
                  PC_inc <= '1';
                  next_state <= break;
                end if;
            
                -- when break =>
            --     PC_inc <= '1';
            --     CNT_inc <= '1';
            --     next_state <= break2;

            -- when break2 =>
            --     if (CNT_data = (CNT_data'range => '0')) then 
            --       next_state <= fetch;
            --     else
            --       DATA_EN <= '1';
            --       -- PC_inc <= '1';
            --       MX1_sel <= '1';
            --       DATA_RDWR <= '0';
            --       next_state <= break3;
            --     end if;

            -- when break3 =>
            --     if (DATA_RDATA = X"5B") then
            --       CNT_inc <= '1';
            --       PC_inc <= '1';
            --       next_state <= break2;
            --     elsif (DATA_RDATA = X"5D") then
            --       CNT_dec <= '1';
            --       PC_inc <= '1';
            --       next_state <= break2;
            --     else
            --       next_state <= break3;
            --     end if;
            

            when put_char =>
                if (OUT_BUSY = '1') then 
                  DATA_RDWR <= '0';
                  DATA_EN <= '1';
                  MX1_sel <= '1';
                  next_state <= put_char;
                else
                  DATA_RDWR <= '0';
                  DATA_EN <= '1';
                  MX1_sel <= '1';
                  next_state <= put_char_end;
                end if;

            when put_char_end =>
                OUT_WE <= '1';
                OUT_DATA <= DATA_RDATA;
                PC_inc <= '1';
                next_state <= fetch;

            when get_char =>
                in_req <= '1';
                if (IN_VLD = '1') then
                  DATA_EN <= '1';
                  DATA_RDWR <= '1';
                  MX1_sel <= '1';
                  MX2_sel <= "00";
                  PC_inc <= '1';
                  next_state <= fetch;
                else
                  next_state <= get_char;
                end if;

            when sreturn =>
                DONE <= '1';
                next_state <= sreturn;

            when sothers =>
                PC_inc <= '1';
                next_state <= fetch;

            when others =>
                PC_inc <= '1';
                next_state <= fetch;
          end case;
  end process;


end behavioral;

