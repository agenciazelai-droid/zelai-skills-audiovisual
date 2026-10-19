# Relatório técnico de recuperação — modelo

Registro do que foi feito, com números verificáveis. Serve para três coisas: provar o
resultado, permitir que outra pessoa continue o trabalho, e virar histórico se o caso
voltar.

Preencher os campos entre `[ ]`. Manter os números exatos em bytes — "mais ou menos
7 GB" não permite conferir nada depois.

---

# Recuperação — [IDENTIFICAÇÃO DO CASO]

**Data:** [AAAA-MM-DD]
**Operador:** [NOME]
**Origem:** [modelo da câmera] · cartão [CAPACIDADE] · [MARCA/MODELO do cartão]
**Material:** [CLIENTE / PROJETO]

## Sintoma relatado

[Nas palavras de quem trouxe o cartão.]

## Histórico antes da intervenção

Importante porque define o que ainda é possível:

- [ ] O cartão voltou à câmera depois do problema
- [ ] Rodou `chkdsk` / "reparar unidade" / Primeiros Socorros
- [ ] Algum recuperador foi executado — qual: [ ]
- [ ] Houve formatação (rápida ou completa)
- [ ] Nada foi feito: o cartão ficou parado

## Identificação do dispositivo

| | |
|---|---|
| Disco | `[/dev/rdiskN ou PhysicalDriveN]` |
| Modelo reportado | `[string exata]` |
| Tamanho | `[N] bytes ([N] GiB)` |
| Barramento | [USB / interno] |
| Volume montado | [letra ou ponto de montagem] · tipo relatado: [exFAT / RAW / Unknown] |

## Diagnóstico (somente leitura)

| Verificação | Resultado |
|---|---|
| Tabela de partição | [OK / ausente / tipo] |
| VBR exFAT | [principal válido / só backup / não encontrado] |
| Checksum da região de boot | principal `0x[ ]` gravado vs `0x[ ]` calculado · backup `0x[ ]` vs `0x[ ]` |
| VolumeFlags | `0x[ ]` [dirty? ] |
| FAT | [legível / ilegível] · cadeias [sequenciais / fragmentadas] |
| Diretório raiz | [N] pastas, [N] arquivos |
| Bitmap de alocação | [N] de [N] clusters em uso = **[N] GiB** |
| Soma das entradas de diretório | **[N] GiB** |
| **Os dois números coincidem?** | **[sim / não]** ← decide o caminho |
| `PercentInUse` | [N]% |

**Conclusão do diagnóstico:** [uma frase. Ex.: "índice íntegro; o volume é rejeitado pelo
sistema por checksum de boot inconsistente".]

## Caminho escolhido

- [ ] A — extração pelo índice
- [ ] B — imagem bit-a-bit, depois extração
- [ ] C — carving por assinatura
- [ ] D — reparo de container
- [ ] E — conserto do cartão (após segunda cópia)

**Justificativa:** [por que este e não outro.]

## Inventário da origem

| Papel | Arquivos | Bytes | GiB |
|---|---|---|---|
| Masters | | | |
| Proxies (LRV / Sub) | | | |
| Auxiliares (miniaturas, XML, índice) | | | |
| **Total** | | | |

Modelo de câmera e implicação: [ex.: "ONE X2 — clipes 360 em pares `_00_`/`_10_`; ambos
obrigatórios"].

Pares completos: [N] de [N]. Órfãos: [listar ou "nenhum"].

## Extração

| | |
|---|---|
| Ferramenta | [script / versão] |
| Destino | [caminho] |
| Extraídos | [N] de [N] |
| Volume | [N] bytes ([N] GiB) |
| Duração | [HH:MM:SS] a ~[N] MB/s |
| Falhas | [N] |
| Escrita na origem | **nenhuma** |

Arquivos que falharam: [listar com motivo, ou "nenhum"].

## Validação

| Verificação | Resultado |
|---|---|
| Tamanho conferido contra o índice | [N] de [N] idênticos |
| Container legível (`ffprobe`) | [N] de [N] |
| Decodificação início / meio / fim | [N] de [N] |
| Trailer de metadados do fabricante | [N] de [N] onde era esperado |
| Resolução e codec conforme o modelo | [sim / divergências] |

Material entregável: **[N] clipes, [DURAÇÃO] total**.

Especificações observadas: [ex.: "h264 2880×2880 por lente, 29,97 fps, AAC 48 kHz
estéreo"].

## Cópias existentes ao fim do trabalho

| Local | Conteúdo | Verificado |
|---|---|---|
| | | |

> Material em um único lugar não é entrega concluída.

## Conserto do cartão

- [ ] Não realizado — motivo: [ ]
- [ ] Realizado em [DATA], após a segunda cópia existir

| | |
|---|---|
| Dano localizado | [ex.: 103 bytes no setor 1 da região de boot principal] |
| Correção aplicada | [ex.: cópia do setor 1 da região de backup] |
| Bytes escritos | [N] |
| Backup dos setores originais | [caminho do arquivo] |
| Conferência pós-escrita | checksum `0x[ ]` gravado = `0x[ ]` calculado |
| Estado final do volume | [ex.: exFAT, ReadWrite, [N] arquivos acessíveis] |

## Causa provável

[ex.: "remoção do cartão durante escrita, provavelmente na extração interrompida".]

## Recomendações entregues ao cliente

- [ ]

## Observações para quem pegar este caso depois

[Qualquer coisa que economizaria tempo: armadilha encontrada, ferramenta que não
funcionou, comportamento estranho do hardware.]
