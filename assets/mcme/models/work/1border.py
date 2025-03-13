import os
import numpy as np
from PIL import Image, ImageDraw

def process_png(file_path):
    # Open the image with RGBA mode
    img = Image.open(file_path).convert("RGBA")
    pixels = np.array(img)
    
    # Remove fully transparent pixels
    alpha_channel = pixels[:, :, 3]
    mask = alpha_channel == 0
    pixels[mask] = [0, 0, 0, 0]
    
    # Compute average color (ignoring transparent pixels)
    non_transparent_pixels = pixels[alpha_channel > 0][:, :3]  # Extract RGB values only
    if non_transparent_pixels.size == 0:
        print(f"Skipping {file_path}, no visible pixels.")
        return
    avg_color = non_transparent_pixels.mean(axis=0).astype(int)
    avg_color_with_alpha = (avg_color[0], avg_color[1], avg_color[2], 3)  # (x/255)
    
    # Create border mask
    img = Image.fromarray(pixels, "RGBA")
    border = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(border)
    
    # Find non-transparent pixels and draw a border around them
    for x in range(img.width):
        for y in range(img.height):
            if img.getpixel((x, y))[3] > 0:  # Check if not fully transparent
                draw.rectangle([x-5, y-5, x+5, y+5], fill=avg_color_with_alpha)
    
    # Composite the border with the original image
    img = Image.alpha_composite(border, img)
    
    # Save the processed image
    img.save(file_path)
    print(f"Processed {file_path}")

if __name__ == "__main__":
    for file in os.listdir():
        if file.endswith(".png") and "leaves" in file:
            process_png(file)