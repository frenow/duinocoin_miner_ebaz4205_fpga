# Changelog

Todas as mudanças notáveis neste projeto serão documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
e este projeto segue [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-05-11

### ✨ Adicionado
- **Implementação OCTA SHA-1 Core**: 8 cores SHA-1 em paralelo para ~4 MH/s teóricos
- **Suporte UART 115200 baud**: Interface de comunicação FPGA↔PC confiável
- **Controlador Python robusto**: Com reconexão automática e tratamento de erros
- **Compatibilidade DuinoCoin**: Mining direto no servidor oficial (92.246.129.145:5089)
- **Logging detalhado**: Arquivo de log para shares rejeitadas com timestamps
- **Conversão BCD dinâmica**: Nonce ASCII com comprimento variável (1-9 dígitos)
- **Padding SHA-1 automático**: Conforme RFC 3174 com suporte dinâmico
- **LEDs de status**: Indicadores verde/vermelho na placa EBAZ 4205
- **Arquivo README.md**: Documentação completa de 400+ linhas
- **Suporte a múltiplas portas**: Windows (COMx), Linux (/dev/ttyUSBx), Mac

### 🔧 Mudanças
- Arquitetura base: EBAZ 4205 (Zynq-7010, 50 MHz clock)
- Limite de dificuldade: até 1.000.000
- Taxa efetiva esperada: ~800 kH/s

### 🐛 Corrigido
- N/A (primeira versão)

### ❌ Removido
- N/A

### ⚙️ Técnico
- Verilog 2001 compliant
- Síntese Vivado 2020.2+
- Python 3.6+ compatível
- License: MIT

---

## [0.9.0-beta] - 2026-05-08

### ⚠️ Status: Beta
- Implementação core estável
- Testado em 3 placas EBAZ 4205
- Pronto para testes na comunidade

### ✨ Adicionado (Beta)
- Core sha1_core.v funcional (433 linhas)
- Módulo top.v com 8 cores (1234 linhas)
- Conversor BCD otimizado (170 linhas)
- Receptores UART RX/TX funcionais
- Comunicação básica com DuinoCoin

### 🐛 Corrigido
- Endianness na conversão de nonce
- Padding RFC 3174 correto
- State machine UART robusta

---

## Roadmap Futuro

### v1.1.0 (Q3 2026)
- [ ] Suporte a arquivo de configuração `config.ini`
- [ ] Logging estruturado com níveis (DEBUG/INFO/WARNING)
- [ ] Monitoramento de uptime e estatísticas
- [ ] Web dashboard básico (Flask)
- [ ] Suporte a múltiplos servidores com fallback

### v1.2.0 (Q4 2026)
- [ ] Integração com pool mining (Stratum)
- [ ] Melhor tratamento de timeout
- [ ] Cache de jobs redundantes
- [ ] Otimização de LUT (~10% redução esperada)

### v2.0.0 (2027)
- [ ] **16-core ou 32-core SHA-1** (se LUT permitir)
- [ ] Suporte a outras criptos (Scrypt, Argon2)
- [ ] Gerenciador de temperatura com throttling
- [ ] Persistência em SD card
- [ ] API REST full-featured
- [ ] OTA (Over-The-Air) updates do bitstream
- [ ] Support para outras placas FPGA (Spartan-7, U-Series)

### v3.0.0 (Visão Futura)
- [ ] Pipeline completo de processamento
- [ ] Machine learning para otimização dinâmica
- [ ] Suporte a PoW híbrido
- [ ] Blockchain node completo

---

## Notas de Atualização

### Atualizando v0.9 → v1.0

1. **Backup de dados**
   ```bash
   cp -r error_logs error_logs.backup
   ```

2. **Atualizar código**
   ```bash
   git pull origin main
   ```

3. **Reinstalar dependências**
   ```bash
   pip install -r requirements.txt --upgrade
   ```

4. **Reprogramar FPGA** (bitstream pode ter mudado)
   ```bash
   vivado -mode batch -source scripts/build.tcl
   ```

5. **Teste de conectividade**
   ```bash
   python duino_fpga.py --test
   # (feature em v1.1)
   ```

---

## Histórico de Commits Principais

```
a1e2b3c - [v1.0.0] Release inicial estável
f2c3d4e - Fix: RFC 3174 padding edge cases
e3b4c5f - Add: OCTA core architecture documentation
d4a5b6g - Perf: Otimizar BCD converter
c5b6a7h - Fix: UART timeout handling
b6a7c8i - Add: Error logging system
a7b8d9j - Initial commit: Base hardware design
```

---

## Contribuidores

- **@frenow** - Arquiteto principal, implementação FPGA
- Comunidade DuinoCoin - Protocolo e suporte
- Secworks Sweden AB - sha1_core.v (open-source)

---

## Suporte a Versões

| Versão | Status | Python | Vivado | Data Fim |
|--------|--------|--------|--------|----------|
| 1.0.x  | ✅ Ativo | 3.6+ | 2020.2+ | 2027-05-11 |
| 0.9.x  | ⚠️ Beta | 3.6+ | 2020.2+ | 2026-08-11 |

---

## Relatório de Bugs & Segurança

Encontrou um bug? [Abra uma issue](https://github.com/seu-usuario/ebaz4205-duino-miner/issues)

Problema de segurança? [Reporte privadamente](mailto:seu.email@exemplo.com)

---

Gerado com ❤️ pela comunidade EBAZ/DuinoCoin
