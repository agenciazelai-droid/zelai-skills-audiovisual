# Skills ZEL@I para audiovisual

Conhecimento de recuperação de material de câmera, empacotado para agentes de IA.
Escrito a partir de casos reais, com o que foi verificado separado do que veio de manual.

---

## 🚨 Se você chegou aqui com um cartão corrompido agora

**Pare e leia estas quatro linhas antes de qualquer outra coisa.** Elas valem mais que o
resto do repositório:

1. **Recuse o "verificar e reparar a unidade"** do Windows, e os "Primeiros Socorros" do
   macOS. O `chkdsk` e o `fsck` **escrevem no cartão** e destroem o que a recuperação
   usa. É o único passo sem volta deste processo.
2. **Não coloque o cartão de volta na câmera.** Ela pode reescrever o índice e renumerar
   os arquivos.
3. **Não formate**, nem "só para a câmera reconhecer".
4. **Tire o cartão do leitor e guarde.** Material parado não piora. Um cartão que pede
   formatação quase nunca significa material perdido — significa que o índice quebrou, e
   o índice costuma estar intacto.

Em um caso real documentado aqui, **103 bytes corrompidos** num setor de 512 trancaram
**112 GiB** de vídeo perfeitamente íntegro.

---

## O que é isso, exatamente

Uma **skill** é uma pasta com instruções e scripts que um agente de IA — [Claude
Code](https://claude.com/claude-code), Codex, Gemini CLI, Cursor — carrega quando o
assunto aparece na conversa. Não é um programa que você abre: é conhecimento que o
agente passa a ter.

Na prática, você instala a pasta, abre o terminal e escreve:

> *"o cartão da minha Insta360 pede para formatar e tem o material do cliente dentro"*

A partir daí o agente conduz: faz a triagem, identifica a câmera, confere espaço,
diagnostica o cartão em leitura pura, extrai o material para onde você escolher e valida
o resultado — recusando os comandos que destroem material, mesmo se você pedir.

**Pré-requisito:** um desses agentes instalado. Se você não usa nenhum, os scripts em
`skills/resgate-de-midia/scripts/` funcionam sozinhos, na mão, pelo terminal — o
`SKILL.md` serve como o procedimento escrito.

---

## O que esta skill cobre

### `resgate-de-midia`

| Cobre | Não cobre |
|---|---|
| **Insta360** ONE X, ONE X2, X3, X4, X4 Air, X5, X6 | ARRI, RED, Blackmagic, Canon, DJI |
| **Sony** A7, FX3, FX30, ZV (`M4ROOT`) e FX6, FX9, PXW, VENICE (`XDROOT`) | cartões em NTFS ou HFS+ |
| Qualquer cartão **exFAT** (padrão acima de 32 GB) | dano **físico** — cartão que nem é reconhecido |
| GoPro e DSLR, parcialmente | recuperação de SSD ou HD |

**Sintomas atendidos:** cartão RAW · "é preciso formatar o disco" · pasta DCIM vazia ·
`.insv` que abre como dois círculos de peixe-olho · "stitching data lost" · "moov atom
not found" · extração interrompida · arquivos `.rsv` da Sony.

### O que ela faz de diferente

- **Triagem antes de tocar no cartão** — identifica a marca e a geração da câmera lendo
  a própria estrutura do cartão, confere o espaço no destino, e **recusa seguir se o
  destino estiver na própria origem**
- **Lista de ações proibidas** — o que nunca executar, nem se pedido, e o que fazer em vez
- **Extração pelo índice**, preservando o **trailer de metadados** que o carving joga
  fora — é o que decide se um `.insv` costura o 360 ou não
- **Diário de erros** que cresce a cada caso, incluindo os erros de quem escreveu a skill
- **Validação que decodifica frames no início, meio e fim** — container que abre não é
  vídeo válido

### A detecção de câmera é automática

O cartão diz qual câmera o gravou, se souber onde olhar:

```
--- Quem gravou este cartao ---
  Marca   : INSTA360
  Geracao : ONE X2 - LRV com extensao .insv confirma esta geracao

  * CRITICO: 2 clipe(s) em par _00_/_10_. Os dois arquivos do par sao obrigatorios;
  * recuperar so um lado entrega clipe que NAO costura o 360.
```

`M4ROOT` → Sony híbrida · `XDROOT` → Sony profissional · pares `_00_`/`_10_` → Insta360
até o X3 · um `.insv` só → X4 em diante · LRV `.insv` → ONE X2 · LRV `.lrv` → X3+ ·
`.rsv` presente → gravação Sony interrompida, **não apagar**.

---

## Instalação

```bash
# pessoal, vale em todos os projetos
git clone https://github.com/agenciazelai-droid/zelai-skills-audiovisual.git
cp -r zelai-skills-audiovisual/skills/resgate-de-midia ~/.claude/skills/
```

```powershell
# Windows
git clone https://github.com/agenciazelai-droid/zelai-skills-audiovisual.git
Copy-Item -Recurse zelai-skills-audiovisual\skills\resgate-de-midia "$env:USERPROFILE\.claude\skills\"
```

Reinicie o agente e confira com `/skills`. A skill dispara sozinha quando você descrever
o problema — não precisa invocar nem decorar comando.

**Os scripts exigem privilégio** para ler o cartão em modo bruto: PowerShell **como
administrador** no Windows, `sudo` no macOS e Linux. Sem isso, dá "acesso negado" — que
parece defeito de hardware e não é.

---

## ⚠️ Estado dos scripts — leia antes de usar em material único

Aqui a diferença entre "testado" e "deve funcionar" pode custar o material de alguém,
então está declarada arquivo por arquivo:

| Script | Plataforma | Estado |
|---|---|---|
| `00-triagem.ps1` | Windows | **testado** contra imagem exFAT: detectou marca e geração |
| `02-diagnostico-exfat.ps1` | Windows | **validado em cartão real** (128 GB, ONE X2) |
| `03-extrair.ps1` | Windows | **validado**: 43 arquivos, 95,84 GiB, zero falhas |
| `04-validar.ps1` | Windows | **validado** nos 43 arquivos |
| `05-diagnosticar-boot.ps1` | Windows | **validado**: localizou os 103 bytes corrompidos |
| `06-consertar-boot.ps1` | Windows | **validado**: o cartão voltou a montar |
| `01-criar-imagem.ps1` | Windows | lógica revisada, **não exercitado** em caso real |
| `00-triagem.sh` | macOS/Linux | **testado** contra imagem exFAT, mesma saída da versão Windows |
| `02-diagnostico-exfat.sh` | macOS/Linux | **parsing provado** contra imagem exFAT real |
| `03-extrair.sh` | macOS/Linux | **extração provada byte a byte**: 6/6 idênticos por SHA-256 |
| `04-validar.sh`, `05`, `06` | macOS/Linux | **não existem ainda** |

**Para quem está no macOS:** os scripts bash foram provados contra uma imagem exFAT
construída para o teste, com comparação SHA-256 entre origem e extraído. Mas **nunca
rodaram sobre um dispositivo de verdade num Mac** — `/dev/rdiskN`, `diskutil`, e as
diferenças entre `od`/`dd` do BSD e do GNU seguem sem teste. Se o material for único e
você está no macOS: use a parte de diagnóstico, leia o `SKILL.md` como procedimento, e
revise os scripts antes de confiar neles.

**Todo script de leitura abre o dispositivo em somente leitura** e recusa rodar sobre o
disco do sistema ou sobre o disco de destino. O único que escreve no cartão é
`06-consertar-boot`, que exige duas flags explícitas, prova a correção em memória antes,
e salva os setores originais para poder desfazer.

---

## O caso que gerou esta skill

Cartão de 128 GB de uma **Insta360 ONE X2** com as férias de um cliente. Extração
interrompida, cartão RAW, Windows pedindo formatação. Um mês de material.

| Verificação | Resultado |
|---|---|
| Tabela de partição | **OK** |
| VBR exFAT principal | **íntegro** |
| FAT | **legível**, cadeias sequenciais |
| Diretório raiz | **percorrível** — 76 arquivos com nome, tamanho e data |
| Bitmap de alocação | 920.954 clusters = **112,42 GiB** |
| Soma das entradas de diretório | **112,42 GiB** — bate exatamente |

A coincidência entre dois caminhos independentes de medição é a prova de que o índice
estava inteiro. O volume era rejeitado por **103 bytes corrompidos** num setor de 512.

**Resultado: 43 de 43 arquivos, 95,84 GiB, 22 clipes, 2h17m de vídeo. Zero perdas.**
Depois, **512 bytes** escritos devolveram o cartão ao funcionamento.

A imagem bit-a-bit que o procedimento convencional exigiria pediria 238 GiB. Havia 112.
**Ler o índice primeiro foi a diferença entre fazer e não fazer.**

---

## Estrutura do repositório

```
skills/resgate-de-midia/
├── SKILL.md                      procedimento, ações proibidas, protocolo de parada
├── references/
│   ├── licoes-de-campo.md        o diário de erros — leitura obrigatória
│   ├── insta360-linha-x.md       manual ONE X → X6, modelo por modelo
│   ├── sony.md                   M4ROOT, XDROOT, XAVC, arquivos .rsv
│   ├── triagem.md                as 7 perguntas e o que cada resposta muda
│   ├── escolher-caminho.md       índice × imagem × carving × reparo
│   ├── exfat.md                  estrutura, checksum de boot, onde o dano mora
│   ├── ferramentas.md            o que cada ferramenta faz e o que estraga
│   └── armadilhas-powershell.md  erros que fazem a verificação mentir
├── scripts/windows/              7 scripts PowerShell
├── scripts/mac/                  3 scripts bash
└── templates/                    relatório técnico e comunicado ao cliente
```

---

## Contribuir

Falta cobertura de **ARRI**, **RED**, **Blackmagic**, **Canon** e **DJI**, e os scripts
`04` a `06` em bash. Quem tiver um cartão dessas câmeras para mapear a estrutura ajuda
muito — ver [CONTRIBUTING.md](CONTRIBUTING.md).

A regra para contribuição técnica: **separar o que foi verificado em campo do que veio
de documentação.** Os documentos marcam isso explicitamente, e essa distinção é o que
torna a skill confiável. Caso de recuperação que **deu errado** também interessa, e
muito: saber que um caminho não funciona economiza o material do próximo.

---

## Licença

[MIT](LICENSE). Use, modifique, venda, inclua no seu fluxo. Se salvar o material de
alguém, conta uma cerveja.

---

## English summary

**AI agent skills for camera work. Content in Portuguese; trigger phrases work in both
Portuguese and English.**

A memory card asking to be formatted rarely means lost footage — it usually means the
filesystem index broke, and the index is often intact. The common advice (run a recovery
tool and let it scan) destroys the metadata trailer that 360 footage needs to stitch.

**If you arrived here with a corrupted card: do not run `chkdsk`, `fsck`, or "repair
drive". They write to the card and destroy what recovery needs. Do not put the card back
in the camera. Do not format.**

`resgate-de-midia` covers read-only exFAT diagnosis, automatic camera identification
from card structure, index-based extraction preserving the vendor metadata trailer,
per-model knowledge for **Insta360 ONE X through X6** and **Sony M4ROOT/XDROOT**,
surgical boot-sector repair, and validation that decodes frames at start, middle and end.
It also ships a list of forbidden actions the agent refuses to run, and a field-error log
that grows with each case.

Born from a real case: a 128 GB Insta360 ONE X2 card, RAW and unreadable, with **103
corrupted bytes** in a single 512-byte sector locking 112 GiB of perfectly intact data.
**43 of 43 files recovered, 95.84 GiB, zero loss** — then 512 bytes written to bring the
card back to life.

PowerShell scripts validated on real hardware. Bash scripts proven byte-for-byte against
a purpose-built exFAT image, but **not yet exercised on macOS device nodes** — review
before trusting them with irreplaceable material.
