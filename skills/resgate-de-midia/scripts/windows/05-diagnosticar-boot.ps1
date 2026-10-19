<#
    05-diagnosticar-boot.ps1 — descobre POR QUE o Windows rejeita o volume exFAT.

    SOMENTE LEITURA. Nao escreve nada, nao conserta nada.

    O exFAT tem duas regioes de boot de 12 setores cada:
      setor  0     Main Boot Sector (VBR)
      setores 1-8  Main Extended Boot Sectors   (cada um fecha com 0xAA550000)
      setor  9     Main OEM Parameters
      setor 10     Main Reserved
      setor 11     Main Boot Checksum  (um UInt32 repetido por todo o setor)
      setores 12-23  a mesma coisa, de backup

    O driver do Windows recalcula o checksum dos setores 0-10 e compara com o 11.
    Se nao bate, ele rejeita o volume INTEIRO - mesmo com FAT, diretorios e dados
    perfeitos. Este script diz exatamente qual verificacao falha.

    Uso (PowerShell COMO ADMINISTRADOR):
        .\05-diagnosticar-boot.ps1 -DiskNumber 2
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][int] $DiskNumber,
    # modelo de disco a recusar por seguranca (ex: o SSD onde fica o destino)
    [string] $ModeloProtegido = '',
    [string] $Relatorio = '.\log\diagnostico-boot.txt'
)

$ErrorActionPreference = 'Stop'
$script:linhas = New-Object System.Collections.Generic.List[string]
function Diz($txt, $cor = 'Gray') { Write-Host $txt -ForegroundColor $cor; $script:linhas.Add($txt) }

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: exige elevacao." -ForegroundColor Red; exit 1
}

# ---------- guardas de identidade ----------
$disco = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
if (-not $disco) { Write-Host "ERRO: disco $DiskNumber nao existe." -ForegroundColor Red; exit 1 }
$discoSistema = (Get-Partition -DriveLetter ($env:SystemDrive.TrimEnd(':'))).DiskNumber
if ($DiskNumber -eq $discoSistema)        { Write-Host "ERRO: disco do SISTEMA." -ForegroundColor Red; exit 1 }
if ($disco.FriendlyName -match $ModeloProtegido -and $ModeloProtegido -ne '')  { Write-Host "ERRO: o disco casa com -ModeloProtegido." -ForegroundColor Red; exit 1 }
if ($disco.BusType -ne 'USB')             { Write-Host "ERRO: nao e USB." -ForegroundColor Red; exit 1 }

$script:SETOR = 512
$script:fs = $null
function LerBytes([int64] $offset, [int] $qtd) {
    $s = $script:SETOR
    $ini = [int64]([math]::Floor($offset / $s) * $s)
    $fim = [int64]([math]::Ceiling(($offset + $qtd) / $s) * $s)
    $bruto = New-Object byte[] ($fim - $ini)
    $script:fs.Position = $ini
    $lidos = 0
    while ($lidos -lt $bruto.Length) { $n = $script:fs.Read($bruto, $lidos, $bruto.Length - $lidos); if ($n -le 0) { break }; $lidos += $n }
    $res = New-Object byte[] $qtd
    $d = [int]($offset - $ini); $c = [math]::Min($qtd, $bruto.Length - $d)
    if ($c -gt 0) { [Array]::Copy($bruto, $d, $res, 0, $c) }
    return ,$res
}
function U16($b, $i) { [BitConverter]::ToUInt16($b, $i) }
function U32($b, $i) { [BitConverter]::ToUInt32($b, $i) }
function U64($b, $i) { [BitConverter]::ToUInt64($b, $i) }

# checksum do exFAT: rotacao de 1 bit a direita + soma, byte a byte
function BootChecksum([byte[]] $dados, [int] $qtdBytes) {
    [uint32] $soma = 0
    for ($i = 0; $i -lt $qtdBytes; $i++) {
        # VolumeFlags (106,107) e PercentInUse (112) ficam FORA do calculo
        if ($i -eq 106 -or $i -eq 107 -or $i -eq 112) { continue }
        $soma = ((($soma -band 1) * 2147483648) + ($soma -shr 1) + $dados[$i]) -band 4294967295
    }
    return [uint32]$soma
}
function TabelaChecksum([byte[]] $dados, [int] $qtdBytes) {
    [uint32] $soma = 0
    for ($i = 0; $i -lt $qtdBytes; $i++) {
        $soma = ((($soma -band 1) * 2147483648) + ($soma -shr 1) + $dados[$i]) -band 4294967295
    }
    return [uint32]$soma
}

$script:fs = New-Object System.IO.FileStream("\\.\PhysicalDrive$DiskNumber",
    [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)

try {
    Diz "================================================================"
    Diz " POR QUE O WINDOWS REJEITA O VOLUME - somente leitura"
    Diz " $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Diz "================================================================"
    Diz ("Disco: PhysicalDrive{0} ({1})" -f $DiskNumber, $disco.FriendlyName)
    Diz ""

    # ---------- onde comeca a particao ----------
    $mbr = LerBytes 0 512
    $baseParticao = 0L
    for ($i = 0; $i -lt 4; $i++) {
        $o = 446 + ($i * 16)
        if ($mbr[$o + 4] -ne 0) { $baseParticao = [int64](U32 $mbr ($o + 8)) * 512; break }
    }
    Diz ("Particao comeca no byte {0} (LBA {1})" -f $baseParticao, ($baseParticao / 512))

    # ---------- as duas regioes de boot ----------
    $achados = New-Object System.Collections.Generic.List[object]
    foreach ($reg in @(
        @{ nome = 'PRINCIPAL'; setorBase = 0 },
        @{ nome = 'BACKUP   '; setorBase = 12 })) {

        $off = $baseParticao + ([int64]$reg.setorBase * 512)
        Diz ""
        Diz ("--- REGIAO DE BOOT {0} (setor {1}) ---" -f $reg.nome.Trim(), $reg.setorBase)

        $regiao = LerBytes $off (12 * 512)       # 12 setores
        $vbr = New-Object byte[] 512
        [Array]::Copy($regiao, 0, $vbr, 0, 512)

        $nomeFs = [Text.Encoding]::ASCII.GetString($vbr, 3, 8)
        $temAssin = ($vbr[510] -eq 0x55 -and $vbr[511] -eq 0xAA)
        Diz ("  FileSystemName : '{0}'  {1}" -f $nomeFs, $(if ($nomeFs -eq 'EXFAT   ') { 'OK' } else { 'INVALIDO' }))
        Diz ("  Assinatura 0x55AA no fim do setor 0: {0}" -f $(if ($temAssin) { 'OK' } else { 'AUSENTE' }))

        if ($nomeFs -ne 'EXFAT   ') {
            Diz "  Regiao inutilizavel: sem VBR exFAT aqui." 'Red'
            $achados.Add([PSCustomObject]@{ Regiao = $reg.nome; Valida = $false; ChecksumOk = $false; Gravado = 0; Calculado = 0; Offset = $off })
            continue
        }

        # Extended Boot Sectors (1 a 8): cada um fecha com 0xAA550000
        $ebsOk = 0; $ebsVazio = 0
        for ($s = 1; $s -le 8; $s++) {
            $p = $s * 512
            $sig = U32 $regiao ($p + 508)
            $todoZero = $true
            for ($k = 0; $k -lt 508; $k++) { if ($regiao[$p + $k] -ne 0) { $todoZero = $false; break } }
            if ($sig -eq 0xAA550000) { $ebsOk++ } elseif ($sig -eq 0 -and $todoZero) { $ebsVazio++ }
        }
        Diz ("  Extended Boot Sectors (1-8): {0} com assinatura, {1} totalmente zerados" -f $ebsOk, $ebsVazio)

        # o checksum gravado no setor 11, repetido 128 vezes
        $gravado = U32 $regiao (11 * 512)
        $repetido = $true
        for ($k = 0; $k -lt 512; $k += 4) {
            if ((U32 $regiao ((11 * 512) + $k)) -ne $gravado) { $repetido = $false; break }
        }

        # o checksum recalculado sobre os setores 0-10
        $calculado = BootChecksum $regiao (11 * 512)

        Diz ("  Checksum gravado  (setor {0}): 0x{1:X8}{2}" -f ($reg.setorBase + 11), $gravado, `
            $(if ($repetido) { '  (repetido corretamente nos 512 bytes)' } else { '  <- NAO esta repetido: setor corrompido' }))
        Diz ("  Checksum recalculado dos dados : 0x{0:X8}" -f $calculado)

        $bate = ($gravado -eq $calculado)
        if ($bate) { Diz "  >>> CHECKSUM BATE" 'Green' } else { Diz "  >>> CHECKSUM NAO BATE - esta e a causa da rejeicao" 'Red' }

        $achados.Add([PSCustomObject]@{
            Regiao = $reg.nome.Trim(); Valida = $true; ChecksumOk = $bate
            Gravado = $gravado; Calculado = $calculado; Offset = $off; Repetido = $repetido
        })
    }

    # ---------- comparar as duas regioes byte a byte ----------
    Diz ""
    Diz "--- AS DUAS REGIOES SAO IGUAIS? ---"
    $rp = LerBytes $baseParticao (12 * 512)
    $rb = LerBytes ($baseParticao + 6144) (12 * 512)
    $difs = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt (12 * 512); $i++) { if ($rp[$i] -ne $rb[$i]) { $difs.Add($i) } }
    if ($difs.Count -eq 0) {
        Diz "  identicas byte a byte"
    } else {
        Diz ("  diferem em {0} bytes" -f $difs.Count)
        $porSetor = $difs | Group-Object { [math]::Floor($_ / 512) } | Sort-Object Name
        foreach ($g in $porSetor) {
            Diz ("    setor {0}: {1} bytes diferentes (offsets {2}{3})" -f $g.Name, $g.Count,
                (($g.Group | Select-Object -First 8 | ForEach-Object { $_ % 512 }) -join ','),
                $(if ($g.Count -gt 8) { ',...' } else { '' }))
        }
    }

    # ---------- a Upcase Table ----------
    Diz ""
    Diz "--- UPCASE TABLE (o Windows tambem valida o checksum dela) ---"
    $vbrOk = $achados | Where-Object { $_.Valida } | Select-Object -First 1
    $vbr = LerBytes $vbrOk.Offset 512
    $bps = [int][math]::Pow(2, $vbr[108]); $spc = [int][math]::Pow(2, $vbr[109])
    $fatOffset = U32 $vbr 80; $fatLength = U32 $vbr 84
    $heapOffset = U32 $vbr 88; $clusterCount = U32 $vbr 92; $rootCluster = U32 $vbr 96
    $bpc = [int64]$bps * $spc
    $fat = LerBytes ($baseParticao + ([int64]$fatOffset * $bps)) ([int]([int64]$fatLength * $bps))
    function Off([int64]$c) { return $baseParticao + ([int64]$heapOffset * $bps) + (($c - 2) * $bpc) }

    $rootBytes = New-Object System.Collections.Generic.List[byte]
    $c = [int64]$rootCluster; $guarda = 0
    while ($c -ge 2 -and $c -lt ($clusterCount + 2) -and $guarda -lt 1000) {
        $rootBytes.AddRange((LerBytes (Off $c) $bpc))
        $prox = U32 $fat ([int]($c * 4))
        if ($prox -ge 4294967287 -or $prox -lt 2) { break }
        $c = $prox; $guarda++
    }
    $rb2 = $rootBytes.ToArray()
    $i = 0; $achouUpcase = $false; $achouBitmap = $false; $rotulo = ''
    while ($i + 32 -le $rb2.Length) {
        $t = $rb2[$i]
        if ($t -eq 0x00) { break }
        if ($t -eq 0x82) {
            $achouUpcase = $true
            $chkGravado = U32 $rb2 ($i + 4)
            $primCluster = U32 $rb2 ($i + 20)
            $tam = [int64](U64 $rb2 ($i + 24))
            Diz ("  entrada encontrada: cluster {0}, {1} bytes, checksum gravado 0x{2:X8}" -f $primCluster, $tam, $chkGravado)
            if ($primCluster -ge 2 -and $tam -gt 0 -and $tam -le 1MB) {
                $tabela = LerBytes (Off $primCluster) ([int]$tam)
                $chkCalc = TabelaChecksum $tabela ([int]$tam)
                Diz ("  checksum recalculado: 0x{0:X8}" -f $chkCalc)
                if ($chkCalc -eq $chkGravado) { Diz "  >>> UPCASE TABLE OK" 'Green' }
                else { Diz "  >>> UPCASE TABLE CORROMPIDA" 'Red' }
            }
        }
        elseif ($t -eq 0x81) { $achouBitmap = $true }
        elseif ($t -eq 0x83) {
            $n = $rb2[$i + 1]
            if ($n -gt 0 -and $n -le 11) { $rotulo = [Text.Encoding]::Unicode.GetString($rb2, $i + 2, $n * 2) }
        }
        $i += 32
    }
    if (-not $achouUpcase) { Diz "  entrada da Upcase Table NAO existe no raiz" 'Red' }
    if (-not $achouBitmap) { Diz "  entrada do Allocation Bitmap NAO existe no raiz" 'Red' }
    Diz ("  rotulo do volume: '{0}'" -f $rotulo)

    # ---------- veredito ----------
    Diz ""
    Diz "===================== VEREDITO ====================="
    $prin = $achados | Where-Object { $_.Regiao -eq 'PRINCIPAL' }
    $back = $achados | Where-Object { $_.Regiao -eq 'BACKUP' }
    foreach ($a in $achados) {
        Diz ("{0,-10} VBR valido: {1,-5}  checksum bate: {2}" -f $a.Regiao, $a.Valida, $a.ChecksumOk)
    }
    Diz ""
    if ($prin.ChecksumOk -and $back.ChecksumOk) {
        Diz "Os dois checksums batem. A rejeicao vem de OUTRA coisa" 'Yellow'
        Diz "(upcase, bitmap, ou um campo que o driver do Windows nao aceita)." 'Yellow'
        Diz "CONSERTO: nao e o checksum. Ver o relatorio acima." 'Yellow'
    } elseif (-not $prin.ChecksumOk -and $back.ChecksumOk) {
        Diz "A regiao PRINCIPAL tem checksum errado e a de BACKUP esta boa." 'Cyan'
        Diz "CONSERTO: copiar os 12 setores da regiao de backup sobre a principal." 'Cyan'
        Diz "Sao 6144 bytes. O resto do cartao nao e tocado." 'Cyan'
    } elseif ($prin.ChecksumOk -and -not $back.ChecksumOk) {
        Diz "A PRINCIPAL esta boa e o BACKUP esta errado." 'Cyan'
        Diz "O Windows le a principal, entao o checksum nao explica a rejeicao." 'Yellow'
        Diz "CONSERTO possivel: regravar o backup a partir da principal." 'Cyan'
    } else {
        Diz "Os DOIS checksums estao errados." 'Cyan'
        Diz "CONSERTO: recalcular e regravar o setor 11 (e o 23) - 512 bytes cada." 'Cyan'
        Diz ("Valor correto a gravar: 0x{0:X8} (principal)" -f $prin.Calculado) 'Cyan'
    }
    Diz "===================================================="
}
catch {
    Diz ""
    Diz "!!! ERRO !!!" 'Red'
    Diz ("Mensagem: " + $_.Exception.Message) 'Red'
    Diz ("Local   : " + ($_.InvocationInfo.PositionMessage -replace "`r?`n", ' | ')) 'Red'
}
finally {
    if ($script:fs) { $script:fs.Dispose() }
    $d = Split-Path $Relatorio -Parent
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    $script:linhas | Out-File -FilePath $Relatorio -Encoding utf8
    Write-Host "`nRelatorio em: $Relatorio" -ForegroundColor Cyan
}
