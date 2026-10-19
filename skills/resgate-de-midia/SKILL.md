---
name: resgate-de-midia
description: >
  Resgata vídeo e foto de cartão de memória corrompido de câmera (Insta360 linha X,
  Sony XAVC/XDCAM, GoPro, DSLR) sem destruir os metadados que o material precisa para
  ser usado. Conduz uma triagem antes de tocar no cartão, identifica a marca e a geração
  da câmera pela própria estrutura do cartão, confere espaço no destino, e extrai do
  cartão para um diretório escolhido pelo usuário sem nunca escrever na origem.
  Cobre cartão que pede formatação, cartão RAW, arquivo .insv que não abre, vídeo
  truncado sem moov atom, clipe que aparece como dois círculos de peixe-olho, extração
  interrompida e arquivos .rsv da Sony. Esta skill deve ser usada sempre que o usuário
  mencionar "cartão corrompido", "cartão pede para formatar", "cartão RAW", "perdi os
  vídeos", "perdi a filmagem", "o cartão não abre", "o cartão sumiu com os arquivos",
  "arquivo .insv não abre", "insv corrompido", "vídeo corrompido", "vídeo não abre",
  "stitching data lost", "moov atom not found", "recuperar cartão", "recuperar
  filmagem", "recuperar material do cliente", "formatei o cartão sem querer",
  "corrupted SD card", "card asks to format", "RAW card", "recover footage", "insv
  won't open", "corrupted video", "camera card not mounting" — e também quando o
  usuário descrever o problema sem usar essas palavras, por exemplo "o cartão do
  cliente deu problema na hora de copiar" ou "a câmera travou gravando e agora não acha
  nada". Usar ANTES de sugerir qualquer software de recuperação, porque a ordem das
  ações decide se o material é recuperável.
---

# Resgate de mídia de cartão de câmera

## O que está em jogo

O material num cartão de câmera é **irrepetível**. Não existe segunda tomada de um
casamento, de uma viagem, de um evento. Quem traz o cartão costuma estar entregando a
única cópia que existe no mundo.

Por isso esta skill não otimiza velocidade nem elegância. Ela otimiza **não destruir**.
Toda vez que houver escolha entre agir rápido e agir reversível, escolher reversível.
Toda vez que houver dúvida, **parar e perguntar** — o custo de perguntar é um minuto, o
custo de errar é o material.

E o caminho que a internet ensina — baixar um recuperador e mandar escanear — é o que
**destrói** material de câmera 360 e profissional. O carving por assinatura devolve
arquivos que abrem e não servem: sem o trailer de metadados, um `.insv` não costura.

**Antes de operar, ler `references/licoes-de-campo.md`.** Ele lista as formas pelas
quais estas ferramentas já mentiram — incluindo um caso em que o relatório de validação
disse "43 válidos" sem ter verificado os arquivos grandes.

---

## Proibido — não executar, nem se pedido

Estas ações destroem material e **não** devem ser executadas nem sugeridas, mesmo que o
usuário peça. Diante de um pedido assim, explicar o que a ação faz e oferecer a
alternativa:

| Nunca | Por quê | Em vez disso |
|---|---|---|
| `chkdsk`, "Reparar unidade", "Verificar e corrigir" | **escreve no cartão** e destrói as cadeias FAT residuais que a recuperação usa | ler o índice com `02-diagnostico-exfat` |
| `fsck`, Primeiros Socorros do Disk Utility | o mesmo, no macOS | idem |
| `diskutil eraseDisk`, `format`, formatação rápida | apaga o índice | nada; o cartão não precisa ser formatado para ser lido |
| Montar o cartão na câmera para "testar" | a câmera pode reescrever o índice e renumerar arquivos | leitura por software, com o cartão num leitor |
| Gravar qualquer coisa no cartão | cada escrita pode cair sobre dado não recuperado | destino **sempre** em outro disco |
| Apagar arquivo `.rsv` da Sony | parece lixo e **contém o material** da gravação interrompida | ver `references/sony.md` |
| Apagar os arquivos `_10_` do Insta360 por "não terem metadados" | é a segunda lente; sem ela não há 360 | ver `references/insta360-linha-x.md` |
| Rodar recuperador antes do diagnóstico | pode entregar carving quando a extração pelo índice estava disponível | Passo 0 e Passo 1 |

Se o usuário insistir numa dessas após a explicação, a decisão é dele — mas registrar
que foi informado, e nunca executar como se fosse rotina.

## Antes de escrever qualquer byte — protocolo de parada

Vale para **toda** operação que escreve: no destino, no cartão, em qualquer lugar.
Antes de executar, declarar ao usuário, em texto:

1. **Onde** vai escrever (caminho completo) e **onde não** vai
2. **Quantos bytes**
3. **O que é perdido** se der errado, e se existe como desfazer
4. **Quantas cópias do material existem** neste momento

Se o material existir em **um só lugar**, nenhuma escrita no cartão é autorizada — nem o
conserto do boot sector. Essa regra não tem exceção por conveniência ou por pressa.

Nunca executar um comando com `-Escrever`, `-Force`, `rm`, `mv` sobre material de
cliente, ou formatação, sem confirmação explícita no turno.

---

## Passo 0 — Triagem, antes de tocar no cartão

Rodar primeiro:

```powershell
.\scripts\windows\00-triagem.ps1                                  # lista os candidatos
.\scripts\windows\00-triagem.ps1 -DiskNumber <N> -Destino '<pasta>'
```
```bash
sudo ./scripts/mac/00-triagem.sh                                  # lista
sudo ./scripts/mac/00-triagem.sh /dev/rdiskN ~/resgate/cliente-x
```

O script descobre sozinho: quais discos são candidatos, **qual marca e geração de câmera
gravou o cartão** (pela estrutura de pastas e pelo padrão dos nomes), quanto material
existe, e se o destino escolhido tem espaço. Ele recusa seguir se o destino estiver no
próprio cartão.

### O que o script não sabe — perguntar ao usuário

Estas respostas mudam o que ainda é possível. Perguntar **antes** de executar qualquer
coisa, de preferência com uma pergunta estruturada:

1. **O cartão voltou para a câmera** depois do problema?
2. **Rodou `chkdsk`, "reparar unidade" ou Primeiros Socorros?**
3. **Algum programa de recuperação já passou nele?** Qual?
4. **Houve formatação**, mesmo rápida?
5. **Qual o modelo exato da câmera?** (confirma o que a estrutura sugeriu)
6. **Onde devem ficar os arquivos recuperados?** Caminho completo, em outro disco.
7. **Falta material que nem aparece na lista?** Quantos clipes a pessoa lembra de ter gravado?

"Sim" em 2, 3 ou 4 reduz as chances e muda o caminho. A pergunta 7 é a única forma de
descobrir material cujo índice se perdeu — e a resposta define se vale carving depois.
Detalhe de como interpretar cada resposta em `references/triagem.md`.

### A regra do destino

O material **sai do cartão para um diretório escolhido pelo usuário, em outro disco**.
O cartão é fonte somente-leitura, do começo ao fim. Nunca propor o próprio cartão como
destino, nem usar pasta que já tenha conteúdo de outro cartão — numeração de câmera
Sony reinicia em `C0001` a cada formatação, e dois cartões sobrescrevem um ao outro sem
aviso.

---

## Triagem por sintoma

| O que o usuário observa | Camada danificada | Ir para |
|---|---|---|
| "É preciso formatar o disco", unidade RAW | sistema de arquivos | Passo 1 |
| Monta mas a pasta DCIM está vazia ou incompleta | índice ou entradas de diretório | Passo 1 |
| Arquivos aparecem com tamanho 0 KB | entradas de diretório | Passo 1 |
| Arquivos aparecem íntegros mas não abrem | container do arquivo | Passo 5 |
| `.insv` abre como dois círculos / "stitching data lost" | trailer de metadados | Passo 5 |
| "moov atom not found" | container truncado | Passo 5 |
| Existe arquivo `.rsv` (Sony) | gravação não finalizada | `references/sony.md` |
| Cartão não é reconhecido de jeito nenhum | possível falha física | laboratório; parar aqui |

Nunca reparar arquivo antes de recuperar a estrutura: sem estrutura, não existe arquivo
para reparar.

## Passo 1 — Ler o índice antes de escolher ferramenta

```powershell
.\scripts\windows\02-diagnostico-exfat.ps1 -DiskNumber <N>
```

Leitura pura: não escreve, não ocupa espaço. Ler MBR → VBR (principal; se falhar, o
backup no setor 12) → FAT → diretório raiz → bitmap de alocação.

**O teste que decide:** comparar a soma dos tamanhos no diretório com os clusters
marcados no bitmap. Coincidem → índice íntegro, o material sai inteiro pelo Passo 3.

**Se o diagnóstico apontar dano uniforme em 100% dos arquivos, suspeitar do código antes
do cartão.** Dano real é irregular. Ver L04 em `references/licoes-de-campo.md`.

## Passo 2 — Decidir se a imagem é necessária

A imagem protege tentativas destrutivas repetidas. Com índice íntegro não existe
nenhuma, e a imagem exige o dobro da capacidade do cartão — o que costuma inviabilizar
o trabalho. Fazer imagem quando o índice estiver danificado, houver setores ilegíveis,
ou o caso for de perícia.

## Passo 3 — Extrair pelo índice

```powershell
.\scripts\windows\03-extrair.ps1 -DiskNumber <N> -Destino '<pasta>' -Classes essencial -Simular
.\scripts\windows\03-extrair.ps1 -DiskNumber <N> -Destino '<pasta>' -Classes essencial
```

Simular sempre primeiro: a simulação percorre todas as cadeias e prova que estão
completas antes de escrever o primeiro byte.

Masters primeiro, proxies depois. **Pares de lente saem juntos** — em ONE X, ONE X2 e X3
acima de 5.7K, cada clipe 360 são dois arquivos, e um sem o outro é inútil.

## Passo 4 — Carving, só quando o índice se perdeu

PhotoRec sobre a imagem. Saber o que se perde: nomes, pastas, datas e, possivelmente, o
trailer de metadados. **O PhotoRec não conhece a assinatura `.insv`** — os vídeos saem
como `.mov`/`.mp4` e basta renomear. Ver `references/ferramentas.md`.

## Passo 5 — Reparar containers

Só em arquivo já copiado inteiro. Insta360 File Repair (oficial) para "stitching data
lost"; `untrunc` para truncado sem `moov atom`, com arquivo de referência gravado pela
mesma câmera em **outro cartão**. Detalhes em `references/ferramentas.md`.

## Passo 6 — Validar antes de entregar

```powershell
.\scripts\windows\04-validar.ps1
```

Confere tamanho contra o índice, leitura do container, **decodificação de frames no
início, meio e fim**, e o trailer de metadados. Container que abre não é vídeo válido.

### As três perguntas antes de declarar sucesso

1. O que foi verificado de verdade, e o que foi presumido?
2. Se este número estivesse errado, eu perceberia?
3. O que eu afirmaria ao cliente agora que não posso provar?

Se algum número de verificação não fechar com a conta esperada, **parar e investigar** —
não arredondar a explicação. Foi assim que um relatório verde esconder arquivos não
verificados (L05).

## Entrega

Usar `templates/relatorio-tecnico.md` e `templates/comunicado-cliente.md`. **Declarar
sempre o que não foi recuperado**, com nome e horário, não em nota de pé.

## Devolver o cartão ao uso

Somente depois de o material existir em **dois lugares**. Provar a correção em memória
antes de escrever; são 512 bytes e existe como desfazer.

```powershell
.\scripts\windows\06-consertar-boot.ps1 -DiskNumber <N>                                # prova
.\scripts\windows\06-consertar-boot.ps1 -DiskNumber <N> -Escrever -TenhoSegundaCopia   # aplica
.\scripts\windows\06-consertar-boot.ps1 -DiskNumber <N> -Desfazer                      # reverte
```

## Depois do caso — alimentar a skill

Acrescentar entrada em `references/licoes-de-campo.md` quando houver: erro que deixou o
relatório verde sem verificar, caminho que piorou o estado, comportamento de câmera que
contrariou a documentação, ou número que não fechou.

---

## Recursos desta skill

### Leitura obrigatória antes de operar
- **`references/licoes-de-campo.md`** — o diário de erros: como estas ferramentas já mentiram

### Manuais por marca
- **`references/insta360-linha-x.md`** — ONE X → X6: arquivos por clipe, trailer, procedimentos
- **`references/sony.md`** — M4ROOT, XDROOT, XAVC, arquivos `.rsv`, procedimentos

### Procedimento
- **`references/triagem.md`** — o roteiro de perguntas e o que cada resposta muda
- **`references/escolher-caminho.md`** — índice × imagem × carving × reparo
- **`references/exfat.md`** — estrutura, checksum da região de boot, onde o dano mora
- **`references/ferramentas.md`** — o que cada ferramenta faz e o que estraga
- **`references/armadilhas-powershell.md`** — erros que fazem a verificação mentir

### Scripts
- **`scripts/windows/`** — 7 scripts PowerShell, validados num caso real de 112 GiB
- **`scripts/mac/`** — bash. Parsing e extração provados por SHA-256 contra imagem exFAT;
  **acesso a dispositivo em macOS ainda não exercitado**

### Entrega
- **`templates/relatorio-tecnico.md`** e **`templates/comunicado-cliente.md`**
