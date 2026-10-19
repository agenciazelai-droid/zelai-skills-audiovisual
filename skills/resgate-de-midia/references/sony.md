# Sony — estrutura de cartão, codecs e gravação interrompida

Referência para recuperar material de câmeras Sony. A Sony mantém **dois troncos de
estrutura** incompatíveis entre si, e saber em qual se está define o que é
indispensável copiar.

> **Procedência:** este documento vem de documentação do fabricante e de fontes
> técnicas, **não de observação direta em cartão Sony**. O conteúdo da linha Insta360
> foi verificado em campo; este não. Conferir a estrutura real antes de agir sobre
> material único.

---

## Os dois troncos

### `PRIVATE/M4ROOT/` — linha híbrida e cinema compacta

Formatos **XAVC S** e **XAVC HS**. Câmeras: A7S III, A7 IV, A7C II, A7CR, A6700,
**FX3**, **FX30**, ZV-E1, e a linha de camcorders de consumo.

```
PRIVATE/
└── M4ROOT/
    ├── CLIP/
    │   ├── C0001.MP4          clipe
    │   ├── C0001M01.XML       metadados DESTE clipe
    │   └── ...
    ├── SUB/                   proxies (pasta oculta)
    │   └── C0001S01.MP4
    ├── THMBNL/                miniaturas
    ├── GENERAL/
    └── MEDIAPRO.XML           índice e contador de numeração do cartão
```

Em **CFexpress Type A** o caminho perde o `PRIVATE`: `/M4ROOT/CLIP`.

### `PRIVATE/XDROOT/` — linha profissional

Formatos **XDCAM HD/HD422/IMX/DVCAM**, **SStP**, **XAVC Intra** e **XAVC Long**.
Câmeras: PXW-FS5/FS7, **FX6**, **FX9**, PXW-Z, linha **VENICE**.

```
PRIVATE/
└── XDROOT/
    ├── Clip/
    │   ├── C0001.MXF          clipe
    │   └── C0001M01.XML
    ├── Sub/                   proxies
    ├── General/
    │   └── LUT/               LUTs gravadas pela câmera
    └── Edit/
```

---

## Regra prática: copiar o cartão inteiro

Diferente da Insta360, onde o `.insv` se basta, **um clipe Sony não é autossuficiente**.
O `.MXF`/`.MP4` sozinho perde:

- o `XML` por clipe — timecode, lente, ISO, look, metadados que o NLE lê
- o `MEDIAPRO.XML` — índice do cartão
- a `General/LUT/` — a LUT aplicada na gravação
- os proxies em `Sub/`

Copiar sempre a **árvore completa a partir de `PRIVATE/`**. Um clipe recuperado por
carving, sem o XML ao lado, chega ao editor sem timecode e sem identificação de lente.

Numa recuperação por carving, isso significa: **recuperar também os `.XML`**, não só os
vídeos. O PhotoRec os devolve como arquivos de texto soltos, e reassociar depende do
conteúdo do XML (que nomeia o clipe internamente), não do nome do arquivo.

---

## Colisão de nomes: o erro que apaga material

A numeração Sony é `C0001`, `C0002`, … e **reseta para `C0001` a cada formatação**.

Consequência direta: dois cartões da mesma câmera, ou dois dias de diária, produzem
`C0001.MP4` diferentes. Copiar dois cartões para a mesma pasta de destino **sobrescreve
material sem aviso**.

Antes de extrair, criar uma pasta por cartão, nomeada com data e identificação:
`2026-10-19_FX3_cartao-A/`. Esta é a causa mais comum de "perda" em set que não tem
nada de corrupção.

---

## Codecs: o que muda na hora de reparar

| Formato | Compressão | Container | Onde aparece |
|---|---|---|---|
| **XAVC-I** | intra-frame (todo frame é chave) | `.MXF` | FX6, FX9, PXW |
| **XAVC-L** | long-GOP | `.MXF` | FX6, FX9, PXW |
| **XAVC S** | long-GOP | `.MP4` | A7, FX3, FX30, ZV |
| **XAVC S-I** | intra-frame | `.MP4` | A7S III, FX3, FX30 |
| **XAVC HS** | long-GOP, **HEVC/H.265** | `.MP4` | A7S III, A1, FX3 |
| **X-OCN** | RAW | `.MXF` | VENICE |

**Por que isso importa num reparo:** em codec **intra-frame** (XAVC-I, XAVC S-I), cada
frame é independente — um arquivo truncado perde só o que vem depois do corte, e o
resto decodifica. Em **long-GOP** (XAVC-L, XAVC S, XAVC HS), o corte no meio de um GOP
estraga todos os frames daquele grupo que dependiam do frame-chave perdido.

Logo: material intra-frame tolera truncamento muito melhor. Ao priorizar o que extrair
com espaço limitado, long-GOP é o que mais precisa sair íntegro.

---

## Gravação interrompida: os arquivos `.rsv`

**Este é o equivalente Sony do cartão que corrompe durante a extração.**

Quando a gravação é interrompida — bateria, remoção do cartão, queda de energia — a
Sony **não deixa um MXF corrompido**. Deixa um arquivo **`.rsv`**: o conteúdo gravado,
sem finalização. Nenhum editor abre `.rsv`.

Câmeras com esse comportamento: **FX3, FX30, FX6, FX9** e a linha **VENICE** (inclusive
takes X-OCN).

### Como tratar

1. **Não apagar o `.rsv`.** Ele contém o material. Parece lixo e não é.
2. **Tentar primeiro a recuperação da própria câmera.** Recolocar o cartão na mesma
   câmera e ligar: o firmware detecta a gravação incompleta e oferece recuperar,
   finalizando o `.rsv` em `.MXF`.
   > Exceção importante: isso **escreve no cartão**. Só fazer quando o cartão estiver
   > saudável e o `.rsv` for o único problema. Se o cartão também estiver corrompido
   > (RAW, pedindo formatação), **não** colocar na câmera — extrair o `.rsv` primeiro.
3. **Se a câmera não recuperar**, existem ferramentas e serviços dedicados a reconstruir
   `.rsv` em `.MXF` finalizado (`rsv.repair`, entre outros). Serviço pago.

### Distinguir os dois problemas

| Sintoma | Natureza | Caminho |
|---|---|---|
| Cartão monta, existe `.rsv` | gravação não finalizada | recuperação pela câmera ou reparo de `.rsv` |
| Cartão pede formatação | sistema de arquivos | diagnóstico de índice (ver `escolher-caminho.md`) |
| `.MXF` existe e não abre | container | reparo de container |

Confundir os dois leva a formatar um cartão que estava íntegro.

---

## Procedimento por linha — o que fazer em cada caso

### Linha híbrida (A7, FX3, FX30, ZV) — `M4ROOT`

1. Procurar `.rsv` **antes de tudo**. Se houver, tratar primeiro (ver acima).
2. Extrair a árvore completa a partir de `PRIVATE/` — não só `CLIP/`.
3. Conferir que cada `C####.MP4` tem seu `C####M01.XML` ao lado.
4. Criar **uma pasta por cartão** no destino: `C0001` colide entre cartões.
5. Identificar o codec (`XAVC S` long-GOP ou `XAVC S-I` intra) — define a tolerância a
   truncamento.
6. Não esquecer `SUB/` se os proxies importarem ao fluxo de edição.

### Linha profissional (FX6, FX9, PXW, VENICE) — `XDROOT`

1. Procurar `.rsv` primeiro. Em VENICE, takes X-OCN interrompidos seguem o mesmo esquema.
2. Extrair a árvore completa a partir de `PRIVATE/XDROOT/`, incluindo `General/LUT/`.
3. Clipe `.MXF` sem o XML ao lado chega ao NLE sem timecode e sem identificação de lente.
4. Em XAVC-I (intra-frame), arquivo truncado perde só o que vem depois do corte — o
   resto decodifica. Em XAVC-L, o corte estraga o GOP inteiro.

### Todas as linhas

1. **Copiar o cartão inteiro, não clipes avulsos.** Esta é a diferença mais importante
   em relação à Insta360.
2. Se a estrutura saiu desmontada (carving), **recolocar os clipes em `CLIP/`** junto dos
   XMLs antes de entregar — é o que faz o NLE reconhecê-los.

## Ferramenta oficial

A Sony distribui um aplicativo de recuperação para cartões **XQD/CFexpress** que
restaura material corrompido.

**Detalhe operacional:** os clipes recuperados podem sair fora da árvore e precisam ser
**recolocados manualmente em `XDROOT/Clip/`**, junto dos XMLs, para que o NLE os
reconheça como clipes completos.

---

## Checklist de recuperação Sony

1. Identificar o tronco: existe `M4ROOT` ou `XDROOT`?
2. Procurar `.rsv` **antes** de qualquer outra coisa — e não apagar.
3. Confirmar o codec (intra ou long-GOP) para estimar tolerância a truncamento.
4. Extrair a árvore completa a partir de `PRIVATE/`, não só os clipes.
5. Criar pasta por cartão, para não colidir `C0001`.
6. Conferir que cada clipe recuperado tem seu `XML` ao lado.
7. Validar com `ffprobe` decodificando início, meio e fim.

---

## O que ainda falta verificar neste documento

Marcado explicitamente para quem for usar ou contribuir:

- [ ] Estrutura real de um cartão FX3 e de um FX6, conferida em disco
- [ ] Nomenclatura exata dos XML (`C0001M01.XML` confirmado? há variação por modelo?)
- [ ] Comportamento do `.rsv` em cartão com sistema de arquivos danificado
- [ ] Se o PhotoRec reconhece `.MXF` por assinatura (no caso do `.insv` **não**
      reconhece — ver `ferramentas.md`)
- [ ] Linha ARRI e RED, ainda não cobertas por esta skill
