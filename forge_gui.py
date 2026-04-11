#!/usr/bin/env python3
"""
GUI de Screenshot Forge (Tkinter / ttk).

Arquitectura
────────────
- **Observer**: el motor de resize notifica progreso vía callback;
  la GUI lo recibe y actualiza barra + log sin acoplarse al motor.
- **Thread separado**: el procesamiento corre en un hilo aparte para
  no bloquear el event-loop de Tkinter.
- **Single Responsibility**: la GUI sólo presenta datos y delega toda
  la lógica de imágenes a ``resizer.py``.
"""

from __future__ import annotations

import logging
import platform
import subprocess
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, ttk

from resizer import process_batch
from sizes import TARGETS

# ── Logging ──────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)

# ── Constantes de diseño ─────────────────────────────────────────────
MIN_WIDTH = 700
MIN_HEIGHT = 500
PAD = 8


class ForgeApp(ttk.Frame):
    """Ventana principal de Screenshot Forge."""

    def __init__(self, master: tk.Tk) -> None:
        super().__init__(master, padding=PAD)
        self.master = master
        self.pack(fill=tk.BOTH, expand=True)

        # Variables de estado
        self.input_var = tk.StringVar()
        self.output_var = tk.StringVar(value=str(Path("./output").resolve()))
        self.device_vars: dict[str, dict[str, tk.BooleanVar]] = {}
        self._running = False

        self._build_ui()

    # ── Construcción de la interfaz ──────────────────────────────────

    def _build_ui(self) -> None:
        """Ensambla todos los widgets de la ventana."""
        self._build_path_section()
        self._build_platform_section()
        self._build_action_section()
        self._build_log_section()

    def _build_path_section(self) -> None:
        """Sección de selección de carpetas de entrada y salida."""
        frame = ttk.LabelFrame(self, text="Rutas", padding=PAD)
        frame.pack(fill=tk.X, pady=(0, PAD))

        # Input
        row_in = ttk.Frame(frame)
        row_in.pack(fill=tk.X, pady=2)
        ttk.Label(row_in, text="Input:", width=8).pack(side=tk.LEFT)
        ttk.Entry(row_in, textvariable=self.input_var).pack(
            side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 4),
        )
        ttk.Button(row_in, text="Browse…", command=self._select_input).pack(
            side=tk.RIGHT,
        )

        # Output
        row_out = ttk.Frame(frame)
        row_out.pack(fill=tk.X, pady=2)
        ttk.Label(row_out, text="Output:", width=8).pack(side=tk.LEFT)
        ttk.Entry(row_out, textvariable=self.output_var).pack(
            side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 4),
        )
        ttk.Button(row_out, text="Browse…", command=self._select_output).pack(
            side=tk.RIGHT,
        )

    def _build_platform_section(self) -> None:
        """Sección de checkboxes por plataforma y dispositivo."""
        frame = ttk.LabelFrame(self, text="Plataformas y dispositivos", padding=PAD)
        frame.pack(fill=tk.X, pady=(0, PAD))

        for plat_name, devices in TARGETS.items():
            plat_frame = ttk.Frame(frame)
            plat_frame.pack(fill=tk.X, pady=2)

            # Etiqueta de plataforma
            ttk.Label(
                plat_frame,
                text=plat_name.upper(),
                font=("TkDefaultFont", 0, "bold"),
                width=10,
            ).pack(side=tk.LEFT)

            self.device_vars[plat_name] = {}
            for dev_name in devices:
                var = tk.BooleanVar(value=True)
                self.device_vars[plat_name][dev_name] = var
                ttk.Checkbutton(
                    plat_frame, text=dev_name, variable=var,
                ).pack(side=tk.LEFT, padx=(0, 8))

    def _build_action_section(self) -> None:
        """Botón Forge + barra de progreso."""
        frame = ttk.Frame(self)
        frame.pack(fill=tk.X, pady=(0, PAD))

        self.forge_btn = ttk.Button(
            frame, text="Forge", command=self._start_forge,
        )
        self.forge_btn.pack(side=tk.LEFT)

        self.open_btn = ttk.Button(
            frame, text="Open Output Folder", command=self._open_output,
            state=tk.DISABLED,
        )
        self.open_btn.pack(side=tk.LEFT, padx=(8, 0))

        self.progress = ttk.Progressbar(
            frame, orient=tk.HORIZONTAL, mode="determinate",
        )
        self.progress.pack(side=tk.RIGHT, fill=tk.X, expand=True, padx=(8, 0))

    def _build_log_section(self) -> None:
        """Área de log scrollable."""
        frame = ttk.LabelFrame(self, text="Log", padding=PAD)
        frame.pack(fill=tk.BOTH, expand=True)

        self.log_text = tk.Text(
            frame, height=10, state=tk.DISABLED, wrap=tk.WORD,
            font=("Courier", 11),
        )
        scrollbar = ttk.Scrollbar(frame, command=self.log_text.yview)
        self.log_text.configure(yscrollcommand=scrollbar.set)

        self.log_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

    # ── Acciones de usuario ──────────────────────────────────────────

    def _select_input(self) -> None:
        """Abre diálogo para seleccionar carpeta o archivo de entrada."""
        path = filedialog.askdirectory(title="Seleccionar carpeta de screenshots")
        if path:
            self.input_var.set(path)

    def _select_output(self) -> None:
        """Abre diálogo para seleccionar carpeta de salida."""
        path = filedialog.askdirectory(title="Seleccionar carpeta de salida")
        if path:
            self.output_var.set(path)

    def _open_output(self) -> None:
        """Abre la carpeta de salida en el explorador de archivos del SO."""
        out = Path(self.output_var.get())
        if not out.exists():
            self._log("La carpeta de salida no existe.")
            return

        system = platform.system()
        if system == "Darwin":
            subprocess.Popen(["open", str(out)])
        elif system == "Windows":
            subprocess.Popen(["explorer", str(out)])
        else:
            subprocess.Popen(["xdg-open", str(out)])

    def _start_forge(self) -> None:
        """Valida entradas e inicia el procesamiento en un hilo separado."""
        if self._running:
            return

        input_path = self.input_var.get().strip()
        if not input_path or not Path(input_path).exists():
            self._log("Error: selecciona una ruta de entrada válida.")
            return

        # Limpiar estado
        self._clear_log()
        self.progress["value"] = 0
        self.open_btn.configure(state=tk.DISABLED)
        self.forge_btn.configure(state=tk.DISABLED)
        self._running = True

        thread = threading.Thread(target=self._run_forge, daemon=True)
        thread.start()

    def _run_forge(self) -> None:
        """Ejecuta el batch en un hilo separado (no bloquea la GUI)."""
        # Recopilar dispositivos seleccionados por plataforma
        selected_targets: dict[str, list[str]] = {}
        for plat, devices in self.device_vars.items():
            active = [d for d, var in devices.items() if var.get()]
            if active:
                selected_targets[plat] = active

        if not selected_targets:
            self.master.after(0, self._log, "No hay dispositivos seleccionados.")
            self.master.after(0, self._finish)
            return

        input_path = self.input_var.get()
        output_base = self.output_var.get()

        total_result_processed = 0
        total_result_errors = 0

        # Ejecutar un batch por cada combinación plataforma/dispositivo activa
        for plat, devices in selected_targets.items():
            for dev in devices:
                result = process_batch(
                    input_path=input_path,
                    output_base=output_base,
                    platform=plat,
                    device=dev,
                    on_progress=self._on_progress,
                )
                total_result_processed += result.processed
                total_result_errors += result.errors

        # Resumen final
        summary = (
            f"\nCompletado: {total_result_processed} generadas, "
            f"{total_result_errors} errores."
        )
        self.master.after(0, self._log, summary)
        self.master.after(0, self._finish)

    # ── Callbacks y helpers ──────────────────────────────────────────

    def _on_progress(self, message: str, percent: int) -> None:
        """Callback invocado desde el hilo de procesamiento.

        Usa ``master.after`` para actualizar la GUI de forma segura
        desde el hilo principal de Tkinter.
        """
        self.master.after(0, self._log, message)
        self.master.after(0, self._set_progress, percent)

    def _set_progress(self, value: int) -> None:
        """Actualiza la barra de progreso."""
        self.progress["value"] = value

    def _log(self, message: str) -> None:
        """Añade una línea al área de log."""
        self.log_text.configure(state=tk.NORMAL)
        self.log_text.insert(tk.END, message + "\n")
        self.log_text.see(tk.END)
        self.log_text.configure(state=tk.DISABLED)

    def _clear_log(self) -> None:
        """Limpia el área de log."""
        self.log_text.configure(state=tk.NORMAL)
        self.log_text.delete("1.0", tk.END)
        self.log_text.configure(state=tk.DISABLED)

    def _finish(self) -> None:
        """Restaura el estado de la GUI al terminar el procesamiento."""
        self._running = False
        self.forge_btn.configure(state=tk.NORMAL)
        self.open_btn.configure(state=tk.NORMAL)
        self.progress["value"] = 100


def main() -> None:
    """Lanza la aplicación GUI."""
    root = tk.Tk()
    root.title("Screenshot Forge")
    root.minsize(MIN_WIDTH, MIN_HEIGHT)
    root.geometry(f"{MIN_WIDTH}x{MIN_HEIGHT}")

    ForgeApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
