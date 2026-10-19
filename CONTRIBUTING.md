# Como contribuir

Este repositório trata de material que muitas vezes é único e insubstituível. Por isso
tem uma regra acima de todas as outras.

## A regra que não se negocia

**Separar o que foi verificado em campo do que veio de documentação.**

Todo documento marca isso explicitamente. Um procedimento que parece certo e não foi
testado, apresentado como testado, custa o material de alguém.

Como marcar:

```markdown
> **Procedência:** verificado em cartão real de [modelo], [data].

> **Procedência:** documentação do fabricante, não verificado em campo.
> Conferir antes de agir sobre material único.
```

E quando a documentação oficial estiver errada, dizer isso com a evidência. O manual do
ONE X2 afirma que o arquivo master contém as duas lentes — não contém, e a prova está
em `references/insta360-linha-x.md`.

## Faltando cobertura

Quem tem acesso ao hardware ajuda mais que quem tem acesso ao manual:

- **ARRI** (ALEXA, AMIRA) — estrutura de cartão, MXF/ARRIRAW
- **RED** (KOMODO, V-RAPTOR) — `.R3D`, estrutura `.RDC`
- **Blackmagic** — BRAW, estrutura de cartão
- **Canon** — Cinema RAW Light, XF-AVC, `CONTENTS/CLIPS`
- **DJI** — Osmo Action, Pocket, Avata
- **GoPro** — `.LRV`/`.THM`, chaptering de arquivos acima de 4 GB

Para cada um, o que realmente importa:

1. Árvore de pastas completa, a partir da raiz do cartão
2. Quantos arquivos formam **um** clipe, e quais são indispensáveis
3. Onde ficam os metadados — dentro do arquivo ou num `.xml`/`.json` ao lado
4. Como a câmera se comporta quando a gravação é interrompida
5. Se o PhotoRec reconhece a extensão por assinatura (no caso do `.insv`, **não**)

O item 4 é o mais valioso e o menos documentado. A Sony deixa um `.rsv`; outras marcas
fazem outra coisa. Saber disso evita apagar o material pensando que é lixo.

## Scripts faltando

Em bash, para macOS e Linux: `04-validar.sh`, `05-diagnosticar-boot.sh`,
`06-consertar-boot.sh`. As versões PowerShell servem de especificação.

### Exigências para script que toca disco

| Exigência | Por quê |
|---|---|
| Abrir em **somente leitura**, salvo quando escrever for o propósito declarado | o cartão é a única cópia |
| Recusar o disco do sistema e o disco de destino | dois discos do mesmo tamanho são indistinguíveis por tamanho |
| Modo de simulação que **prova** a operação antes de executar | o conserto de boot recalcula o checksum em memória primeiro |
| Escrever em `.parcial` e renomear só após conferir o tamanho | arquivo truncado não pode parecer pronto |
| Permitir retomar | extração de 100 GB é interrompida na vida real |
| Registrar relatório mesmo em caso de erro | gravar o log no `finally`/`trap` |
| Nenhuma dependência de Python ou Java | quem está com o cartão na mão não vai instalar runtime |

### Verificação não pode falhar em silêncio

O pior bug possível aqui é um verificador que aprova sem ter verificado. Aconteceu neste
repositório: `[math]::Min(128KB, $arquivo.Length)` estoura acima de 2 GiB, e com erro
suprimido o script seguiu com a variável do laço anterior — **o relatório disse "43
válidos"** sem ter conferido os arquivos grandes.

Preferir erro fatal a erro suprimido. Validar que cada leitura devolveu o que foi
pedido. Ver `references/armadilhas-powershell.md`.

## Testar sem hardware

Dá para validar a lógica inteira contra uma imagem exFAT construída para o teste. Foi
assim que os scripts bash deste repositório foram provados:

```powershell
# Windows: cria um VHD fixo, formata em exFAT, povoa
diskpart   # create vdisk file="teste.vhd" maximum=400 type=fixed
           # attach vdisk / convert mbr / create partition primary
           # format fs=exfat quick / assign letter=Y
```

```bash
# o VHD fixo começa no setor 0, então serve como imagem de disco
./02-diagnostico-exfat.sh teste.vhd
./03-extrair.sh teste.vhd ./saida
```

Depois, **comparar SHA-256** entre os arquivos de dentro da imagem montada e os
extraídos. Tamanho igual não prova conteúdo igual. Foi essa comparação que provou o
extrator bash: 6 de 6 idênticos.

## Escrevendo conteúdo de skill

- `SKILL.md` enxuto, 1.500 a 2.000 palavras. Detalhe vai para `references/`.
- Forma **imperativa**: "Ler o índice antes de escolher ferramenta" — não "você deve ler".
- A `description` do frontmatter é o que faz a skill disparar. Terceira pessoa, com
  **frases-gatilho literais**, em português e inglês. Descrição vaga = skill que nunca roda.
- Incluir também como a pessoa descreve o problema **sem** usar o termo técnico: "o
  cartão do cliente deu problema na hora de copiar".

## Abrindo um PR

1. Diga o que foi verificado em hardware e o que não foi
2. Inclua a saída real dos comandos, não só a descrição
3. Para estrutura de cartão nova, inclua a árvore de pastas completa
4. Para script novo, inclua o resultado do teste contra imagem

Caso de recuperação que deu errado também interessa, e muito. Saber que um caminho não
funciona economiza o material do próximo.
