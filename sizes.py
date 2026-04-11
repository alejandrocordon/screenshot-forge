"""
Registro centralizado de tamaños objetivo para App Store y Google Play.

Patrón: Registry — un único punto de verdad para todas las dimensiones
requeridas por cada tienda. Agregar un nuevo dispositivo es tan simple
como añadir una entrada al diccionario; ningún otro módulo necesita cambiar
(Open/Closed Principle).
"""

# Cada tupla es (ancho, alto) en píxeles.
# Cuando hay dos tuplas para un mismo dispositivo, la primera es portrait
# y la segunda es landscape.

TARGETS: dict[str, dict[str, list[tuple[int, int]]]] = {
    "ios": {
        "6.7inch": [
            (1290, 2796),   # portrait
            (2796, 1290),   # landscape
        ],
        "6.5inch": [
            (1242, 2688),   # portrait  — iPhone XS Max / 11 Pro Max
            (2688, 1242),   # landscape
            (1284, 2778),   # portrait  — iPhone 12/13/14 Pro Max
            (2778, 1284),   # landscape
        ],
        "5.5inch": [
            (1242, 2208),   # portrait
            (2208, 1242),   # landscape
        ],
        "ipad_12.9inch": [
            (2048, 2732),   # portrait
            (2732, 2048),   # landscape
        ],
    },
    "android": {
        "phone": [
            (1080, 1920),   # portrait
            (1920, 1080),   # landscape
        ],
        "7inch_tablet": [
            (1200, 1920),   # portrait
            (1920, 1200),   # landscape
        ],
        "10inch_tablet": [
            (1600, 2560),   # portrait
            (2560, 1600),   # landscape
        ],
        "chromebook": [
            (1920, 1080),   # landscape únicamente
        ],
    },
}

# Extensiones de imagen soportadas (en minúsculas, con punto)
SUPPORTED_EXTENSIONS: set[str] = {".png", ".jpg", ".jpeg"}


def get_targets(
    platform: str | None = None,
    device: str | None = None,
) -> dict[str, dict[str, list[tuple[int, int]]]]:
    """Filtra y devuelve los tamaños objetivo según plataforma y dispositivo.

    Args:
        platform: ``"ios"``, ``"android"`` o ``None`` para todas.
        device: nombre del dispositivo (ej. ``"6.5inch"``, ``"phone"``)
                o ``None`` para todos los del platform seleccionado.

    Returns:
        Sub-diccionario de ``TARGETS`` que cumple los filtros.

    Raises:
        ValueError: si *platform* o *device* no existen en el registro.
    """
    # --- Filtro por plataforma ---
    if platform and platform != "all":
        if platform not in TARGETS:
            valid = ", ".join(TARGETS)
            raise ValueError(
                f"Plataforma '{platform}' no válida. Opciones: {valid}"
            )
        filtered = {platform: TARGETS[platform]}
    else:
        filtered = dict(TARGETS)

    # --- Filtro por dispositivo ---
    if device:
        result: dict[str, dict[str, list[tuple[int, int]]]] = {}
        found = False
        for plat, devices in filtered.items():
            if device in devices:
                result[plat] = {device: devices[device]}
                found = True
        if not found:
            all_devices = [
                d for devs in filtered.values() for d in devs
            ]
            raise ValueError(
                f"Dispositivo '{device}' no encontrado. "
                f"Disponibles: {', '.join(all_devices)}"
            )
        return result

    return filtered
