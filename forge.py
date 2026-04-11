#!/usr/bin/env python3
"""
CLI de Screenshot Forge.

Punto de entrada principal para uso en terminal. Actúa como **Facade**
sobre ``resizer.process_batch``, exponiendo la configuración mediante
argparse y presentando un resumen legible al usuario.

Uso rápido::

    python forge.py -i ./screenshots -o ./output -p ios
    python forge.py -i captura.png -p android -d phone
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from resizer import process_batch
from sizes import TARGETS

# ── Logging ──────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s: %(message)s",
)
logger = logging.getLogger(__name__)


def _build_parser() -> argparse.ArgumentParser:
    """Construye el parser de argumentos de la CLI."""
    # Recopilar todos los dispositivos válidos para el help
    all_devices = [d for devs in TARGETS.values() for d in devs]

    parser = argparse.ArgumentParser(
        prog="forge",
        description=(
            "Screenshot Forge — redimensiona screenshots a los tamaños "
            "oficiales de App Store y Google Play."
        ),
    )
    parser.add_argument(
        "-i", "--input",
        required=True,
        help="Ruta al archivo de imagen o carpeta con screenshots.",
    )
    parser.add_argument(
        "-o", "--output",
        default="./output",
        help="Carpeta de salida (default: ./output).",
    )
    parser.add_argument(
        "-p", "--platform",
        choices=["ios", "android", "all"],
        default="all",
        help="Plataforma objetivo (default: all).",
    )
    parser.add_argument(
        "-d", "--device",
        default=None,
        help=f"Dispositivo específico. Opciones: {', '.join(all_devices)}",
    )
    parser.add_argument(
        "-q", "--quality",
        type=int,
        choices=range(0, 10),
        default=6,
        metavar="0-9",
        help="Nivel de compresión PNG, 0=nula 9=máxima (default: 6).",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """Punto de entrada de la CLI.

    Args:
        argv: lista de argumentos (``None`` para tomar de ``sys.argv``).

    Returns:
        Código de salida: 0 si todo fue bien, 1 si hubo errores.
    """
    parser = _build_parser()
    args = parser.parse_args(argv)

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"Error: la ruta '{args.input}' no existe.", file=sys.stderr)
        return 1

    print(f"Screenshot Forge")
    print(f"{'─' * 40}")
    print(f"  Input:      {input_path}")
    print(f"  Output:     {args.output}")
    print(f"  Plataforma: {args.platform}")
    print(f"  Dispositivo:{' ' + args.device if args.device else ' todos'}")
    print(f"  Compresión: {args.quality}")
    print(f"{'─' * 40}\n")

    result = process_batch(
        input_path=input_path,
        output_base=args.output,
        platform=args.platform if args.platform != "all" else None,
        device=args.device,
        quality=args.quality,
    )

    # ── Resumen final ────────────────────────────────────────────────
    print(f"\n{'═' * 40}")
    print(f"  Generadas:  {result.processed}")
    print(f"  Errores:    {result.errors}")

    if result.paths:
        # Mostrar las carpetas únicas de salida
        folders = sorted({str(Path(p).parent) for p in result.paths})
        print(f"  Carpetas:")
        for folder in folders:
            print(f"    → {folder}")

    if result.error_details:
        print(f"\n  Detalle de errores:")
        for file_name, error_msg in result.error_details:
            print(f"    ✗ {file_name}: {error_msg}")

    print(f"{'═' * 40}")

    return 1 if result.errors > 0 and result.processed == 0 else 0


if __name__ == "__main__":
    sys.exit(main())
