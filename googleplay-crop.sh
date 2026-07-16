#!/usr/bin/env bash
#
# googleplay-crop.sh
# ------------------
# Recorta todas las imágenes de una carpeta a una resolución válida para subir
# capturas a Google Play Console, usando solo `sips` (nativo de macOS, sin
# dependencias externas).
#
# Reglas de Google Play para capturas:
#   - Formato PNG (24 bits, sin alfa) o JPEG.
#   - Cada lado entre 320 px y 3840 px.
#   - El lado largo NO puede medir más del doble que el corto (máx. 2:1).
#   - Recomendado 16:9 / 9:16 en teléfono y 16:10 en tablet.
#
# Por eso este script recorta a proporciones seguras (no 20:9), garantizando
# que las capturas pasen la validación.
#
# Tamaños soportados (la orientación de cada imagen elige automáticamente
# entre portrait y landscape):
#
#     phone     Teléfono 16:9    ->  1080 x 1920  |  1920 x 1080
#     tablet7   Tablet 7"  16:10 ->  1200 x 1920  |  1920 x 1200
#     tablet10  Tablet 10" 16:10 ->  1600 x 2560  |  2560 x 1600
#     chromebook Chromebook 16:9 ->  1920 x 1080  (siempre landscape)
#     all       Genera phone + tablet7 + tablet10, cada uno en su subcarpeta.
#
# Cada imagen se escala para RELLENAR el lienzo manteniendo su proporción
# (sin deformar) y luego se recorta al centro hasta la resolución exacta.
#
# Uso:
#     ./googleplay-crop.sh <carpeta_origen> [opciones]
#
set -euo pipefail

# Tamaños que se generan con "-s all".
ALL_SIZES="phone tablet7 tablet10"

# ---------------------------------------------------------------------------
# Ayuda
# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Uso: ./googleplay-crop.sh <carpeta_origen> [opciones]

Opciones:
  -o, --out <carpeta>      Carpeta de salida    (por defecto: <origen>/googleplay)
  -s, --size <tamaño>      Tamaño objetivo       (por defecto: phone)
  -f, --format <png|jpg>   Formato de salida     (por defecto: png)
  -h, --help               Muestra esta ayuda

Tamaños (-s):
  phone       Teléfono 16:9     1080x1920 / 1920x1080
  tablet7     Tablet 7"  16:10  1200x1920 / 1920x1200
  tablet10    Tablet 10" 16:10  1600x2560 / 2560x1600
  chromebook  Chromebook 16:9   1920x1080 (siempre landscape)
  all         Genera phone + tablet7 + tablet10, cada uno en su subcarpeta.

Comportamiento:
  - Detecta la orientación de cada imagen (portrait / landscape).
  - Escala para rellenar manteniendo la proporción (no deforma).
  - Recorta al centro hasta la resolución exacta de Google Play.
  - Procesa: .png .jpg .jpeg .heic .heif .tif .tiff .gif .bmp

Ejemplos:
  ./googleplay-crop.sh ~/Desktop/capturas
  ./googleplay-crop.sh ~/Desktop/capturas -s tablet10 -f jpg
  ./googleplay-crop.sh ~/Desktop/capturas -s all -o ~/Desktop/listas
EOF
}

# ---------------------------------------------------------------------------
# Tabla de tamaños -> "PORT_W PORT_H LAND_W LAND_H etiqueta"
# (case en vez de array asociativo para que funcione con el bash 3.2 de macOS)
# ---------------------------------------------------------------------------
dims_for() {
  case "$1" in
    phone)      echo '1080 1920 1920 1080 Telefono Android 16:9' ;;
    tablet7)    echo '1200 1920 1920 1200 Tablet 7 pulgadas 16:10' ;;
    tablet10)   echo '1600 2560 2560 1600 Tablet 10 pulgadas 16:10' ;;
    chromebook) echo '1920 1080 1920 1080 Chromebook 16:9 landscape' ;;
    *)          return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Parseo de argumentos
# ---------------------------------------------------------------------------
SRC=""
OUT_DIR=""
SIZE="phone"
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
  echo "   Usa: phone, tablet7, tablet10, chromebook o all (ver --help)" >&2
  exit 1
fi

case "$FORMAT" in
  png)       OUT_EXT="png";  SIPS_FORMAT="png"  ;;
  jpg|jpeg)  OUT_EXT="jpg";  SIPS_FORMAT="jpeg" ;;
  *)         echo "❌ Formato no válido: $FORMAT (usa png o jpg)" >&2; exit 1 ;;
esac

# Carpeta de salida por defecto: <origen>/googleplay
OUT_DIR="${OUT_DIR:-$SRC/googleplay}"

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
