#!/usr/bin/env python3
"""
Interfaz web de Screenshot Forge.

Servidor Flask que expone una página con drag-and-drop de imágenes
y selección de plataformas/dispositivos. Procesa las imágenes con
``resizer.process_batch`` y devuelve un ZIP con los resultados.

Uso::

    python forge_web.py
    # Abrir http://localhost:5000

Principio aplicado: misma inversión de dependencias que la CLI y la GUI.
Este módulo depende de ``resizer`` y ``sizes``, nunca al revés.
"""

from __future__ import annotations

import io
import logging
import os
import shutil
import tempfile
import zipfile
from pathlib import Path

from flask import Flask, jsonify, render_template, request, send_file

from resizer import process_batch
from sizes import TARGETS

# ── Logging ──────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Límite de subida: 50 MB (suficiente para varias capturas de pantalla)
app.config["MAX_CONTENT_LENGTH"] = 50 * 1024 * 1024

# Carpeta persistente de salida. En Docker se monta como volumen
# para que los archivos queden en el host.
# Variable de entorno OUTPUT_DIR permite configurarla sin tocar código.
OUTPUT_DIR = Path(os.environ.get("OUTPUT_DIR", "./output"))


@app.route("/")
def index() -> str:
    """Sirve la página principal con el formulario de drag-and-drop."""
    return render_template("index.html")


@app.route("/api/targets")
def api_targets() -> tuple:
    """Devuelve las plataformas y dispositivos disponibles como JSON.

    Formato::

        {
          "ios": ["6.7inch", "6.5inch", ...],
          "android": ["phone", "7inch_tablet", ...]
        }
    """
    targets = {
        platform: list(devices.keys())
        for platform, devices in TARGETS.items()
    }
    return jsonify(targets)


@app.route("/forge", methods=["POST"])
def forge() -> tuple:
    """Recibe imágenes y selección de targets, devuelve un ZIP.

    Espera un multipart form con:
    - ``images``: uno o más archivos de imagen
    - ``targets``: JSON string con la selección, ej:
      ``{"ios": ["6.7inch"], "android": ["phone"]}``
    """
    # --- Validar que hay imágenes ---
    files = request.files.getlist("images")
    if not files or all(f.filename == "" for f in files):
        return jsonify({"error": "No se recibieron imágenes."}), 400

    # --- Parsear selección de targets ---
    import json
    targets_json = request.form.get("targets", "{}")
    try:
        selected = json.loads(targets_json)
    except json.JSONDecodeError:
        return jsonify({"error": "Formato de targets inválido."}), 400

    if not selected:
        return jsonify({"error": "Selecciona al menos un dispositivo."}), 400

    # --- Directorio temporal solo para los uploads ---
    tmp_input = Path(tempfile.mkdtemp(prefix="forge_input_"))

    try:
        # --- Guardar imágenes subidas ---
        for f in files:
            if f.filename:
                safe_name = Path(f.filename).name
                f.save(str(tmp_input / safe_name))

        # --- Procesar: la salida va a OUTPUT_DIR (persistente) ---
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

        total_processed = 0
        total_errors = 0

        for platform, devices in selected.items():
            for device in devices:
                result = process_batch(
                    input_path=tmp_input,
                    output_base=OUTPUT_DIR,
                    platform=platform,
                    device=device,
                )
                total_processed += result.processed
                total_errors += result.errors

        if total_processed == 0:
            return jsonify({
                "error": f"No se generó ninguna imagen. Errores: {total_errors}",
            }), 500

        # --- Crear ZIP en memoria desde los archivos persistidos ---
        zip_buffer = io.BytesIO()
        with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zf:
            for file_path in OUTPUT_DIR.rglob("*.png"):
                arcname = str(file_path.relative_to(OUTPUT_DIR))
                zf.write(file_path, arcname)

        zip_buffer.seek(0)

        logger.info(
            "Forge web completado: %d generadas, %d errores. "
            "Archivos en: %s",
            total_processed, total_errors, OUTPUT_DIR.resolve(),
        )

        return send_file(
            zip_buffer,
            mimetype="application/zip",
            as_attachment=True,
            download_name="screenshots-forged.zip",
        )

    finally:
        # --- Limpiar solo los uploads temporales ---
        shutil.rmtree(tmp_input, ignore_errors=True)


def main() -> None:
    """Lanza el servidor de desarrollo."""
    print("Screenshot Forge Web")
    print("http://localhost:8642")
    print()
    app.run(host="0.0.0.0", port=8642, debug=False)


if __name__ == "__main__":
    main()
