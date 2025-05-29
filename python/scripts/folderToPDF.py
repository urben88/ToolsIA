#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Convierte el contenido de un proyecto a PDF, TXT o CSV.
"""

import os
import csv
from pathlib import Path

try:
    from fpdf import FPDF          # Sólo se necesita si se elige PDF
except ImportError:
    FPDF = None                     # Permitimos TXT/CSV aunque no esté FPDF


EXTENSIONES = {
    ".py", ".js", ".ts", ".html", ".css", ".json", ".java", ".c", ".cpp",
    ".h", ".hpp", ".cs", ".php", ".rb", ".xml", ".yml", ".yaml", ".sh",
    ".bat", ".md", ".txt", ".ini", ".cfg", ".toml", ".sql", ".jsx",
    ".tsx", ".vue"
}


# --------------------------------------------------------------------------- #
# Utilidades comunes
# --------------------------------------------------------------------------- #
def scan_project(base_folder: Path):
    """
    Recorre el directorio y devuelve:
      1) arbol: estructura anidada { carpeta: { … , "__files__": [nombres] } }
      2) files: lista [(ruta_relativa, [líneas de texto]), … ]
    """
    arbol, files = {}, []
    for root, _, filenames in os.walk(base_folder):
        rel_root = Path(root).relative_to(base_folder)
        current = arbol
        if rel_root != Path("."):
            for part in rel_root.parts:
                current = current.setdefault(part, {})
        for name in filenames:
            if any(name.endswith(ext) for ext in EXTENSIONES):
                current.setdefault("__files__", []).append(name)
                path = Path(root) / name
                try:
                    with path.open("r", encoding="utf-8", errors="ignore") as fh:
                        files.append((path.relative_to(base_folder), fh.readlines()))
                except Exception as e:
                    print(f"⚠️  No se pudo leer {path}: {e}")
    return arbol, files


# --------------------------------------------------------------------------- #
# Salida PDF
# --------------------------------------------------------------------------- #
def arbol_pdf(pdf: "FPDF", nodo: dict, indent: int = 0):
    for key, val in sorted(nodo.items()):
        if key == "__files__":
            for f in sorted(val):
                pdf.multi_cell(0, 5, " " * indent + f"- {f}", new_x="LMARGIN", new_y="NEXT")
        else:
            pdf.multi_cell(0, 5, " " * indent + f"[{key}]/", new_x="LMARGIN", new_y="NEXT")
            arbol_pdf(pdf, val, indent + 4)


def export_pdf(base: Path, output: Path, arbol: dict, files: list):
    if FPDF is None:
        raise RuntimeError("❗ Instala primero fpdf2:  pip install fpdf2")

    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=15)
    pdf.set_font("Courier", size=10)

    # Portada con árbol
    pdf.add_page()
    pdf.set_font("Courier", style="B", size=12)
    pdf.multi_cell(0, 8, f"Resumen de archivos en:\n{base}\n", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Courier", size=10)
    arbol_pdf(pdf, arbol)

    # Secciones por archivo
    for rel_path, lines in files:
        pdf.add_page()
        pdf.set_font("Courier", style="B", size=11)
        pdf.multi_cell(0, 7, f"{rel_path}\n", new_x="LMARGIN", new_y="NEXT")
        pdf.set_font("Courier", size=9)
        for ln in lines:
            pdf.multi_cell(0, 5, ln.encode("latin-1", "replace").decode("latin-1"),
                           new_x="LMARGIN", new_y="NEXT")

    pdf.output(output)
    print(f"✅ PDF generado: {output}")


# --------------------------------------------------------------------------- #
# Salida TXT
# --------------------------------------------------------------------------- #
def export_txt(output: Path, arbol: dict, files: list):
    def arbol_txt(nodo: dict, indent: int = 0):
        for k, v in sorted(nodo.items()):
            if k == "__files__":
                for f in sorted(v):
                    yield " " * indent + f"- {f}"
            else:
                yield " " * indent + f"[{k}]/"
                yield from arbol_txt(v, indent + 4)

    with output.open("w", encoding="utf-8") as fh:
        fh.write("# Árbol de archivos\n")
        fh.write("\n".join(arbol_txt(arbol)))
        fh.write("\n\n# Contenido de archivos\n\n")
        for rel_path, lines in files:
            fh.write(f"## {rel_path}\n")
            fh.writelines(lines)
            fh.write("\n")
    print(f"✅ TXT generado: {output}")


# --------------------------------------------------------------------------- #
# Salida CSV
# --------------------------------------------------------------------------- #
def export_csv(output: Path, files: list):
    """
    CSV con columnas: ruta, num_linea, contenido
    """
    with output.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(["path", "line_no", "content"])
        for rel_path, lines in files:
            for n, ln in enumerate(lines, 1):
                writer.writerow([str(rel_path), n, ln.rstrip("\n")])
    print(f"✅ CSV generado: {output}")


# --------------------------------------------------------------------------- #
# Programa principal
# --------------------------------------------------------------------------- #
def main():
    print("📦 Convertidor de código")
    base = Path(input("📂 Ruta de la carpeta del proyecto: ").strip('"')).resolve()
    if not base.is_dir():
        print("❌ Ruta no válida")
        return

    out_name = input("💾 Nombre de salida (sin extensión): ").strip()
    fmt = input("📄 Formato (pdf / txt / csv): ").lower().strip()

    arbol, files = scan_project(base)

    output_path = base / f"{out_name}.{fmt}"
    try:
        if fmt == "pdf":
            export_pdf(base, output_path, arbol, files)
        elif fmt == "txt":
            export_txt(output_path, arbol, files)
        elif fmt == "csv":
            export_csv(output_path, files)
        else:
            print("⚠️  Formato no reconocido. Elige pdf, txt o csv.")
    except Exception as e:
        print(f"❌ Error generando salida: {e}")


if __name__ == "__main__":
    main()
