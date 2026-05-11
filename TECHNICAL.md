# Documentação Técnica - EBAZ 4205 DuinoCoin Miner

Documentação detalhada da arquitetura, protocolos e implementação técnica.

## 📑 Índice

1. [Arquitetura FPGA](#arquitetura-fpga)
2. [Protocolo de Comunicação](#protocolo-de-comunicação)
3. [Algoritmo SHA-1](#algoritmo-sha-1)
4. [Timing & Performance](#timing--performance)
5. [Utilização de Recursos](#utilização-de-recursos)
6. [Fluxo de Dados](#fluxo-de-dados)

---

## Arquitetura FPGA

### Visão Geral Hierárquica

```
┌─────────────────────────────────────────────────────┐
│             Zynq-7010 Processing System             │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │         FPGA Fabric (PL - Programmable)     │  │
│  │                                              │  │
│  │  ┌─────────────────────────────────────┐   │  │
│  │  │      TOP Module (top.v)             │   │  │
│  │  │                                     │   │  │
│  │  │  ┌─────────────┬─────────────────┐ │   │  │
│  │  │  │ UART RX     │  UART TX        │ │   │  │
│  │  │  │ (115200)    │  (115200)       │ │   │  │
│  │  │  └──────┬──────┴────────┬────────┘ │   │  │
│  │  │         │               │          │   │  │
│  │  │  ┌──────▼─────────────────────┐   │   │  │
│  │  │  │  80-Byte Buffer Control    │   │   │  │
│  │  │  │  (Message + Hash Store)    │   │   │  │
│  │  │  └──────┬─────────────────────┘   │   │  │
│  │  │         │                         │   │  │
│  │  │  ┌──────▼──────────────────────┐  │   │  │
│  │  │  │  Message Block Builder     │  │   │  │
│  │  │  │  (Dynamic Padding RFC3174) │  │   │  │
│  │  │  └──────┬────────────────────┘   │   │  │
│  │  │         │                         │   │  │
│  │  │  ┌──────▼──────────────────────┐  │   │  │
│  │  │  │  OCTA SHA-1 Core Array     │  │   │  │
│  │  │  │                            │  │   │  │
│  │  │  │  ┌─────────────────────┐  │  │   │  │
│  │  │  │  │ SHA-1 Core 0       │  │  │   │  │
│  │  │  │  │ (nonce_0)          │  │  │   │  │
│  │  │  │  └─────┬───────────────┘  │  │   │  │
│  │  │  │        │ ... (7 total)    │  │   │  │
│  │  │  │  ┌─────▼───────────────┐  │  │   │  │
│  │  │  │  │ SHA-1 Core 7       │  │  │   │  │
│  │  │  │  │ (nonce_0+7)        │  │  │   │  │
│  │  │  │  └──────────┬─────────┘   │  │   │  │
│  │  │  └─────────────┼────────────┘   │   │  │
│  │  │                │                │   │  │
│  │  │  ┌─────────────▼──────────────┐ │   │  │
│  │  │  │  Nonce Match Detector     │ │   │  │
│  │  │  │  (8x Parallel Comparator) │ │   │  │
│  │  │  │  + Result Encoder         │ │   │  │
│  │  │  └─────────┬──────────────────┘ │   │  │
│  │  │            │                    │   │  │
│  │  │  ┌─────────▼──────────────────┐ │   │  │
│  │  │  │  BCD Converters (8x)       │ │   │  │
│  │  │  │  + ASCII Encoder           │ │   │  │
│  │  │  │  (Nonce to text)           │ │   │  │
│  │  │  └─────────┬──────────────────┘ │   │  │
│  │  │            │                    │   │  │
│  │  │  ┌─────────▼──────────────────┐ │   │  │
│  │  │  │  LED Control & Status      │ │   │  │
│  │  │  │  - Green: Active          │ │   │  │
│  │  │  │  - Red: Match found       │ │   │  │
│  │  │  └────────────────────────────┘ │   │  │
│  │  └────────────────────────────────┘   │  │
│  │                                        │  │
│  └────────────────────────────────────────┘  │
│                                             │
│  Clock: FCLK_CLK0 (50 MHz)                  │
│  Reset: FCLK_RESET0_N (ativo baixo)         │
│                                             │
└─────────────────────────────────────────────┘
```

### Módulos Verilog

#### 1. top.v (1234 linhas)

**Responsabilidades:**
- Orquestração de todos os módulos
- Gerenciamento de buffer UART (80 bytes)
- Construção dinâmica de blocos de mensagem
- Coordenação de 8 cores SHA-1 paralelos
- Comparação e formatação de resultados

**Entradas:**
- `clk` (50 MHz)
- `rst_n` (reset ativo baixo)
- `uart_rx` (serial input)

**Saídas:**
- `uart_tx` (serial output)
- `led_green`, `led_red` (status LEDs)

**Registradores Principais:**
```verilog
reg [7:0] buffer [0:79];        // 80-byte input buffer
reg [31:0] nonce_0;             // Current nonce counter (register)
wire [31:0] nonce_1...7;        // Derived nonces (combinatorial)
wire [159:0] SHA1_EXPECTED;     // Expected hash (160 bits)
reg [511:0] MESSAGE_BLOCK_0..7; // Dynamic message blocks
```

**FSM Principal:**
```
IDLE → RECEIVING_JOB → HASHING → RESULT_ENCODING → TRANSMITTING → IDLE
```

#### 2. sha1_core.v (433 linhas)

**Responsabilidades:**
- Implementação do algoritmo SHA-1 (RFC 3174)
- 80 rodadas de processamento
- Geração de digest (160 bits)

**Portas:**
```verilog
input  [511:0]   block           // Bloco de mensagem (512 bits)
output [159:0]   digest          // Hash resultado (160 bits)
output           digest_valid    // Sinal de conclusão
input            init            // Inicializar novo hash
input            next            // Processar próxima rodada
```

**Constantes SHA-1:**
```verilog
H0 = 0x67452301
H1 = 0xEFCDAB89
H2 = 0x98BADCFE
H3 = 0x10325476
H4 = 0xC3D2E1F0
```

**Pipeline:**
```
Cycle 0-79: Processamento de 80 rodadas
Cycle 80: Finalização e output
Total: ~100 ciclos de clock
@ 50MHz: ~2 µs por hash (teórico)
```

#### 3. nonce_bcd_simple.v (170 linhas)

**Responsabilidades:**
- Conversão de nonce (32-bit) → 9 dígitos BCD
- Determinação automática de comprimento (sem zeros à esq.)
- Otimizado para síntese (totalmente combinatorial)

**Algoritmo:**
```
digit9 = nonce / 100.000.000
remainder = nonce % 100.000.000
digit8 = remainder / 10.000.000
remainder = remainder % 10.000.000
... (repeat for digits 1-7)
digit_count = (digit9≠0)?9 : (digit8≠0)?8 : ... : 1
```

**Exemplo:**
```
Entrada:  nonce = 42587
Saída:    digit5=4, digit4=2, digit3=5, digit2=8, digit1=7
          digit_count = 5
ASCII:    "42587" (5 caracteres)
```

#### 4. uart_rx.v (145 linhas)

**Responsabilidades:**
- Receção de dados série a 115200 baud
- Detecção de rising/falling edge
- Armazenamento de 8 bits por byte

**State Machine:**
```
S_IDLE → S_START → S_REC_BYTE → S_STOP → S_DATA → S_IDLE
         (detect)   (8 bits)   (wait)  (latch) (ready)
```

**Cálculos:**
```
CYCLE = CLK_FRE * 1000000 / BAUD_RATE
      = 50 * 1000000 / 115200
      = 434 ciclos de clock por bit
      ≈ 20 µs por bit
      ≈ 200 µs por byte
      ≈ 16 ms por 80 bytes
```

#### 5. uart_tx.v

**Responsabilidades:**
- Transmissão de dados série (espelhagem de RX)
- Envio de 4 bytes de nonce resultado

---

## Protocolo de Comunicação

### UART Physical Layer

| Parâmetro | Valor |
|-----------|-------|
| Baudrate | 115200 |
| Data Bits | 8 |
| Stop Bits | 1 |
| Parity | None |
| Flow Control | None |
| Timeout (PC) | 60 segundos |

### Handshake de Job

#### Fase 1: Requisição (PC → FPGA via socket)

PC conecta ao servidor DuinoCoin e envia:
```
JOB,frenow,MEDIUM,None
```

**Resposta do Servidor:**
```
8f4e1a2c3d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a,\
f3d2e1c0b9a8765432109876543210abcdef1234,\
MEDIUM
```

#### Fase 2: Envio do Job (PC → FPGA via UART)

PC converte job e envia 80 bytes:

```
Bytes 0-39:   message_hash (40 caracteres ASCII hex)
              = 20 bytes de dados binários em formato ASCII
              Exemplo: "8f4e1a2c3d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a"

Bytes 40-79:  expected_hash (40 caracteres ASCII hex)
              Exemplo: "f3d2e1c0b9a8765432109876543210abcdef1234"

Total: 80 bytes (ASCII puro, sem terminador)
Tempo transmissão: ~16 ms
```

**Exemplo prático:**
```
Enviado:
b'8f4e1a2c3d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9af3d2e1c0b9a8765432109876543210abcdef1234'
```

#### Fase 3: Processamento (FPGA)

1. UART RX recebe 80 bytes em buffer
2. Message builder constrói 512-bit block com padding
3. 8 cores SHA-1 processam nonce_0...nonce_7 simultaneamente
4. Nonce matcher compara resultados com expected_hash
5. Se match encontrado: encoda nonce em ASCII + BCD
6. Transmite 4 bytes resultado via UART TX

```verilog
// Dentro do top.v
always @(posedge clk or negedge rst_n) begin
    if (buffer_complete) begin
        // 1. Decode expected hash (ASCII hex → 160 bits)
        SHA1_EXPECTED <= hex_decode(buffer[40:79]);
        
        // 2. Reset nonce counter
        nonce_0 <= 32'd0;
        
        // 3. Start hashing loop
        for (i=0; i<DIFFICULTY; i=i+8) begin
            // Construct MESSAGE_BLOCK_0..7
            // Compare SHA1_digest_0..7 with SHA1_EXPECTED
            if (match_found) begin
                // Send nonce + break
            end
            nonce_0 <= nonce_0 + 32'd8;
        end
    end
end
```

#### Fase 4: Resposta (FPGA → PC via UART)

Se match encontrado:
```
Bytes 0-3: nonce (32-bit big-endian)
           Exemplo: 0x0000A62B (42587 em decimal)
           
Tempo resposta: < 60 segundos
```

**Exemplo:**
```python
# No PC:
response = ser.read(4)  # Bloqueia até 4 bytes
nonce = int.from_bytes(response, byteorder='big')
print(f"Nonce encontrado: {nonce}")  # Output: 42587
```

Se **TIMEOUT** (nenhum match após 60s):
```
FPGA não responde → PC solicita novo job
```

#### Fase 5: Submissão (PC → Servidor)

```
{nonce},{hashrate},{software_name}
42587,120000,fpga_ebaz4205_miner

Respostas possíveis:
GOOD            # Share aceita
BAD_HASH        # Hash incorreto
BAD_RANGE       # Dificuldade muito alta
```

---

## Algoritmo SHA-1

### Especificação RFC 3174

SHA-1 produz digest de 160 bits (20 bytes) de uma mensagem de tamanho arbitrário.

#### Etapas:

1. **Preprocessing:**
   ```
   1. Append bit '1' ao fim da mensagem
   2. Append bits '0' até comprimento ≡ 56 (mod 64)
   3. Append comprimento original em 64 bits (big-endian)
   4. Quebra resultado em blocos de 512 bits
   ```

2. **Processamento:**
   ```
   Para cada bloco de 512 bits:
   a) Quebra em 16 palavras de 32 bits (W0..W15)
   b) Expande para 80 palavras (W16..W79)
   c) Inicializa A,B,C,D,E com H0..H4
   d) Executa 80 rodadas:
      temp = (A <<< 5) + f(round,B,C,D) + E + W[i] + K[i]
      E = D
      D = C
      C = B <<< 30
      B = A
      A = temp
   e) Adiciona resultado aos hashes
   ```

3. **Output:**
   ```
   H0 | H1 | H2 | H3 | H4 = 160 bits (20 bytes)
   ```

#### Implementação em FPGA:

```verilog
// sha1_core.v - Loop principal
always @(posedge clk) begin
    for (round = 0; round <= 79; round++) begin
        // Funções condicionais
        if (round < 20)
            f = (b & c) | ((~b) & d);
        else if (round < 40)
            f = b ^ c ^ d;
        else if (round < 60)
            f = (b & c) | (b & d) | (c & d);
        else
            f = b ^ c ^ d;
        
        // Seleciona constante K
        case (round)
            0-19:   k = 32'h5a827999;
            20-39:  k = 32'h6ed9eba1;
            40-59:  k = 32'h8f1bbcdc;
            60-79:  k = 32'hca62c1d6;
        endcase
        
        // Calcula T
        t = left_rotate(a, 5) + f + e + w[round] + k;
        
        // Shift valores
        e = d;
        d = c;
        c = left_rotate(b, 30);
        b = a;
        a = t;
    end
end
```

---

## Timing & Performance

### Análise de Latência

```
┌─────────────────────────────────────────────────────┐
│         Fluxo de Tempo de um Job (ms)               │
├─────────────────────────────────────────────────────┤
│                                                     │
│  0 ms:    Job request enviado PC → Servidor        │
│  ~200ms:  Job recebido PC (latência rede)          │
│  200ms:   PC envia 80 bytes → FPGA                 │
│  216ms:   FPGA recebe job completo (80B @ 115200)  │
│  216ms:   FPGA inicia processamento                │
│  ~2ms:    Cada hash SHA-1 (80 rodadas @ 50MHz)     │
│           → Para 8 cores paralelos                 │
│           → ~2ms per 8 nonces                      │
│           → Para dificuldade 100k: ~25 ms          │
│  241ms:   Match encontrado (exemplo: @42587)       │
│  241ms:   FPGA transmite 4 bytes nonce              │
│  245ms:   PC recebe nonce (4B @ 115200)            │
│  245ms:   PC calcula hashrate e submete            │
│  ~450ms:  Resposta servidor recebida               │
│           (latência rede + processamento)           │
│                                                     │
│  Total por ciclo: ~250-500 ms (incluindo latência) │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Throughput Teórico

```
Capacidade de Processamento:

Clock FPGA:           50 MHz
Nonces/ciclo:         8 (OCTA cores)
Rodadas SHA-1:        80
Latência SHA-1:       ~100 ciclos (pipelined)

Throughput = (50 MHz / 100 ciclos) × 8 nonces
           = 500 kH/s por core (teórico)
           × 8 cores
           = 4 MH/s (máximo teórico)

Realístico (com overhead UART):
           ≈ 800 kH/s - 1.2 MH/s
```

### Benchmark Experimental (esperado)

```
Dificuldade: MEDIUM (100k)
Tempo/job:   ~50-100 ms (processamento puro)
Hashrate:    ~1-2 MH/s
Taxa acertos: 1 match a cada 2-3 minutos
Shares/hora: 20-30 shares (com uptime 100%)
```

---

## Utilização de Recursos

### Estimativa de LUT/BRAM (Zynq-7010)

```
┌───────────────────────────────────────────────┐
│  Análise de Recursos (Vivado Synthesis)       │
├───────────────────────────────────────────────┤
│                                               │
│  Disponível: 28.000 LUTs | 560 KB BRAM       │
│                                               │
│  Módulo            LUTs      BRAM      Slices│
│  ────────────────────────────────────────────│
│  sha1_core (×8)    12.000    100 KB    3.000 │
│  nonce_bcd (×8)    800       -         200   │
│  uart_rx/tx        300       -         100   │
│  Message Builder   1.200     -         400   │
│  Top (FSM+ctrl)    800       32 KB     250   │
│  Buffer (80B)      -         10 KB     -     │
│  ────────────────────────────────────────────│
│  TOTAL ESTIM.      ~15.100   ~142 KB   ~3.95K│
│  Utilização:       54%       25%              │
│                                               │
│  Margem restante: 12.900 LUTs para v2.0     │
│                                               │
└───────────────────────────────────────────────┘
```

### Oportunidades de Otimização

1. **Reduzir tamanho do SHA-1**: Compartilhar partes entre cores
2. **Memory-based BCD**: Usar LUT RAM para lookup tables
3. **Pipeline otimizado**: Reduzir latência SHA-1
4. **Área para 16+ cores**: Margem de 45% disponível

---

## Fluxo de Dados

### Macro Fluxo (Visão 30.000 pés)

```
    Servidor DuinoCoin
           │
           │ Job request/response
           ▼
    ┌─────────────────┐
    │  Python Script  │  (duino_fpga.py)
    │  (PC)           │
    └────────┬────────┘
             │ UART (80B job / 4B nonce)
             │
    ┌────────▼────────┐
    │  FPGA (EBAZ)    │
    │  - Processa     │
    │  - Compara      │
    │  - Responde     │
    └─────────────────┘
```

### Micro Fluxo (Dentro da FPGA)

```
         UART_RX (80 bytes)
              │
              ▼
      ┌────────────────────┐
      │  Buffer Shifter    │
      │  (80-byte shift)   │
      └────────┬───────────┘
               │
               ▼
      ┌────────────────────┐
      │  Message Builder   │
      │  (RFC 3174 Padding)│
      └────────┬───────────┘
               │
               ├─► MESSAGE_BLOCK_0
               ├─► MESSAGE_BLOCK_1
               ├─► ...
               └─► MESSAGE_BLOCK_7
                   │
       ┌───────────┴───────────┬───────────┬───────────┬───────────┬───────────┬───────────┐
       │                       │           │           │           │           │           │
       ▼                       ▼           ▼           ▼           ▼           ▼           ▼
    SHA1_0              SHA1_1          SHA1_2      SHA1_3      SHA1_4      SHA1_5      SHA1_6      SHA1_7
   (nonce_0)          (nonce_1)       (nonce_2)   (nonce_3)   (nonce_4)   (nonce_5)   (nonce_6)   (nonce_7)
       │                       │           │           │           │           │           │
       └───────────┬───────────┴───────────┴───────────┴───────────┴───────────┴───────────┘
                   │
                   ▼
        ┌──────────────────────┐
        │  8x Hash Comparator  │
        │  (vs expected_hash)  │
        └──────┬───────────────┘
               │
        ┌──────▼────────┐
        │ Match Found?  │
        └──┬─────────┬──┘
           │         │
           │ NO      │ YES
           │         │
           │   ┌─────▼──────────────┐
           │   │  Nonce Encoder     │
           │   │  (to ASCII + BCD)  │
           │   └─────┬──────────────┘
           │         │
           │    ┌────▼───────┐
           │    │  UART_TX   │
           │    │  (4 bytes) │
           │    └────────────┘
           │
      ┌────▼─────────────────┐
      │  Nonce Counter += 8  │
      │  (próxima iteração)  │
      └──────────────────────┘
```

---

## Detalhes de Implementação

### Message Block Builder (RFC 3174)

```verilog
// Estrutura do bloco SHA-1 (512 bits = 64 bytes)
// ┌─────────────────────────────────────────────────────┐
// │  Bytes 0-39   │ Bytes 40-47             │ 8 últimos  │
// │  Message      │ Nonce (var) + 0x80      │ Compriment │
// │  (40 bytes)   │ + Padding               │ (16 bits)  │
// └─────────────────────────────────────────────────────┘

// Exemplo com nonce=42587 (5 dígitos):
// ┌──────────────────────────────────────────────────┐
// │ message_40bytes │ 42587 │ 0x80 │ 19 zeros│ length│
// └──────────────────────────────────────────────────┘
// │                  │ 5B    │1B   │ 19B    │ 2B    │
```

---

## Verificação de Funcionamento

### Teste 1: UART Loopback

```python
import serial
ser = serial.Serial('COM20', 115200)

# Enviar teste
test_data = b'A' * 80
ser.write(test_data)

# Aguardar resposta
response = ser.read(4, timeout=5)
print(f"Resposta: {response.hex()}")
```

### Teste 2: Hash Conhecido

Usar vetor de teste SHA-1:
```
Entrada:    "abc"
Saída SHA-1: a9993e364706816aba3e25717850c26c9cd0d89d
```

### Teste 3: Mining Real

```bash
python duino_fpga.py
# Aguardar primeiro match em ~1-5 minutos
```

---

## Referências

- [RFC 3174 - US Secure Hash Algorithm 1](https://tools.ietf.org/html/rfc3174)
- [Xilinx Zynq-7010 Datasheet](https://www.xilinx.com/support/)
- [Vivado Design Suite User Guide](https://www.xilinx.com/support/)
- [DuinoCoin Protocol](https://github.com/revoxAE/duino-coin)

---

**Documento Técnico v1.0**
**Atualizado: 11 Maio 2026**
