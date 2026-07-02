# Importações necessárias para o minerador
import hashlib  # Para calcular SHA-1
import os  # Para executar operações do sistema
from socket import socket, SOL_SOCKET, SO_REUSEADDR  # Socket com opções
import sys  # Para argumentos do sistema
import time  # Para temporização e timestamps
import serial
from datetime import datetime  # Para timestamps detalhados nos logs

# Garante saida UTF-8 no console (evita crash com emojis no Windows/cp1252)
try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

# ===== DEFINIÇÕES DE CORES ANSI =====
class Colors:
    """Cores ANSI para terminal"""
    RESET = '\033[0m'
    BOLD = '\033[1m'
    DIM = '\033[2m'
    
    # Cores de Texto
    BLACK = '\033[30m'
    RED = '\033[31m'
    GREEN = '\033[32m'
    YELLOW = '\033[33m'
    BLUE = '\033[34m'
    MAGENTA = '\033[35m'
    CYAN = '\033[36m'
    WHITE = '\033[37m'
    
    # Cores de Fundo
    BG_RED = '\033[41m'
    BG_GREEN = '\033[42m'
    BG_YELLOW = '\033[43m'
    BG_BLUE = '\033[44m'
    BG_MAGENTA = '\033[45m'
    BG_CYAN = '\033[46m'
    
    # Estilos
    SUCCESS = f'{BOLD}{GREEN}'
    ERROR = f'{BOLD}{RED}'
    WARNING = f'{BOLD}{YELLOW}'
    INFO = f'{BOLD}{CYAN}'
    DEBUG = f'{BOLD}{MAGENTA}'

# Configurações
COM_PORT = "COM5"
BAUDRATE = 115200 # Alterado 115200
TIMEOUT = 60
NODE_ADDRESS = '92.246.129.145'  # IP do servidor DuinoCoin
NODE_PORT = 5089  # Porta do servidor (como int, não string)

# Faixa maxima de nonce que o bitstream FPGA varre (= parametro DIFFICULTY no top.v).
# No DuinoCoin o nonce fica em [0, 100*dificuldade]; logo a dificuldade maxima
# solucionavel = FPGA_MAX_NONCE // 100. Ajuste ao reflashar o FPGA.
# Faixa de nonce do bitstream = parametro DIFFICULTY do top.v.
# ATENCAO: 999_999_999 corresponde ao BITSTREAM NOVO (DIFFICULTY=999999999).
# So use este valor DEPOIS de regravar o FPGA. Com o bitstream antigo
# (teto ~100M), volte para 100_000_000 senao havera reconexoes.
FPGA_MAX_NONCE = 999_999_999
MAX_DIFFICULTY = FPGA_MAX_NONCE // 100  # ~10M

# Hashrate MAXIMO reportado a pool. Com o bitstream novo o FPGA resolve a
# dificuldade que a pool pede para ~10 MH/s (~2M), entao reportamos o valor
# REAL (cap alto -> min(real, cap) = real). Assim nao ha subnotificacao e a
# recompensa (Kolka) fica correta.
REPORT_HASHRATE_CAP = 20_000_000  # H/s (folga acima do hashrate real)

# Conexao serial persistente (aberta uma unica vez e reutilizada entre jobs)
ser = None

def get_serial():
    """Abre (ou reutiliza) a conexao serial persistente com o FPGA."""
    global ser
    if ser is not None and ser.is_open:
        return ser
    ser = serial.Serial(COM_PORT, BAUDRATE, timeout=TIMEOUT)
    return ser

def close_serial():
    """Fecha a serial para forcar reabertura/resync na proxima chamada."""
    global ser
    try:
        if ser is not None and ser.is_open:
            ser.close()
    except Exception:
        pass
    ser = None

def send_to_fpga(data):
    """
    Envia 80 bytes para o FPGA e le 4 bytes de nonce (big-endian).

    Reutiliza a porta serial (sem abrir/fechar por job) e limpa o buffer de
    entrada antes de enviar para evitar dessincronizacao com bytes antigos.

    Returns:
        Nonce (int) ou None em timeout/erro.
    """
    try:
        s = get_serial()
        s.reset_input_buffer()  # descarta bytes residuais de jobs anteriores
        s.write(data)
        print(f"{Colors.INFO}📤 [ENVIO]{Colors.RESET} {data.decode('ascii', errors='ignore')} (80 bytes)")

        response = s.read(4)  # bloqueia ate 4 bytes ou timeout
        if len(response) < 4:
            close_serial()    # timeout/parcial -> reabre depois para resincronizar
            return None
        return int.from_bytes(response, byteorder='big')

    except Exception as e:
        print(f"{Colors.ERROR}❌ [ERRO FPGA]{Colors.RESET} {e}")
        close_serial()
        return None

def is_valid_share(message_hash, nonce, expected_hash):
    """
    Validacao local: confere se SHA1(message_hash + str(nonce)) == expected_hash.
    Evita enviar submit incorreto para a pool (protege a reputacao do minerador).
    """
    calc = hashlib.sha1((message_hash + str(nonce)).encode('ascii')).hexdigest()
    return calc == expected_hash.strip().lower()

# ===== ESTATISTICAS DA SESSAO =====
stats_aceitas   = 0    # shares aceitas pela pool (GOOD)
stats_rejeitadas = 0   # shares rejeitadas pela pool (BAD/desconhecida)
stats_invalidas  = 0   # resultados invalidos barrados localmente (nao enviados)
stats_hr_sum = 0.0     # soma de hashrate das shares aceitas (para media)
stats_hr_n   = 0
session_start = None   # definido ao iniciar

def print_session_stats():
    """Imprime o rodape com o resumo acumulado da sessao."""
    total = stats_aceitas + stats_rejeitadas + stats_invalidas
    taxa = (stats_aceitas / total * 100.0) if total else 0.0
    hr_media = (stats_hr_sum / stats_hr_n) if stats_hr_n else 0.0
    up = (time.time() - session_start) if session_start else 0.0
    h, rem = divmod(int(up), 3600)
    m, s = divmod(rem, 60)
    print(f"{Colors.BOLD}{Colors.CYAN}📊 [SESSÃO]{Colors.RESET} "
          f"{Colors.GREEN}✓ {stats_aceitas}{Colors.RESET} | "
          f"{Colors.RED}✗ {stats_rejeitadas}{Colors.RESET} | "
          f"{Colors.YELLOW}⚠ inv {stats_invalidas}{Colors.RESET} | "
          f"Aceitação: {Colors.CYAN}{taxa:.1f}%{Colors.RESET} | "
          f"⚡ Média: {Colors.CYAN}{int(hr_media/1000)}{Colors.RESET} kH/s | "
          f"⏱ {h:02d}:{m:02d}:{s:02d}")

def current_time():
    """Retorna a hora atual formatada como HH:MM:SS"""
    return time.strftime("%H:%M:%S", time.localtime())

def init_error_log():
    """
    Inicializa o arquivo de log para erros de rejeição
    Cria um arquivo com timestamp para cada sessão
    """
    log_dir = "error_logs"
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = os.path.join(log_dir, f"rejected_shares_{timestamp}.txt")
    
    # Cria header do arquivo
    with open(log_file, 'w', encoding='utf-8') as f:
        f.write("="*80 + "\n")
        f.write(f"LOG DE SHARES REJEITADAS - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write("="*80 + "\n\n")
    
    return log_file

def log_rejected_share(log_file, nonce, hashrate, difficulty, message_hash, expected_hash, feedback, timeDifference):
    """
    Registra um share rejeitado no arquivo de log
    
    Args:
        log_file: Caminho do arquivo de log
        nonce: Nonce enviado
        hashrate: Taxa de hashes por segundo
        difficulty: Dificuldade do job
        message_hash: Hash da mensagem
        expected_hash: Hash esperado
        feedback: Resposta do servidor
        timeDifference: Tempo gasto no cálculo
    """
    try:
        with open(log_file, 'a', encoding='utf-8') as f:
            timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
            
            f.write(f"TIMESTAMP: {timestamp}\n")
            f.write(f"STATUS: {'BAD' if feedback[:3] == 'BAD' else 'UNKNOWN'}\n")
            f.write(f"RESPOSTA_SERVIDOR: {feedback}\n")
            f.write("-" * 80 + "\n")
            f.write(f"NONCE: {nonce}\n")
            f.write(f"HASHRATE: {int(hashrate)} H/s ({int(hashrate/1000)} kH/s)\n")
            f.write(f"DIFICULDADE: {difficulty}\n")
            f.write(f"TEMPO_CALCULO: {timeDifference:.4f}s\n")
            f.write("-" * 80 + "\n")
            f.write(f"MESSAGE_HASH: {message_hash}\n")
            f.write(f"EXPECTED_HASH: {expected_hash}\n")
            f.write("=" * 80 + "\n\n")
    except Exception as e:
        print(f"{Colors.ERROR}❌ Erro ao escrever no arquivo de log: {e}{Colors.RESET}")
def create_socket():
    """
    Cria um novo socket com configurações adequadas
    
    Returns:
        socket configurado e pronto para conectar
    """
    try:
        soc = socket()
        # Permite reusar endereço (crucial para reconexões rápidas)
        soc.setsockopt(SOL_SOCKET, SO_REUSEADDR, 1)
        return soc
    except Exception as e:
        print(f"{Colors.ERROR}❌ [ERRO]{Colors.RESET} Falha ao criar socket: {e}")
        return None
def connect_to_server(soc):
    """
    Conecta ao servidor DuinoCoin com tratamento de erros
    
    Args:
        soc: socket objeto
    
    Returns:
        True se conexão bem-sucedida, False caso contrário
    """
    try:
        print(f"{Colors.BOLD}{Colors.CYAN}⛏️  MINERADOR duinoCoin FPGA EBAZ 4205 v1{Colors.RESET} {Colors.YELLOW}by @frenow{Colors.RESET}")
        print(f'{Colors.INFO}🔗 [{current_time()}]{Colors.RESET} Conectando ao servidor {Colors.YELLOW}{NODE_ADDRESS}:{NODE_PORT}{Colors.RESET}...')
        soc.connect((NODE_ADDRESS, NODE_PORT))
        print(f'{Colors.SUCCESS}✓ [{current_time()}]{Colors.RESET} Conexão estabelecida com sucesso')
        return True
    except Exception as e:
        print(f'{Colors.ERROR}✗ [{current_time()}]{Colors.RESET} Falha na conexão: {e}')
        return False
# Configurações do minerador
username = 'frenow'         #altere aqui a sua wallet
mining_key = 'None'

# Inicializa arquivo de log
error_log_file = init_error_log()
print(f'{Colors.INFO}📝 [{current_time()}]{Colors.RESET} Arquivo de log criado: {Colors.YELLOW}{error_log_file}{Colors.RESET}')

# Loop infinito para reconectação automática em caso de falha
attempt = 0
session_start = time.time()
while True:
    attempt += 1
    soc = None
    
    try:
        # Cria novo socket para esta tentativa
        soc = create_socket()
        if soc is None:
            raise Exception("Falha ao criar socket")
        
        # Busca conexão com o servidor DuinoCoin
        if not connect_to_server(soc):
            raise Exception("Não conseguiu conectar ao servidor")
        
        # Recebe versão do servidor
        server_version = soc.recv(100).decode().strip()
        print(f'{Colors.SUCCESS}✓ [{current_time()}]{Colors.RESET} Server Version: {Colors.YELLOW}{server_version}{Colors.RESET}')
        
        # ===== SEÇÃO PRINCIPAL DE MINERAÇÃO =====
        # Loop que permanece enquanto conectado ao servidor
        job_count = 0
        while True:
            job_count += 1
            
            # Solicita novo job (trabalho) ao servidor
            job_request = f"JOB,{username},MEDIUM,{mining_key}"
            soc.send(bytes(job_request, encoding="utf8"))
            
            # Recebe o job do servidor no formato: hash_base,expected_hash,difficulty
            job_data = soc.recv(1024).decode().rstrip("\n")
            print(f'{Colors.INFO}📦 [JOB #{job_count}]{Colors.RESET} Recebido: {Colors.YELLOW}{job_data}{Colors.RESET}')
            
            # Separa os componentes do job
            job_parts = job_data.split(",")
            if len(job_parts) < 3:
                print(f'{Colors.ERROR}✗ [{current_time()}]{Colors.RESET} Formato de job inválido: {job_data}')
                break
            
            message_hash = job_parts[0]      # Hash da mensagem
            expected_hash = job_parts[1]     # Hash esperado
            difficulty = job_parts[2]        # Dificuldade
            
            # IMPORTANTE: o protocolo exige 1 resultado por job. Para abandonar um
            # job sem enviar submit incorreto, e preciso RECONECTAR (break), pois
            # pedir novo JOB sem submeter dessincroniza (servidor: "Incorrect result").
            if int(difficulty) > MAX_DIFFICULTY:  # acima disso o nonce excede a faixa do FPGA
                print(f'{Colors.WARNING}⚠️  [{current_time()}]{Colors.RESET} Dificuldade alta demais p/ o FPGA: {difficulty} (máx: {MAX_DIFFICULTY}) - reconectando')
                break
            
            # Combina mensagem + hash esperado (80 bytes total: 40+40)
            payload = (message_hash + expected_hash).encode('ascii')
            
            if len(payload) != 80:
                print(f'{Colors.ERROR}✗ [{current_time()}]{Colors.RESET} Payload inválido ({len(payload)} bytes, esperado 80)')
                break
            
            print(f'{Colors.DEBUG}⚙️  [MINERANDO]{Colors.RESET} Dificuldade: {Colors.YELLOW}{difficulty}{Colors.RESET}')
            
            # Marca o tempo de início do cálculo de hash
            hashingStartTime = time.time()
            
            # Envia para FPGA e recebe resultado (nonce)
            nonce = send_to_fpga(payload)
            
            if nonce is None:
                print(f'{Colors.ERROR}✗ [{current_time()}]{Colors.RESET} Timeout na FPGA, reconectando')
                break
            
            # Calcula estatísticas
            hashingStopTime = time.time()
            timeDifference = hashingStopTime - hashingStartTime
            hashrate = (nonce / timeDifference) if (nonce > 0 and timeDifference > 0) else 0
            
            # ===== VALIDAÇÃO LOCAL DO HASH (evita submit incorreto na pool) =====
            # Se o FPGA nao encontrou o nonce (ex.: job fora da faixa ou glitch),
            # o hash nao confere -> NAO enviamos nada e reconectamos (abandona o job
            # sem registrar share ruim na pool).
            if not is_valid_share(message_hash, nonce, expected_hash):
                print(f'{Colors.WARNING}⚠️  [{current_time()}]{Colors.RESET} Resultado {Colors.RED}INVÁLIDO{Colors.RESET} '
                      f'(nonce {Colors.YELLOW}{nonce}{Colors.RESET}) — NÃO enviado à pool, reconectando')
                log_rejected_share(error_log_file, nonce, hashrate, difficulty,
                                   message_hash, expected_hash, "LOCAL_INVALID (nao enviado)", timeDifference)
                stats_invalidas += 1
                print_session_stats()
                break
            
            # Envia resultado: nonce,hashrate,software. O hashrate reportado e
            # limitado (REPORT_HASHRATE_CAP) para a pool nao escalar a dificuldade
            # acima do que o FPGA consegue varrer (evita reconexoes constantes).
            reported_hashrate = min(int(hashrate), REPORT_HASHRATE_CAP)
            result_msg = f"{nonce},{reported_hashrate},fpga_ebaz4205_miner"
            soc.send(bytes(result_msg, encoding="utf8"))
            
            # Aguarda feedback do servidor
            feedback = soc.recv(1024).decode().rstrip("\n").upper()
            
            # Se a resposta foi aceita
            if feedback[:4] == "GOOD":
                stats_aceitas += 1
                stats_hr_sum += hashrate
                stats_hr_n   += 1
                print(f'{Colors.SUCCESS}✓ [{current_time()}]{Colors.RESET} Share {Colors.GREEN}ACEITA{Colors.RESET} | '
                      f'💰 Nonce: {Colors.YELLOW}{nonce}{Colors.RESET} | '
                      f'⚡ Hashrate: {Colors.CYAN}{int(hashrate/1000)}{Colors.RESET} kH/s | '
                      f'🎯 Dificuldade: {Colors.YELLOW}{difficulty}{Colors.RESET}')
                
            # Se a resposta foi rejeitada
            elif feedback[:3] == "BAD":
                stats_rejeitadas += 1
                print(f'{Colors.WARNING}⚠️  [{current_time()}]{Colors.ERROR} BAD: {Colors.ERROR}{feedback}{Colors.RESET}')
                print(f'{Colors.ERROR}✗ [{current_time()}]{Colors.RESET} Share {Colors.RED}REJEITADA{Colors.RESET} | '
                      f'💰 Nonce: {Colors.YELLOW}{nonce}{Colors.RESET} | '
                      f'⚡ Hashrate: {Colors.CYAN}{int(hashrate/1000)}{Colors.RESET} kH/s | '
                      f'🎯 Dificuldade: {Colors.YELLOW}{difficulty}{Colors.RESET}')
                # Log do erro
                log_rejected_share(error_log_file, nonce, hashrate, difficulty, message_hash, expected_hash, feedback, timeDifference)
                
            else:
                stats_rejeitadas += 1
                print(f'{Colors.WARNING}⚠️  [{current_time()}]{Colors.ERROR} Resposta desconhecida: {Colors.ERROR}{feedback}{Colors.RESET}')
                print(f'{Colors.ERROR}✗ [{current_time()}]{Colors.RESET} Share {Colors.RED}REJEITADA{Colors.RESET} | '
                      f'💰 Nonce: {Colors.YELLOW}{nonce}{Colors.RESET} | '
                      f'⚡ Hashrate: {Colors.CYAN}{int(hashrate/1000)}{Colors.RESET} kH/s | '
                      f'🎯 Dificuldade: {Colors.YELLOW}{difficulty}{Colors.RESET}')
                # Log do erro
                log_rejected_share(error_log_file, nonce, hashrate, difficulty, message_hash, expected_hash, feedback, timeDifference)

            # Rodape com o resumo acumulado da sessao
            print_session_stats()
    
    # ===== TRATAMENTO DE ERROS =====
    except KeyboardInterrupt:
        print(f'\n{Colors.WARNING}⏹️  [{current_time()}]{Colors.RESET} Mineração interrompida pelo usuário')
        if soc is not None:
            try:
                soc.close()
            except:
                pass
        break  # Sai do loop principal
    
    except Exception as e:
        print(f'{Colors.ERROR}❌ [{current_time()}]{Colors.RESET} ERRO: {str(e)}')
        
        # Fechamento seguro do socket
        if soc is not None:
            try:
                print(f'{Colors.INFO}🔌 [{current_time()}]{Colors.RESET} Fechando socket...')
                soc.close()
                print(f'{Colors.SUCCESS}✓ [{current_time()}]{Colors.RESET} Socket fechado com sucesso')
            except Exception as close_error:
                print(f'{Colors.ERROR}❌ [{current_time()}]{Colors.RESET} Erro ao fechar socket: {close_error}')
        
        # Aguarda antes de reconectar
        print(f'{Colors.WARNING}⚠️  [{current_time()}]{Colors.RESET} Tentativa #{attempt} falhou. Reconectando em 5s...')
        time.sleep(5)

    finally:
        # Garante fechamento do socket em qualquer saida do try (inclusive nos
        # 'break' de reconexao), evitando vazamento de sockets.
        if soc is not None:
            try:
                soc.close()
            except Exception:
                pass
        # NÃO usa os.execl(), apenas continua o loop (mais limpo)