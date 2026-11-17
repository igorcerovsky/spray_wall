#!/usr/bin/env python3
"""Export local SprayWall SQLite data and rectified wall images to web/."""

from __future__ import annotations

import json
import os
import shutil
import sqlite3
from pathlib import Path

WALL_PROJECT_DIR = Path.home() / "Documents" / "wall_project"
SQLITE_PATH = WALL_PROJECT_DIR / "spraywall.sqlite"
MAIN_WALL_IMG = WALL_PROJECT_DIR / "main_wall_rectified.png"
KICKBOARD_IMG = WALL_PROJECT_DIR / "kickboard_rectified.png"

REPO_ROOT = Path(__file__).resolve().parent.parent
WEB_DIR = REPO_ROOT / "web"
WEB_DATA_PATH = WEB_DIR / "data" / "boulders.json"
WEB_DATA_JS_PATH = WEB_DIR / "data" / "boulders.js"
WEB_IMAGES_DIR = WEB_DIR / "images"

AVAILABLE_GRADES = [
    "1", "2", "3", "4",
    "5a", "5b", "5c",
    "6a", "6a+", "6b", "6b+", "6c", "6c+",
    "7a", "7a+", "7b", "7b+", "7c", "7c+",
    "8a", "8a+", "8b", "8b+", "8c", "8c+",
    "9a",
]


def parse_csv_ints(value: str | None) -> list[int]:
    if not value:
        return []
    result: list[int] = []
    for part in value.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            result.append(int(part))
        except ValueError:
            continue
    return result


def main() -> None:
    if not SQLITE_PATH.exists():
        raise FileNotFoundError(f"SQLite store not found at {SQLITE_PATH}")

    WEB_DATA_PATH.parent.mkdir(parents=True, exist_ok=True)
    WEB_IMAGES_DIR.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(str(SQLITE_PATH))
    conn.row_factory = sqlite3.Row

    holds_rows = conn.execute(
        """
        SELECT ZHOLDID, ZXCM, ZYCM, ZMAJORCMVALUE, ZMINORCMVALUE, ZROTATIONDEGVALUE, ZPLANERAW
        FROM ZHOLD
        ORDER BY ZHOLDID ASC
        """
    ).fetchall()

    holds = [
        {
            "id": int(r["ZHOLDID"]),
            "xCm": float(r["ZXCM"]),
            "yCm": float(r["ZYCM"]),
            "majorCm": float(r["ZMAJORCMVALUE"] if r["ZMAJORCMVALUE"] is not None else 8.0),
            "minorCm": float(r["ZMINORCMVALUE"] if r["ZMINORCMVALUE"] is not None else 8.0),
            "rotationDeg": float(r["ZROTATIONDEGVALUE"] if r["ZROTATIONDEGVALUE"] is not None else 0.0),
            "plane": r["ZPLANERAW"] or "main",
        }
        for r in holds_rows
    ]

    boulders_rows = conn.execute(
        """
        SELECT ZBOULDERID, ZNAME, ZGRADE, ZSETTER, ZSTATUSRAW, ZRATINGVALUE,
               ZTAGS, ZNOTES, ZSTARTHOLDIDSCSV, ZHOLDIDSCSV, ZFOOTHOLDIDSCSV, ZTOPHOLDIDSCSV,
               ZUPDATEDAT
        FROM ZBOULDER
        ORDER BY ZUPDATEDAT DESC
        """
    ).fetchall()

    boulders = []
    for r in boulders_rows:
        start_ids = parse_csv_ints(r["ZSTARTHOLDIDSCSV"])
        hold_ids = parse_csv_ints(r["ZHOLDIDSCSV"])
        foothold_ids = parse_csv_ints(r["ZFOOTHOLDIDSCSV"])
        top_ids = parse_csv_ints(r["ZTOPHOLDIDSCSV"])
        boulders.append(
            {
                "id": int(r["ZBOULDERID"]),
                "name": (r["ZNAME"] or f"Boulder {r['ZBOULDERID']}").strip(),
                "grade": (r["ZGRADE"] or "").strip(),
                "setter": (r["ZSETTER"] or "").strip(),
                "status": (r["ZSTATUSRAW"] or "draft").strip(),
                "rating": int(r["ZRATINGVALUE"] or 0),
                "tags": (r["ZTAGS"] or "").strip(),
                "notes": (r["ZNOTES"] or "").strip(),
                "startHoldIDs": start_ids,
                "holdIDs": hold_ids,
                "footholdIDs": foothold_ids,
                "topHoldIDs": top_ids,
                "updatedAt": float(r["ZUPDATEDAT"] or 0),
            }
        )

    conn.close()

    payload = {
        "wall": {
            "widthCm": 360.0,
            "mainWallHeightCm": 320.0,
            "kickboardHeightCm": 40.0,
            "totalHeightCm": 360.0,
        },
        "availableGrades": AVAILABLE_GRADES,
        "holds": holds,
        "boulders": boulders,
    }

    with open(WEB_DATA_PATH, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)

    with open(WEB_DATA_JS_PATH, "w", encoding="utf-8") as f:
        f.write("window.SPRAYWALL_DATA = ")
        json.dump(payload, f, ensure_ascii=False)
        f.write(";\n")

    for src, name in [(MAIN_WALL_IMG, "main_wall_rectified.png"), (KICKBOARD_IMG, "kickboard_rectified.png")]:
        if src.exists():
            shutil.copy2(src, WEB_IMAGES_DIR / name)
        else:
            print(f"Warning: {src} not found")

    print(f"Exported {len(holds)} holds and {len(boulders)} boulders to {WEB_DATA_PATH}")


if __name__ == "__main__":
    main()
