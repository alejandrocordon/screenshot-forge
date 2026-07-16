#!/usr/bin/env bash
#
# googleplay-icon.sh
# ------------------
# Convierte "unos recursos de icono" en el icono de app de Google Play:
#
#     Formato PNG o JPEG, tamaño EXACTO 512 x 512 px, peso máximo 1 MB.
#
# Acepta como entrada:
#   - Una imagen normal      (.png .jpg .jpeg .webp .heic .tif .gif .bmp ...)
#   - Un SVG                 (.svg)
#   - Un vector drawable XML de Android          (<vector ...>)
#   - Un adaptive icon de Android                (<adaptive-icon> con
#       background + foreground), pasándolo directo o con --foreground/--background
#   - Una carpeta: se autodetecta el mejor recurso (adaptive icon, SVG o PNG).
#
# Motor (usa lo mejor que haya instalado):
#   - rsvg-convert (o qlmanage) para rasterizar SVG / vector XML.
#   - Pillow (Python) para componer capas, encajar a 512x512, dar formato y
#     mantener el peso por debajo de 1 MB.  Pillow ya está en requirements.txt.
#   - sips no se usa aquí porque no sabe componer capas ni leer SVG.
#
# Uso:
#     ./googleplay-icon.sh <recurso_o_carpeta> [opciones]
#
set -euo pipefail

TARGET=512
MAX_BYTES=$((1 * 1024 * 1024))   # 1 MB

# ---------------------------------------------------------------------------
# Ayuda
# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Uso: ./googleplay-icon.sh <recurso_o_carpeta> [opciones]

Convierte recursos de icono al icono de Google Play (PNG/JPEG, 512x512, máx 1 MB).

Opciones:
  -o, --out <ruta>              Carpeta de salida  (por defecto: <origen>/icon)
  -f, --format <png|jpg>        Formato de salida  (por defecto: png)
  -m, --mode <cover|contain>    Encaje si no es cuadrado (por defecto: cover)
  -b, --bg <RRGGBB|none>        Fondo para 'contain'/JPEG  (por defecto: FFFFFF)
  -n, --name <nombre>           Nombre del archivo de salida (sin extensión)
      --foreground <archivo>    Capa frontal   (adaptive icon)
      --background <arch|#hex>  Capa de fondo o color (adaptive icon)
  -h, --help                    Muestra esta ayuda

Entradas admitidas:
  imagen (.png/.jpg/.webp/.heic/...), .svg, vector XML de Android,
  adaptive icon XML (background + foreground), o una carpeta con esos recursos.

Modos (-m):
  cover    Rellena 512x512 y recorta al centro (por defecto; ideal si ya es
           cuadrado o de borde a borde).
  contain  Encaja el icono completo sin recortar y rellena con -b (para logos).

Notas:
  - El resultado SIEMPRE mide 512x512 exacto.
  - Con -f png se conserva la transparencia (usa -b none para relleno transparente
    en 'contain'); Google Play prefiere iconos opacos, por eso -b FFFFFF por defecto.
  - Con -f jpg se aplana sobre -b y se baja la calidad si hiciera falta para ≤1 MB.
  - Vector drawable XML: conversión "best-effort" (paths, grupos, colores sólidos).
    Gradientes/clip-path complejos pueden no convertirse; en ese caso pasa un
    SVG o PNG del foreground.

Ejemplos:
  ./googleplay-icon.sh logo.svg
  ./googleplay-icon.sh icon.png -m contain -b FFFFFF
  ./googleplay-icon.sh ic_launcher.xml -o ~/Desktop/listo
  ./googleplay-icon.sh --foreground fg.svg --background '#1E88E5' -o out
  ./googleplay-icon.sh ./app/src/main/res        # autodetecta el adaptive icon
EOF
}

# ---------------------------------------------------------------------------
# Parseo de argumentos
# ---------------------------------------------------------------------------
SRC=""
OUT_DIR=""
FORMAT="png"
MODE="cover"
BG="FFFFFF"
NAME=""
FG_SPEC=""
BG_SPEC=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out)        OUT_DIR="${2:-}";  shift 2 ;;
    -f|--format)     FORMAT="${2:-}";   shift 2 ;;
    -m|--mode)       MODE="${2:-}";     shift 2 ;;
    -b|--bg)         BG="${2:-}";       shift 2 ;;
    -n|--name)       NAME="${2:-}";     shift 2 ;;
    --foreground)    FG_SPEC="${2:-}";  shift 2 ;;
    --background)    BG_SPEC="${2:-}";  shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    -*)              echo "❌ Opción desconocida: $1" >&2; usage; exit 1 ;;
    *)
      if [[ -z "$SRC" ]]; then SRC="$1"; else
        echo "❌ Argumento inesperado: $1" >&2; exit 1
      fi
      shift ;;
  esac
done

# Normaliza formato/modo/color.
case "$FORMAT" in
  png)       OUT_EXT="png" ;;
  jpg|jpeg)  OUT_EXT="jpg" ;;
  *)         echo "❌ Formato no válido: $FORMAT (usa png o jpg)" >&2; exit 1 ;;
esac
case "$MODE" in
  cover|contain) ;;
  *) echo "❌ Modo no válido: $MODE (usa cover o contain)" >&2; exit 1 ;;
esac
BG="${BG#\#}"   # admite tanto "FFFFFF" como "#FFFFFF"
if [[ "$BG" != "none" && ! "$BG" =~ ^[0-9A-Fa-f]{6}$ ]]; then
  echo "❌ Color -b no válido: $BG (usa 6 dígitos hex o 'none')" >&2; exit 1
fi

# Origen obligatorio salvo que se usen --foreground/--background.
if [[ -z "$SRC" && -z "$FG_SPEC" && -z "$BG_SPEC" ]]; then
  echo "❌ Falta el recurso de origen." >&2
  usage
  exit 1
fi
if [[ -n "$SRC" && ! -e "$SRC" ]]; then
  echo "❌ El origen no existe: $SRC" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Dependencias
# ---------------------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ Se necesita python3." >&2; exit 1
fi
if ! python3 -c 'import PIL' >/dev/null 2>&1; then
  echo "❌ Se necesita Pillow (ya está en requirements.txt):" >&2
  echo "     pip3 install Pillow" >&2
  exit 1
fi

have_svg_engine() { command -v rsvg-convert >/dev/null 2>&1 || command -v qlmanage >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Carpeta de salida por defecto y nombre.
# ---------------------------------------------------------------------------
if [[ -z "$OUT_DIR" ]]; then
  if [[ -n "$SRC" && -d "$SRC" ]]; then
    OUT_DIR="$SRC/icon"
  elif [[ -n "$SRC" ]]; then
    OUT_DIR="$(cd "$(dirname "$SRC")" && pwd)/icon"
  else
    OUT_DIR="$(pwd)/icon"
  fi
fi

# ---------------------------------------------------------------------------
# Ayudante Python (embebido para que sea un único archivo).
# ---------------------------------------------------------------------------
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/gpicon.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
PYH="$TMPD/helper.py"
N=0   # contador para nombres de temporales

cat > "$PYH" <<'PYEOF'
#!/usr/bin/env python3
# Ayudante de googleplay-icon.sh: conversión vector-drawable->SVG, composición
# de adaptive icon, encaje a 512x512, formato y control de peso (<=1 MB).
import sys, os, argparse
import xml.etree.ElementTree as ET
from PIL import Image, ImageOps

AND  = '{http://schemas.android.com/apk/res/android}'
AAPT = '{http://schemas.android.com/aapt}'

def warn(m): print("  ⚠️  " + m, file=sys.stderr)

def css_rgb(h):
    h = h.strip().lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))

def css_rgba(h):
    r, g, b = css_rgb(h); return (r, g, b, 255)

def android_color(c):
    """#RGB / #ARGB / #RRGGBB / #AARRGGBB -> ('#RRGGBB', opacity) o (None, None)."""
    if not c: return (None, None)
    c = c.strip()
    if c.startswith('@') or c.startswith('?'): return (None, None)
    c = c.lstrip('#')
    if len(c) == 3:
        c = ''.join(x * 2 for x in c)
    elif len(c) == 4:  # #ARGB
        a = int(c[0] * 2, 16); c = ''.join(x * 2 for x in c[1:]); return ('#' + c.upper(), a / 255.0)
    if len(c) == 6:
        return ('#' + c.upper(), 1.0)
    if len(c) == 8:  # #AARRGGBB
        a = int(c[0:2], 16); return ('#' + c[2:].upper(), a / 255.0)
    return (None, None)

# ---------------------------------------------------------------------------
def load_any(path):
    im = Image.open(path)
    im = ImageOps.exif_transpose(im)
    return im.convert('RGBA')

def fit(img, size, mode, bg_rgba):
    w, h = img.size
    if mode == 'cover':
        s = max(size / w, size / h)
        nw, nh = max(1, round(w * s)), max(1, round(h * s))
        r = img.resize((nw, nh), Image.LANCZOS)
        l, t = (nw - size) // 2, (nh - size) // 2
        return r.crop((l, t, l + size, t + size))
    else:  # contain
        s = min(size / w, size / h)
        nw, nh = max(1, round(w * s)), max(1, round(h * s))
        r = img.resize((nw, nh), Image.LANCZOS)
        c = Image.new('RGBA', (size, size), bg_rgba)
        c.alpha_composite(r, ((size - nw) // 2, (size - nh) // 2))
        return c

def save_within(img, out, fmt, bgcolor, maxbytes):
    if fmt in ('jpg', 'jpeg'):
        jpgbg = (255, 255, 255) if bgcolor.lower() == 'none' else css_rgb(bgcolor)
        base = Image.new('RGB', img.size, jpgbg)
        rgba = img.convert('RGBA')
        base.paste(rgba, mask=rgba.split()[-1])
        q = 92
        while True:
            base.save(out, 'JPEG', quality=q, optimize=True, progressive=True)
            if os.path.getsize(out) <= maxbytes or q <= 40:
                break
            q -= 6
    else:
        img.convert('RGBA').save(out, 'PNG', optimize=True)
        if os.path.getsize(out) > maxbytes:
            try:
                pal = img.convert('RGBA').quantize(colors=256, method=Image.FASTOCTREE)
                tmp = out + '.q.png'
                pal.save(tmp, 'PNG', optimize=True)
                if os.path.getsize(tmp) <= maxbytes and os.path.getsize(tmp) < os.path.getsize(out):
                    os.replace(tmp, out)
                else:
                    os.remove(tmp)
            except Exception as e:
                warn('no se pudo optimizar el PNG: %s' % e)
    im = Image.open(out)
    print('%dx%d %d' % (im.size[0], im.size[1], os.path.getsize(out)))

# ---------------------------------------------------------------------------
def cmd_render(a):
    WORK = max(1024, a.size)
    if a.src and a.src != 'NONE':
        base = load_any(a.src)
    else:
        # Componer background + foreground (adaptive icon).
        if a.bg and a.bg != 'NONE':
            if a.bg.startswith('#'):
                base = Image.new('RGBA', (WORK, WORK), css_rgba(a.bg))
            else:
                base = fit(load_any(a.bg), WORK, 'cover', (0, 0, 0, 0))
        else:
            base = Image.new('RGBA', (WORK, WORK), (0, 0, 0, 0))
        if a.fg and a.fg != 'NONE':
            fg = fit(load_any(a.fg), WORK, 'contain', (0, 0, 0, 0))
            base.alpha_composite(fg)

    pad = (0, 0, 0, 0) if a.bgcolor.lower() == 'none' else css_rgba(a.bgcolor)
    img = fit(base, a.size, a.mode, pad if a.mode == 'contain' else (0, 0, 0, 0))
    save_within(img, a.out, a.format, a.bgcolor, a.maxbytes)

def cmd_solid(a):
    col = (0, 0, 0, 0) if a.color.lower() == 'none' else css_rgba(a.color)
    Image.new('RGBA', (a.size, a.size), col).save(a.out, 'PNG')

# ---------------------------------------------------------------------------
def cmd_vd2svg(a):
    root = ET.parse(a.inp).getroot()
    if not root.tag.split('}')[-1] == 'vector':
        print('no es un vector drawable', file=sys.stderr); sys.exit(2)
    vw = float(root.get(AND + 'viewportWidth') or root.get(AND + 'width') or 24)
    vh = float(root.get(AND + 'viewportHeight') or root.get(AND + 'height') or 24)
    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %g %g" width="%g" height="%g">'
           % (vw, vh, vw, vh)]
    unsupported = set()

    def emit_path(el, ind):
        d = el.get(AND + 'pathData')
        if not d: return
        if el.find(AAPT + 'attr') is not None:  # fill/stroke con gradiente
            unsupported.add('gradiente (se rellena en gris)')
            fillhex, fop = '#808080', 1.0
        else:
            fillhex, fop = android_color(el.get(AND + 'fillColor'))
        if fillhex is None:
            fc = el.get(AND + 'fillColor')
            if fc and fc.startswith('@'):
                unsupported.add('color por @referencia (se usa negro)')
                fillhex, fop = '#000000', 1.0
            else:
                fillhex, fop = 'none', 1.0
        attrs = ['d="%s"' % d, 'fill="%s"' % fillhex]
        fa = el.get(AND + 'fillAlpha')
        if fa:
            try: fop = float(fa)
            except ValueError: pass
        if fop is not None and fop < 1:
            attrs.append('fill-opacity="%.3f"' % fop)
        ft = el.get(AND + 'fillType')
        if ft and ft.lower() == 'evenodd':
            attrs.append('fill-rule="evenodd"')
        sh, sop = android_color(el.get(AND + 'strokeColor'))
        if sh and sh != 'none':
            attrs.append('stroke="%s"' % sh)
            sw = el.get(AND + 'strokeWidth')
            if sw: attrs.append('stroke-width="%s"' % sw)
            sa = el.get(AND + 'strokeAlpha')
            if sa:
                try: sop = float(sa)
                except ValueError: pass
            if sop is not None and sop < 1:
                attrs.append('stroke-opacity="%.3f"' % sop)
        out.append(ind + '<path ' + ' '.join(attrs) + '/>')

    def walk(el, ind):
        for ch in el:
            tag = ch.tag.split('}')[-1]
            if tag == 'path':
                emit_path(ch, ind)
            elif tag == 'group':
                tx = float(ch.get(AND + 'translateX') or 0); ty = float(ch.get(AND + 'translateY') or 0)
                sx = float(ch.get(AND + 'scaleX') or 1);      sy = float(ch.get(AND + 'scaleY') or 1)
                rot = float(ch.get(AND + 'rotation') or 0)
                px = float(ch.get(AND + 'pivotX') or 0);      py = float(ch.get(AND + 'pivotY') or 0)
                tf = []
                if tx or ty: tf.append('translate(%g %g)' % (tx, ty))
                if rot:      tf.append('rotate(%g %g %g)' % (rot, px, py))
                if sx != 1 or sy != 1:
                    tf.append('translate(%g %g) scale(%g %g) translate(%g %g)' % (px, py, sx, sy, -px, -py))
                out.append(ind + ('<g transform="%s">' % ' '.join(tf) if tf else '<g>'))
                walk(ch, ind + '  ')
                out.append(ind + '</g>')
            elif tag == 'clip-path':
                unsupported.add('clip-path (se ignora)')
    walk(root, '  ')
    out.append('</svg>')
    with open(a.out, 'w') as f:
        f.write('\n'.join(out))
    for u in sorted(unsupported):
        warn('vector XML: ' + u)

# ---------------------------------------------------------------------------
def _resolve_color(name, root):
    for dp, _dn, fn in os.walk(root):
        if os.path.basename(dp).startswith('values'):
            for f in fn:
                if f.endswith('.xml'):
                    try: t = ET.parse(os.path.join(dp, f)).getroot()
                    except ET.ParseError: continue
                    for c in t.iter('color'):
                        if c.get('name') == name and c.text:
                            return c.text.strip()
    return None

def _search_file(name, root):
    order = ['.png', '.webp', '.jpg', '.jpeg', '.svg', '.xml']
    found = {}
    for dp, _dn, fn in os.walk(root):
        for f in fn:
            b, e = os.path.splitext(f)
            e = e.lower()
            if b == name and e in order:
                p = os.path.join(dp, f)
                if e in ('.png', '.webp', '.jpg', '.jpeg'):
                    # entre densidades, quédate con la de mayor área
                    prev = found.get(e)
                    if prev is None or os.path.getsize(p) > os.path.getsize(prev):
                        found[e] = p
                else:
                    found.setdefault(e, p)
    for e in order:
        if e in found: return found[e]
    return None

def _resolve_ref(ref, root):
    """Devuelve una ruta de archivo, un color '#RRGGBB' o 'NONE'."""
    if not ref: return 'NONE'
    ref = ref.strip()
    if ref.startswith('#'):
        css, op = android_color(ref)
        if css is None: return 'NONE'
        return 'NONE' if op == 0 else css
    if ref.startswith('@android:color/'):
        name = ref.rsplit('/', 1)[-1].lower()
        return {'white': '#FFFFFF', 'black': '#000000'}.get(name, 'NONE' if name == 'transparent' else '#FFFFFF')
    if ref.startswith('@color/'):
        hexv = _resolve_color(ref.rsplit('/', 1)[-1], root)
        if hexv:
            css, op = android_color(hexv)
            if css: return 'NONE' if op == 0 else css
        return 'NONE'
    if ref.startswith('@drawable/') or ref.startswith('@mipmap/'):
        return _search_file(ref.rsplit('/', 1)[-1], root) or 'NONE'
    if os.path.exists(ref):
        return ref
    return 'NONE'

def cmd_adaptive(a):
    root = ET.parse(a.xml).getroot()
    result = {}
    for layer in ('background', 'foreground'):
        el = root.find(AND + layer)
        if el is None: el = root.find(layer)
        spec = 'NONE'
        if el is not None:
            inline = el.find(AAPT + 'attr')
            if inline is not None and len(inline):
                child = list(inline)[0]  # <vector> embebido
                tmp = os.path.join(a.tmp, layer + '_inline.xml')
                ET.ElementTree(child).write(tmp, xml_declaration=True, encoding='utf-8')
                spec = tmp
            else:
                spec = _resolve_ref(el.get(AND + 'drawable'), a.root)
        result[layer] = spec
    print('BG ' + result['background'])
    print('FG ' + result['foreground'])

# ---------------------------------------------------------------------------
def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest='cmd', required=True)

    r = sub.add_parser('render')
    r.add_argument('--src', default='NONE'); r.add_argument('--bg', default='NONE')
    r.add_argument('--fg', default='NONE'); r.add_argument('--out', required=True)
    r.add_argument('--format', default='png'); r.add_argument('--mode', default='cover')
    r.add_argument('--bgcolor', default='FFFFFF'); r.add_argument('--size', type=int, default=512)
    r.add_argument('--maxbytes', type=int, default=1048576)
    r.set_defaults(fn=cmd_render)

    s = sub.add_parser('solid')
    s.add_argument('--color', required=True); s.add_argument('--out', required=True)
    s.add_argument('--size', type=int, default=1024); s.set_defaults(fn=cmd_solid)

    v = sub.add_parser('vd2svg')
    v.add_argument('inp'); v.add_argument('out'); v.set_defaults(fn=cmd_vd2svg)

    ad = sub.add_parser('adaptive')
    ad.add_argument('xml'); ad.add_argument('--root', required=True)
    ad.add_argument('--tmp', required=True); ad.set_defaults(fn=cmd_adaptive)

    a = p.parse_args()
    a.fn(a)

if __name__ == '__main__':
    main()
PYEOF

# ---------------------------------------------------------------------------
# Rasteriza un SVG a PNG (rsvg-convert preferido, qlmanage de respaldo).
# ---------------------------------------------------------------------------
svg_to_png() {
  local in="$1" out="$2"
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w 1024 -h 1024 -a "$in" -o "$out" 2>/dev/null && [[ -s "$out" ]] && return 0
  fi
  if command -v qlmanage >/dev/null 2>&1; then
    local qd="$TMPD/ql.$N"; mkdir -p "$qd"
    qlmanage -t -s 1024 -o "$qd" "$in" >/dev/null 2>&1 || true
    local produced="$qd/$(basename "$in").png"
    [[ -f "$produced" ]] && { mv "$produced" "$out"; return 0; }
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Convierte cualquier recurso a una imagen que Pillow pueda abrir.
# Imprime la ruta resultante (rasteriza SVG / vector XML; los rásters se pasan
# tal cual).  Los colores '#hex' se devuelven sin tocar.
# ---------------------------------------------------------------------------
resolve_to_image() {
  local spec="$1" ext
  if [[ "$spec" == "#"* || "$spec" == "NONE" || "$spec" == "none" ]]; then
    echo "$spec"; return 0
  fi
  if [[ ! -e "$spec" ]]; then
    echo "❌ No existe el recurso: $spec" >&2; return 1
  fi
  ext="$(printf '%s' "${spec##*.}" | tr '[:upper:]' '[:lower:]')"
  N=$((N + 1))
  case "$ext" in
    svg)
      have_svg_engine || { echo "❌ Necesito rsvg-convert o qlmanage para leer SVG (brew install librsvg)." >&2; return 1; }
      local o="$TMPD/img.$N.png"
      svg_to_png "$spec" "$o" || { echo "❌ No pude rasterizar el SVG: $spec" >&2; return 1; }
      echo "$o" ;;
    xml)
      have_svg_engine || { echo "❌ Necesito rsvg-convert o qlmanage para el vector XML (brew install librsvg)." >&2; return 1; }
      local tsvg="$TMPD/vd.$N.svg" o="$TMPD/img.$N.png"
      python3 "$PYH" vd2svg "$spec" "$tsvg" || { echo "❌ No pude convertir el vector XML: $spec (pasa un SVG/PNG del foreground)." >&2; return 1; }
      svg_to_png "$tsvg" "$o" || { echo "❌ No pude rasterizar el vector XML: $spec" >&2; return 1; }
      echo "$o" ;;
    png|jpg|jpeg|webp|heic|heif|tif|tiff|gif|bmp)
      echo "$spec" ;;
    *)
      echo "❌ Tipo de entrada no soportado (.$ext): $spec" >&2; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Detecta si un archivo XML es un adaptive-icon.
# ---------------------------------------------------------------------------
is_adaptive_xml() {
  [[ -f "$1" ]] && grep -q '<adaptive-icon' "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Determina el nombre de salida.
# ---------------------------------------------------------------------------
out_name() {
  if [[ -n "$NAME" ]]; then echo "$NAME"; return; fi
  if [[ -n "$SRC" && -f "$SRC" ]]; then
    local b; b="$(basename "$SRC")"; echo "${b%.*}"; return
  fi
  echo "icon"
}

# ---------------------------------------------------------------------------
# Ejecución
# ---------------------------------------------------------------------------
shopt -s nullglob nocaseglob
mkdir -p "$OUT_DIR"

OUT_FILE="$OUT_DIR/$(out_name).$OUT_EXT"

echo "🎯 Objetivo: ${TARGET}x${TARGET}  |  Formato: $OUT_EXT  |  Modo: $MODE  |  Fondo: ${BG}"
echo "📦 Salida  : $OUT_FILE"
echo "================================================================"

KIND=""       # "single" | "adaptive"
ADAPT_XML=""  # ruta del adaptive-icon xml (si aplica)
SEARCH_ROOT="" # raíz para resolver @drawable/@color

if [[ -n "$FG_SPEC" || -n "$BG_SPEC" ]]; then
  KIND="adaptive"
  # Raíz de búsqueda para posibles @refs de --background.
  if [[ -n "$SRC" && -d "$SRC" ]]; then SEARCH_ROOT="$SRC"; else SEARCH_ROOT="$(pwd)"; fi
elif [[ -n "$SRC" && -f "$SRC" ]] && is_adaptive_xml "$SRC"; then
  KIND="adaptive"; ADAPT_XML="$SRC"; SEARCH_ROOT="$(cd "$(dirname "$SRC")" && pwd)"
elif [[ -n "$SRC" && -d "$SRC" ]]; then
  # Carpeta: busca primero un adaptive-icon.
  found_xml="$(grep -rl -m1 '<adaptive-icon' "$SRC" 2>/dev/null | head -1 || true)"
  if [[ -n "$found_xml" ]]; then
    KIND="adaptive"; ADAPT_XML="$found_xml"; SEARCH_ROOT="$SRC"
    echo "🔎 Adaptive icon detectado: $ADAPT_XML"
  else
    # Elige el mejor recurso suelto: SVG > ic_launcher* > PNG más grande.
    best="$(ls -1 "$SRC"/*.svg 2>/dev/null | head -1 || true)"
    [[ -z "$best" ]] && best="$(ls -1S "$SRC"/ic_launcher*.png "$SRC"/*.png 2>/dev/null | head -1 || true)"
    [[ -z "$best" ]] && best="$(ls -1S "$SRC"/*.jpg "$SRC"/*.jpeg "$SRC"/*.webp 2>/dev/null | head -1 || true)"
    if [[ -z "$best" ]]; then
      echo "❌ No encontré recursos de icono en: $SRC" >&2; exit 1
    fi
    KIND="single"; SRC="$best"
    echo "🔎 Recurso elegido: $SRC"
  fi
else
  KIND="single"
fi

if [[ "$KIND" == "adaptive" ]]; then
  # Resuelve las especificaciones de capa (flags tienen prioridad sobre el XML).
  if [[ -z "$FG_SPEC$BG_SPEC" && -n "$ADAPT_XML" ]]; then
    while IFS= read -r line; do
      case "$line" in
        BG\ *) BG_SPEC="${line#BG }" ;;
        FG\ *) FG_SPEC="${line#FG }" ;;
      esac
    done < <(python3 "$PYH" adaptive "$ADAPT_XML" --root "$SEARCH_ROOT" --tmp "$TMPD")
  fi
  # Un '#hex' con almohadilla de las flags: normaliza NONE.
  [[ -z "$FG_SPEC" ]] && FG_SPEC="NONE"
  [[ -z "$BG_SPEC" ]] && BG_SPEC="NONE"

  echo "🎨 Fondo   : $BG_SPEC"
  echo "🖼  Frente  : $FG_SPEC"

  # Convierte cada capa a algo que render pueda usar (ruta de imagen o #hex).
  BG_RENDER="$(resolve_to_image "$BG_SPEC")" || exit 1
  # Un foreground que sea color sólido -> genera un lienzo sólido.
  if [[ "$FG_SPEC" == "#"* ]]; then
    N=$((N + 1)); FG_RENDER="$TMPD/fg.$N.png"
    python3 "$PYH" solid --color "$FG_SPEC" --out "$FG_RENDER" --size 1024
  else
    FG_RENDER="$(resolve_to_image "$FG_SPEC")" || exit 1
  fi

  RESULT="$(python3 "$PYH" render \
      --bg "$BG_RENDER" --fg "$FG_RENDER" \
      --out "$OUT_FILE" --format "$OUT_EXT" --mode "$MODE" \
      --bgcolor "$BG" --size "$TARGET" --maxbytes "$MAX_BYTES")"
else
  IMG="$(resolve_to_image "$SRC")" || exit 1
  RESULT="$(python3 "$PYH" render \
      --src "$IMG" \
      --out "$OUT_FILE" --format "$OUT_EXT" --mode "$MODE" \
      --bgcolor "$BG" --size "$TARGET" --maxbytes "$MAX_BYTES")"
fi

# RESULT = "512x512 <bytes>"
dims="${RESULT%% *}"; bytes="${RESULT##* }"
human="$(awk -v b="$bytes" 'BEGIN{ if (b<1024) printf "%d B", b; else if (b<1048576) printf "%.0f KB", b/1024; else printf "%.2f MB", b/1048576 }')"
echo "----------------------------------------------------------------"
if (( bytes > MAX_BYTES )); then
  echo "  ⚠️  $dims  $human  (¡supera 1 MB! prueba -f jpg)"
else
  echo "  ✅ $dims  $human"
fi
echo "✅ Icono listo -> $OUT_FILE"
