import tkinter as tk
from tkinter import filedialog, messagebox
import qrcode
from PIL import ImageTk, Image
import io

class QRGeneratorGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("QR Generator")
        self.root.geometry("500x600")

        # Text area
        self.text_box = tk.Text(root, height=15, width=50)
        self.text_box.pack(pady=10)

        # Buttons
        btn_frame = tk.Frame(root)
        btn_frame.pack()

        tk.Button(btn_frame, text="Load File", command=self.load_file).grid(row=0, column=0, padx=5)
        tk.Button(btn_frame, text="Generate QR", command=self.generate_qr).grid(row=0, column=1, padx=5)
        tk.Button(btn_frame, text="Save QR", command=self.save_qr).grid(row=0, column=2, padx=5)

        # Canvas to display QR
        self.qr_label = tk.Label(root)
        self.qr_label.pack(pady=15)

        self.qr_img = None  # store last QR

    def load_file(self):
        path = filedialog.askopenfilename(
            title="Open File",
            filetypes=[("Config files", "*.conf"), ("Text files", "*.txt"), ("All files", "*.*")]
        )
        if path:
            with open(path, "r") as f:
                content = f.read()
                self.text_box.delete("1.0", tk.END)
                self.text_box.insert(tk.END, content)

    def generate_qr(self):
        text = self.text_box.get("1.0", tk.END).strip()
        if not text:
            messagebox.showerror("Error", "Text box is empty")
            return

        # Generate QR
        qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_L)
        qr.add_data(text)
        qr.make(fit=True)
        img = qr.make_image(fill_color="black", back_color="white")

        # Keep image in memory
        self.qr_img = img

        # Display QR in GUI
        img_tk = ImageTk.PhotoImage(img.resize((300, 300)))
        self.qr_label.configure(image=img_tk)
        self.qr_label.image = img_tk  # keep reference

    def save_qr(self):
        if self.qr_img is None:
            messagebox.showerror("Error", "Generate a QR first")
            return

        path = filedialog.asksaveasfilename(
            defaultextension=".png",
            filetypes=[("PNG files", "*.png")]
        )
        if path:
            self.qr_img.save(path)
            messagebox.showinfo("Saved", f"QR saved to {path}")

if __name__ == "__main__":
    root = tk.Tk()
    app = QRGeneratorGUI(root)
    root.mainloop()
