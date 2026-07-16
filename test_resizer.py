"""
Tests para el motor de redimensionamiento.

Ejecutar::

    pip install pytest
    pytest test_resizer.py -v
"""

from __future__ import annotations

import os
import types
from pathlib import Path

import pytest
from PIL import Image

import resizer
from resizer import (
    BatchResult,
    FFmpegNotFoundError,
    _collect_video_files,
    process_batch,
    resize_and_crop,
    resize_and_crop_video,
)
from sizes import SUPPORTED_VIDEO_EXTENSIONS, TARGETS


# ── Fixtures ─────────────────────────────────────────────────────────

@pytest.fixture
def sample_image(tmp_path: Path) -> Path:
    """Crea una imagen sintética de 800x600 para las pruebas."""
    img = Image.new("RGB", (800, 600), color=(100, 150, 200))
    path = tmp_path / "sample.png"
    img.save(str(path))
    return path


@pytest.fixture
def sample_dir(tmp_path: Path) -> Path:
    """Crea un directorio con varias imágenes sintéticas."""
    img_dir = tmp_path / "screenshots"
    img_dir.mkdir()

    for name, color in [("home", (255, 0, 0)), ("settings", (0, 255, 0))]:
        img = Image.new("RGB", (1080, 1920), color=color)
        img.save(str(img_dir / f"{name}.png"))

    return img_dir


# ── Tests de resize_and_crop ─────────────────────────────────────────

class TestResizeAndCrop:
    """Verifica que resize_and_crop genera las dimensiones exactas."""

    def test_exact_dimensions_portrait(self, sample_image: Path) -> None:
        """El resultado debe tener exactamente el tamaño target (portrait)."""
        target = (1080, 1920)
        result = resize_and_crop(sample_image, target)
        assert result.size == target

    def test_exact_dimensions_landscape(self, sample_image: Path) -> None:
        """El resultado debe tener exactamente el tamaño target (landscape)."""
        target = (2688, 1242)
        result = resize_and_crop(sample_image, target)
        assert result.size == target

    def test_exact_dimensions_square(self, tmp_path: Path) -> None:
        """Funciona con imágenes y targets cuadrados."""
        img = Image.new("RGB", (500, 500), color=(50, 50, 50))
        path = tmp_path / "square.png"
        img.save(str(path))

        target = (1024, 1024)
        result = resize_and_crop(path, target)
        assert result.size == target

    @pytest.mark.parametrize("target", [
        (1290, 2796),
        (1242, 2688),
        (2048, 2732),
        (1080, 1920),
        (1920, 1080),
    ])
    def test_all_common_sizes(self, sample_image: Path, target: tuple[int, int]) -> None:
        """Verifica varias dimensiones reales de las tiendas."""
        result = resize_and_crop(sample_image, target)
        assert result.size == target

    def test_rgba_image_converted(self, tmp_path: Path) -> None:
        """Las imágenes RGBA se convierten correctamente a RGB."""
        img = Image.new("RGBA", (640, 480), color=(255, 0, 0, 128))
        path = tmp_path / "rgba.png"
        img.save(str(path))

        result = resize_and_crop(path, (1080, 1920))
        assert result.mode == "RGB"
        assert result.size == (1080, 1920)


# ── Tests de process_batch ───────────────────────────────────────────

class TestProcessBatch:
    """Verifica el procesamiento batch completo."""

    def test_single_file_creates_all_sizes(
        self, sample_image: Path, tmp_path: Path,
    ) -> None:
        """Un solo archivo genera variantes para todos los targets."""
        output_dir = tmp_path / "output"
        result = process_batch(sample_image, output_dir)

        assert result.processed > 0
        assert result.errors == 0
        # Verificar que se crearon archivos
        generated = list(output_dir.rglob("*.png"))
        assert len(generated) == result.processed

    def test_directory_processes_all_images(
        self, sample_dir: Path, tmp_path: Path,
    ) -> None:
        """Procesar un directorio genera variantes para cada imagen."""
        output_dir = tmp_path / "output"
        result = process_batch(sample_dir, output_dir)

        # 2 imágenes × total de tamaños
        total_sizes = sum(
            len(s) for d in TARGETS.values() for s in d.values()
        )
        assert result.processed == 2 * total_sizes
        assert result.errors == 0

    def test_platform_filter(
        self, sample_image: Path, tmp_path: Path,
    ) -> None:
        """Filtrar por plataforma solo genera archivos de esa plataforma."""
        output_dir = tmp_path / "output"
        result = process_batch(sample_image, output_dir, platform="ios")

        # Solo debe haber carpeta ios, no android
        assert (output_dir / "ios").exists()
        assert not (output_dir / "android").exists()
        assert result.processed > 0

    def test_device_filter(
        self, sample_image: Path, tmp_path: Path,
    ) -> None:
        """Filtrar por dispositivo solo genera los tamaños de ese device."""
        output_dir = tmp_path / "output"
        result = process_batch(
            sample_image, output_dir, platform="android", device="phone",
        )

        # phone tiene 2 tamaños: portrait + landscape
        assert result.processed == 2
        assert (output_dir / "android" / "phone").exists()

    def test_correct_folder_structure(
        self, sample_image: Path, tmp_path: Path,
    ) -> None:
        """Verifica que se crean las carpetas platform/device correctas."""
        output_dir = tmp_path / "output"
        process_batch(sample_image, output_dir)

        for plat, devices in TARGETS.items():
            for dev in devices:
                assert (output_dir / plat / dev).is_dir(), (
                    f"Falta carpeta: {plat}/{dev}"
                )

    def test_output_filename_format(
        self, sample_image: Path, tmp_path: Path,
    ) -> None:
        """Los archivos de salida siguen el formato nombre_WxH.png."""
        output_dir = tmp_path / "output"
        process_batch(
            sample_image, output_dir, platform="android", device="phone",
        )

        phone_dir = output_dir / "android" / "phone"
        files = sorted(f.name for f in phone_dir.iterdir())
        assert "sample_1080x1920.png" in files
        assert "sample_1920x1080.png" in files


# ── Tests de robustez ────────────────────────────────────────────────

class TestRobustness:
    """Verifica que el sistema es resiliente ante errores."""

    def test_non_image_files_ignored(self, tmp_path: Path) -> None:
        """Archivos que no son imágenes se ignoran sin crashear."""
        input_dir = tmp_path / "mixed"
        input_dir.mkdir()

        # Crear archivo de texto que NO es imagen
        (input_dir / "readme.txt").write_text("no soy imagen")
        (input_dir / "data.csv").write_text("a,b,c\n1,2,3")

        # Crear una imagen válida
        img = Image.new("RGB", (100, 100), color=(0, 0, 0))
        img.save(str(input_dir / "valid.png"))

        output_dir = tmp_path / "output"
        result = process_batch(input_dir, output_dir)

        # Solo la imagen válida se procesa
        assert result.processed > 0
        assert result.errors == 0

    def test_corrupt_image_does_not_crash(self, tmp_path: Path) -> None:
        """Una imagen corrupta no detiene el procesamiento batch."""
        input_dir = tmp_path / "corrupt"
        input_dir.mkdir()

        # Archivo con extensión .png pero contenido basura
        corrupt = input_dir / "broken.png"
        corrupt.write_bytes(b"esto no es una imagen PNG valida")

        # Imagen válida
        img = Image.new("RGB", (200, 200), color=(128, 128, 128))
        img.save(str(input_dir / "good.png"))

        output_dir = tmp_path / "output"
        result = process_batch(input_dir, output_dir)

        # La imagen válida se procesó; la corrupta generó errores
        assert result.processed > 0
        assert result.errors > 0
        assert len(result.error_details) > 0

    def test_empty_directory(self, tmp_path: Path) -> None:
        """Un directorio vacío retorna resultado vacío sin crashear."""
        empty_dir = tmp_path / "empty"
        empty_dir.mkdir()

        output_dir = tmp_path / "output"
        result = process_batch(empty_dir, output_dir)

        assert result.processed == 0
        assert result.errors == 0

    def test_nonexistent_input_path(self, tmp_path: Path) -> None:
        """Una ruta inexistente retorna resultado vacío."""
        output_dir = tmp_path / "output"
        result = process_batch(tmp_path / "no_existe", output_dir)

        assert result.processed == 0

    def test_progress_callback_receives_updates(
        self, sample_image: Path, tmp_path: Path,
    ) -> None:
        """El callback de progreso recibe llamadas con porcentaje 0-100."""
        messages: list[tuple[str, int]] = []

        def on_progress(msg: str, pct: int) -> None:
            messages.append((msg, pct))

        output_dir = tmp_path / "output"
        process_batch(
            sample_image, output_dir,
            platform="android", device="chromebook",
            on_progress=on_progress,
        )

        assert len(messages) > 0
        # El último mensaje debe tener 100%
        assert messages[-1][1] == 100


# ── Test de batch result ─────────────────────────────────────────────

class TestBatchResult:
    """Verifica la estructura del dataclass BatchResult."""

    def test_default_values(self) -> None:
        """Los valores por defecto son cero/vacío."""
        result = BatchResult()
        assert result.processed == 0
        assert result.errors == 0
        assert result.paths == []
        assert result.error_details == []


# ── Helpers de video ─────────────────────────────────────────────────

def _fake_ffmpeg_success(created: list[str] | None = None):
    """Devuelve un fake de ``subprocess.run`` que "genera" el archivo salida."""
    calls: list[list[str]] = []

    def fake_run(cmd, capture_output=True, text=True):  # noqa: ANN001
        calls.append(cmd)
        Path(cmd[-1]).write_bytes(b"fake mp4 bytes")
        if created is not None:
            created.append(cmd[-1])
        return types.SimpleNamespace(returncode=0, stderr="")

    fake_run.calls = calls  # type: ignore[attr-defined]
    return fake_run


@pytest.fixture
def sample_video(tmp_path: Path) -> Path:
    """Crea un archivo con extensión de video (contenido irrelevante)."""
    path = tmp_path / "demo.mp4"
    path.write_bytes(b"\x00\x00\x00\x18ftypmp42 not a real video")
    return path


# ── Tests de recopilación de videos ──────────────────────────────────

class TestVideoCollection:
    """Verifica la detección de archivos de video."""

    def test_collects_all_video_extensions(self, tmp_path: Path) -> None:
        """Sólo se recogen .mp4/.mov/.m4v, ignorando otros archivos."""
        d = tmp_path / "in"
        d.mkdir()
        for name in ["a.mp4", "b.mov", "c.m4v", "d.png", "notes.txt"]:
            (d / name).write_bytes(b"x")

        vids = _collect_video_files(d)
        assert {v.name for v in vids} == {"a.mp4", "b.mov", "c.m4v"}

    def test_single_video_file(self, sample_video: Path) -> None:
        """Un archivo de video suelto se devuelve en una lista."""
        assert _collect_video_files(sample_video) == [sample_video]

    def test_single_non_video_file(self, tmp_path: Path) -> None:
        """Un archivo que no es video devuelve lista vacía."""
        p = tmp_path / "shot.png"
        p.write_bytes(b"x")
        assert _collect_video_files(p) == []

    def test_supported_extensions_constant(self) -> None:
        """Las extensiones esperadas están registradas."""
        assert {".mp4", ".mov", ".m4v"} <= SUPPORTED_VIDEO_EXTENSIONS


# ── Tests de recorte de video (sin ffmpeg) ───────────────────────────

class TestVideoWithoutFfmpeg:
    """Comportamiento cuando ffmpeg no está disponible."""

    def test_resize_video_raises_without_ffmpeg(
        self, sample_video: Path, tmp_path: Path, monkeypatch,
    ) -> None:
        """resize_and_crop_video lanza FFmpegNotFoundError sin ffmpeg."""
        monkeypatch.setattr(resizer, "ffmpeg_available", lambda: False)
        with pytest.raises(FFmpegNotFoundError):
            resize_and_crop_video(
                sample_video, (1290, 2796), tmp_path / "out.mp4",
            )

    def test_batch_records_error_without_ffmpeg(
        self, sample_video: Path, tmp_path: Path, monkeypatch,
    ) -> None:
        """Un video con targets iOS pero sin ffmpeg cuenta como error, sin crashear."""
        monkeypatch.setattr(resizer, "ffmpeg_available", lambda: False)
        out = tmp_path / "output"
        result = process_batch(
            sample_video, out, platform="ios", device="6.7inch",
        )
        assert result.processed == 0
        assert result.errors == 1
        assert "ffmpeg" in result.error_details[0][1].lower()

    def test_video_skipped_for_android_only(
        self, tmp_path: Path, monkeypatch,
    ) -> None:
        """Sin targets de Apple, los videos se omiten sin generar errores."""
        # Aunque ffmpeg estuviera disponible, android no recorta videos.
        monkeypatch.setattr(resizer, "ffmpeg_available", lambda: True)
        d = tmp_path / "in"
        d.mkdir()
        (d / "demo.mp4").write_bytes(b"x")
        Image.new("RGB", (800, 600)).save(str(d / "home.png"))

        out = tmp_path / "output"
        result = process_batch(d, out, platform="android", device="phone")

        # 1 imagen × 2 tamaños de phone; el video se ignora por completo.
        assert result.processed == 2
        assert result.errors == 0
        assert list(out.rglob("*.mp4")) == []


# ── Tests de recorte de video (ffmpeg simulado) ──────────────────────

class TestVideoCropping:
    """Verifica el flujo de recorte de video con ffmpeg simulado."""

    def test_batch_crops_video_to_apple_sizes(
        self, sample_video: Path, tmp_path: Path, monkeypatch,
    ) -> None:
        """El video se recorta a cada tamaño de Apple como .mp4."""
        fake_run = _fake_ffmpeg_success()
        monkeypatch.setattr(resizer, "ffmpeg_available", lambda: True)
        monkeypatch.setattr(resizer.subprocess, "run", fake_run)

        out = tmp_path / "output"
        result = process_batch(
            sample_video, out, platform="ios", device="6.7inch",
        )

        # 6.7inch tiene 2 tamaños (portrait + landscape).
        assert result.processed == 2
        assert result.errors == 0
        mp4s = sorted(p.name for p in out.rglob("*.mp4"))
        assert mp4s == ["demo_1290x2796.mp4", "demo_2796x1290.mp4"]
        # Los .mp4 viven bajo ios/<device>/, no en android.
        assert (out / "ios" / "6.7inch" / "demo_1290x2796.mp4").exists()

    def test_ffmpeg_filter_uses_cover_and_crop(
        self, sample_video: Path, tmp_path: Path, monkeypatch,
    ) -> None:
        """El comando ffmpeg pide scale-to-cover + crop al tamaño exacto."""
        fake_run = _fake_ffmpeg_success()
        monkeypatch.setattr(resizer, "ffmpeg_available", lambda: True)
        monkeypatch.setattr(resizer.subprocess, "run", fake_run)

        out = tmp_path / "output"
        process_batch(sample_video, out, platform="ios", device="6.7inch")

        assert fake_run.calls, "ffmpeg no fue invocado"
        cmd = fake_run.calls[0]
        vf = cmd[cmd.index("-vf") + 1]
        assert "force_original_aspect_ratio=increase" in vf
        assert "crop=1290:2796" in vf or "crop=2796:1290" in vf

    def test_ffmpeg_failure_recorded(
        self, sample_video: Path, tmp_path: Path, monkeypatch,
    ) -> None:
        """Si ffmpeg falla, se registra como error sin detener el batch."""
        def fake_run(cmd, capture_output=True, text=True):  # noqa: ANN001
            return types.SimpleNamespace(returncode=1, stderr="boom: invalid data")

        monkeypatch.setattr(resizer, "ffmpeg_available", lambda: True)
        monkeypatch.setattr(resizer.subprocess, "run", fake_run)

        out = tmp_path / "output"
        result = process_batch(
            sample_video, out, platform="ios", device="6.7inch",
        )
        assert result.processed == 0
        assert result.errors == 2  # ambos tamaños fallan
        assert "boom" in result.error_details[0][1]

    def test_videos_only_in_ios_folders_all_platforms(
        self, tmp_path: Path, monkeypatch,
    ) -> None:
        """Con 'all', los videos sólo aparecen bajo ios/, nunca android/."""
        fake_run = _fake_ffmpeg_success()
        monkeypatch.setattr(resizer, "ffmpeg_available", lambda: True)
        monkeypatch.setattr(resizer.subprocess, "run", fake_run)

        d = tmp_path / "in"
        d.mkdir()
        (d / "demo.mp4").write_bytes(b"x")
        Image.new("RGB", (800, 600)).save(str(d / "home.png"))

        out = tmp_path / "output"
        process_batch(d, out)  # todas las plataformas

        assert list((out / "android").rglob("*.mp4")) == []
        assert list((out / "ios").rglob("*.mp4"))  # hay videos en ios
        # Las imágenes sí se generan en ambas plataformas.
        assert list((out / "android").rglob("*.png"))
        assert list((out / "ios").rglob("*.png"))
