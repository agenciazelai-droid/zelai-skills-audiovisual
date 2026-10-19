# Triagem — o que perguntar, e o que cada resposta muda

O script `00-triagem` descobre sozinho o que está no cartão. O que ele **não** pode
descobrir é o histórico: o que já foi feito com aquele cartão antes de chegar às suas
mãos. E é o histórico que define o que ainda é possível.

Perguntar antes de executar qualquer coisa. Em agente, usar pergunta estruturada — uma
rodada de perguntas vale mais que seis mensagens.

---

## As sete perguntas

### 1. O cartão voltou para a câmera depois do problema?

| Resposta | O que muda |
|---|---|
| Não | melhor cenário |
| Sim, e a câmera não leu | risco baixo: a câmera que não monta não reescreve |
| **Sim, e a câmera leu / mostrou arquivos** | **a câmera pode ter reescrito o índice e renumerado.** Comparar a numeração dos arquivos com o que o cliente lembra. Caso documentado de GO Ultra: a câmera renumerou tudo a partir de `001` e material de dias anteriores desapareceu do índice |
| Sim, e gravou algo novo | material novo pode ter caído sobre o antigo. Carving no espaço livre é a única chance do que foi sobrescrito |

### 2. Rodou "reparar unidade", `chkdsk` ou Primeiros Socorros?

| Resposta | O que muda |
|---|---|
| Não | o índice residual está preservado |
| **Sim** | **reduz as chances e muda a ordem.** O `chkdsk` reescreve estruturas e pode ter destruído as cadeias FAT residuais. Ainda vale rodar o diagnóstico — mas se o índice não bater com o bitmap, o caminho é carving direto, e esperar fragmentação |
| Não sei / "só cliquei em OK no que apareceu" | tratar como **sim**. Assumir o pior e confirmar pelo diagnóstico |

A última linha importa: quem não é técnico costuma clicar no botão que o sistema oferece
sem registrar o que era. Perguntar "apareceu alguma janela pedindo para verificar o
disco?" em vez de usar o nome da ferramenta.

### 3. Algum programa de recuperação já passou nele?

| Resposta | O que muda |
|---|---|
| Não | ideal |
| Sim, só leu (modo demo, prévia) | risco baixo |
| **Sim, e gravou os resultados no próprio cartão** | **pior caso de software:** os arquivos "recuperados" caíram sobre dado não recuperado. Perda real e irreversível |
| Sim, e não lembro qual | perguntar se o resultado foi salvo em outro disco |

Anotar o nome do programa. Alguns gravam índices temporários no volume de origem.

### 4. Houve formatação, mesmo rápida?

| Resposta | O que muda |
|---|---|
| Não | o índice pode estar inteiro |
| Sim, formatação **rápida** | o índice foi reescrito, **os dados continuam lá.** Caminho: carving. Taxa de recuperação costuma ser alta |
| **Sim, formatação completa** | zera o conteúdo. Chance de recuperação muito baixa; considerar laboratório |
| Sim, **pela câmera** | normalmente equivale à rápida, mas algumas câmeras fazem escrita completa |

### 5. Qual o modelo exato da câmera?

A estrutura do cartão já sugere a marca e a geração, e o script informa isso. A
confirmação do modelo serve para três coisas:

- **saber se o clipe 360 são um ou dois arquivos** (a divisória é o X4 — ver
  `insta360-linha-x.md`)
- **saber a resolução esperada** por lente, para validar o que foi extraído
- **saber se a câmera tem recuperação própria** (Sony finaliza `.rsv`; Insta360 tem
  ferramenta de reparo)

Se a resposta do cliente divergir do que a estrutura mostra, **a estrutura vence** — mas
investigar: pode ser cartão usado em duas câmeras diferentes, o que explica numeração
estranha.

### 6. Onde devem ficar os arquivos recuperados?

Não é detalhe operacional, é regra de segurança. Exigir **caminho completo em outro
disco**. Recusar:

- o próprio cartão (reescreveria a origem)
- uma pasta que já contenha material de outro cartão — numeração Sony reinicia em
  `C0001` a cada formatação, e dois cartões se sobrescrevem **sem aviso**
- um disco com menos espaço que o material

Convenção que evita o problema: uma pasta por cartão, nomeada com data e identificação —
`2026-10-19_FX3_cartao-A/`.

### 7. Falta material que nem aparece na lista?

A pergunta mais negligenciada, e a única forma de descobrir material cujo índice se
perdeu.

Perguntar de forma concreta: **quantos clipes a pessoa lembra de ter gravado? Em quais
dias?** Comparar com o inventário.

| Situação | O que fazer |
|---|---|
| O que ela lembra está todo na lista | extrair pelo índice e encerrar |
| **Falta material que ela afirma ter gravado** | o índice daquele material se perdeu. Depois de extrair o que há, fazer carving **no espaço livre** do cartão |
| Ela não sabe dizer | usar as miniaturas: toda miniatura sem vídeo é um clipe cujo índice se perdeu |

Dois sinais objetivos de material fora do índice:

- **miniatura órfã** em `DCIM/Camera01/Thumb/` (Insta360)
- **lacuna grande na numeração** com datas que não fecham — lembrando que lacuna pequena
  é normal, a câmera pula números

O espaço livre também informa: um cartão com pouco espaço livre tem pouca chance de
esconder material apagado recuperável.

---

## Antes de prosseguir, dizer ao cliente

Três coisas, antes de executar:

1. **O cartão não será escrito.** O material sai dele para a pasta escolhida.
2. **Nada é formatado nem reparado** sem autorização, e só depois de a cópia existir.
3. **O que não for recuperado será dito**, com nome e horário.

E uma coisa que não se promete: taxa de sucesso. Antes do diagnóstico, não há número
honesto a dar.

---

## O que não perguntar

| Não perguntar | Por quê |
|---|---|
| "O cartão é bom ou é falsificado?" | não muda a conduta agora, e soa como culpa |
| "Por que você não tinha backup?" | irrelevante neste momento; a prevenção vai no fim |
| termos técnicos sem tradução | transfere ao cliente o trabalho de entender |
| "Quanto vale esse material pra você?" | a conduta é a mesma independente da resposta |

A primeira merece nota: cartão falsificado tende a falhar fisicamente, não logicamente —
e isso aparece no diagnóstico como erro de leitura, não como índice quebrado. Vale
investigar **depois**, pelo resultado, nunca pela pergunta.

---

## Registrar as respostas

Preencher a seção "Histórico antes da intervenção" de
`templates/relatorio-tecnico.md` **antes** de começar. Duas razões:

- define o que é esperado encontrar, evitando atribuir ao cartão um dano que veio de
  software
- se o caso voltar, ou outra pessoa continuar, o histórico não se perde
