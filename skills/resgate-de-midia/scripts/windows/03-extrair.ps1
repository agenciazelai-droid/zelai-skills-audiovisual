<#
    03-extrair.ps1 — extrai arquivos de um cartao exFAT RAW, SOMENTE LEITURA na origem.

    Nao usa imagem, nao usa carving, nao repara o cartao. Le a FAT e as entradas de
    diretorio, segue a cadeia de clusters de cada arquivo e grava o arquivo inteiro
    no destino, byte a byte, com o nome, o caminho e a data originais.

    Isso preserva o trailer de metadados do .insv (giroscopio e dados de costura),
    que o carving por assinatura perderia.

    Uso (PowerShell COMO ADMINISTRADOR):
        .\03-extrair.ps1 -DiskNumber 2 -Simular
        .\03-extrair.ps1 -DiskNumber 2 -Classes essencial
        .\03-extrair.ps1 -DiskNumber 2 -Classes tudo
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][int] $DiskNumber,
    # modelo de disco a recusar por seguranca (ex: o SSD onde fica o destino)
    [string] $ModeloProtegido = '',
    [string] $Destino = '.\recuperado',
    [ValidateSet('essencial','lrv','tudo')][string] $Classes = 'essencial',
    [string[]] $Apenas = @(),   # padroes wildcard no nome, ex: '*_027.insv','*_035.insv'
    [string] $Log = '.\log\extracao.txt',
    [int]    $BlocoMB = 16,
    [switch] $Simular
)

$ErrorActionPreference = 'Stop'
$script:linhas = New-Object System.Collections.Generic.List[string]
function Diz($txt, $cor = 'Gray') { Write-Host $txt -ForegroundColor $cor; $script:linhas.Add("$(Get-Date -Format 'HH:mm:ss')  $txt") }

# ---------- elevacao ----------
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: exige elevacao. Abra o PowerShell como Administrador." -ForegroundColor Red; exit 1
}

# ---------- guardas de identidade ----------
$disco = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
if (-not $disco) { Write-Host "ERRO: disco $DiskNumber nao existe." -ForegroundColor Red; exit 1 }
$discoSistema = (Get-Partition -DriveLetter ($env:SystemDrive.TrimEnd(':'))).DiskNumber
if ($DiskNumber -eq $discoSistema) { Write-Host "ERRO: e o disco do SISTEMA." -ForegroundColor Red; exit 1 }
if ($disco.FriendlyName -match $ModeloProtegido -and $ModeloProtegido -ne '') { Write-Host "ERRO: o disco casa com -ModeloProtegido." -ForegroundColor Red; exit 1 }
if ($disco.BusType -ne 'USB') { Write-Host "ERRO: nao e USB." -ForegroundColor Red; exit 1 }
$letraDestino = (Split-Path $Destino -Qualifier).TrimEnd(':')
$discoDestino = (Get-Partition -DriveLetter $letraDestino -ErrorAction SilentlyContinue).DiskNumber
if ($null -ne $discoDestino -and $DiskNumber -eq $discoDestino) {
    Write-Host "ERRO: origem e destino no mesmo disco." -ForegroundColor Red; exit 1
}

Diz "================================================================"
Diz " EXTRACAO — origem em somente leitura"
Diz " $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Diz "================================================================"
Diz ("Origem : PhysicalDrive{0} ({1})" -f $DiskNumber, $disco.FriendlyName)
Diz ("Destino: {0}" -f $Destino)
Diz ("Classes: {0}{1}" -f $Classes, $(if ($Simular) { '   [SIMULACAO]' } else { '' }))

# ---------- leitura alinhada ----------
$script:fs = $null
$script:SETOR = 512
function LerBytes([int64] $offset, [int] $qtd) {
    $s = $script:SETOR
    $ini = [int64]([math]::Floor($offset / $s) * $s)
    $fim = [int64]([math]::Ceiling(($offset + $qtd) / $s) * $s)
    $bruto = New-Object byte[] ($fim - $ini)
    $script:fs.Position = $ini
    $lidos = 0
    while ($lidos -lt $bruto.Length) {
        $n = $script:fs.Read($bruto, $lidos, $bruto.Length - $lidos)
        if ($n -le 0) { break }
        $lidos += $n
    }
    $res = New-Object byte[] $qtd
    $desloc = [int]($offset - $ini)
    $copiar = [math]::Min($qtd, $bruto.Length - $desloc)
    if ($copiar -gt 0) { [Array]::Copy($bruto, $desloc, $res, 0, $copiar) }
    return ,$res
}
function U16($b, $i) { [BitConverter]::ToUInt16($b, $i) }
function U32($b, $i) { [BitConverter]::ToUInt32($b, $i) }
function U64($b, $i) { [BitConverter]::ToUInt64($b, $i) }
function DataExfat([uint32] $ts) {
    if ($ts -eq 0) { return $null }
    $seg = ($ts -band 0x1F) * 2; $min = ($ts -shr 5) -band 0x3F; $hor = ($ts -shr 11) -band 0x1F
    $dia = ($ts -shr 16) -band 0x1F; $mes = ($ts -shr 21) -band 0x0F; $ano = (($ts -shr 25) -band 0x7F) + 1980
    if ($mes -lt 1 -or $mes -gt 12 -or $dia -lt 1 -or $dia -gt 31) { return $null }
    try { return (Get-Date -Year $ano -Month $mes -Day $dia -Hour $hor -Minute $min -Second ([math]::Min($seg,59))) } catch { return $null }
}

$script:fs = New-Object System.IO.FileStream("\\.\PhysicalDrive$DiskNumber",
    [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)

try {
    # ---------- MBR e VBR ----------
    $mbr = LerBytes 0 512
    $baseParticao = 0L
    for ($i = 0; $i -lt 4; $i++) {
        $o = 446 + ($i * 16)
        if ($mbr[$o + 4] -ne 0) { $baseParticao = [int64](U32 $mbr ($o + 8)) * 512; break }
    }
    $vbr = LerBytes $baseParticao 512
    if ([Text.Encoding]::ASCII.GetString($vbr, 3, 8) -ne 'EXFAT   ') {
        $vbr = LerBytes ($baseParticao + 6144) 512
        if ([Text.Encoding]::ASCII.GetString($vbr, 3, 8) -ne 'EXFAT   ') {
            Diz "ERRO: VBR exFAT nao encontrado. Rode o 02-diagnostico primeiro." 'Red'; exit 2
        }
        Diz "Usando o VBR de BACKUP (setor 12)." 'Yellow'
    }

    $bps = [int][math]::Pow(2, $vbr[108])
    $spc = [int][math]::Pow(2, $vbr[109])
    $fatOffset = U32 $vbr 80; $fatLength = U32 $vbr 84
    $heapOffset = U32 $vbr 88; $clusterCount = U32 $vbr 92; $rootCluster = U32 $vbr 96
    $bytesPorCluster = [int64]$bps * $spc
    $inicioVol = $baseParticao
    $fatBase = $inicioVol + ([int64]$fatOffset * $bps)

    Diz ("Cluster: {0} KiB   Clusters: {1}   Root: {2}" -f ($bytesPorCluster/1KB), $clusterCount, $rootCluster)
    $fatBytes = [int64]$fatLength * $bps
    $script:fatCache = $null
    if ($fatBytes -gt 0 -and $fatBytes -le 128MB) { $script:fatCache = LerBytes $fatBase ([int]$fatBytes) }

    function ClusterParaOffset([int64] $c) { return $inicioVol + ([int64]$heapOffset * $bps) + (($c - 2) * $bytesPorCluster) }

    function CadeiaDeClusters([int64] $primeiro, [bool] $semFat, [int64] $tamanho) {
        $lista = New-Object System.Collections.Generic.List[int64]
        if ($primeiro -lt 2) { return ,$lista }
        if ($semFat) {
            $n = [int64][math]::Max(1, [math]::Ceiling($tamanho / [double]$bytesPorCluster))
            for ($i = 0L; $i -lt $n; $i++) { $lista.Add($primeiro + $i) }
            return ,$lista
        }
        $c = $primeiro; $limite = 0
        while ($c -ge 2 -and $c -lt ($clusterCount + 2) -and $limite -lt 4000000) {
            $lista.Add($c)
            if ($script:fatCache) {
                $pos = [int]($c * 4)
                if ($pos + 4 -gt $script:fatCache.Length) { break }
                $prox = U32 $script:fatCache $pos
            } else { $prox = U32 (LerBytes ($fatBase + ($c * 4)) 4) 0 }
            # 0xFFFFFFF7 como literal vira -9 (Int32) no PowerShell 5.1: usar o decimal
            if ($prox -ge 4294967287 -or $prox -lt 2) { break }
            $c = $prox; $limite++
        }
        return ,$lista
    }

    # ---------- inventario ----------
    $arquivos = New-Object System.Collections.Generic.List[object]
    function LerDiretorio([int64] $cluster, [bool] $semFat, [int64] $tamanho, [string] $caminho, [int] $nivel) {
        if ($nivel -gt 8) { return }
        $cadeia = CadeiaDeClusters $cluster $semFat $tamanho
        $dados = New-Object System.Collections.Generic.List[byte]
        foreach ($cl in $cadeia) {
            if ($dados.Count -gt 64MB) { break }
            $dados.AddRange((LerBytes (ClusterParaOffset $cl) $bytesPorCluster))
        }
        $b = $dados.ToArray()
        $i = 0
        while ($i + 32 -le $b.Length) {
            $tipo = $b[$i]
            if ($tipo -eq 0x00) { break }
            if ($tipo -eq 0x85) {
                $sec = $b[$i + 1]
                $ehPasta = [bool]((U16 $b ($i + 4)) -band 0x10)
                $modificado = DataExfat (U32 $b ($i + 12))
                $nome = ''; $primCluster = 0; $tam = [int64]0; $flagsSec = 0
                for ($s = 1; $s -le $sec; $s++) {
                    $j = $i + ($s * 32)
                    if ($j + 32 -gt $b.Length) { break }
                    if ($b[$j] -eq 0xC0) {
                        $flagsSec = $b[$j + 1]; $primCluster = U32 $b ($j + 20); $tam = [int64](U64 $b ($j + 24))
                    } elseif ($b[$j] -eq 0xC1) { $nome += [Text.Encoding]::Unicode.GetString($b, $j + 2, 30) }
                }
                $nome = $nome.TrimEnd([char]0)
                $semFatSec = [bool]($flagsSec -band 0x02)
                $full = if ($caminho) { "$caminho\$nome" } else { $nome }
                if ($ehPasta) {
                    if ($primCluster -ge 2) { LerDiretorio $primCluster $semFatSec $tam $full ($nivel + 1) }
                } else {
                    $cl = 'auxiliar'
                    if     ($nome -like 'LRV_*')                                    { $cl = 'lrv' }
                    elseif ($nome -like 'VID_*' -and $nome -like '*.insv')           { $cl = 'essencial' }
                    elseif ($nome -like '*.mp4' -and $nome -notlike 'LRV_*')         { $cl = 'essencial' }
                    $script:arquivos.Add([PSCustomObject]@{
                        Caminho = $full; Nome = $nome; Bytes = $tam; Cluster = $primCluster
                        SemFat = $semFatSec; Modificado = $modificado; Classe = $cl
                    })
                }
                $i += 32 * ($sec + 1)
                continue
            }
            $i += 32
        }
    }
    LerDiretorio $rootCluster $false 0 '' 0
    Diz ("Arquivos no indice: {0}" -f $arquivos.Count)

    # ---------- selecao ----------
    $sel = switch ($Classes) {
        'essencial' { $arquivos | Where-Object { $_.Classe -eq 'essencial' } }
        'lrv'       { $arquivos | Where-Object { $_.Classe -eq 'lrv' } }
        'tudo'      { $arquivos | Where-Object { $_.Classe -ne 'auxiliar' } }
    }
    if ($Apenas.Count -gt 0) {
        $sel = $sel | Where-Object { $nome = $_.Nome; ($Apenas | Where-Object { $nome -like $_ }).Count -gt 0 }
        Diz ("Filtro -Apenas: {0}" -f ($Apenas -join ', ')) 'Yellow'
    }
    $sel = $sel | Sort-Object Caminho   # mantem os pares _00_/_10_ juntos
    $totalBytes = ($sel | Measure-Object Bytes -Sum).Sum
    $livre = (Get-Volume -DriveLetter $letraDestino).SizeRemaining

    Diz ""
    Diz ("Selecionados : {0} arquivos, {1} GiB" -f $sel.Count, [math]::Round($totalBytes/1GB,2)) 'Cyan'
    Diz ("Livre em {0}: : {1} GiB" -f $letraDestino, [math]::Round($livre/1GB,2)) 'Cyan'

    if ($totalBytes -gt $livre) {
        Diz ("ESPACO INSUFICIENTE: faltam {0} GiB." -f [math]::Round(($totalBytes - $livre)/1GB,2)) 'Red'
        Diz "Reduza o escopo (-Classes essencial) ou libere espaco. Nada foi extraido." 'Yellow'
        exit 3
    }

    if ($Simular) {
        Diz ""
        Diz "=== PLANO (nada sera escrito) ==="
        foreach ($a in $sel) {
            $cad = CadeiaDeClusters $a.Cluster $a.SemFat $a.Bytes
            $esperado = [int64][math]::Ceiling($a.Bytes / [double]$bytesPorCluster)
            $ok = if ($cad.Count -ge $esperado) { 'cadeia OK ' } else { 'CADEIA CURTA' }
            Diz ("{0,9} MB  {1}  clusters: {2}/{3}  {4}" -f [math]::Round($a.Bytes/1MB,1), $ok, $cad.Count, $esperado, $a.Caminho)
        }
        Diz ""
        Diz "Simulacao concluida. Rode sem -Simular para extrair." 'Cyan'
        exit 0
    }

    # ---------- extracao ----------
    $bloco = $BlocoMB * 1MB
    $feitos = 0; $pulados = 0; $falhos = 0; $bytesFeitos = 0L
    $inicio = Get-Date

    foreach ($a in $sel) {
        $saida = Join-Path $Destino $a.Caminho
        $pasta = Split-Path $saida -Parent
        if (-not (Test-Path $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }

        if ((Test-Path $saida) -and ((Get-Item $saida).Length -eq $a.Bytes)) {
            $pulados++; $bytesFeitos += $a.Bytes
            Diz ("PULA  (ja esta completo)  {0}" -f $a.Caminho)
            continue
        }

        $cadeia = CadeiaDeClusters $a.Cluster $a.SemFat $a.Bytes
        $esperado = [int64][math]::Ceiling($a.Bytes / [double]$bytesPorCluster)
        if ($cadeia.Count -lt $esperado) {
            Diz ("FALHA (cadeia curta: {0} de {1} clusters)  {2}" -f $cadeia.Count, $esperado, $a.Caminho) 'Red'
            $falhos++
            continue
        }

        # agrupa clusters contiguos em runs, para ler em blocos grandes
        $runs = New-Object System.Collections.Generic.List[object]
        $ini = $cadeia[0]; $fim = $cadeia[0]
        for ($k = 1; $k -lt $cadeia.Count; $k++) {
            if ($cadeia[$k] -eq ($fim + 1)) { $fim = $cadeia[$k] }
            else { $runs.Add([PSCustomObject]@{ Ini = $ini; Fim = $fim }); $ini = $cadeia[$k]; $fim = $cadeia[$k] }
        }
        $runs.Add([PSCustomObject]@{ Ini = $ini; Fim = $fim })

        $tmp = "$saida.parcial"
        $out = New-Object System.IO.FileStream($tmp, [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $restante = $a.Bytes
        try {
            foreach ($r in $runs) {
                if ($restante -le 0) { break }
                $offRun = ClusterParaOffset $r.Ini
                $tamRun = (($r.Fim - $r.Ini) + 1) * $bytesPorCluster
                $pos = 0L
                while ($pos -lt $tamRun -and $restante -gt 0) {
                    $pedir = [int][math]::Min([int64]$bloco, [math]::Min($tamRun - $pos, $restante))
                    $buf = LerBytes ($offRun + $pos) $pedir
                    $out.Write($buf, 0, $pedir)
                    $pos += $pedir; $restante -= $pedir; $bytesFeitos += $pedir
                }
            }
            $out.Flush()
        } finally { $out.Dispose() }

        $tamanhoFinal = (Get-Item $tmp).Length
        if ($tamanhoFinal -ne $a.Bytes) {
            Diz ("FALHA (gravou {0} de {1} bytes)  {2}" -f $tamanhoFinal, $a.Bytes, $a.Caminho) 'Red'
            $falhos++
            continue
        }
        if (Test-Path $saida) { Remove-Item $saida -Force }
        Rename-Item -LiteralPath $tmp -NewName (Split-Path $saida -Leaf)
        if ($a.Modificado) {
            try { (Get-Item $saida).LastWriteTime = $a.Modificado } catch {}
        }
        $feitos++
        $seg = ((Get-Date) - $inicio).TotalSeconds
        $mbs = if ($seg -gt 0) { [math]::Round(($bytesFeitos/1MB)/$seg,1) } else { 0 }
        Diz ("OK    {0,9} MB  {1}  ({2} MB/s, {3}/{4})" -f `
            [math]::Round($a.Bytes/1MB,1), $a.Caminho, $mbs, ($feitos + $pulados), $sel.Count)
        Write-Progress -Activity "Extraindo" -Status ("$feitos de $($sel.Count)  |  $mbs MB/s") `
            -PercentComplete ([math]::Min(100, 100 * $bytesFeitos / [double]$totalBytes))
    }
    Write-Progress -Activity "Extraindo" -Completed

    $dur = (Get-Date) - $inicio
    Diz ""
    Diz "================= RESULTADO ================="
    Diz ("Extraidos: {0}   Pulados: {1}   Falhos: {2}" -f $feitos, $pulados, $falhos)
    Diz ("Volume   : {0} GiB em {1:hh\:mm\:ss}" -f [math]::Round($bytesFeitos/1GB,2), $dur)
    Diz ("Destino  : {0}" -f $Destino)
    if ($falhos -eq 0) { Diz "Nenhuma falha. Proximo passo: validar com ffprobe (04-validar.ps1)." 'Green' }
    else { Diz "Houve falhas: os arquivos acima precisam de carving ou reparo." 'Yellow' }
    Diz "============================================="
}
catch {
    Diz ""
    Diz "!!! ERRO !!!" 'Red'
    Diz ("Mensagem: " + $_.Exception.Message) 'Red'
    Diz ("Local   : " + ($_.InvocationInfo.PositionMessage -replace "`r?`n", ' | ')) 'Red'
}
finally {
    if ($script:fs) { $script:fs.Dispose() }
    $d = Split-Path $Log -Parent
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    $script:linhas | Out-File -FilePath $Log -Encoding utf8
    Write-Host "`nLog em: $Log" -ForegroundColor Cyan
}
