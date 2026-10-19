# Insta360 linha X — o que cada modelo grava

Documento de referência para decidir, numa recuperação, **quantos arquivos formam um
clipe** e **quais deles são indispensáveis**. A resposta muda de geração em geração, e
errar aqui significa entregar ao cliente um clipe que não costura.

Fontes: manuais oficiais da Insta360 por modelo + observação direta num cartão real de
ONE X2 (119 GiB, 22 clipes, outubro de 2026). Onde as duas discordam, a observação de
campo vem marcada e **prevalece**.

---

## Convenção de nomes (toda a linha X)

```
[prefixo]_[YYYYMMDD]_[HHMMSS]_[LP]_[NNN].[extensão]
```

| Campo | Valores | Significado |
|---|---|---|
| prefixo | `VID`, `IMG`, `LRV` | vídeo, foto, proxy de baixa resolução |
| `YYYYMMDD_HHMMSS` | data e hora | relógio da câmera — **não confiável** se a bateria zerou |
| `L` (1º dígito) | `0` / `1` | lente: 0 = traseira (lado oposto à tela), 1 = frontal (lado da tela) |
| `P` (2º dígito) | `0` / `1` | 0 = master, 1 = proxy |
| `NNN` | sequencial | numerado pela câmera; **pula números**, e isso não indica perda |
| extensão | `.insv`, `.lrv`, `.mp4`, `.insp`, `.jpg`, `.dng` | ver tabela por modelo |

Combinações: `_00_` master traseira · `_10_` master frontal · `_01_` proxy traseira ·
`_11_` proxy frontal.

**Os números de sequência pulando é normal.** Num cartão real de X2 apareceram os
clipes 004, 006, 008, 012, 013, 014, 016… A numeração é por arquivo gerado, não por
clipe. Não tratar lacuna na sequência como arquivo perdido — verificar pelas
miniaturas em `DCIM/Camera01/Thumb/`, cruzando cada `.bmp` com seu vídeo.

---

## Matriz: arquivos por clipe em modo 360

| Modelo | Ano | Máx. 360 | **VID por clipe** | Proxy | Lente única |
|---|---|---|---|---|---|
| ONE X | 2018 | 5.7K30 | **2** (um por lente) em 5.7K+ | 1 LRV | — |
| ONE X2 | 2020 | 5.7K30 | **2** (um por lente) | 1 LRV | MP4 |
| X3 | 2022 | 5.7K30 | **2** acima de 5.7K · **1** até 5.7K | 1 LRV | MP4 |
| X4 | 2024 | 8K30 | **1** (as duas lentes juntas) | 1 LRV | MP4 |
| X4 Air | 2026 | 8K30 | **1** | 1 LRV | MP4 |
| X5 | 2025 | 8K30 | **1** | 1 LRV | MP4 |
| X6 | 2026 | 8K50 | **1** | 1 LRV | MP4 |

O manual do X6 declara: *"X6, X5, X4 Air e X4 geram apenas um arquivo VID contendo
dados de ambas as lentes"*, ao contrário do X3.

### A divisória é o X4

**ONE X, ONE X2 e X3 em alta resolução:** o clipe 360 são **dois arquivos**, um por
lente. Os dois precisam estar na mesma pasta ou o Insta360 Studio não costura. Numa
recuperação, **par incompleto = clipe perdido**, mesmo que um dos lados esteja perfeito.

**X4, X4 Air, X5 e X6:** um arquivo só, com as duas lentes dentro. Esse risco não
existe.

Antes de qualquer extração, identificar o modelo. Na dúvida, o próprio padrão dos nomes
responde: se existirem pares `_00_` e `_10_` com o mesmo timestamp e a mesma sequência,
a câmera é da geração que divide em dois.

### Erro conhecido na documentação oficial

O manual do **ONE X2** afirma que o master `_00_` contém as duas lentes num arquivo.
**Está errado.** Observação num cartão real de X2 mostra pares:

```
VID_20260812_174444_00_004.insv   7.524.018.742 bytes   (lente traseira)
VID_20260812_174444_10_004.insv   7.486.832.640 bytes   (lente frontal)
LRV_20260812_174444_11_004.insv   2.131.937.422 bytes   (proxy)
```

Os dois VID têm a mesma duração (1.195,3 s) e contagem de frames praticamente idêntica
(35.823 e 35.822), cada um com um stream h264 de **2880×2880** — uma lente cada.

---

## O arquivo LRV (proxy)

Vídeo de baixa resolução que a câmera gera junto com o master, para preview, análise de
cena e reconhecimento por IA.

**A extensão varia por geração** — detalhe que quebra scripts de automação:

| Modelo | Extensão do LRV |
|---|---|
| ONE X2 | **`.insv`** (observado em campo: `LRV_20260815_122551_11_031.insv`) |
| X3 em diante | **`.lrv`** (ex.: `LRV_20220925_160925_11_070.lrv`) |

**O LRV não é gerado** em: Bullet Time, TimeShift, Timelapse, e vídeo em alta taxa de
quadros (4K@60/50fps, 3K@100fps, acima de 100fps).

### Quando o LRV salva o trabalho

Numa recuperação com espaço apertado, descartar os LRV primeiro — num cartão de X2 de
112,42 GiB eles eram 16,57 GiB, ou 15% do total. Mas **só descartar depois de validar
os masters.** Se um master for irrecuperável, o LRV entrega imagem em baixa resolução,
e para um cliente isso é melhor que nada.

---

## O trailer de metadados

O `.insv` é um MP4 (ISO BMFF) com um **trailer proprietário no fim do arquivo**, onde
vivem os dados de giroscópio e de costura. Sem ele, o Insta360 Studio abre dois
círculos de peixe-olho e não gera o 360.

**Assinatura (magic):** `8db42d694ccc418790edff439fe026bf`

Observado em campo, a **32 bytes do fim do arquivo**, em todos os 22 arquivos que
deveriam tê-lo.

### Onde o trailer existe e onde não existe

| Arquivo | Trailer | Observação |
|---|---|---|
| `_00_` master (lente traseira) | **sim** | é o arquivo que o Studio abre |
| `_10_` master (lente frontal) | **não** | ausência é **normal**, não é perda |
| `.mp4` de lente única | **sim** | confirmado em campo |

Ausência de trailer no `_10_` **não indica dano**. Confirmação: os arquivos `_10_`
observados têm tamanho em múltiplo exato de MiB (41.943.040 = 40 MiB; 83.886.080 =
80 MiB), e batem byte a byte com o índice do cartão.

Verificar o trailer é a prova de que a extração preservou o que o carving destruiria.
Ler os últimos 128 KB do arquivo e procurar a assinatura — e **só exigir sua presença
em `_00_` e nos `.mp4`**.

---

## Fotos

| Modo | Extensão | Observação |
|---|---|---|
| Foto 360 | `.insp` | JPEG com metadados de costura; abre em visualizador comum, mas chapado |
| Foto 360 RAW | `.dng` | um por lente |
| Foto lente única | `.jpg` | comum |

---

## Estrutura de pastas no cartão

```
DCIM/
├── Camera01/
│   ├── VID_*.insv          masters
│   ├── LRV_*.insv | *.lrv  proxies
│   ├── VID_*.mp4           lente única
│   └── Thumb/
│       └── VID_*.bmp       miniaturas (~0,3 MB) — úteis para achar clipe faltando
└── fileinfo_list.list      índice interno da câmera
```

A pasta `Thumb/` é a melhor ferramenta de auditoria disponível: **toda miniatura
corresponde a um vídeo**. Miniatura sem vídeo = clipe cujo índice se perdeu, e aí sim
vale carving. Vídeo sem miniatura é comum e não significa nada.

---

## Especificações que importam na validação

| Modelo | Resolução por lente (360) | Codec | Áudio |
|---|---|---|---|
| ONE X2 | 2880×2880 por arquivo, 29,97 fps | h264 | AAC 48 kHz estéreo |
| X3 | 2880×2880 (5.7K) | h264 / h265 | AAC |
| X4 / X4 Air | 8K equivalente, arquivo único | h265 | AAC |
| X5 | 8K30, arquivo único | h265 | AAC |
| X6 | 8K50, sensores de 1 polegada, Dolby Vision nativo | h265 | AAC |

Em lente única (Steady Cam), observado em X2: h264 **2560×1440 a 50 fps**.

Usar esses números na validação: resolução fora do esperado indica arquivo remontado
errado, não só corrompido.

---

## Procedimento por geração — o que fazer em cada caso

### ONE X, ONE X2, X3 (as gerações de par de lente)

1. **Identificar os pares** antes de extrair. Para cada `VID_<data>_<hora>_00_<seq>`
   deve existir `VID_<data>_<hora>_10_<seq>` com o mesmo carimbo e a mesma sequência.
2. **Extrair os dois juntos.** Ordenar a extração por nome garante isso naturalmente.
3. **Nunca descartar os `_10_`** por "não terem metadados" — é a segunda lente.
4. **Conferir pares órfãos.** Um `_00_` sem `_10_` significa que o índice daquele lado se
   perdeu: o clipe não costura, e vale carving no espaço livre para procurar o par.
5. Para abrir, manter os dois arquivos **na mesma pasta**. O Studio abre o `_00_` e
   procura o par ao lado.

### X4, X4 Air, X5, X6 (arquivo único)

1. Um `.insv` por clipe, com as duas lentes dentro. Não há par a preservar.
2. Resoluções maiores (8K): arquivos maiores, mais tempo de extração, mais espaço.
3. O trailer de metadados vive no próprio arquivo — presença obrigatória.

### Todas as gerações

1. **Auditar pelas miniaturas**: cruzar `DCIM/Camera01/Thumb/*.bmp` com os vídeos. Toda
   miniatura deve ter seu vídeo; o contrário é normal.
2. **Não confiar na sequência numérica** para detectar perda — a câmera pula números.
3. **Guardar os LRV até a validação terminar.** Descartar só depois de os masters
   passarem na decodificação.

## Ferramenta oficial

**Insta360 File Repair** v1.1 (29/12/2024), gratuita, Windows e macOS. Suporta ONE X,
X2, X3, X4, X4 Air, X5 e X6. Repara `.insv` e `.mp4` com "stitching data lost" ou que
abrem como dois panoramas.

Procedimento oficial, conforme o manual:

1. Baixar na página de downloads da Insta360, ao fim da página
2. Abrir a ferramenta e selecionar o arquivo
3. **Não mover o arquivo durante o reparo**
4. **Não desligar o computador durante o processo**

Requisitos declarados para o reparo automático funcionar: o arquivo precisa ser `.insv`
ou `.mp4` gravado por câmera Insta360, **e** apresentar um destes sintomas — abre como
dois panoramas esféricos no Studio, mostra "stitching data lost", ou dá erro ao importar.

Se o arquivo não atender aos requisitos, o suporte da Insta360 atende 24/7 e aceita
envio de arquivo para análise. Para material de cliente, essa é uma opção legítima antes
de esgotar tentativas que podem piorar o estado.

Download: página de downloads da Insta360, ao fim da página. O site bloqueia download
automatizado (HTTP 403) — baixar pelo navegador.

**Limite declarado pelo fabricante:** se os dados de giroscópio e de som estiverem
danificados, o reparo não é completo. E ela só atua em arquivo que já foi copiado
inteiro — não recupera nada do cartão.
