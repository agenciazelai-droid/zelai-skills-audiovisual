# exFAT — estrutura, e onde o dano costuma morar

Cartões de câmera acima de 32 GB vêm em exFAT. Entender onde cada coisa fica é o que
permite ler o índice sem escrever nada e decidir o caminho com fato em vez de palpite.

Todos os offsets abaixo valem a partir do **início da partição**, não do disco. Localizar
esse início na tabela de partição primeiro.

---

## As duas regiões de boot

O exFAT guarda a região de boot **duas vezes**, 12 setores cada:

| Setor | Conteúdo |
|---|---|
| 0 | **Main Boot Sector** (VBR) — os parâmetros do volume |
| 1–8 | Main Extended Boot Sectors — cada um fecha com `0xAA550000` |
| 9 | Main OEM Parameters |
| 10 | Main Reserved |
| 11 | **Main Boot Checksum** — um `UInt32` repetido por todo o setor |
| 12–23 | a mesma estrutura, de **backup** |

**O driver recalcula o checksum dos setores 0–10 e compara com o setor 11. Se não bate,
rejeita o volume inteiro** — por mais íntegros que estejam FAT, diretórios e dados.

É aqui que mora a maioria dos casos de "cartão pede para formatar" em cartão que nunca
sofreu dano físico.

### O algoritmo do checksum

Rotação de 1 bit à direita, somando byte a byte, sobre os setores 0 a 10
(11 × 512 = 5.632 bytes com setor de 512). **Três offsets ficam fora da conta:**
106, 107 (`VolumeFlags`) e 112 (`PercentInUse`).

```
soma = 0
para cada byte i em 0..5631:
    se i em {106, 107, 112}: pular
    soma = ((soma & 1) << 31) + (soma >> 1) + byte[i]   (em 32 bits)
```

Que o 112 fique de fora tem consequência prática: a região principal e a de backup
podem diferir **legitimamente** nesse byte, sem quebrar nada.

### Diagnóstico e conserto

Calcular o checksum das duas regiões e comparar com o gravado em cada uma:

| Principal | Backup | Significado | Ação |
|---|---|---|---|
| bate | bate | a rejeição tem outra causa | investigar upcase, bitmap, campos |
| **não bate** | **bate** | dano na principal | copiar do backup o(s) setor(es) divergente(s) |
| bate | não bate | o driver lê a principal; não é a causa | regravar o backup, opcional |
| não bate | não bate | ambas corrompidas | recalcular e regravar o setor 11 |

**Comparar as duas regiões byte a byte para localizar o dano.** Em caso real, dos 104
bytes divergentes, 103 estavam no **setor 1** e 1 no offset 112 do setor 0 (inofensivo).
O conserto foi copiar **um setor de 512 bytes**.

Antes de escrever, **provar em memória**: montar a região com o setor substituído,
recalcular, e confirmar que o resultado bate com o valor já gravado no setor 11.

---

## Campos do VBR que importam

Offsets dentro do setor 0:

| Offset | Tamanho | Campo | Para que serve |
|---|---|---|---|
| 3 | 8 | `FileSystemName` | deve ser `"EXFAT   "` (3 espaços) |
| 64 | 8 | `PartitionOffset` | em setores |
| 72 | 8 | `VolumeLength` | em setores |
| 80 | 4 | `FatOffset` | início da FAT, em setores |
| 84 | 4 | `FatLength` | tamanho da FAT, em setores |
| 88 | 4 | `ClusterHeapOffset` | início da área de dados, em setores |
| 92 | 4 | `ClusterCount` | total de clusters |
| 96 | 4 | `FirstClusterOfRootDirectory` | onde o diretório raiz começa |
| 106 | 2 | `VolumeFlags` | bit 1 = **VolumeDirty** |
| 108 | 1 | `BytesPerSectorShift` | potência de 2 — faixa válida: 9 a 12 |
| 109 | 1 | `SectorsPerClusterShift` | potência de 2 |
| 110 | 1 | `NumberOfFats` | 1 normalmente |
| **112** | 1 | `PercentInUse` | **0–100 = % em uso; 0xFF = indisponível** |
| 510 | 2 | `BootSignature` | `0x55AA` |

`PercentInUse` é um atalho valioso: dá a ocupação do cartão lendo **um byte**, antes de
percorrer qualquer diretório. Num caso real indicou 94%, e a contagem completa do bitmap
confirmou 112,42 de 119,08 GiB.

Posição de um cluster em bytes:

```
offset = inicioParticao + (ClusterHeapOffset × bytesPorSetor)
                        + ((cluster - 2) × bytesPorCluster)
```

Clusters são numerados a partir de **2**.

---

## A FAT e as cadeias

Entradas de 4 bytes, como FAT32. A entrada do cluster N guarda o número do próximo
cluster do arquivo.

| Valor | Significado |
|---|---|
| `0x00000002` a `ClusterCount+1` | próximo cluster |
| `0xFFFFFFFF` | fim da cadeia |
| `0xFFFFFFF7` | cluster defeituoso |
| `0x00000000` | livre |

Cartão de câmera costuma ter cadeias **sequenciais** — a câmera grava de forma contígua.
Num caso real: `FAT[999]=1000`, `FAT[1000]=1001`, `FAT[1001]=1002`. Isso permite coalescer
leituras grandes em vez de ler cluster por cluster.

A FAT inteira costuma ser pequena (8 MiB num cartão de 128 GB): **carregar em memória de
uma vez** e percorrer as cadeias sem voltar ao disco.

### `NoFatChain` — a exceção

No Stream Extension da entrada de diretório, offset 1, bit 1 (`0x02`): quando setado, o
arquivo é **contíguo e a FAT não é consultada**. Os clusters são simplesmente
`primeiro`, `primeiro+1`, … pelo número necessário.

Tratar os dois casos. Ignorar essa flag faz a extração falhar em arquivos contíguos sem
erro aparente.

---

## Entradas de diretório

Blocos de 32 bytes. Um arquivo ocupa um **conjunto** de entradas consecutivas.

| `EntryType` | O que é |
|---|---|
| `0x85` | File Directory Entry — atributos e datas |
| `0xC0` | Stream Extension — tamanho e primeiro cluster |
| `0xC1` | File Name — 15 caracteres UTF-16LE por entrada |
| `0x81` | Allocation Bitmap |
| `0x82` | Upcase Table |
| `0x83` | Volume Label |
| `0x00` | fim do diretório |

**`0x85` File Directory Entry:**

| Offset | Campo |
|---|---|
| 1 | `SecondaryCount` — quantas entradas seguem |
| 4 | `FileAttributes` — bit `0x10` = diretório |
| 8 | `CreateTimestamp` |
| 12 | `LastModifiedTimestamp` |

**`0xC0` Stream Extension:**

| Offset | Campo |
|---|---|
| 1 | `GeneralSecondaryFlags` — bit `0x02` = `NoFatChain` |
| 3 | `NameLength` |
| 8 | `ValidDataLength` |
| 20 | `FirstCluster` |
| 24 | `DataLength` |

`ValidDataLength` menor que `DataLength` indica arquivo pré-alocado e não totalmente
gravado — sinal de **gravação interrompida**. Num cartão saudável os dois são iguais.

Timestamp no formato DOS: bits 0–4 segundos÷2, 5–10 minutos, 11–15 horas, 16–20 dia,
21–24 mês, 25–31 ano desde 1980. Segundos podem vir como 60 — limitar a 59 antes de
converter.

---

## Allocation Bitmap e Upcase Table

**Allocation Bitmap** (entrada `0x81` no raiz): um bit por cluster, setado = em uso.
Contar os bits dá o espaço realmente ocupado, por um caminho **independente** das
entradas de diretório. É essa independência que torna a comparação uma prova.

**Upcase Table** (entrada `0x82`): tabela de maiúsculas, com `TableChecksum` no offset 4.
O driver valida esse checksum. Corrompida, é outra causa de rejeição do volume — e o
algoritmo é o mesmo do boot, **sem offsets excluídos**.

---

## Ler disco bruto: duas armadilhas

**Alinhamento ao setor.** Leitura de `\\.\PhysicalDriveN` ou `/dev/rdiskN` só aceita
offset e tamanho múltiplos do setor. Ler 4 bytes de uma entrada da FAT num offset
arbitrário **falha**. Ler o bloco alinhado que contém a faixa e recortar.

**Elevação.** Acesso bruto exige administrador no Windows e `sudo` no macOS/Linux. Sem
isso, "acesso negado" — que parece falta de hardware e não é.

No macOS, usar `/dev/rdiskN` (acesso cru, direto) em vez de `/dev/diskN` (bufferizado):
é ordens de magnitude mais rápido. Desmontar antes com `diskutil unmountDisk`, **sem
ejetar**.

---

## Sinais no diagnóstico

| Observação | Leitura |
|---|---|
| `VolumeFlags` com bit 1 setado | volume marcado como dirty — desmontagem suja |
| `PercentInUse` = `0xFF` | indisponível; contar o bitmap |
| `ValidDataLength` < `DataLength` | gravação interrompida naquele arquivo |
| soma do diretório == bitmap | **índice íntegro** |
| VBR principal ruim, backup bom | dano raso, conserto cirúrgico possível |
| nenhum `"EXFAT   "` em 2 GiB | índice perdido — carving |
| `BytesPerSectorShift` fora de 9–12 | VBR corrompido, não confiar nos outros campos |
