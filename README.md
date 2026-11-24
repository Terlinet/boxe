# Boxer

Jogo de boxe arcade em primeira pessoa, inspirado nos clássicos do Atari 2600 e controlado por movimentos.

## Como jogar

Na tela inicial, toque em **INICIAR LUTA** e permita o acesso à câmera. Fique de frente para o celular, com o rosto e os braços visíveis:

- Mova a cabeça para um dos lados para desviar do golpe do oponente.
- Estenda rapidamente um dos braços, mantendo o punho na altura do ombro, para socar e ouvir o efeito sonoro do golpe.

A luta usa a câmera frontal e o reconhecimento de pose do Google ML Kit no Android e iOS. Nos navegadores, o rastreamento de pose do MediaPipe reconhece os mesmos movimentos usando a câmera frontal. A arena é vista pelos olhos do jogador, com o oponente à frente e as luvas do jogador no primeiro plano.

No navegador, abra o jogo por HTTPS e permita o acesso à câmera. O primeiro carregamento do modelo de pose requer conexão com a internet.
