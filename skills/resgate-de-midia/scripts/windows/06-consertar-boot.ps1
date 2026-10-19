<#
    06-consertar-boot.ps1 — conserta a regiao de boot do exFAT.

    O QUE FAZ: copia o setor 1 (primeiro Extended Boot Sector) da regiao de BACKUP
    sobre o da regiao PRINCIPAL. 512 bytes. Com isso o checksum da principal volta
    a bater e o Windows passa a montar o volume de novo.

    *** ESTE E O UNICO SCRIPT DESTA PASTA QUE ESCREVE NO CARTAO. ***

    Protecoes:
      - roda em modo -Simular por padrao: prova em memoria que o conserto funciona
        (recalcula o checksum com o setor corrigido) SEM tocar no cartao
      - para escrever de verdade exige -Escrever E -TenhoSegundaCopia
      - antes de escrever, salva os 24 setores originais num arquivo (da para desfazer)
      - depois de escrever, rele do cartao e confere
      - recusa rodar sobre o disco do sistema ou sobre o SSD de trabalho

    Uso (PowerShell COMO ADMINISTRADOR):
        .\06-consertar-boot.ps1 -DiskNumber 2                               # simula
        .\06-consertar-boot.ps1 -DiskNumber 2 -Escrever -TenhoSegundaCopia  # conserta
        .\06-consertar-boot.ps1 -DiskNumber 2 -Desfazer                     # reverte
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][int] $DiskNumber,
    # modelo de disco a recusar por seguranca (ex: o SSD onde fica o destino)
    [string] $ModeloProtegido = '',
    [switch] $Escrever,
    [switch] $TenhoSegundaCopia,
    [switch] $Desfazer,
    [string] $BackupSetores = '.\log\boot-original-24setores.bin',
    [string] $Log           = '.\log\conserto-boot.txt'
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
if ($DiskNumber -eq $discoSistema)       { Write-Host "ERRO: disco do SISTEMA. Abortado." -ForegroundColor Red; exit 1 }
if ($disco.FriendlyName -match $ModeloProtegido -and $ModeloProtegido -ne '') { Write-Host "ERRO: o disco casa com -ModeloProtegido. Abortado." -ForegroundColor Red; exit 1 }
if ($disco.BusType -ne 'USB')            { Write-Host "ERRO: nao e USB. Abortado." -ForegroundColor Red; exit 1 }

$SETOR = 512
function U32($b, $i) { [BitConverter]::ToUInt32($b, $i) }
function BootChecksum([byte[]] $dados, [int] $qtdBytes) {
    [uint32] $soma = 0
    for ($i = 0; $i -lt $qtdBytes; $i++) {
        if ($i -eq 106 -or $i -eq 107 -or $i -eq 112) { continue }   # VolumeFlags e PercentInUse ficam fora
        $soma = ((($soma -band 1) * 2147483648) + ($soma -shr 1) + $dados[$i]) -band 4294967295
    }
    return [uint32]$soma
}

$modo = 'SIMULACAO'
if ($Desfazer) { $modo = 'DESFAZER' } elseif ($Escrever) { $modo = 'ESCRITA REAL' }

Diz "================================================================"
Diz " CONSERTO DA REGIAO DE BOOT exFAT - modo: $modo"
Diz " $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Diz "================================================================"
Diz ("Disco: PhysicalDrive{0} ({1}, {2} GiB)" -f $DiskNumber, $disco.FriendlyName, [math]::Round($disco.Size/1GB,2))

# ---------- abre em leitura (ou leitura+escrita) ----------
$acesso = if ($Escrever -or $Desfazer) { [System.IO.FileAccess]::ReadWrite } else { [System.IO.FileAccess]::Read }
$fs = $null
try {
    $fs = New-Object System.IO.FileStream("\\.\PhysicalDrive$DiskNumber",
        [System.IO.FileMode]::Open, $acesso, [System.IO.FileShare]::ReadWrite)
} catch {
    Diz ("ERRO ao abrir o disco: " + $_.Exception.Message) 'Red'
    if ($Escrever -or $Desfazer) {
        Diz "" 'Yellow'
        Diz "Escrita em disco bruto costuma exigir que o volume esteja offline." 'Yellow'
        Diz "No PowerShell elevado, rode antes:" 'Yellow'
        Diz "    Set-Disk -Number $DiskNumber -IsOffline `$true" 'Yellow'
        Diz "e depois, ao terminar:" 'Yellow'
        Diz "    Set-Disk -Number $DiskNumber -IsOffline `$false" 'Yellow'
    }
    exit 1
}

function LerSetores([int64] $offsetBytes, [int] $qtdSetores) {
    $buf = New-Object byte[] ($qtdSetores * $SETOR)
    $fs.Position = $offsetBytes
    $lidos = 0
    while ($lidos -lt $buf.Length) { $n = $fs.Read($buf, $lidos, $buf.Length - $lidos); if ($n -le 0) { break }; $lidos += $n }
    return ,$buf
}

try {
    # ---------- onde comeca a particao ----------
    $mbr = LerSetores 0 1
    $baseParticao = 0L
    for ($i = 0; $i -lt 4; $i++) {
        $o = 446 + ($i * 16)
        if ($mbr[$o + 4] -ne 0) { $baseParticao = [int64](U32 $mbr ($o + 8)) * 512; break }
    }
    if ($baseParticao -eq 0) { Diz "ERRO: nenhuma particao na MBR." 'Red'; exit 1 }
    Diz ("Particao no byte {0} (LBA {1})" -f $baseParticao, ($baseParticao / 512))

    # ---------- DESFAZER ----------
    if ($Desfazer) {
        if (-not (Test-Path $BackupSetores)) { Diz "ERRO: nao achei $BackupSetores" 'Red'; exit 1 }
        $orig = [System.IO.File]::ReadAllBytes($BackupSetores)
        if ($orig.Length -ne (24 * $SETOR)) { Diz ("ERRO: backup tem {0} bytes, esperado 12288." -f $orig.Length) 'Red'; exit 1 }
        Diz ("Restaurando os 24 setores originais de {0}" -f $BackupSetores) 'Yellow'
        $fs.Position = $baseParticao
        $fs.Write($orig, 0, $orig.Length)
        $fs.Flush()
        $conf = LerSetores $baseParticao 24
        $igual = $true
        for ($i = 0; $i -lt $orig.Length; $i++) { if ($conf[$i] -ne $orig[$i]) { $igual = $false; break } }
        if ($igual) { Diz ">>> RESTAURADO. O cartao voltou ao estado de antes do conserto." 'Green' }
        else        { Diz ">>> A releitura nao confere. Verifique antes de usar o cartao." 'Red' }
        exit 0
    }

    # ---------- le as duas regioes ----------
    $prin = LerSetores $baseParticao 12
    $back = LerSetores ($baseParticao + (12 * $SETOR)) 12

    $nomeP = [Text.Encoding]::ASCII.GetString($prin, 3, 8)
    $nomeB = [Text.Encoding]::ASCII.GetString($back, 3, 8)
    if ($nomeP -ne 'EXFAT   ' -or $nomeB -ne 'EXFAT   ') {
        Diz ("ERRO: uma das regioes nao e exFAT (principal '{0}', backup '{1}'). Abortado." -f $nomeP, $nomeB) 'Red'
        exit 1
    }

    $chkGravadoP = U32 $prin (11 * $SETOR)
    $chkCalcP    = BootChecksum $prin (11 * $SETOR)
    $chkGravadoB = U32 $back (11 * $SETOR)
    $chkCalcB    = BootChecksum $back (11 * $SETOR)

    Diz ""
    Diz "--- ESTADO ATUAL ---"
    Diz ("PRINCIPAL: gravado 0x{0:X8}  calculado 0x{1:X8}  {2}" -f $chkGravadoP, $chkCalcP, $(if ($chkGravadoP -eq $chkCalcP) { 'bate' } else { 'NAO BATE' }))
    Diz ("BACKUP   : gravado 0x{0:X8}  calculado 0x{1:X8}  {2}" -f $chkGravadoB, $chkCalcB, $(if ($chkGravadoB -eq $chkCalcB) { 'bate' } else { 'NAO BATE' }))

    if ($chkGravadoP -eq $chkCalcP) {
        Diz ""
        Diz "A regiao principal JA esta consistente. Nada a consertar aqui." 'Green'
        Diz "Se o Windows ainda rejeita o volume, a causa e outra." 'Yellow'
        exit 0
    }
    if ($chkGravadoB -ne $chkCalcB) {
        Diz ""
        Diz "A regiao de BACKUP tambem esta inconsistente: nao serve de doadora." 'Red'
        Diz "Este script nao cobre esse caso. Abortado sem escrever nada." 'Red'
        exit 2
    }

    # ---------- quais setores diferem ----------
    Diz ""
    Diz "--- DIFERENCAS ENTRE AS REGIOES ---"
    $setoresDif = @{}
    for ($i = 0; $i -lt (12 * $SETOR); $i++) {
        if ($prin[$i] -ne $back[$i]) {
            $s = [int][math]::Floor($i / $SETOR)
            if (-not $setoresDif.ContainsKey($s)) { $setoresDif[$s] = 0 }
            $setoresDif[$s]++
        }
    }
    foreach ($s in ($setoresDif.Keys | Sort-Object)) {
        $nota = ''
        if ($s -eq 0 -and $setoresDif[$s] -eq 1 -and $prin[112] -ne $back[112]) { $nota = '  (so o PercentInUse, que fica fora do checksum)' }
        Diz ("  setor {0}: {1} bytes diferentes{2}" -f $s, $setoresDif[$s], $nota)
    }

    # ---------- a PROVA: monta a correcao em memoria e recalcula ----------
    Diz ""
    Diz "--- PROVA EM MEMORIA (nada escrito ainda) ---"
    # candidato 1: trocar so o setor 1
    $tent1 = New-Object byte[] (12 * $SETOR)
    [Array]::Copy($prin, 0, $tent1, 0, 12 * $SETOR)
    [Array]::Copy($back, $SETOR, $tent1, $SETOR, $SETOR)
    $chk1 = BootChecksum $tent1 (11 * $SETOR)
    Diz ("trocando SO o setor 1  -> checksum ficaria 0x{0:X8}  {1}" -f $chk1, $(if ($chk1 -eq $chkGravadoP) { 'BATE com o gravado' } else { 'ainda nao bate' }))

    # candidato 2: copiar a regiao de backup inteira (setores 0-10, preservando o setor 11 gravado)
    $tent2 = New-Object byte[] (12 * $SETOR)
    [Array]::Copy($back, 0, $tent2, 0, 12 * $SETOR)
    $chk2 = BootChecksum $tent2 (11 * $SETOR)
    Diz ("copiando a regiao toda -> checksum ficaria 0x{0:X8}  {1}" -f $chk2, $(if ($chk2 -eq (U32 $tent2 (11 * $SETOR))) { 'BATE' } else { 'nao bate' }))

    $plano = $null
    if ($chk1 -eq $chkGravadoP) {
        $plano = @{ nome = 'trocar apenas o setor 1'; dados = $back; offsetOrigem = $SETOR; offsetDestino = ($baseParticao + $SETOR); bytes = $SETOR }
    } elseif ($chk2 -eq (U32 $tent2 (11 * $SETOR))) {
        $plano = @{ nome = 'copiar os 12 setores do backup'; dados = $back; offsetOrigem = 0; offsetDestino = $baseParticao; bytes = (12 * $SETOR) }
    }

    if (-not $plano) {
        Diz ""
        Diz "Nenhuma das duas correcoes faz o checksum bater. Abortado sem escrever." 'Red'
        exit 2
    }

    Diz ""
    Diz ("PLANO: {0}  ({1} bytes)" -f $plano.nome, $plano.bytes) 'Cyan'
    Diz ("  destino: byte {0} do disco (LBA {1})" -f $plano.offsetDestino, ($plano.offsetDestino / 512)) 'Cyan'
    Diz "  o resto do cartao nao e tocado." 'Cyan'

    # ---------- ponto de parada ----------
    if (-not $Escrever) {
        Diz ""
        Diz "=== SIMULACAO CONCLUIDA - NADA FOI ESCRITO ===" 'Green'
        Diz "O conserto esta provado em memoria. Para aplicar de verdade:" 'Yellow'
        Diz ("    .\06-consertar-boot.ps1 -DiskNumber {0} -Escrever -TenhoSegundaCopia" -f $DiskNumber) 'Yellow'
        exit 0
    }
    if (-not $TenhoSegundaCopia) {
        Diz ""
        Diz "RECUSADO: -Escrever exige tambem -TenhoSegundaCopia." 'Red'
        Diz "Nao se escreve no cartao enquanto o material estiver em um unico lugar." 'Red'
        exit 1
    }

    # ---------- backup dos 24 setores ----------
    Diz ""
    $orig24 = LerSetores $baseParticao 24
    $d = Split-Path $BackupSetores -Parent
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    [System.IO.File]::WriteAllBytes($BackupSetores, $orig24)
    Diz ("Backup dos 24 setores originais salvo: {0} ({1} bytes)" -f $BackupSetores, $orig24.Length) 'Green'
    Diz ("Para desfazer: .\06-consertar-boot.ps1 -DiskNumber {0} -Desfazer" -f $DiskNumber)

    # ---------- escreve ----------
    Diz ""
    Diz ("ESCREVENDO {0} bytes em {1}..." -f $plano.bytes, $plano.offsetDestino) 'Yellow'
    $fs.Position = $plano.offsetDestino
    $fs.Write($plano.dados, $plano.offsetOrigem, $plano.bytes)
    $fs.Flush()

    # ---------- confere relendo do cartao ----------
    $depois = LerSetores $baseParticao 12
    $chkGravadoD = U32 $depois (11 * $SETOR)
    $chkCalcD    = BootChecksum $depois (11 * $SETOR)
    Diz ""
    Diz "--- CONFERENCIA (relido do cartao) ---"
    Diz ("gravado 0x{0:X8}   calculado 0x{1:X8}" -f $chkGravadoD, $chkCalcD)
    if ($chkGravadoD -eq $chkCalcD) {
        Diz ""
        Diz ">>> CONSERTADO. O checksum agora bate." 'Green'
        Diz "Remova e reconecte o cartao: o Windows deve montar o volume normalmente." 'Green'
        Diz "Confira se os arquivos aparecem em DCIM\Camera01 antes de considerar fechado." 'Cyan'
    } else {
        Diz ""
        Diz ">>> A escrita nao surtiu efeito (o checksum ainda nao bate)." 'Red'
        Diz "Possivel causa: o Windows descartou a escrita por o volume estar montado." 'Yellow'
        Diz ("Tente: Set-Disk -Number {0} -IsOffline `$true, repita, e depois volte com `$false." -f $DiskNumber) 'Yellow'
    }
}
catch {
    Diz ""
    Diz "!!! ERRO !!!" 'Red'
    Diz ("Mensagem: " + $_.Exception.Message) 'Red'
    Diz ("Local   : " + ($_.InvocationInfo.PositionMessage -replace "`r?`n", ' | ')) 'Red'
    if ($Escrever) { Diz "Se a escrita comecou, use -Desfazer para restaurar os 24 setores." 'Yellow' }
}
finally {
    if ($fs) { $fs.Dispose() }
    $dd = Split-Path $Log -Parent
    if (-not (Test-Path $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
    $script:linhas | Out-File -FilePath $Log -Encoding utf8
    Write-Host "`nLog em: $Log" -ForegroundColor Cyan
}
