# Ferramentas — qual usar, quando, e o que cada uma estraga

Catálogo com o que cada ferramenta faz **e o que ela destrói**. A segunda coluna é a que
costuma faltar na internet.

---

## Leitura e diagnóstico

### TestDisk / PhotoRec (CGSecurity, GPL)

Duas ferramentas no mesmo pacote, com propósitos opostos.

**TestDisk** recupera **estrutura**: tabela de partição, boot sector, e tem o modo
`Advanced → List → Copy`, que lista e copia arquivos pelo índice — preservando nomes e
pastas. Também cria imagem de disco por `Image Creation`.

**PhotoRec** faz **carving por assinatura**: ignora o índice e varre o dispositivo
procurando cabeçalhos conhecidos.

| | TestDisk (List/Copy) | PhotoRec |
|---|---|---|
| Preserva nome e pasta | **sim** | não |
| Preserva data | sim | não |
| Preserva arquivo completo | sim | pode truncar |
| Funciona sem índice | não | **sim** |
| Escreve na origem | não | não |

**Tentar TestDisk antes do PhotoRec, sempre.** A ordem inversa é o erro mais comum.

**Fato verificado:** o PhotoRec 7.2 **não conhece a assinatura `.insv`** — zero
ocorrências da string no binário. Vídeos Insta360 saem como `.mov`/`.mp4`. Renomear
depois. Sem saber disso, a varredura parece não ter achado nada.

- Download: `cgsecurity.org` — a URL `Download_and_donate.php/arquivo.zip` entrega uma
  página HTML, não o zip. O link direto é `https://www.cgsecurity.org/arquivo.zip`.
- Portátil, sem instalação. **Exige elevação.**
- Versões: 7.2 estável, 7.3-WIP com mais assinaturas.

### ddrescue (GNU) e HDDSuperClone

Para imagem de mídia com **setores defeituosos**. Têm releitura com estratégia e mapa de
progresso que permite retomar. Um `dd` simples desiste no primeiro erro.

Usar quando o diagnóstico registrar erros de leitura. Para dano puramente lógico, não
são necessários.

---

## Reparo de container

### Insta360 File Repair (oficial, gratuito)

v1.1, 29/12/2024. Windows e macOS. Suporta ONE X, X2, X3, X4, X4 Air, X5, X6.

**Resolve:** `.insv`/`.mp4` com "stitching data lost", ou que abre como dois panoramas
esféricos no Studio.

**Não resolve:** nada que esteja no cartão. Só atua em arquivo já copiado inteiro.

**Limite declarado pelo fabricante:** se giroscópio e som estiverem danificados, o
reparo não é completo.

Download na página de downloads da Insta360, ao fim da página. O site responde **HTTP
403 a download automatizado** — baixar pelo navegador.

### anthwlock/untrunc (GPL-2.0)

Reconstrói o `moov atom` de MP4/MOV/3GP truncado, usando um arquivo **de referência**
saudável.

```bash
untrunc referencia.mp4 quebrado.mp4     # gera quebrado_fixed.mp4
```

- **Exige** referência da mesma câmera, mesmo modo e mesma resolução. Não precisa ter a
  mesma duração nem o mesmo conteúdo.
- **A referência é gratuita:** gravar um clipe de 30 segundos com a mesma câmera, em
  outro cartão.
- Binários Windows prontos nos releases. Suporte específico a GoPro e Sony XAVC.
- Para `.insv`, renomear para `.mp4` antes.
- FFmpeg acima de 8.1 pode causar incompatibilidade de estrutura.

### kichiki/finsta360 (GPL-3.0, Python)

Finaliza MP4 incompleto de Insta360, regenerando as tabelas de amostra de H264/AAC e
reconstruindo o `moov` a partir de referência.

```bash
./finsta360 -s corrompido.mp4 -r referencia.mp4 -o saida.mp4
```

Testado no ONE X. Plano B do untrunc.

### alex-plekhanov/insvtools (Apache-2.0, Java)

Manipula os metadados do `.insv`: `dump-meta`, `extract-meta`, **`replace-meta`**,
`compose-meta`, `remove-meta`.

Uso na recuperação: **transplantar o trailer de metadados** de um clipe bom para um
recuperado que perdeu o seu. Requer JDK 8+ e Maven.

### ke4ukz/insvtool

Só diagnóstico: despeja metadados de `.insv`.

### GHSLAB/Vision360-Toolbox

Converte `.insv` e extrai GPS usando o SDK oficial da Insta360 + ExifTool. Confirmado
em Linux Debian; outras plataformas não testadas.

---

## Remontagem de fragmentos

### seungwoochoe/insta360-footage-recovery (MIT, Python 3.9+)

Reconstrói `.insv` **fragmentado** seguindo as cadeias exFAT residuais, a partir dos
inícios que o PhotoRec encontrou. Usa os offsets embutidos nos nomes gerados pelo
PhotoRec para remontar na ordem correta.

Fluxo: PhotoRec → inventário exFAT → mapeamento de cadeias órfãs → extração → validação
com FFmpeg.

**Ressalvas:** poucos commits, escrito para um cartão específico de GO Ultra, roda em
macOS/Unix. **É código de referência para adaptar, não produto.** Mas o método é o
correto para o problema.

---

## Validação

### ffmpeg / ffprobe

Indispensável e insubstituível no fim do processo.

```bash
# estrutura do container
ffprobe -v error -print_format json -show_format -show_streams arquivo.insv

# decodificar um frame em t segundos (vale o código de saída)
ffmpeg -v error -ss <t> -i arquivo.insv -frames:v 1 -f null -
```

**Container que abre não é vídeo válido.** Decodificar no **início, meio e fim** — um
arquivo truncado abre, informa a duração original e falha só no fim.

Builds Windows: `gyan.dev/ffmpeg/builds` (`ffmpeg-release-essentials.zip`), portátil.

### exiftool

Lê metadados de `.insv`/`.insp`. Útil para conferir modelo de câmera e configuração de
gravação quando o nome do arquivo não basta.

---

## Serviços pagos — a rede de segurança

Quando o caminho livre falha, e para material de cliente, vale ter na manga:

| Serviço | O que faz |
|---|---|
| **restore.media** | repara header de vídeo online; suporta `.insv`; recupera GPS |
| **Disk Drill** (Advanced Camera Recovery) | remonta clipes fragmentados; cita Insta360 por nome |
| **rsv.repair** | reconstrói `.rsv` Sony em `.MXF` finalizado |
| **Rescue Digital Media** | serviço humano, análise caso a caso |
| Suporte oficial Insta360 | atendimento 24/7; aceita envio de arquivo para análise |

Para material único de cliente, apresentar essa opção **antes** de esgotar tentativas
que podem piorar o estado.

---

## O que NÃO usar

| Ferramenta | Por quê |
|---|---|
| `chkdsk` / "Reparar unidade" do Windows | **escreve no cartão** e destrói as cadeias FAT residuais. O único passo irreversível do processo |
| `fsck` / "First Aid" do Disk Utility | o mesmo, no macOS |
| Formatação rápida "para a câmera reconhecer" | reescreve o índice |
| Recuperadores que escrevem no disco de origem | qualquer ferramenta sem modo somente-leitura explícito |
| Recuperador rodando direto no cartão sem diagnóstico | pode entregar carving quando a extração pelo índice estava disponível |

Quando o cliente pergunta "posso só clicar em reparar?", a resposta é não — e vale
explicar por quê: o reparo conserta o sistema de arquivos sacrificando o que sobrou do
mapa dos arquivos.

---

## Disponibilidade por sistema

| Ferramenta | Windows | macOS | Linux |
|---|---|---|---|
| TestDisk / PhotoRec | sim | sim | sim |
| untrunc | binário pronto | compilar | compilar |
| Insta360 File Repair | sim | sim | não |
| finsta360 | Python | Python | Python |
| insvtools | JDK | JDK | JDK |
| ddrescue | via WSL/Cygwin | Homebrew | nativo |
| ffmpeg | sim | sim | sim |

Os scripts desta skill não dependem de Python nem de Java: PowerShell no Windows, bash
com ferramentas nativas no macOS.
