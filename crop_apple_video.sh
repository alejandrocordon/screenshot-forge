#!/usr/bin/env bash
#
# crop_apple_video.sh — recorta App Preview de video a las resoluciones
# oficiales de App Preview de la App Store usando ffmpeg, con la misma
# estrategia que las capturas: scale-to-cover + center-crop (sin barras
# negras ni distorsión). Nota: los videos usan resoluciones propias,
# distintas a las de los screenshots.
#
# Soporta .mp4 y .mov (también .m4v). Compatible con el bash 3.2 de macOS.
#
# Uso:
#   ./crop_apple_video.sh -i demo.mov -o ./output
#   ./crop_apple_video.sh -i ./videos -o ./output -d 6.7inch
#   ./crop_apple_video.sh demo.mp4                 # salida en ./output
#
# Requiere ffmpeg en el PATH (brew install ffmpeg).

set -euo pipefail

# ── Resoluciones oficiales de App Preview de la App Store (device:ANCHOxALTO)
# OJO: los videos NO usan los tamaños de los screenshots. Apple define
# resoluciones propias para los App Preview (portrait + landscape):
#   https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications/
SIZES=(
  "6.7inch:886x1920"
  "6.7inch:1920x886"
  "6.5inch:886x1920"
  "6.5inch:1920x886"
  "5.5inch:1080x1920"
  "5.5inch:1920x1080"
  "ipad_12.9inch:1200x1600"
  "ipad_12.9inch:1600x1200"
)

CRF=20            # calidad libx264 (menor = mejor)
INPUT=""
OUTPUT="./output"
DEVICE=""         # vacío = todos los dispositivos

# ── Ayuda ────────────────────────────────────────────────────────────
usage() {
  cat <<'USAGE'
crop_apple_video.sh — recorta videos a los tamaños de la App Store (Apple).

  -i, --input   <ruta>   Archivo de video o carpeta con videos (.mp4/.mov/.m4v).
  -o, --output  <ruta>   Carpeta de salida (default: ./output).
  -d, --device  <name>   Solo un dispositivo: 6.7inch | 6.5inch | 5.5inch | ipad_12.9inch.
  -h, --help             Muestra esta ayuda.

Salida: output/ios/<dispositivo>/<nombre>_<ancho>x<alto>.mp4
USAGE
}

# ── Parseo de argumentos ─────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    -i|--input)  INPUT="${2:-}"; shift 2 ;;
    -o|--output) OUTPUT="${2:-}"; shift 2 ;;
    -d|--device) DEVICE="${2:-}"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    -*)          echo "Opción desconocida: $1" >&2; usage; exit 2 ;;
    *)           INPUT="$1"; shift ;;   # primer posicional = input
  esac
done

# ── Validaciones ─────────────────────────────────────────────────────
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: ffmpeg no está instalado o no está en el PATH." >&2
  echo "       Instálalo con: brew install ffmpeg" >&2
  exit 1
fi

if [ -z "$INPUT" ]; then
  echo "Error: falta el input (-i)." >&2
  usage
  exit 2
fi

if [ ! -e "$INPUT" ]; then
  echo "Error: la ruta '$INPUT' no existe." >&2
  exit 1
fi

# Validar el dispositivo si se pidió uno concreto.
if [ -n "$DEVICE" ]; then
  known=""
  for entry in "${SIZES[@]}"; do
    d="${entry%%:*}"
    case " $known " in *" $d "*) : ;; *) known="$known $d" ;; esac
  done
  case " $known " in
    *" $DEVICE "*) : ;;
    *) echo "Error: dispositivo '$DEVICE' no válido. Opciones:$known" >&2; exit 2 ;;
  esac
fi

# ── ¿Es un archivo de video soportado? ───────────────────────────────
is_video() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    *.mp4|*.mov|*.m4v) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Recopilar los videos de entrada ──────────────────────────────────
VIDEOS=()
if [ -f "$INPUT" ]; then
  if is_video "$INPUT"; then
    VIDEOS+=("$INPUT")
  else
    echo "Error: '$INPUT' no es un video soportado (.mp4/.mov/.m4v)." >&2
    exit 1
  fi
else
  for f in "$INPUT"/*; do
    [ -f "$f" ] || continue
    if is_video "$f"; then VIDEOS+=("$f"); fi
  done
fi

if [ "${#VIDEOS[@]}" -eq 0 ]; then
  echo "No se encontraron videos (.mp4/.mov/.m4v) en: $INPUT" >&2
  exit 1
fi

# ── Procesar ─────────────────────────────────────────────────────────
generated=0
errors=0

echo "crop_apple_video"
echo "────────────────────────────────────────"
echo "  Videos:       ${#VIDEOS[@]}"
echo "  Salida:       $OUTPUT"
[ -n "$DEVICE" ] && echo "  Dispositivo:  $DEVICE"
echo "────────────────────────────────────────"

for video in "${VIDEOS[@]}"; do
  base="$(basename "$video")"
  stem="${base%.*}"

  for entry in "${SIZES[@]}"; do
    device="${entry%%:*}"
    wh="${entry#*:}"
    w="${wh%x*}"
    h="${wh#*x}"

    # Filtro por dispositivo, si se pidió.
    if [ -n "$DEVICE" ] && [ "$device" != "$DEVICE" ]; then
      continue
    fi

    out_dir="$OUTPUT/ios/$device"
    out_file="$out_dir/${stem}_${w}x${h}.mp4"
    mkdir -p "$out_dir"

    # scale ...=increase → escala para CUBRIR; crop centra al tamaño exacto.
    # fps=min(30,source_fps) → cabecea a 30 fps (máximo que acepta la App
    # Store para App Preview) sin subir el frame rate de fuentes ≤30.
    vf="scale=${w}:${h}:force_original_aspect_ratio=increase,crop=${w}:${h},fps=min(30\,source_fps)"

    if ffmpeg -nostdin -y -loglevel error \
        -i "$video" -vf "$vf" \
        -c:v libx264 -preset veryfast -crf "$CRF" -pix_fmt yuv420p \
        -c:a aac -movflags +faststart \
        "$out_file"; then
      generated=$((generated + 1))
      echo "  [OK] ios/$device/${stem}_${w}x${h}.mp4"
    else
      errors=$((errors + 1))
      echo "  [ERROR] $base → ${w}x${h}" >&2
    fi
  done
done

echo "════════════════════════════════════════"
echo "  Generados: $generated"
echo "  Errores:   $errors"
echo "════════════════════════════════════════"

[ "$errors" -gt 0 ] && [ "$generated" -eq 0 ] && exit 1
exit 0
