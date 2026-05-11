# 🆘 Suporte & FAQ

Respostas rápidas para perguntas frequentes e troubleshooting.

## ❓ Perguntas Frequentes (FAQ)

### P: Como encontro minha porta serial?

**Windows:**
```powershell
Get-PnpDevice -Class Ports | Select-Object Name
# ou
mode
```

**Linux:**
```bash
ls /dev/tty* | grep USB
# ou
dmesg | tail -20
```

**Mac:**
```bash
ls /dev/tty.usb*
```

### P: O FPGA não responde / timeout

**Checklist:**

1. ✅ FPGA programada com bitstream correto?
   ```bash
   vivado -mode batch -source scripts/program.tcl
   ```

2. ✅ Cabo USB conectado corretamente?
   - Verifique se appears em `Get-PnpDevice`

3. ✅ Fonte de alimentação estável?
   - Use fonte 12V/2A+ com proteção
   - Verifique LED power na placa

4. ✅ Taxa baud correta?
   - Padrão: 115200
   - Se conecta mas sem dados: tente 57600

5. ✅ Reset da placa?
   - Desconecte USB por 10 segundos
   - Reconecte

### P: Dificuldade máxima suportada?

**Resposta:** 1.000.000 (1M)

Se receber `BAD_RANGE`:
```python
# Mudar em duino_fpga.py (linha 205):
job_request = f"JOB,{username},EASY,{mining_key}"
# ou MEDIUM (padrão)
```

### P: Como saber se está minerando?

1. **Verifique output Python:**
   ```
   ✓ [12:34:57] Share ACEITA
   ```

2. **Monitore logs:**
   ```bash
   tail -f error_logs/rejected_shares_*.txt
   ```

3. **Veja LEDs:**
   - Verde piscando = mineração ativa
   - Vermelho = match encontrado

4. **Servidor:**
   ```
   Acesse: https://duino-coin.com/mining
   Procure seu usuário: frenow
   ```

### P: Quantos hashes por segundo?

**Teórico:** 4 MH/s
**Realístico:** 800 kH/s - 1.2 MH/s

Depende de:
- Latência UART
- Latência de rede
- Clock FPGA (50 MHz fixo)

### P: Posso minerar múltiplas moedas?

**Atualmente:** Não, apenas DuinoCoin

**Futuro (v2.0):** Sim (Scrypt, Argon2, etc.)

### P: Preciso recompilar o HDL para usar?

**Não!** O bitstream `.bit` já está compilado.

**Recompile apenas se:**
- Modificar `*.v` (Verilog)
- Mudar pinos/constraints
- Adicionar features novas

### P: Qual placa FPGA?

**Atualmente:** EBAZ 4205 (Zynq-7010 only)

**Futuro (v2.0):** Suporte a Spartan-7, Artix-7

---

## 🔧 Troubleshooting Avançado

### Erro: "ModuleNotFoundError: No module named 'serial'"

```bash
pip install pyserial
# ou re-install tudo:
pip install -r requirements.txt
```

### Erro: "Connection refused" (servidor offline?)

```python
# Tente servidor alternativo em duino_fpga.py:
NODE_ADDRESS = '145.239.86.42'
# ou
NODE_ADDRESS = '51.75.34.139'
```

### Erro: "BAD_HASH" frequente

**Possíveis causas:**

1. **Buffer UART corrompido**
   - Verifique cabagem
   - Teste loopback: `python -m serial.tools.miniterm COM20 115200`

2. **Padding incorreto**
   - Valide RFC 3174 em `top.v` linhas 356-393
   - Teste com job simples offline

3. **Endianness errada**
   - SHA-1 usa big-endian
   - Verifique `duino_fpga.py` linha 74

4. **Dificuldade muito alta**
   - Se dificuldade > 1M: reduz para MEDIUM

### Erro: "UART Rate Too Low"

Se bitrate parece lento:

```python
# Tente aumentar timeout em duino_fpga.py:
TIMEOUT = 120  # aumenta de 60 para 120 segundos
```

### Erro: Placa FPGA não encontrada

```bash
# Windows - verificar drivers:
Get-PnpDevice | Select-Object Name | findstr /i xilinx

# Se não aparece: instalar drivers
# Baixe de: https://www.xilinx.com/support/
```

---

## 📊 Diagnostics & Monitoramento

### Test Mode (Futuro v1.1)

```bash
python duino_fpga.py --test
# Executará testes:
# 1. Conexão UART
# 2. UART loopback
# 3. Teste SHA-1 offline
# 4. Conexão servidor
```

### Coletar Logs para Suporte

```bash
# Copiar todos os logs
mkdir suporte_debug
cp -r error_logs suporte_debug/
cp duino_fpga.py suporte_debug/
python duino_fpga.py 2>&1 | tee suporte_debug/run.log

# Comprimir
zip -r suporte_debug.zip suporte_debug/

# Compartilhar no GitHub Issue
```

### Performance Baseline

```bash
# Medir hashrate real (5 minutos)
python duino_fpga.py | head -50
# Procure por "Hashrate: XXX kH/s"
```

---

## 🚨 Erros Críticos

### Erro: Síntese Vivado Falha

```
ERROR: [HDL 8-5825] Syntax error near "..."
```

**Solução:**

1. Verifique sintaxe Verilog
   ```bash
   vivado -mode batch -source scripts/check_syntax.tcl
   ```

2. Limpe projeto
   ```bash
   cd project_ebaz_miner.runs/synth_1
   rm -rf ./*
   ```

3. Tente de novo
   ```bash
   vivado -mode batch -source scripts/build.tcl
   ```

### Erro: Implementação Falha (Place & Route)

```
CRITICAL WARNING: [Place 30-574] Poor placement
```

**Causas:**

- Muito poucas LUTs (se modificar código)
- Constraints incorretos

**Solução:**

```bash
# Limpar implementation
cd project_ebaz_miner.runs/impl_1
rm -rf ./*

# Rerun
vivado -mode batch -source scripts/build.tcl
```

### Erro: Bitstream Inválido

Se `.bit` corrupto ou incompatível:

```bash
# Recompile do zero
vivado -mode batch -source scripts/clean_build.tcl
```

---

## 📞 Contato & Escalation

### Níveis de Suporte

1. **FAQ & Docs** (você está aqui)
   - Problemas comuns resolvidos

2. **GitHub Issues**
   - Bug reports
   - Feature requests
   - Discussões técnicas

3. **Discord/Forum**
   - Chat em tempo real
   - Comunidade FPGA/Duino

4. **Email Direto**
   - Problemas de segurança
   - Issues críticas

### Ao Reportar um Problema

**Inclua:**

```markdown
## Issue
Descrição clara do problema

## Steps to Reproduce
1. Passo 1
2. Passo 2
3. Passo 3

## Esperado
O que deveria acontecer

## Atual
O que realmente acontece

## Logs
```
[Colar output/erro aqui]
```

## Ambiente
- OS: Windows 10 / Ubuntu 20.04 / macOS
- Python: 3.8 / 3.9 / 3.10
- Vivado: 2020.2 / 2021.2
- Placa: EBAZ 4205
```

---

## 💡 Dicas & Truques

### Otimizar Performance

1. **Usar clock mais rápido** (se possível)
   - Modifique `parameter CLK_FRE = 50` em `top.v`
   - Recompile e teste

2. **Reduzir latência UART**
   - Use conversor USB-UART de qualidade (FT232RL preferível)
   - Minimize comprimento do cabo

3. **Cache de jobs**
   - Se tiver múltiplos nonces, envie em lote
   - (Futuro v1.2)

### Economia de Energia

```
EBAZ 4205 consumo:
- Idle:    ~5W
- Mining:  ~15-20W
- Pico:    ~25W

Dica: Coloque ventilador se temp > 60°C
```

### Monitoramento 24/7

```bash
# Script para rodar 24h com auto-restart
#!/bin/bash
while true; do
    python duino_fpga.py
    sleep 5  # Aguarde 5s antes de reconnectar
done
```

---

## 🔐 Segurança

### Credenciais

- **Username:** Sem criptografia necessária (público)
- **Mining key:** Deixe como `None` se não usar
- **Nunca** compartilhe arquivo com password

### Firewall

Se mining não conecta ao servidor:

```bash
# Windows
netsh advfirewall firewall add rule name="EBAZ Mining" \
  dir=out action=allow program=python.exe remoteport=5089 protocol=tcp

# Linux
sudo ufw allow 5089/tcp
```

### Validação de Hash

DuinoCoin valida automaticamente no servidor.
Não precisa validar localmente.

---

## 📚 Recursos Adicionais

- **README.md** - Documentação principal
- **TECHNICAL.md** - Detalhes de implementação
- **CONTRIBUTING.md** - Guia de contribuição
- **CHANGELOG.md** - Histórico de versões

---

## 🎯 Roadmap de Suporte

| Versão | Data | Suporte |
|--------|------|---------|
| 1.0.x  | Agora | ✅ Ativo |
| 1.1.x  | Q3 2026 | 🔜 Em breve |
| 1.2.x  | Q4 2026 | 🔜 Planejado |
| 2.0.x  | 2027 | 🔜 Roadmap |

---

**Última atualização:** 11 Maio 2026
**Versão:** 1.0
**Status:** Ativo ✅
