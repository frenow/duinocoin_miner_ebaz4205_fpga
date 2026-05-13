/*
Did you like the project? Leave a star ? or buy me a coffee ?.
DuinoCoin Wallet: frenow
BTC Wallet: bc1qdf5qhmfymltn8xu52grlnskdelz8unsznljwe5
by frenow@gmail.com
*/

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

parameter DIFFICULTY = 99999999; // Valor máximo de nonce para proof-of-work (100.000.000 iterações) -> 99.999.999

// ========================================================================
// CONSTANTE: Quantidade de cores (MAX_CORE define quantas vezes o modulo se repete)
// Mude este valor para instanciar dinamicamente mais ou menos cores
// ========================================================================
localparam MAX_CORE = 8;  // 8 cores: nonce_0 a nonce_7 (MUDE AQUI para 2, 4, 16, 32, etc)
                          // Cada core processa um nonce em paralelo
                          // Incremento: nonce_0 += MAX_CORE a cada iteracao


// ========================================
// ESTRATÉGIA MULT SHA-1 CORE
// ========================================
// Implementação: n cores SHA-1 em paralelo para nX velocidade de mineração
// - sha1_core_0 até sha1_core_n: processam nonce_0 até nonce_n simultaneamente
// - nonce_0 é o registrador; nonce_1-n são derivados combinacionalmente

// - Todos n cores executam SHA-1 simultaneamente
// - Incremento: nonce_0 += MAX_CORE a cada iteração
// - Resultado: até nx velocidade vs. implementação com 1 core

// Mensagem de entrada (dinâmica): 40 bytes recebidos via UART, armazenados em buffer[0..39]
// Hash SHA-1 esperado: 40 caracteres ASCII hexadecimais recebidos via UART, armazenados em buffer[40..79]
// Hash representa 20 bytes binários (160 bits) para comparação SHA-1
wire [159:0] SHA1_EXPECTED;  // Hash SHA-1 esperado (160 bits = 20 bytes, decodificado de buffer[40..79])

// Variavel nonce MULT-core: 
// - nonce_0: valor atual (registrador) - SEQUENCIAL
// - nonce_1 a nonce_n: nonce_0 + 1 a nonce_0 + n - DERIVADOS COMBINACIONALMENTE
// Nota: 32 bits suportam ate 4.294.967.295, mais que suficiente para 100.000.000 dificuldade
// ========================================================================
// NONCES: Registrador principal + derivacoes combinacionais
// ========================================================================
reg [31:0] nonce_0;  // Nonce para sha1_core_0 (Incrementado +MAX_CORE)
wire [31:0] nonce [0:MAX_CORE-1];  // Array de fios para nonces (nonce_0 + 0, nonce_0 + 1, ..., nonce_0 + MAX_CORE-1)
 
// ========================================================================
// GENERATE: Gera nonces derivados combinacionalmente
// ========================================================================
// Loop dinamico: para cada valor de i (0 ate MAX_CORE-1)
// - nonce[0] = nonce_0 + 0
// - nonce[1] = nonce_0 + 1
// - nonce[2] = nonce_0 + 2
// - ...
// - nonce[MAX_CORE-1] = nonce_0 + (MAX_CORE-1)
// Dessa forma, os cores SHA-1 processam nonces consecutivos em paralelo
// ========================================================================
generate
    genvar i;
    for (i = 0; i < MAX_CORE; i = i + 1) begin : nonce_gen
        // Calcula o i-esimo nonce: nonce_0 + offset (i)
        assign nonce[i] = nonce_0 + i;
    end
endgenerate


// Conversao ASCII do nonce: comprimento variavel (sem zeros a esquerda)
// Maximo 9 bytes para valores ate 999.999.999 (menos que 1.000.000.000)
// Exemplo: nonce=1        -> nonce_ascii="1"         (1 byte)
//          nonce=12345    -> nonce_ascii="12345"     (5 bytes)
//          nonce=120000000 -> nonce_ascii="120000000" (9 bytes)

// ========================================================================
// BCD CONVERTER DINAMICO: Converte nonce para 9 digitos BCD
// Instancia automaticamente MAX_CORE modulos nonce_bcd_simple
// ========================================================================

// Arrays para armazenar os sinais dos digitos BCD de cada core
wire [3:0] digit9  [0:MAX_CORE-1];
wire [3:0] digit8  [0:MAX_CORE-1];
wire [3:0] digit7  [0:MAX_CORE-1];
wire [3:0] digit6  [0:MAX_CORE-1];
wire [3:0] digit5  [0:MAX_CORE-1];
wire [3:0] digit4  [0:MAX_CORE-1];
wire [3:0] digit3  [0:MAX_CORE-1];
wire [3:0] digit2  [0:MAX_CORE-1];
wire [3:0] digit1  [0:MAX_CORE-1];
wire [3:0] nonce_ascii_len [0:MAX_CORE-1];  // Comprimento de cada nonce em ASCII

// ========================================================================
// CONVERSAO BCD -> ASCII DINAMICA
// Array de nonce_ascii para todos os cores
// ========================================================================
reg [71:0] nonce_ascii [0:MAX_CORE-1];  // Expandido para 72 bits (9 bytes = ate 9 digitos)

// ========================================================================
// GENERATE: Instancia MAX_CORE modulos nonce_bcd_simple
// ========================================================================
// Loop dinamico: para cada valor de j (0 ate MAX_CORE-1)
// - Cria instancia: bcd_inst[0], bcd_inst[1], ..., bcd_inst[MAX_CORE-1]
// - Conecta nonce[j] como entrada (nonce_0 + j)
// - Conecta saidas BCD (digit1-digit9) e comprimento (digit_count)
// - Simples: sem senhas de clock, puramente combinacional
// ========================================================================
generate
    genvar j;
    for (j = 0; j < MAX_CORE; j = j + 1) begin : bcd_loop
        // Instancia modulo nonce_bcd_simple para o j-esimo core
        nonce_bcd_simple bcd_inst (
            .nonce(nonce[j]),                // Entrada: nonce correspondente (nonce_0 + j)
            .digit9(digit9[j]),              // Saidas BCD: digitos em codigo BCD puro (0-9)
            .digit8(digit8[j]),
            .digit7(digit7[j]),
            .digit6(digit6[j]),
            .digit5(digit5[j]),
            .digit4(digit4[j]),
            .digit3(digit3[j]),
            .digit2(digit2[j]),
            .digit1(digit1[j]),
            .digit_count(nonce_ascii_len[j]) // Saida: quantos digitos vavalidos (1-9)
        );
    end
endgenerate

// ========================================================================
// GENERATE: Logica combinacional para converter BCD em ASCII
// ========================================================================
// Loop dinamico: para cada valor de k (0 ate MAX_CORE-1)
// - Converte cada digito BCD (0-9) em ASCII (0x30-0x39):
//   * BCD 0 -> ASCII 0x30 ('0')
//   * BCD 1 -> ASCII 0x31 ('1')
//   * ...
//   * BCD 9 -> ASCII 0x39 ('9')
// - Baseado no comprimento (nonce_ascii_len[k]), monta a string ASCII
//   * 1 digito: apenas digit1
//   * 2 digitos: digit2 + digit1
//   * 9 digitos: digit9 + digit8 + ... + digit1
// - Preenchimento esquerdo com zeros (exemplo: 9 bytes para 9 digitos)
// ========================================================================
generate
    genvar k;
    for (k = 0; k < MAX_CORE; k = k + 1) begin : ascii_conv_loop
        // LoLogica combinacional para o k-esimo core
        always @(*) begin
            // Case: converte digitos BCD em ASCII com base no comprimento
            case (nonce_ascii_len[k])
                4'd1: nonce_ascii[k] = {64'd0, 8'h30 + digit1[k]};
                4'd2: nonce_ascii[k] = {56'd0, 8'h30 + digit2[k], 8'h30 + digit1[k]};
                4'd3: nonce_ascii[k] = {48'd0, 8'h30 + digit3[k], 8'h30 + digit2[k], 8'h30 + digit1[k]};
                4'd4: nonce_ascii[k] = {40'd0, 8'h30 + digit4[k], 8'h30 + digit3[k], 8'h30 + digit2[k], 8'h30 + digit1[k]};
                4'd5: nonce_ascii[k] = {32'd0, 8'h30 + digit5[k], 8'h30 + digit4[k], 8'h30 + digit3[k], 8'h30 + digit2[k], 8'h30 + digit1[k]};
                4'd6: nonce_ascii[k] = {24'd0, 8'h30 + digit6[k], 8'h30 + digit5[k], 8'h30 + digit4[k], 8'h30 + digit3[k], 8'h30 + digit2[k], 8'h30 + digit1[k]};
                4'd7: nonce_ascii[k] = {16'd0, 8'h30 + digit7[k], 8'h30 + digit6[k], 8'h30 + digit5[k], 8'h30 + digit4[k], 8'h30 + digit3[k], 8'h30 + digit2[k], 8'h30 + digit1[k]};
                4'd8: nonce_ascii[k] = {8'd0,  8'h30 + digit8[k], 8'h30 + digit7[k], 8'h30 + digit6[k], 8'h30 + digit5[k], 8'h30 + digit4[k], 8'h30 + digit3[k], 8'h30 + digit2[k], 8'h30 + digit1[k]};
                4'd9: nonce_ascii[k] = {8'h30 + digit9[k], 8'h30 + digit8[k], 8'h30 + digit7[k], 8'h30 + digit6[k], 8'h30 + digit5[k], 8'h30 + digit4[k], 8'h30 + digit3[k], 8'h30 + digit2[k], 8'h30 + digit1[k]};
                default: nonce_ascii[k] = 72'd0;
            endcase
        end
    end
endgenerate

// ========================================================================
// COMPRIMENTO DA MENSAGEM: Calculo dinamico para cada core
// ========================================================================
// Calculo do comprimento da mensagem em bits para cada core
// ========================================================================
// GENERATE: Calcula comprimento da mensagem em bits
// ========================================================================
// Loop dinamico: para cada valor de m (0 ate MAX_CORE-1)
// - Comprimento = 40 bytes (mensagem fixa) + nonce_ascii_len[m] bytes
// - Exemplo: msg (40B) + nonce "12345" (5B) = 45 bytes = 360 bits
// - Calculo em bits: msg_length_bits[m] = (40 + nonce_ascii_len[m]) * 8
//                                        = 320 + (nonce_ascii_len[m] << 3)
// ========================================================================
wire [15:0] msg_length_bits [0:MAX_CORE-1];
generate
    genvar m;
    for (m = 0; m < MAX_CORE; m = m + 1) begin : msg_len_loop
        // Comprimento = 40 bytes (mensagem) + nonce_ascii_len bytes
        // Em bits = (40 + nonce_ascii_len) * 8 = 320 + (nonce_ascii_len << 3)
        assign msg_length_bits[m] = 16'd320 + (nonce_ascii_len[m] << 3);
    end
endgenerate

// Bloco de mensagem: bloco de entrada de 512 bits com preenchimento (padrão RFC 3174 SHA-1)
// Estrutura dinâmica:
//   Bytes 0-39:  Mensagem (40 bytes) do buffer UART
//   Bytes 40+:   Nonce ASCII (1-9 bytes, comprimento variável, sem zeros à esquerda, até 120M)
//   Byte 47+:    0x80 (marcador de preenchimento) + bytes zero + comprimento_mensagem_bits (64-bit big-endian)
// ========================================================================
// BLOCOS DE MENSAGEM DINAMICOS
// ========================================================================
reg [511:0] MESSAGE_BLOCK [0:MAX_CORE-1];

// Implementa buffering de 80 bytes: 40 bytes de mensagem + 40 bytes de hash ASCII hex
// Recebe buffer completo, então dispara computação SHA-1
// Ao encontrar correspondência, transmite resultado de nonce de 4 bytes
// Estrutura: buffer[0..39] = mensagem, buffer[40..79] = hash esperado

// Constante de tamanho de buffer
localparam BUFFER_SIZE = 80;  // Total: 40 bytes de mensagem + 40 bytes de hash ASCII
// Buffer de recepção dinâmico
reg [7:0] buffer [0:BUFFER_SIZE-1];  // Buffer de 80 bytes: [0..39] mensagem, [40..79] hash

// Nonce ASCII variável (1-9 bytes) + 0x80 + padding + comprimento
// Usa case statement para selecionar quantidade correta de bits
reg [191:0] nonce_pad_part;  // 24 bytes = 192 bits (resto do bloco)

// Lógica combinacional: constrói dinamicamente todos MESSAGE_BLOCK[*]
generate
    genvar z;
    for (z = 0; z < MAX_CORE; z = z + 1) begin : msg_block_gen
        always @(*) begin : msg_block_builder
            case (nonce_ascii_len[z])
                4'd1: nonce_pad_part = {nonce_ascii[z][7:0],   
                                        8'h80, 
                                        160'h00000000000000000000000000000000000000, 
                                        msg_length_bits[z]};
                4'd2: nonce_pad_part = {nonce_ascii[z][15:0],  
                                        8'h80, 
                                        152'h0000000000000000000000000000000000000, 
                                        msg_length_bits[z]};
                4'd3: nonce_pad_part = {nonce_ascii[z][23:0],  
                                        8'h80, 
                                        144'h000000000000000000000000000000000000, 
                                        msg_length_bits[z]};
                4'd4: nonce_pad_part = {nonce_ascii[z][31:0],  
                                        8'h80, 
                                        136'h00000000000000000000000000000000000, 
                                        msg_length_bits[z]};
                4'd5: nonce_pad_part = {nonce_ascii[z][39:0],  
                                        8'h80, 
                                        128'h0000000000000000000000000000000000, 
                                        msg_length_bits[z]};
                4'd6: nonce_pad_part = {nonce_ascii[z][47:0],  
                                        8'h80, 
                                        120'h000000000000000000000000000000000, 
                                        msg_length_bits[z]};
                4'd7: nonce_pad_part = {nonce_ascii[z][55:0],  
                                        8'h80, 
                                        112'h00000000000000000000000000000000, 
                                        msg_length_bits[z]};
                4'd8: nonce_pad_part = {nonce_ascii[z][63:0],  
                                        8'h80, 
                                        104'h0000000000000000000000000000, 
                                        msg_length_bits[z]};
                4'd9: nonce_pad_part = {nonce_ascii[z][71:0],  
                                        8'h80, 
                                        96'h000000000000000000000000, 
                                        msg_length_bits[z]};
                default: nonce_pad_part = 192'd0;
            endcase
            
            // Monta o bloco completo: mensagem (320b) + nonce+pad (192b) = 512b
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
            // Bytes 0-39: Mensagem fixa do buffer UART
            MESSAGE_BLOCK[z] = {
                buffer[0],  buffer[1],  buffer[2],  buffer[3],  
                buffer[4],  buffer[5],  buffer[6],  buffer[7],
                buffer[8],  buffer[9],  buffer[10], buffer[11], 
                buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], 
                buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], 
                buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], 
                buffer[36], buffer[37], buffer[38], buffer[39]
                , nonce_pad_part};
        end
    end
endgenerate

// SHA1_EXPECTED: Decodifica 40 caracteres ASCII hexadecimais de buffer[40..79] em hash binario de 160 bits
// Converscao: cada par de caracteres ASCII hex [2n, 2n+1] torna-se um byte binario
// Exemplo: ASCII '48' -> 0x48, 'a3' -> 0xa3, etc. (suporta maiusculas e minusculas)
generate
    genvar x;
    for (x = 0; x < 20; x = x + 1) begin : hex_decode
        wire [3:0] high = (buffer[40 + x*2] >= 8'h61) ? (buffer[40 + x*2] - 8'h57) :
                          (buffer[40 + x*2] >= 8'h41) ? (buffer[40 + x*2] - 8'h37) :
                          (buffer[40 + x*2] - 8'h30);
        
        wire [3:0] low = (buffer[40 + x*2 + 1] >= 8'h61) ? (buffer[40 + x*2 + 1] - 8'h57) :
                         (buffer[40 + x*2 + 1] >= 8'h41) ? (buffer[40 + x*2 + 1] - 8'h37) :
                         (buffer[40 + x*2 + 1] - 8'h30);
        
        assign SHA1_EXPECTED[(19-x)*8 +: 8] = {high, low};
    end
endgenerate

// ========================================================================
// SHA-1 CORES DINAMICOS: Instancia MAX_CORE modulos sha1_core
// ========================================================================

// Arrays para sinais de entrada/saida dos cores SHA-1
wire [159:0] sha1_digest       [0:MAX_CORE-1];  // Resumos SHA-1 (160 bits cada)
wire sha1_digest_valid         [0:MAX_CORE-1];  // Flags: resumo valido
wire sha1_core_ready           [0:MAX_CORE-1];  // Flags: core pronto
reg  sha1_init                 [0:MAX_CORE-1];  // Sinais: iniciar core
reg  sha1_next                 [0:MAX_CORE-1];  // Sinais: processar proximo bloco

// Registradores para armazenar resultados dos cores
reg [159:0] sha1_digest_reg    [0:MAX_CORE-1];
reg sha1_digest_valid_reg      [0:MAX_CORE-1];

// Sinais de controle geral
wire sha1_start;                  // Sinal de início: ativado quando buffer UART está cheio (estado BUFFER_FULL)
wire uart_tx_done_signal;         // Sinal de conclusão: ativado quando transmissão UART termina (estado UART_TX_DONE)

reg led_red_output;              // Saída LED: status de correspondência SHA-1
reg led_green_output;           // Saída LED: status de correspondência SHA-1

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

// ========================================================================
// GENERATE: Instancia MAX_CORE modulos sha1_core
// ========================================================================
// Loop dinamico: para cada valor de p (0 ate MAX_CORE-1)
// - Cria instancia sha1_inst[0], sha1_inst[1], ..., sha1_inst[MAX_CORE-1]
// - Cada sha1_core processa um nonce diferente em paralelo:
//   * sha1_inst[0] processa nonce_0
//   * sha1_inst[1] processa nonce_1 = nonce_0 + 1
//   * ...
//   * sha1_inst[MAX_CORE-1] processa nonce_MAX_CORE-1 = nonce_0 + (MAX_CORE-1)
// - Sinais de controle (init, next) e flags (ready, digest_valid) sao indexados
// - Resultado: ate MAX_CORE vezes mais rapido comparado a 1 core
// ========================================================================
generate
    genvar p;
    for (p = 0; p < MAX_CORE; p = p + 1) begin : sha1_loop
        // Instancia modulo sha1_core para n nonce
        sha1_core sha1_inst (
            .clk(clk),
            .reset_n(rst_n),
            .init(sha1_init[p]),              // Sinal de inicializacao (ativado para DISPARAR novo hash)
            .next(sha1_next[p]),              // Sinal de proximo bloco (para blocos multiplos)
            .block(MESSAGE_BLOCK[p]),         // Bloco de mensagem (512 bits)
            .ready(sha1_core_ready[p]),       // Flag: core pronto (pode aceitar novo bloco)
            .digest(sha1_digest[p]),          // Resumo SHA-1 (160 bits)
            .digest_valid(sha1_digest_valid[p])  // Flag: resumo valido (hash completo)
        );
    end
endgenerate

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

// ========================================================================
// LOGICA COMBINACIONAL: Verifica se TODOS os cores completaram
// ========================================================================
// Gera sinal all_digest_ready que ativa quando TODOS os cores tem digest_valid
wire [MAX_CORE-1:0] digest_valid_array;
wire all_digest_ready;

generate
    genvar v;
    for (v = 0; v < MAX_CORE; v = v + 1) begin : digest_check
        assign digest_valid_array[v] = sha1_digest_valid[v];
    end
endgenerate

// Verifica se TODOS os bits estao setados (AND de todos os digest_valid)
assign all_digest_ready = &digest_valid_array;

// ========================================================================
// LOGICA COMBINACIONAL: Verifica se TODOS os cores estao prontos
// ========================================================================
wire [MAX_CORE-1:0] ready_array;
wire all_cores_ready_combined;

generate
    genvar u;
    for (u = 0; u < MAX_CORE; u = u + 1) begin : ready_check
        assign ready_array[u] = sha1_core_ready[u];
    end
endgenerate

assign all_cores_ready_combined = &ready_array;

// ========================================================================
// LOGICA COMBINACIONAL: Verifica correspondencia em qualquer core
// ========================================================================
wire [MAX_CORE-1:0] match_array;
wire match_found;

generate
    genvar n;
    for (n = 0; n < MAX_CORE; n = n + 1) begin : match_check
        assign match_array[n] = (sha1_digest_reg[n] == SHA1_EXPECTED);
    end
endgenerate

assign match_found = |match_array;

// Lógica principal da máquina de estados SHA-1
// Implementa mineração proof-of-work com MULT-CORE SHA-1
// itera nonce_0 de MAX_CORE em MAX_CORE: processando nonce_0 até nonce_n em paralelo
always @(posedge clk) begin : sha1_state_machine
    // ========== RESET DOS SINAIS DE CONTROLE ==========
    // Estes sinais sao pulsados (ativos por 1 ciclo apenas)
    integer q, r, s, c, e, f;
    for (q = 0; q < MAX_CORE; q = q + 1) begin
        sha1_init[q] <= 1'b0;
        sha1_next[q] <= 1'b0;
    end    

    case (state)
STATE_RESET: begin
    // ========== INICIALIZAÇÃO: RESET GERAL ==========
    // Reinicia todos os contadores e saídas
    led_red_output   <= 1'b0;
    led_green_output <= 1'b0;

    nonce_0 <= 32'd0;  // Reinicia nonce_0 para 0 na inicialização

    state <= STATE_IDLE;
end

STATE_IDLE: begin
    // ========== AGUARDAR MULT-CORE PRONTO + BUFFER CHEIO ==========
    // Reinicia nonce_0 quando transmissão UART completa (prepara para próxima mensagem)
    if (uart_tx_done_signal) begin
        nonce_0 <= 32'd0;
    end
    
    // ========== TRANSICAO PARA INIT_SHA1 ==========
    // Condicao: TODOS n cores prontos AND buffer cheio
    if (all_cores_ready_combined && sha1_start) begin
        state <= STATE_INIT_SHA1;
    end
end

STATE_INIT_SHA1: begin
    // ========== DISPARAR TODOS OS 7 CORES SHA-1 ==========
    // Inicializa simultaneamente:
    // - sha1_core_0 com MESSAGE_BLOCK_0 (nonce_0)
    // - sha1_core_1 com MESSAGE_BLOCK_1 (nonce_1 = nonce_0 + 1)
    // - ...
    // - sha1_core_6 com MESSAGE_BLOCK_6 (nonce_6 = nonce_0 + 6)
    led_red_output <= 1'b1;  // LED: indica que processamento começou
    
    // Iniciar TODOS os cores simultaneamente
    for (s = 0; s < MAX_CORE; s = s + 1) begin
        sha1_init[s] <= 1'b1;
    end
    
    state <= STATE_RUNNING;
end

STATE_RUNNING: begin
             state <= STATE_DONE_WAIT;
         end

STATE_DONE_WAIT: begin
    // ========== AGUARDAR TODOS OS CORES COMPLETAREM ==========
    // Pesquisa sinais validos de resumo SHA-1 (todos resultados prontos)
    // Quando TODOS os cores terminam, captura os resultados

    if (all_digest_ready) begin
        // Captura resultados de TODOS os cores dinamicamente
        // Os resultados sao armazenados em sha1_digest_reg[c] e sha1_digest_valid_reg[c]
        for (c = 0; c < MAX_CORE; c = c + 1) begin
            sha1_digest_reg[c] <= sha1_digest[c];
            sha1_digest_valid_reg[c] <= 1'b1;
        end
    
        state <= STATE_RESULT;
    end
end

STATE_RESULT: begin
    // ========== VERIFICAR MULT-CORE: MATCH EM NONCE_0 OU NONCE_1 OU ... OU NONCE_MAX ==========
// Logica: Verifica se SHA1(msg) correspondem ao esperado para qualquer core
// Ou se atingimos limite de dificuldade (nonce_0 >= DIFFICULTY-1)
//------------------------------------MATCH------------------------------------------
if (match_found || (nonce_0 >= DIFFICULTY - MAX_CORE)) begin
    // ========== correspondencia ENCONTRADA OU DIFICULDADE ATINGIDA ==========
    led_green_output <= 1'b1;   // LED: correspondencia encontrada!
    led_red_output <= 1'b0;     // Desativa indicador de trabalho

    // ========== AGUARDAR TODOS OS CORES PRONTOS ANTES DE RETORNAR A IDLE ==========
    if (all_cores_ready_combined) begin
        state <= STATE_IDLE;
        
        // Limpa flags de validade para proximo ciclo
        for (e = 0; e < MAX_CORE; e = e + 1) begin
            sha1_digest_valid_reg[e] <= 1'b0;
        end

    end else begin
        // Pisca LED enquanto aguarda cores ficarem prontos
        led_green_output <= ~led_green_output;  // Alterna LED
    end
end else begin
    // ========== SEM correspondencia: Incrementa NONCE E TENTA NOVAMENTE ==========
    led_red_output <= 1'b0;
    
    // Sem correspondencia: Incrementa nonce_0 em +MAX_CORE para proxima tentativa
    // e recalcula SHA-1 para todos os nonces
    if (all_cores_ready_combined) begin
        // Incrementa nonce_0 em +MAX_CORE (para processar proximos nonces)
        if (nonce_0 < DIFFICULTY - MAX_CORE) begin
            nonce_0 <= nonce_0 + MAX_CORE;
        end else begin
            nonce_0 <= 32'd0;  // Reinicia para 0 apos atingir dificuldade maxima
        end
        
        state <= STATE_INIT_SHA1;  // Volta ao init para proxima iteracao

        // Limpa flags de validade para proxima computa
        for (f = 0; f < MAX_CORE; f = f + 1) begin
            sha1_digest_valid_reg[f] <= 1'b0;
        end

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
reg [7:0] match_index_reg = 8'd0;      // Registrador para armazenar indice do nonce que corresponde
integer idx_match;                      // Indice para pesquisa de correspondencia

// ========================================================================
// LOGICA COMBINACIONAL: Encontra o indice do nonce que corresponde
// ========================================================================
// Pesquisa arrays dinamicamente: verifica qual core tem uma correspondencia
// Resultado armazenado em match_index_reg para uso na UART state machine
always @(*) begin
    match_index_reg = 0;  // Padrao: nonce_0
    
    // Pesquisa linear: encontra o PRIMEIRO core que combina
    for (idx_match = 0; idx_match < MAX_CORE; idx_match = idx_match + 1) begin
        if (sha1_digest_reg[idx_match] == SHA1_EXPECTED) begin
            match_index_reg = idx_match;
        end
    end
end

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
    // ========== AGUARDAR RESULTADO DE MULT-CORE SHA-1 ==========
    // Incremento de nonce_0 acontece na Maquina de estados SHA-1 (STATE_IDLE e STATE_RESULT)

    // Quando resultado SHA-1 estao prontos, prepara transmissao do nonce correto
    // Transmite nonce correspondente quando SHA1(msg) == SHA1_EXPECTED para qualquer core
    // Ou transmite nonce_0 se atingiu dificuldade maxima (>= DIFFICULTY-1)

    // Verifica se qualquer core encontrou correspondencia OU atingiu dificuldade maxima
    if ((match_found || (nonce_0 >= DIFFICULTY - MAX_CORE)) && tx_data_ready) begin          
            // ========== SELECIONAR QUAL NONCE TRANSMITIR ==========
        // Usa match_index_reg (ja calculado em logica combinacional)
        // Transmite o nonce do core que encontrou correspondencia
        
        // Armazena o nonce que corresponde (nonce_0 + match_index_reg)
        tx_data <= nonce[match_index_reg][31:24];  // Byte 0 MSB - LSB primeiro na transmissao
        
        // Comeca transmissao do resultado de nonce de 4 bytes
        tx_data_valid <= 1'b1;
        tx_index <= 5'd0;                       // Comeca no indice 0
        uart_state <= UART_TRANSMIT_NONCE;      // Move para estado de transmissao
    end
end

UART_TRANSMIT_NONCE: begin
     // ========== TRANSMITIR 4 BYTES DO NONCE MULT-CORE ==========
     // Transmite nonce_to_transmit (que contém nonce_0 até nonce_n)
     // Ordem de transmissão: MSB-primeiro (big-endian) [31:24], [23:16], [15:8], [7:0]
     
     if (tx_data_ready) begin
          if (tx_index < 5'd3) begin
              // Mais bytes de nonce para transmitir: prepara próximo byte
              // tx_index: 0?1?2?3 (4 transições para 4 bytes total)
              tx_index <= tx_index + 1'b1;
             
             // Extrai próximo byte do nonce_to_transmit usando (tx_index + 1)
             case(tx_index + 1'b1)
                 5'd1:  tx_data <= nonce[match_index_reg][23:16];   // Byte 1
                 5'd2:  tx_data <= nonce[match_index_reg][15:8];    // Byte 2
                 5'd3:  tx_data <= nonce[match_index_reg][7:0];     // Byte 3 (LSB)
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
