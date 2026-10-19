# Armadilhas de PowerShell que fazem a verificação mentir

Seis erros encontrados escrevendo os scripts desta skill. Nenhum deles gera mensagem de
erro clara, e **três fazem a verificação aprovar material que não foi verificado** — o
pior tipo de bug numa recuperação, porque o relatório fica verde.

Documentados porque voltariam a custar tempo, e porque valem para qualquer script que
leia disco bruto no Windows.

---

## 1. `0xFFFFFFF7` vira `-9`

```powershell
PS> 0xFFFFFFF7
-9
```

Literal hexadecimal acima de `0x7FFFFFFF` é interpretado como `Int32` com overflow. A
comparação com o marcador de fim de cadeia da FAT:

```powershell
if ($prox -ge 0xFFFFFFF7) { break }    # equivale a  $prox -ge -9  →  SEMPRE verdadeiro
```

**Sintoma:** toda cadeia de clusters termina no primeiro elemento. Os arquivos aparecem
como se tivessem 1 cluster — e isso parece dano no cartão, não bug no código.

**Correção:** usar o decimal.

```powershell
if ($prox -ge 4294967287 -or $prox -lt 2) { break }
```

Esse foi o bug mais caro: fez um cartão perfeitamente íntegro parecer irrecuperável.

---

## 2. Leitura de disco bruto exige alinhamento ao setor

Ler 4 bytes de uma entrada da FAT num offset arbitrário de `\\.\PhysicalDriveN`
**falha**. Offset e tamanho precisam ser múltiplos do tamanho do setor.

**Correção:** ler o bloco alinhado que contém a faixa e recortar.

```powershell
function LerBytes([int64] $offset, [int] $qtd) {
    $s = 512
    $ini = [int64]([math]::Floor($offset / $s) * $s)
    $fim = [int64]([math]::Ceiling(($offset + $qtd) / $s) * $s)
    $bruto = New-Object byte[] ($fim - $ini)
    $fs.Position = $ini
    # ... ler $bruto inteiro ...
    $res = New-Object byte[] $qtd
    [Array]::Copy($bruto, [int]($offset - $ini), $res, 0, $qtd)
    return ,$res
}
```

Melhor ainda para a FAT: carregar os 8 MiB inteiros em memória de uma vez.

---

## 3. `return $byteArray` desembala para `Object[]`

```powershell
function Ler { $b = New-Object byte[] 512; return $b }
(Ler).GetType().Name     # Object[]  — não Byte[]
```

O PowerShell enumera arrays no retorno. Chamadas `.NET` que aceitam `byte[]` continuam
funcionando por coerção automática, então o problema fica escondido — até encontrar um
método que **não** faz coerção:

```
List[byte].AddRange(Object[])  →  "Não é possível converter o argumento collection"
```

**Correção:** vírgula unária.

```powershell
return ,$b
```

Vale também para `List<T>`: `return ,$lista`.

---

## 4. `[math]::Min(128KB, $arquivo.Length)` estoura acima de 2 GiB

`128KB` é `Int32`, `$arquivo.Length` é `Int64`. O PowerShell casa a sobrecarga `Int32` e
lança em qualquer arquivo acima de 2 GiB — exatamente os arquivos de vídeo.

**O que torna isso grave:** com `$ErrorActionPreference = 'Continue'`, o script segue com
a variável da iteração anterior e **a verificação passa a mentir em silêncio**. Num caso
real isso produziu uma contagem errada de trailers de metadados, com o relatório final
dizendo "43 válidos".

**Correção:** comparar em `int64` e converter só o tamanho do buffer.

```powershell
[int64]$len = $arquivo.Length
[int]$tam = if ($len -lt 131072) { [int]$len } else { 131072 }
```

**Lição mais ampla:** num script de verificação, erro suprimido é pior que erro fatal.
Preferir `Stop` e capturar, ou validar que cada leitura devolveu o que foi pedido.

---

## 5. `.ps1` sem BOM é lido como ANSI no PowerShell 5.1

Um travessão (`—`) num comentário quebra o parse do arquivo inteiro, com erros
apontando para linhas que não têm nada de errado:

```
Token 'GiB' inesperado na expressão ou instrução.
```

**Correção:** gravar com BOM UTF-8.

```powershell
$utf8bom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($caminho, $texto, $utf8bom)
```

Ferramentas que escrevem UTF-8 sem BOM (a maioria) produzem esse efeito. Alternativa:
manter os scripts em ASCII puro.

---

## 6. `if` como expressão não existe no 5.1

```powershell
Add-Member -NotePropertyValue ( if ($x) { 'a' } else { 'b' } )    # erro de parse
```

Atribuição direta **funciona** (`$v = if ($x) { 'a' } else { 'b' }`), mas `if` dentro de
uma expressão ou como argumento, não.

**Correção:** calcular antes, ou usar `$( ... )`.

```powershell
$classe = 'padrao'
if ($x) { $classe = 'a' }
Add-Member -NotePropertyValue $classe
```

---

## Padrões que valem adotar

**Guardas de identidade antes de qualquer acesso.** Recusar explicitamente o disco do
sistema, o disco de destino e qualquer coisa que não seja USB:

```powershell
if ($DiskNumber -eq $discoDoSistema) { exit 1 }
if ($disco.FriendlyName -match 'MODELO_DO_SSD_DE_TRABALHO') { exit 1 }
if ($disco.BusType -ne 'USB') { exit 1 }
```

**Elevação por UAC sem sair do terminal.** `Start-Process -Verb RunAs` com a saída
redirecionada para arquivo, e ler o arquivo depois:

```powershell
$cmd = "& '$script' -DiskNumber 2 *> '$log'"
Start-Process powershell -Verb RunAs `
  -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command',$cmd -Wait
```

**Gravar o relatório no `finally`.** Assim o log existe mesmo quando o script morre — e
é nele que o erro aparece.

**Escrever em `.parcial` e renomear só depois de conferir o tamanho.** Torna a retomada
confiável e impede que um arquivo truncado pareça pronto.

**Provar em memória antes de escrever no dispositivo.** No conserto do boot sector:
montar a região corrigida, recalcular o checksum e confirmar que bate. Só então gravar.

---

## Tempo de execução

PowerShell é lento em laço apertado. Dois números de referência, em USB 3.0 com cartão
microSD:

- **Extração: ~25 MB/s** com leituras coalescidas em blocos de 16 MiB. 95,84 GiB levaram
  1h06m.
- Percorrer a cadeia de um arquivo de 7 GB (57 mil clusters) com a FAT em memória: alguns
  segundos. Lendo a FAT do disco a cada cluster: inviável.

Para volumes muito maiores, considerar reescrever o laço de cópia em C# via
`Add-Type`, ou usar `dd` no macOS/Linux.
