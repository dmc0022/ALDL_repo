from PIL import Image, ImageSequence
from pathlib import Path

def gif_to_hex(in_path, out_path):
    img = Image.open(in_path)
    w, h = img.size
    frames = getattr(img, "n_frames", 1)

    print(f"Input: {in_path}")
    print(f"  Size: {w} x {h}")
    print(f"  Frames: {frames}")

    pixels = []

    for fi, frame in enumerate(ImageSequence.Iterator(img)):
        frame_rgb = frame.convert("RGB")
        print(f"  Processing frame {fi + 1}/{frames}...")
        for y in range(h):
            for x in range(w):
                r, g, b = frame_rgb.getpixel((x, y))

                rv = 1 if r > 127 else 0
                gv = 1 if g > 127 else 0
                bv = 1 if b > 127 else 0

                val = (rv << 2) | (gv << 1) | bv
                pixels.append(val)

    total_bytes = len(pixels)
    print(f"  Total bytes: {total_bytes}")

    with open(out_path, "w") as f:
        for val in pixels:
            f.write(f"{val:02X}\n")

    print(f"  Wrote: {out_path}")
    return frames


def batch_gifs_to_hex_from_folder():
    # Folder where this Python file is located
    script_dir = Path(__file__).resolve().parent

    # Input/output folders relative to this script
    input_folder = script_dir / "gifs"
    output_folder = script_dir / "hex_outputs"
    output_folder.mkdir(exist_ok=True)

    print(f"Looking for GIFs in: {input_folder}")

    if not input_folder.exists():
        print(f"Folder does not exist: {input_folder}")
        return

    # Find all files whose extension is .gif, regardless of upper/lowercase
    gif_files = [f for f in input_folder.iterdir() if f.is_file() and f.suffix.lower() == ".gif"]

    if not gif_files:
        print(f"No GIF files found in: {input_folder}")
        return

    gif_files = sorted(gif_files)

    for index, gif_path in enumerate(gif_files, start=1):
        try:
            with Image.open(gif_path) as img:
                frame_count = getattr(img, "n_frames", 1)

            out_name = f"gif{index}_{frame_count}.hex"
            out_path = output_folder / out_name

            gif_to_hex(gif_path, out_path)

        except Exception as e:
            print(f"Error processing {gif_path}: {e}")


if __name__ == "__main__":
    batch_gifs_to_hex_from_folder()