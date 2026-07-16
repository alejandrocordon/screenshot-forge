"""
Motor de redimensionamiento y recorte de imágenes.

Patrones aplicados
──────────────────
- **Strategy** (implícito): la lógica de scale-to-cover + center-crop está
  encapsulada en ``resize_and_crop``; se podría intercambiar por otra
  estrategia (ej. letterbox) sin afectar al resto del sistema.
- **Observer / Callback**: ``process_batch`` acepta un *callback* opcional
  que notifica el progreso a quien lo invoque (CLI, GUI, tests…).
- **Facade**: ``process_batch`` oculta toda la complejidad de iterar
  archivos, filtrar targets y organizar la salida.

Principios SOLID
────────────────
- **S** – Responsabilidad única: este módulo sólo sabe de imágenes.
- **O** – Abierto/cerrado: nuevos tamaños se añaden en ``sizes.py``;
  este módulo no necesita cambiar.
- **D** – Inversión de dependencias: depende de ``Path`` y callbacks
  genéricos, no de Tkinter ni argparse.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from PIL import Image

from sizes import SUPPORTED_EXTENSIONS, get_targets

logger = logging.getLogger(__name__)

# Tipo del callback de progreso: recibe (mensaje, porcentaje 0-100)
ProgressCallback = Callable[[str, int], None]


@dataclass
class BatchResult:
    """Resumen de un procesamiento batch.

    Atributos:
        processed: cantidad de variantes generadas exitosamente.
        errors: cantidad de imágenes que fallaron.
        paths: rutas absolutas de cada archivo generado.
        error_details: lista de ``(archivo, mensaje_error)``.
    """

    processed: int = 0
    errors: int = 0
    paths: list[str] = field(default_factory=list)
    error_details: list[tuple[str, str]] = field(default_factory=list)


def resize_and_crop(image_path: str | Path, target_size: tuple[int, int]) -> Image.Image:
    """Redimensiona una imagen con *scale-to-cover* y *center-crop*.

    El algoritmo garantiza que la imagen resultante tiene **exactamente**
    las dimensiones de ``target_size``, sin barras negras ni distorsión.

    Args:
        image_path: ruta al archivo de imagen origen.
        target_size: ``(ancho, alto)`` deseado en píxeles.

    Returns:
        Objeto :class:`PIL.Image.Image` con las dimensiones exactas.

    Raises:
        FileNotFoundError: si *image_path* no existe.
        PIL.UnidentifiedImageError: si el archivo no es una imagen válida.
    """
    target_w, target_h = target_size

    img = Image.open(image_path)
    img = img.convert("RGB")  # Normalizar canales (RGBA → RGB, etc.)
    src_w, src_h = img.size

    # --- Scale-to-cover: el ratio mayor garantiza cobertura total ---
    scale = max(target_w / src_w, target_h / src_h)
    new_w = round(src_w * scale)
    new_h = round(src_h * scale)
    img = img.resize((new_w, new_h), Image.LANCZOS)

    # --- Center-crop al tamaño exacto ---
    left = (new_w - target_w) // 2
    top = (new_h - target_h) // 2
    img = img.crop((left, top, left + target_w, top + target_h))

    return img


def _collect_image_files(input_path: Path) -> list[Path]:
    """Recopila archivos de imagen válidos desde un archivo o directorio.

    Si ``input_path`` es un archivo, lo devuelve en una lista (si su
    extensión es soportada). Si es un directorio, recoge todos los
    archivos con extensión soportada en el nivel raíz (no recursivo).
    """
    if input_path.is_file():
        if input_path.suffix.lower() in SUPPORTED_EXTENSIONS:
            return [input_path]
        logger.warning("Extensión no soportada: %s", input_path.name)
        return []

    if input_path.is_dir():
        files = sorted(
            f for f in input_path.iterdir()
            if f.is_file() and f.suffix.lower() in SUPPORTED_EXTENSIONS
        )
        logger.info("Encontrados %d archivos de imagen en %s", len(files), input_path)
        return files

    logger.error("Ruta no válida: %s", input_path)
    return []


def _count_total_operations(
    image_files: list[Path],
    targets: dict[str, dict[str, list[tuple[int, int]]]],
) -> int:
    """Calcula el número total de variantes que se generarán."""
    size_count = sum(
        len(sizes)
        for devices in targets.values()
        for sizes in devices.values()
    )
    return len(image_files) * size_count


def process_batch(
    input_path: str | Path,
    output_base: str | Path,
    platform: str | None = None,
    device: str | None = None,
    quality: int = 6,
    on_progress: ProgressCallback | None = None,
) -> BatchResult:
    """Procesa un lote de imágenes contra todos los tamaños objetivo.

    Args:
        input_path: archivo o carpeta con screenshots de origen.
        output_base: carpeta raíz de salida.
        platform: ``"ios"``, ``"android"`` o ``None``/``"all"`` para ambas.
        device: nombre del dispositivo o ``None`` para todos.
        quality: compresión PNG (0 = sin compresión, 9 = máxima). Default 6.
        on_progress: callback ``(mensaje, porcentaje)`` para reportar avance.

    Returns:
        :class:`BatchResult` con el resumen de la operación.
    """
    input_path = Path(input_path)
    output_base = Path(output_base)
    result = BatchResult()

    # --- Resolver targets ---
    targets = get_targets(platform, device)

    # --- Recopilar archivos ---
    image_files = _collect_image_files(input_path)
    if not image_files:
        msg = f"No se encontraron imágenes en: {input_path}"
        logger.warning(msg)
        if on_progress:
            on_progress(msg, 100)
        return result

    total_ops = _count_total_operations(image_files, targets)
    current_op = 0

    # --- Iterar: archivo × plataforma × dispositivo × tamaño ---
    for img_file in image_files:
        stem = img_file.stem  # nombre sin extensión

        for plat_name, devices in targets.items():
            for dev_name, sizes in devices.items():
                for target_size in sizes:
                    current_op += 1
                    w, h = target_size
                    out_dir = output_base / plat_name / dev_name
                    out_file = out_dir / f"{stem}_{w}x{h}.png"

                    try:
                        out_dir.mkdir(parents=True, exist_ok=True)
                        img = resize_and_crop(img_file, target_size)
                        img.save(str(out_file), "PNG", compress_level=quality)

                        result.processed += 1
                        result.paths.append(str(out_file))

                        msg = f"[OK] {out_file.relative_to(output_base)}"
                        logger.info(msg)

                    except Exception as exc:
                        result.errors += 1
                        result.error_details.append((str(img_file), str(exc)))

                        msg = f"[ERROR] {img_file.name} → {w}x{h}: {exc}"
                        logger.error(msg)

                    # Notificar progreso
                    if on_progress:
                        pct = round(current_op / total_ops * 100)
                        on_progress(msg, pct)

    return result
