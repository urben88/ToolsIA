import os
import tkinter as tk
from tkinter import ttk, messagebox, filedialog

# Configuración de exclusiones por defecto (para optimizar el peso)
EXCLUDED_DIRS = {'.git', '__pycache__', 'node_modules', 'venv', 'env', '.idea', '.vscode', 'build', 'dist', 'bin', 'obj'}
EXCLUDED_EXTS = {'.exe', '.dll', '.so', '.dylib', '.class', '.jar', '.png', '.jpg', '.jpeg', '.gif', '.ico', '.svg', '.zip', '.tar', '.gz', '.pdf', '.pyc'}
EXCLUDED_FILES = {'package-lock.json', 'yarn.lock', 'contexto_codigo.txt', 'contexto_proyecto.py'}

class ContextCollectorApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Recolector de Contexto para LLM")
        self.root.geometry("600x700")
        
        # Estado de selección
        self.nodes = {}  # Map item_id -> full_path
        self.check_states = {} # Map item_id -> bool (True=Checked)

        # Frame principal
        main_frame = ttk.Frame(root, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)

        # Etiqueta de instrucciones
        lbl = ttk.Label(main_frame, text="Selecciona carpetas y archivos para añadir al contexto:")
        lbl.pack(pady=(0, 5), anchor="w")

        # Scrollbar y Treeview
        tree_frame = ttk.Frame(main_frame)
        tree_frame.pack(fill=tk.BOTH, expand=True)
        
        scrollbar = ttk.Scrollbar(tree_frame)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        self.tree = ttk.Treeview(tree_frame, selectmode="none", yscrollcommand=scrollbar.set)
        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.config(command=self.tree.yview)

        # Evento de clic para simular checkboxes
        self.tree.bind("<Button-1>", self.on_click)

        # Botón de Generar
        btn_frame = ttk.Frame(main_frame)
        btn_frame.pack(fill=tk.X, pady=10)
        
        self.btn_generate = ttk.Button(btn_frame, text="Generar 'contexto_codigo.txt'", command=self.generate_context)
        self.btn_generate.pack(fill=tk.X, ipady=5)

        # Cargar el árbol de directorios
        self.root_path = os.getcwd()
        self.populate_tree()

    def populate_tree(self):
        # Limpiar árbol
        for i in self.tree.get_children():
            self.tree.delete(i)
        self.nodes.clear()
        self.check_states.clear()

        # Insertar nodo raíz
        root_node = self.tree.insert("", "end", text=f"☐ {os.path.basename(self.root_path)}/", open=True)
        self.nodes[root_node] = self.root_path
        self.check_states[root_node] = False
        
        self.process_directory(root_node, self.root_path)

    def process_directory(self, parent_node, path):
        try:
            # Ordenar: carpetas primero, luego archivos
            items = os.listdir(path)
            items.sort(key=lambda x: (not os.path.isdir(os.path.join(path, x)), x.lower()))

            for item in items:
                full_path = os.path.join(path, item)
                
                # Filtrar carpetas y archivos ignorados
                if item in EXCLUDED_DIRS or item in EXCLUDED_FILES:
                    continue
                if os.path.isfile(full_path):
                    _, ext = os.path.splitext(item)
                    if ext.lower() in EXCLUDED_EXTS:
                        continue

                is_dir = os.path.isdir(full_path)
                display_text = f"☐ {item}" + ("/" if is_dir else "")
                
                node_id = self.tree.insert(parent_node, "end", text=display_text, open=False)
                self.nodes[node_id] = full_path
                self.check_states[node_id] = False

                if is_dir:
                    self.process_directory(node_id, full_path)
                    
        except PermissionError:
            pass

    def on_click(self, event):
        item_id = self.tree.identify_row(event.y)
        if item_id:
            # Toggle estado
            current_state = self.check_states.get(item_id, False)
            new_state = not current_state
            self.toggle_item(item_id, new_state)

    def toggle_item(self, item_id, state):
        self.check_states[item_id] = state
        
        # Actualizar texto visualmente
        original_text = self.tree.item(item_id, "text")
        clean_name = original_text[2:] # Quitar el símbolo anterior
        symbol = "☑" if state else "☐"
        self.tree.item(item_id, text=f"{symbol} {clean_name}")

        # Si es carpeta, propagar a hijos
        for child in self.tree.get_children(item_id):
            self.toggle_item(child, state)

    def generate_context(self):
        output_file = "contexto_codigo.txt"
        total_files = 0
        
        try:
            with open(output_file, "w", encoding="utf-8") as f:
                f.write(f"CONTEXTO DEL PROYECTO: {os.path.basename(self.root_path)}\n")
                f.write("="*50 + "\n\n")

                for item_id, path in self.nodes.items():
                    # Solo procesar si está marcado y es un archivo
                    if self.check_states.get(item_id, False) and os.path.isfile(path):
                        try:
                            # Intentar leer el archivo
                            with open(path, "r", encoding="utf-8") as source_file:
                                content = source_file.read()
                                
                                rel_path = os.path.relpath(path, self.root_path)
                                f.write(f"--- ARCHIVO: {rel_path} ---\n")
                                f.write(content)
                                f.write("\n\n")
                                total_files += 1
                        except UnicodeDecodeError:
                            # Si falla la lectura (archivo binario no detectado), lo saltamos
                            print(f"Saltando archivo binario o codificación desconocida: {path}")
                        except Exception as e:
                            print(f"Error leyendo {path}: {e}")

            messagebox.showinfo("Éxito", f"Contexto generado exitosamente en:\n{output_file}\n\nArchivos procesados: {total_files}")
            
        except Exception as e:
            messagebox.showerror("Error", f"No se pudo crear el archivo: {e}")

if __name__ == "__main__":
    root = tk.Tk()
    app = ContextCollectorApp(root)
    root.mainloop()