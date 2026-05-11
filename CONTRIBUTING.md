# Contribuindo para EBAZ 4205 DuinoCoin Miner

Obrigado por se interessar em contribuir! Este documento fornece diretrizes e instruções.

## Código de Conduta

Esperamos que todos os contribuidores sigam princípios de respeito e profissionalismo:
- Seja respeitoso com outras pessoas
- Aceite crítica construtiva
- Foque no melhor para a comunidade
- Respeite opiniões diferentes

## Como Contribuir

### 1. Reportar Bugs

**Antes de reportar:**
- Verifique se o bug já foi reportado
- Teste com a versão mais recente
- Tente reproduzir de forma isolada

**Ao reportar, inclua:**
```markdown
## Descrição do Bug
Descrição clara e concisa do problema.

## Como Reproduzir
1. Passo 1
2. Passo 2
3. Passo 3

## Comportamento Esperado
O que deveria acontecer

## Comportamento Atual
O que realmente acontece

## Ambiente
- Sistema Operacional: Windows 10 / Ubuntu 20.04 / etc
- Python: 3.8 / 3.9 / 3.10
- Vivado: 2020.2 / 2021.2 / etc
- Placa: EBAZ 4205

## Logs & Erro
```
[Colar output/erro aqui]
```

## Possível Solução
[Se você tiver alguma ideia...]
```

### 2. Sugerir Melhorias

Abra uma issue com a tag `enhancement`:

```markdown
## Descrição
Descrição da melhoria sugerida

## Justificativa
Por que essa melhoria seria útil?

## Solução Proposta
Como você imagina implementar isso?

## Alternativas Consideradas
Quais outras abordagens?

## Contexto Adicional
Qualquer outro detalhe...
```

### 3. Submeter Pull Requests

#### Processo:

1. **Fork o repositório**
   ```bash
   git clone https://github.com/seu-usuario/ebaz4205-duino-miner.git
   cd ebaz4205-duino-miner
   ```

2. **Crie uma branch feature**
   ```bash
   git checkout -b feature/sua-feature-legal
   # ou
   git checkout -b fix/seu-bug-fix
   ```

3. **Faça seus commits**
   ```bash
   git add .
   git commit -m "Descrição clara da mudança"
   ```
   
   **Diretrizes de commit:**
   - Use presente do imperativo ("Add feature" não "Added feature")
   - Primeira linha: máximo 72 caracteres
   - Linha em branco + detalhes se necessário
   - Reference issues: "Fixes #123"
   
   Exemplo:
   ```
   Add 16-core SHA-1 support for FPGA v2
   
   - Doubles throughput via additional parallel cores
   - Requires 1500+ additional LUTs
   - Maintains backward compatibility
   
   Fixes #45
   ```

4. **Push para sua fork**
   ```bash
   git push origin feature/sua-feature-legal
   ```

5. **Abra um Pull Request**
   - Título descritivo
   - Referência a issues relacionadas
   - Descrição detalhada das mudanças
   - Screenshots/logs se aplicável

#### Checklist de PR:

Antes de submeter, certifique-se de:

- [ ] Código segue o style guide do projeto
- [ ] Atualizou documentação relevante
- [ ] Adicionou testes se aplicável
- [ ] Testou em hardware real (se for mudança de HDL)
- [ ] Sem arquivos temporários/compilados
- [ ] Commit history limpo e descritivo
- [ ] Nenhum merge conflict

### 4. Melhorias de Documentação

Documentação é crucial! Você pode:

- Melhorar README.md com exemplos
- Documentar código Verilog com comentários
- Criar tutorials/guides
- Corrigir typos
- Melhorar clarity

---

## Style Guides

### Python

Seguimos **PEP 8** com algumas exceções:

```python
# ✅ BOM
def calculate_hashrate(nonces, time_elapsed):
    """Calculate mining hashrate in H/s."""
    if time_elapsed > 0:
        return nonces / time_elapsed
    return 0

# ❌ RUIM
def calc_hr(n,t):
    if t > 0:
        return n / t

# Variáveis
COM_PORT = "COM20"  # Constantes: UPPER_CASE
mining_key = "abc"  # Variáveis: lower_case

# Strings
print(f"Hash: {value}")  # Use f-strings (Python 3.6+)

# Imports
import serial  # Standard library primeiro
import time
from datetime import datetime

# Depois: third-party
# Depois: local imports
```

**Verificação automática:**
```bash
pip install flake8
flake8 duino_fpga.py
```

### Verilog/SystemVerilog

```verilog
// ========================================
// Module Header
// ========================================
module nonce_bcd_simple (
    input  wire [31:0] nonce,           // Input description
    output wire [3:0]  digit9,          // Output description
    output wire [3:0]  digit_count      // Result
);

// ✅ BOM: Snake_case para nomes, comentários claros
reg [31:0] remainder_d9;
wire [31:0] remainder_d8;

// ❌ RUIM
reg[31:0]r9;  // Sem espaços, nomes obscuros
wir[31:0]r8;

// Sintaxe
always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        // Reset logic
    end else begin
        // Normal logic
    end
end

// Comparações
assign digit = (value >= 32'd100) ? 4'd1 : 4'd0;
```

**Verificação:**
```tcl
# Em Vivado:
check_syntax
```

### Comentários

```verilog
// Use // para comentários de uma linha
/*
  Use /* */ para blocos
  de múltiplas linhas
  quando apropriado
*/

// ✅ Bom: explica PORQUÊ, não O QUÊ
// Incrementa nonce_0 em 8 para proximo ciclo (8 cores processam em paralelo)
nonce_0 <= nonce_0 + 32'd8;

// ❌ Ruim: redundante
// nonce_0 += 8
nonce_0 <= nonce_0 + 32'd8;
```

---

## Testando sua Contribuição

### Testes Python

```bash
# Instalar dependências de test
pip install pytest pytest-cov

# Rodar testes
pytest tests/

# Com cobertura
pytest --cov=duino_fpga tests/
```

### Testes Verilog/HDL

1. **Simulação em Vivado**
   ```tcl
   open_project project_ebaz_miner.xpr
   create_fileset -simset sim_1
   run_simulation
   ```

2. **Verificação de Sintaxe**
   ```tcl
   check_syntax
   ```

3. **Teste em Hardware**
   ```bash
   # Programar FPGA
   vivado -mode batch -source scripts/program.tcl \
     -tclargs design_1_wrapper.bit
   
   # Rodar mining
   python duino_fpga.py
   
   # Monitorar logs
   tail -f error_logs/rejected_shares_*.txt
   ```

---

## Processo de Review

1. **Automated checks** rodam automaticamente:
   - Testes Python
   - Verificação de estilo
   - Build Verilog

2. **Maintainer review**: Um dos maintainers irá:
   - Revisar código
   - Testar em hardware se necessário
   - Solicitar mudanças se preciso
   - Mergear quando aprovado

3. **Turnaround time**: Geralmente 3-7 dias

---

## Desenvolvendo Localmente

### Setup Completo

```bash
# Clone seu fork
git clone https://github.com/seu-usuario/ebaz4205-duino-miner.git
cd ebaz4205-duino-miner

# Crie virtual env (recomendado)
python -m venv venv
source venv/bin/activate  # Linux/Mac
# ou
venv\Scripts\activate  # Windows

# Instale dependências
pip install -r requirements.txt
pip install pytest flake8  # Dev tools

# Abra Vivado para trabalhar em HDL
vivado project_ebaz_miner.xpr &
```

### Workflow Típico

```bash
# Crie branch
git checkout -b feature/meu-recurso

# Edite arquivos
# Testes locais
python duino_fpga.py

# Commit
git add .
git commit -m "Add awesome feature"

# Push
git push origin feature/meu-recurso

# Abra PR no GitHub
# (link aparecerá no push output)
```

---

## Grandes Contribuições

Para mudanças **substanciais**:

1. Abra uma **issue de discussão** primeiro
2. Descreva escopo e abordagem
3. Obtenha feedback antes de trabalhar
4. Assim evitamos rejeições após muito trabalho

Exemplo:
```markdown
## Proposta: Suporte a Stratum Protocol

Gostaria de adicionar suporte para mining em pools via Stratum.

### Escopo
- Implementar cliente Stratum
- Modificar protocolo de comunicação FPGA→PC
- Adicionar fallback automático

### Questões
1. Prioridade em relação a v2?
2. Mantém compatibilidade com mineração direta?
```

---

## Precisa de Ajuda?

- 📖 Leia [README.md](README.md) completo
- 🐛 Verifique [Issues abertas](https://github.com/seu-usuario/ebaz4205-duino-miner/issues)
- 💬 Abra uma [Discussion](https://github.com/seu-usuario/ebaz4205-duino-miner/discussions)
- 📧 Email: seu.email@exemplo.com

---

## Reconhecimento

Todos os contribuidores serão:
- ✅ Creditados no README.md
- ✅ Mencionados no CHANGELOG
- ✅ Agradecidos nas releases

---

Obrigado por contribuir! 🎉
