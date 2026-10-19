# Skills ZEL@I para audiovisual

Skills de [Claude Code](https://claude.com/claude-code) para quem trabalha com câmera.
Conhecimento que não está em manual, escrito a partir de casos reais.

> **Cartão que pede formatação quase nunca significa material perdido.**
> Significa, na maioria das vezes, que o índice do sistema de arquivos quebrou — e o
> índice costuma estar intacto. O caminho que a internet ensina (baixar um recuperador
> e mandar escanear) é justamente o que **destrói** os metadados que um `.insv` precisa
> para costurar o 360.

---

## Skills disponíveis

### [`resgate-de-midia`](skills/resgate-de-midia/)

Resgata vídeo e foto de cartão corrompido sem destruir o que o material precisa para
ser usado.

- **Triagem antes de tocar no cartão**: identifica a marca e a geração da câmera lendo a
  própria estrutura do cartão, confere espaço no destino, e **recusa seguir** se o
  destino estiver na própria origem
- **Lista de ações proibidas** — o que nunca executar, nem se pedido, e o que fazer em vez
- Diagnóstico do exFAT em **leitura pura** — zero escrita, zero espaço em disco
- A pergunta que decide tudo: **o índice ainda está lá?**
- Extração seguindo o índice, preservando o **trailer de metadados** que o carving joga fora
- Manual de procedimentos por marca e geração: **Insta360 ONE X → X6** e **Sony
  M4ROOT/XDROOT**, incluindo os arquivos `.rsv`
- **Diário de erros** que cresce a cada caso — inclusive os erros de quem escreveu a skill
- Conserto cirúrgico do boot sector para devolver o cartão ao uso
- Validação que decodifica frames no **início, meio e fim** — container que abre não é vídeo válido
- Modelos de relatório técnico e de comunicado ao cliente

### A detecção de câmera é automática

O cartão diz qual câmera o gravou, se souber onde olhar. A triagem lê a estrutura e
conclui:

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

**Cobre:** cartão RAW · "é preciso formatar o disco" · DCIM vazia · `.insv` que abre como
dois círculos · "stitching data lost" · "moov atom not found" · extração interrompida ·
arquivos `.rsv` da Sony

---

## O caso que gerou esta skill

Cartão de 128 GB de uma **Insta360 ONE X2** com as férias de um cliente. Extração
interrompida, cartão RAW, Windows pedindo formatação. Um mês de material.

O que o diagnóstico encontrou:

| Verificação | Resultado |
|---|---|
| Tabela de partição | **OK** |
| VBR exFAT principal | **íntegro** |
| FAT | **legível**, cadeias sequenciais |
| Diretório raiz | **percorrível** — 76 arquivos com nome, tamanho e data |
| Bitmap de alocação | 920.954 clusters = **112,42 GiB** |
| Soma das entradas de diretório | **112,42 GiB** — bate exatamente |

O volume era rejeitado por **103 bytes corrompidos** num setor de 512. Nada mais.

**Resultado: 43 de 43 arquivos, 95,84 GiB, 22 clipes, 2h17m de vídeo. Zero perdas.**
Tamanho idêntico ao índice do cartão nos 43, decodificação validada em três pontos de
cada arquivo, e o trailer de metadados presente nos 22 arquivos que precisavam dele.

Depois: **512 bytes** escritos devolveram o cartão ao funcionamento.

A imagem bit-a-bit, que o procedimento convencional exigiria, pediria 238 GiB. Havia
112. **Ler o índice primeiro foi a diferença entre fazer e não fazer.**

---

## Instalação

Clonar dentro da pasta de skills:

```bash
# pessoal (vale em todos os projetos)
git clone https://github.com/agenciazelai-droid/zelai-skills-audiovisual.git ~/.claude/skills-av
cp -r ~/.claude/skills-av/skills/* ~/.claude/skills/

# ou apenas uma skill
cp -r skills/resgate-de-midia ~/.claude/skills/
```

Reiniciar o Claude Code e conferir com `/skills`. A skill dispara sozinha quando você
descrever o problema — não precisa invocar.

Também funciona em **Codex**, **Gemini CLI**, **Cursor** e outros agentes que leem
`SKILL.md`.

---

## Estado dos scripts — leia antes de usar em material único

Honestidade sobre o que foi testado, porque aqui a diferença importa:

| Script | Plataforma | Estado |
|---|---|---|
| `00-triagem.ps1` | Windows | **testado** contra imagem exFAT: detectou marca e geração |
| `02-diagnostico-exfat.ps1` | Windows | **validado em cartão real** (128 GB, ONE X2) |
| `03-extrair.ps1` | Windows | **validado**: 43 arquivos, 95,84 GiB, zero falhas |
| `04-validar.ps1` | Windows | **validado** nos 43 arquivos |
| `05-diagnosticar-boot.ps1` | Windows | **validado**: localizou os 103 bytes |
| `06-consertar-boot.ps1` | Windows | **validado**: cartão voltou a montar |
| `01-criar-imagem.ps1` | Windows | lógica revisada, não exercitado em caso real |
| `00-triagem.sh` | macOS/Linux | **testado** contra imagem exFAT, mesma saída da versão Windows |
| `02-diagnostico-exfat.sh` | macOS/Linux | **parsing provado** contra imagem exFAT real |
| `03-extrair.sh` | macOS/Linux | **extração provada byte a byte**: 6/6 idênticos por SHA-256 |
| `04-validar.sh`, `05`, `06` | macOS/Linux | **ainda não escritos** |

Os scripts bash foram validados contra uma imagem exFAT construída para o teste, com
comparação SHA-256 entre origem e extraído. **O que não foi testado:** acesso a
`/dev/rdiskN` em hardware macOS real, `diskutil`, e diferenças entre as versões BSD e
GNU de `od` e `dd`. Revisar antes de rodar sobre material único.

Todo script de leitura abre o dispositivo em **somente leitura** e recusa rodar sobre o
disco do sistema ou sobre o disco de destino. O único que escreve no cartão é
`06-consertar-boot`, que exige duas flags explícitas e salva os setores originais antes.

---

## Antes de qualquer coisa, se você chegou aqui com um cartão na mão

1. **Recuse o "verificar e reparar a unidade"** do Windows, e os Primeiros Socorros do
   macOS. O `chkdsk` e o `fsck` **escrevem no cartão** e destroem as cadeias que a
   recuperação usa. É o único passo sem volta.
2. **Não devolva o cartão à câmera.**
3. **Não formate**, nem "só para a câmera reconhecer".
4. Rode o diagnóstico de leitura antes de escolher qualquer ferramenta.

---

## Contribuir

Falta cobertura de **ARRI**, **RED**, **Blackmagic**, **Canon** e **DJI**, e os scripts
`04` a `06` em bash. Quem tiver um cartão dessas câmeras para mapear a estrutura ajuda
muito — ver [CONTRIBUTING.md](CONTRIBUTING.md).

A regra para contribuição técnica: **separar o que foi verificado em campo do que veio
de documentação.** Os documentos marcam isso explicitamente, e a distinção é o que
torna a skill confiável.

---

## Licença

[MIT](LICENSE). Use, modifique, venda, inclua no seu fluxo. Se salvar o material de
alguém, conta uma cerveja.

---

## English summary

**Claude Code skills for camera work, in Portuguese.**

A memory card asking to be formatted rarely means lost footage — it usually means the
filesystem index broke, and the index is often intact. The common advice (run a recovery
tool and let it scan) destroys the metadata trailer that 360 footage needs to stitch.

`resgate-de-midia` covers: read-only exFAT diagnosis, index-based extraction preserving
the vendor metadata trailer, per-model knowledge for **Insta360 ONE X through X6** and
**Sony M4ROOT/XDROOT**, surgical boot-sector repair, and validation that decodes frames
at start, middle and end.

Born from a real case: a 128 GB Insta360 ONE X2 card, RAW and unreadable, with **103
corrupted bytes** in a single 512-byte sector locking 112 GiB of perfectly intact data.
**43 of 43 files recovered, 95,84 GiB, zero loss** — then 512 bytes written to bring the
card back to life.

Skill content is Portuguese; trigger phrases work in both Portuguese and English.
PowerShell scripts validated on real hardware; bash scripts proven byte-for-byte against
a purpose-built exFAT image, but **not yet exercised on macOS device nodes**.
