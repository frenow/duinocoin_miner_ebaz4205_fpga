//======================================================================
// sha1_w_mem.v  (versao simplificada "always-shift")
// -----------------------------------------------------------------
// Memoria/expansao W do SHA-1.
//
// Em vez de manter as 16 palavras estaticas e selecionar W[t] com um
// mux 16:1 controlado por um contador (w_ctr), este design SEMPRE
// desloca a janela e emite a cabeca (w_mem[0]). A palavra recem
// calculada entra no fim (w_mem[15]). Isso produz exatamente a mesma
// sequencia W[0..79], porem:
//   - elimina o contador w_ctr e o mux 16:1 (que estava no caminho
//     critico e consumia ~2000 LUTs / os F7/F8 muxes);
//   - simplifica bastante o codigo.
//
// Recorrencia: W[t] = ROTL1(W[t-3] ^ W[t-8] ^ W[t-14] ^ W[t-16])
// Com a cabeca em W[t-16]: taps = w_mem[0], w_mem[2], w_mem[8], w_mem[13].
//
// Base: Secworks SHA-1 (mantida a compatibilidade de interface).
//======================================================================

`timescale 1ns / 1ps

module sha1_w_mem(
                  input wire           clk,
                  input wire           reset_n,

                  input wire [511 : 0] block,

                  input wire           init,
                  input wire           next,

                  output wire [31 : 0] w
                 );

  reg [31 : 0] w_mem [0 : 15];

  // Saida: sempre a cabeca da janela (tap fixo, sem mux).
  assign w = w_mem[0];

  // Proxima palavra do schedule (entra no fim da janela).
  wire [31 : 0] w_xor = w_mem[13] ^ w_mem[8] ^ w_mem[2] ^ w_mem[0];
  wire [31 : 0] w_new = {w_xor[30 : 0], w_xor[31]};  // ROTL1

  integer i;
  always @ (posedge clk or negedge reset_n)
    begin : reg_update
      if (!reset_n)
        begin
          for (i = 0 ; i < 16 ; i = i + 1)
            w_mem[i] <= 32'h0;
        end
      else if (init)
        begin
          // Carrega as 16 palavras do bloco (big-endian).
          for (i = 0 ; i < 16 ; i = i + 1)
            w_mem[i] <= block[511 - i*32 -: 32];
        end
      else if (next)
        begin
          // Desloca a janela e insere a palavra calculada no fim.
          for (i = 0 ; i < 15 ; i = i + 1)
            w_mem[i] <= w_mem[i+1];
          w_mem[15] <= w_new;
        end
    end

endmodule 
