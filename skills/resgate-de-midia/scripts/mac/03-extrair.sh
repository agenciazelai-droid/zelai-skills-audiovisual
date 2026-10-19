#!/usr/bin/env bash
# 03-extrair.sh - extrai arquivos de um exFAT seguindo o indice, SOMENTE LEITURA na origem.
#
# Nao usa imagem, nao usa carving, nao repara nada. Le a FAT e as entradas de
# diretorio, segue a cadeia de clusters de cada arquivo e grava o arquivo inteiro
# no destino, byte a byte, com nome e caminho originais.
#
# Isso preserva o trailer de metadados do .insv (girosocopio e dados de costura),
# que o carving por assinatura perderia.
#
# Uso (macOS):
#     diskutil unmountDisk /dev/disk4
#     sudo ./03-extrair.sh /dev/rdisk4 ./recuperado
#     sudo ./03-extrair.sh /dev/rdisk4 ./recuperado --simular
#     sudo ./03-extrair.sh /dev/rdisk4 ./recuperado --so-master
#
# Opcoes:
#   --simular    lista o plano e valida as cadeias, sem escrever nada
#   --so-master  pula os proxies LRV e as miniaturas (economiza espaco)

set -uo pipefail

DISPOSITIVO="${1:-}"
DESTINO="${2:-./recuperado}"
SIMULAR=0
SO_MASTER=0
shift 2 2>/dev/null || true
for arg in "$@"; do
  case "$arg" in
    --simular)   SIMULAR=1 ;;
    --so-master) SO_MASTER=1 ;;
    *) echo "opcao desconhecida: $arg" >&2; exit 1 ;;
  esac
done

if [ -z "$DISPOSITIVO" ]; then
  echo "uso: $0 <dispositivo-ou-imagem> <pasta-destino> [--simular] [--so-master]" >&2
  exit 1
fi
[ -r "$DISPOSITIVO" ] || { echo "ERRO: nao consigo ler $DISPOSITIVO (use sudo)" >&2; exit 1; }

# guarda: destino nao pode estar dentro da origem
case "$(cd "$(dirname "$DESTINO")" 2>/dev/null && pwd)" in
  "$DISPOSITIVO"*) echo "ERRO: destino dentro da origem. Abortado." >&2; exit 1 ;;
esac

SETOR=512

ler_hex() {
  local offset=$1 tamanho=$2
  local ini_bloco=$(( offset / SETOR * SETOR ))
  local desloc=$(( offset - ini_bloco ))
  local blocos=$(( (desloc + tamanho + SETOR - 1) / SETOR ))
  dd if="$DISPOSITIVO" bs=$SETOR skip=$(( ini_bloco / SETOR )) count=$blocos 2>/dev/null \
    | od -An -tx1 -v -j "$desloc" -N "$tamanho" | tr -d ' \n'
}
le_para_dec() {
  local hex=$1 out="" i
  for (( i=${#hex}-2; i>=0; i-=2 )); do out="${out}${hex:$i:2}"; done
  echo $(( 16#${out:-0} ))
}
u8()  { le_para_dec "$(ler_hex "$1" 1)"; }
u16() { le_para_dec "$(ler_hex "$1" 2)"; }
u32() { le_para_dec "$(ler_hex "$1" 4)"; }
u64() { le_para_dec "$(ler_hex "$1" 8)"; }
ler_ascii() {
  local ini_bloco=$(( $1 / SETOR * SETOR ))
  dd if="$DISPOSITIVO" bs=$SETOR skip=$(( ini_bloco / SETOR )) count=1 2>/dev/null \
    | dd bs=1 skip=$(( $1 - ini_bloco )) count="$2" 2>/dev/null
}
mb() { awk -v b="$1" 'BEGIN{ printf "%.1f", b/1048576 }'; }

# ---------- localizar o volume ----------
base_particao=0
for i in 0 1 2 3; do
  o=$(( 446 + i * 16 ))
  [ "$(u8 $(( o + 4 )))" -eq 0 ] && continue
  base_particao=$(( $(u32 $(( o + 8 ))) * 512 ))
  break
done

vbr_base=-1
for cand in "$base_particao" $(( base_particao + 12 * SETOR )); do
  if [ "$(ler_ascii $(( cand + 3 )) 8)" = "EXFAT   " ]; then vbr_base=$cand; break; fi
done
[ "$vbr_base" -lt 0 ] && { echo "ERRO: VBR exFAT nao encontrado. Rode 02-diagnostico primeiro." >&2; exit 2; }

bps=$(( 1 << $(u8 $(( vbr_base + 108 ))) ))
spc=$(( 1 << $(u8 $(( vbr_base + 109 ))) ))
fat_offset=$(u32 $(( vbr_base + 80 )))
heap_offset=$(u32 $(( vbr_base + 88 )))
cluster_count=$(u32 $(( vbr_base + 92 )))
root_cluster=$(u32 $(( vbr_base + 96 )))
bpc=$(( bps * spc ))
fat_base=$(( vbr_base + fat_offset * bps ))

echo "================================================================"
echo " EXTRACAO - origem em somente leitura"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================"
echo "Origem : $DISPOSITIVO"
echo "Destino: $DESTINO"
echo "Cluster: $(( bpc / 1024 )) KiB   Clusters: $cluster_count   Root: $root_cluster"
[ "$SIMULAR" -eq 1 ]   && echo "MODO   : SIMULACAO (nada sera escrito)"
[ "$SO_MASTER" -eq 1 ] && echo "FILTRO : so masters (pula LRV e miniaturas)"
echo

cl_off() { echo $(( vbr_base + heap_offset * bps + ( $1 - 2 ) * bpc )); }

# ---------- inventario ----------
INV="$(mktemp)"; trap 'rm -f "$INV"' EXIT

percorrer() {
  local cluster=$1 caminho=$2 nivel=$3
  [ "$nivel" -gt 6 ] && return
  local guarda=0
  while [ "$cluster" -ge 2 ] && [ "$cluster" -lt $(( cluster_count + 2 )) ] && [ "$guarda" -lt 2048 ]; do
    local base i
    base=$(cl_off "$cluster")
    i=0
    while [ "$i" -lt "$bpc" ]; do
      local off tipo
      off=$(( base + i ))
      tipo=$(u8 "$off")
      [ "$tipo" -eq 0 ] && return
      if [ "$tipo" -eq 133 ]; then
        local sec attrs eh_pasta nome prim tam flags s j t2
        sec=$(u8 $(( off + 1 )))
        attrs=$(u16 $(( off + 4 )))
        eh_pasta=$(( attrs & 16 ))
        nome=""; prim=0; tam=0; flags=0
        s=1
        while [ "$s" -le "$sec" ]; do
          j=$(( off + s * 32 ))
          t2=$(u8 "$j")
          if [ "$t2" -eq 192 ]; then
            flags=$(u8 $(( j + 1 ))); prim=$(u32 $(( j + 20 ))); tam=$(u64 $(( j + 24 )))
          elif [ "$t2" -eq 193 ]; then
            local pedaco k car
            pedaco=$(ler_hex $(( j + 2 )) 30)
            for (( k=0; k<60; k+=4 )); do
              car="${pedaco:$k:2}"
              [ "$car" = "00" ] && continue
              nome="${nome}$(printf "\\x${car}")"
            done
          fi
          s=$(( s + 1 ))
        done
        if [ "$eh_pasta" -ne 0 ]; then
          [ "$prim" -ge 2 ] && percorrer "$prim" "${caminho}/${nome}" $(( nivel + 1 ))
        else
          local sem_fat=$(( flags & 2 ))
          printf "%s\t%s\t%s\t%s\n" "$tam" "$prim" "$sem_fat" "${caminho#/}/${nome}" >> "$INV"
        fi
        i=$(( i + 32 * ( sec + 1 ) ))
        continue
      fi
      i=$(( i + 32 ))
    done
    local prox
    prox=$(u32 $(( fat_base + cluster * 4 )))
    # 0xFFFFFFF7 = 4294967287
    if [ "$prox" -ge 4294967287 ] || [ "$prox" -lt 2 ]; then break; fi
    cluster=$prox
    guarda=$(( guarda + 1 ))
  done
}
percorrer "$root_cluster" "" 0

total_arq=$(wc -l < "$INV" | tr -d ' ')
echo "Arquivos no indice: $total_arq"

# ---------- selecao ----------
SEL="$(mktemp)"; trap 'rm -f "$INV" "$SEL"' EXIT
while IFS=$'\t' read -r tam prim semfat caminho; do
  nome="${caminho##*/}"
  case "$nome" in
    .*|'') continue ;;
  esac
  case "$caminho" in
    System\ Volume\ Information/*) continue ;;
  esac
  if [ "$SO_MASTER" -eq 1 ]; then
    case "$nome" in
      LRV_*|*.bmp|*.list) continue ;;
    esac
  fi
  printf "%s\t%s\t%s\t%s\n" "$tam" "$prim" "$semfat" "$caminho" >> "$SEL"
done < "$INV"

sel_n=$(wc -l < "$SEL" | tr -d ' ')
sel_bytes=$(awk -F'\t' '{ s += $1 } END { print s+0 }' "$SEL")
echo "Selecionados      : $sel_n arquivos, $(mb "$sel_bytes") MB"
echo

# ---------- extrair ----------
feitos=0; pulados=0; falhos=0
while IFS=$'\t' read -r tam prim semfat caminho; do
  [ "$prim" -lt 2 ] && { echo "PULA  (sem cluster inicial)  $caminho"; pulados=$(( pulados + 1 )); continue; }

  precisa=$(( ( tam + bpc - 1 ) / bpc ))

  # monta a cadeia
  cadeia=""
  n=0
  if [ "$semfat" -ne 0 ]; then
    c=$prim
    while [ "$n" -lt "$precisa" ]; do cadeia="$cadeia $c"; c=$(( c + 1 )); n=$(( n + 1 )); done
  else
    c=$prim
    while [ "$c" -ge 2 ] && [ "$c" -lt $(( cluster_count + 2 )) ] && [ "$n" -lt "$precisa" ]; do
      cadeia="$cadeia $c"
      n=$(( n + 1 ))
      prox=$(u32 $(( fat_base + c * 4 )))
      if [ "$prox" -ge 4294967287 ] || [ "$prox" -lt 2 ]; then break; fi
      c=$prox
    done
  fi

  if [ "$n" -lt "$precisa" ]; then
    echo "FALHA (cadeia curta: $n de $precisa clusters)  $caminho"
    falhos=$(( falhos + 1 ))
    continue
  fi

  if [ "$SIMULAR" -eq 1 ]; then
    printf "%9s MB  cadeia OK  %d/%d clusters  %s\n" "$(mb "$tam")" "$n" "$precisa" "$caminho"
    continue
  fi

  saida="$DESTINO/$caminho"
  mkdir -p "$(dirname "$saida")"
  if [ -f "$saida" ] && [ "$(wc -c < "$saida" | tr -d ' ')" = "$tam" ]; then
    echo "PULA  (ja esta completo)  $caminho"
    pulados=$(( pulados + 1 ))
    continue
  fi

  tmp="$saida.parcial"
  : > "$tmp"
  # agrupa clusters contiguos em runs, para ler em blocos grandes
  ini=0; fim=0
  for cl in $cadeia; do
    if [ "$ini" -eq 0 ]; then ini=$cl; fim=$cl; continue; fi
    if [ "$cl" -eq $(( fim + 1 )) ]; then fim=$cl; continue; fi
    dd if="$DISPOSITIVO" bs=$bpc skip=$(( ( $(cl_off "$ini") ) / bpc )) \
       count=$(( fim - ini + 1 )) 2>/dev/null >> "$tmp"
    ini=$cl; fim=$cl
  done
  if [ "$ini" -ne 0 ]; then
    dd if="$DISPOSITIVO" bs=$bpc skip=$(( ( $(cl_off "$ini") ) / bpc )) \
       count=$(( fim - ini + 1 )) 2>/dev/null >> "$tmp"
  fi

  # corta o excesso do ultimo cluster para o tamanho exato do arquivo
  if command -v truncate >/dev/null 2>&1; then
    truncate -s "$tam" "$tmp"
  else
    dd if="$tmp" of="$tmp.corte" bs=1048576 count=$(( tam / 1048576 )) 2>/dev/null
    resto=$(( tam % 1048576 ))
    [ "$resto" -gt 0 ] && dd if="$tmp" of="$tmp.corte" bs=1 skip=$(( tam - resto )) \
      seek=$(( tam - resto )) count="$resto" conv=notrunc 2>/dev/null
    mv "$tmp.corte" "$tmp"
  fi

  real=$(wc -c < "$tmp" | tr -d ' ')
  if [ "$real" != "$tam" ]; then
    echo "FALHA (gravou $real de $tam bytes)  $caminho"
    falhos=$(( falhos + 1 ))
    continue
  fi
  mv "$tmp" "$saida"
  feitos=$(( feitos + 1 ))
  printf "OK    %9s MB  %s\n" "$(mb "$tam")" "$caminho"
done < "$SEL"

echo
echo "================= RESULTADO ================="
if [ "$SIMULAR" -eq 1 ]; then
  echo "Simulacao concluida. Rode sem --simular para extrair."
else
  echo "Extraidos: $feitos   Pulados: $pulados   Falhos: $falhos"
  echo "Destino  : $DESTINO"
  if [ "$falhos" -eq 0 ]; then
    echo "Nenhuma falha. Proximo passo: validar com ffprobe (04-validar.sh)."
  else
    echo "Houve falhas: os arquivos acima precisam de carving ou reparo."
  fi
fi
echo "============================================="
