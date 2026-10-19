---
name: resgate-de-midia
description: >
  Resgata vídeo e foto de cartão de memória corrompido de câmera (Insta360 linha X,
  Sony XAVC/XDCAM, GoPro, DSLR) sem destruir os metadados que o material precisa para
  ser usado. Cobre cartão que pede formatação, cartão RAW, arquivo .insv que não abre,
  vídeo truncado sem moov atom, clipe que aparece como dois círculos de peixe-olho, e
  extração interrompida. Esta skill deve ser usada sempre que o usuário mencionar
  "cartão corrompido", "cartão pede para formatar", "cartão RAW", "perdi os vídeos",
  "perdi a filmagem", "o cartão não abre", "o cartão sumiu com os arquivos", "arquivo
  .insv não abre", "insv corrompido", "vídeo corrompido", "vídeo não abre", "stitching
  data lost", "moov atom not found", "recuperar cartão", "recuperar filmagem",
  "recuperar material do cliente", "formatei o cartão sem querer", "corrupted SD card",
  "card asks to format", "RAW card", "recover footage", "insv won't open", "corrupted
  video", "camera card not mounting" — e também quando o usuário descrever o problema
  sem usar essas palavras, por exemplo "o cartão do cliente deu problema na hora de
  copiar" ou "a câmera travou gravando e agora não acha nada". Usar ANTES de sugerir
  qualquer software de recuperação, porque a ordem das ações decide se o material é
  recuperável.
---

# Resgate de mídia de cartão de câmera

Esta skill existe porque o caminho que a internet ensina — baixar um recuperador e
mandar escanear — é o caminho que **destrói** material de câmera 360 e profissional.
O carving por assinatura devolve arquivos que abrem e não servem: sem o trailer de
metadados, um `.insv` não costura, e um clipe Sony perde o XML que o NLE lê.

A ordem correta começa com uma pergunta que quase ninguém faz: **o índice do sistema
de arquivos ainda está lá?** Na maioria dos casos de "cartão pede para formatar", está.

## Regra zero: o cartão sai do caminho de escrita

Aplicar antes de qualquer diagnóstico, sempre, sem exceção:

1. **Recusar o "verificar e reparar a unidade" do Windows e o "reparar" do macOS.**
   O `chkdsk` e o `fsck` escrevem no cartão e destroem as cadeias FAT residuais — que
   são exatamente o que a remontagem usa. Este é o único passo verdadeiramente
   irreversível de todo o processo.
2. **Não devolver o cartão à câmera.** Ligar a câmera pode reescrever o índice e
   renumerar arquivos.
3. **Não formatar**, nem "formatação rápida", nem pela câmera.
4. **Abrir o dispositivo somente em leitura** em toda ferramenta e todo script.
5. **Confirmar a identidade do disco pelo modelo, nunca pelo tamanho.** Dois discos de
   119 GiB numa mesma máquina são indistinguíveis por tamanho, e apontar a ferramenta
   para o disco errado é o acidente mais fácil de cometer.

## Triagem por sintoma

| O que o usuário observa | Camada danificada | Ir para |
|---|---|---|
| "É preciso formatar o disco", unidade RAW | sistema de arquivos | Passo 1 |
| Monta mas a pasta DCIM está vazia ou incompleta | índice ou entradas de diretório | Passo 1 |
| Arquivos aparecem com tamanho 0 KB | entradas de diretório | Passo 1 |
| Arquivos aparecem íntegros mas não abrem | container do arquivo | Passo 5 |
| `.insv` abre como dois círculos / "stitching data lost" | trailer de metadados | Passo 5 |
| "moov atom not found" | container truncado | Passo 5 |
| Cartão não é reconhecido de jeito nenhum | possível falha física | laboratório; parar aqui |

Nunca reparar arquivo antes de recuperar a estrutura: sem a estrutura, não existe
arquivo para reparar.

## Passo 1 — Ler o índice antes de escolher ferramenta

Executar o diagnóstico de leitura pura. Ele não escreve, não ocupa espaço e responde o
que define todo o resto:

```powershell
# Windows, PowerShell COMO ADMINISTRADOR
.\scripts\windows\02-diagnostico-exfat.ps1 -DiskNumber <N>
```
```bash
# macOS/Linux
sudo ./scripts/mac/02-diagnostico-exfat.sh /dev/rdiskN
```

Ler, nessa ordem: MBR/GPT → VBR (principal; se falhar, o backup no setor 12) → FAT →
diretório raiz → bitmap de alocação.

**O teste que decide:** comparar a soma dos tamanhos das entradas de diretório com os
clusters marcados no bitmap de alocação. Se os dois números coincidem, o índice está
íntegro e o material sai inteiro pelo Passo 3 — sem imagem, sem carving, sem reparo.

Consultar `references/exfat.md` para a estrutura e os offsets, e
`references/escolher-caminho.md` para a árvore de decisão completa.

## Passo 2 — Decidir se a imagem bit-a-bit é necessária

A imagem protege **tentativas destrutivas repetidas**. Quando o índice está íntegro,
não existe nenhuma: a extração é leitura dirigida. Nesse caso a imagem só custa espaço
— e costuma ser o que inviabiliza o trabalho, porque exige o dobro da capacidade do
cartão.

Fazer imagem quando: o índice estiver danificado, houver setores ilegíveis, ou o caso
for de perícia. Usar `01-criar-imagem.ps1`, que registra setores ruins e permite
retomar. Diante de erros de leitura, trocar para `ddrescue` ou HDDSuperClone, que têm
estratégia de releitura.

## Passo 3 — Extrair pelo índice (caminho preferido)

Seguir a cadeia de clusters de cada arquivo e gravar byte a byte no destino, com nome,
caminho e data originais. Isso preserva **o arquivo inteiro**, incluindo o trailer
proprietário que o carving descartaria.

```powershell
.\scripts\windows\03-extrair.ps1 -DiskNumber <N> -Classes essencial -Simular
.\scripts\windows\03-extrair.ps1 -DiskNumber <N> -Classes essencial
```

Simular primeiro: a simulação percorre todas as cadeias e prova que estão completas
antes de escrever o primeiro byte no destino.

**Priorizar por papel do arquivo quando o espaço aprecia.** Masters primeiro, proxies
(LRV, `Sub/`) depois — eles só importam se um master falhar na validação.

**Garantir que os pares de lente saiam juntos.** Em ONE X, ONE X2 e X3 acima de 5.7K,
cada clipe 360 são dois arquivos; recuperar um sem o outro entrega um clipe inútil.
Consultar `references/insta360-linha-x.md` para a matriz modelo por modelo — ela mudou
no X4 e o manual oficial do X2 está errado a respeito.

## Passo 4 — Carving, só quando o índice se perdeu

Quando o diagnóstico não achar VBR nem cadeias utilizáveis, aí sim PhotoRec sobre a
imagem. Saber de antemão o que se perde:

- **PhotoRec não conhece a assinatura `.insv`** (verificado no binário 7.2): os vídeos
  saem como `.mov`/`.mp4`. Renomear para `.insv` depois.
- Nomes originais, pastas e datas não voltam.
- O corte por assinatura pode truncar o trailer de metadados.

Para remontar clipes fragmentados a partir das cadeias FAT residuais, usar
`seungwoochoe/insta360-footage-recovery` como referência de método. Ver
`references/ferramentas.md`.

## Passo 5 — Reparar containers

Aplicar somente a arquivos que já foram copiados inteiros:

1. **Insta360 File Repair** (oficial, gratuito, Windows/macOS) — para `.insv` com
   "stitching data lost" ou que abre como dois círculos. Suporta ONE X até X6.
2. **anthwlock/untrunc** — para clipe truncado sem `moov atom`. Exige arquivo de
   referência da **mesma câmera, mesmo modo e mesma resolução**. Esse arquivo é
   gratuito: gravar um clipe novo de 30 segundos em outro cartão.
3. **kichiki/finsta360** — alternativa que reconstrói o `moov` a partir de referência.
4. **alex-plekhanov/insvtools** (`replace-meta`) — transplantar metadados de um clipe
   bom para um recuperado.

## Passo 6 — Validar antes de entregar

Container que abre não é vídeo válido. Validar cada arquivo:

```powershell
.\scripts\windows\04-validar.ps1
```

A validação confere quatro coisas: tamanho contra o índice do cartão, leitura do
container pelo `ffprobe`, **decodificação de frames no início, no meio e no fim**, e
presença do trailer de metadados do fabricante.

Entregar ao cliente usando `templates/relatorio-tecnico.md` e
`templates/comunicado-cliente.md`. Declarar sempre o que **não** foi recuperado.

## Devolver o cartão ao uso

Opcional, e **somente depois de o material existir em dois lugares**.

Quando o diagnóstico apontar checksum da região de boot inconsistente, o conserto é
cirúrgico: copiar o setor divergente da região de backup sobre a principal. Provar a
correção em memória antes de escrever:

```powershell
.\scripts\windows\06-consertar-boot.ps1 -DiskNumber <N>                                # prova
.\scripts\windows\06-consertar-boot.ps1 -DiskNumber <N> -Escrever -TenhoSegundaCopia   # aplica
.\scripts\windows\06-consertar-boot.ps1 -DiskNumber <N> -Desfazer                      # reverte
```

Em caso real, **103 bytes corrompidos num setor de 512 trancaram 112 GiB** de material
perfeitamente íntegro. A escrita foi de 512 bytes.

## Prevenção, para dizer ao cliente no fim

A causa mais comum desse dano é **remoção do cartão durante escrita** — inclusive uma
cópia interrompida. Ejetar sempre pelo sistema, nos dois sistemas operacionais. E
nunca formatar o cartão antes de o material estar verificado por checksum no destino.

## Recursos desta skill

### Referências
- **`references/escolher-caminho.md`** — árvore de decisão: índice × imagem × carving × reparo
- **`references/exfat.md`** — estrutura do exFAT, checksum da região de boot, onde o dano mora
- **`references/insta360-linha-x.md`** — matriz ONE X → X6: arquivos por clipe, nomenclatura, trailer
- **`references/sony.md`** — M4ROOT, XDROOT, XAVC, XMLs e proxies
- **`references/ferramentas.md`** — TestDisk, PhotoRec, untrunc, finsta360, insvtools, serviços pagos
- **`references/armadilhas-powershell.md`** — erros que fazem a verificação mentir em silêncio

### Scripts
- **`scripts/windows/`** — 6 scripts PowerShell, validados num caso real de 112 GiB
- **`scripts/mac/`** — equivalentes em bash. **Não testados em hardware macOS** — revisar antes de usar em material único

### Modelos de entrega
- **`templates/relatorio-tecnico.md`** — o que foi feito, o que foi verificado
- **`templates/comunicado-cliente.md`** — linguagem sem jargão, incluindo o que não voltou
