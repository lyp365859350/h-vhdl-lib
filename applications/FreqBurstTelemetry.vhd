library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

Library UNIMACRO;
use UNIMACRO.vcomponents.all;


entity FreqBurstTelemetry is
    port (
        CLK                     : in std_logic;
        RST                     : in std_logic;
        
        SERIAL_RX               : in std_logic;
        SERIAL_TX               : out std_logic;
        
				-- TX data
        VALID_IN                : in std_logic;
        I_ADC										: in std_logic_vector(15 downto 0);
        Q_ADC										: in std_logic_vector(15 downto 0);
        CYCLE_COUNT 						: in std_logic_vector(7 downto 0);        
        SAMPLE_COUNT						: in std_logic_vector(15 downto 0); -- could roll over

				-- RX data
        VALID_OUT               : out std_logic;
        CYCLES							    : out std_logic_vector(7 downto 0); -- cycles-1
        FREQ_START							: out std_logic_vector(3 downto 0);
        FREQ_END								: out std_logic_vector(3 downto 0);
        TIME_PRE	    					: out std_logic_vector(15 downto 0); -- units of samples
        TIME_STEP			  				: out std_logic_vector(15 downto 0); -- units of samples
        TIME_POST 	  					: out std_logic_vector(15 downto 0) -- units of samples
    );
end FreqBurstTelemetry;


architecture Behavioral of FreqBurstTelemetry is

	-- RX signals
  signal packet_rx_data_sig        : std_logic_vector(SYMBOL_WIDTH*DATA_SYMBOLS-1 downto 0);

  signal serial_valid_sig       : std_logic;
  signal serial_data_sig        : std_logic_vector(SYMBOL_WIDTH-1 downto 0);

	-- TX signals
  signal fifo_tx_ready_sig            : std_logic;
  signal fifo_tx_not_valid_sig            : std_logic;
  signal fifo_tx_valid_sig            : std_logic;
  signal packet_tx_ready_sig            : std_logic;
  signal packet_tx_valid_sig            : std_logic;
  signal uart_tx_ready_sig            : std_logic;

  signal fifo_tx_data_sig          : std_logic_vector(SYMBOL_WIDTH*PACKET_SYMBOLS-1 downto 0);
  signal packet_tx_data_sig          : std_logic_vector(SYMBOL_WIDTH*(PACKET_SYMBOLS+HEADER_SYMBOLS)-1 downto 0);
  signal packet_tx_symbol_sig          : std_logic_vector(SYMBOL_WIDTH-1 downto 0);


begin    

		CYCLES 			<= packet_rx_data_reg_sig(8*9-1 downto 8*8);
		FREQ_START 	<= packet_rx_data_reg_sig(8*8-1  downto 8*7+4);
		FREQ_END 		<= packet_rx_data_reg_sig(8*7+3  downto 8*7);
		TIME_PRE 		<= packet_rx_data_reg_sig(8*7-1 downto 8*5);
		TIME_STEP 	<= packet_rx_data_reg_sig(8*5-1 downto 8*3);
		TIME_POST 	<= packet_rx_data_reg_sig(8*3-1 downto 0);

    SerialRx_module: entity work.SerialRx
        generic map (
        SAMPLE_PERIOD_WIDTH 	=> 1;
        SAMPLE_PERIOD 			=> 1;
        DETECTOR_PERIOD_WIDTH 	=> 4;
        DETECTOR_PERIOD 		=> 16; -- sample detector MA filter
        DETECTOR_LOGIC_HIGH 	=> 12; -- 12..15 is high
        DETECTOR_LOGIC_LOW 		=> 3;  -- 0..3 is low
        BIT_TIMER_WIDTH 		=> 8;
        BIT_TIMER_PERIOD 		=> 100; -- clk_freq/sample_period/100
        VALID_LAG 				=> 50   -- when to start looking for a VALID signal
        )
        port map (
            CLK 					=> CLK,
            EN 						=> '1',
            RST 					=> RST,
            RX 						=> SERIAL_RX,
            VALID 					=> serial_rx_valid_sig,
            DATA 					=> serial_rx_data_sig,
            ALARM 					=> SERIAL_ALARM
        );
    
    PacketRx_module: entity work.PacketRx
        generic map (
            SYMBOL_WIDTH        => 8,
            DATA_SYMBOLS      	=> 9,
            HEADER_SYMBOLS      => 2
        )
        port map (
            CLK                 => CLK,
            RST                 => RST,
            
            HEADER_IN           => x"0102",
            SYMBOL_IN           => serial_rx_data_sig,

            VALID_IN            => serial_rx_valid_sig,
            READY_OUT           => open,
            VALID_OUT           => VALID,
           	READY_IN            => '1',
        
            DATA_OUT            => packet_rx_data_sig
        );




    FIFO_Tx_module : FIFO_SYNC_MACRO
    generic map (
--        DEVICE              => "7SERIES",             -- Target Device: "VIRTEX5, "VIRTEX6", "7SERIES" 
--        ALMOST_FULL_OFFSET  => X"0080",               -- Sets almost full threshold
--        ALMOST_EMPTY_OFFSET => X"0080",               -- Sets the almost empty threshold
        DATA_WIDTH          => 32                    -- Valid values are 1-72 (37-72 only valid when FIFO_SIZE="36Kb")
--        FIFO_SIZE           => "18Kb"               -- Target BRAM, "18Kb" or "36Kb" 
    )
    port map (
        CLK                 => CLK,                 -- 1-bit input clock
        RST                 => RST,                 -- 1-bit input reset
        -- input path
        DI                  => DATA_IN,        -- Input data, width defined by DATA_WIDTH parameter
        WREN                => VALID_IN,       -- 1-bit input write enable
        -- output path
        DO                  => fifo_tx_data_sig,       -- Output data, width defined by DATA_WIDTH parameter
        RDEN                => fifo_tx_ready_sig,        -- 1-bit input read enable
        EMPTY               => fifo_tx_not_valid_sig   -- 1-bit output empty
    );
    
    fifo_tx_valid_sig <= not fifo_tx_not_valid_sig;
    packet_tx_data_sig <= HEADER_IN & fifo_tx_data_sig;

    PacketTx_module: entity work.PacketTx
        generic map (
            SYMBOL_WIDTH        => SYMBOL_WIDTH,
            PACKET_SYMBOLS      => PACKET_SYMBOLS + HEADER_SYMBOLS
        )
        port map (
            CLK                 => CLK,
            RST                 => RST,
            
            PACKET_IN           => packet_tx_data_sig,

            VALID_IN            => fifo_tx_valid_sig,            
            READY_OUT           => packet_tx_ready_sig,
            VALID_OUT           => packet_tx_valid_sig,
            READY_IN            => uart_tx_ready_sig,
            
            SYMBOL_OUT          => packet_tx_symbol_sig
        );
    
    TX_module: entity work.SerialTx
        port map (
            -- inputs
            CLK                 => CLK,
            EN                  => '1',
            RST                 => RST,
            BIT_TIMER_PERIOD    => SERIAL_PERIOD,
            VALID               => packet_tx_valid_sig,
            DATA                => packet_tx_symbol_sig,
            -- outputs
            READY               => uart_tx_ready_sig,
            TX                  => SERIAL_TX
        );


end Behavioral;