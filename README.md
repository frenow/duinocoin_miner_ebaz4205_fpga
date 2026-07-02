# ðŸ—ï¸ EBAZ 4205 DuinoCoin FPGA Miner

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Verilog](https://img.shields.io/badge/Verilog-2001-orange.svg)](https://en.wikipedia.org/wiki/Verilog)
[![Python](https://img.shields.io/badge/python-3.x-green.svg)](https://www.python.org/)
[![Status](https://img.shields.io/badge/status-active-brightgreen.svg)](https://github.com)
[![Hashrate](https://img.shields.io/badge/Hashrate-~7.5%2B%20MH%2Fs-brightgreen.svg)](#performance)


### Did you like the project? Leave a star â­ or buy me a coffee ðŸ’°. 
#### DuinoCoin Wallet: frenow 
#### BTC Wallet: bc1qdf5qhmfymltn8xu52grlnskdelz8unsznljwe5

Um minerador de **DuinoCoin** de alto desempenho implementado em FPGA usando a placa **EBAZ 4205** com Zynq-7010. Implementa **mÃºltiplos cores SHA-1 em paralelo** (`MAX_CORE`, atualmente **18** no fonte) para mÃ¡xima eficiÃªncia criptogrÃ¡fica. **Ativo e minerando** com hashrate real na casa de **milhÃµes de hashes por segundo** (â‰ˆ **7,5 MH/s validado com 13 cores**).

> **v2 â€” otimizaÃ§Ãµes aplicadas:** datapath do nonce reescrito (contador binÃ¡rio+BCD incremental, sem multiplicadores/DSP), `MESSAGE_BLOCK` registrado, `sha1_w_mem` simplificado (always-shift, sem o mux 16:1), somador da rodada em DSP (`use_dsp`), e minerador Python com **validaÃ§Ã£o de hash antes do submit**, conexÃ£o serial persistente, estatÃ­sticas de sessÃ£o e controle de dificuldade compatÃ­vel com o FPGA. Veja o [Changelog](#-changelog-v2).

![EBAZ 4205 Board](ebaz4205.jpeg)

---

## ðŸ“‹ Ãndice

- [CaracterÃ­sticas](#caracterÃ­sticas)
- [Hardware](#hardware)
- [Arquitetura](#arquitetura)
- [InstalaÃ§Ã£o](#instalaÃ§Ã£o)
- [ConfiguraÃ§Ã£o](#configuraÃ§Ã£o)
- [Uso](#uso)
- [Estrutura de Arquivos](#estrutura-de-arquivos)
- [Performance](#performance)
- [Troubleshooting](#troubleshooting)
- [Changelog (v2)](#-changelog-v2)
- [Contribuindo](#contribuindo)
- [LicenÃ§a](#licenÃ§a)

---

## ðŸ”§ ImplementaÃ§Ã£o DinÃ¢mica (Generate Blocks)

A implementaÃ§Ã£o utiliza **Verilog `generate` statements** para criar instÃ¢ncias parametrizadas sem hardcoding:

### 1. GeraÃ§Ã£o de Nonces (top.v:70-76)

```verilog
generate
    genvar i;
    for (i = 0; i < MAX_CORE; i = i + 1) begin : nonce_gen
        assign nonce[i] = nonce_0 + i;
    end
endgenerate
```

**Resultado com MAX_CORE=18:**
- `nonce[0] = nonce_0 + 0`
- `nonce[1] = nonce_0 + 1`
- ... atÃ© `nonce[17] = nonce_0 + 17`

### 2. Nonce em BCD incremental (v2 â€” sem multiplicadores)

> **MudanÃ§a v2:** o antigo mÃ³dulo `nonce_bcd_simple.v` (conversÃ£o binÃ¡rioâ†’decimal com
> multiplicadores/DSP) foi **removido do datapath** (o arquivo continua no projeto,
> porÃ©m **Ã³rfÃ£o/nÃ£o instanciado**). Aquela conversÃ£o combinacional criava um caminho
> crÃ­tico de ~77 ns, estourando o clock de 20 ns (50 MHz).

Agora o nonce Ã© mantido **simultaneamente em binÃ¡rio e em BCD** e apenas **incrementado**
`+MAX_CORE` por iteraÃ§Ã£o (soma decimal com ripple simples, barata). Cada core deriva o
seu nonce com um offset pequeno em BCD, sem multiplicadores:

```verilog
// Incremento BCD do nonce base (always @(*), ripple decimal) â€” top.v
reg [39:0] nonce_bcd_next;   // nonce_bcd_0 + MAX_CORE
// Offset por core dentro do generate: nonce_bcd_0 + z
```

- **BinÃ¡rio** (`nonce_0`, 32 bits): usado para transmitir o resultado e comparar dificuldade.
- **BCD** (`nonce_bcd_0`, 40 bits / 10 dÃ­gitos): usado para montar a string ASCII decimal.

### 3. Message Builders REGISTRADOS (v2)

```verilog
generate
    genvar z;
    for (z = 0; z < MAX_CORE; z = z + 1) begin : msg_block_gen
        // ... monta pad (nonce ASCII + 0x80 + zeros + comprimento) ...
        always @(posedge clk) begin
            MESSAGE_BLOCK[z] <= { buffer[0..39], pad };  // 512 bits, REGISTRADO
        end
    end
endgenerate
```

O bloco de 512 bits (padding RFC 3174) agora Ã© **registrado**. A FSM passa por um estado
`STATE_BUILD` para o bloco estabilizar **antes** de disparar o SHA-1, quebrando o caminho
combinacional que estourava o timing.

### 4. SHA-1 Core Instances (v2 â€” sem porta `next`)

```verilog
generate
    genvar p;
    for (p = 0; p < MAX_CORE; p = p + 1) begin : sha1_loop
        sha1_core sha1_inst (
            .clk(clk),
            .reset_n(rst_n),
            .init(sha1_init[p]),           // caminho multi-bloco (next) removido: 1 bloco sÃ³
            .block(MESSAGE_BLOCK[p]),
            .ready(sha1_core_ready[p]),
            .digest(sha1_digest[p]),
            .digest_valid(sha1_digest_valid[p])
        );
    end
endgenerate
```

**Instancia `MAX_CORE` SHA-1 cores** processando em paralelo. Como a mensagem cabe sempre
em **um Ãºnico bloco** de 512 bits, o caminho multi-bloco (`next`/`first_block`) foi removido.

### Como Escalar para Mais Cores

```verilog
// top.v â€” parÃ¢metro no topo do mÃ³dulo
localparam MAX_CORE = 18;  // mude aqui (2, 4, 8, 13, 16, 18, ...)
```

Tudo mais (nonces, BCD, message builders, SHA-1 cores, lÃ³gica de match) Ã© gerado
automaticamente via `generate`. **ApÃ³s alterar, re-sintetize** e verifique LUT/DSP/timing
(o limite prÃ¡tico no Zynq-7010 Ã© definido por LUT e DSP â€” veja [Performance](#-performance)).

---

### Hardware
- âœ… **FPGA Xilinx Zynq-7010** na placa EBAZ 4205
- âœ… **MÃºltiplos SHA-1 Cores em Paralelo** (`MAX_CORE`, atualmente 18)
- âœ… **Interface UART** a 115.200 baud
- âœ… **Processamento de Nonces** de 32 bits (atÃ© 4.2 bilhÃµes)
- âœ… **Faixa de busca (`DIFFICULTY`)** = 999.999.999 â†’ resolve dificuldade de pool atÃ© ~10M
- âœ… **Somador da rodada SHA-1 em DSP** (`use_dsp`) â€” libera LUTs
- âœ… **Timing fechado em 50 MHz** (apÃ³s reescrita do datapath do nonce)
- âœ… **Indicadores LED** de status (verde/vermelho)

### Software (minerador Python)
- âœ… **ValidaÃ§Ã£o de hash local antes do submit** (nÃ£o envia resultado incorreto Ã  pool)
- âœ… **ConexÃ£o serial persistente** (abre a porta 1x e reutiliza)
- âœ… **EstatÃ­sticas de sessÃ£o** (aceitas/rejeitadas/invÃ¡lidas + hashrate mÃ©dio + uptime)
- âœ… **Filtro de dificuldade** compatÃ­vel com a faixa do FPGA
- âœ… **Controle do hashrate reportado** (`REPORT_HASHRATE_CAP`) p/ calibrar dificuldade
- âœ… **ReconexÃ£o automÃ¡tica** e fechamento seguro do socket
- âœ… **SaÃ­da UTF-8 forÃ§ada** (nÃ£o quebra no console do Windows)
- âœ… **Logging detalhado** de shares rejeitadas + cores ANSI

### Protocolo
- âœ… **CompatÃ­vel com DuinoCoin** (protocolo oficial)
- âœ… **Formato de Job**: `MEDIUM` difficulty
- âœ… **Payload**: 80 bytes (40 bytes mensagem + 40 bytes hash esperado)
- âœ… **Resposta**: 4 bytes nonce (32-bit big-endian)
- âœ… **1 resultado por job** (obrigatÃ³rio): jobs insolÃºveis â†’ reconecta (nunca envia submit errado)

---

## ðŸ”§ Hardware

### EspecificaÃ§Ãµes da EBAZ 4205

| Componente | EspecificaÃ§Ã£o |
|-----------|--------------|
| **FPGA** | Xilinx Zynq-7010 |
| **LÃ³gica** | 28.000 LUTs |
| **MemÃ³ria BRAM** | 560 KB |
| **Clock** | 50 MHz (Zynq) |
| **Interface** | UART, GPIO |
| **AlimentaÃ§Ã£o** | 12V DC / 2A (via conector) |
| **DimensÃµes** | ~80x60 mm |

### Pinagem UART

```
UART_RX  â†’ GPIO (entrada serial)
UART_TX  â†’ GPIO (saÃ­da serial)
LED_GRN  â†’ GPIO (LED verde - ativo alto)
LED_RED  â†’ GPIO (LED vermelho - ativo alto)
CLK      â†’ FCLK_CLK0 (50 MHz do Zynq)
RST_N    â†’ FCLK_RESET0_N (reset ativo baixo)
```

### Requisitos de AlimentaÃ§Ã£o

```
TensÃ£o:  12V DC
Corrente: 1-2A (pico atÃ© 3A durante sÃ­ntese)
Tipo:    Fonte chaveada (com proteÃ§Ã£o)
```

---

## ðŸ›ï¸ Arquitetura

### Diagrama de Blocos

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚        Python Controller                â”‚
â”‚  (duino_fpga.py)                        â”‚
â”‚  - Comunica com servidor DuinoCoin      â”‚
â”‚  - Envia jobs via UART                  â”‚
â”‚  - Recebe nonces encontrados            â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
               â”‚ UART 115200 baud
               â”‚ (80 bytes â†’ 4 bytes)
               â–¼
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚     FPGA Top Module (top.v)             â”‚
â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”â”‚
â”‚  â”‚  MAX_CORE SHA-1 Cores em Paralelo  â”‚â”‚
â”‚  â”‚  â”œâ”€ SHA-1 Core 0 (nonce_0)         â”‚â”‚
â”‚  â”‚  â”œâ”€ SHA-1 Core 1 (nonce_0 + 1)     â”‚â”‚
â”‚  â”‚  â”œâ”€ SHA-1 Core 2 (nonce_0 + 2)     â”‚â”‚
â”‚  â”‚  â”œâ”€ ...                             â”‚â”‚
â”‚  â”‚  â””â”€ SHA-1 Core N-1 (nonce_0 + N-1) â”‚â”‚
â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜â”‚
â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”â”‚
â”‚  â”‚  Componentes Suporte                â”‚â”‚
â”‚  â”‚  â”œâ”€ UART RX (recebe jobs)           â”‚â”‚
â”‚  â”‚  â”œâ”€ UART TX (transmite nonces)      â”‚â”‚
â”‚  â”‚  â”œâ”€ Contador nonce binÃ¡rio + BCD    â”‚â”‚
â”‚  â”‚  â””â”€ Message Builder REGISTRADO      â”‚â”‚
â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜â”‚
â”‚                                         â”‚
â”‚  Zynq-7010 Processing System            â”‚
â”‚  â””â”€ Clock: 50 MHz                       â”‚
â”‚  â””â”€ Reset: Ativo baixo                  â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### EstratÃ©gia MULTI-CORE DinÃ¢mica

A implementaÃ§Ã£o utiliza **mÃ³dulos gerados dinamicamente** via `generate` blocks do Verilog:

```verilog
// Em top.v (parÃ¢metro no topo do mÃ³dulo):
localparam MAX_CORE = 18;  // Mude para 2, 4, 8, 13, 16, 18, ...
```

**Processamento em Paralelo (exemplo com MAX_CORE=18):**
```
Lote 0: Processa nonce_0, nonce_0+1, ..., nonce_0+17
Lote 1: Processa nonce_0+18, ..., nonce_0+35
Lote 2: Processa nonce_0+36, ..., nonce_0+53
...

Incremento: nonce_0 += MAX_CORE apÃ³s cada lote (~86 ciclos por lote)
Ganho: ~MAX_CORE vezes mais rÃ¡pido (escalabilidade linear atÃ© o limite de LUT/DSP)
```

**Arquitetura DinÃ¢mica:**
```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚ Nonce Generator (Combinacional)         â”‚
â”‚ â”œâ”€ nonce[0] = nonce_0 + 0               â”‚
â”‚ â”œâ”€ nonce[1] = nonce_0 + 1               â”‚
â”‚ â”œâ”€ nonce[2] = nonce_0 + 2               â”‚ (gerado via loop)
â”‚ â”œâ”€ nonce[...] = nonce_0 + [...]         â”‚
â”‚ â””â”€ nonce[MAX_CORE-1] = nonce_0 + MAX... â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
           â†“ (nonce base em BCD + offset por core)
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚ Nonce BCD (incremental, sem multiplic.) â”‚
â”‚ â”œâ”€ nonce_bcd_0  (registrador base)      â”‚
â”‚ â”œâ”€ +z por core (ripple decimal simples) â”‚ (ASCII = dÃ­gito + 0x30)
â”‚ â””â”€ +MAX_CORE por lote (nonce_bcd_next)  â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
           â†“ (nonces em texto ASCII)
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚ Message Builders REGISTRADOS (MAX_CORE) â”‚
â”‚ â”œâ”€ MESSAGE_BLOCK[0] <= msg + nonce[0].. â”‚
â”‚ â”œâ”€ MESSAGE_BLOCK[1] <= msg + nonce[1].. â”‚ (padding RFC 3174, via STATE_BUILD)
â”‚ â””â”€ MESSAGE_BLOCK[MAX_CORE-1] <= ...     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
           â†“ (512-bit blocks)
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚ SHA-1 Cores (MAX_CORE instÃ¢ncias)       â”‚
â”‚ â”œâ”€ sha1_inst[0] processa nonce[0]       â”‚
â”‚ â”œâ”€ sha1_inst[1] processa nonce[1]       â”‚ (SHA-1 em paralelo)
â”‚ â””â”€ sha1_inst[MAX_CORE-1] processa nonce â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

**Vantagens:**
- âœ… **Escalabilidade via parÃ¢metro**: Mude `MAX_CORE` para 2/4/16/32
- âœ… **GeraÃ§Ã£o automÃ¡tica de cÃ³digo**: Loops `generate` criam instÃ¢ncias
- âœ… **Paralelismo nativo**: LUT-bound, nÃ£o memory-bound
- âœ… **LatÃªncia reduzida**: MAX_CORE comparaÃ§Ãµes simultÃ¢neas
- âœ… **Zero hardcoding**: Toda lÃ³gica Ã© parametrizada

---

## ðŸš€ InstalaÃ§Ã£o

### PrÃ©-requisitos

#### Hardware
- Placa EBAZ 4205
- Fonte de alimentaÃ§Ã£o 12V/2A+
- Conversor USB-UART (FT232RL ou CH340) @ 115200 baud
- Cabo USB-UART ou jumpers de ligaÃ§Ã£o direta

#### Software
- **Python 3.6+**
- **Vivado Design Suite 2020.2+** (para compilar HDL)
- **Xilinx ISE WebPACK** (alternativa)

### Passos de InstalaÃ§Ã£o

#### 1. Clonar RepositÃ³rio

```bash
git clone https://github.com/seu-usuario/ebaz4205-duino-miner.git
cd ebaz4205-duino-miner
```

#### 2. Instalar DependÃªncias Python

```bash
pip install -r requirements.txt
```

**ConteÃºdo de `requirements.txt`:**
```
pyserial>=3.5
```

#### 3. Compilar HDL (Vivado)

```bash
cd project_ebaz_miner
vivado -mode batch -source scripts/build.tcl
```

Ou via GUI:
```bash
vivado project_ebaz_miner.xpr &
```

#### 4. Gerar Bitstream

No Vivado:
```
Flow â†’ Run Synthesis
Flow â†’ Run Implementation  
Flow â†’ Generate Bitstream
```

Arquivo gerado: `project_ebaz_miner.runs/impl_1/design_1_wrapper.bit`

#### 5. Programar FPGA

Via Vivado:
```
Program and Debug â†’ Program Device
Selecione: design_1_wrapper.bit
```

Ou via linha de comando:
```bash
vivado -mode batch -source scripts/program.tcl \
  -tclargs design_1_wrapper.bit
```

#### 6. Verificar ConexÃ£o Serial

```bash
# Windows (PowerShell)
Get-PnpDevice -Class Ports

# Linux/Mac
ls -la /dev/tty*
```

---

## âš™ï¸ ConfiguraÃ§Ã£o

### Arquivo: `duino_fpga.py`

#### VariÃ¡veis Principais

```python
# ============ CONFIGURAÃ‡ÃƒO UART ============
COM_PORT = "COM5"         # Porta serial (altere para sua porta)
BAUDRATE = 115200         # Taxa de transmissÃ£o
TIMEOUT = 60              # Timeout de recepÃ§Ã£o (segundos)

# ========== CONFIGURAÃ‡ÃƒO SERVIDOR ==========
NODE_ADDRESS = '92.246.129.145'  # IP do servidor DuinoCoin
NODE_PORT = 5089                 # Porta do servidor

# ===== LIMITES x CAPACIDADE DO FPGA (v2) =====
# Faixa de nonce que o bitstream varre = parÃ¢metro DIFFICULTY no top.v.
#   - Bitstream NOVO (DIFFICULTY=999999999):  FPGA_MAX_NONCE = 999_999_999
#   - Bitstream antigo (teto ~100M):          FPGA_MAX_NONCE = 100_000_000
FPGA_MAX_NONCE = 999_999_999
MAX_DIFFICULTY = FPGA_MAX_NONCE // 100   # dificuldade de pool mÃ¡x. solucionÃ¡vel

# Hashrate MÃXIMO reportado Ã  pool (ela calibra a dificuldade por este valor).
#   - Bitstream NOVO: use um cap alto (ex.: 20_000_000) p/ reportar o valor REAL.
#   - Bitstream antigo: limite (ex.: 900_000) p/ a dificuldade caber no FPGA.
REPORT_HASHRATE_CAP = 20_000_000

# ========== CREDENCIAIS ==================
username = 'frenow'       # Seu usuÃ¡rio DuinoCoin
mining_key = 'None'       # Mining key (deixar 'None' se nÃ£o usar)
```

> âš ï¸ **CoerÃªncia FPGA â†” script:** `FPGA_MAX_NONCE` deve casar com o `DIFFICULTY`
> gravado no FPGA. Se o script permitir dificuldade maior do que o bitstream
> resolve, o FPGA devolve um nonce invÃ¡lido â€” que a **validaÃ§Ã£o de hash** barra
> (sem enviar Ã  pool), forÃ§ando reconexÃ£o. Veja [Troubleshooting](#-troubleshooting).

#### Como Encontrar Sua Porta Serial

**Windows:**
```powershell
Get-PnpDevice -Class Ports | Select-Object Name,InstanceId
# Procure por "USB" ou "COM"
```

**Linux/Mac:**
```bash
dmesg | tail -20
# ou
ls -la /dev/tty* | grep -i usb
```

#### ConfiguraÃ§Ã£o da Dificuldade

No servidor DuinoCoin, vocÃª pode solicitar dificuldades customizadas modificando:

```python
job_request = f"JOB,{username},MEDIUM,{mining_key}"
# OpÃ§Ãµes: EASY, MEDIUM, HARD
```

**Como o FPGA e a pool interagem (importante):** a pool escala a dificuldade conforme
o **hashrate reportado**. Com o bitstream novo (`DIFFICULTY=999999999`) o FPGA resolve
atÃ© ~10M de dificuldade, entÃ£o basta reportar o hashrate real (`REPORT_HASHRATE_CAP`
alto). Com o bitstream antigo (teto ~100M / dificuldade â‰¤ 1M), Ã© preciso **limitar** o
hashrate reportado para a pool nÃ£o pedir dificuldade acima do que o FPGA alcanÃ§a â€” caso
contrÃ¡rio hÃ¡ reconexÃµes constantes.

---

## ðŸ’» Uso

### ExecuÃ§Ã£o BÃ¡sica

```bash
python duino_fpga.py
```

### Output Esperado

```
â›ï¸  MINERADOR duinoCoin FPGA EBAZ 4205 v1 by @frenow
ðŸ”— [12:34:56] Conectando ao servidor 92.246.129.145:5089...
âœ“ [12:34:57] ConexÃ£o estabelecida com sucesso
âœ“ [12:34:57] Server Version: 3.0
ðŸ“¦ [JOB #1] Recebido: 8f4e...c0a1,f3d2...a5b2,172800
âš™ï¸  [MINERANDO] Dificuldade: 172800
ðŸ“¤ [ENVIO] 8f4e...c0a1f3d2...a5b2 (80 bytes)
âœ“ [12:34:58] Share ACEITA | ðŸ’° Nonce: 9123166 | âš¡ Hashrate: 10361 kH/s | ðŸŽ¯ Dificuldade: 172800
ðŸ“Š [SESSÃƒO] âœ“ 6 | âœ— 0 | âš  inv 0 | AceitaÃ§Ã£o: 100.0% | âš¡ MÃ©dia: 10192 kH/s | â± 00:00:04
```

O rodapÃ© **ðŸ“Š [SESSÃƒO]** mostra: shares aceitas, rejeitadas pela pool, invÃ¡lidas barradas
localmente (nÃ£o enviadas), taxa de aceitaÃ§Ã£o, hashrate mÃ©dio e tempo de sessÃ£o.

### Monitoramento em Tempo Real

```bash
# Em outro terminal, acompanhe logs
tail -f error_logs/rejected_shares_*.txt
```

### Parar MineraÃ§Ã£o

```
Pressione: Ctrl+C
```

Output:
```
â¹ï¸  [12:35:00] MineraÃ§Ã£o interrompida pelo usuÃ¡rio
```

---

## ðŸ“ Estrutura de Arquivos

```
ebaz4205-duino-miner/
â”œâ”€â”€ README.md                           # Este arquivo
â”œâ”€â”€ LICENSE                             # MIT License
â”œâ”€â”€ requirements.txt                    # DependÃªncias Python
â”œâ”€â”€ duino_fpga.py                       # Controller principal
â”œâ”€â”€ send.py                             # Utilidade de envio (deprecated)
â”œâ”€â”€ ebaz4205.jpeg                       # Foto da placa
â”‚
â”œâ”€â”€ project_ebaz_miner.xpr              # Projeto Vivado
â”œâ”€â”€ project_ebaz_miner.srcs/
â”‚   â”œâ”€â”€ sources_1/
â”‚   â”‚   â”œâ”€â”€ new/
â”‚   â”‚   â”‚   â”œâ”€â”€ top.v                   # MÃ³dulo top (~428 linhas)
â”‚   â”‚   â”‚   â”‚   â””â”€â”€ Arquitetura MULTI-CORE parametrizada (MAX_CORE=18)
â”‚   â”‚   â”‚   â”‚   â””â”€â”€ Nonce binÃ¡rio + BCD incremental (sem multiplicadores/DSP)
â”‚   â”‚   â”‚   â”‚   â””â”€â”€ MESSAGE_BLOCK REGISTRADO + estado STATE_BUILD
â”‚   â”‚   â”‚   â”‚   â””â”€â”€ Generate: nonce_gen, msg_block_gen, sha1_loop
â”‚   â”‚   â”‚   â”‚   â””â”€â”€ Buffer UART (80 bytes) + padding RFC 3174
â”‚   â”‚   â”‚   â”‚
â”‚   â”‚   â”‚   â”œâ”€â”€ sha1_core.v             # Core SHA-1 (~403 linhas)
â”‚   â”‚   â”‚   â”‚   â””â”€â”€ 80 rodadas; somador da rodada em DSP (use_dsp)
â”‚   â”‚   â”‚   â”‚   â””â”€â”€ 160-bit digest output; caminho 'next' removido (1 bloco)
â”‚   â”‚   â”‚   â”‚   â””â”€â”€ Ready/digest_valid handshake
â”‚   â”‚   â”‚   â”‚
â”‚   â”‚   â”‚   â”œâ”€â”€ sha1_w_mem.v            # MemÃ³ria W scheduler (~67 linhas, v2)
â”‚   â”‚   â”‚   â”‚   â””â”€â”€ ExpansÃ£o do bloco (80 palavras W)
â”‚   â”‚   â”‚   â”‚   â””â”€â”€ "always-shift" (sem contador w_ctr / sem mux 16:1)
â”‚   â”‚   â”‚   â”‚
â”‚   â”‚   â”‚   â”œâ”€â”€ nonce_bcd_simple.v      # (OBSOLETO/Ã³rfÃ£o â€” 170 linhas)
â”‚   â”‚   â”‚   â”‚   â””â”€â”€ SubstituÃ­do pelo contador BCD inline no top.v
â”‚   â”‚   â”‚   â”‚   â””â”€â”€ Pode ser removido do projeto (Remove File)
â”‚   â”‚   â”‚   â”‚
â”‚   â”‚   â”‚   â”œâ”€â”€ uart_rx.v               # Receptor UART (145 linhas)
â”‚   â”‚   â”‚   â”‚   â””â”€â”€ State machine (IDLEâ†’STARTâ†’RECVâ†’STOP)
â”‚   â”‚   â”‚   â”‚   â””â”€â”€ DetecÃ§Ã£o de baud rate configurÃ¡vel
â”‚   â”‚   â”‚   â”‚
â”‚   â”‚   â”‚   â””â”€â”€ uart_tx.v               # Transmissor UART
â”‚   â”‚   â”‚       â””â”€â”€ Envio de dados sÃ©rie
â”‚   â”‚   â”‚
â”‚   â”‚   â””â”€â”€ bd/
â”‚   â”‚       â””â”€â”€ design_1/               # Block Design Zynq
â”‚   â”‚           â”œâ”€â”€ design_1.bd
â”‚   â”‚           â”œâ”€â”€ design_1_wrapper.v
â”‚   â”‚           â”œâ”€â”€ hdl/
â”‚   â”‚           â”œâ”€â”€ hw_handoff/
â”‚   â”‚           â””â”€â”€ ip/
â”‚   â”‚               â”œâ”€â”€ design_1_processing_system7_0_0/
â”‚   â”‚               â”‚   â””â”€â”€ Zynq PS configuraÃ§Ã£o
â”‚   â”‚               â””â”€â”€ design_1_top_0_0/
â”‚   â”‚                   â””â”€â”€ Top module compilado
â”‚   â”‚
â”‚   â””â”€â”€ constrs_1/
â”‚       â””â”€â”€ new/
â”‚           â””â”€â”€ constr.xdc              # Constraints Vivado
â”‚               â””â”€â”€ Pinagem UART/LED
â”‚               â””â”€â”€ Timing constraints
â”‚
â”œâ”€â”€ project_ebaz_miner.runs/
â”‚   â”œâ”€â”€ impl_1/                         # Implementation output
â”‚   â”‚   â””â”€â”€ design_1_wrapper.bit        # Bitstream final
â”‚   â””â”€â”€ synth_1/                        # Synthesis output
â”‚
â”œâ”€â”€ error_logs/
â”‚   â””â”€â”€ rejected_shares_*.txt           # Logs de erro dinÃ¢micos
â”‚       â””â”€â”€ Registra nonce, hashrate, hashes esperados
â”‚
â””â”€â”€ scripts/ (futuro)
    â”œâ”€â”€ build.tcl                       # Script de build Vivado
    â”œâ”€â”€ program.tcl                     # Script de programaÃ§Ã£o
    â””â”€â”€ setup.sh                        # Setup do ambiente
```

### DescriÃ§Ã£o dos Arquivos Verilog

| Arquivo | Linhas | PropÃ³sito |
|---------|--------|----------|
| `top.v` | ~428 | MÃ³dulo raiz: MULTI-CORE (MAX_CORE=18), nonce binÃ¡rio+BCD, UART, message builder registrado |
| `sha1_core.v` | ~403 | Core SHA-1 (80 rodadas), somador da rodada em DSP - instanciado MAX_CORE vezes |
| `sha1_w_mem.v` | ~67 | ExpansÃ£o de palavras W (schedule) â€” versÃ£o "always-shift" (v2) |
| `nonce_bcd_simple.v` | 170 | **OBSOLETO/Ã³rfÃ£o** â€” datapath BCD agora Ã© inline no top.v |
| `uart_rx.v` | 145 | Receptor UART com state machine |
| `uart_tx.v` | 135 | Transmissor UART sÃ©rie |

---

## ðŸ“Š Performance

### Benchmarks em ProduÃ§Ã£o (v2)

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚  PERFORMANCE REAL - DUINOCOIN NETWORK          â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚  Hashrate Efetivo:  ~7,5 MH/s (13 cores)      â”‚
â”‚  (mediÃ§Ãµes recentes ~10 MH/s por share)        â”‚
â”‚  Timing 50 MHz:     âœ… FECHADO (WNS > 0)       â”‚
â”‚  Status:            âœ… ATIVO E MINERANDO       â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### Modelo de Throughput

```
Throughput â‰ˆ MAX_CORE / (~86 ciclos por lote) Ã— 50 MHz

  MAX_CORE=13  â†’  ~7,5 MH/s   (validado)
  MAX_CORE=18  â†’  ~10,5 MH/s  (alvo â€” requer validaÃ§Ã£o de sÃ­ntese)

Cada lote processa MAX_CORE nonces em paralelo; o SHA-1 (80 rodadas,
1 rodada/ciclo) domina os ~86 ciclos. A 50 MHz o hashrate escala com
MAX_CORE atÃ© o limite de LUT/DSP do FPGA.
```

### UtilizaÃ§Ã£o de Recursos FPGA (build de 13 cores)

| Recurso | UtilizaÃ§Ã£o | DisponÃ­vel | % UtilizaÃ§Ã£o |
|---------|-----------|-----------|---------------|
| **LUT** | 16.440 | 17.600 | **93.4%** ðŸ”´ |
| **FF** | 15.003 | 35.200 | **42.6%** ðŸŸ¢ |
| **DSP** | 80 | 80 | **100%** ðŸ”´ |
| **BRAM** | 0 | 60 | **0%** ðŸŸ¢ |
| **IO** | 5 | 100 | **5.0%** |

**AnÃ¡lise (limites reais):**
- ðŸ”´ **LUT (93%)** e ðŸ”´ **DSP (100%)** sÃ£o os recursos que **limitam** o nÃºmero de cores.
- ðŸŸ¢ **FF (43%)** e ðŸŸ¢ **BRAM (0%)** sobram, mas o SHA-1 nÃ£o mapeia bem neles.
- As otimizaÃ§Ãµes v2 (`sha1_w_mem` always-shift + `use_dsp` sÃ³ no somador da rodada)
  liberam LUT/DSP para caber **mais cores** â€” daÃ­ o alvo de 16â€“18.

### Escalabilidade (`MAX_CORE`)

| MAX_CORE | Throughput aprox. | ObservaÃ§Ã£o |
|----------|-------------------|------------|
| 8  | ~4,6 MH/s | folgado |
| 13 | ~7,5 MH/s | **validado** (LUT 93% / DSP 100%) |
| 16â€“18 | ~9â€“10,5 MH/s | **alvo** apÃ³s otimizaÃ§Ãµes v2 â€” validar LUT/DSP/timing |

**Como testar escalabilidade:**
1. Ajuste `localparam MAX_CORE` no `top.v`.
2. Execute sÃ­ntese + implementaÃ§Ã£o no Vivado.
3. Verifique `*_utilization_placed.rpt` (LUT/DSP < 100%) e o timing (WNS â‰¥ 0).
4. Se estourar LUT/DSP ou faltar timing, reduza `MAX_CORE`.

---

### Fatores que Afetam Performance

1. **Clock FPGA**: 50 MHz fixo (Zynq)
2. **LatÃªncia UART**: 80 bytes Ã— 10 bits / 115200 baud â‰ˆ 7 ms
3. **Overhead de Job**: ReconexÃ£o, parsing, reconversÃ£o
4. **Dificuldade**: Quanto maior, mais nonces para testar

### Como Medir Real

```python
# No duino_fpga.py (linhas 236-253):
hashingStartTime = time.time()
nonce = send_to_fpga(payload)
hashingStopTime = time.time()
timeDifference = hashingStopTime - hashingStartTime

if nonce > 0:
    hashrate = nonce / timeDifference  # Hashes por segundo
```

---

## ðŸ› Troubleshooting

### Problema 1: Porta Serial NÃ£o Encontrada

**Erro:**
```
âŒ [ERRO FPGA] 'COM5' does not exist or access denied
```

**SoluÃ§Ã£o:**
```python
# Listar portas disponÃ­veis
python -c "import serial.tools.list_ports; print([p.device for p in serial.tools.list_ports.comports()])"

# Atualizar duino_fpga.py com a porta correta
COM_PORT = "COM3"  # ou /dev/ttyUSB0 no Linux
```

### Problema 2: Timeout na FPGA

**Erro:**
```
âœ— [12:35:00] Timeout na FPGA, solicitando novo job
```

**Causas & SoluÃ§Ãµes:**
```
a) FPGA nÃ£o programada:
   â†’ Reprograme o bitstream via Vivado
   
b) ConexÃ£o UART ruim:
   â†’ Verifique cabos/conectores
   â†’ Tente taxa menor (57600 baud)
   
c) Fonte de alimentaÃ§Ã£o fraca:
   â†’ Use fonte 12V/2A+ com proteÃ§Ã£o
   â†’ Mina dados de queda de tensÃ£o
   
d) Clock nÃ£o estÃ¡vel:
   â†’ Verifique LED de power da placa
   â†’ Teste com osciloscÃ³pio (50 MHz)
```

### Problema 3: Shares Rejeitadas Frequentemente

**Erro:**
```
âš ï¸  [12:35:00] BAD: BAD_HASH
```

**Nota v2:** o minerador agora **valida o hash localmente antes de enviar**
(`is_valid_share`), entÃ£o resultados incorretos **nÃ£o chegam mais Ã  pool** â€” em vez
de `BAD`, vocÃª verÃ¡ `âš  INVÃLIDO â€” NÃƒO enviado Ã  pool, reconectando`.

**Causas & SoluÃ§Ãµes:**
```
a) Dificuldade acima da capacidade do FPGA (causa mais comum):
   â†’ nonce excede FPGA_MAX_NONCE â†’ hash nÃ£o confere â†’ reconecta
   â†’ Ajuste FPGA_MAX_NONCE/REPORT_HASHRATE_CAP (ver Problema 6) ou regrave o FPGA

b) Padding de mensagem incorreto:
   â†’ Valide o padding RFC 3174 no top.v (bloco msg_block_gen)

c) Endianness / buffer:
   â†’ SHA-1 usa big-endian; valide os 80 bytes recebidos via UART
```

### Problema 4: ConexÃ£o Recusada ao Servidor

**Erro:**
```
âœ— [12:35:00] Falha na conexÃ£o: [Errno 111] Connection refused
```

**SoluÃ§Ãµes:**
```bash
# Verificar conectividade
ping 92.246.129.145

# Testar porta
nc -zv 92.246.129.145 5089

# PossÃ­vel servidor offline:
# Tente outro servidor DuinoCoin:
NODE_ADDRESS = '145.239.86.42'  # Alternativo
NODE_PORT = 5089
```

### Problema 5: Python ImportError

**Erro:**
```
ModuleNotFoundError: No module named 'serial'
```

**SoluÃ§Ã£o:**
```bash
pip install pyserial
# ou
pip install -r requirements.txt
```

### Problema 6: MineraÃ§Ã£o Reinicia/Reconecta Constantemente

**Sintoma:**
```
âš ï¸  Dificuldade alta demais p/ o FPGA: 1982120 (mÃ¡x: 1000000) - reconectando
... (reconecta, comeÃ§a do zero, repete) ...
```

**Causa:** a pool **escala a dificuldade conforme o hashrate reportado**. Se o valor
reportado for alto demais para o que o bitstream resolve, a pool pede uma dificuldade
cujo nonce excede a faixa do FPGA â†’ o job Ã© insolÃºvel â†’ reconexÃ£o a cada ciclo.

**SoluÃ§Ãµes:**
```
a) Regravar o FPGA com DIFFICULTY=999999999 (recomendado):
   â†’ FPGA_MAX_NONCE   = 999_999_999
   â†’ REPORT_HASHRATE_CAP = 20_000_000   # reporta o hashrate REAL
   â†’ A pool passa a atribuir dificuldade solucionÃ¡vel; estabiliza sem reconectar

b) Sem regravar (bitstream antigo, teto ~100M):
   â†’ FPGA_MAX_NONCE   = 100_000_000
   â†’ REPORT_HASHRATE_CAP = 900_000      # limita o hashrate reportado
   â†’ A pool mantÃ©m a dificuldade dentro da faixa do FPGA (estÃ¡vel),
     porÃ©m com subnotificaÃ§Ã£o de hashrate (menor recompensa por share)
```

> A opÃ§Ã£o (a) Ã© a Ãºnica que reporta o hashrate verdadeiro **e** mantÃ©m a mineraÃ§Ã£o estÃ¡vel.

---

## ðŸ”¬ Desenvolvimento & Testing

### Testar Escalabilidade com Diferentes MAX_CORE

**Passo 1: Alterar parametrizaÃ§Ã£o**

```verilog
// Editar project_ebaz_miner.srcs/sources_1/new/top.v

// ParÃ¢metro no topo do mÃ³dulo:
localparam MAX_CORE = 13;  // ajuste e re-sintetize (8, 13, 16, 18, ...)

// Verificar LUT/DSP/timing apÃ³s cada sÃ­ntese
```

**Passo 2: Compilar e verificar**

```bash
vivado -mode batch -source scripts/build.tcl

# UtilizaÃ§Ã£o (LUT/DSP) e timing
grep -E "Slice LUTs|DSPs" project_ebaz_miner.runs/impl_1/*utilization_placed.rpt
grep -E "All user|violated|WNS"  project_ebaz_miner.runs/impl_1/*timing_summary_routed.rpt
```

**Passo 3: Escalabilidade real (v2, apÃ³s otimizaÃ§Ãµes)**

| MAX_CORE | LUT% | DSP% | Timing 50 MHz | ViÃ¡vel? |
|----------|------|------|---------------|---------|
| 8  | ~60% | ~65% | âœ… | âœ… |
| 13 | 93%  | 100% | âœ… (WNS>0) | âœ… **validado** |
| 16â€“18 | a validar | a validar | a validar | ðŸŽ¯ alvo |

**ConclusÃ£o:** os limites reais no Zynq-7010 sÃ£o **LUT e DSP** (nÃ£o FF/BRAM). Com as
otimizaÃ§Ãµes v2, 13 cores fecham em 50 MHz; 16â€“18 Ã© o alvo a validar por sÃ­ntese.

### Testar MÃ³dulo SHA-1 Isolado

```verilog
// test_sha1_core.v
module test_sha1;
  // ...
  // Teste com vetor conhecido
  // Entrada: "abc" (0x61626380...)
  // SaÃ­da SHA-1: a9993e364706816aba3e25717850c26c9cd0d89d
endmodule
```

### Testar UART Loopback

```bash
# Conectar TX â†’ RX (loop)
python -c "
import serial
ser = serial.Serial('COM5', 115200)
ser.write(b'TEST' * 20)  # 80 bytes
response = ser.read(4)
print(f'Response: {response.hex()}')
"
```

### Simular Job Offline

```python
# Criar job conhecido
message_hash = "8f4e" + "0" * 36  # 40 chars
expected_hash = "f3d2" + "0" * 36  # 40 chars
payload = (message_hash + expected_hash).encode('ascii')
assert len(payload) == 80
print(f"Payload vÃ¡lido: {len(payload)} bytes")
```

---

## ðŸ“ Changelog (v2)

### Hardware (Verilog)
- âœ… **Datapath do nonce reescrito:** contador **binÃ¡rio + BCD incremental** (`+MAX_CORE`
  por lote, ripple decimal). Removeu os multiplicadores/DSP e o caminho crÃ­tico de ~77 ns
  que **estourava o timing** de 50 MHz. `nonce_bcd_simple.v` ficou obsoleto.
- âœ… **`MESSAGE_BLOCK` registrado** + estado **`STATE_BUILD`** (bloco estÃ¡vel antes do `init`).
- âœ… **`sha1_w_mem` "always-shift":** removidos o contador `w_ctr` e o **mux 16:1** (que
  estava no caminho crÃ­tico e gastava ~2000 LUTs). MÃ³dulo caiu de ~260 â†’ ~67 linhas.
- âœ… **`use_dsp` no somador da rodada** (`a_reg`) â€” libera LUTs; somadores do digest em LUT.
- âœ… **Limpeza:** caminho multi-bloco (`next`/`first_block`) removido; funÃ§Ãµes `bcd_add`/
  `bcd_len` inlinadas; `sha1_digest_valid_reg[]` removido.
- âœ… **`DIFFICULTY` = 999.999.999** (faixa de nonce ~1G â†’ resolve dificuldade de pool atÃ© ~10M).
- âœ… **Timing 50 MHz fechado** (WNS > 0) e **`MAX_CORE` elevado** (13 validado; 16â€“18 alvo).

### Software (duino_fpga.py)
- âœ… **ValidaÃ§Ã£o de hash local antes do submit** (`is_valid_share`) â€” nunca envia resultado incorreto.
- âœ… **ConexÃ£o serial persistente** (sem abrir/fechar por job) + `reset_input_buffer()`.
- âœ… **EstatÃ­sticas de sessÃ£o** (aceitas/rejeitadas/invÃ¡lidas, taxa, hashrate mÃ©dio, uptime).
- âœ… **Filtro de dificuldade** (`MAX_DIFFICULTY`) e **cap de hashrate** (`REPORT_HASHRATE_CAP`).
- âœ… **ReconexÃ£o limpa** (1 resultado por job; job insolÃºvel â†’ reconecta) + `finally` fecha socket.
- âœ… **SaÃ­da UTF-8 forÃ§ada** (corrige crash de emoji no console do Windows).

---

## ðŸš€ PrÃ³ximas Melhorias

### Core Architecture
- [ ] **Validar e fixar `MAX_CORE`** mÃ¡ximo (16â€“18) com sÃ­ntese/timing no hardware
- [ ] **Pipeline SHA-1** (limitado pelos FF do 7z010 â€” ver anÃ¡lise) 
- [ ] **Suporte a SHA-256** (novo algoritmo, parametrizÃ¡vel)

### Software & Connectivity
- [ ] **Suporte a mÃºltiplos servidores** com failover automÃ¡tico
- [ ] **Pool mining direto** (Stratum protocol)
- [ ] **Dashboard Web** em tempo real
- [ ] **Log persistente** em cartÃ£o SD

### Hardware Features
- [ ] **Monitoramento de temperatura** (sensor DS18B20)
- [ ] **OTA (Over-The-Air) updates** via Zynq
- [ ] **Controle de clock dinÃ¢mico** (DVFS - Dynamic Voltage and Frequency Scaling)

### Experimental
- [ ] **Suporte a outras criptos** (Scrypt, Ethash, etc.)
- [ ] **Machine Learning inference** em cores ociosos

---

## ðŸ“– Guia de CÃ³digo-Fonte

### top.v - MÃ³dulo Principal (~428 linhas, v2)

**Estrutura (por blocos, nÃ£o por linha fixa):**

```
CabeÃ§alho/params:   CLK_FRE, UART_FRE, DIFFICULTY=999999999, MAX_CORE=18
Nonce:              nonce_0 (binÃ¡rio) + nonce_bcd_0 (BCD) + nonce_bcd_next (incremento)
Decode hash:        buffer[40..79] â†’ SHA1_EXPECTED (160 bits)
Message builder:    generate msg_block_gen â†’ MESSAGE_BLOCK[z] REGISTRADO (padding RFC 3174)
SHA-1 cores:        generate sha1_loop â†’ MAX_CORE instÃ¢ncias
Combinacional:      all_digest_ready, all_cores_ready, match_found, match_index
FSM SHA-1:          RESET â†’ IDLE â†’ BUILD â†’ INIT_SHA1 â†’ RUNNING â†’ DONE_WAIT â†’ RESULT
FSM UART:           IDLE â†’ BUFFER_FULL â†’ TRANSMIT_NONCE â†’ TX_DONE
```

**SeÃ§Ãµes DinÃ¢micas (Generate Loops):**

| Genvar | Loop | InstÃ¢ncias | PropÃ³sito |
|--------|------|-----------|----------|
| i | nonce_gen | MAX_CORE | Nonce binÃ¡rio derivado (`nonce_0 + i`) |
| x | hex_decode | 20 | Decodifica hash esperado (ASCII hex â†’ binÃ¡rio) |
| z | msg_block_gen | MAX_CORE | Nonce BCD (+z), ASCII e MESSAGE_BLOCK registrado |
| p | sha1_loop | MAX_CORE | SHA-1 cores |
| v | status_check | MAX_CORE | Flags ready/digest_valid/match |

**Arrays DinÃ¢micos (dimensÃ£o [0:MAX_CORE-1]):**

```verilog
wire [31:0]  nonce [0:MAX_CORE-1]         // Nonces binÃ¡rios derivados
reg  [511:0] MESSAGE_BLOCK [0:MAX_CORE-1] // Blocos SHA-1 (REGISTRADOS)
wire [159:0] sha1_digest [0:MAX_CORE-1]   // Resumos SHA-1
wire         sha1_digest_valid [0:MAX_CORE-1]
reg  [159:0] sha1_digest_reg [0:MAX_CORE-1]
```
> Removidos na v2: `digit9..digit1[]`, `nonce_ascii[]`, `nonce_ascii_len[]`,
> `sha1_next[]`, `sha1_digest_valid_reg[]` (nÃ£o mais necessÃ¡rios).

**State Machines:**
1. **SHA-1:** RESET â†’ IDLE â†’ **BUILD** â†’ INIT_SHA1 â†’ RUNNING â†’ DONE_WAIT â†’ RESULT
   (`BUILD` registra o MESSAGE_BLOCK do nonce atual; `RUNNING` dÃ¡ 1 ciclo para o
   `init` limpar o `digest_valid` do lote anterior)
2. **UART:** IDLE â†’ BUFFER_FULL â†’ TRANSMIT_NONCE â†’ TX_DONE

### Outros MÃ³dulos

- **sha1_core.v** (~403 linhas): Core SHA-1 (80 rodadas); somador da rodada em DSP (`use_dsp`); caminho multi-bloco removido
- **sha1_w_mem.v** (~67 linhas): expansÃ£o W "always-shift" (sem contador/mux 16:1)
- **nonce_bcd_simple.v** (170 linhas): **obsoleto/Ã³rfÃ£o** (substituÃ­do pelo BCD inline)
- **uart_rx.v** (145 linhas): Receptor UART com state machine
- **uart_tx.v** (135 linhas): Transmissor UART sÃ©rie

---

## ðŸ“š ReferÃªncias

- [DuinoCoin Official](https://github.com/revoxAE/duino-coin)
- [Xilinx Zynq-7010 Datasheet](https://www.xilinx.com/support/)
- [SHA-1 RFC 3174](https://tools.ietf.org/html/rfc3174)
- [Verilog 2001 Standard](https://en.wikipedia.org/wiki/Verilog)
- [EBAZ 4205 Resources](https://www.ebazresources.com/)

---

## ðŸ¤ Contribuindo

ContribuiÃ§Ãµes sÃ£o bem-vindas! Por favor:

1. **Fork** o projeto
2. **Crie uma branch** (`git checkout -b feature/AmazingFeature`)
3. **Commit** suas mudanÃ§as (`git commit -m 'Add AmazingFeature'`)
4. **Push** para a branch (`git push origin feature/AmazingFeature`)
5. **Abra um Pull Request**

### Linhas Diretrizes

- Mantenha compatibilidade com Python 3.6+
- Documente mudanÃ§as em Verilog com comentÃ¡rios
- Teste em hardware real antes de PR
- Siga padrÃ£o de naming: `snake_case` (Python), `lower_case` (Verilog)

---

## ðŸ“ LicenÃ§a

Este projeto estÃ¡ licenciado sob a **MIT License** - veja arquivo [LICENSE](LICENSE) para detalhes.

**Resumo:**
- âœ… Uso comercial
- âœ… ModificaÃ§Ã£o
- âœ… DistribuiÃ§Ã£o
- âŒ Responsabilidade limitada
- âŒ Sem garantia

---

## ðŸ“§ Contato & Suporte

- **Autor**: @frenow
- **Issues**: [GitHub Issues](https://github.com/seu-usuario/ebaz4205-duino-miner/issues)
- **Discussions**: [GitHub Discussions](https://github.com/seu-usuario/ebaz4205-duino-miner/discussions)
- **Email**: seu.email@exemplo.com

---

## ðŸ™ Agradecimentos

- **Xilinx** por Vivado e Zynq
- **Secworks Sweden AB** por sha1_core.v open-source
- **DuinoCoin Community** pelo protocolo e suporte
- **EBAZ Community** pelos recursos e documentaÃ§Ã£o

---

## âš¡ Quick Start (TL;DR)

```bash
# 1. Clonar
git clone https://github.com/seu-usuario/ebaz4205-duino-miner.git && cd ebaz4205-duino-miner

# 2. Instalar
pip install -r requirements.txt

# 3. Configurar porta serial
nano duino_fpga.py  # Altere COM_PORT para sua porta

# 4. Programar FPGA
vivado -mode batch -source scripts/build.tcl

# 5. Minerar!
python duino_fpga.py
```

---

**Feliz mineraÃ§Ã£o! â›ï¸ðŸ’°**

*Ãšltima atualizaÃ§Ã£o: 02 Julho 2026*
*VersÃ£o: 2.0 (datapath do nonce reescrito, w_mem always-shift, use_dsp, validaÃ§Ã£o de hash + estatÃ­sticas no minerador)*

