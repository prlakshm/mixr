from pathlib import Path
import sys

import numpy as np
from PIL import Image


def capsule_runs(image: np.ndarray) -> list[tuple[int, int]]:
    row = image[600]
    core = (
        (row[:, 0] > 45)
        & (row[:, 2] > 100)
        & ((row[:, 2] - row[:, 1]) > 60)
    )
    columns = np.where(core)[0]
    runs: list[tuple[int, int]] = []
    start = previous = int(columns[0])
    for column in columns[1:]:
        column = int(column)
        if column > previous + 1:
            runs.append((start, previous))
            start = column
        previous = column
    runs.append((start, previous))
    return runs


def patch_luma(image: np.ndarray, x: float) -> float:
    x_center = int(round(x))
    patch = image[540:661, x_center - 4 : x_center + 5]
    return float(
        (
            0.2126 * patch[..., 0]
            + 0.7152 * patch[..., 1]
            + 0.0722 * patch[..., 2]
        ).mean()
    )


image_path = Path(sys.argv[1])
image = np.asarray(Image.open(image_path).convert("RGB"), dtype=float)
runs = capsule_runs(image)
assert len(runs) == 6, f"expected six bars, found {runs}"

hard_gaps = [runs[index + 1][0] - runs[index][1] - 1 for index in range(5)]
assert hard_gaps == [48] * 5, f"hard gaps differ: {hard_gaps}"

midpoints = [
    (runs[index][1] + runs[index + 1][0]) / 2
    for index in range(5)
]
gap_luma = [patch_luma(image, midpoint) for midpoint in midpoints]
outer_mean = sum(gap_luma[:2] + gap_luma[3:]) / 4
center_ratio = gap_luma[2] / outer_mean

assert center_ratio <= 1.05, (
    "center gap is optically compressed: "
    f"luma={gap_luma[2]:.2f}, outer mean={outer_mean:.2f}, "
    f"ratio={center_ratio:.3f}"
)

print(f"PASS hard gaps: {hard_gaps}")
print(f"PASS visible-gap luma: {[round(value, 2) for value in gap_luma]}")
print(f"PASS center/outer ratio: {center_ratio:.3f}")
