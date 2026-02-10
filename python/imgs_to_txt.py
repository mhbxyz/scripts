import os
import argparse
from datetime import datetime
from PIL import Image
import pytesseract

__version__ = "1.0.0"

def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}")

def run_ocr_to_txt(input_dir, lang="eng"):
    if not os.path.isdir(input_dir):
        log(f"Directory {input_dir} does not exist.")
        return

    images = sorted([
        f for f in os.listdir(input_dir)
        if f.lower().endswith(('.png', '.jpg', '.jpeg'))
    ])

    if not images:
        log("No image files found in the directory.")
        return

    output_txt = os.path.join(
        os.path.dirname(input_dir),
        os.path.basename(input_dir.rstrip("/\\")) + ".txt"
    )

    log(f"{len(images)} image(s) found for OCR.")
    all_text = []

    for index, img_file in enumerate(images, 1):
        img_path = os.path.join(input_dir, img_file)
        try:
            log(f"Performing OCR on {img_file} ...")
            text = pytesseract.image_to_string(Image.open(img_path), lang=lang)
            all_text.append(f"\n\n===== Page {index} : {img_file} =====\n\n{text.strip()}")
        except Exception as e:
            log(f"Error processing {img_file}: {e}")

    try:
        with open(output_txt, "w", encoding="utf-8") as f:
            f.write("\n".join(all_text))
        log(f"✅ OCR complete. Output saved to: {output_txt}")
    except Exception as e:
        log(f"Error writing output file: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Performs OCR on a folder of image files and outputs a single .txt file with page breaks."
    )
    parser.add_argument("input_dir", help="Path to the folder containing images")
    parser.add_argument("--lang", default="eng", help="Tesseract OCR language (e.g., eng, fra, deu...)")
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")

    args = parser.parse_args()
    run_ocr_to_txt(args.input_dir, args.lang)
