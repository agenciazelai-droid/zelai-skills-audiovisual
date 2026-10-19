#!/usr/bin/env bash
# 00-triagem.sh - a primeira coisa a rodar. SOMENTE LEITURA.
#
# Faz tres coisas:
#   1. DESCOBRE sozinho: discos candidatos, qual marca e geracao de camera gravou
#      o cartao (pela estrutura e pelos nomes), e quanto material existe.
#   2. CONFERE o destino: existe, nao esta dentro do cartao, e tem espaco.
#   3. ENTREGA um plano, e lista o que precisa ser perguntado a quem trouxe o cartao.
#
# Nao escreve no cartao. Nao escreve no destino. Nao decide nada sozinho.
#
# Uso (macOS):
#     ./00-triagem.sh                                 # lista os candidatos
#     diskutil unmountDisk /dev/disk4                 # desmontar, SEM ejetar
#     sudo ./00-triagem.sh /dev/rdisk4 ~/resgate/cliente-x
#
# Uso (Linux):
#     sudo ./00-triagem.sh /dev/sdb /mnt/resgate/cliente-x

set -uo pipefail

DISPOSITIVO="${1:-}"
DESTINO="${2:-}"
SETOR=512

# ---------- 1. candidatos ----------
echo "================================================================"
echo " TRIAGEM - primeira leitura do cartao (nada e escrito)"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================"

if [ -z "$DISPOSITIVO" ]; then
  echo
  echo "--- Discos presentes ---"
  if command -v diskutil >/dev/null 2>&1; then
    diskutil list | sed 's/^/  /'
    echo
    echo "  Externos e removiveis:"
    diskutil list external physical 2>/dev/null | grep -E "^/dev/" | sed 's/^/    /'
  elif command -v lsblk >/dev/null 2>&1; then
    lsblk -o NAME,SIZE,TYPE,TRAN,MODEL,MOUNTPOINT | sed 's/^/  /'
  else
    ls -l /dev/sd* /dev/disk* 2>/dev/null | sed 's/^/  /'
  fi
  echo
  echo "ATENCAO: dois discos de tamanho parecido sao indistinguiveis pelo tamanho."
  echo "Confirme a origem pelo MODELO, nunca pelo numero de GB."
  echo
  echo "No macOS, desmonte sem ejetar antes de ler:"
  echo "    diskutil unmountDisk /dev/diskN"
  echo
  echo "Depois rode:  sudo $0 /dev/rdiskN <pasta-de-destino>"
  exit 0
fi

[ -r "$DISPOSITIVO" ] || { echo "ERRO: nao consigo ler $DISPOSITIVO (use sudo)" >&2; exit 1; }

# guarda: a origem nao pode ser o disco onde o sistema esta montado
if command -v diskutil >/dev/null 2>&1; then
  raiz_disco=$(diskutil info / 2>/dev/null | awk -F': *' '/Part of Whole/ {print $2}')
  alvo_disco=$(basename "$DISPOSITIVO" | sed 's/^r//')
  if [ -n "${raiz_disco:-}" ] && [ "$alvo_disco" = "$raiz_disco" ]; then
    echo "ERRO: $DISPOSITIVO e o disco do SISTEMA. Abortado." >&2
    exit 1
  fi
fi

echo
echo "Origem escolhida: $DISPOSITIVO"

# ---------- leitura ----------
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
gib() { awk -v b="$1" 'BEGIN{ printf "%.2f", b/1073741824 }'; }

# ---------- estado do sistema de arquivos ----------
echo
echo "--- Estado do sistema de arquivos ---"

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

INV="$(mktemp)"; trap 'rm -f "$INV"' EXIT
material=0
indice_ok=0

if [ "$vbr_base" -lt 0 ]; then
  echo "  exFAT nao localizado (nem principal, nem backup)."
  echo "  O indice pode ter se perdido: caminho provavel e carving, que exige imagem."
else
  if [ "$vbr_base" -eq "$base_particao" ]; then echo "  exFAT encontrado: VBR principal"
  else echo "  exFAT encontrado: VBR de BACKUP (o principal esta danificado)"; fi

  bps=$(( 1 << $(u8 $(( vbr_base + 108 ))) ))
  spc=$(( 1 << $(u8 $(( vbr_base + 109 ))) ))
  fat_offset=$(u32 $(( vbr_base + 80 )))
  heap_offset=$(u32 $(( vbr_base + 88 )))
  cluster_count=$(u32 $(( vbr_base + 92 )))
  root_cluster=$(u32 $(( vbr_base + 96 )))
  percent=$(u8 $(( vbr_base + 112 )))
  bpc=$(( bps * spc ))
  fat_base=$(( vbr_base + fat_offset * bps ))
  cl_off() { echo $(( vbr_base + heap_offset * bps + ( $1 - 2 ) * bpc )); }

  percorrer() {
    local cluster=$1 caminho=$2 nivel=$3
    [ "$nivel" -gt 6 ] && return
    local guarda=0
    while [ "$cluster" -ge 2 ] && [ "$cluster" -lt $(( cluster_count + 2 )) ] && [ "$guarda" -lt 1024 ]; do
      local base i
      base=$(cl_off "$cluster"); i=0
      while [ "$i" -lt "$bpc" ]; do
        local off tipo
        off=$(( base + i )); tipo=$(u8 "$off")
        [ "$tipo" -eq 0 ] && return
        if [ "$tipo" -eq 133 ]; then
          local sec attrs eh_pasta nome prim tam s j t2
          sec=$(u8 $(( off + 1 ))); attrs=$(u16 $(( off + 4 ))); eh_pasta=$(( attrs & 16 ))
          nome=""; prim=0; tam=0; s=1
          while [ "$s" -le "$sec" ]; do
            j=$(( off + s * 32 )); t2=$(u8 "$j")
            if [ "$t2" -eq 192 ]; then prim=$(u32 $(( j + 20 ))); tam=$(u64 $(( j + 24 )))
            elif [ "$t2" -eq 193 ]; then
              local pedaco k car
              pedaco=$(ler_hex $(( j + 2 )) 30)
              for (( k=0; k<60; k+=4 )); do
                car="${pedaco:$k:2}"; [ "$car" = "00" ] && continue
                nome="${nome}$(printf "\\x${car}")"
              done
            fi
            s=$(( s + 1 ))
          done
          if [ "$eh_pasta" -ne 0 ]; then
            [ "$prim" -ge 2 ] && percorrer "$prim" "${caminho}/${nome}" $(( nivel + 1 ))
          else
            printf "%s\t%s\n" "$tam" "${caminho}/${nome}" >> "$INV"
          fi
          i=$(( i + 32 * ( sec + 1 ) )); continue
        fi
        i=$(( i + 32 ))
      done
      local prox
      prox=$(u32 $(( fat_base + cluster * 4 )))
      if [ "$prox" -ge 4294967287 ] || [ "$prox" -lt 2 ]; then break; fi
      cluster=$prox; guarda=$(( guarda + 1 ))
    done
  }
  percorrer "$root_cluster" "" 0

  n_arq=$(wc -l < "$INV" | tr -d ' ')
  material=$(awk -F'\t' '{ s += $1 } END { print s+0 }' "$INV")
  [ "$n_arq" -gt 0 ] && indice_ok=1
  echo "  Arquivos no indice: $n_arq   Material: $(gib "$material") GiB"
  [ "$percent" -le 100 ] && echo "  PercentInUse do volume: ${percent}%"
fi

# ---------- 2. identificar a camera ----------
echo
echo "--- Quem gravou este cartao ---"
marca="nao identificada"; geracao=""
obs="$(mktemp)"; trap 'rm -f "$INV" "$obs"' EXIT

if [ "$indice_ok" -eq 1 ]; then
  tem_m4root=$(grep -ci "M4ROOT" "$INV" || true)
  tem_xdroot=$(grep -ci "XDROOT" "$INV" || true)
  tem_insta=$(grep -cE "Camera0[0-9]" "$INV" || true)
  tem_gopro=$(grep -ci "GOPRO" "$INV" || true)
  n_insv=$(grep -ci "\.insv$" "$INV" || true)
  n_rsv=$(grep -ci "\.rsv$" "$INV" || true)
  n_mxf=$(grep -ci "\.mxf$" "$INV" || true)

  if [ "$tem_xdroot" -gt 0 ] || [ "$n_mxf" -gt 0 ]; then
    marca="SONY - linha profissional"
    geracao="XDROOT: FX6, FX9, PXW, VENICE (XAVC-I/L, XDCAM, X-OCN)"
    echo "Copiar a arvore inteira a partir de PRIVATE/: o MXF sozinho perde XML, timecode e LUT." >> "$obs"
  elif [ "$tem_m4root" -gt 0 ]; then
    marca="SONY - linha hibrida / cinema compacta"
    geracao="M4ROOT: A7, FX3, FX30, ZV (XAVC S / XAVC HS)"
    echo "Copiar a arvore inteira a partir de PRIVATE/: o MP4 sozinho perde o XML por clipe." >> "$obs"
    echo "Numeracao C0001 reseta a cada formatacao: criar uma pasta por cartao no destino." >> "$obs"
  elif [ "$tem_gopro" -gt 0 ]; then
    marca="GOPRO"
    geracao="estrutura DCIM/1xxGOPRO"
    echo "Arquivo acima de 4 GB e dividido em capitulos: recuperar todos os pedacos." >> "$obs"
  elif [ "$tem_insta" -gt 0 ] || [ "$n_insv" -gt 0 ]; then
    marca="INSTA360"
    com_par=$(grep -oE "VID_[0-9]{8}_[0-9]{6}_(00|10)_[0-9]+\.insv" "$INV" \
      | sed -E 's/VID_([0-9]{8}_[0-9]{6})_(00|10)_([0-9]+)\.insv/\1_\3/' \
      | sort | uniq -c | awk '$1 >= 2' | wc -l | tr -d ' ')
    so_um=$(grep -oE "VID_[0-9]{8}_[0-9]{6}_(00|10)_[0-9]+\.insv" "$INV" \
      | sed -E 's/VID_([0-9]{8}_[0-9]{6})_(00|10)_([0-9]+)\.insv/\1_\3/' \
      | sort | uniq -c | awk '$1 == 1' | wc -l | tr -d ' ')
    lrv_insv=$(grep -c "LRV_.*\.insv$" "$INV" || true)
    lrv_lrv=$(grep -c "LRV_.*\.lrv$" "$INV" || true)

    if [ "$com_par" -gt 0 ]; then
      geracao="ONE X, ONE X2 ou X3 em alta resolucao - DOIS arquivos por clipe 360"
      echo "CRITICO: $com_par clipe(s) em par _00_/_10_. Os dois arquivos do par sao obrigatorios;" >> "$obs"
      echo "recuperar so um lado entrega clipe que NAO costura o 360." >> "$obs"
      [ "$so_um" -gt 0 ] && echo "ATENCAO: $so_um clipe(s) com apenas uma lente no indice - possivel perda." >> "$obs"
      if [ "$lrv_insv" -gt 0 ] && [ "$lrv_lrv" -eq 0 ]; then
        geracao="ONE X2 - LRV com extensao .insv confirma esta geracao"
      fi
      [ "$lrv_lrv" -gt 0 ] && geracao="X3 - LRV com extensao .lrv"
    elif [ "$n_insv" -gt 0 ]; then
      geracao="X4, X4 Air, X5 ou X6 - UM arquivo por clipe, com as duas lentes"
      echo "Sem risco de par incompleto nesta geracao." >> "$obs"
    fi
    echo "Conferir DCIM/Camera01/Thumb: toda miniatura deve ter seu video. Miniatura orfa = clipe perdido." >> "$obs"
  fi

  if [ "$n_rsv" -gt 0 ]; then
    echo "ACHADO IMPORTANTE: $n_rsv arquivo(s) .rsv - gravacao interrompida da Sony." >> "$obs"
    echo "NAO apagar: o material esta dentro. Ver references/sony.md antes de agir." >> "$obs"
  fi
fi

echo "  Marca   : $marca"
[ -n "$geracao" ] && echo "  Geracao : $geracao"
if [ -s "$obs" ]; then echo; sed 's/^/  * /' "$obs"; fi

# ---------- 3. destino ----------
echo
echo "--- Destino dos arquivos recuperados ---"
echo "O material sai do cartao para uma pasta que VOCE escolhe. O cartao nunca e escrito."

if [ -z "$DESTINO" ]; then
  echo
  echo "Nenhum destino informado. Rode de novo com a pasta como segundo argumento."
  [ "$material" -gt 0 ] && echo "Reserve pelo menos $(gib "$material") GiB livres."
else
  pai="$(dirname "$DESTINO")"
  if [ ! -d "$pai" ]; then
    echo "  ERRO: a pasta pai '$pai' nao existe."
  else
    # o destino nao pode estar no mesmo dispositivo da origem
    if command -v diskutil >/dev/null 2>&1; then
      dev_destino=$(df "$pai" 2>/dev/null | awk 'NR==2 {print $1}')
      alvo=$(basename "$DISPOSITIVO" | sed 's/^r//')
      case "$dev_destino" in
        *"$alvo"*) echo "  ERRO: o destino esta NO PROPRIO CARTAO. Isso reescreveria a origem."; echo "  Escolha uma pasta em outro disco."; ;;
        *) echo "  Destino em $dev_destino - diferente da origem. OK." ;;
      esac
    fi
    if [ -d "$DESTINO" ]; then
      ja=$(find "$DESTINO" -type f 2>/dev/null | wc -l | tr -d ' ')
      [ "$ja" -gt 0 ] && echo "  AVISO: a pasta ja tem $ja arquivo(s). Prefira uma pasta vazia por cartao."
    else
      echo "  A pasta '$DESTINO' ainda nao existe - sera criada na extracao."
    fi
    livre_kb=$(df -k "$pai" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "${livre_kb:-}" ]; then
      livre=$(( livre_kb * 1024 ))
      echo "  Livre no destino: $(gib "$livre") GiB"
      if [ "$material" -gt 0 ]; then
        echo "  Material a copiar: $(gib "$material") GiB"
        margem=$(( material + material / 20 ))
        if [ "$livre" -ge "$margem" ]; then
          echo "  CABE, com $(gib $(( livre - material ))) GiB de folga."
        else
          echo "  NAO CABE: faltam $(gib $(( margem - livre ))) GiB."
          echo "  Saidas: liberar espaco, outro disco, ou extrair so os masters (--so-master)."
        fi
      fi
    fi
  fi
fi

# ---------- 4. plano ----------
echo
echo "===================== PLANO ====================="
if [ "$indice_ok" -eq 1 ] && [ "$material" -gt 0 ]; then
  echo "Indice legivel: o caminho e EXTRACAO PELO INDICE."
  echo "Nao precisa de imagem bit-a-bit nem de carving."
  echo
  echo "  1) confirmar a consistencia:"
  echo "     sudo ./02-diagnostico-exfat.sh $DISPOSITIVO"
  echo "  2) simular (valida as cadeias, nao escreve):"
  echo "     sudo ./03-extrair.sh $DISPOSITIVO ${DESTINO:-<pasta>} --simular"
  echo "  3) extrair:"
  echo "     sudo ./03-extrair.sh $DISPOSITIVO ${DESTINO:-<pasta>} --so-master"
  echo "  4) validar com ffprobe (decodificar inicio, meio e fim de cada arquivo)"
else
  echo "Indice nao rendeu arquivos: o caminho passa por IMAGEM + CARVING."
  echo "  1) imagem com ddrescue (reserve ~2x a capacidade do cartao)"
  echo "  2) PhotoRec sobre a imagem (ver references/ferramentas.md)"
fi
echo "================================================="

# ---------- 5. o que o script nao sabe ----------
echo
echo "--- Perguntar a quem trouxe o cartao (muda o que ainda e possivel) ---"
echo "  1. O cartao voltou para a camera depois do problema?"
echo "  2. Rodou 'reparar unidade', chkdsk, ou Primeiros Socorros do macOS?"
echo "  3. Algum programa de recuperacao ja passou nele? Qual?"
echo "  4. Houve formatacao, mesmo rapida?"
echo "  5. Qual o modelo exato da camera? (confirma o que a estrutura sugeriu acima)"
echo "  6. Falta material que nem aparece na lista? Quantos clipes ele lembra de ter gravado?"
echo
echo "Resposta 'sim' em 2, 3 ou 4 reduz as chances e muda o caminho - ver references/triagem.md."
