import sys
import time
import serial


SERIAL_PORT = 'COM20'
SERIAL_BAUD = 115200
DELAY_BETWEEN_MESSAGES = 1  # Delay em segundos entre mensagens


def connect_serial():
    """Conecta à porta serial FPGA"""
    try:
        ser = serial.Serial(SERIAL_PORT, SERIAL_BAUD, timeout=1)
        return ser
    except Exception as e:
        print(f'Erro ao conectar na porta {SERIAL_PORT}: {e}')
        sys.exit(1)


def current_time():
    """Retorna o horário atual formatado"""
    return time.strftime("%H:%M:%S", time.localtime())


def send_to_fpga(ser, pmsg):
    """Envia uma mensagem para o FPGA"""
    try:
        msg = f"{pmsg}\n"
        ser.write(msg.encode('utf-8'))
        ser.flush()
        print(f'{current_time()} : Sent to FPGA: {msg.strip()}')
    except Exception as e:
        print(f'{current_time()} : Error sending data: {e}')


def read_from_fpga(ser):
    """Lê resposta do FPGA"""
    try:
        line = ser.readline().decode('utf-8').strip()
        return line
    except Exception as e:
        print(f'{current_time()} : Error reading data: {e}')
        return None


def process_message(ser, message):
    """Processa uma mensagem: envia e recebe resposta"""
    send_to_fpga(ser, message)
    time.sleep(DELAY_BETWEEN_MESSAGES)
    result = read_from_fpga(ser)
    
    if result:
        print(f'{current_time()} : Received from FPGA: {result}')
        print()
    else:
        print(f'{current_time()} : No response received')
        print()


def main():
    """Função principal"""
    # Lista de strings a enviar
    messages = [
        'Emerson Duarte',
        'EBAZ4205',
        'String Reverse',
        'FPGA Test',
        'Hello World',
        'Python UART',
        '12345',
        'test'
    ]
    
    print(f'{current_time()} : ========== Reverse system from FPGA EBAZ4205 ==========')
    print(f'{current_time()} : Conectando na porta {SERIAL_PORT} ({SERIAL_BAUD} baud)...')
    print()
    
    ser = connect_serial()
    print(f'{current_time()} : Conectado com sucesso!')
    print()
    
    try:
        for i, message in enumerate(messages, 1):
            print(f'{current_time()} : [{i}/{len(messages)}]')
            process_message(ser, message)
            
    except KeyboardInterrupt:
        print(f'\n{current_time()} : Execução interrompida pelo usuário')
    except Exception as e:
        print(f'{current_time()} : Erro durante execução: {e}')
    finally:
        ser.close()
        print(f'{current_time()} : Porta serial fechada')
        print(f'{current_time()} : ========== Teste finalizado ==========')


if __name__ == '__main__':
    main()