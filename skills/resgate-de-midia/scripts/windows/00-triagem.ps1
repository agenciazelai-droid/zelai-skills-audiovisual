<#
    00-triagem.ps1 — a primeira coisa a rodar. SOMENTE LEITURA.

    Faz tres coisas, nesta ordem:

      1. DESCOBRE sozinho o que da para descobrir: quais discos sao candidatos a
         cartao de camera, qual marca e geracao de camera gravou aquele cartao
         (pela propria estrutura de pastas e nomes), e quanto material existe.

      2. CONFERE o destino: existe, nao esta dentro do cartao, e tem espaco
         sobrando para o material. Recusa seguir se faltar espaco.

      3. ENTREGA um plano: qual caminho de recuperacao seguir e qual comando rodar.

    Nao escreve no cartao. Nao escreve no destino. Nao decide nada sozinho:
    imprime o plano para o operador conferir.

    O que este script NAO sabe e precisa ser perguntado a quem trouxe o cartao
    esta listado no fim da saida, porque muda o que ainda e possivel fazer.

    Uso (PowerShell COMO ADMINISTRADOR):
        .\00-triagem.ps1                                  # so lista os candidatos
        .\00-triagem.ps1 -DiskNumber 2
        .\00-triagem.ps1 -DiskNumber 2 -Destino 'E:\resgate\cliente-x'
#>

[CmdletBinding()]
param(
    [int]    $DiskNumber = -1,
    [string] $Destino = '',
    [string] $ModeloProtegido = '',
    [string] $Relatorio = '.\log\triagem.txt'
)

$ErrorActionPreference = 'Stop'
$script:linhas = New-Object System.Collections.Generic.List[string]
function Diz($txt, $cor = 'Gray') { Write-Host $txt -ForegroundColor $cor; $script:linhas.Add($txt) }

# ================= 1. candidatos =================
Diz "================================================================"
Diz " TRIAGEM — primeira leitura do cartao (nada e escrito)"
Diz " $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Diz "================================================================"

$discoSistema = (Get-Partition -DriveLetter ($env:SystemDrive.TrimEnd(':'))).DiskNumber
Diz ""
Diz "--- Discos presentes ---"
$todos = Get-Disk | Sort-Object Number
foreach ($d in $todos) {
    $marca = ''
    if ($d.Number -eq $discoSistema)                    { $marca = '  <- disco do SISTEMA, nunca usar como origem' }
    elseif ($ModeloProtegido -and $d.FriendlyName -match $ModeloProtegido) { $marca = '  <- protegido por -ModeloProtegido' }
    elseif ($d.BusType -eq 'USB')                       { $marca = '  <- candidato a cartao' }
    Diz ("  Disco {0}: {1,-28} {2,-5} {3,8} GiB  {4}{5}" -f $d.Number, $d.FriendlyName, $d.BusType,
        [math]::Round($d.Size/1GB,2), $d.PartitionStyle, $marca)
}

Diz ""
Diz "ATENCAO: dois discos de tamanho parecido sao indistinguiveis pelo tamanho." 'Yellow'
Diz "Confirme a origem pelo MODELO, nunca pelo numero de GiB." 'Yellow'

if ($DiskNumber -lt 0) {
    Diz ""
    Diz "Escolha a origem e rode de novo:  .\00-triagem.ps1 -DiskNumber <N> -Destino <pasta>" 'Cyan'
    $d = Split-Path $Relatorio -Parent
    if ($d -and -not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    $script:linhas | Out-File -FilePath $Relatorio -Encoding utf8
    exit 0
}

# ================= guardas =================
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: leitura de disco bruto exige elevacao." -ForegroundColor Red; exit 1
}
$disco = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
if (-not $disco) { Diz "ERRO: disco $DiskNumber nao existe." 'Red'; exit 1 }
if ($DiskNumber -eq $discoSistema) { Diz "ERRO: disco do SISTEMA. Abortado." 'Red'; exit 1 }
if ($ModeloProtegido -and $disco.FriendlyName -match $ModeloProtegido) { Diz "ERRO: disco protegido. Abortado." 'Red'; exit 1 }

Diz ""
Diz ("Origem escolhida: Disco {0} — {1} ({2} GiB)" -f $DiskNumber, $disco.FriendlyName, [math]::Round($disco.Size/1GB,2)) 'Cyan'

# ================= leitura do indice =================
$SETOR = 512
$script:fs = $null
function LerBytes([int64] $offset, [int] $qtd) {
    $ini = [int64]([math]::Floor($offset / $SETOR) * $SETOR)
    $fim = [int64]([math]::Ceiling(($offset + $qtd) / $SETOR) * $SETOR)
    $bruto = New-Object byte[] ($fim - $ini)
    $script:fs.Position = $ini
    $lidos = 0
    while ($lidos -lt $bruto.Length) { $n = $script:fs.Read($bruto, $lidos, $bruto.Length - $lidos); if ($n -le 0) { break }; $lidos += $n }
    $res = New-Object byte[] $qtd
    $desl = [int]($offset - $ini); $cop = [math]::Min($qtd, $bruto.Length - $desl)
    if ($cop -gt 0) { [Array]::Copy($bruto, $desl, $res, 0, $cop) }
    return ,$res
}
function U16($b,$i) { [BitConverter]::ToUInt16($b,$i) }
function U32($b,$i) { [BitConverter]::ToUInt32($b,$i) }
function U64($b,$i) { [BitConverter]::ToUInt64($b,$i) }

$script:fs = New-Object System.IO.FileStream("\\.\PhysicalDrive$DiskNumber",
    [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)

$arquivos = New-Object System.Collections.Generic.List[object]
$indiceOk = $false
$bytesMaterial = 0L

try {
    $mbr = LerBytes 0 512
    $basePart = 0L
    for ($i = 0; $i -lt 4; $i++) {
        $o = 446 + ($i * 16)
        if ($mbr[$o + 4] -ne 0) { $basePart = [int64](U32 $mbr ($o + 8)) * 512; break }
    }
    $vbrBase = -1
    foreach ($c in @($basePart, ($basePart + 6144))) {
        if ([Text.Encoding]::ASCII.GetString((LerBytes $c 512), 3, 8) -eq 'EXFAT   ') { $vbrBase = $c; break }
    }

    Diz ""
    Diz "--- Estado do sistema de arquivos ---"
    if ($vbrBase -lt 0) {
        Diz "  exFAT nao localizado (nem principal, nem backup)." 'Yellow'
        Diz "  O indice pode ter se perdido: o caminho provavel e carving, que exige imagem." 'Yellow'
    } else {
        $origem = if ($vbrBase -eq $basePart) { 'principal' } else { 'BACKUP (setor 12)' }
        Diz ("  exFAT encontrado: VBR {0}" -f $origem) 'Green'

        $vbr = LerBytes $vbrBase 512
        $bps = [int][math]::Pow(2, $vbr[108]); $spc = [int][math]::Pow(2, $vbr[109])
        $fatOff = U32 $vbr 80; $fatLen = U32 $vbr 84
        $heapOff = U32 $vbr 88; $clCount = U32 $vbr 92; $rootCl = U32 $vbr 96
        $bpc = [int64]$bps * $spc
        $fatBase = $vbrBase + ([int64]$fatOff * $bps)
        $fatCache = $null
        if (([int64]$fatLen * $bps) -le 128MB) { $fatCache = LerBytes $fatBase ([int]([int64]$fatLen * $bps)) }

        function ClOff([int64]$c) { return $vbrBase + ([int64]$heapOff * $bps) + (($c - 2) * $bpc) }
        function Cadeia([int64]$p, [bool]$semFat, [int64]$tam) {
            $l = New-Object System.Collections.Generic.List[int64]
            if ($p -lt 2) { return ,$l }
            if ($semFat) {
                $n = [int64][math]::Max(1, [math]::Ceiling($tam / [double]$bpc))
                for ($k = 0L; $k -lt $n; $k++) { $l.Add($p + $k) }
                return ,$l
            }
            $c = $p; $g = 0
            while ($c -ge 2 -and $c -lt ($clCount + 2) -and $g -lt 500000) {
                $l.Add($c)
                if ($fatCache) { $pos = [int]($c * 4); if ($pos + 4 -gt $fatCache.Length) { break }; $prox = U32 $fatCache $pos }
                else { $prox = U32 (LerBytes ($fatBase + ($c * 4)) 4) 0 }
                if ($prox -ge 4294967287 -or $prox -lt 2) { break }
                $c = $prox; $g++
            }
            return ,$l
        }
        function LerDir([int64]$cl, [bool]$semFat, [int64]$tam, [string]$caminho, [int]$nivel) {
            if ($nivel -gt 6) { return }
            $dados = New-Object System.Collections.Generic.List[byte]
            foreach ($c in (Cadeia $cl $semFat $tam)) {
                if ($dados.Count -gt 32MB) { break }
                $dados.AddRange((LerBytes (ClOff $c) $bpc))
            }
            $b = $dados.ToArray(); $i = 0
            while ($i + 32 -le $b.Length) {
                $t = $b[$i]
                if ($t -eq 0) { break }
                if ($t -eq 0x85) {
                    $sec = $b[$i+1]
                    $ehPasta = [bool]((U16 $b ($i+4)) -band 0x10)
                    $nome = ''; $prim = 0; $tm = [int64]0; $fl = 0
                    for ($s = 1; $s -le $sec; $s++) {
                        $j = $i + ($s * 32); if ($j + 32 -gt $b.Length) { break }
                        if ($b[$j] -eq 0xC0) { $fl = $b[$j+1]; $prim = U32 $b ($j+20); $tm = [int64](U64 $b ($j+24)) }
                        elseif ($b[$j] -eq 0xC1) { $nome += [Text.Encoding]::Unicode.GetString($b, $j+2, 30) }
                    }
                    $nome = $nome.TrimEnd([char]0)
                    $full = if ($caminho) { "$caminho\$nome" } else { $nome }
                    if ($ehPasta) { if ($prim -ge 2) { LerDir $prim ([bool]($fl -band 2)) $tm $full ($nivel+1) } }
                    else { $script:arquivos.Add([PSCustomObject]@{ Caminho = $full; Nome = $nome; Bytes = $tm }) }
                    $i += 32 * ($sec + 1); continue
                }
                $i += 32
            }
        }
        LerDir $rootCl $false 0 '' 0
        $bytesMaterial = ($arquivos | Measure-Object Bytes -Sum).Sum
        if (-not $bytesMaterial) { $bytesMaterial = 0L }
        $indiceOk = ($arquivos.Count -gt 0)
        Diz ("  Arquivos no indice: {0}   Material: {1} GiB" -f $arquivos.Count, [math]::Round($bytesMaterial/1GB,2))
        $pct = $vbr[112]
        if ($pct -le 100) { Diz ("  PercentInUse do volume: {0}%" -f $pct) }
    }
}
finally { if ($script:fs) { $script:fs.Dispose() } }

# ================= 2. identificar a camera pela estrutura =================
Diz ""
Diz "--- Quem gravou este cartao ---"

$marca = 'nao identificada'
$geracao = ''
$obs = New-Object System.Collections.Generic.List[string]

if ($arquivos.Count -gt 0) {
    $caminhos = $arquivos.Caminho
    $nomes = $arquivos.Nome

    $temM4ROOT = ($caminhos | Where-Object { $_ -match 'M4ROOT' }).Count -gt 0
    $temXDROOT = ($caminhos | Where-Object { $_ -match 'XDROOT' }).Count -gt 0
    $temInsta  = ($caminhos | Where-Object { $_ -match 'Camera0\d' }).Count -gt 0
    $temGoPro  = ($caminhos | Where-Object { $_ -match 'GOPRO' }).Count -gt 0
    $insv      = ($nomes | Where-Object { $_ -like '*.insv' }).Count
    $rsv       = ($nomes | Where-Object { $_ -like '*.rsv' }).Count
    $mxf       = ($nomes | Where-Object { $_ -like '*.MXF' -or $_ -like '*.mxf' }).Count

    if ($temXDROOT -or $mxf -gt 0) {
        $marca = 'SONY — linha profissional'
        $geracao = 'XDROOT: FX6, FX9, PXW, VENICE (XAVC-I/L, XDCAM, X-OCN)'
        $obs.Add('Copiar a arvore inteira a partir de PRIVATE\: o MXF sozinho perde o XML, o timecode e a LUT.')
    }
    elseif ($temM4ROOT) {
        $marca = 'SONY — linha hibrida / cinema compacta'
        $geracao = 'M4ROOT: A7, FX3, FX30, ZV (XAVC S / XAVC HS)'
        $obs.Add('Copiar a arvore inteira a partir de PRIVATE\: o MP4 sozinho perde o XML por clipe.')
        $obs.Add('Numeracao C0001 reseta a cada formatacao: criar uma pasta por cartao no destino.')
    }
    elseif ($temGoPro) {
        $marca = 'GOPRO'
        $geracao = 'estrutura DCIM\1xxGOPRO'
        $obs.Add('Arquivo acima de 4 GB e dividido em capitulos: recuperar todos os pedacos.')
    }
    elseif ($temInsta -or $insv -gt 0) {
        $marca = 'INSTA360'
        # a geracao se revela pelos pares de lente
        $pares = @{}
        foreach ($n in $nomes) {
            if ($n -match '^VID_(\d{8}_\d{6})_(00|10)_(\d+)\.insv$') {
                $k = "$($Matches[1])_$($Matches[3])"
                if (-not $pares.ContainsKey($k)) { $pares[$k] = @() }
                $pares[$k] += $Matches[2]
            }
        }
        $comPar = ($pares.Values | Where-Object { $_.Count -ge 2 }).Count
        $soUm   = ($pares.Values | Where-Object { $_.Count -eq 1 }).Count
        $lrvInsv = ($nomes | Where-Object { $_ -like 'LRV_*.insv' }).Count
        $lrvLrv  = ($nomes | Where-Object { $_ -like 'LRV_*.lrv' }).Count

        if ($comPar -gt 0) {
            $geracao = 'ONE X, ONE X2 ou X3 em alta resolucao — DOIS arquivos por clipe 360'
            $obs.Add("CRITICO: $comPar clipe(s) em par _00_/_10_. Os dois arquivos do par sao obrigatorios;")
            $obs.Add('recuperar so um lado entrega clipe que NAO costura o 360.')
            if ($soUm -gt 0) { $obs.Add("ATENCAO: $soUm clipe(s) com apenas uma lente no indice — possivel perda.") }
            if ($lrvInsv -gt 0 -and $lrvLrv -eq 0) { $geracao = 'ONE X2 — LRV com extensao .insv confirma esta geracao' }
            if ($lrvLrv -gt 0) { $geracao = 'X3 — LRV com extensao .lrv' }
        } elseif ($insv -gt 0) {
            $geracao = 'X4, X4 Air, X5 ou X6 — UM arquivo por clipe, com as duas lentes'
            $obs.Add('Sem risco de par incompleto nesta geracao.')
        }
        $obs.Add('Conferir DCIM\Camera01\Thumb: toda miniatura deve ter seu video. Miniatura orfa = clipe perdido.')
    }

    if ($rsv -gt 0) {
        $obs.Add("ACHADO IMPORTANTE: $rsv arquivo(s) .rsv — gravacao interrompida da Sony.")
        $obs.Add('NAO apagar: o material esta dentro. Ver references\sony.md antes de agir.')
    }
}

Diz ("  Marca   : {0}" -f $marca) 'Cyan'
if ($geracao) { Diz ("  Geracao : {0}" -f $geracao) 'Cyan' }
if ($obs.Count -gt 0) {
    Diz ""
    foreach ($o in $obs) { Diz ("  * {0}" -f $o) 'Yellow' }
}

# ================= 3. conferir o destino =================
Diz ""
Diz "--- Destino dos arquivos recuperados ---"
Diz "O material sai do cartao para uma pasta que VOCE escolhe. O cartao nunca e escrito."

if (-not $Destino) {
    Diz ""
    Diz "Nenhum destino informado. Rode de novo com -Destino '<pasta>'." 'Yellow'
    if ($bytesMaterial -gt 0) {
        Diz ("Reserve pelo menos {0} GiB livres (o material) — ou {1} GiB se quiser imagem tambem." -f `
            [math]::Round($bytesMaterial/1GB,2), [math]::Round(($bytesMaterial + $disco.Size)/1GB,2)) 'Yellow'
    }
} else {
    $letra = (Split-Path $Destino -Qualifier).TrimEnd(':')
    $ok = $true

    $discoDestino = (Get-Partition -DriveLetter $letra -ErrorAction SilentlyContinue).DiskNumber
    if ($null -eq $discoDestino) {
        Diz ("  AVISO: nao identifiquei o disco de '{0}:'. Confirme que nao e o cartao." -f $letra) 'Yellow'
    } elseif ($discoDestino -eq $DiskNumber) {
        Diz "  ERRO: o destino esta NO PROPRIO CARTAO. Isso reescreveria a origem." 'Red'
        Diz "  Escolha uma pasta em outro disco." 'Red'
        $ok = $false
    } else {
        Diz ("  Destino em disco {0} — diferente da origem (disco {1}). OK." -f $discoDestino, $DiskNumber) 'Green'
    }

    if ($ok) {
        if (-not (Test-Path $Destino)) {
            Diz ("  A pasta '{0}' ainda nao existe — sera criada na extracao." -f $Destino)
        } else {
            $ja = (Get-ChildItem $Destino -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
            if ($ja -gt 0) { Diz ("  AVISO: a pasta ja tem {0} arquivo(s). Prefira uma pasta vazia por cartao." -f $ja) 'Yellow' }
        }
        $vol = Get-Volume -DriveLetter $letra -ErrorAction SilentlyContinue
        if ($vol) {
            $livre = $vol.SizeRemaining
            Diz ("  Livre no destino: {0} GiB" -f [math]::Round($livre/1GB,2))
            if ($bytesMaterial -gt 0) {
                Diz ("  Material a copiar: {0} GiB" -f [math]::Round($bytesMaterial/1GB,2))
                $margem = [int64]($bytesMaterial * 1.05)
                if ($livre -ge $margem) {
                    Diz ("  CABE, com {0} GiB de folga." -f [math]::Round(($livre - $bytesMaterial)/1GB,2)) 'Green'
                } else {
                    Diz ("  NAO CABE: faltam {0} GiB." -f [math]::Round(($margem - $livre)/1GB,2)) 'Red'
                    Diz "  Saidas: liberar espaco, outro disco, ou extrair so os masters (-Classes essencial)." 'Yellow'
                    $ok = $false
                }
            }
        }
    }
}

# ================= 4. plano =================
Diz ""
Diz "===================== PLANO ====================="
if ($indiceOk -and $bytesMaterial -gt 0) {
    Diz "Indice legivel: o caminho e EXTRACAO PELO INDICE." 'Green'
    Diz "Nao precisa de imagem bit-a-bit nem de carving."
    Diz ""
    Diz "  1) confirmar a consistencia:"
    Diz ("     .\02-diagnostico-exfat.ps1 -DiskNumber {0}" -f $DiskNumber)
    Diz "  2) simular (valida as cadeias, nao escreve):"
    Diz ("     .\03-extrair.ps1 -DiskNumber {0} -Destino '<pasta>' -Classes essencial -Simular" -f $DiskNumber)
    Diz "  3) extrair:"
    Diz ("     .\03-extrair.ps1 -DiskNumber {0} -Destino '<pasta>' -Classes essencial" -f $DiskNumber)
    Diz "  4) validar:"
    Diz "     .\04-validar.ps1"
} else {
    Diz "Indice nao rendeu arquivos: o caminho passa por IMAGEM + CARVING." 'Yellow'
    Diz ("  1) .\01-criar-imagem.ps1 -DiskNumber {0} -Destino '<pasta>\cartao.img'" -f $DiskNumber)
    Diz "  2) PhotoRec sobre a imagem (ver references\ferramentas.md)"
    Diz "  Reserve ~2x a capacidade do cartao."
}
Diz "================================================="

# ================= 5. o que o script nao sabe =================
Diz ""
Diz "--- Perguntar a quem trouxe o cartao (muda o que ainda e possivel) ---"
Diz "  1. O cartao voltou para a camera depois do problema?"
Diz "  2. Rodou 'reparar unidade', chkdsk, ou Primeiros Socorros do macOS?"
Diz "  3. Algum programa de recuperacao ja passou nele? Qual?"
Diz "  4. Houve formatacao, mesmo rapida?"
Diz "  5. Qual o modelo exato da camera? (confirma o que a estrutura sugeriu acima)"
Diz "  6. Falta material que nem aparece na lista? Quantos clipes ele lembra de ter gravado?"
Diz ""
Diz "Resposta 'sim' em 2, 3 ou 4 reduz as chances e muda o caminho — ver references\triagem.md." 'Yellow'

$d = Split-Path $Relatorio -Parent
if ($d -and -not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
$script:linhas | Out-File -FilePath $Relatorio -Encoding utf8
Write-Host "`nRelatorio em: $Relatorio" -ForegroundColor Cyan
