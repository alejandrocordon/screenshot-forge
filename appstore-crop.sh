#!/usr/bin/env bash
#
# appstore-crop.sh
# -----------------
# Recorta todas las imágenes de una carpeta a una resolución EXACTA válida para
# publicar capturas en App Store Connect, usando solo `sips` (nativo de macOS,
# sin dependencias externas).
#
# Tamaños soportados (la orientación de cada imagen elige automáticamente
# entre portrait y landscape):
#
#     6.9     iPhone 6.9"   ->  1290 x 2796  |  2796 x 1290   (15/16 Pro Max, 16 Plus)
#     6.9xl   iPhone 6.9"   ->  1320 x 2868  |  2868 x 1320   (iPhone 16 Pro Max nativo)
#     6.7     iPhone 6.7"   ->  1284 x 2778  |  2778 x 1284   (12/13/14 Pro Max)
#     6.5     iPhone 6.5"   ->  1242 x 2688  |  2688 x 1242   (XS Max, 11 Pro Max)
#     ipad    iPad Pro 13"  ->  2064 x 2752  |  2752 x 2064
#     ipad12  iPad Pro 12.9"->  2048 x 2732  |  2732 x 2048
#     all     Genera 6.9 + 6.5 + ipad, cada uno en su subcarpeta.
#
# Cada imagen se escala para RELLENAR el lienzo manteniendo su proporción
# (sin deformar) y luego se recorta al centro hasta la resolución exacta.
#
# Uso:
#     ./appstore-crop.sh <carpeta_origen> [opciones]
#
set -euo pipefail

# Tamaños que se generan con "-s all" (los slots requeridos hoy en App Store).
ALL_SIZES="6.9 6.5 ipad"

# ---------------------------------------------------------------------------
# Ayuda
# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Uso: ./appstore-crop.sh <carpeta_origen> [opciones]

Opciones:
  -o, --out <carpeta>      Carpeta de salida    (por defecto: <origen>/appstore)
  -s, --size <tamaño>      Tamaño objetivo       (por defecto: 6.5)
  -f, --format <png|jpg>   Formato de salida     (por defecto: png)
  -h, --help               Muestra esta ayuda

Tamaños (-s):
  6.9      iPhone 6.9"    1290x2796 / 2796x1290   (15/16 Pro Max, 16 Plus)
  6.9xl    iPhone 6.9"    1320x2868 / 2868x1320   (iPhone 16 Pro Max nativo)
  6.7      iPhone 6.7"    1284x2778 / 2778x1284   (12/13/14 Pro Max)
  6.5      iPhone 6.5"    1242x2688 / 2688x1242   (XS Max, 11 Pro Max)
  ipad     iPad Pro 13"   2064x2752 / 2752x2064
  ipad12   iPad Pro 12.9" 2048x2732 / 2732x2048
  all      Genera 6.9 + 6.5 + ipad, cada uno en su subcarpeta.

Comportamiento:
  - Detecta la orientación de cada imagen (portrait / landscape).
  - Escala para rellenar manteniendo la proporción (no deforma).
  - Recorta al centro hasta la resolución exacta de App Store.
  - Procesa: .png .jpg .jpeg .heic .heif .tif .tiff .gif .bmp

Ejemplos:
  ./appstore-crop.sh ~/Desktop/capturas
  ./appstore-crop.sh ~/Desktop/capturas -s 6.9 -f jpg
  ./appstore-crop.sh ~/Desktop/capturas -s all -o ~/Desktop/listas
EOF
}

# ---------------------------------------------------------------------------
# Tabla de tamaños -> "PORT_W PORT_H LAND_W LAND_H etiqueta"
# (case en vez de array asociativo para que funcione con el bash 3.2 de macOS)
# ---------------------------------------------------------------------------
dims_for() {
  case "$1" in
    6.9)    echo '1290 2796 2796 1290 iPhone 6.9 pulgadas' ;;
    6.9xl)  echo '1320 2868 2868 1320 iPhone 6.9 pulgadas (16 Pro Max)' ;;
    6.7)    echo '1284 2778 2778 1284 iPhone 6.7 pulgadas' ;;
    6.5)    echo '1242 2688 2688 1242 iPhone 6.5 pulgadas' ;;
    ipad)   echo '2064 2752 2752 2064 iPad Pro 13 pulgadas' ;;
    ipad12) echo '2048 2732 2732 2048 iPad Pro 12.9 pulgadas' ;;
    *)      return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Parseo de argumentos
# ---------------------------------------------------------------------------
SRC=""
OUT_DIR=""
SIZE="6.5"
FORMAT="png"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out)    OUT_DIR="${2:-}"; shift 2 ;;
    -s|--size)   SIZE="${2:-}";    shift 2 ;;
    -f|--format) FORMAT="${2:-}";  shift 2 ;;
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
  echo "❌ Falta la carpeta de origen." >&2
  usage
  exit 1
fi
if [[ ! -d "$SRC" ]]; then
  echo "❌ La carpeta de origen no existe: $SRC" >&2
  exit 1
fi

# Validación del tamaño (acepta "all" o cualquier clave de dims_for).
if [[ "$SIZE" != "all" ]] && ! dims_for "$SIZE" >/dev/null; then
  echo "❌ Tamaño no válido: $SIZE" >&2
  echo "   Usa: 6.9, 6.9xl, 6.7, 6.5, ipad, ipad12 o all (ver --help)" >&2
  exit 1
fi

case "$FORMAT" in
  png)       OUT_EXT="png";  SIPS_FORMAT="png"  ;;
  jpg|jpeg)  OUT_EXT="jpg";  SIPS_FORMAT="jpeg" ;;
  *)         echo "❌ Formato no válido: $FORMAT (usa png o jpg)" >&2; exit 1 ;;
esac

# Carpeta de salida por defecto: <origen>/appstore
OUT_DIR="${OUT_DIR:-$SRC/appstore}"

# ---------------------------------------------------------------------------
# Procesado de una imagen hacia el tamaño objetivo actual.
# Usa las variables globales: PORT_W PORT_H LAND_W LAND_H CUR_OUT
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

  # Orientación -> resolución objetivo.
  local Tw Th orient
  if (( W >= H )); then
    orient="landscape"; Tw="$LAND_W"; Th="$LAND_H"
  else
    orient="portrait";  Tw="$PORT_W"; Th="$PORT_H"
  fi

  # Escala mínima que cubre el objetivo en ambas dimensiones (sin deformar).
  # Como scale = max(Tw/W, Th/H), al redimensionar el ancho a ceil(W*scale)
  # el alto resultante también queda >= Th. Luego recortamos al centro.
  local newW
  newW="$(awk -v W="$W" -v H="$H" -v Tw="$Tw" -v Th="$Th" 'BEGIN{
    sw = Tw / W; sh = Th / H;
    s  = (sw > sh) ? sw : sh;
    v  = W * s; r = int(v); if (v > r) r++;
    print r;
  }')"

  # 1) Redimensiona por ancho conservando la proporción.
  # 2) Recorta al centro a la resolución exacta (alto, ancho).
  sips --resampleWidth  "$newW"        "$src" --out "$out"        >/dev/null 2>&1
  sips --cropToHeightWidth "$Th" "$Tw" "$out" --out "$out"        >/dev/null 2>&1

  # Asegura el formato/espacio de color de salida.
  sips -s format "$SIPS_FORMAT" "$out" --out "$out"               >/dev/null 2>&1

  echo "  ✅ $base  ->  ${Tw}x${Th} ($orient)"
}

# ---------------------------------------------------------------------------
# Procesa toda la carpeta para un único tamaño.
# ---------------------------------------------------------------------------
run_size() {
  local key="$1" out_base="$2"

  # Carga dimensiones y etiqueta del tamaño.
  set -- $(dims_for "$key")
  PORT_W="$1"; PORT_H="$2"; LAND_W="$3"; LAND_H="$4"; shift 4
  local label="$*"

  CUR_OUT="$out_base"
  mkdir -p "$CUR_OUT"

  echo "📐 $label  (portrait ${PORT_W}x${PORT_H} | landscape ${LAND_W}x${LAND_H})"
  echo "📦 Salida : $CUR_OUT"
  echo "----------------------------------------------------------------"

  local f count=0
  for f in "$SRC"/*.png "$SRC"/*.jpg "$SRC"/*.jpeg \
           "$SRC"/*.heic "$SRC"/*.heif \
           "$SRC"/*.tif "$SRC"/*.tiff \
           "$SRC"/*.gif "$SRC"/*.bmp; do
    # Evita reprocesar la propia carpeta de salida.
    [[ "$(cd "$(dirname "$f")" && pwd)" == "$(cd "$OUT_DIR" && pwd)" ]] && continue
    process "$f"
    count=$((count + 1))
  done

  echo "----------------------------------------------------------------"
  if (( count == 0 )); then
    echo "⚠️  No se encontraron imágenes en: $SRC"
  else
    echo "✅ $count imagen(es) -> $CUR_OUT"
  fi
  TOTAL_IMAGES="$count"
}

# ---------------------------------------------------------------------------
# Ejecución
# ---------------------------------------------------------------------------
shopt -s nullglob nocaseglob

echo "📁 Origen : $SRC"
echo "🖼  Formato: $OUT_EXT"
echo "================================================================"

if [[ "$SIZE" == "all" ]]; then
  for key in $ALL_SIZES; do
    run_size "$key" "$OUT_DIR/$key"
    echo
  done
  echo "✅ Listo. Sets generados en: $OUT_DIR/{$(echo "$ALL_SIZES" | tr ' ' ',')}"
else
  run_size "$SIZE" "$OUT_DIR"
fi
