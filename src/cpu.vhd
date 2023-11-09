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

-- FSM
type fsm_states is (
  start,
  fetch,
  decode,
  increment_ptr,
  decrement_ptr,
  increment_val,
  decrement_val,
  while_start,
  while_end,
  break,
  print,
  get_char,
  sreturn,
);

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
        elseif (CLK'event and CLK = '1') then
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
          PTR_addr <= (others => '0');
        elsif (CLK'event and CLK = '1') then
          if (PTR_inc = '1') then
            PTR_addr <= PTR_addr + 1;
          elsif (PTR_dec = '1') then
            PTR_addr <= PTR_addr - 1;
          end if;
        end if;
  end process;




end behavioral;

