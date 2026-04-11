# Screenshot Forge — Arquitectura y Documentación Técnica

## Tabla de contenidos

1. [Vista general](#vista-general)
2. [Diagrama de componentes](#diagrama-de-componentes)
3. [Flujo de datos](#flujo-de-datos)
4. [Principios SOLID aplicados](#principios-solid-aplicados)
5. [Patrones de diseño](#patrones-de-diseño)
6. [Módulos en detalle](#módulos-en-detalle)
7. [Guía de uso — CLI](#guía-de-uso--cli)
8. [Guía de uso — GUI](#guía-de-uso--gui)
9. [Testing](#testing)
10. [Extender el proyecto](#extender-el-proyecto)

---

## Vista general

Screenshot Forge es una herramienta Python que redimensiona screenshots
a los tamaños oficiales de **Apple App Store** y **Google Play Store**.

```
┌──────────────────────────────────────────────────┐
│                Screenshot Forge                   │
│                                                   │
│   Entrada:  imagen.png  o  carpeta/              │
│   Salida:   output/ios/6.7inch/img_1290x2796.png │
│                                                   │
│   Interfaces:  CLI (forge.py)                     │
│                GUI (forge_gui.py)                  │
└──────────────────────────────────────────────────┘
```

---

## Diagrama de componentes

```
┌─────────────────────────────────────────────────────────┐
│                      PRESENTACIÓN                        │
│                                                          │
│   ┌──────────────┐         ┌──────────────────┐         │
│   │   forge.py   │         │   forge_gui.py   │         │
│   │   (CLI)      │         │   (GUI Tkinter)  │         │
│   │   argparse   │         │   ttk + thread   │         │
│   └──────┬───────┘         └────────┬─────────┘         │
│          │                          │                    │
│          │   on_progress callback   │                    │
│          └──────────┬───────────────┘                    │
│                     │                                    │
├─────────────────────┼────────────────────────────────────┤
│                     ▼          LÓGICA DE NEGOCIO         │
│          ┌──────────────────┐                            │
│          │   resizer.py     │                            │
│          │                  │                            │
│          │ resize_and_crop()│◄── Strategy (scale-to-     │
│          │ process_batch()  │    cover + center-crop)    │
│          │ BatchResult      │                            │
│          └────────┬─────────┘                            │
│                   │                                      │
├───────────────────┼──────────────────────────────────────┤
│                   ▼            DATOS / CONFIGURACIÓN     │
│          ┌──────────────────┐                            │
│          │   sizes.py       │                            │
│          │                  │                            │
│          │ TARGETS (dict)   │◄── Registry (tamaños      │
│          │ get_targets()    │    oficiales iOS/Android)  │
│          └──────────────────┘                            │
│                                                          │
├──────────────────────────────────────────────────────────┤
│                    DEPENDENCIAS EXTERNAS                  │
│          ┌──────────────────┐                            │
│          │     Pillow       │                            │
│          │  (PIL.Image)     │                            │
│          └──────────────────┘                            │
└──────────────────────────────────────────────────────────┘
```

---

## Flujo de datos

```
                    ┌─────────┐
                    │ Usuario │
                    └────┬────┘
                         │
                    elige interfaz
                         │
              ┌──────────┴──────────┐
              ▼                     ▼
       ┌────────────┐       ┌─────────────┐
       │  forge.py  │       │forge_gui.py │
       │  (CLI)     │       │  (GUI)      │
       └─────┬──────┘       └──────┬──────┘
             │                     │
             │  Ambos invocan      │
             └──────────┬──────────┘
                        ▼
              ┌───────────────────┐
              │  process_batch()  │
              │  (resizer.py)     │
              └────────┬──────────┘
                       │
          ┌────────────┼─────────────┐
          ▼            ▼             ▼
   ┌────────────┐ ┌─────────┐ ┌──────────┐
   │ get_targets│ │ collect  │ │ resize   │
   │ (sizes.py) │ │ files   │ │ & crop   │
   └────────────┘ └─────────┘ └────┬─────┘
                                   │
                                   ▼
                           ┌──────────────┐
                           │  Pillow      │
                           │ Image.resize │
                           │ Image.crop   │
                           └──────┬───────┘
                                  │
                                  ▼
                        ┌───────────────────┐
                        │  output/          │
                        │  ├── ios/         │
                        │  │   ├── 6.7inch/ │
                        │  │   ├── 6.5inch/ │
                        │  │   └── ...      │
                        │  └── android/     │
                        │      ├── phone/   │
                        │      └── ...      │
                        └───────────────────┘
```

---

## Principios SOLID aplicados

### S — Single Responsibility (Responsabilidad Única)

```
┌──────────────┬────────────────────────────────────┐
│    Módulo    │         Responsabilidad             │
├──────────────┼────────────────────────────────────┤
│  sizes.py    │  Definir tamaños oficiales          │
│  resizer.py  │  Procesar imágenes                  │
│  forge.py    │  Interfaz CLI                       │
│  forge_gui.py│  Interfaz GUI                       │
└──────────────┴────────────────────────────────────┘
```

Cada módulo tiene **una sola razón para cambiar**. Si Apple añade
un nuevo tamaño de iPhone, sólo se toca `sizes.py`. Si se quiere
una interfaz web, se crea un nuevo archivo sin modificar el motor.

### O — Open/Closed (Abierto/Cerrado)

```
  sizes.py (TARGETS)
  ┌──────────────────────────┐
  │ "ios": {                 │
  │   "6.7inch": [...],      │
  │   "6.5inch": [...],      │     ← Agregar aquí
  │   "NEW_DEVICE": [...],   │     ← sin tocar resizer.py
  │ }                        │
  └──────────────────────────┘

  resizer.py
  ┌──────────────────────────┐
  │ for plat, devices in     │
  │     targets.items():     │  ← Itera lo que recibe;
  │   for dev, sizes in ...  │     no le importa cuántos hay
  └──────────────────────────┘
```

### L — Liskov Substitution (Sustitución de Liskov)

El callback `on_progress` acepta cualquier callable con firma
`(str, int) -> None`. Tanto CLI como GUI pasan su propia
implementación sin que `resizer.py` necesite saber cuál es.

### I — Interface Segregation (Segregación de Interfaces)

```
  resizer.py expone exactamente lo necesario:

  ┌─ Para usuarios simples ──────────────────┐
  │  resize_and_crop(path, size) → Image     │
  └──────────────────────────────────────────┘

  ┌─ Para procesamiento batch ───────────────┐
  │  process_batch(input, output, ...) → Res │
  └──────────────────────────────────────────┘
```

No fuerza a nadie a usar la interfaz batch si sólo necesita
redimensionar una imagen.

### D — Dependency Inversion (Inversión de Dependencias)

```
  ┌───────────────┐        ┌───────────────┐
  │  forge.py     │───────►│  resizer.py   │
  │  forge_gui.py │───────►│  (abstracción)│
  └───────────────┘        └───────┬───────┘
                                   │
                                   ▼
                           ┌───────────────┐
                           │   sizes.py    │
                           │   Pillow      │
                           └───────────────┘

  Las interfaces (CLI/GUI) dependen de resizer.py,
  nunca al revés. resizer.py no importa ni tkinter ni argparse.
```

---

## Patrones de diseño

### 1. Registry (sizes.py)

```
  TARGETS = {
      "ios":     { device: [sizes...], ... },
      "android": { device: [sizes...], ... },
  }
        │
        ▼
  get_targets(platform?, device?)
        │
        ▼
  sub-diccionario filtrado
```

Un punto centralizado que actúa como **fuente de verdad** para
todas las dimensiones. Cualquier módulo consulta `get_targets()`
sin conocer la estructura interna.

### 2. Strategy (resizer.py)

```
  ┌─────────────────────────────┐
  │  resize_and_crop()          │
  │                             │
  │  1. Abrir imagen            │
  │  2. Calcular scale-to-cover │
  │  3. Resize con LANCZOS      │
  │  4. Center-crop             │
  │  5. Retornar resultado      │
  └─────────────────────────────┘
```

La estrategia de redimensionamiento está encapsulada. Si mañana
se necesita una estrategia de *letterbox* o *fit-inside*, se puede
crear una función alternativa sin tocar el resto.

### 3. Observer / Callback (resizer.py → GUI/CLI)

```
  resizer.py                     forge_gui.py
  ┌──────────────┐              ┌──────────────┐
  │              │  on_progress │              │
  │ process_batch├─────────────►│ _on_progress │
  │              │  (msg, %)    │              │
  │              │              │ → log_text   │
  │              │              │ → progressbar│
  └──────────────┘              └──────────────┘
```

El motor **no sabe** quién lo escucha. Simplemente invoca el
callback si existe. La GUI actualiza su barra de progreso y log;
la CLI podría imprimir puntos; los tests verifican las llamadas.

### 4. Facade (process_batch)

```
  ┌──────────────────────────────────────────┐
  │            process_batch()               │
  │                                          │
  │  ┌──────────┐  ┌───────────┐  ┌───────┐ │
  │  │get_targets│  │collect    │  │resize │ │
  │  │          │  │files     │  │& crop │ │
  │  └──────────┘  └───────────┘  │& save │ │
  │                               └───────┘ │
  │  → mkdir, iterar, manejar errores,      │
  │    notificar progreso, generar resumen   │
  └──────────────────────────────────────────┘
```

Una sola llamada orquesta: lectura de targets, recopilación de
archivos, creación de carpetas, resize, guardado y reporte.

---

## Módulos en detalle

### `sizes.py`

| Elemento             | Tipo                                  | Descripción                        |
|----------------------|---------------------------------------|------------------------------------|
| `TARGETS`            | `dict[str, dict[str, list[tuple]]]`   | Todos los tamaños por plataforma   |
| `SUPPORTED_EXTENSIONS`| `set[str]`                           | `.png`, `.jpg`, `.jpeg`            |
| `get_targets()`      | `function`                            | Filtra por plataforma y/o device   |

### `resizer.py`

| Elemento             | Tipo          | Descripción                              |
|----------------------|---------------|------------------------------------------|
| `BatchResult`        | `dataclass`   | Resumen: processed, errors, paths, etc.  |
| `resize_and_crop()`  | `function`    | Scale-to-cover + center-crop una imagen  |
| `process_batch()`    | `function`    | Procesa lote completo con callbacks      |

### `forge.py`

| Elemento        | Tipo       | Descripción                    |
|-----------------|------------|--------------------------------|
| `main()`        | `function` | Entry point CLI                |
| `_build_parser()`| `function`| Configura argparse             |

### `forge_gui.py`

| Elemento        | Tipo    | Descripción                         |
|-----------------|---------|-------------------------------------|
| `ForgeApp`      | `class` | Frame principal, hereda de ttk.Frame|
| `main()`        | `function` | Lanza la ventana Tk              |

---

## Guía de uso — CLI

### Instalación

```bash
git clone https://github.com/AlejandroCordon/screenshot-forge.git
cd screenshot-forge
pip install -r requirements.txt
```

### Comandos

```bash
# Todas las plataformas, todos los dispositivos
python forge.py -i ./screenshots -o ./output

# Solo iOS
python forge.py -i ./screenshots -p ios

# Solo Android phones
python forge.py -i ./screenshots -p android -d phone

# Un solo archivo, compresión máxima
python forge.py -i captura.png -o ./out -q 9

# Ayuda completa
python forge.py --help
```

### Argumentos

| Flag               | Requerido | Default    | Descripción                      |
|--------------------|-----------|------------|----------------------------------|
| `-i` / `--input`   | Si        | —          | Archivo o carpeta de entrada     |
| `-o` / `--output`  | No        | `./output` | Carpeta de salida                |
| `-p` / `--platform`| No        | `all`      | `ios`, `android`, o `all`        |
| `-d` / `--device`  | No        | todos      | Device específico                |
| `-q` / `--quality` | No        | `6`        | Compresión PNG (0-9)             |

### Ejemplo de salida

```
Screenshot Forge
────────────────────────────────────
  Input:      ./screenshots
  Output:     ./output
  Plataforma: all
  Dispositivo: todos
  Compresión: 6
────────────────────────────────────

════════════════════════════════════
  Generadas:  36
  Errores:    0
  Carpetas:
    → output/ios/6.7inch
    → output/ios/6.5inch
    → output/android/phone
    → ...
════════════════════════════════════
```

---

## Guía de uso — GUI

```bash
python forge_gui.py
```

```
┌─ Screenshot Forge ──────────────────────────────────────┐
│                                                          │
│  ┌─ Rutas ────────────────────────────────────────────┐  │
│  │ Input:  [/Users/.../screenshots    ] [Browse…]     │  │
│  │ Output: [/Users/.../output         ] [Browse…]     │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌─ Plataformas y dispositivos ───────────────────────┐  │
│  │ IOS     ☑ 6.7inch ☑ 6.5inch ☑ 5.5inch ☑ ipad     │  │
│  │ ANDROID ☑ phone ☑ 7inch_tablet ☑ 10inch ☑ chrome  │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  [Forge] [Open Output Folder]  [████████████████ 100%]   │
│                                                          │
│  ┌─ Log ──────────────────────────────────────────────┐  │
│  │ [OK] ios/6.7inch/home_1290x2796.png                │  │
│  │ [OK] ios/6.7inch/home_2796x1290.png                │  │
│  │ [OK] ios/6.5inch/home_1242x2688.png                │  │
│  │ ...                                                │  │
│  │ Completado: 36 generadas, 0 errores.               │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

### Flujo

1. **Browse** la carpeta con screenshots
2. **Seleccionar** plataformas y devices (todos activos por defecto)
3. **Click en Forge** — el procesamiento corre en background
4. **Observar** el progreso en el log y la barra
5. **Open Output Folder** para ver los resultados

---

## Testing

```bash
pip install pytest
pytest test_resizer.py -v
```

### Matriz de tests

```
┌──────────────────────────────┬──────────────────────────────┐
│         Test                 │       Qué verifica           │
├──────────────────────────────┼──────────────────────────────┤
│ test_exact_dimensions_*      │ Salida = tamaño target exacto│
│ test_all_common_sizes        │ Todos los tamaños de tiendas │
│ test_rgba_image_converted    │ RGBA → RGB sin errores       │
│ test_single_file_creates_*   │ Un archivo → todas variantes │
│ test_directory_processes_*   │ Carpeta → batch completo     │
│ test_platform_filter         │ Filtro por iOS/Android       │
│ test_device_filter           │ Filtro por device            │
│ test_correct_folder_structure│ Carpetas platform/device     │
│ test_output_filename_format  │ nombre_WxH.png               │
│ test_non_image_files_ignored │ .txt, .csv se saltan         │
│ test_corrupt_image_no_crash  │ Imagen rota no para el batch │
│ test_empty_directory         │ Dir vacío → resultado vacío  │
│ test_progress_callback       │ Callback recibe 0-100%       │
└──────────────────────────────┴──────────────────────────────┘
```

---

## Extender el proyecto

### Agregar un nuevo tamaño de dispositivo

Solo edita `sizes.py`:

```python
TARGETS = {
    "ios": {
        # ... existentes ...
        "6.1inch": [(1170, 2532), (2532, 1170)],  # ← nuevo
    },
}
```

**Ningún otro archivo necesita cambiar.** (Open/Closed Principle)

### Agregar una nueva estrategia de resize

Crea una nueva función en `resizer.py` con la misma firma:

```python
def letterbox(image_path, target_size) -> Image:
    ...
```

### Agregar una nueva interfaz (ej. web)

Crea un nuevo archivo (ej. `forge_web.py`) que importe
`process_batch` de `resizer.py`. El motor no necesita cambios.
