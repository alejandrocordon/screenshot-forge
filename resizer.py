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
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from PIL import Image

from sizes import (
    SUPPORTED_EXTENSIONS,
    SUPPORTED_VIDEO_EXTENSIONS,
    get_targets,
)

logger = logging.getLogger(__name__)

# Tipo del callback de progreso: recibe (mensaje, porcentaje 0-100)
ProgressCallback = Callable[[str, int], None]

# Calidad de codificación de video (CRF de libx264: menor = mejor calidad).
# 18-23 es el rango "visualmente sin pérdidas"; 20 es un buen compromiso.
_VIDEO_CRF = 20


class FFmpegNotFoundError(RuntimeError):
    """Se lanza cuando se necesita ffmpeg para recortar un video y no existe."""


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


def ffmpeg_available() -> bool:
    """Indica si el binario ``ffmpeg`` está disponible en el ``PATH``."""
    return shutil.which("ffmpeg") is not None


def resize_and_crop_video(
    video_path: str | Path,
    target_size: tuple[int, int],
    output_path: str | Path,
    crf: int = _VIDEO_CRF,
) -> Path:
    """Recorta un video con *scale-to-cover* y *center-crop* vía ffmpeg.

    Aplica exactamente la misma estrategia que :func:`resize_and_crop` pero
    sobre un video: escala el material para cubrir por completo
    ``target_size`` y luego recorta al centro hasta las dimensiones exactas,
    sin barras negras ni distorsión. El audio (si existe) se recodifica a AAC
    para máxima compatibilidad con la App Store.

    Args:
        video_path: ruta al video de origen.
        target_size: ``(ancho, alto)`` deseado en píxeles.
        output_path: ruta del archivo ``.mp4`` de salida.
        crf: calidad de libx264 (menor = mejor). Default :data:`_VIDEO_CRF`.

    Returns:
        La ruta del video generado (:class:`Path`).

    Raises:
        FFmpegNotFoundError: si ``ffmpeg`` no está instalado.
        RuntimeError: si ffmpeg falla al procesar el video.
    """
    if not ffmpeg_available():
        raise FFmpegNotFoundError(
            "ffmpeg no está instalado o no está en el PATH; es necesario "
            "para recortar videos. Instálalo desde https://ffmpeg.org."
        )

    target_w, target_h = target_size
    output_path = Path(output_path)

    # scale ...:force_original_aspect_ratio=increase → escala para *cubrir*
    # (equivale al max(ratio) de resize_and_crop). crop centra por defecto.
    vf = (
        f"scale={target_w}:{target_h}:force_original_aspect_ratio=increase,"
        f"crop={target_w}:{target_h}"
    )

    cmd = [
        "ffmpeg",
        "-y",                       # sobrescribir salida sin preguntar
        "-i", str(video_path),
        "-vf", vf,
        "-c:v", "libx264",
        "-preset", "veryfast",
        "-crf", str(crf),
        "-pix_fmt", "yuv420p",      # compatibilidad amplia de reproductores
        "-c:a", "aac",              # recodificar audio (o ninguno si no hay)
        "-movflags", "+faststart",  # metadata al inicio → streaming
        str(output_path),
    ]

    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        # Quedarnos con la última línea de stderr suele bastar para el usuario.
        detail = ""
        if proc.stderr:
            lines = [ln for ln in proc.stderr.splitlines() if ln.strip()]
            detail = lines[-1] if lines else ""
        raise RuntimeError(f"ffmpeg falló: {detail}" if detail else "ffmpeg falló")

    return output_path


def _collect_image_files(input_path: Path) -> list[Path]:
    """Recopila archivos de imagen válidos desde un archivo o directorio.

    Si ``input_path`` es un archivo, lo devuelve en una lista (si su
    extensión es soportada). Si es un directorio, recoge todos los
    archivos con extensión soportada en el nivel raíz (no recursivo).
    """
    if input_path.is_file():
        suffix = input_path.suffix.lower()
        if suffix in SUPPORTED_EXTENSIONS:
            return [input_path]
        # No avisar si es un video: lo recogerá _collect_video_files.
        if suffix not in SUPPORTED_VIDEO_EXTENSIONS:
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


def _collect_video_files(input_path: Path) -> list[Path]:
    """Recopila archivos de video válidos desde un archivo o directorio.

    Misma lógica que :func:`_collect_image_files` pero filtrando por
    :data:`sizes.SUPPORTED_VIDEO_EXTENSIONS`.
    """
    if input_path.is_file():
        if input_path.suffix.lower() in SUPPORTED_VIDEO_EXTENSIONS:
            return [input_path]
        return []

    if input_path.is_dir():
        files = sorted(
            f for f in input_path.iterdir()
            if f.is_file() and f.suffix.lower() in SUPPORTED_VIDEO_EXTENSIONS
        )
        if files:
            logger.info("Encontrados %d videos en %s", len(files), input_path)
        return files

    return []


def _count_size_variants(
    targets: dict[str, dict[str, list[tuple[int, int]]]],
) -> int:
    """Cuenta cuántas variantes de tamaño hay en un árbol de targets."""
    return sum(
        len(sizes)
        for devices in targets.values()
        for sizes in devices.values()
    )


def _count_total_operations(
    image_files: list[Path],
    targets: dict[str, dict[str, list[tuple[int, int]]]],
) -> int:
    """Calcula el número total de variantes que se generarán."""
    return len(image_files) * _count_size_variants(targets)


def process_batch(
    input_path: str | Path,
    output_base: str | Path,
    platform: str | None = None,
    device: str | None = None,
    quality: int = 6,
    on_progress: ProgressCallback | None = None,
) -> BatchResult:
    """Procesa un lote de imágenes (y videos) contra los tamaños objetivo.

    Las **imágenes** se recortan a todos los targets resueltos. Los **videos**
    sólo se recortan a los tamaños de **Apple/iOS** (los App Preview de la
    App Store); si no hay targets iOS seleccionados, los videos se ignoran.
    El recorte de video requiere ``ffmpeg`` instalado.

    Args:
        input_path: archivo o carpeta con screenshots/videos de origen.
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
    video_files = _collect_video_files(input_path)

    if not image_files and not video_files:
        msg = f"No se encontraron imágenes ni videos en: {input_path}"
        logger.warning(msg)
        if on_progress:
            on_progress(msg, 100)
        return result

    # --- Plan de video: sólo se recorta al "crop de Apple" (iOS) ---
    ios_targets = {"ios": targets["ios"]} if "ios" in targets else {}
    have_ffmpeg = ffmpeg_available()
    process_videos = bool(video_files) and bool(ios_targets) and have_ffmpeg

    if video_files and not ios_targets:
        logger.info(
            "Se encontraron %d video(s) pero no hay targets de Apple/iOS "
            "seleccionados; los videos se omiten.", len(video_files),
        )
    if video_files and ios_targets and not have_ffmpeg:
        for vid in video_files:
            result.errors += 1
            result.error_details.append(
                (str(vid), "ffmpeg no está disponible; instálalo para "
                           "recortar videos."),
            )
            logger.error(
                "ffmpeg no disponible; no se puede recortar el video %s",
                vid.name,
            )

    # --- Contar operaciones totales para el progreso ---
    total_ops = _count_total_operations(image_files, targets)
    if process_videos:
        total_ops += len(video_files) * _count_size_variants(ios_targets)
    current_op = 0

    def _notify(message: str) -> None:
        if on_progress:
            pct = round(current_op / total_ops * 100) if total_ops else 100
            on_progress(message, pct)

    # --- Imágenes: archivo × plataforma × dispositivo × tamaño ---
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

                    _notify(msg)

    # --- Videos: sólo contra los targets de Apple/iOS ---
    if process_videos:
        for vid_file in video_files:
            stem = vid_file.stem

            for plat_name, devices in ios_targets.items():
                for dev_name, sizes in devices.items():
                    for target_size in sizes:
                        current_op += 1
                        w, h = target_size
                        out_dir = output_base / plat_name / dev_name
                        out_file = out_dir / f"{stem}_{w}x{h}.mp4"

                        try:
                            out_dir.mkdir(parents=True, exist_ok=True)
                            resize_and_crop_video(
                                vid_file, target_size, out_file,
                            )

                            result.processed += 1
                            result.paths.append(str(out_file))

                            msg = f"[OK] {out_file.relative_to(output_base)}"
                            logger.info(msg)

                        except Exception as exc:
                            result.errors += 1
                            result.error_details.append(
                                (str(vid_file), str(exc)),
                            )

                            msg = f"[ERROR] {vid_file.name} → {w}x{h}: {exc}"
                            logger.error(msg)

                        _notify(msg)

    # Si no había ninguna operación (p. ej. sólo videos y falta ffmpeg), los
    # bucles no notificaron progreso: enviar un ping final al 100%.
    if on_progress and total_ops == 0:
        on_progress("Completado.", 100)

    return result
