`timescale 1ns / 1ps

module top(
    input  wire clk,        // 50MHz do Zynq
    input  wire rst_n,      // FCLK_RESET0_N do Zynq
    input  wire uart_rx,    
    output wire uart_tx,    
    output wire led_green,   
    output wire led_red    	
);

parameter CLK_FRE  = 50;    // Frequência do relógio em MHz
parameter UART_FRE = 115200; // Taxa de bauds UART 115200

parameter DIFFICULTY = 100000000; // Valor máximo de nonce para proof-of-work (100.000.000 iterações)

// ========================================
// ESTRATÉGIA OCTA SHA-1 CORE
// ========================================
// Implementação: 7 cores SHA-1 em paralelo para 7X velocidade de mineração
// - sha1_core_0 até sha1_core_7: processam nonce_0 até nonce_6 simultaneamente
// - nonce_0 é o registrador; nonce_1-7 são derivados combinacionalmente

// - Todos 8 cores executam SHA-1 simultaneamente
// - Incremento: nonce_0 += 8 a cada iteração
// - Resultado: até 8x velocidade vs. implementação com 1 core

// Mensagem de entrada (dinâmica): 40 bytes recebidos via UART, armazenados em buffer[0..39]
// Hash SHA-1 esperado: 40 caracteres ASCII hexadecimais recebidos via UART, armazenados em buffer[40..79]
// Hash representa 20 bytes binários (160 bits) para comparação SHA-1
reg [159:0] SHA1_EXPECTED;  // Hash SHA-1 esperado (160 bits = 20 bytes, decodificado de buffer[40..79])

// Variável nonce OCTA-core: 
// - nonce_0: valor atual (registrador) - SEQUENCIAL
// - nonce_1 a nonce_*: nonce_0 + 1 a nonce_0 + 6 - DERIVADOS COMBINACIONALMENTE
// Nota: 32 bits suportam até 4.294.967.295, mais que suficiente para 100.000.000 dificuldade
reg [31:0] nonce_0;  // Nonce para sha1_core_0  (incrementado +8)
wire [31:0] nonce_1;  // Nonce para sha1_core_1 (nonce_0 + 1) - wire combinacional
wire [31:0] nonce_2;  
wire [31:0] nonce_3;  
wire [31:0] nonce_4;  
wire [31:0] nonce_5;  
wire [31:0] nonce_6;  
wire [31:0] nonce_7;  

assign nonce_1 = nonce_0 + 32'd1;  // Sempre 1 a mais que nonce_0
assign nonce_2 = nonce_0 + 32'd2;  // Sempre 2 a mais que nonce_0
assign nonce_3 = nonce_0 + 32'd3;  // Sempre 3 a mais que nonce_0
assign nonce_4 = nonce_0 + 32'd4;  // ...
assign nonce_5 = nonce_0 + 32'd5;  
assign nonce_6 = nonce_0 + 32'd6;  
assign nonce_7 = nonce_0 + 32'd7;  

// Conversão ASCII do nonce: comprimento variável (sem zeros à esquerda)
// Máximo 9 bytes para valores até 999.999.999 (menos que 1.000.000.000)
// Exemplo: nonce=1        -> nonce_ascii="1"         (1 byte)
//          nonce=12345    -> nonce_ascii="12345"     (5 bytes)
//          nonce=120000000 -> nonce_ascii="120000000" (9 bytes)

// ASCII conversion para nonce_0 (registrador - atualizado a cada ciclo)
reg [71:0] nonce_ascii_0;  // Expandido para 72 bits (9 bytes = até 9 dígitos)
wire [3:0] nonce_ascii_len_0;  // Aumentado para 4 bits (suporta até 15 dígitos, usamos até 9)

// ASCII conversion para nonce_1 (registrador - atualizado a cada ciclo, derivado de nonce_0 + 1)
// Nota: Mudado de wire para reg porque recebe atribuições em always @(*)
reg [71:0] nonce_ascii_1;  // Expandido para 72 bits (9 bytes = até 9 dígitos)
wire [3:0] nonce_ascii_len_1;  // Aumentado para 4 bits (suporta até 15 dígitos, usamos até 9)

reg [71:0] nonce_ascii_2;  
wire [3:0] nonce_ascii_len_2;  

reg [71:0] nonce_ascii_3;  
wire [3:0] nonce_ascii_len_3;

reg [71:0] nonce_ascii_4;  
wire [3:0] nonce_ascii_len_4;

reg [71:0] nonce_ascii_5;  
wire [3:0] nonce_ascii_len_5;

reg [71:0] nonce_ascii_6;  
wire [3:0] nonce_ascii_len_6;

reg [71:0] nonce_ascii_7;  
wire [3:0] nonce_ascii_len_7;

// ========================================================================
// BCD Converter: converte nonce para 9 dígitos
// ========================================================================
wire [3:0] digit9_0, digit8_0, digit7_0, digit6_0, digit5_0, digit4_0, digit3_0, digit2_0, digit1_0;
wire [3:0] digit9_1, digit8_1, digit7_1, digit6_1, digit5_1, digit4_1, digit3_1, digit2_1, digit1_1;
wire [3:0] digit9_2, digit8_2, digit7_2, digit6_2, digit5_2, digit4_2, digit3_2, digit2_2, digit1_2;
wire [3:0] digit9_3, digit8_3, digit7_3, digit6_3, digit5_3, digit4_3, digit3_3, digit2_3, digit1_3;
wire [3:0] digit9_4, digit8_4, digit7_4, digit6_4, digit5_4, digit4_4, digit3_4, digit2_4, digit1_4;
wire [3:0] digit9_5, digit8_5, digit7_5, digit6_5, digit5_5, digit4_5, digit3_5, digit2_5, digit1_5;
wire [3:0] digit9_6, digit8_6, digit7_6, digit6_6, digit5_6, digit4_6, digit3_6, digit2_6, digit1_6;
wire [3:0] digit9_7, digit8_7, digit7_7, digit6_7, digit5_7, digit4_7, digit3_7, digit2_7, digit1_7;

nonce_bcd_simple bcd_inst_0 (
    .nonce(nonce_0),
    .digit9(digit9_0),
    .digit8(digit8_0),
    .digit7(digit7_0),
    .digit6(digit6_0),
    .digit5(digit5_0),
    .digit4(digit4_0),
    .digit3(digit3_0),
    .digit2(digit2_0),
    .digit1(digit1_0),
    .digit_count(nonce_ascii_len_0)
);

nonce_bcd_simple bcd_inst_1 (
    .nonce(nonce_1),
    .digit9(digit9_1),
    .digit8(digit8_1),
    .digit7(digit7_1),
    .digit6(digit6_1),
    .digit5(digit5_1),
    .digit4(digit4_1),
    .digit3(digit3_1),
    .digit2(digit2_1),
    .digit1(digit1_1),
    .digit_count(nonce_ascii_len_1)
);

nonce_bcd_simple bcd_inst_2 (
    .nonce(nonce_2),
    .digit9(digit9_2),
    .digit8(digit8_2),
    .digit7(digit7_2),
    .digit6(digit6_2),
    .digit5(digit5_2),
    .digit4(digit4_2),
    .digit3(digit3_2),
    .digit2(digit2_2),
    .digit1(digit1_2),
    .digit_count(nonce_ascii_len_2)
);

nonce_bcd_simple bcd_inst_3 (
    .nonce(nonce_3),
    .digit9(digit9_3),
    .digit8(digit8_3),
    .digit7(digit7_3),
    .digit6(digit6_3),
    .digit5(digit5_3),
    .digit4(digit4_3),
    .digit3(digit3_3),
    .digit2(digit2_3),
    .digit1(digit1_3),
    .digit_count(nonce_ascii_len_3)
);

nonce_bcd_simple bcd_inst_4 (
    .nonce(nonce_4),
    .digit9(digit9_4),
    .digit8(digit8_4),
    .digit7(digit7_4),
    .digit6(digit6_4),
    .digit5(digit5_4),
    .digit4(digit4_4),
    .digit3(digit3_4),
    .digit2(digit2_4),
    .digit1(digit1_4),
    .digit_count(nonce_ascii_len_4)
);

nonce_bcd_simple bcd_inst_5 (
    .nonce(nonce_5),
    .digit9(digit9_5),
    .digit8(digit8_5),
    .digit7(digit7_5),
    .digit6(digit6_5),
    .digit5(digit5_5),
    .digit4(digit4_5),
    .digit3(digit3_5),
    .digit2(digit2_5),
    .digit1(digit1_5),
    .digit_count(nonce_ascii_len_5)
);

nonce_bcd_simple bcd_inst_6 (
    .nonce(nonce_6),
    .digit9(digit9_6),
    .digit8(digit8_6),
    .digit7(digit7_6),
    .digit6(digit6_6),
    .digit5(digit5_6),
    .digit4(digit4_6),
    .digit3(digit3_6),
    .digit2(digit2_6),
    .digit1(digit1_6),
    .digit_count(nonce_ascii_len_6)
);

nonce_bcd_simple bcd_inst_7 (
    .nonce(nonce_7),
    .digit9(digit9_7),
    .digit8(digit8_7),
    .digit7(digit7_7),
    .digit6(digit6_7),
    .digit5(digit5_7),
    .digit4(digit4_7),
    .digit3(digit3_7),
    .digit2(digit2_7),
    .digit1(digit1_7),
    .digit_count(nonce_ascii_len_7)
);

// Bloco de mensagem: bloco de entrada de 512 bits com preenchimento (padrão RFC 3174 SHA-1)
// Estrutura dinâmica:
//   Bytes 0-39:  Mensagem (40 bytes) do buffer UART
//   Bytes 40+:   Nonce ASCII (1-9 bytes, comprimento variável, sem zeros à esquerda, até 120M)
//   Byte 47+:    0x80 (marcador de preenchimento) + bytes zero + comprimento_mensagem_bits (64-bit big-endian)

// ========== MESSAGE_BLOCK_0 para sha1_core_0 com nonce_0 ==========
reg [511:0] MESSAGE_BLOCK_0;
reg [511:0] MESSAGE_BLOCK_1;
reg [511:0] MESSAGE_BLOCK_2;
reg [511:0] MESSAGE_BLOCK_3;
reg [511:0] MESSAGE_BLOCK_4;
reg [511:0] MESSAGE_BLOCK_5;
reg [511:0] MESSAGE_BLOCK_6;
reg [511:0] MESSAGE_BLOCK_7;

// Calcular comprimento da mensagem em bits: (40 + nonce_ascii_len) * 8
wire [15:0] msg_length_bits_0 = 16'd320 + (nonce_ascii_len_0 << 3);  // 320 = 40*8, shift left 3 = multiply by 8
wire [15:0] msg_length_bits_1 = 16'd320 + (nonce_ascii_len_1 << 3);  
wire [15:0] msg_length_bits_2 = 16'd320 + (nonce_ascii_len_2 << 3);  
wire [15:0] msg_length_bits_3 = 16'd320 + (nonce_ascii_len_3 << 3);  
wire [15:0] msg_length_bits_4 = 16'd320 + (nonce_ascii_len_4 << 3);  
wire [15:0] msg_length_bits_5 = 16'd320 + (nonce_ascii_len_5 << 3);  
wire [15:0] msg_length_bits_6 = 16'd320 + (nonce_ascii_len_6 << 3);  
wire [15:0] msg_length_bits_7 = 16'd320 + (nonce_ascii_len_7 << 3);  

// Implementa buffering de 80 bytes: 40 bytes de mensagem + 40 bytes de hash ASCII hex
// Recebe buffer completo, então dispara computação SHA-1
// Ao encontrar correspondência, transmite resultado de nonce de 4 bytes
// Estrutura: buffer[0..39] = mensagem, buffer[40..79] = hash esperado

// Constante de tamanho de buffer
localparam BUFFER_SIZE = 80;  // Total: 40 bytes de mensagem + 40 bytes de hash ASCII
// Buffer de recepção dinâmico
reg [7:0] buffer [0:BUFFER_SIZE-1];  // Buffer de 80 bytes: [0..39] mensagem, [40..79] hash


// Lógica combinacional: constrói dinamicamente MESSAGE_BLOCK_*
always @(*) begin
    // Construir nonce_ascii baseado na contagem de dígitos
    // Converter BCD puro (0-9) para ASCII (0x30-0x39)
     case (nonce_ascii_len_0)
         4'd1: nonce_ascii_0 = {64'd0, 8'h30 + digit1_0};
         4'd2: nonce_ascii_0 = {56'd0, 8'h30 + digit2_0, 8'h30 + digit1_0};
         4'd3: nonce_ascii_0 = {48'd0, 8'h30 + digit3_0, 8'h30 + digit2_0, 8'h30 + digit1_0};
         4'd4: nonce_ascii_0 = {40'd0, 8'h30 + digit4_0, 8'h30 + digit3_0, 8'h30 + digit2_0, 8'h30 + digit1_0};
         4'd5: nonce_ascii_0 = {32'd0, 8'h30 + digit5_0, 8'h30 + digit4_0, 8'h30 + digit3_0, 8'h30 + digit2_0, 8'h30 + digit1_0};
         4'd6: nonce_ascii_0 = {24'd0, 8'h30 + digit6_0, 8'h30 + digit5_0, 8'h30 + digit4_0, 8'h30 + digit3_0, 8'h30 + digit2_0, 8'h30 + digit1_0};
         4'd7: nonce_ascii_0 = {16'd0, 8'h30 + digit7_0, 8'h30 + digit6_0, 8'h30 + digit5_0, 8'h30 + digit4_0, 8'h30 + digit3_0, 8'h30 + digit2_0, 8'h30 + digit1_0};
         4'd8: nonce_ascii_0 = {8'd0, 8'h30 + digit8_0, 8'h30 + digit7_0, 8'h30 + digit6_0, 8'h30 + digit5_0, 8'h30 + digit4_0, 8'h30 + digit3_0, 8'h30 + digit2_0, 8'h30 + digit1_0};
         4'd9: nonce_ascii_0 = {8'h30 + digit9_0, 8'h30 + digit8_0, 8'h30 + digit7_0, 8'h30 + digit6_0, 8'h30 + digit5_0, 8'h30 + digit4_0, 8'h30 + digit3_0, 8'h30 + digit2_0, 8'h30 + digit1_0};
         default: nonce_ascii_0 = 72'd0;
     endcase
    
     case (nonce_ascii_len_1)
         4'd1: nonce_ascii_1 = {64'd0, 8'h30 + digit1_1};
         4'd2: nonce_ascii_1 = {56'd0, 8'h30 + digit2_1, 8'h30 + digit1_1};
         4'd3: nonce_ascii_1 = {48'd0, 8'h30 + digit3_1, 8'h30 + digit2_1, 8'h30 + digit1_1};
         4'd4: nonce_ascii_1 = {40'd0, 8'h30 + digit4_1, 8'h30 + digit3_1, 8'h30 + digit2_1, 8'h30 + digit1_1};
         4'd5: nonce_ascii_1 = {32'd0, 8'h30 + digit5_1, 8'h30 + digit4_1, 8'h30 + digit3_1, 8'h30 + digit2_1, 8'h30 + digit1_1};
         4'd6: nonce_ascii_1 = {24'd0, 8'h30 + digit6_1, 8'h30 + digit5_1, 8'h30 + digit4_1, 8'h30 + digit3_1, 8'h30 + digit2_1, 8'h30 + digit1_1};
         4'd7: nonce_ascii_1 = {16'd0, 8'h30 + digit7_1, 8'h30 + digit6_1, 8'h30 + digit5_1, 8'h30 + digit4_1, 8'h30 + digit3_1, 8'h30 + digit2_1, 8'h30 + digit1_1};
         4'd8: nonce_ascii_1 = {8'd0, 8'h30 + digit8_1, 8'h30 + digit7_1, 8'h30 + digit6_1, 8'h30 + digit5_1, 8'h30 + digit4_1, 8'h30 + digit3_1, 8'h30 + digit2_1, 8'h30 + digit1_1};
         4'd9: nonce_ascii_1 = {8'h30 + digit9_1, 8'h30 + digit8_1, 8'h30 + digit7_1, 8'h30 + digit6_1, 8'h30 + digit5_1, 8'h30 + digit4_1, 8'h30 + digit3_1, 8'h30 + digit2_1, 8'h30 + digit1_1};
         default: nonce_ascii_1 = 72'd0;
     endcase
    
     case (nonce_ascii_len_2)
         4'd1: nonce_ascii_2 = {64'd0, 8'h30 + digit1_2};
         4'd2: nonce_ascii_2 = {56'd0, 8'h30 + digit2_2, 8'h30 + digit1_2};
         4'd3: nonce_ascii_2 = {48'd0, 8'h30 + digit3_2, 8'h30 + digit2_2, 8'h30 + digit1_2};
         4'd4: nonce_ascii_2 = {40'd0, 8'h30 + digit4_2, 8'h30 + digit3_2, 8'h30 + digit2_2, 8'h30 + digit1_2};
         4'd5: nonce_ascii_2 = {32'd0, 8'h30 + digit5_2, 8'h30 + digit4_2, 8'h30 + digit3_2, 8'h30 + digit2_2, 8'h30 + digit1_2};
         4'd6: nonce_ascii_2 = {24'd0, 8'h30 + digit6_2, 8'h30 + digit5_2, 8'h30 + digit4_2, 8'h30 + digit3_2, 8'h30 + digit2_2, 8'h30 + digit1_2};
         4'd7: nonce_ascii_2 = {16'd0, 8'h30 + digit7_2, 8'h30 + digit6_2, 8'h30 + digit5_2, 8'h30 + digit4_2, 8'h30 + digit3_2, 8'h30 + digit2_2, 8'h30 + digit1_2};
         4'd8: nonce_ascii_2 = {8'd0, 8'h30 + digit8_2, 8'h30 + digit7_2, 8'h30 + digit6_2, 8'h30 + digit5_2, 8'h30 + digit4_2, 8'h30 + digit3_2, 8'h30 + digit2_2, 8'h30 + digit1_2};
         4'd9: nonce_ascii_2 = {8'h30 + digit9_2, 8'h30 + digit8_2, 8'h30 + digit7_2, 8'h30 + digit6_2, 8'h30 + digit5_2, 8'h30 + digit4_2, 8'h30 + digit3_2, 8'h30 + digit2_2, 8'h30 + digit1_2};
         default: nonce_ascii_2 = 72'd0;
     endcase
    
     case (nonce_ascii_len_3)
         4'd1: nonce_ascii_3 = {48'd0, 8'h30 + digit1_3};
         4'd2: nonce_ascii_3 = {40'd0, 8'h30 + digit2_3, 8'h30 + digit1_3};
         4'd3: nonce_ascii_3 = {32'd0, 8'h30 + digit3_3, 8'h30 + digit2_3, 8'h30 + digit1_3};
         4'd4: nonce_ascii_3 = {24'd0, 8'h30 + digit4_3, 8'h30 + digit3_3, 8'h30 + digit2_3, 8'h30 + digit1_3};
         4'd5: nonce_ascii_3 = {16'd0, 8'h30 + digit5_3, 8'h30 + digit4_3, 8'h30 + digit3_3, 8'h30 + digit2_3, 8'h30 + digit1_3};
         4'd6: nonce_ascii_3 = {8'd0, 8'h30  + digit6_3, 8'h30 + digit5_3, 8'h30 + digit4_3, 8'h30 + digit3_3, 8'h30 + digit2_3, 8'h30 + digit1_3};
         4'd7: nonce_ascii_3 = {8'h30 + digit7_3, 8'h30 + digit6_3, 8'h30 + digit5_3, 8'h30 + digit4_3, 8'h30 + digit3_3, 8'h30 + digit2_3, 8'h30 + digit1_3};
         4'd8: nonce_ascii_3 = {8'd0, 8'h30 + digit8_3, 8'h30 + digit7_3, 8'h30 + digit6_3, 8'h30 + digit5_3, 8'h30 + digit4_3, 8'h30 + digit3_3, 8'h30 + digit2_3, 8'h30 + digit1_3};
         4'd9: nonce_ascii_3 = {8'h30 + digit9_3, 8'h30 + digit8_3, 8'h30 + digit7_3, 8'h30 + digit6_3, 8'h30 + digit5_3, 8'h30 + digit4_3, 8'h30 + digit3_3, 8'h30 + digit2_3, 8'h30 + digit1_3};
         default: nonce_ascii_3 = 72'd0;
     endcase

     case (nonce_ascii_len_4)
         4'd1: nonce_ascii_4 = {48'd0, 8'h30 + digit1_4};
         4'd2: nonce_ascii_4 = {40'd0, 8'h30 + digit2_4, 8'h30 + digit1_4};
         4'd3: nonce_ascii_4 = {32'd0, 8'h30 + digit3_4, 8'h30 + digit2_4, 8'h30 + digit1_4};
         4'd4: nonce_ascii_4 = {24'd0, 8'h30 + digit4_4, 8'h30 + digit3_4, 8'h30 + digit2_4, 8'h30 + digit1_4};
         4'd5: nonce_ascii_4 = {16'd0, 8'h30 + digit5_4, 8'h30 + digit4_4, 8'h30 + digit3_4, 8'h30 + digit2_4, 8'h30 + digit1_4};
         4'd6: nonce_ascii_4 = {8'd0, 8'h30  + digit6_4, 8'h30 + digit5_4, 8'h30 + digit4_4, 8'h30 + digit3_4, 8'h30 + digit2_4, 8'h30 + digit1_4};
         4'd7: nonce_ascii_4 = {8'h30 + digit7_4, 8'h30 + digit6_4, 8'h30 + digit5_4, 8'h30 + digit4_4, 8'h30 + digit3_4, 8'h30 + digit2_4, 8'h30 + digit1_4};
         4'd8: nonce_ascii_4 = {8'd0, 8'h30 + digit8_4, 8'h30 + digit7_4, 8'h30 + digit6_4, 8'h30 + digit5_4, 8'h30 + digit4_4, 8'h30 + digit3_4, 8'h30 + digit2_4, 8'h30 + digit1_4};
         4'd9: nonce_ascii_4 = {8'h30 + digit9_4, 8'h30 + digit8_4, 8'h30 + digit7_4, 8'h30 + digit6_4, 8'h30 + digit5_4, 8'h30 + digit4_4, 8'h30 + digit3_4, 8'h30 + digit2_4, 8'h30 + digit1_4};
         default: nonce_ascii_4 = 72'd0;
     endcase
    
     case (nonce_ascii_len_5)
         4'd1: nonce_ascii_5 = {48'd0, 8'h30 + digit1_5};
         4'd2: nonce_ascii_5 = {40'd0, 8'h30 + digit2_5, 8'h30 + digit1_5};
         4'd3: nonce_ascii_5 = {32'd0, 8'h30 + digit3_5, 8'h30 + digit2_5, 8'h30 + digit1_5};
         4'd4: nonce_ascii_5 = {24'd0, 8'h30 + digit4_5, 8'h30 + digit3_5, 8'h30 + digit2_5, 8'h30 + digit1_5};
         4'd5: nonce_ascii_5 = {16'd0, 8'h30 + digit5_5, 8'h30 + digit4_5, 8'h30 + digit3_5, 8'h30 + digit2_5, 8'h30 + digit1_5};
         4'd6: nonce_ascii_5 = {8'd0, 8'h30  + digit6_5, 8'h30 + digit5_5, 8'h30 + digit4_5, 8'h30 + digit3_5, 8'h30 + digit2_5, 8'h30 + digit1_5};
         4'd7: nonce_ascii_5 = {8'h30 + digit7_5, 8'h30 + digit6_5, 8'h30 + digit5_5, 8'h30 + digit4_5, 8'h30 + digit3_5, 8'h30 + digit2_5, 8'h30 + digit1_5};
         4'd8: nonce_ascii_5 = {8'd0, 8'h30 + digit8_5, 8'h30 + digit7_5, 8'h30 + digit6_5, 8'h30 + digit5_5, 8'h30 + digit4_5, 8'h30 + digit3_5, 8'h30 + digit2_5, 8'h30 + digit1_5};
         4'd9: nonce_ascii_5 = {8'h30 + digit9_5, 8'h30 + digit8_5, 8'h30 + digit7_5, 8'h30 + digit6_5, 8'h30 + digit5_5, 8'h30 + digit4_5, 8'h30 + digit3_5, 8'h30 + digit2_5, 8'h30 + digit1_5};
         default: nonce_ascii_5 = 72'd0;
     endcase
    
     case (nonce_ascii_len_6)
         4'd1: nonce_ascii_6 = {48'd0, 8'h30 + digit1_6};
         4'd2: nonce_ascii_6 = {40'd0, 8'h30 + digit2_6, 8'h30 + digit1_6};
         4'd3: nonce_ascii_6 = {32'd0, 8'h30 + digit3_6, 8'h30 + digit2_6, 8'h30 + digit1_6};
         4'd4: nonce_ascii_6 = {24'd0, 8'h30 + digit4_6, 8'h30 + digit3_6, 8'h30 + digit2_6, 8'h30 + digit1_6};
         4'd5: nonce_ascii_6 = {16'd0, 8'h30 + digit5_6, 8'h30 + digit4_6, 8'h30 + digit3_6, 8'h30 + digit2_6, 8'h30 + digit1_6};
         4'd6: nonce_ascii_6 = {8'd0, 8'h30  + digit6_6, 8'h30 + digit5_6, 8'h30 + digit4_6, 8'h30 + digit3_6, 8'h30 + digit2_6, 8'h30 + digit1_6};
         4'd7: nonce_ascii_6 = {8'h30 + digit7_6, 8'h30 + digit6_6, 8'h30 + digit5_6, 8'h30 + digit4_6, 8'h30 + digit3_6, 8'h30 + digit2_6, 8'h30 + digit1_6};
         4'd8: nonce_ascii_6 = {8'd0, 8'h30 + digit8_6, 8'h30 + digit7_6, 8'h30 + digit6_6, 8'h30 + digit5_6, 8'h30 + digit4_6, 8'h30 + digit3_6, 8'h30 + digit2_6, 8'h30 + digit1_6};
         4'd9: nonce_ascii_6 = {8'h30 + digit9_6, 8'h30 + digit8_6, 8'h30 + digit7_6, 8'h30 + digit6_6, 8'h30 + digit5_6, 8'h30 + digit4_6, 8'h30 + digit3_6, 8'h30 + digit2_6, 8'h30 + digit1_6};
         default: nonce_ascii_6 = 72'd0;
     endcase
    
     case (nonce_ascii_len_7)
         4'd1: nonce_ascii_7 = {48'd0, 8'h30 + digit1_7};
         4'd2: nonce_ascii_7 = {40'd0, 8'h30 + digit2_7, 8'h30 + digit1_7};
         4'd3: nonce_ascii_7 = {32'd0, 8'h30 + digit3_7, 8'h30 + digit2_7, 8'h30 + digit1_7};
         4'd4: nonce_ascii_7 = {24'd0, 8'h30 + digit4_7, 8'h30 + digit3_7, 8'h30 + digit2_7, 8'h30 + digit1_7};
         4'd5: nonce_ascii_7 = {16'd0, 8'h30 + digit5_7, 8'h30 + digit4_7, 8'h30 + digit3_7, 8'h30 + digit2_7, 8'h30 + digit1_7};
         4'd6: nonce_ascii_7 = {8'd0, 8'h30  + digit6_7, 8'h30 + digit5_7, 8'h30 + digit4_7, 8'h30 + digit3_7, 8'h30 + digit2_7, 8'h30 + digit1_7};
         4'd7: nonce_ascii_7 = {8'h30  + digit7_7, 8'h30 + digit6_7, 8'h30 + digit5_7, 8'h30 + digit4_7, 8'h30 + digit3_7, 8'h30 + digit2_7, 8'h30 + digit1_7};
         4'd8: nonce_ascii_7 = {8'd0, 8'h30 + digit8_7, 8'h30 + digit7_7, 8'h30 + digit6_7, 8'h30 + digit5_7, 8'h30 + digit4_7, 8'h30 + digit3_7, 8'h30 + digit2_7, 8'h30 + digit1_7};
         4'd9: nonce_ascii_7 = {8'h30 + digit9_7, 8'h30 + digit8_7, 8'h30 + digit7_7, 8'h30 + digit6_7, 8'h30 + digit5_7, 8'h30 + digit4_7, 8'h30 + digit3_7, 8'h30 + digit2_7, 8'h30 + digit1_7};
         default: nonce_ascii_7 = 72'd0;
     endcase
    
    // ========================================================================
    // Estrutura dinâmica: buffer[40] + nonce_ascii[variável] + 0x80 + padding + comprimento
    // 
    // Comprimento total = 40 + nonce_ascii_len bytes
    // Comprimento em bits = (40 + nonce_ascii_len) * 8
    // Tabela:
    //   nonce_len=1: msg_bits = 328 (0x0148), padding = 20 bytes
    //   nonce_len=2: msg_bits = 336 (0x0150), padding = 19 bytes
    //   nonce_len=3: msg_bits = 344 (0x0158), padding = 18 bytes
    //   nonce_len=4: msg_bits = 352 (0x0160), padding = 17 bytes
    //   nonce_len=5: msg_bits = 360 (0x0168), padding = 16 bytes
    //   nonce_len=6: msg_bits = 368 (0x0170), padding = 15 bytes
    //   nonce_len=7: msg_bits = 376 (0x0178), padding = 14 bytes
    //   nonce_len=8: msg_bits = 384 (0x0180), padding = 13 bytes
    //   nonce_len=9: msg_bits = 392 (0x0188), padding = 12 bytes
    // ========================================================================
    
    // Bloco de mensagem = 512 bits total
    // Posição do padding dinâmica: buffer[40] + nonce_ascii + 0x80 + zeros + comprimento(2 bytes)
    MESSAGE_BLOCK_0 = {
        // Bytes 0-39: mensagem do buffer UART
        buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
        buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
        buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
        buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
        buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
        
          // Nonce ASCII variável (1-9 bytes) + 0x80 (marcador padding) + zeros + comprimento
          // TOTAL = 512 bits = 64 bytes (40 buffer + 1-9 nonce + 1 pad + padding + 2 length)
          (nonce_ascii_len_0 == 4'd1) ? {nonce_ascii_0[7:0],   8'h80, 160'h00000000000000000000000000000000000000, msg_length_bits_0} :
          (nonce_ascii_len_0 == 4'd2) ? {nonce_ascii_0[15:0],  8'h80, 152'h0000000000000000000000000000000000000, msg_length_bits_0} :
          (nonce_ascii_len_0 == 4'd3) ? {nonce_ascii_0[23:0],  8'h80, 144'h000000000000000000000000000000000000, msg_length_bits_0} :
          (nonce_ascii_len_0 == 4'd4) ? {nonce_ascii_0[31:0],  8'h80, 136'h00000000000000000000000000000000000, msg_length_bits_0} :
          (nonce_ascii_len_0 == 4'd5) ? {nonce_ascii_0[39:0],  8'h80, 128'h0000000000000000000000000000000000, msg_length_bits_0} :
          (nonce_ascii_len_0 == 4'd6) ? {nonce_ascii_0[47:0],  8'h80, 120'h000000000000000000000000000000000, msg_length_bits_0} :
          (nonce_ascii_len_0 == 4'd7) ? {nonce_ascii_0[55:0],  8'h80, 112'h00000000000000000000000000000000, msg_length_bits_0} :
          (nonce_ascii_len_0 == 4'd8) ? {nonce_ascii_0[63:0],  8'h80, 104'h0000000000000000000000000000, msg_length_bits_0} :
          /* 4'd9 */                    {nonce_ascii_0[71:0],  8'h80, 96'h000000000000000000000000, msg_length_bits_0}
    };
    
    MESSAGE_BLOCK_1 = {
        // Bytes 0-39: mensagem do buffer UART
        buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
        buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
        buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
        buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
        buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
        
          // Nonce ASCII variável (1-9 bytes) + 0x80 (marcador padding) + zeros + comprimento
          // TOTAL = 512 bits = 64 bytes (40 buffer + 1-9 nonce + 1 pad + padding + 2 length)
          (nonce_ascii_len_1 == 4'd1) ? {nonce_ascii_1[7:0],   8'h80, 160'h0000000000000000000, msg_length_bits_1} :
          (nonce_ascii_len_1 == 4'd2) ? {nonce_ascii_1[15:0],  8'h80, 152'h000000000000000000, msg_length_bits_1} :
          (nonce_ascii_len_1 == 4'd3) ? {nonce_ascii_1[23:0],  8'h80, 144'h00000000000000000, msg_length_bits_1} :
          (nonce_ascii_len_1 == 4'd4) ? {nonce_ascii_1[31:0],  8'h80, 136'h0000000000000000, msg_length_bits_1} :
          (nonce_ascii_len_1 == 4'd5) ? {nonce_ascii_1[39:0],  8'h80, 128'h000000000000000, msg_length_bits_1} :
          (nonce_ascii_len_1 == 4'd6) ? {nonce_ascii_1[47:0],  8'h80, 120'h00000000000000, msg_length_bits_1} :
          (nonce_ascii_len_1 == 4'd7) ? {nonce_ascii_1[55:0],  8'h80, 112'h0000000000000, msg_length_bits_1} :
          (nonce_ascii_len_1 == 4'd8) ? {nonce_ascii_1[63:0],  8'h80, 104'h000000000000, msg_length_bits_1} :
          /* 4'd9 */                    {nonce_ascii_1[71:0],  8'h80, 96'h00000000000, msg_length_bits_1}
    };
    
    MESSAGE_BLOCK_2 = {
        // Bytes 0-39: mensagem do buffer UART
        buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
        buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
        buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
        buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
        buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
        
          // Nonce ASCII variável (1-9 bytes) + 0x80 (marcador padding) + zeros + comprimento
          // TOTAL = 512 bits = 64 bytes (40 buffer + 1-9 nonce + 1 pad + padding + 2 length)
          (nonce_ascii_len_2 == 4'd1) ? {nonce_ascii_2[7:0],   8'h80, 160'h0000000000000000000, msg_length_bits_2} :
          (nonce_ascii_len_2 == 4'd2) ? {nonce_ascii_2[15:0],  8'h80, 152'h000000000000000000, msg_length_bits_2} :
          (nonce_ascii_len_2 == 4'd3) ? {nonce_ascii_2[23:0],  8'h80, 144'h00000000000000000, msg_length_bits_2} :
          (nonce_ascii_len_2 == 4'd4) ? {nonce_ascii_2[31:0],  8'h80, 136'h0000000000000000, msg_length_bits_2} :
          (nonce_ascii_len_2 == 4'd5) ? {nonce_ascii_2[39:0],  8'h80, 128'h000000000000000, msg_length_bits_2} :
          (nonce_ascii_len_2 == 4'd6) ? {nonce_ascii_2[47:0],  8'h80, 120'h00000000000000, msg_length_bits_2} :
          (nonce_ascii_len_2 == 4'd7) ? {nonce_ascii_2[55:0],  8'h80, 112'h0000000000000, msg_length_bits_2} :
          (nonce_ascii_len_2 == 4'd8) ? {nonce_ascii_2[63:0],  8'h80, 104'h000000000000, msg_length_bits_2} :
          /* 4'd9 */                    {nonce_ascii_2[71:0],  8'h80, 96'h00000000000, msg_length_bits_2}
    };
    
    MESSAGE_BLOCK_3 = {
        // Bytes 0-39: mensagem do buffer UART
        buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
        buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
        buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
        buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
        buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
        
          // Nonce ASCII variável (1-9 bytes) + 0x80 (marcador padding) + zeros + comprimento
          // TOTAL = 512 bits = 64 bytes (40 buffer + 1-9 nonce + 1 pad + padding + 2 length)
          (nonce_ascii_len_3 == 4'd1) ? {nonce_ascii_3[7:0],   8'h80, 160'h0000000000000000000, msg_length_bits_3} :
          (nonce_ascii_len_3 == 4'd2) ? {nonce_ascii_3[15:0],  8'h80, 152'h000000000000000000, msg_length_bits_3} :
          (nonce_ascii_len_3 == 4'd3) ? {nonce_ascii_3[23:0],  8'h80, 144'h00000000000000000, msg_length_bits_3} :
          (nonce_ascii_len_3 == 4'd4) ? {nonce_ascii_3[31:0],  8'h80, 136'h0000000000000000, msg_length_bits_3} :
          (nonce_ascii_len_3 == 4'd5) ? {nonce_ascii_3[39:0],  8'h80, 128'h000000000000000, msg_length_bits_3} :
          (nonce_ascii_len_3 == 4'd6) ? {nonce_ascii_3[47:0],  8'h80, 120'h00000000000000, msg_length_bits_3} :
          (nonce_ascii_len_3 == 4'd7) ? {nonce_ascii_3[55:0],  8'h80, 112'h0000000000000, msg_length_bits_3} :
          (nonce_ascii_len_3 == 4'd8) ? {nonce_ascii_3[63:0],  8'h80, 104'h000000000000, msg_length_bits_3} :
          /* 4'd9 */                    {nonce_ascii_3[71:0],  8'h80, 96'h00000000000, msg_length_bits_3}
    };
    
    MESSAGE_BLOCK_4 = {
        // Bytes 0-39: mensagem do buffer UART
        buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
        buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
        buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
        buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
        buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
        
          // Nonce ASCII variável (1-9 bytes) + 0x80 (marcador padding) + zeros + comprimento
          // TOTAL = 512 bits = 64 bytes (40 buffer + 1-9 nonce + 1 pad + padding + 2 length)
          (nonce_ascii_len_4 == 4'd1) ? {nonce_ascii_4[7:0],   8'h80, 160'h0000000000000000000, msg_length_bits_4} :
          (nonce_ascii_len_4 == 4'd2) ? {nonce_ascii_4[15:0],  8'h80, 152'h000000000000000000, msg_length_bits_4} :
          (nonce_ascii_len_4 == 4'd3) ? {nonce_ascii_4[23:0],  8'h80, 144'h00000000000000000, msg_length_bits_4} :
          (nonce_ascii_len_4 == 4'd4) ? {nonce_ascii_4[31:0],  8'h80, 136'h0000000000000000, msg_length_bits_4} :
          (nonce_ascii_len_4 == 4'd5) ? {nonce_ascii_4[39:0],  8'h80, 128'h000000000000000, msg_length_bits_4} :
          (nonce_ascii_len_4 == 4'd6) ? {nonce_ascii_4[47:0],  8'h80, 120'h00000000000000, msg_length_bits_4} :
          (nonce_ascii_len_4 == 4'd7) ? {nonce_ascii_4[55:0],  8'h80, 112'h0000000000000, msg_length_bits_4} :
          (nonce_ascii_len_4 == 4'd8) ? {nonce_ascii_4[63:0],  8'h80, 104'h000000000000, msg_length_bits_4} :
          /* 4'd9 */                    {nonce_ascii_4[71:0],  8'h80, 96'h00000000000, msg_length_bits_4}
    };
    
    MESSAGE_BLOCK_5 = {
        // Bytes 0-39: mensagem do buffer UART
        buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
        buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
        buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
        buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
        buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
        
          // Nonce ASCII variável (1-9 bytes) + 0x80 (marcador padding) + zeros + comprimento
          // TOTAL = 512 bits = 64 bytes (40 buffer + 1-9 nonce + 1 pad + padding + 2 length)
          (nonce_ascii_len_5 == 4'd1) ? {nonce_ascii_5[7:0],   8'h80, 160'h0000000000000000000, msg_length_bits_5} :
          (nonce_ascii_len_5 == 4'd2) ? {nonce_ascii_5[15:0],  8'h80, 152'h000000000000000000, msg_length_bits_5} :
          (nonce_ascii_len_5 == 4'd3) ? {nonce_ascii_5[23:0],  8'h80, 144'h00000000000000000, msg_length_bits_5} :
          (nonce_ascii_len_5 == 4'd4) ? {nonce_ascii_5[31:0],  8'h80, 136'h0000000000000000, msg_length_bits_5} :
          (nonce_ascii_len_5 == 4'd5) ? {nonce_ascii_5[39:0],  8'h80, 128'h000000000000000, msg_length_bits_5} :
          (nonce_ascii_len_5 == 4'd6) ? {nonce_ascii_5[47:0],  8'h80, 120'h00000000000000, msg_length_bits_5} :
          (nonce_ascii_len_5 == 4'd7) ? {nonce_ascii_5[55:0],  8'h80, 112'h0000000000000, msg_length_bits_5} :
          (nonce_ascii_len_5 == 4'd8) ? {nonce_ascii_5[63:0],  8'h80, 104'h000000000000, msg_length_bits_5} :
          /* 4'd9 */                    {nonce_ascii_5[71:0],  8'h80, 96'h00000000000, msg_length_bits_5}
    };
    
    MESSAGE_BLOCK_6 = {
        // Bytes 0-39: mensagem do buffer UART
        buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
        buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
        buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
        buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
        buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
        
          // Nonce ASCII variável (1-9 bytes) + 0x80 (marcador padding) + zeros + comprimento
          // TOTAL = 512 bits = 64 bytes (40 buffer + 1-9 nonce + 1 pad + padding + 2 length)
          (nonce_ascii_len_6 == 4'd1) ? {nonce_ascii_6[7:0],   8'h80, 160'h0000000000000000000, msg_length_bits_6} :
          (nonce_ascii_len_6 == 4'd2) ? {nonce_ascii_6[15:0],  8'h80, 152'h000000000000000000, msg_length_bits_6} :
          (nonce_ascii_len_6 == 4'd3) ? {nonce_ascii_6[23:0],  8'h80, 144'h00000000000000000, msg_length_bits_6} :
          (nonce_ascii_len_6 == 4'd4) ? {nonce_ascii_6[31:0],  8'h80, 136'h0000000000000000, msg_length_bits_6} :
          (nonce_ascii_len_6 == 4'd5) ? {nonce_ascii_6[39:0],  8'h80, 128'h000000000000000, msg_length_bits_6} :
          (nonce_ascii_len_6 == 4'd6) ? {nonce_ascii_6[47:0],  8'h80, 120'h00000000000000, msg_length_bits_6} :
          (nonce_ascii_len_6 == 4'd7) ? {nonce_ascii_6[55:0],  8'h80, 112'h0000000000000, msg_length_bits_6} :
          (nonce_ascii_len_6 == 4'd8) ? {nonce_ascii_6[63:0],  8'h80, 104'h000000000000, msg_length_bits_6} :
          /* 4'd9 */                    {nonce_ascii_6[71:0],  8'h80, 96'h00000000000, msg_length_bits_6}
    };
    
    MESSAGE_BLOCK_7 = {
        // Bytes 0-39: mensagem do buffer UART
        buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
        buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
        buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
        buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
        buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
        
          // Nonce ASCII variável (1-9 bytes) + 0x80 (marcador padding) + zeros + comprimento
          // TOTAL = 512 bits = 64 bytes (40 buffer + 1-9 nonce + 1 pad + padding + 2 length)
          (nonce_ascii_len_7 == 4'd1) ? {nonce_ascii_7[7:0],   8'h80, 160'h0000000000000000000, msg_length_bits_7} :
          (nonce_ascii_len_7 == 4'd2) ? {nonce_ascii_7[15:0],  8'h80, 152'h000000000000000000, msg_length_bits_7} :
          (nonce_ascii_len_7 == 4'd3) ? {nonce_ascii_7[23:0],  8'h80, 144'h00000000000000000, msg_length_bits_7} :
          (nonce_ascii_len_7 == 4'd4) ? {nonce_ascii_7[31:0],  8'h80, 136'h0000000000000000, msg_length_bits_7} :
          (nonce_ascii_len_7 == 4'd5) ? {nonce_ascii_7[39:0],  8'h80, 128'h000000000000000, msg_length_bits_7} :
          (nonce_ascii_len_7 == 4'd6) ? {nonce_ascii_7[47:0],  8'h80, 120'h00000000000000, msg_length_bits_7} :
          (nonce_ascii_len_7 == 4'd7) ? {nonce_ascii_7[55:0],  8'h80, 112'h0000000000000, msg_length_bits_7} :
          (nonce_ascii_len_7 == 4'd8) ? {nonce_ascii_7[63:0],  8'h80, 104'h000000000000, msg_length_bits_7} :
          /* 4'd9 */                    {nonce_ascii_7[71:0],  8'h80, 96'h00000000000, msg_length_bits_7}
    };
    
    // SHA1_EXPECTED: Decodifica 40 caracteres ASCII hexadecimais de buffer[40..79] em hash binário de 160 bits
    // Conversão: cada par de caracteres ASCII hex [2n, 2n+1] torna-se um byte binário
    // Exemplo: ASCII '48' -> 0x48, 'a3' -> 0xa3, etc. (suporta maiúsculas e minúsculas)
    SHA1_EXPECTED = {
        // Bytes 0-19: Decodifica pares hex de índices de buffer 40-79
        (buffer[40] >= 8'h61 ? buffer[40] - 8'h57 : buffer[40] - 8'h30) << 4 | 
        (buffer[41] >= 8'h61 ? buffer[41] - 8'h57 : buffer[41] - 8'h30),
        (buffer[42] >= 8'h61 ? buffer[42] - 8'h57 : buffer[42] - 8'h30) << 4 | 
        (buffer[43] >= 8'h61 ? buffer[43] - 8'h57 : buffer[43] - 8'h30),
        (buffer[44] >= 8'h61 ? buffer[44] - 8'h57 : buffer[44] - 8'h30) << 4 | 
        (buffer[45] >= 8'h61 ? buffer[45] - 8'h57 : buffer[45] - 8'h30),
        (buffer[46] >= 8'h61 ? buffer[46] - 8'h57 : buffer[46] - 8'h30) << 4 | 
        (buffer[47] >= 8'h61 ? buffer[47] - 8'h57 : buffer[47] - 8'h30),
        (buffer[48] >= 8'h61 ? buffer[48] - 8'h57 : buffer[48] - 8'h30) << 4 | 
        (buffer[49] >= 8'h61 ? buffer[49] - 8'h57 : buffer[49] - 8'h30),
        (buffer[50] >= 8'h61 ? buffer[50] - 8'h57 : buffer[50] - 8'h30) << 4 | 
        (buffer[51] >= 8'h61 ? buffer[51] - 8'h57 : buffer[51] - 8'h30),
        (buffer[52] >= 8'h61 ? buffer[52] - 8'h57 : buffer[52] - 8'h30) << 4 | 
        (buffer[53] >= 8'h61 ? buffer[53] - 8'h57 : buffer[53] - 8'h30),
        (buffer[54] >= 8'h61 ? buffer[54] - 8'h57 : buffer[54] - 8'h30) << 4 | 
        (buffer[55] >= 8'h61 ? buffer[55] - 8'h57 : buffer[55] - 8'h30),
        (buffer[56] >= 8'h61 ? buffer[56] - 8'h57 : buffer[56] - 8'h30) << 4 | 
        (buffer[57] >= 8'h61 ? buffer[57] - 8'h57 : buffer[57] - 8'h30),
        (buffer[58] >= 8'h61 ? buffer[58] - 8'h57 : buffer[58] - 8'h30) << 4 | 
        (buffer[59] >= 8'h61 ? buffer[59] - 8'h57 : buffer[59] - 8'h30),
        (buffer[60] >= 8'h61 ? buffer[60] - 8'h57 : buffer[60] - 8'h30) << 4 | 
        (buffer[61] >= 8'h61 ? buffer[61] - 8'h57 : buffer[61] - 8'h30),
        (buffer[62] >= 8'h61 ? buffer[62] - 8'h57 : buffer[62] - 8'h30) << 4 | 
        (buffer[63] >= 8'h61 ? buffer[63] - 8'h57 : buffer[63] - 8'h30),
        (buffer[64] >= 8'h61 ? buffer[64] - 8'h57 : buffer[64] - 8'h30) << 4 | 
        (buffer[65] >= 8'h61 ? buffer[65] - 8'h57 : buffer[65] - 8'h30),
        (buffer[66] >= 8'h61 ? buffer[66] - 8'h57 : buffer[66] - 8'h30) << 4 | 
        (buffer[67] >= 8'h61 ? buffer[67] - 8'h57 : buffer[67] - 8'h30),
        (buffer[68] >= 8'h61 ? buffer[68] - 8'h57 : buffer[68] - 8'h30) << 4 | 
        (buffer[69] >= 8'h61 ? buffer[69] - 8'h57 : buffer[69] - 8'h30),
        (buffer[70] >= 8'h61 ? buffer[70] - 8'h57 : buffer[70] - 8'h30) << 4 | 
        (buffer[71] >= 8'h61 ? buffer[71] - 8'h57 : buffer[71] - 8'h30),
        (buffer[72] >= 8'h61 ? buffer[72] - 8'h57 : buffer[72] - 8'h30) << 4 | 
        (buffer[73] >= 8'h61 ? buffer[73] - 8'h57 : buffer[73] - 8'h30),
        (buffer[74] >= 8'h61 ? buffer[74] - 8'h57 : buffer[74] - 8'h30) << 4 | 
        (buffer[75] >= 8'h61 ? buffer[75] - 8'h57 : buffer[75] - 8'h30),
        (buffer[76] >= 8'h61 ? buffer[76] - 8'h57 : buffer[76] - 8'h30) << 4 | 
        (buffer[77] >= 8'h61 ? buffer[77] - 8'h57 : buffer[77] - 8'h30),
        (buffer[78] >= 8'h61 ? buffer[78] - 8'h57 : buffer[78] - 8'h30) << 4 | 
        (buffer[79] >= 8'h61 ? buffer[79] - 8'h57 : buffer[79] - 8'h30)
    };
    
end

// Sinais de computação SHA-1 (OCTA-CORE)
reg [27:0] clock_counter;     // Contador de temporização da máquina de estados
reg nonce_increment_done;     // flag: garante que nonce incrementa exatamente uma vez por buffer

// ========== REGISTRADORES DE RESULTADO PARA SHA1_CORE_0 ==========
reg [159:0] sha1_digest_0;        // Resultado do resumo SHA-1 computado para nonce_0
reg sha1_digest_0_valid;          // flag: computação SHA-1 completa para nonce_0

// ========== REGISTRADORES DE RESULTADO PARA SHA1_CORE_1 ==========
reg [159:0] sha1_digest_1;        // Resultado do resumo SHA-1 computado para nonce_1
reg sha1_digest_1_valid;          // flag: computação SHA-1 completa para nonce_1
reg [159:0] sha1_digest_2;        // ...
reg sha1_digest_2_valid;          
reg [159:0] sha1_digest_3;        
reg sha1_digest_3_valid;          
reg [159:0] sha1_digest_4;        
reg sha1_digest_4_valid;          
reg [159:0] sha1_digest_5;        
reg sha1_digest_5_valid;          
reg [159:0] sha1_digest_6;        
reg sha1_digest_6_valid;          
reg [159:0] sha1_digest_7;        
reg sha1_digest_7_valid;          

// ========== SINAIS PARA SHA1_CORE_0 ==========
wire sha1_core_0_ready;           // Sinal: núcleo SHA-1 pronto (pode aceitar nova computação)
wire [159:0] sha1_core_0_digest;  // Resumo de saída do núcleo SHA-1 (160 bits)
wire sha1_core_0_digest_valid;    // flag: conclusão do núcleo SHA-1
reg sha1_0_init;                  // Sinal pulsado: dispara inicialização do núcleo SHA-1
reg sha1_0_next;                  // Sinal pulsado: dispara processamento do próximo bloco

// ========== SINAIS PARA SHA1_CORE_1 ==========
wire sha1_core_1_ready;           // Sinal: núcleo SHA-1 pronto (pode aceitar nova computação)
wire [159:0] sha1_core_1_digest;  // Resumo de saída do núcleo SHA-1 (160 bits)
wire sha1_core_1_digest_valid;    // flag: conclusão do núcleo SHA-1
reg sha1_1_init;                  // Sinal pulsado: dispara inicialização do núcleo SHA-1
reg sha1_1_next;                  // Sinal pulsado: dispara processamento do próximo bloco

// ========== SINAIS PARA SHA1_CORE_2 ==========
wire sha1_core_2_ready;           // Sinal: núcleo SHA-1 pronto (pode aceitar nova computação)
wire [159:0] sha1_core_2_digest;  // Resumo de saída do núcleo SHA-1 (160 bits)
wire sha1_core_2_digest_valid;    // flag: conclusão do núcleo SHA-1
reg sha1_2_init;                  // Sinal pulsado: dispara inicialização do núcleo SHA-1
reg sha1_2_next;                  // Sinal pulsado: dispara processamento do próximo bloco

wire sha1_core_3_ready;           // ...
wire [159:0] sha1_core_3_digest;  
wire sha1_core_3_digest_valid;    
reg sha1_3_init;                  
reg sha1_3_next;                  

wire sha1_core_4_ready;           
wire [159:0] sha1_core_4_digest;  
wire sha1_core_4_digest_valid;    
reg sha1_4_init;                  
reg sha1_4_next;                  

wire sha1_core_5_ready;           
wire [159:0] sha1_core_5_digest;  
wire sha1_core_5_digest_valid;    
reg sha1_5_init;                  
reg sha1_5_next;                  

wire sha1_core_6_ready;           
wire [159:0] sha1_core_6_digest;  
wire sha1_core_6_digest_valid;    
reg sha1_6_init;                  
reg sha1_6_next;                  

wire sha1_core_7_ready;           
wire [159:0] sha1_core_7_digest;  
wire sha1_core_7_digest_valid;    
reg sha1_7_init;                  
reg sha1_7_next;                  

// Sinais de controle geral
wire sha1_start;                  // Sinal de início: ativado quando buffer UART está cheio (estado BUFFER_FULL)
wire uart_tx_done_signal;         // Sinal de conclusão: ativado quando transmissão UART termina (estado UART_TX_DONE)

reg led_red_output;              // Saída LED: status de correspondência SHA-1
reg led_green_output;           // Saída LED: status de correspondência SHA-1

reg [27:0] blink_counter;    // Contador de pisca para LED

// Máquina de estados SHA-1: implementa proof-of-work com iteração de nonce
// Estados: RESET ? IDLE ? INIT_SHA1 ? RUNNING ? DONE_WAIT ? RESULT
// Em RESULT: se hash corresponde, transmite nonce; caso contrário, incrementa e tenta novamente
reg [2:0] state;
localparam STATE_RESET      = 3'b000;  // Inicializar: reinicia todos os contadores
localparam STATE_IDLE       = 3'b001;  // Aguardar: núcleo SHA-1 pronto E buffer UART cheio
localparam STATE_INIT_SHA1  = 3'b010;  // Inicializar núcleo SHA-1 com MESSAGE_BLOCK
localparam STATE_RUNNING    = 3'b011;  // Atraso: aguardar conclusão do núcleo SHA-1 (~1 segundo)
localparam STATE_DONE_WAIT  = 3'b100;  // Pesquisar: aguardar flag digest_valid SHA-1
localparam STATE_RESULT     = 3'b101;  // Verificar: se correspondência encontrada, sinaliza TX UART; caso contrário incrementa nonce e tenta novamente

// Sinais de recepção UART
wire [7:0] rx_data;        // Byte de dados recebido
wire rx_data_valid;       // flag de dados válidos RX
reg rx_data_ready = 1'b1; // flag RX pronto

// Sinais de transmissão UART
reg [7:0] tx_data;       // Byte de dados a transmitir
reg tx_data_valid;      // flag de dados válidos TX
wire tx_data_ready;    // flag TX pronto

// Saídas LED: invertidas porque LEDs estão em ativo-baixo
assign led_green = ~led_green_output;                     
assign led_red   = ~led_red_output;   

// ========================================
// INSTANCIAÇÃO DOS n CORES SHA-1
// ========================================

// ========== SHA1_CORE_0: Processa nonce_0 (nonce par) ==========
// Conecta MESSAGE_BLOCK_0 com sinais de controle sha1_0_*
sha1_core sha1_inst_0(
    .clk(clk),
    .reset_n(rst_n),
    .init(sha1_0_init),         // Sinal pulsado para inicializar
    .next(sha1_0_next),         // Sinal pulsado para processar
    .block(MESSAGE_BLOCK_0),    // Bloco de mensagem com nonce_0
    .ready(sha1_core_0_ready),  // Flag: core pronto
    .digest(sha1_core_0_digest),  // Resultado SHA-1 (160 bits)
    .digest_valid(sha1_core_0_digest_valid)  // Flag: resultado válido
);

// ========== SHA1_CORE_1: Processa nonce_1 (nonce ímpar) ==========
// Conecta MESSAGE_BLOCK_1 com sinais de controle sha1_1_*
sha1_core sha1_inst_1(
    .clk(clk),
    .reset_n(rst_n),
    .init(sha1_1_init),         // Sinal pulsado para inicializar
    .next(sha1_1_next),         // Sinal pulsado para processar
    .block(MESSAGE_BLOCK_1),    // Bloco de mensagem com nonce_1
    .ready(sha1_core_1_ready),  // Flag: core pronto
    .digest(sha1_core_1_digest),  // Resultado SHA-1 (160 bits)
    .digest_valid(sha1_core_1_digest_valid)  // Flag: resultado válido
);



sha1_core sha1_inst_2(
    .clk(clk),
    .reset_n(rst_n),
    .init(sha1_2_init),         
    .next(sha1_2_next),         
    .block(MESSAGE_BLOCK_2),    
    .ready(sha1_core_2_ready),  
    .digest(sha1_core_2_digest),
    .digest_valid(sha1_core_2_digest_valid)  
);

sha1_core sha1_inst_3(
    .clk(clk),
    .reset_n(rst_n),
    .init(sha1_3_init),         
    .next(sha1_3_next),         
    .block(MESSAGE_BLOCK_3),    
    .ready(sha1_core_3_ready),  
    .digest(sha1_core_3_digest),
    .digest_valid(sha1_core_3_digest_valid) 
);

sha1_core sha1_inst_4(
    .clk(clk),
    .reset_n(rst_n),
    .init(sha1_4_init),        
    .next(sha1_4_next),        
    .block(MESSAGE_BLOCK_4),   
    .ready(sha1_core_4_ready), 
    .digest(sha1_core_4_digest), 
    .digest_valid(sha1_core_4_digest_valid) 
);

sha1_core sha1_inst_5(
    .clk(clk),
    .reset_n(rst_n),
    .init(sha1_5_init),       
    .next(sha1_5_next),       
    .block(MESSAGE_BLOCK_5),  
    .ready(sha1_core_5_ready), 
    .digest(sha1_core_5_digest),  
    .digest_valid(sha1_core_5_digest_valid)  
);

sha1_core sha1_inst_6(
    .clk(clk),
    .reset_n(rst_n),
    .init(sha1_6_init),       
    .next(sha1_6_next),       
    .block(MESSAGE_BLOCK_6),  
    .ready(sha1_core_6_ready), 
    .digest(sha1_core_6_digest),  
    .digest_valid(sha1_core_6_digest_valid)  
);

sha1_core sha1_inst_7(
    .clk(clk),
    .reset_n(rst_n),
    .init(sha1_7_init),       
    .next(sha1_7_next),       
    .block(MESSAGE_BLOCK_7),  
    .ready(sha1_core_7_ready), 
    .digest(sha1_core_7_digest),  
    .digest_valid(sha1_core_7_digest_valid)  
);

// Recepção UART
uart_rx #(
    .CLK_FRE(CLK_FRE),
    .BAUD_RATE(UART_FRE)
) uart_rx_inst (
    .clk(clk),
    .rst_n(rst_n),
    .rx_data(rx_data),
    .rx_data_valid(rx_data_valid),
    .rx_data_ready(rx_data_ready),
    .rx_pin(uart_rx)
);

// Transmissão UART
uart_tx #(
    .CLK_FRE(CLK_FRE),
    .BAUD_RATE(UART_FRE)
) uart_tx_inst (
    .clk(clk),
    .rst_n(rst_n),
    .tx_data(tx_data),
    .tx_data_valid(tx_data_valid),
    .tx_data_ready(tx_data_ready),
    .tx_pin(uart_tx)
);

// Lógica principal da máquina de estados SHA-1
// Implementa mineração proof-of-work com OCTA-CORE SHA-1
// itera nonce_0 de 7 em 7: processando nonce_0 até nonce_* em paralelo
always @(posedge clk) begin
    // ========== RESET DOS SINAIS DE CONTROLE ==========
    // Estes sinais são pulsados (ativos por 1 ciclo apenas)
    sha1_0_init <= 1'b0;  // Pulso: ativado por um ciclo para disparar inicialização SHA-1 core 0
    sha1_0_next <= 1'b0;  // Pulso: ativado por um ciclo para disparar próximo bloco SHA-1 core 0
    sha1_1_init <= 1'b0;  // ...
    sha1_1_next <= 1'b0;  
    sha1_2_init <= 1'b0;  
    sha1_2_next <= 1'b0;  
    sha1_3_init <= 1'b0;  
    sha1_3_next <= 1'b0;  
    sha1_4_init <= 1'b0;  
    sha1_4_next <= 1'b0;  
    sha1_5_init <= 1'b0;  
    sha1_5_next <= 1'b0;  
    sha1_6_init <= 1'b0;  
    sha1_6_next <= 1'b0;  
    sha1_7_init <= 1'b0;  
    sha1_7_next <= 1'b0;  

    case (state)
STATE_RESET: begin
    // ========== INICIALIZAÇÃO: RESET GERAL ==========
    // Reinicia todos os contadores e saídas
    led_red_output   <= 1'b0;
    led_green_output <= 1'b0;

    clock_counter <= 28'd0;
    nonce_0 <= 32'd0;  // Reinicia nonce_0 para 0 na inicialização

    // Aguarda 5 ciclos de relógio para estabilização do sistema
    if (clock_counter >= 28'd5) begin
        clock_counter <= 28'd0;
        state <= STATE_IDLE;
    end else begin
        clock_counter <= clock_counter + 1'b1;
    end
end

STATE_IDLE: begin
    // ========== AGUARDAR OCTA-CORE PRONTO + BUFFER CHEIO ==========
    // Reinicia nonce_0 quando transmissão UART completa (prepara para próxima mensagem)
    if (uart_tx_done_signal) begin
        nonce_0 <= 32'd0;
    end
    
    // ========== INCREMENTAR NONCE_0 (ESTRATÉGIA OCTA-CORE) ==========
    // Primeiro incremento: disparado por sha1_start e flag nonce_increment_done
    // Garante que nonce_0 incrementa exatamente uma vez por buffer de mensagem
    // Incrementa de +8 para processar nonce_0 até nonce_7 em paralelo
    if (sha1_start && !nonce_increment_done) begin
        if (nonce_0 < DIFFICULTY - 1) begin  // Garante espaço para nonce_1 = nonce_0 + 1
            nonce_0 <= nonce_0 + 32'd8;  // INCREMENTA +8 (em vez de +1)
        end else begin
            nonce_0 <= 32'd0;  // Reinicia para 0 após atingir dificuldade máxima
        end
        nonce_increment_done <= 1'b1;  // Define flag para prevenir incrementos redundantes
    end
    
    // ========== TRANSIÇÃO PARA INIT_SHA1 ==========
    // Condição: TODOS 7 cores prontos AND buffer cheio AND nonce já incrementado
    if ((sha1_core_0_ready && 
         sha1_core_1_ready && 
         sha1_core_2_ready && 
         sha1_core_3_ready && 
         sha1_core_4_ready && 
         sha1_core_5_ready && 
         sha1_core_6_ready && 
         sha1_core_7_ready) && sha1_start && nonce_increment_done) begin
        state <= STATE_INIT_SHA1;
        clock_counter <= 28'd0;
    end
end

STATE_INIT_SHA1: begin
    // ========== DISPARAR TODOS OS 8 CORES SHA-1 ==========
    // Inicializa simultaneamente:
    // - sha1_core_0 com MESSAGE_BLOCK_0 (nonce_0)
    // - sha1_core_1 com MESSAGE_BLOCK_1 (nonce_1 = nonce_0 + 1)
    // - ...
    led_red_output <= 1'b1;  // LED: indica que processamento começou
    
    sha1_0_init <= 1'b1;  // Pulso: dispara CORE 0 por um ciclo
    sha1_1_init <= 1'b1;  // Pulso: dispara CORE 1 por um ciclo
    sha1_2_init <= 1'b1;  // (TODOS 8 cores ao mesmo tempo!)
    sha1_3_init <= 1'b1;   
    sha1_4_init <= 1'b1;   
    sha1_5_init <= 1'b1;   
    sha1_6_init <= 1'b1;
    sha1_7_init <= 1'b1;
    
    state <= STATE_RUNNING;
    clock_counter <= 28'd0;
end

STATE_RUNNING: begin
             // Aguarda conclusão do núcleo SHA-1 contador atinge ~185 ns, mas SHA-1 normalmente completa neste intervalo
             if (clock_counter >= 28'd5) begin
                 state <= STATE_DONE_WAIT;
                 clock_counter <= 28'd0;
             end else begin
                 clock_counter <= clock_counter + 1'b1;
             end
         end

STATE_DONE_WAIT: begin
    // ========== AGUARDAR TODOS OS 7 CORES COMPLETAREM ==========
    // Pesquisa sinais válidos de resumo SHA-1 (todos 7 resultados prontos)
    // Quando TODOS os cores terminam, captura os resultados
    if (sha1_core_0_digest_valid &&
        sha1_core_1_digest_valid && 
        sha1_core_2_digest_valid && 
        sha1_core_3_digest_valid && 
        sha1_core_4_digest_valid && 
        sha1_core_5_digest_valid && 
        sha1_core_6_digest_valid && 
        sha1_core_7_digest_valid) begin
            sha1_digest_0 <= sha1_core_0_digest;  // Captura resultado de nonce_0
            sha1_digest_0_valid <= 1'b1;
            sha1_digest_1 <= sha1_core_1_digest;  // Captura resultado de nonce_1
            sha1_digest_1_valid <= 1'b1;
            sha1_digest_2 <= sha1_core_2_digest;  
            sha1_digest_2_valid <= 1'b1;
            sha1_digest_3 <= sha1_core_3_digest;  
            sha1_digest_3_valid <= 1'b1;
            sha1_digest_4 <= sha1_core_4_digest;  
            sha1_digest_4_valid <= 1'b1;
            sha1_digest_5 <= sha1_core_5_digest;  
            sha1_digest_5_valid <= 1'b1;
            sha1_digest_6 <= sha1_core_6_digest;  
            sha1_digest_6_valid <= 1'b1;
            sha1_digest_7 <= sha1_core_7_digest;  
            sha1_digest_7_valid <= 1'b1;

            clock_counter <= 28'd0;
            state <= STATE_RESULT;
    end
end

STATE_RESULT: begin
    // ========== VERIFICAR OCTA-CORE: MATCH EM NONCE_0 OU NONCE_1 OU ... OU NONCE_* ==========
    // Lógica: Verifica se SHA1(msg) correspondem ao esperado
    // Ou se atingimos limite de dificuldade (nonce_0 >= DIFFICULTY-1, o que faria nonce_1 até nonce_* >= DIFFICULTY)
    //        ************************************** MATCH **************************************
    if ((sha1_digest_0 == SHA1_EXPECTED) || 
        (sha1_digest_1 == SHA1_EXPECTED) || 
        (sha1_digest_2 == SHA1_EXPECTED) || 
        (sha1_digest_3 == SHA1_EXPECTED) || 
        (sha1_digest_4 == SHA1_EXPECTED) || 
        (sha1_digest_5 == SHA1_EXPECTED) || 
        (sha1_digest_6 == SHA1_EXPECTED) || 
        (sha1_digest_7 == SHA1_EXPECTED) || 
        (nonce_0 >= DIFFICULTY - 1)) begin
            // ========== CORRESPONDÊNCIA ENCONTRADA OU DIFICULDADE ATINGIDA ==========
            led_green_output <= 1'b1;   // LED: correspondência encontrada!
            led_red_output <= 1'b0;     // Desativa indicador de trabalho
        
         // ========== AGUARDAR TODOS OS 7 CORES PRONTOS ANTES DE RETORNAR À IDLE ==========
         if (sha1_core_0_ready && 
             sha1_core_1_ready && 
             sha1_core_2_ready && 
             sha1_core_3_ready && 
             sha1_core_4_ready && 
             sha1_core_5_ready && 
             sha1_core_6_ready && 
             sha1_core_7_ready) begin
                state <= STATE_IDLE;
                clock_counter <= 28'd0;
                
                sha1_digest_0_valid <= 1'b0;
                sha1_digest_1_valid <= 1'b0;
                sha1_digest_2_valid <= 1'b0;
                sha1_digest_3_valid <= 1'b0;
                sha1_digest_4_valid <= 1'b0;
                sha1_digest_5_valid <= 1'b0;
                sha1_digest_6_valid <= 1'b0;
                sha1_digest_7_valid <= 1'b0;

                nonce_increment_done <= 1'b0;  // Reinicia flag para próximo buffer de mensagem
        end else begin
            // Pisca LED enquanto aguarda cores ficarem prontos
            if (clock_counter >= 28'd5) begin
                clock_counter <= 28'd0;
                led_green_output <= ~led_green_output;  // Alterna LED
            end else begin
                clock_counter <= clock_counter + 1'b1;
            end
        end
    end else begin
        // ========== SEM CORRESPONDÊNCIA: INCREMENTA NONCE E TENTA NOVAMENTE ==========
         led_red_output <= 1'b0;
         
         // Sem correspondência: incrementa nonce_0 em +8 para próxima tentativa
         // e recalcula SHA-1 para todos os 8 nonces
         if (sha1_core_0_ready &&
            sha1_core_1_ready && 
            sha1_core_2_ready && 
            sha1_core_3_ready && 
            sha1_core_4_ready && 
            sha1_core_5_ready && 
            sha1_core_6_ready && 
            sha1_core_7_ready) begin
                 // Incrementa nonce_0 em +8 (para processar próximas 8 nonces)
                 if (nonce_0 < DIFFICULTY - 1) begin
                    nonce_0 <= nonce_0 + 32'd8;
                end else begin
                    nonce_0 <= 32'd0;  // Reinicia para 0 após atingir dificuldade máxima
                end
                
                state <= STATE_INIT_SHA1;  // Volta ao init para próxima iteração
                clock_counter <= 28'd0;

                sha1_digest_0_valid <= 1'b0;  // Limpa para próxima computação
                sha1_digest_1_valid <= 1'b0;  
                sha1_digest_2_valid <= 1'b0;  
                sha1_digest_3_valid <= 1'b0;  
                sha1_digest_4_valid <= 1'b0;  
                sha1_digest_5_valid <= 1'b0;  
                sha1_digest_6_valid <= 1'b0;  
                sha1_digest_7_valid <= 1'b0;  

                led_red_output <= ~led_red_output;  // Reativa LED indicador de trabalho
        end
    end
end

default: begin
            state <= STATE_RESET;
        end
    endcase
end

// Máquina de Estados de Recepção e Transmissão UART
// ===================================================

// Estados da máquina de estados UART
localparam UART_IDLE         = 2'd0;  // Acumulando bytes no buffer
localparam UART_BUFFER_FULL  = 2'd1;  // Buffer completo, pronto para computação SHA-1
localparam UART_TRANSMIT_NONCE = 2'd2; // Transmitindo resultado de nonce (4 bytes = 32 bits)
localparam UART_TX_DONE      = 2'd3;  // Transmissão completa

// Registradores da máquina de estados UART
reg [1:0] uart_state;           // Estado atual

// Sinais combinacionais para controle baseado em estado
// Sinal: início SHA-1 (ativado quando buffer UART está cheio)
// Isso notifica a máquina de estados SHA-1 que nova mensagem está pronta
assign sha1_start = (uart_state == UART_BUFFER_FULL) ? 1'b1 : 1'b0;

// Sinal: transmissão UART completa (ativado quando transmissão termina)
// Notifica a máquina de estados SHA-1 para reiniciar nonce para próxima mensagem
assign uart_tx_done_signal = (uart_state == UART_TX_DONE) ? 1'b1 : 1'b0;

reg [6:0] byte_count;           // Contador de recepção: 0 a 80 (necessita 7 bits)
reg [4:0] tx_index;             // Índice de transmissão: 0 a 3 para 4 bytes de nonce (necessita 5 bits)

// Registrador para armazenar qual nonce transmitir (nonce_0 ou nonce_1 ou nonce_2 ou nonce_3)
reg [31:0] nonce_to_transmit = 32'd0;  // Inicializado para 0 - Armazena nonce a ser transmitido

// Detector de borda de subida: detecta chegada de novo byte UART
reg rx_valid_reg1;
reg rx_valid_reg2;
wire rx_new_byte = rx_valid_reg1 && !rx_valid_reg2;

// Máquina de estados UART: manipula recepção de mensagem e transmissão de resultado
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
         // Reinicia: inicializa todas as variáveis de estado UART
         uart_state <= UART_IDLE;
         byte_count <= 7'd0;  // Começa em 0 (suporta até 80)
         tx_index <= 5'd0;    // Começa em 0 (transmite 4 bytes: índices 0-3)
         tx_data <= 8'd0;
         tx_data_valid <= 1'b0;
         rx_valid_reg1 <= 1'b0;
         rx_valid_reg2 <= 1'b0;

    end else begin
        // Detecção de borda de subida: captura chegada de novo byte UART
        rx_valid_reg1 <= rx_data_valid;
        rx_valid_reg2 <= rx_valid_reg1;

        // Lógica principal da máquina de estados UART
        case (uart_state)
            //------------------------------------------
UART_IDLE: begin
                // Acumula bytes no buffer conforme chegam
                // byte_count rastreia quantos bytes foram recebidos até agora (0 a 80)
                tx_data_valid <= 1'b0;  // Ainda não transmitindo

                // Novo byte chegou: armazena e incrementa contador
                if (rx_new_byte && byte_count < BUFFER_SIZE) begin
                    buffer[byte_count] <= rx_data;      // Armazena no índice atual
                    byte_count <= byte_count + 1'b1;    // Incrementa contador
                    
                     // Transição quando último byte recebido (byte_count atinge 79, incrementará para 80)
                     if (byte_count == BUFFER_SIZE - 1) begin
                         uart_state <= UART_BUFFER_FULL;
                     end
                end
            end

             //------------------------------------------
UART_BUFFER_FULL: begin
    // ========== AGUARDAR RESULTADO DE OCTA-CORE SHA-1 ==========
    // Incremento de nonce_0 acontece na máquina de estados SHA-1 (STATE_IDLE e STATE_RESULT)
    
    // Quando resultado SHA-1 estão prontos, prepara transmissão do nonce correto
    // Transmite nonce_0 se SHA1(msg) == SHA1_EXPECTED
    // ...
    // Transmite nonce_0 até nonce_* se atingiu dificuldade máxima (>= DIFFICULTY-1)
    
      if ((sha1_digest_0_valid && tx_data_ready && (sha1_digest_0 == SHA1_EXPECTED)) ||
          (sha1_digest_1_valid && tx_data_ready && (sha1_digest_1 == SHA1_EXPECTED)) ||
          (sha1_digest_2_valid && tx_data_ready && (sha1_digest_2 == SHA1_EXPECTED)) ||
          (sha1_digest_3_valid && tx_data_ready && (sha1_digest_3 == SHA1_EXPECTED)) ||
          (sha1_digest_4_valid && tx_data_ready && (sha1_digest_4 == SHA1_EXPECTED)) ||
          (sha1_digest_5_valid && tx_data_ready && (sha1_digest_5 == SHA1_EXPECTED)) ||
          (sha1_digest_6_valid && tx_data_ready && (sha1_digest_6 == SHA1_EXPECTED)) ||
          (sha1_digest_7_valid && tx_data_ready && (sha1_digest_7 == SHA1_EXPECTED)) ||
          (nonce_0 >= DIFFICULTY - 1)) begin
          
          // ========== SELECIONAR QUAL NONCE TRANSMITIR ==========
          // Prioridade: nonce_7 (verifica primeiro), depois restante...
          // Seleciona o nonce E IMEDIATAMENTE armazena em nonce_to_transmit
          if (sha1_digest_7 == SHA1_EXPECTED) begin
              nonce_to_transmit <= nonce_7;  // Transmite nonce_7 
              tx_data <= nonce_7[31:24];     // Byte 0 MSB - Lê diretamente do nonce
          end else 
          if (sha1_digest_6 == SHA1_EXPECTED) begin
              nonce_to_transmit <= nonce_6;  // Transmite nonce_6 
              tx_data <= nonce_6[31:24];     // Byte 0 MSB - Lê diretamente do nonce
          end else 
          if (sha1_digest_5 == SHA1_EXPECTED) begin
              nonce_to_transmit <= nonce_5;  // Transmite nonce_5 
              tx_data <= nonce_5[31:24];     // Byte 0 MSB - Lê diretamente do nonce
          end else 
          if (sha1_digest_4 == SHA1_EXPECTED) begin
              nonce_to_transmit <= nonce_4;  // Transmite nonce_4 
              tx_data <= nonce_4[31:24];     // Byte 0 MSB - Lê diretamente do nonce
          end else 
          if (sha1_digest_3 == SHA1_EXPECTED) begin
              nonce_to_transmit <= nonce_3;  // Transmite nonce_3 
              tx_data <= nonce_3[31:24];     // Byte 0 MSB - Lê diretamente do nonce
          end else 
          if (sha1_digest_2 == SHA1_EXPECTED) begin
              nonce_to_transmit <= nonce_2;  // Transmite nonce_2 
              tx_data <= nonce_2[31:24];     // Byte 0 MSB - Lê diretamente do nonce
          end else 
          if (sha1_digest_1 == SHA1_EXPECTED) begin
              nonce_to_transmit <= nonce_1;  // Transmite nonce_1 
              tx_data <= nonce_1[31:24];     // Byte 0 MSB - Lê diretamente do nonce
          end else begin
              nonce_to_transmit <= nonce_0;  // Transmite nonce_0 por padrão
              tx_data <= nonce_0[31:24];     // Byte 0 MSB - Lê diretamente do nonce
          end
         
         // Começa transmissão do resultado de nonce de 4 bytes
         tx_data_valid <= 1'b1;

         tx_index <= 5'd0;                     // Começa no índice 0
         uart_state <= UART_TRANSMIT_NONCE;    // Move para estado de transmissão
     end
end

UART_TRANSMIT_NONCE: begin
     // ========== TRANSMITIR 4 BYTES DO NONCE OCTA-CORE ==========
     // Transmite nonce_to_transmit (que contém nonce_0 até nonce_*)
     // Ordem de transmissão: MSB-primeiro (big-endian) [31:24], [23:16], [15:8], [7:0]
     
     if (tx_data_ready) begin
          if (tx_index < 5'd3) begin
              // Mais bytes de nonce para transmitir: prepara próximo byte
              // tx_index: 0?1?2?3 (4 transições para 4 bytes total)
              tx_index <= tx_index + 1'b1;
             
             // Extrai próximo byte do nonce_to_transmit usando (tx_index + 1)
             case(tx_index + 1'b1)
                 5'd1:  tx_data <= nonce_to_transmit[23:16];   // Byte 1
                 5'd2:  tx_data <= nonce_to_transmit[15:8];    // Byte 2
                 5'd3:  tx_data <= nonce_to_transmit[7:0];     // Byte 3 (LSB)
                 default: tx_data <= 8'd0;
             endcase
             
             tx_data_valid <= 1'b1;
         end else begin
             // Todos os 4 bytes de nonce (índices 0-3) transmitidos: finaliza
             tx_data_valid <= 1'b0;

             uart_state <= UART_TX_DONE;
         end
     end
 end

             //------------------------------------------
UART_TX_DONE: begin
                  // Transmissão completa: prepara para próxima mensagem
                  // Reinicia byte_count para 0 para receber próximo buffer de mensagem
                  byte_count <= 7'd0;
                  uart_state <= UART_IDLE;
                  // Nota: máquina de estados SHA-1 reinicia nonce quando transmissão UART completa
               end
        endcase
    end
end


endmodule
