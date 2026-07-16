"""
Tests para el motor de redimensionamiento.

Ejecutar::

    pip install pytest
    pytest test_resizer.py -v
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from PIL import Image

from resizer import BatchResult, process_batch, resize_and_crop
from sizes import TARGETS


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
