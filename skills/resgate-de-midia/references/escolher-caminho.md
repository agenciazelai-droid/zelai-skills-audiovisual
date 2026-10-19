# Escolher o caminho: índice, imagem, carving ou reparo

A decisão mais importante de uma recuperação é tomada **antes** de abrir qualquer
ferramenta. Errar aqui custa espaço, tempo e — no caso de câmera 360 — os metadados que
tornam o material utilizável.

## A pergunta que define tudo

> **O índice do sistema de arquivos ainda está lá?**

"Cartão pede para formatar" não responde essa pergunta. O Windows rejeita o volume
inteiro por falhas de validação que não têm relação com a integridade dos dados — um
checksum de 4 bytes inconsistente basta.

Em caso real: cartão de 128 GB de ONE X2 pedindo formatação, com **MBR válida, VBR
principal íntegro, FAT legível, diretório raiz percorrível e bitmap de alocação
coerente**. 112,42 GiB intactos, trancados por **103 bytes** corrompidos num setor.

## O teste de consistência

Ler o índice (operação de leitura pura, custo zero) e comparar dois números obtidos por
caminhos independentes:

| Número | De onde vem |
|---|---|
| soma dos `DataLength` das entradas de diretório | entradas de diretório |
| clusters marcados em uso × bytes por cluster | bitmap de alocação |

**Coincidem** → FAT, bitmap e diretórios concordam. O índice está íntegro: extrair pelo
índice (caminho A).

**Divergem muito ou o VBR não é localizável** → o índice se perdeu: carving (caminho C).

No caso real, os dois deram **112,42 GiB**. Essa coincidência é a prova.

## Árvore de decisão

```
O cartão é reconhecido pelo hardware?
├── NÃO → falha física. Parar. Laboratório.
│         Sinais: nem aparece, aparece com 0 bytes, faz clique.
└── SIM
    │
    Existe VBR exFAT (principal ou o backup no setor 12)?
    ├── NÃO → varrer a assinatura "EXFAT   " no início do dispositivo
    │         ├── achou → seguir com o VBR encontrado
    │         └── não achou → CAMINHO C (carving)
    └── SIM
        │
        A FAT é legível e as cadeias são coerentes?
        ├── NÃO → CAMINHO C (carving)
        └── SIM
            │
            Soma do diretório == bitmap de alocação?
            ├── NÃO → CAMINHO C (carving), ou B se precisar de tentativas
            └── SIM → CAMINHO A (extração pelo índice)  ← o bom
                      │
                      Os arquivos extraídos abrem e decodificam?
                      ├── SIM → pronto. Validar e entregar.
                      └── NÃO → CAMINHO D (reparo de container)
```

## Caminho A — extração pelo índice

**Quando:** índice íntegro (o caso mais comum de "pede para formatar").

Seguir a cadeia de clusters de cada arquivo e gravar byte a byte no destino.

| | |
|---|---|
| Espaço necessário | só o tamanho dos **dados**, não do cartão |
| Preserva | nome, pasta, data, **o arquivo inteiro com trailer de metadados** |
| Escreve no cartão | não |
| Permite retomar | sim |
| Risco | nenhum além de bug no extrator — mitigável validando tamanho e decodificação |

**Nunca pular para carving quando este caminho está disponível.** A diferença é
entregar `.insv` que costura ou `.insv` que abre como dois círculos.

### Otimizações que esse caminho permite

- **Priorizar por papel do arquivo**: masters antes dos proxies. Num caso real, os
  masters eram 95,84 GiB e o total 112,42 GiB — e só os masters caberiam no disco
  disponível (112,26 GiB livres). Os proxies, 16,57 GiB, ficaram de fora e nunca
  fizeram falta.
- **Coalescer clusters contíguos** em leituras grandes. Sem isso, um arquivo de 7 GB
  com cluster de 128 KiB exige 57 mil leituras pequenas.
- **Retomar**: arquivo já completo no destino é pulado, conferindo o tamanho.

## Caminho B — imagem bit-a-bit

**Quando:** haverá tentativas destrutivas repetidas, há setores ilegíveis, ou o caso é
de perícia.

**Quando NÃO:** índice íntegro. Nesse cenário não existe tentativa destrutiva, e a
imagem exige **o dobro da capacidade do cartão** — que é justamente o que costuma
inviabilizar o trabalho.

| | |
|---|---|
| Espaço | tamanho total do cartão, cheio ou vazio |
| Para extrair depois | + o tamanho dos dados |
| Total | ~2× a capacidade |

Diante de erro de leitura, trocar para `ddrescue` ou HDDSuperClone: eles têm estratégia
de releitura e mapa de progresso. Um `dd` simples desiste no primeiro setor ruim.

## Caminho C — carving por assinatura

**Quando:** o índice se perdeu de verdade.

Saber de antemão o que se perde:

| Perda | Consequência |
|---|---|
| nomes e pastas | arquivos saem como `f826880_ftyp.mov` |
| datas | sem ordenação cronológica |
| **trailer de metadados** | `.insv` não costura; XML Sony se desassocia |
| fragmentação | arquivo descontínuo sai cortado no primeiro salto |

**Fato verificado:** o PhotoRec 7.2 **não conhece a assinatura `.insv`** — zero
ocorrências da string no binário. Os vídeos saem como `.mov`/`.mp4` e basta renomear.
Sem saber disso, parece que a varredura não achou nada.

Os números nos nomes que o PhotoRec gera são **offsets no disco**. É isso que permite
remontar fragmentos na ordem correta — ver `seungwoochoe/insta360-footage-recovery`.

## Caminho D — reparo de container

**Quando:** o arquivo saiu inteiro mas não abre, ou abre errado.

Pré-requisito: o arquivo precisa estar **copiado por completo**. Nenhuma ferramenta
desta categoria recupera nada do cartão.

| Sintoma | Ferramenta |
|---|---|
| `.insv` abre como dois círculos, "stitching data lost" | Insta360 File Repair (oficial) |
| "moov atom not found", clipe truncado | `anthwlock/untrunc` + arquivo de referência |
| MP4 Insta360 incompleto | `kichiki/finsta360` |
| metadados perdidos, vídeo bom | `alex-plekhanov/insvtools replace-meta` |
| `.rsv` Sony | recuperação pela câmera, ou serviço de reparo de `.rsv` |

**O arquivo de referência do untrunc é gratuito:** gravar um clipe novo de 30 segundos
com a mesma câmera, no mesmo modo e resolução, **em outro cartão**.

## Caminho E — devolver o cartão ao uso

Separado de tudo acima, porque **escreve no cartão**. Executar somente depois de o
material existir em dois lugares.

Quando o checksum da região de boot for inconsistente e a região de backup estiver
íntegra, o conserto é copiar o setor divergente do backup sobre o principal.

**Provar em memória antes de escrever:** montar a região corrigida, recalcular o
checksum e confirmar que bate com o valor gravado. Só então aplicar. Salvar os 24
setores originais antes, para poder reverter.

No caso real: 512 bytes escritos, cartão voltou a montar como exFAT ReadWrite com os
66 arquivos acessíveis.

## Ordem de operações que não se inverte

1. Diagnóstico de leitura
2. Decisão de caminho
3. Extração
4. Validação
5. Segunda cópia
6. **Só então** qualquer escrita no cartão

Reparar arquivo antes de recuperar estrutura não funciona: não existe arquivo ainda.
Consertar o cartão antes de extrair põe a única cópia em risco por conveniência.
