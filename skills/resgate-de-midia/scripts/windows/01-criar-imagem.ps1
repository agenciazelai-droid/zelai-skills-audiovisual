<#
    01-criar-imagem.ps1 — imagem bit-a-bit SOMENTE LEITURA de um cartao de memoria.

    Abre \\.\PhysicalDriveN em leitura, copia bloco por bloco para um .img,
    registra setores ilegiveis num log e permite retomar de onde parou.
    NUNCA escreve no cartao. Nao formata, nao repara, nao monta.

    Uso (PowerShell COMO ADMINISTRADOR):
        .\01-criar-imagem.ps1                      # apenas lista os discos
        .\01-criar-imagem.ps1 -DiskNumber 2        # cria a imagem do disco 2
        .\01-criar-imagem.ps1 -DiskNumber 2 -Retomar
#>

[CmdletBinding()]
param(
    [int]    $DiskNumber = -1,
    [string] $Destino    = '.\imagem\cartao.img',
    [string] $LogRuins   = '.\log\setores-ruins.txt',
    [int]    $BlocoMB    = 4,
    [switch] $Retomar
)

$ErrorActionPreference = 'Stop'

function Escrever($txt, $cor = 'Gray') { Write-Host $txt -ForegroundColor $cor }

# ---------- 1. elevacao ----------
$admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Escrever "ERRO: leitura de disco bruto exige elevacao." 'Red'
    Escrever "Abra o PowerShell como Administrador e rode de novo." 'Yellow'
    exit 1
}

# ---------- 2. inventario dos discos ----------
Escrever "`n=== Discos presentes ===" 'Cyan'
Get-Disk | Select-Object Number, FriendlyName, BusType,
    @{n='SizeGB';e={[math]::Round($_.Size/1GB,2)}}, PartitionStyle, HealthStatus |
    Format-Table -AutoSize | Out-String | Write-Host

if ($DiskNumber -lt 0) {
    Escrever "Nenhum disco escolhido. Rode de novo com -DiskNumber <N>." 'Yellow'
    Escrever "O cartao e o disco que NAO e o do sistema nem o SSD de trabalho.`n" 'Yellow'
    exit 0
}

$disco = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
if (-not $disco) { Escrever "ERRO: disco $DiskNumber nao existe." 'Red'; exit 1 }

# ---------- 3. guardas ----------
# 3a. nunca o disco do sistema
$discoSistema = (Get-Partition -DriveLetter ($env:SystemDrive.TrimEnd(':'))).DiskNumber
if ($DiskNumber -eq $discoSistema) {
    Escrever "ERRO: disco $DiskNumber e o disco do sistema. Abortado." 'Red'; exit 1
}
# 3b. nunca o disco que hospeda o destino (leria a si mesmo enquanto cresce)
$letraDestino = (Split-Path $Destino -Qualifier).TrimEnd(':')
$discoDestino = (Get-Partition -DriveLetter $letraDestino -ErrorAction SilentlyContinue).DiskNumber
if ($null -ne $discoDestino -and $DiskNumber -eq $discoDestino) {
    Escrever "ERRO: disco $DiskNumber e o mesmo que hospeda o destino ($letraDestino`:). Abortado." 'Red'; exit 1
}

$tamanho = [int64] $disco.Size
Escrever "Origem : PhysicalDrive$DiskNumber  ($($disco.FriendlyName), $([math]::Round($tamanho/1GB,2)) GB)" 'White'
Escrever "Destino: $Destino" 'White'

# 3c. espaco livre
$livre = (Get-Volume -DriveLetter $letraDestino).SizeRemaining
$jaFeito = 0L
if (Test-Path $Destino) {
    $jaFeito = (Get-Item $Destino).Length
    if (-not $Retomar) {
        Escrever "`nATENCAO: $Destino ja existe ($([math]::Round($jaFeito/1GB,2)) GB)." 'Yellow'
        Escrever "Use -Retomar para continuar, ou apague o arquivo para comecar do zero." 'Yellow'
        exit 1
    }
}
$falta = $tamanho - $jaFeito
if ($livre -lt $falta) {
    Escrever ("`nERRO: espaco insuficiente. Falta copiar {0} GB, livre em {1}: {2} GB." -f
        [math]::Round($falta/1GB,2), $letraDestino, [math]::Round($livre/1GB,2)) 'Red'
    Escrever "Libere espaco ou aponte -Destino para um disco externo." 'Yellow'
    exit 1
}

# ---------- 4. confirmacao explicita ----------
Escrever "`nIsto e uma operacao de LEITURA. Nada sera escrito no cartao." 'Green'
$resp = Read-Host "Confirmar leitura de PhysicalDrive$DiskNumber ? (digite SIM)"
if ($resp -ne 'SIM') { Escrever "Cancelado pelo operador." 'Yellow'; exit 0 }

# ---------- 5. copia ----------
$bloco  = $BlocoMB * 1MB
$offset = [int64]([math]::Floor($jaFeito / $bloco) * $bloco)   # alinha a retomada ao bloco
$buffer = New-Object byte[] $bloco
$zeros  = New-Object byte[] $bloco
$ruins  = 0
$lidos  = 0L
$inicio = Get-Date

$origem = $null; $saida = $null
try {
    $origem = New-Object System.IO.FileStream("\\.\PhysicalDrive$DiskNumber",
        [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $saida = New-Object System.IO.FileStream($Destino,
        [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    $saida.SetLength($offset)
    $saida.Position = $offset

    Escrever "`nIniciando em offset $([math]::Round($offset/1GB,3)) GB. Ctrl+C interrompe (da para retomar).`n" 'Cyan'

    while ($offset -lt $tamanho) {
        $aLer = [int][math]::Min([int64]$bloco, $tamanho - $offset)
        $ok = $false
        try {
            $origem.Position = $offset
            $n = $origem.Read($buffer, 0, $aLer)
            if ($n -gt 0) { $saida.Write($buffer, 0, $n); $ok = $true; $lidos += $n }
        } catch { $ok = $false }

        if (-not $ok) {
            # releitura fina: 64 KB por vez, o que falhar vira zeros e vai para o log
            $fino = 64KB
            for ($p = 0; $p -lt $aLer; $p += $fino) {
                $sub = [int][math]::Min([int64]$fino, [int64]($aLer - $p))
                try {
                    $origem.Position = $offset + $p
                    $n = $origem.Read($buffer, 0, $sub)
                    $saida.Write($buffer, 0, $n)
                    $lidos += $n
                } catch {
                    $saida.Write($zeros, 0, $sub)
                    $ruins++
                    Add-Content -Path $LogRuins -Value ("offset={0} bytes={1} setor_lba={2}" -f
                        ($offset + $p), $sub, [math]::Floor(($offset + $p) / 512)) -Encoding utf8
                }
            }
        }

        $offset += $aLer
        if (($offset / $bloco) % 64 -eq 0) {
            $pct = [math]::Round(100 * $offset / $tamanho, 2)
            $seg = ((Get-Date) - $inicio).TotalSeconds
            $mbs = if ($seg -gt 0) { [math]::Round(($lidos/1MB) / $seg, 1) } else { 0 }
            Write-Progress -Activity "Imagem de PhysicalDrive$DiskNumber" `
                -Status ("$pct%  |  $([math]::Round($offset/1GB,2)) / $([math]::Round($tamanho/1GB,2)) GB  |  $mbs MB/s  |  blocos ruins: $ruins") `
                -PercentComplete $pct
        }
    }
    $saida.Flush()
}
finally {
    if ($saida)  { $saida.Dispose() }
    if ($origem) { $origem.Dispose() }
    Write-Progress -Activity "Imagem" -Completed
}

# ---------- 6. relatorio ----------
$dur = (Get-Date) - $inicio
Escrever "`n=== Concluido ===" 'Green'
Escrever ("Imagem   : {0} ({1} GB)" -f $Destino, [math]::Round((Get-Item $Destino).Length/1GB,2))
Escrever ("Duracao  : {0:hh\:mm\:ss}" -f $dur)
if ($ruins -gt 0) {
    Escrever ("Blocos ilegiveis: {0} (zerados) -> {1}" -f $ruins, $LogRuins) 'Yellow'
    Escrever "Setor ruim indica desgaste fisico: considere ddrescue/HDDSuperClone para uma segunda passada." 'Yellow'
} else {
    Escrever "Nenhum erro de leitura. Dano e logico, nao fisico." 'Green'
}
Escrever "`nO cartao pode sair do leitor e ir para a gaveta. O trabalho continua na imagem.`n" 'Cyan'
