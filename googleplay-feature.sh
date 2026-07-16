#!/usr/bin/env bash
#
# googleplay-feature.sh
# ---------------------
# Genera el "feature graphic" (gráfico de funciones) de Google Play a partir de
# una imagen o de una carpeta de imágenes, usando solo `sips` (nativo de macOS,
# sin dependencias externas).
#
# Requisitos de Google Play para el feature graphic:
#   - Formato PNG o JPEG.
#   - Tamaño EXACTO: 1024 px por 500 px (relación 2.048:1, siempre horizontal).
#   - Peso máximo: 15 MB.
#
# Este script deja cada imagen en 1024x500 exacto, sin deformar, con dos modos:
#
#     crop  (por defecto)  Escala para RELLENAR el lienzo y recorta al centro.
#                          Ideal si el arte ya es apaisado tipo banner.
#     pad                  Encaja la imagen COMPLETA dentro del lienzo y rellena
#                          el resto con un color de fondo (barras). Ideal si no
#                          quieres cortar nada (p. ej. un logo o una captura).
#
# Uso:
#     ./googleplay-feature.sh <imagen_o_carpeta> [opciones]
#
set -euo pipefail

# Tamaño fijo del feature graphic de Google Play.
TARGET_W=1024
TARGET_H=500
MAX_BYTES=$((15 * 1024 * 1024))   # 15 MB

# ---------------------------------------------------------------------------
# Ayuda
# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Uso: ./googleplay-feature.sh <imagen_o_carpeta> [opciones]

Genera el feature graphic de Google Play (PNG/JPEG, 1024x500 exacto, máx 15 MB).

Opciones:
  -o, --out <ruta>         Carpeta de salida     (por defecto: <origen>/feature)
  -m, --mode <crop|pad>    Modo de encaje        (por defecto: crop)
  -f, --format <png|jpg>   Formato de salida     (por defecto: png)
  -b, --bg <RRGGBB>        Color de relleno pad  (por defecto: 000000, negro)
  -h, --help               Muestra esta ayuda

Modos (-m):
  crop   Escala para rellenar 1024x500 y recorta al centro (sin deformar).
         Recomendado cuando el arte ya es apaisado (tipo banner).
  pad    Encaja la imagen completa dentro de 1024x500 y rellena el resto con
         el color -b (barras). Recomendado para no cortar nada (logo/captura).

Comportamiento:
  - Acepta una sola imagen o una carpeta (procesa todas las de dentro).
  - El resultado SIEMPRE mide 1024x500 exacto (relación 2.048:1).
  - Avisa si el archivo supera los 15 MB permitidos por Google Play.
  - Procesa: .png .jpg .jpeg .heic .heif .tif .tiff .gif .bmp

Ejemplos:
  ./googleplay-feature.sh ~/Desktop/banner.png
  ./googleplay-feature.sh ~/Desktop/banner.png -m pad -b FFFFFF
  ./googleplay-feature.sh ~/Desktop/arte -f jpg -o ~/Desktop/listas
EOF
}

# ---------------------------------------------------------------------------
# Parseo de argumentos
# ---------------------------------------------------------------------------
SRC=""
OUT_DIR=""
MODE="crop"
FORMAT="png"
BG="000000"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out)    OUT_DIR="${2:-}"; shift 2 ;;
    -m|--mode)   MODE="${2:-}";    shift 2 ;;
    -f|--format) FORMAT="${2:-}";  shift 2 ;;
    -b|--bg)     BG="${2:-}";      shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    -*)          echo "❌ Opción desconocida: $1" >&2; usage; exit 1 ;;
    *)
      if [[ -z "$SRC" ]]; then SRC="$1"; else
        echo "❌ Argumento inesperado: $1" >&2; exit 1
      fi
      shift ;;
  esac
done

if [[ -z "$SRC" ]]; then
  echo "❌ Falta la imagen o carpeta de origen." >&2
  usage
  exit 1
fi
if [[ ! -e "$SRC" ]]; then
  echo "❌ El origen no existe: $SRC" >&2
  exit 1
fi

case "$MODE" in
  crop|pad) ;;
  *) echo "❌ Modo no válido: $MODE (usa crop o pad)" >&2; exit 1 ;;
esac

case "$FORMAT" in
  png)       OUT_EXT="png";  SIPS_FORMAT="png"  ;;
  jpg|jpeg)  OUT_EXT="jpg";  SIPS_FORMAT="jpeg" ;;
  *)         echo "❌ Formato no válido: $FORMAT (usa png o jpg)" >&2; exit 1 ;;
esac

# Valida el color de fondo (6 dígitos hex) solo si se usará el modo pad.
if [[ "$MODE" == "pad" && ! "$BG" =~ ^[0-9A-Fa-f]{6}$ ]]; then
  echo "❌ Color de fondo no válido: $BG (usa 6 dígitos hex, p. ej. 000000)" >&2
  exit 1
fi

# Carpeta de salida por defecto: <origen>/feature (junto a la imagen/carpeta).
if [[ -z "$OUT_DIR" ]]; then
  if [[ -d "$SRC" ]]; then
    OUT_DIR="$SRC/feature"
  else
    OUT_DIR="$(cd "$(dirname "$SRC")" && pwd)/feature"
  fi
fi

# ---------------------------------------------------------------------------
# Procesa una imagen -> 1024x500 exacto según el modo elegido.
# ---------------------------------------------------------------------------
process() {
  local src="$1"
  local base name out W H
  base="$(basename "$src")"
  name="${base%.*}"
  out="$CUR_OUT/${name}.${OUT_EXT}"

  # Dimensiones originales en píxeles.
  W="$(sips -g pixelWidth  "$src" 2>/dev/null | awk '/pixelWidth/{print $2}')"
  H="$(sips -g pixelHeight "$src" 2>/dev/null | awk '/pixelHeight/{print $2}')"
  if [[ -z "$W" || -z "$H" ]]; then
    echo "  ⚠️  Omitida (no es una imagen válida): $base"
    return
  fi

  if [[ "$MODE" == "crop" ]]; then
    # RELLENAR: escala = max(Tw/W, Th/H). Al redimensionar el ancho a
    # ceil(W*scale) el alto también queda >= Th; luego recorte al centro.
    local newW
    newW="$(awk -v W="$W" -v H="$H" -v Tw="$TARGET_W" -v Th="$TARGET_H" 'BEGIN{
      sw = Tw / W; sh = Th / H;
      s  = (sw > sh) ? sw : sh;
      v  = W * s; r = int(v); if (v > r) r++;
      print r;
    }')"
    sips --resampleWidth "$newW"                 "$src" --out "$out" >/dev/null 2>&1
    sips --cropToHeightWidth "$TARGET_H" "$TARGET_W" "$out" --out "$out" >/dev/null 2>&1
  else
    # ENCAJAR: escala = min(Tw/W, Th/H) para que la imagen entera quepa.
    # newW/newH se truncan (floor) para garantizar que no exceden el lienzo,
    # y luego se rellena hasta 1024x500 con el color de fondo.
    local newW newH
    read -r newW newH <<EOF
$(awk -v W="$W" -v H="$H" -v Tw="$TARGET_W" -v Th="$TARGET_H" 'BEGIN{
  sw = Tw / W; sh = Th / H;
  s  = (sw < sh) ? sw : sh;
  nw = int(W * s); nh = int(H * s);
  if (nw < 1) nw = 1; if (nh < 1) nh = 1;
  if (nw > Tw) nw = Tw; if (nh > Th) nh = Th;
  print nw, nh;
}')
EOF
    sips --resampleHeightWidth "$newH" "$newW"   "$src" --out "$out" >/dev/null 2>&1
    sips --padToHeightWidth "$TARGET_H" "$TARGET_W" --padColor "$BG" \
                                                 "$out" --out "$out" >/dev/null 2>&1
  fi

  # Asegura el formato de salida.
  sips -s format "$SIPS_FORMAT" "$out" --out "$out" >/dev/null 2>&1

  # Aviso de peso (Google Play permite hasta 15 MB).
  local bytes warn=""
  bytes="$(stat -f%z "$out" 2>/dev/null || echo 0)"
  if (( bytes > MAX_BYTES )); then
    warn="  ⚠️  supera 15 MB ($(awk -v b="$bytes" 'BEGIN{printf "%.1f MB", b/1048576}'))"
  fi

  echo "  ✅ $base  ->  ${TARGET_W}x${TARGET_H} (${MODE})${warn}"
}

# ---------------------------------------------------------------------------
# Ejecución
# ---------------------------------------------------------------------------
shopt -s nullglob nocaseglob

CUR_OUT="$OUT_DIR"
mkdir -p "$CUR_OUT"

echo "📁 Origen : $SRC"
echo "🖼  Formato: $OUT_EXT   |  Modo: $MODE$( [[ $MODE == pad ]] && echo "  |  Fondo: #$BG" )"
echo "📐 Objetivo: ${TARGET_W}x${TARGET_H} (feature graphic Google Play)"
echo "📦 Salida : $CUR_OUT"
echo "================================================================"

count=0
if [[ -d "$SRC" ]]; then
  OUT_ABS="$(cd "$OUT_DIR" && pwd)"
  for f in "$SRC"/*.png "$SRC"/*.jpg "$SRC"/*.jpeg \
           "$SRC"/*.heic "$SRC"/*.heif \
           "$SRC"/*.tif "$SRC"/*.tiff \
           "$SRC"/*.gif "$SRC"/*.bmp; do
    # Evita reprocesar la propia carpeta de salida.
    [[ "$(cd "$(dirname "$f")" && pwd)" == "$OUT_ABS" ]] && continue
    process "$f"
    count=$((count + 1))
  done
else
  process "$SRC"
  count=1
fi

echo "----------------------------------------------------------------"
if (( count == 0 )); then
  echo "⚠️  No se encontraron imágenes en: $SRC"
else
  echo "✅ $count imagen(es) -> $CUR_OUT"
fi
