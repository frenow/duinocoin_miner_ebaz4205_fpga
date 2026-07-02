/*
Did you like the project? Leave a star or buy me a coffee.
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

parameter CLK_FRE  = 50;      // Frequencia do clock em MHz
parameter UART_FRE = 115200;  // Baud rate UART

parameter DIFFICULTY = 999999999; // Nonce maximo para proof-of-work

// Quantidade de cores SHA-1 em paralelo (nonce_0 + 0 .. nonce_0 + MAX_CORE-1)
// Hashrate ~ MAX_CORE / ~86 ciclos x 50MHz. Aumente enquanto couber no FPGA.
localparam MAX_CORE = 20;

// ========================================================================
// Nonces
// ========================================================================
reg  [31:0] nonce_0;       // Nonce binario base (para transmissao e dificuldade)
reg  [39:0] nonce_bcd_0;   // Mesmo nonce em BCD (para montar a mensagem)

// Incremento BCD do nonce base: nonce_bcd_0 + MAX_CORE (ripple decimal simples).
// Usado no registrador da FSM. So os 2 digitos mais baixos recebem a constante.
reg  [39:0] nonce_bcd_next;
always @(*) begin : bcd_increment
    integer bi;
    reg [4:0] bs;
    reg [3:0] bk;
    reg       bc;
    bc = 1'b0;
    for (bi = 0; bi < 10; bi = bi + 1) begin
        if      (bi == 0) bk = MAX_CORE % 10;
        else if (bi == 1) bk = (MAX_CORE / 10) % 10;
        else              bk = 4'd0;
        bs = nonce_bcd_0[bi*4 +: 4] + bk + bc;
        if (bs > 5'd9) begin bs = bs - 5'd10; bc = 1'b1; end
        else                 bc = 1'b0;
        nonce_bcd_next[bi*4 +: 4] = bs[3:0];
    end
end

wire [31:0] nonce [0:MAX_CORE-1];  // nonce binario por core = nonce_0 + i
generate
    genvar i;
    for (i = 0; i < MAX_CORE; i = i + 1) begin : nonce_gen
        assign nonce[i] = nonce_0 + i;
    end
endgenerate

// ========================================================================
// Buffer UART: 80 bytes -> [0..39] mensagem, [40..79] hash esperado (ASCII hex)
// ========================================================================
localparam BUFFER_SIZE = 80;
reg [7:0] buffer [0:BUFFER_SIZE-1];

// Hash esperado (160 bits) decodificado de buffer[40..79]
wire [159:0] SHA1_EXPECTED;
generate
    genvar x;
    for (x = 0; x < 20; x = x + 1) begin : hex_decode
        wire [3:0] high = (buffer[40 + x*2] >= 8'h61) ? (buffer[40 + x*2] - 8'h57) :
                          (buffer[40 + x*2] >= 8'h41) ? (buffer[40 + x*2] - 8'h37) :
                          (buffer[40 + x*2] - 8'h30);
        wire [3:0] low  = (buffer[40 + x*2 + 1] >= 8'h61) ? (buffer[40 + x*2 + 1] - 8'h57) :
                          (buffer[40 + x*2 + 1] >= 8'h41) ? (buffer[40 + x*2 + 1] - 8'h37) :
                          (buffer[40 + x*2 + 1] - 8'h30);
        assign SHA1_EXPECTED[(19-x)*8 +: 8] = {high, low};
    end
endgenerate

// ========================================================================
// Blocos de mensagem (512 bits) - REGISTRADOS
// Estrutura: buffer[0..39] (320b) + nonce ASCII + 0x80 + zeros + len(16b)
// ========================================================================
reg [511:0] MESSAGE_BLOCK [0:MAX_CORE-1];

generate
    genvar z;
    for (z = 0; z < MAX_CORE; z = z + 1) begin : msg_block_gen
        localparam integer OFF = z;

        // nb = nonce_bcd_0 + z (offset do core) via ripple decimal simples
        reg [39:0] nb;
        always @(*) begin : bcd_offset
            integer oi;
            reg [4:0] os;
            reg [3:0] ok;
            reg       oc;
            oc = 1'b0;
            for (oi = 0; oi < 10; oi = oi + 1) begin
                if      (oi == 0) ok = OFF % 10;
                else if (oi == 1) ok = (OFF / 10) % 10;
                else              ok = 4'd0;
                os = nonce_bcd_0[oi*4 +: 4] + ok + oc;
                if (os > 5'd9) begin os = os - 5'd10; oc = 1'b1; end
                else                 oc = 1'b0;
                nb[oi*4 +: 4] = os[3:0];
            end
        end

        // Comprimento decimal (digitos sem zeros a esquerda)
        wire [3:0] ln = (nb[35:32] != 0) ? 4'd9 :
                        (nb[31:28] != 0) ? 4'd8 :
                        (nb[27:24] != 0) ? 4'd7 :
                        (nb[23:20] != 0) ? 4'd6 :
                        (nb[19:16] != 0) ? 4'd5 :
                        (nb[15:12] != 0) ? 4'd4 :
                        (nb[11: 8] != 0) ? 4'd3 :
                        (nb[ 7: 4] != 0) ? 4'd2 : 4'd1;
        wire [15:0] mlb = 16'd320 + (ln << 3);             // comprimento em bits

        wire [7:0] d0 = 8'h30 + nb[ 3: 0];
        wire [7:0] d1 = 8'h30 + nb[ 7: 4];
        wire [7:0] d2 = 8'h30 + nb[11: 8];
        wire [7:0] d3 = 8'h30 + nb[15:12];
        wire [7:0] d4 = 8'h30 + nb[19:16];
        wire [7:0] d5 = 8'h30 + nb[23:20];
        wire [7:0] d6 = 8'h30 + nb[27:24];
        wire [7:0] d7 = 8'h30 + nb[31:28];
        wire [7:0] d8 = 8'h30 + nb[35:32];

        reg [191:0] pad;  // nonce ASCII + 0x80 + zeros + comprimento (24 bytes)
        always @(*) begin
            case (ln)
                4'd1: pad = {d0,                                     8'h80, 160'd0, mlb};
                4'd2: pad = {d1,d0,                                  8'h80, 152'd0, mlb};
                4'd3: pad = {d2,d1,d0,                               8'h80, 144'd0, mlb};
                4'd4: pad = {d3,d2,d1,d0,                            8'h80, 136'd0, mlb};
                4'd5: pad = {d4,d3,d2,d1,d0,                         8'h80, 128'd0, mlb};
                4'd6: pad = {d5,d4,d3,d2,d1,d0,                      8'h80, 120'd0, mlb};
                4'd7: pad = {d6,d5,d4,d3,d2,d1,d0,                   8'h80, 112'd0, mlb};
                4'd8: pad = {d7,d6,d5,d4,d3,d2,d1,d0,                8'h80, 104'd0, mlb};
                4'd9: pad = {d8,d7,d6,d5,d4,d3,d2,d1,d0,             8'h80,  96'd0, mlb};
                default: pad = 192'd0;
            endcase
        end

        // Registra o bloco (quebra o caminho combinacional ate o SHA-1)
        always @(posedge clk) begin
            MESSAGE_BLOCK[z] <= {
                buffer[0],  buffer[1],  buffer[2],  buffer[3],
                buffer[4],  buffer[5],  buffer[6],  buffer[7],
                buffer[8],  buffer[9],  buffer[10], buffer[11],
                buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19],
                buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27],
                buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35],
                buffer[36], buffer[37], buffer[38], buffer[39],
                pad
            };
        end
    end
endgenerate

// ========================================================================
// Cores SHA-1
// ========================================================================
wire [159:0] sha1_digest       [0:MAX_CORE-1];
wire         sha1_digest_valid  [0:MAX_CORE-1];
wire         sha1_core_ready    [0:MAX_CORE-1];
reg          sha1_init          [0:MAX_CORE-1];

reg [159:0]  sha1_digest_reg       [0:MAX_CORE-1];

wire sha1_start;
wire uart_tx_done_signal;

reg led_red_output;
reg led_green_output;

reg [2:0] state;
localparam STATE_RESET      = 3'b000;
localparam STATE_IDLE       = 3'b001;
localparam STATE_INIT_SHA1  = 3'b010;
localparam STATE_RUNNING    = 3'b011;  // 1 ciclo p/ init limpar digest_valid do lote anterior
localparam STATE_DONE_WAIT  = 3'b100;
localparam STATE_RESULT     = 3'b101;
localparam STATE_BUILD      = 3'b110;  // aguarda MESSAGE_BLOCK registrar o nonce atual

// UART
wire [7:0] rx_data;
wire       rx_data_valid;
reg        rx_data_ready = 1'b1;

reg [7:0]  tx_data;
reg        tx_data_valid;
wire       tx_data_ready;

assign led_green = ~led_green_output;
assign led_red   = ~led_red_output;

generate
    genvar p;
    for (p = 0; p < MAX_CORE; p = p + 1) begin : sha1_loop
        sha1_core sha1_inst (
            .clk(clk),
            .reset_n(rst_n),
            .init(sha1_init[p]),
            .block(MESSAGE_BLOCK[p]),
            .ready(sha1_core_ready[p]),
            .digest(sha1_digest[p]),
            .digest_valid(sha1_digest_valid[p])
        );
    end
endgenerate

uart_rx #(.CLK_FRE(CLK_FRE), .BAUD_RATE(UART_FRE)) uart_rx_inst (
    .clk(clk), .rst_n(rst_n),
    .rx_data(rx_data), .rx_data_valid(rx_data_valid),
    .rx_data_ready(rx_data_ready), .rx_pin(uart_rx)
);

uart_tx #(.CLK_FRE(CLK_FRE), .BAUD_RATE(UART_FRE)) uart_tx_inst (
    .clk(clk), .rst_n(rst_n),
    .tx_data(tx_data), .tx_data_valid(tx_data_valid),
    .tx_data_ready(tx_data_ready), .tx_pin(uart_tx)
);

// ========================================================================
// Combos de status dos cores
// ========================================================================
wire [MAX_CORE-1:0] digest_valid_array;
wire [MAX_CORE-1:0] ready_array;
wire [MAX_CORE-1:0] match_array;
generate
    genvar v;
    for (v = 0; v < MAX_CORE; v = v + 1) begin : status_check
        assign digest_valid_array[v] = sha1_digest_valid[v];
        assign ready_array[v]        = sha1_core_ready[v];
        assign match_array[v]        = (sha1_digest_reg[v] == SHA1_EXPECTED);
    end
endgenerate

wire all_digest_ready         = &digest_valid_array;
wire all_cores_ready_combined = &ready_array;
wire match_found              = |match_array;

// ========================================================================
// FSM principal (proof-of-work multi-core)
// ========================================================================
always @(posedge clk) begin : sha1_state_machine
    integer q, s, c;

    // Pulso de init (ativo 1 ciclo)
    for (q = 0; q < MAX_CORE; q = q + 1) begin
        sha1_init[q] <= 1'b0;
    end

    case (state)
        STATE_RESET: begin
            led_red_output   <= 1'b0;
            led_green_output <= 1'b0;
            nonce_0     <= 32'd0;
            nonce_bcd_0 <= 40'd0;
            state <= STATE_IDLE;
        end

        STATE_IDLE: begin
            if (uart_tx_done_signal) begin
                nonce_0     <= 32'd0;
                nonce_bcd_0 <= 40'd0;
            end
            if (all_cores_ready_combined && sha1_start) begin
                state <= STATE_BUILD;
            end
        end

        // Espera 1 ciclo para MESSAGE_BLOCK registrar o nonce corrente
        STATE_BUILD: begin
            state <= STATE_INIT_SHA1;
        end

        STATE_INIT_SHA1: begin
            led_red_output <= 1'b1;
            for (s = 0; s < MAX_CORE; s = s + 1) begin
                sha1_init[s] <= 1'b1;
            end
            state <= STATE_RUNNING;
        end

        STATE_RUNNING: begin
            state <= STATE_DONE_WAIT;
        end

        STATE_DONE_WAIT: begin
            if (all_digest_ready) begin
                for (c = 0; c < MAX_CORE; c = c + 1) begin
                    sha1_digest_reg[c] <= sha1_digest[c];
                end
                state <= STATE_RESULT;
            end
        end

        STATE_RESULT: begin
            if (match_found || (nonce_0 >= DIFFICULTY - MAX_CORE)) begin
                led_green_output <= 1'b1;
                led_red_output   <= 1'b0;
                if (all_cores_ready_combined) begin
                    state <= STATE_IDLE;
                end else begin
                    led_green_output <= ~led_green_output;
                end
            end else begin
                led_red_output <= 1'b0;
                if (all_cores_ready_combined) begin
                    if (nonce_0 < DIFFICULTY - MAX_CORE) begin
                        nonce_0     <= nonce_0 + MAX_CORE;
                        nonce_bcd_0 <= nonce_bcd_next;
                    end else begin
                        nonce_0     <= 32'd0;
                        nonce_bcd_0 <= 40'd0;
                    end
                    state <= STATE_BUILD;
                    led_red_output <= ~led_red_output;
                end
            end
        end

        default: state <= STATE_RESET;
    endcase
end

// ========================================================================
// FSM UART (recepcao de 80 bytes / transmissao do nonce de 4 bytes)
// ========================================================================
localparam UART_IDLE           = 2'd0;
localparam UART_BUFFER_FULL    = 2'd1;
localparam UART_TRANSMIT_NONCE = 2'd2;
localparam UART_TX_DONE        = 2'd3;

reg [1:0] uart_state;

assign sha1_start          = (uart_state == UART_BUFFER_FULL);
assign uart_tx_done_signal = (uart_state == UART_TX_DONE);

reg [6:0] byte_count;
reg [4:0] tx_index;

// Indice do core que casou (busca linear, combinacional)
reg [7:0] match_index_reg = 8'd0;
integer   idx_match;
always @(*) begin
    match_index_reg = 0;
    for (idx_match = 0; idx_match < MAX_CORE; idx_match = idx_match + 1) begin
        if (sha1_digest_reg[idx_match] == SHA1_EXPECTED)
            match_index_reg = idx_match;
    end
end

// Detector de borda de novo byte UART
reg rx_valid_reg1;
reg rx_valid_reg2;
wire rx_new_byte = rx_valid_reg1 && !rx_valid_reg2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        uart_state    <= UART_IDLE;
        byte_count    <= 7'd0;
        tx_index      <= 5'd0;
        tx_data       <= 8'd0;
        tx_data_valid <= 1'b0;
        rx_valid_reg1 <= 1'b0;
        rx_valid_reg2 <= 1'b0;
    end else begin
        rx_valid_reg1 <= rx_data_valid;
        rx_valid_reg2 <= rx_valid_reg1;

        case (uart_state)
            UART_IDLE: begin
                tx_data_valid <= 1'b0;
                if (rx_new_byte && byte_count < BUFFER_SIZE) begin
                    buffer[byte_count] <= rx_data;
                    byte_count <= byte_count + 1'b1;
                    if (byte_count == BUFFER_SIZE - 1)
                        uart_state <= UART_BUFFER_FULL;
                end
            end

            UART_BUFFER_FULL: begin
                if ((match_found || (nonce_0 >= DIFFICULTY - MAX_CORE)) && tx_data_ready) begin
                    tx_data       <= nonce[match_index_reg][31:24];  // MSB primeiro
                    tx_data_valid <= 1'b1;
                    tx_index      <= 5'd0;
                    uart_state    <= UART_TRANSMIT_NONCE;
                end
            end

            UART_TRANSMIT_NONCE: begin
                if (tx_data_ready) begin
                    if (tx_index < 5'd3) begin
                        tx_index <= tx_index + 1'b1;
                        case (tx_index + 1'b1)
                            5'd1: tx_data <= nonce[match_index_reg][23:16];
                            5'd2: tx_data <= nonce[match_index_reg][15:8];
                            5'd3: tx_data <= nonce[match_index_reg][7:0];
                            default: tx_data <= 8'd0;
                        endcase
                        tx_data_valid <= 1'b1;
                    end else begin
                        tx_data_valid <= 1'b0;
                        uart_state    <= UART_TX_DONE;
                    end
                end
            end

            UART_TX_DONE: begin
                byte_count <= 7'd0;
                uart_state <= UART_IDLE;
            end
        endcase
    end
end

endmodule
