# Lições de campo — o diário de erros

Este arquivo cresce a cada caso. Não é documentação: é a lista do que já deu errado, com
o que custou e o que mudou por causa disso.

**Ler antes de operar.** A maioria destes erros não dá mensagem de erro — alguns fazem o
relatório ficar **verde** enquanto nada foi verificado. Esses são os piores, porque o
operador entrega material não conferido ao cliente acreditando que conferiu.

Formato de cada entrada: **o que aconteceu → o que custou → a regra que nasceu disso.**

---

## Parte 1 — Erros de quem opera o cartão

### L01 · Remoção do cartão durante escrita

**O que aconteceu:** cliente interrompeu a extração dos arquivos e removeu o cartão.
Resultado: 103 bytes corrompidos num setor de 512, dentro da região de boot do exFAT.

**O que custou:** 112,42 GiB inacessíveis. O Windows passou a pedir formatação. Um mês de
material de férias parecia perdido.

**A regra:** ejetar sempre pelo sistema operacional, nos dois sistemas. A quantidade de
dado corrompido foi ridícula — 103 bytes — e o efeito foi total, porque o driver valida
um checksum e rejeita o volume inteiro quando ele não bate.

### L02 · Devolver o cartão à câmera para "tentar ler"

**O que aconteceu:** o cartão voltou à câmera para ver se ela abria. Não abriu.

**O que custou:** nada, por sorte. A câmera não conseguiu montar e por isso não
reescreveu nada.

**A regra:** não é sorte que se repete. A câmera que **consegue** montar um cartão com
índice danificado pode reescrever o índice e renumerar arquivos — e aí material que
estava recuperável pelo índice passa a exigir carving. Em caso documentado de GO Ultra,
exatamente isso aconteceu: a câmera renumerou tudo a partir de `001`.

### L03 · Material em cópia única

**O que aconteceu:** 95,84 GiB recuperados ficaram num único SSD de 119 GiB.

**O que custou:** nada ainda. Mas é o mesmo risco que originou o caso.

**A regra:** recuperação não está concluída enquanto o material existir em um só lugar.
Enquanto a segunda cópia não existe, **nenhuma escrita no cartão** — nem o conserto.

---

## Parte 2 — Erros de quem escreve o código

Estes são os mais importantes desta skill, porque um verificador que mente é pior que
não ter verificador.

### L04 · O literal que virou número negativo

**O que aconteceu:** `if ($prox -ge 0xFFFFFFF7)` para detectar o fim de uma cadeia na FAT.
No PowerShell 5.1, `0xFFFFFFF7` é `Int32` com overflow e vale **-9**. Toda comparação dava
verdadeiro.

**O que custou:** toda cadeia de clusters terminava no primeiro elemento. O diagnóstico
disse "1 de 57404 clusters" em todos os arquivos — e isso **parecia dano severo no
cartão**. Por alguns minutos, a conclusão correta era "irrecuperável pelo índice, partir
para carving".

**A regra:** quando o diagnóstico aponta dano uniforme em 100% dos arquivos, suspeitar
do código antes do cartão. Dano real é irregular. O que salvou foi uma verificação
cruzada: o bitmap de alocação concordava com a soma do diretório, e isso é incompatível
com uma FAT destruída.

### L05 · A verificação que ficou verde sem verificar

**O que aconteceu:** `[math]::Min(128KB, $arquivo.Length)` casa a sobrecarga `Int32` e
estoura em arquivo acima de 2 GiB. Com `$ErrorActionPreference = 'Continue'`, o script
seguiu reusando a variável do laço anterior.

**O que custou:** o relatório de validação declarou **"43 válidos, 0 com problema"** sem
ter conferido o trailer de metadados dos arquivos grandes — que são justamente os
arquivos de vídeo. A contagem de trailers saiu errada (20 em vez de 22) e só foi notada
porque o número **não fechava com a aritmética esperada**.

**A regra, e é a mais importante deste arquivo:** num script de verificação, **erro
suprimido é pior que erro fatal**. Validar que cada leitura devolveu o que foi pedido.
E sempre que um número de verificação não fechar com a conta esperada, **parar e
investigar** — não arredondar a explicação.

### L06 · A guarda de segurança que abortaria sempre

**O que aconteceu:** ao generalizar os scripts para publicação, a guarda que recusa o
disco errado virou `$disco.FriendlyName -match $ModeloProtegido -and $ModeloProtegido -ne ''`
— mas o parâmetro `$ModeloProtegido` não existia no bloco `param`. Em PowerShell,
`$null -ne ''` é **verdadeiro**, e `-match $null` casa com tudo.

**O que custou:** nada, porque foi detectado antes de rodar. Rodaria abortando **todo
script, sempre**.

**A regra:** guarda de segurança precisa ser testada nos dois sentidos — que ela dispara
quando deve **e que não dispara quando não deve**. Guarda que sempre barra é tão inútil
quanto guarda que nunca barra, e dá a falsa impressão de proteção.

### L07 · Confiar no manual do fabricante

**O que aconteceu:** o manual oficial do Insta360 ONE X2 afirma que o arquivo master
`_00_` contém as duas lentes. Com base nisso, a primeira análise do cartão afirmou o
mesmo ao operador.

**O que custou:** uma afirmação errada entregue. Os dados reais mostram **dois arquivos
por clipe**, um por lente, com 2880×2880 cada.

**A regra:** quando houver dado de campo, ele vence o manual. E a diferença aqui não é
acadêmica: na geração ONE X/X2/X3, recuperar metade do par entrega um clipe que **não
costura**. Um operador que confiasse no manual poderia descartar os arquivos `_10_` como
redundantes.

### L08 · O alarme falso que quase virou laudo de perda

**O que aconteceu:** o validador acusou "metadados Insta360 ausentes" em 21 arquivos.

**O que custou:** quase um relatório dizendo ao cliente que 21 arquivos estavam
comprometidos. Os arquivos `_10_` **não têm** trailer — é como a câmera grava.

**A regra:** antes de reportar perda, confirmar que a ausência é anormal. A prova veio
de dois lugares: os arquivos `_10_` têm tamanho em múltiplo exato de MiB (41.943.040 =
40 MiB), e batem byte a byte com o índice do cartão. Um padrão regular e consistente é
assinatura de comportamento projetado, não de dano.

### L09 · Tamanho igual não é conteúdo igual

**O que aconteceu:** o extrator em bash entregou 6 arquivos com tamanho exato. Parecia
pronto.

**O que custou:** nada, porque a comparação SHA-256 foi feita antes de declarar sucesso —
e confirmou. Mas tamanho correto com bytes trocados é um resultado possível de erro de
offset, e teria passado.

**A regra:** validar conteúdo, não só tamanho. Para provar um extrator, comparar hash
entre origem e destino. Para validar vídeo, decodificar frames no **início, meio e fim**.

### L10 · O nome que quase expôs os clientes

**O que aconteceu:** ao publicar a skill, o nome natural do repositório colidia com um
repositório **privado** que continha skills com dados operacionais de clientes.

**O que custou:** nada, porque os remotes locais foram conferidos antes do push.

**A regra:** antes de criar repositório ou dar push, conferir `git remote get-url` das
pastas candidatas. Nome de pasta não prova qual repositório é. Aqui, pasta e remoto
nem coincidem.

### L11 · Arredondar número em documento que se diz exato

**O que aconteceu:** num documento marcado como observação de campo, um tamanho saiu
arredondado (`2.132.000.000`) ao lado de dois valores exatos.

**A regra:** em documento que fundamenta decisão técnica, número arredondado ao lado de
número exato destrói a credibilidade dos dois. Se for aproximado, dizer que é.

### L12 · `dd bs=1` em offset grande

**O que aconteceu:** ler o bitmap de alocação com `dd bs=1 skip=<centenas de MB>`.

**O que custou:** tempo de execução inviável — `dd` copia byte a byte até o offset.

**A regra:** ler em blocos de setor e recortar. Vale para qualquer leitura de disco
bruto, nos dois sistemas.

---

## Como usar este arquivo

Antes de operar, ler a **Parte 2**. Ela descreve as formas pelas quais este conjunto de
ferramentas já mentiu, e todas são repetíveis.

Depois de cada caso, acrescentar entrada. O que merece registro:

- erro que fez o relatório ficar verde sem verificar
- caminho que pareceu certo e piorou o estado
- comportamento de câmera ou de cartão que contrariou a documentação
- número que não fechou e o que explicou a diferença

O que **não** merece registro: erro de digitação, coisa que a mensagem de erro já
explica, e preferência pessoal de ferramenta.

## As três perguntas antes de declarar sucesso

1. **O que eu verifiquei de verdade, e o que eu presumi?**
2. **Se este número estivesse errado, eu perceberia?** (L05 passou por aqui e falhou)
3. **O que eu afirmaria ao cliente agora que não posso provar?**
