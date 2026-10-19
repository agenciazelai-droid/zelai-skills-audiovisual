<#
    04-validar.ps1 — valida os arquivos extraidos.

    Para cada arquivo em recuperado\:
      1. confere o tamanho contra o inventario do cartao
      2. ffprobe: container, duracao, streams, codec, resolucao
      3. decodifica frames no INICIO, MEIO e FIM (container que abre nao e video valido)
      4. procura o trailer de metadados da Insta360 no fim do arquivo
         (giroscopio e dados de costura — o que o carving por assinatura perderia)

    Nao toca no cartao. Trabalha apenas nos arquivos ja extraidos.
#>

[CmdletBinding()]
param(
    [string] $Pasta      = '.\recuperado',
    [string] $Inventario = '.\log\inventario.csv',
    [string] $Log        = '.\log\validacao.txt',
    [string] $BinFfmpeg  = '.\ferramentas\ffmpeg-essentials\ffmpeg-9.0.2-essentials_build\bin'
)

$ErrorActionPreference = 'Continue'
$linhas = New-Object System.Collections.Generic.List[string]
function Diz($txt, $cor = 'Gray') { Write-Host $txt -ForegroundColor $cor; $linhas.Add($txt) }

$ffprobe = Join-Path $BinFfmpeg 'ffprobe.exe'
$ffmpeg  = Join-Path $BinFfmpeg 'ffmpeg.exe'
foreach ($b in @($ffprobe, $ffmpeg)) {
    if (-not (Test-Path $b)) { Write-Host "ERRO: nao achei $b" -ForegroundColor Red; exit 1 }
}

# magic da Insta360 que fecha o arquivo .insv (trailer de metadados)
$MAGIC = '8db42d694ccc418790edff439fe026bf'

$inv = @{}
if (Test-Path $Inventario) {
    Import-Csv $Inventario | ForEach-Object { $inv[$_.Caminho] = [int64]$_.Bytes }
}

$arqs = Get-ChildItem $Pasta -Recurse -File -Include *.insv,*.mp4 -ErrorAction SilentlyContinue | Sort-Object FullName
if (-not $arqs) { Diz "Nenhum arquivo em $Pasta" 'Yellow'; exit 0 }

Diz "================================================================"
Diz " VALIDACAO — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Diz "================================================================"
Diz ("Arquivos a validar: {0}" -f $arqs.Count)
Diz ""

$bons = 0; $ruins = 0; $semMagic = 0
foreach ($a in $arqs) {
    $rel = $a.FullName.Substring($Pasta.Length).TrimStart('\')
    Diz ("--- {0} ---" -f $rel)
    $problema = $false

    # 1. tamanho contra o inventario
    if ($inv.ContainsKey($rel)) {
        if ($inv[$rel] -eq $a.Length) {
            Diz ("  tamanho : {0} bytes  (igual ao cartao)" -f $a.Length)
        } else {
            Diz ("  tamanho : {0} bytes  DIFERENTE do cartao ({1})" -f $a.Length, $inv[$rel]) 'Red'
            $problema = $true
        }
    } else {
        Diz ("  tamanho : {0} bytes  (sem referencia no inventario)" -f $a.Length) 'Yellow'
    }

    # 2. ffprobe
    $json = & $ffprobe -v error -print_format json -show_format -show_streams $a.FullName 2>$null
    $dur = 0.0
    if ($LASTEXITCODE -ne 0 -or -not $json) {
        Diz "  ffprobe : FALHOU em ler o container" 'Red'
        $problema = $true
    } else {
        try {
            $meta = ($json -join '') | ConvertFrom-Json
            $dur = [double]$meta.format.duration
            Diz ("  container: {0}   duracao: {1:n1}s   {2:n1} MB" -f `
                $meta.format.format_name, $dur, ($a.Length/1MB))
            foreach ($s in $meta.streams) {
                if ($s.codec_type -eq 'video') {
                    Diz ("  video   : {0}  {1}x{2}  {3} fps  {4} frames" -f `
                        $s.codec_name, $s.width, $s.height, $s.r_frame_rate, $s.nb_frames)
                } elseif ($s.codec_type -eq 'audio') {
                    Diz ("  audio   : {0}  {1} Hz  {2} canais" -f $s.codec_name, $s.sample_rate, $s.channels)
                } else {
                    Diz ("  {0}: {1}" -f $s.codec_type, $s.codec_name)
                }
            }
        } catch {
            Diz ("  ffprobe : saida ilegivel ({0})" -f $_.Exception.Message) 'Red'
            $problema = $true
        }
    }

    # 3. decodificar no inicio, meio e fim
    if ($dur -gt 1) {
        $pontos = @(
            @{ nome = 'inicio'; t = 0.0 },
            @{ nome = 'meio';   t = [math]::Round($dur / 2, 1) },
            @{ nome = 'fim';    t = [math]::Max(0, [math]::Round($dur - 1.5, 1)) }
        )
        $okDec = @()
        foreach ($pt in $pontos) {
            $err = & $ffmpeg -v error -ss $pt.t -i $a.FullName -frames:v 1 -f null - 2>&1
            if ($LASTEXITCODE -eq 0 -and -not $err) { $okDec += $pt.nome }
            else {
                $okDec += ("{0}:FALHOU" -f $pt.nome)
                $problema = $true
            }
        }
        Diz ("  decodifica: {0}" -f ($okDec -join '  '))
    } else {
        Diz "  decodifica: duracao desconhecida, pulado" 'Yellow'
    }

    # 4. trailer de metadados da Insta360
    # [math]::Min(128KB, $int64) casa a sobrecarga Int32 e estoura em arquivo > 2 GiB:
    # comparar explicitamente em int64 e so depois converter o tamanho do buffer.
    [int64]$len = $a.Length
    [int]$tam = if ($len -lt 131072) { [int]$len } else { 131072 }
    $fsa = New-Object System.IO.FileStream($a.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
    $lido = 0
    try {
        $buf = New-Object byte[] $tam
        $fsa.Position = $len - $tam
        while ($lido -lt $tam) { $n = $fsa.Read($buf, $lido, $tam - $lido); if ($n -le 0) { break }; $lido += $n }
    } finally { $fsa.Dispose() }
    $txtCauda = [Text.Encoding]::ASCII.GetString($buf, 0, $lido)
    # No X2, o trailer de metadados vive no arquivo principal (_00_ ou o .mp4 de lente
    # unica). O _10_ carrega apenas o fluxo da segunda lente e nao tem trailer: a
    # ausencia ali e o comportamento normal da camera, nao perda na extracao.
    $esperaMagic = ($a.Name -notlike '*_10_*')
    if ($txtCauda.Contains($MAGIC)) {
        $pos = $txtCauda.LastIndexOf($MAGIC)
        Diz ("  metadados Insta360: PRESENTE (magic a {0} bytes do fim)" -f ($tam - $pos)) 'Green'
    } elseif ($esperaMagic) {
        Diz "  metadados Insta360: AUSENTE e era esperado neste arquivo" 'Red'
        $semMagic++
        $problema = $true
    } else {
        Diz "  metadados Insta360: ausente (normal na segunda lente _10_)"
    }

    if ($problema) { $ruins++; Diz "  >>> COM PROBLEMA" 'Red' } else { $bons++; Diz "  >>> OK" 'Green' }
    Diz ""
}

Diz "================= RESULTADO ================="
Diz ("Validos        : {0}" -f $bons)
Diz ("Com problema   : {0}" -f $ruins)
Diz ("Sem o trailer onde era esperado: {0}  (sem metadados, o Studio nao costura o 360)" -f $semMagic)
Diz "============================================="

$d = Split-Path $Log -Parent
if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
$linhas | Out-File -FilePath $Log -Encoding utf8
Write-Host "`nLog em: $Log" -ForegroundColor Cyan
