#!/usr/bin/env bash
# 02-diagnostico-exfat.sh - descobre se o indice do exFAT ainda esta inteiro.
#
# SOMENTE LEITURA. Nao escreve no cartao, nao conserta, nao ocupa espaco.
#
# Responde as duas perguntas que decidem o caminho da recuperacao:
#   1) a estrutura do exFAT esta recuperavel?
#   2) quantos GB de material existem de verdade?
#
# Uso (macOS):
#     diskutil list                          # achar o disco (NAO ejetar)
#     diskutil unmountDisk /dev/disk4        # desmontar, sem ejetar
#     sudo ./02-diagnostico-exfat.sh /dev/rdisk4
#
# Uso (Linux):
#     sudo ./02-diagnostico-exfat.sh /dev/sdb
#
# Tambem aceita um arquivo de imagem:
#     ./02-diagnostico-exfat.sh cartao.img
#
# No macOS usar /dev/rdiskN (cru) e nao /dev/diskN (bufferizado): e muito mais rapido.

set -uo pipefail

DISPOSITIVO="${1:-}"
if [ -z "$DISPOSITIVO" ]; then
  echo "uso: $0 <dispositivo-ou-imagem>" >&2
  echo "  macOS:  sudo $0 /dev/rdisk4" >&2
  echo "  Linux:  sudo $0 /dev/sdb" >&2
  echo "  imagem: $0 cartao.img" >&2
  exit 1
fi
if [ ! -r "$DISPOSITIVO" ]; then
  echo "ERRO: nao consigo ler $DISPOSITIVO" >&2
  echo "Acesso a disco bruto exige sudo." >&2
  exit 1
fi

SETOR=512

# ---------- leitura de inteiros little-endian ----------
# le $2 bytes a partir do offset $1 e imprime em hexadecimal, sem espacos
ler_hex() {
  local offset=$1 tamanho=$2
  local ini_bloco=$(( offset / SETOR * SETOR ))
  local desloc=$(( offset - ini_bloco ))
  local fim=$(( offset + tamanho ))
  local blocos=$(( (fim - ini_bloco + SETOR - 1) / SETOR ))
  dd if="$DISPOSITIVO" bs=$SETOR skip=$(( ini_bloco / SETOR )) count=$blocos 2>/dev/null \
    | od -An -tx1 -v -j "$desloc" -N "$tamanho" | tr -d ' \n'
}

# converte hexadecimal little-endian em decimal
le_para_dec() {
  local hex=$1 out=""
  local i
  for (( i=${#hex}-2; i>=0; i-=2 )); do
    out="${out}${hex:$i:2}"
  done
  echo $(( 16#${out:-0} ))
}

u8()  { le_para_dec "$(ler_hex "$1" 1)"; }
u16() { le_para_dec "$(ler_hex "$1" 2)"; }
u32() { le_para_dec "$(ler_hex "$1" 4)"; }
u64() { le_para_dec "$(ler_hex "$1" 8)"; }

# le $2 bytes do offset $1 como texto ASCII
ler_ascii() {
  local offset=$1 tamanho=$2
  local ini_bloco=$(( offset / SETOR * SETOR ))
  local desloc=$(( offset - ini_bloco ))
  dd if="$DISPOSITIVO" bs=$SETOR skip=$(( ini_bloco / SETOR )) count=1 2>/dev/null \
    | dd bs=1 skip="$desloc" count="$tamanho" 2>/dev/null
}

gib() { awk -v b="$1" 'BEGIN{ printf "%.2f", b/1073741824 }'; }

echo "================================================================"
echo " DIAGNOSTICO exFAT - somente leitura"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================"
echo "Dispositivo: $DISPOSITIVO"
echo

# ---------- 1. tabela de particao ----------
echo "--- [1/5] Tabela de particao (MBR) ---"
assin="$(ler_hex 510 2)"
if [ "$assin" = "55aa" ]; then
  echo "Assinatura 0x55AA: OK"
else
  echo "Assinatura 0x55AA: AUSENTE (0x$assin)"
fi

base_particao=0
for i in 0 1 2 3; do
  o=$(( 446 + i * 16 ))
  tipo=$(u8 $(( o + 4 )))
  [ "$tipo" -eq 0 ] && continue
  lba=$(u32 $(( o + 8 )))
  setores=$(u32 $(( o + 12 )))
  printf "Particao %d: tipo 0x%02X  LBA inicial %d  %d setores (%s GiB)\n" \
    $(( i + 1 )) "$tipo" "$lba" "$setores" "$(gib $(( setores * 512 )))"
  if [ "$base_particao" -eq 0 ]; then base_particao=$(( lba * 512 )); fi
done
[ "$base_particao" -eq 0 ] && echo "Nenhuma particao na MBR; tratando o inicio como volume."

# ---------- 2. VBR: principal, backup, varredura ----------
echo
echo "--- [2/5] Setor de boot do exFAT (VBR) ---"
vbr_base=-1
origem_vbr=""
for candidato in "$base_particao" $(( base_particao + 12 * SETOR )); do
  nome="$(ler_ascii $(( candidato + 3 )) 8)"
  if [ "$nome" = "EXFAT   " ]; then
    vbr_base=$candidato
    if [ "$candidato" -eq "$base_particao" ]; then
      origem_vbr="principal (offset $candidato)"
    else
      origem_vbr="BACKUP, setor 12 (offset $candidato)"
    fi
    break
  fi
done

if [ "$vbr_base" -lt 0 ]; then
  echo "VBR principal e backup ilegiveis. Varrendo os primeiros 2 GiB..."
  encontrado=-1
  off=0
  limite=$(( 2 * 1024 * 1024 * 1024 ))
  while [ "$off" -lt "$limite" ]; do
    nome="$(ler_ascii $(( off + 3 )) 8)"
    if [ "$nome" = "EXFAT   " ]; then encontrado=$off; break; fi
    off=$(( off + SETOR * 2048 ))   # salta 1 MiB
  done
  if [ "$encontrado" -ge 0 ]; then
    vbr_base=$encontrado
    origem_vbr="encontrado por varredura (offset $encontrado)"
  else
    echo
    echo "RESULTADO: nenhum setor de boot exFAT encontrado."
    echo "O dano NAO e raso. O caminho passa a ser carving com PhotoRec +"
    echo "remontagem de fragmentos, que exige imagem completa do cartao."
    exit 2
  fi
fi
echo "VBR encontrado: $origem_vbr"
case "$origem_vbr" in
  BACKUP*) echo "O principal esta destruido mas o BACKUP esta intacto - este e o cenario bom." ;;
esac

# ---------- 3. parametros do sistema de arquivos ----------
bps_shift=$(u8 $(( vbr_base + 108 )))
spc_shift=$(u8 $(( vbr_base + 109 )))
if [ "$bps_shift" -lt 9 ] || [ "$bps_shift" -gt 12 ]; then
  echo "VBR com BytesPerSectorShift invalido ($bps_shift). Estrutura suspeita." >&2
  exit 2
fi
bps=$(( 1 << bps_shift ))
spc=$(( 1 << spc_shift ))
fat_offset=$(u32 $(( vbr_base + 80 )))
fat_length=$(u32 $(( vbr_base + 84 )))
heap_offset=$(u32 $(( vbr_base + 88 )))
cluster_count=$(u32 $(( vbr_base + 92 )))
root_cluster=$(u32 $(( vbr_base + 96 )))
vol_flags=$(u16 $(( vbr_base + 106 )))
percent=$(u8 $(( vbr_base + 112 )))
bpc=$(( bps * spc ))

echo
echo "--- [3/5] Parametros do sistema de arquivos ---"
echo "Bytes por setor    : $bps"
echo "Setores por cluster: $spc  (cluster = $(( bpc / 1024 )) KiB)"
echo "Total de clusters  : $cluster_count"
echo "FAT em setor       : $fat_offset  ($fat_length setores)"
echo "Heap em setor      : $heap_offset"
echo "Root no cluster    : $root_cluster"
printf "VolumeFlags        : 0x%04X%s\n" "$vol_flags" \
  "$( [ $(( vol_flags & 2 )) -ne 0 ] && echo '  <- ATENCAO: VolumeDirty' )"
if [ "$percent" -le 100 ]; then
  total_vol=$(( cluster_count * bpc ))
  echo "PercentInUse       : ${percent}%  =>  ~$(gib $(( total_vol / 100 * percent ))) GiB em uso"
else
  echo "PercentInUse       : nao disponivel (0xFF)"
fi

fat_base=$(( vbr_base + fat_offset * bps ))
cluster_para_offset() { echo $(( vbr_base + heap_offset * bps + ( $1 - 2 ) * bpc )); }

# proxima entrada da cadeia, lendo a FAT
proximo_cluster() {
  local c=$1
  local v
  v=$(u32 $(( fat_base + c * 4 )))
  echo "$v"
}

# ---------- 4. percorrer o diretorio raiz ----------
echo
echo "--- [4/5] Conteudo (travessia do diretorio raiz) ---"

arquivos=0
pastas=0
soma_bytes=0
bitmap_cluster=0
bitmap_tam=0
LISTA="$(mktemp)"
trap 'rm -f "$LISTA"' EXIT

percorrer() {
  local cluster=$1 caminho=$2 nivel=$3
  [ "$nivel" -gt 6 ] && return

  local guarda=0
  while [ "$cluster" -ge 2 ] && [ "$cluster" -lt $(( cluster_count + 2 )) ] && [ "$guarda" -lt 2048 ]; do
    local base
    base=$(cluster_para_offset "$cluster")

    local i=0
    while [ "$i" -lt "$bpc" ]; do
      local off=$(( base + i ))
      local tipo
      tipo=$(u8 "$off")

      if [ "$tipo" -eq 0 ]; then return; fi

      if [ "$tipo" -eq 129 ]; then            # 0x81 Allocation Bitmap
        bitmap_cluster=$(u32 $(( off + 20 )))
        bitmap_tam=$(u64 $(( off + 24 )))
      elif [ "$tipo" -eq 133 ]; then          # 0x85 File Directory Entry
        local sec attrs eh_pasta nome prim tam flags j s
        sec=$(u8 $(( off + 1 )))
        attrs=$(u16 $(( off + 4 )))
        eh_pasta=$(( attrs & 16 ))
        nome=""; prim=0; tam=0; flags=0
        s=1
        while [ "$s" -le "$sec" ]; do
          j=$(( off + s * 32 ))
          local t2
          t2=$(u8 "$j")
          if [ "$t2" -eq 192 ]; then          # 0xC0 Stream Extension
            flags=$(u8 $(( j + 1 )))
            prim=$(u32 $(( j + 20 )))
            tam=$(u64 $(( j + 24 )))
          elif [ "$t2" -eq 193 ]; then        # 0xC1 File Name (UTF-16LE)
            local pedaco
            pedaco=$(ler_hex $(( j + 2 )) 30)
            local k car
            for (( k=0; k<60; k+=4 )); do
              car="${pedaco:$k:2}"
              [ "$car" = "00" ] && continue
              nome="${nome}$(printf "\\x${car}")"
            done
          fi
          s=$(( s + 1 ))
        done

        if [ "$eh_pasta" -ne 0 ]; then
          pastas=$(( pastas + 1 ))
          if [ "$prim" -ge 2 ]; then
            percorrer "$prim" "${caminho}/${nome}" $(( nivel + 1 ))
          fi
        else
          arquivos=$(( arquivos + 1 ))
          soma_bytes=$(( soma_bytes + tam ))
          printf "%s\t%s\n" "$tam" "${caminho}/${nome}" >> "$LISTA"
        fi
        i=$(( i + 32 * ( sec + 1 ) ))
        continue
      fi
      i=$(( i + 32 ))
    done

    # proximo cluster do diretorio, pela FAT
    local prox
    prox=$(proximo_cluster "$cluster")
    # 0xFFFFFFF7 = 4294967287
    if [ "$prox" -ge 4294967287 ] || [ "$prox" -lt 2 ]; then break; fi
    cluster=$prox
    guarda=$(( guarda + 1 ))
  done
}

percorrer "$root_cluster" "" 0

echo "Pastas encontradas  : $pastas"
echo "Arquivos encontrados: $arquivos"

# ---------- 5. espaco em uso pelo bitmap ----------
echo
echo "--- [5/5] Espaco realmente em uso ---"
if [ "$bitmap_cluster" -ge 2 ] && [ "$bitmap_tam" -gt 0 ]; then
  bmp_off=$(cluster_para_offset "$bitmap_cluster")
  # Ler em blocos de setor, nunca com bs=1: "dd bs=1 skip=<centenas de MB>" copia
  # byte a byte e leva horas. Le os setores que cobrem o bitmap e corta o excesso.
  bmp_ini_bloco=$(( bmp_off / SETOR ))
  bmp_desloc=$(( bmp_off - bmp_ini_bloco * SETOR ))
  bmp_blocos=$(( (bmp_desloc + bitmap_tam + SETOR - 1) / SETOR ))
  usados=$(dd if="$DISPOSITIVO" bs=$SETOR skip="$bmp_ini_bloco" count="$bmp_blocos" 2>/dev/null \
    | od -An -tu1 -v -j "$bmp_desloc" -N "$bitmap_tam" \
    | awk '{ for (i=1; i<=NF; i++) { n=$i; while (n>0) { c+=n%2; n=int(n/2) } } } END { print c+0 }')
  echo "Clusters em uso: $usados de $cluster_count"
  echo "MATERIAL NO CARTAO: $(gib $(( usados * bpc ))) GiB"
else
  echo "Bitmap de alocacao nao localizado no raiz."
  usados=0
fi
echo "Soma dos arquivos listados: $(gib $soma_bytes) GiB"

# ---------- veredito ----------
echo
echo "=================== VEREDITO ==================="
if [ "$arquivos" -gt 0 ] && [ "$usados" -gt 0 ]; then
  pelo_bitmap=$(( usados * bpc ))
  # tolerancia de 5% entre os dois caminhos de medicao
  limite=$(( pelo_bitmap / 20 ))
  dif=$(( soma_bytes > pelo_bitmap ? soma_bytes - pelo_bitmap : pelo_bitmap - soma_bytes ))
  if [ "$dif" -le "$limite" ]; then
    echo "INDICE INTEGRO: a soma do diretorio bate com o bitmap."
    echo "Caminho: extracao pelo indice (03-extrair). Sem imagem, sem carving."
    echo "Espaco necessario no destino: $(gib $soma_bytes) GiB"
  else
    echo "Os dois caminhos de medicao divergem:"
    echo "  diretorio: $(gib $soma_bytes) GiB   bitmap: $(gib $pelo_bitmap) GiB"
    echo "Indice parcialmente danificado. Considerar imagem + carving."
  fi
else
  echo "Indice nao rendeu arquivos utilizaveis: caminho de carving."
fi
echo "================================================"
echo
echo "Os 20 maiores arquivos:"
sort -rn "$LISTA" 2>/dev/null | head -20 | awk -F'\t' '{ printf "  %9.1f MB  %s\n", $1/1048576, $2 }'
