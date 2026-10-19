<#
    02-diagnostico-exfat.ps1 — diagnostico SOMENTE LEITURA de um cartao exFAT RAW.

    Nao escreve NADA no cartao. Nao copia arquivo. Nao ocupa espaco em disco
    (so o relatorio de texto). Responde duas perguntas:

      1) A estrutura do exFAT esta recuperavel? (VBR principal / VBR de backup)
      2) Quantos GB de material existem de verdade no cartao?

    Uso (PowerShell COMO ADMINISTRADOR):
        .\02-diagnostico-exfat.ps1 -DiskNumber 2
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][int] $DiskNumber,
    # modelo de disco a recusar por seguranca (ex: o SSD onde fica o destino)
    [string] $ModeloProtegido = '',
    [string] $Relatorio = '.\log\diagnostico.txt',
    [int]    $MaxEntradas = 200000
)

$ErrorActionPreference = 'Stop'
$script:linhas = New-Object System.Collections.Generic.List[string]

function Diz($txt, $cor = 'Gray') {
    Write-Host $txt -ForegroundColor $cor
    $script:linhas.Add($txt)
}

# ================= 1. elevacao =================
$admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host "ERRO: leitura de disco bruto exige elevacao." -ForegroundColor Red
    Write-Host "Abra o PowerShell como Administrador e rode de novo." -ForegroundColor Yellow
    exit 1
}

# ================= 2. guardas de identidade =================
$disco = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
if (-not $disco) { Write-Host "ERRO: disco $DiskNumber nao existe." -ForegroundColor Red; exit 1 }

$discoSistema = (Get-Partition -DriveLetter ($env:SystemDrive.TrimEnd(':'))).DiskNumber
if ($DiskNumber -eq $discoSistema) {
    Write-Host "ERRO: disco $DiskNumber e o disco do SISTEMA. Abortado." -ForegroundColor Red; exit 1
}
if ($disco.FriendlyName -match $ModeloProtegido -and $ModeloProtegido -ne '') {
    Write-Host "ERRO: o disco casa com -ModeloProtegido. Abortado." -ForegroundColor Red; exit 1
}
if ($disco.BusType -ne 'USB') {
    Write-Host "ERRO: disco $DiskNumber nao e USB. Abortado por seguranca." -ForegroundColor Red; exit 1
}

Diz "================================================================"
Diz " DIAGNOSTICO exFAT — somente leitura"
Diz " $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Diz "================================================================"
Diz ("Disco    : PhysicalDrive{0}" -f $DiskNumber)
Diz ("Modelo   : {0}" -f $disco.FriendlyName)
Diz ("Barramento: {0}   Estilo: {1}" -f $disco.BusType, $disco.PartitionStyle)
Diz ("Tamanho  : {0} bytes ({1} GiB)" -f $disco.Size, [math]::Round($disco.Size/1GB,2))
Diz ""

# ================= 3. helpers de leitura =================
$fs = $null
$script:SETOR = 512
function LerBytes([int64] $offset, [int] $qtd) {
    # Leitura de disco bruto SO aceita offset e tamanho alinhados ao setor.
    # Le o bloco alinhado que contem a faixa pedida e recorta o pedaco.
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
    return ,$res   # a virgula impede o PowerShell de desembalar o byte[] em Object[]
}
function U16($b, $i) { [BitConverter]::ToUInt16($b, $i) }
function U32($b, $i) { [BitConverter]::ToUInt32($b, $i) }
function U64($b, $i) { [BitConverter]::ToUInt64($b, $i) }

function DataExfat([uint32] $ts) {
    if ($ts -eq 0) { return $null }
    $seg = ($ts -band 0x1F) * 2
    $min = ($ts -shr 5)  -band 0x3F
    $hor = ($ts -shr 11) -band 0x1F
    $dia = ($ts -shr 16) -band 0x1F
    $mes = ($ts -shr 21) -band 0x0F
    $ano = (($ts -shr 25) -band 0x7F) + 1980
    if ($mes -lt 1 -or $mes -gt 12 -or $dia -lt 1 -or $dia -gt 31) { return $null }
    try { return (Get-Date -Year $ano -Month $mes -Day $dia -Hour $hor -Minute $min -Second $seg) } catch { return $null }
}

try {
    $script:fs = New-Object System.IO.FileStream("\\.\PhysicalDrive$DiskNumber",
        [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
} catch {
    Write-Host ("ERRO ao abrir o disco: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

try {
    # ================= 4. MBR =================
    Diz "--- [1/5] Tabela de particao (MBR) ---"
    $mbr = LerBytes 0 512
    $assinatura = ('{0:X2}{1:X2}' -f $mbr[511], $mbr[510])
    Diz ("Assinatura 0x55AA: {0}" -f $(if ($assinatura -eq 'AA55') { 'OK' } else { "AUSENTE (0x$assinatura)" }))

    $parts = @()
    for ($i = 0; $i -lt 4; $i++) {
        $o = 446 + ($i * 16)
        $tipo = $mbr[$o + 4]
        if ($tipo -eq 0) { continue }
        $lbaIni = U32 $mbr ($o + 8)
        $setores = U32 $mbr ($o + 12)
        $parts += [PSCustomObject]@{
            N = $i + 1; Tipo = ('0x{0:X2}' -f $tipo); LbaInicial = $lbaIni
            Setores = $setores; GiB = [math]::Round(($setores * 512) / 1GB, 2)
        }
        Diz ("Particao {0}: tipo 0x{1:X2}  LBA inicial {2}  {3} setores  ({4} GiB)" -f `
            ($i + 1), $tipo, $lbaIni, $setores, [math]::Round(($setores * 512) / 1GB, 2))
    }
    if ($parts.Count -eq 0) { Diz "NENHUMA particao na MBR. Seguindo para varredura de VBR." 'Yellow' }

    # ================= 5. VBR: principal, backup, varredura =================
    Diz ""
    Diz "--- [2/5] Setor de boot do exFAT (VBR) ---"
    $candidatos = @()
    foreach ($p in $parts) { $candidatos += [int64]$p.LbaInicial * 512 }
    if ($candidatos.Count -eq 0) { $candidatos += 0 }

    $vbr = $null; $vbrOrigem = ''; $baseParticao = 0L
    foreach ($base in $candidatos) {
        # VBR principal: setor 0 da particao
        $t = LerBytes $base 512
        $nome = [Text.Encoding]::ASCII.GetString($t, 3, 8)
        if ($nome -eq 'EXFAT   ') {
            $vbr = $t; $vbrOrigem = "principal (offset $base)"; $baseParticao = $base; break
        }
        # VBR de backup: setor 12 da particao
        $t2 = LerBytes ($base + (12 * 512)) 512
        $nome2 = [Text.Encoding]::ASCII.GetString($t2, 3, 8)
        if ($nome2 -eq 'EXFAT   ') {
            $vbr = $t2; $vbrOrigem = "BACKUP, setor 12 (offset $($base + 6144))"; $baseParticao = $base; break
        }
    }

    if (-not $vbr) {
        Diz "VBR principal e backup ilegiveis. Varrendo os primeiros 2 GiB por assinatura EXFAT..." 'Yellow'
        $passo = 1MB
        for ($off = 0L; $off -lt 2GB; $off += $passo) {
            $blk = LerBytes $off $passo
            for ($k = 0; $k -lt $passo; $k += 512) {
                if ($blk[$k+3] -eq 0x45 -and $blk[$k+4] -eq 0x58 -and $blk[$k+5] -eq 0x46 -and $blk[$k+6] -eq 0x41 -and $blk[$k+7] -eq 0x54) {
                    $vbr = New-Object byte[] 512
                    [Array]::Copy($blk, $k, $vbr, 0, 512)
                    $vbrOrigem = "encontrado por varredura (offset $($off + $k))"
                    $baseParticao = $off + $k
                    break
                }
            }
            if ($vbr) { break }
        }
    }

    if (-not $vbr) {
        Diz ""
        Diz "RESULTADO: nenhum setor de boot exFAT encontrado." 'Red'
        Diz "O dano NAO e raso. O caminho passa a ser carving com PhotoRec + remontagem" 'Yellow'
        Diz "de fragmentos, que exige a imagem completa do cartao (119 GiB de disco)." 'Yellow'
        exit 2
    }

    Diz ("VBR encontrado: {0}" -f $vbrOrigem) 'Green'
    if ($vbrOrigem -like 'BACKUP*') {
        Diz "O principal esta destruido mas o BACKUP esta intacto — este e o cenario bom." 'Green'
    }

    # ================= 6. parametros do sistema de arquivos =================
    $bytesPorSetorShift = $vbr[108]
    $setoresPorClusterShift = $vbr[109]
    if ($bytesPorSetorShift -lt 9 -or $bytesPorSetorShift -gt 12) {
        Diz ("VBR com BytesPerSectorShift invalido ({0}). Estrutura suspeita." -f $bytesPorSetorShift) 'Red'
        exit 2
    }
    $bps          = [int][math]::Pow(2, $bytesPorSetorShift)
    $spc          = [int][math]::Pow(2, $setoresPorClusterShift)
    $partOffset   = U64 $vbr 64
    $volLength    = U64 $vbr 72
    $fatOffset    = U32 $vbr 80
    $fatLength    = U32 $vbr 84
    $heapOffset   = U32 $vbr 88
    $clusterCount = U32 $vbr 92
    $rootCluster  = U32 $vbr 96
    $numFats      = $vbr[110]
    $percentInUse = $vbr[112]
    $volFlags     = U16 $vbr 106

    $bytesPorCluster = [int64]$bps * $spc
    $inicioVol = $baseParticao

    Diz ""
    Diz "--- [3/5] Parametros do sistema de arquivos ---"
    Diz ("Bytes por setor    : {0}" -f $bps)
    Diz ("Setores por cluster: {0}  (cluster = {1} KiB)" -f $spc, ($bytesPorCluster/1KB))
    Diz ("Total de clusters  : {0}" -f $clusterCount)
    Diz ("FAT em setor       : {0}   ({1} setores, {2} FATs)" -f $fatOffset, $fatLength, $numFats)
    Diz ("Heap em setor      : {0}" -f $heapOffset)
    Diz ("Root no cluster    : {0}" -f $rootCluster)
    Diz ("VolumeFlags        : 0x{0:X4}{1}" -f $volFlags, $(if ($volFlags -band 0x02) { '  <- ATENCAO: VolumeDirty' } else { '' }))
    if ($percentInUse -le 100) {
        Diz ("PercentInUse (campo do VBR): {0}%  =>  ~{1} GiB em uso" -f `
            $percentInUse, [math]::Round(($percentInUse/100.0) * ($clusterCount * $bytesPorCluster)/1GB, 2)) 'Cyan'
    } else {
        Diz "PercentInUse: nao disponivel (0xFF)"
    }

    function ClusterParaOffset([int64] $cluster) {
        return $inicioVol + ([int64]$heapOffset * $bps) + (($cluster - 2) * $bytesPorCluster)
    }

    # ================= 7. FAT e cadeias =================
    $fatBase  = $inicioVol + ([int64]$fatOffset * $bps)
    $fatBytes = [int64]$fatLength * $bps
    $script:fatCache = $null
    if ($fatBytes -gt 0 -and $fatBytes -le 128MB) {
        Diz ("Carregando a FAT inteira na memoria ({0} MiB)..." -f [math]::Round($fatBytes/1MB,1))
        $script:fatCache = LerBytes $fatBase ([int]$fatBytes)
    }

    function CadeiaDeClusters([int64] $primeiro, [bool] $semFat, [int64] $tamanho) {
        $lista = New-Object System.Collections.Generic.List[int64]
        if ($semFat) {
            $n = [math]::Max(1, [math]::Ceiling($tamanho / $bytesPorCluster))
            for ($i = 0; $i -lt $n; $i++) { $lista.Add($primeiro + $i) }
            return ,$lista
        }
        $c = $primeiro; $limite = 0
        while ($c -ge 2 -and $c -lt ($clusterCount + 2) -and $limite -lt 2000000) {
            $lista.Add($c)
            if ($script:fatCache) {
                $pos = [int]($c * 4)
                if ($pos + 4 -gt $script:fatCache.Length) { break }
                $prox = U32 $script:fatCache $pos
            } else {
                $prox = U32 (LerBytes ($fatBase + ($c * 4)) 4) 0
            }
            # 0xFFFFFFF7 como literal vira -9 (Int32) no PowerShell 5.1: usar o decimal
            if ($prox -ge 4294967287 -or $prox -lt 2) { break }
            $c = $prox; $limite++
        }
        return ,$lista
    }

    # ================= 8. percorrer diretorios =================
    Diz ""
    Diz "--- [4/5] Conteudo (travessia do diretorio raiz) ---"
    $arquivos = New-Object System.Collections.Generic.List[object]
    $bitmapInfo = $null
    $entradasVistas = 0
    $pastas = 0

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
            $script:entradasVistas++
            if ($script:entradasVistas -gt $MaxEntradas) { return }

            if ($tipo -eq 0x81) {
                $script:bitmapInfo = [PSCustomObject]@{
                    FirstCluster = (U32 $b ($i + 20)); DataLength = (U64 $b ($i + 24))
                    Flags = $b[$i + 1]
                }
            }
            elseif ($tipo -eq 0x85) {
                $secundarios = $b[$i + 1]
                $attrs = U16 $b ($i + 4)
                $ehPasta = [bool]($attrs -band 0x10)
                $modificado = DataExfat (U32 $b ($i + 12))
                $nome = ''
                $primCluster = 0; $tam = [int64]0; $flagsSec = 0
                for ($s = 1; $s -le $secundarios; $s++) {
                    $j = $i + ($s * 32)
                    if ($j + 32 -gt $b.Length) { break }
                    if ($b[$j] -eq 0xC0) {
                        $flagsSec = $b[$j + 1]
                        $primCluster = U32 $b ($j + 20)
                        $tam = [int64](U64 $b ($j + 24))
                    } elseif ($b[$j] -eq 0xC1) {
                        $nome += [Text.Encoding]::Unicode.GetString($b, $j + 2, 30)
                    }
                }
                $nome = $nome.TrimEnd([char]0)
                $semFatSec = [bool]($flagsSec -band 0x02)
                $full = if ($caminho) { "$caminho\$nome" } else { $nome }

                if ($ehPasta) {
                    $script:pastas++
                    if ($primCluster -ge 2) { LerDiretorio $primCluster $semFatSec $tam $full ($nivel + 1) }
                } else {
                    $script:arquivos.Add([PSCustomObject]@{
                        Caminho = $full; Bytes = $tam; MB = [math]::Round($tam/1MB,1)
                        Cluster = $primCluster; Modificado = $modificado
                        Ext = ([System.IO.Path]::GetExtension($nome)).ToLower()
                    })
                }
                $i += 32 * ($secundarios + 1)
                continue
            }
            $i += 32
        }
    }

    LerDiretorio $rootCluster $false 0 '' 0

    Diz ("Pastas encontradas  : {0}" -f $pastas)
    Diz ("Arquivos encontrados: {0}" -f $arquivos.Count)

    if ($arquivos.Count -eq 0) {
        Diz "O diretorio raiz nao rendeu arquivos. A FAT ou o heap podem estar danificados." 'Yellow'
    }

    # ================= 9. bitmap de alocacao =================
    Diz ""
    Diz "--- [5/5] Espaco realmente em uso ---"
    if ($bitmapInfo) {
        $pop = New-Object int[] 256
        for ($v = 0; $v -lt 256; $v++) { $n = 0; $x = $v; while ($x) { $n += ($x -band 1); $x = $x -shr 1 }; $pop[$v] = $n }
        $cad = CadeiaDeClusters $bitmapInfo.FirstCluster ([bool]0) $bitmapInfo.DataLength
        $usados = 0L; $lidosBmp = 0L
        foreach ($cl in $cad) {
            $blk = LerBytes (ClusterParaOffset $cl) $bytesPorCluster
            foreach ($byte in $blk) { $usados += $pop[$byte] }
            $lidosBmp += $bytesPorCluster
            if ($lidosBmp -ge $bitmapInfo.DataLength) { break }
        }
        $gbUsados = [math]::Round(($usados * $bytesPorCluster)/1GB, 2)
        Diz ("Clusters em uso: {0} de {1}" -f $usados, $clusterCount)
        Diz ("MATERIAL NO CARTAO: {0} GiB" -f $gbUsados) 'Cyan'
    } else {
        Diz "Bitmap de alocacao nao localizado no raiz." 'Yellow'
    }

    $somaArquivos = ($arquivos | Measure-Object Bytes -Sum).Sum
    if ($somaArquivos) {
        Diz ("Soma dos arquivos listados: {0} GiB" -f [math]::Round($somaArquivos/1GB,2)) 'Cyan'
    }

    # ================= 10. resumo de midia =================
    Diz ""
    Diz "=== POR EXTENSAO ==="
    $arquivos | Group-Object Ext | Sort-Object { ($_.Group | Measure-Object Bytes -Sum).Sum } -Descending |
        ForEach-Object {
            Diz ("{0,-8} {1,5} arquivos  {2,9} GiB" -f $_.Name, $_.Count,
                [math]::Round((($_.Group | Measure-Object Bytes -Sum).Sum)/1GB,2))
        }

    # classificacao por papel do arquivo na camera
    foreach ($a in $arquivos) {
        $nome = Split-Path $a.Caminho -Leaf
        $classe = 'auxiliar (thumb/indice)'
        if     ($nome -like 'LRV_*')                         { $classe = 'LRV proxy (descartavel)' }
        elseif ($nome -like 'VID_*' -and $a.Ext -eq '.insv')  { $classe = 'VID master 360 (essencial)' }
        elseif ($a.Ext -eq '.mp4')                            { $classe = 'MP4 lente unica (essencial)' }
        $a | Add-Member -NotePropertyName Classe -NotePropertyValue $classe -Force
    }

    Diz ""
    Diz "=== POR PAPEL NA CAMERA ==="
    $arquivos | Group-Object Classe | Sort-Object { ($_.Group | Measure-Object Bytes -Sum).Sum } -Descending |
        ForEach-Object {
            Diz ("{0,-30} {1,4} arquivos  {2,8} GiB" -f $_.Name, $_.Count,
                [math]::Round((($_.Group | Measure-Object Bytes -Sum).Sum)/1GB,2))
        }

    $essencial = ($arquivos | Where-Object { $_.Classe -like '*essencial*' } | Measure-Object Bytes -Sum).Sum
    $descartavel = ($arquivos | Where-Object { $_.Classe -like 'LRV*' } | Measure-Object Bytes -Sum).Sum
    Diz ""
    Diz ("ESSENCIAL (sem os proxies): {0} GiB" -f [math]::Round($essencial/1GB,2)) 'Cyan'
    Diz ("Proxies LRV, se descartados, liberam: {0} GiB" -f [math]::Round($descartavel/1GB,2)) 'Cyan'

    Diz ""
    Diz "=== PARES DE LENTE (um clipe 360 precisa dos DOIS) ==="
    $pares = $arquivos | Where-Object { $_.Caminho -match 'VID_(\d{8}_\d{6})_(00|10)_(\d+)\.insv$' } | ForEach-Object {
        if ($_.Caminho -match 'VID_(\d{8}_\d{6})_(00|10)_(\d+)\.insv$') {
            [PSCustomObject]@{ Clipe = "$($Matches[1])_$($Matches[3])"; Lente = $Matches[2]; Bytes = $_.Bytes }
        }
    } | Group-Object Clipe
    $completos = ($pares | Where-Object { $_.Count -eq 2 }).Count
    $orfaos    = $pares | Where-Object { $_.Count -ne 2 }
    Diz ("Clipes 360 com o par completo: {0}" -f $completos)
    if ($orfaos) {
        Diz ("Clipes com lente faltando: {0}" -f $orfaos.Count) 'Yellow'
        $orfaos | ForEach-Object { Diz ("  {0} (so a lente {1})" -f $_.Name, ($_.Group.Lente -join ',')) }
    } else { Diz "Nenhum clipe orfao: todos os pares estao completos." 'Green' }

    Diz ""
    Diz "=== TODOS OS ARQUIVOS ==="
    $arquivos | Sort-Object Bytes -Descending | ForEach-Object {
        Diz ("{0,9} MB  {1}  {2}" -f $_.MB, $(if ($_.Modificado) { $_.Modificado.ToString('yyyy-MM-dd HH:mm') } else { '                ' }), $_.Caminho)
    }

    $csv = Join-Path (Split-Path $Relatorio -Parent) 'inventario.csv'
    $arquivos | Select-Object Caminho, Classe, Bytes, MB, Cluster, Ext,
        @{n='Modificado';e={ if ($_.Modificado) { $_.Modificado.ToString('yyyy-MM-dd HH:mm:ss') } else { '' } }} |
        Sort-Object Bytes -Descending | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    Diz ""
    Diz ("Inventario completo em CSV: {0}" -f $csv) 'Cyan'

    $datas = $arquivos | Where-Object { $_.Modificado } | Sort-Object Modificado
    if ($datas) {
        Diz ""
        Diz ("Periodo da gravacao: {0}  ate  {1}" -f `
            $datas[0].Modificado.ToString('yyyy-MM-dd'), $datas[-1].Modificado.ToString('yyyy-MM-dd')) 'Cyan'
    }

    # ================= 11. veredito de espaco =================
    $precisa = if ($somaArquivos) { $somaArquivos } else { 0 }
    $livreD = (Get-Volume -DriveLetter $letraDestino).SizeRemaining
    Diz ""
    Diz "================= VEREDITO DE ESPACO ================="
    Diz ("Material a copiar : {0} GiB" -f [math]::Round($precisa/1GB,2))
    Diz ("Livre em D:       : {0} GiB" -f [math]::Round($livreD/1GB,2))
    if ($precisa -gt 0 -and $livreD -gt ($precisa * 1.05)) {
        Diz "CABE em D: sem comprar disco. Copia direta do cartao, sem imagem." 'Green'
    } elseif ($precisa -gt 0) {
        Diz ("NAO cabe. Faltam {0} GiB — ou copia em lotes, ou disco externo." -f `
            [math]::Round(($precisa * 1.05 - $livreD)/1GB,2)) 'Yellow'
    }
    Diz "======================================================"
}
catch {
    Diz ""
    Diz "!!! ERRO DURANTE O DIAGNOSTICO !!!" 'Red'
    Diz ("Mensagem: " + $_.Exception.Message) 'Red'
    Diz ("Tipo    : " + $_.Exception.GetType().FullName) 'Red'
    Diz ("Local   : " + ($_.InvocationInfo.PositionMessage -replace "`r?`n", ' | ')) 'Red'
}
finally {
    if ($script:fs) { $script:fs.Dispose() }
    $dir = Split-Path $Relatorio -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $script:linhas | Out-File -FilePath $Relatorio -Encoding utf8
    Write-Host "`nRelatorio salvo em: $Relatorio" -ForegroundColor Cyan
}
