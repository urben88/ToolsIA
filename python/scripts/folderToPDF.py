import os
from fpdf import FPDF

def generar_arbol_directorios(base_folder, extensiones):
    arbol = {}

    for root, _, files in os.walk(base_folder):
        relative_root = os.path.relpath(root, base_folder)
        current = arbol
        if relative_root != ".":
            for part in relative_root.split(os.sep):
                current = current.setdefault(part, {})
        for file in files:
            if any(file.endswith(ext) for ext in extensiones):
                current.setdefault("__files__", []).append(file)
    return arbol

def escribir_arbol_en_pdf(pdf, arbol, indent=0):
    for key, value in sorted(arbol.items()):
        if key == "__files__":
            for file in sorted(value):
                pdf.multi_cell(0, 5, " " * indent + f"- {file}")
        else:
            pdf.multi_cell(0, 5, " " * indent + f"[{key}]/")
            escribir_arbol_en_pdf(pdf, value, indent + 4)

def main():
    print("📦 Convertidor de código a PDF (con rutas relativas)")

    input_path = input("📂 Ruta de la carpeta del proyecto (ej: ./carpeta): ").strip('"')
    output_name = input("📄 Nombre del archivo PDF (sin .pdf): ").strip()

    if not os.path.isdir(input_path):
        print("❌ Error: la ruta no es una carpeta válida.")
        return

    extensiones = [".py", ".js", ".ts", ".html", ".css", ".json", ".java"]
    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=15)
    pdf.set_font("Courier", size=10)

    base_folder = os.path.abspath(input_path)
    arbol = generar_arbol_directorios(base_folder, extensiones)

    # Página inicial con resumen del árbol de archivos
    pdf.add_page()
    pdf.set_font("Courier", style='B', size=12)
    pdf.multi_cell(0, 8, f"Resumen de archivos en:\n{input_path}\n")
    pdf.set_font("Courier", size=10)
    escribir_arbol_en_pdf(pdf, arbol)

    # Recorrido de archivos y creación de páginas
    for root, _, files in os.walk(base_folder):
        for file in files:
            if any(file.endswith(ext) for ext in extensiones):
                path = os.path.join(root, file)
                relative_path = os.path.relpath(path, base_folder)

                try:
                    with open(path, "r", encoding="utf-8", errors="ignore") as f:
                        lines = f.readlines()

                    pdf.add_page()
                    pdf.set_font("Courier", style='B', size=11)
                    ruta_visible = os.path.join(os.path.normpath(input_path), relative_path).replace(os.path.abspath('.') + os.sep, '')
                    pdf.multi_cell(0, 7, f"{ruta_visible}\n")

                    pdf.set_font("Courier", size=9)
                    for line in lines:
                        pdf.multi_cell(0, 5, line.rstrip())

                except Exception as e:
                    print(f"⚠️ No se pudo leer {path}: {e}")

    output_path = f"{output_name}.pdf"
    pdf.output(output_path)
    print(f"\n✅ PDF generado: {output_path}")

if __name__ == "__main__":
    try:
        from fpdf import FPDF
    except ImportError:
        print("❗ Debes instalar la librería FPDF primero:")
        print("   pip install fpdf")
    else:
        main()
