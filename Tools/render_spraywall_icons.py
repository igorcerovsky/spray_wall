import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageOps

def create_squircle_mask(size=(1024, 1024), icon_size=824, n=4.2):
    mask = Image.new('L', size, 0)
    w, h = size
    cx, cy = w / 2.0, h / 2.0
    half = icon_size / 2.0
    y, x = np.ogrid[:h, :w]
    dx = np.abs((x - cx) / half)
    dy = np.abs((y - cy) / half)
    distance = (dx ** n + dy ** n) ** (1.0 / n)
    edge_width = 2.0 / half
    alpha = np.clip((1.0 - distance) / edge_width, 0, 1) * 255
    return Image.fromarray(alpha.astype(np.uint8))

def create_drop_shadow(mask, offset=(0, 24), blur=28, opacity=0.42):
    w, h = mask.size
    shadow = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    black = Image.new('RGBA', (w, h), (6, 8, 14, int(255 * opacity)))
    shadow.paste(black, mask=mask)
    offset_shadow = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    offset_shadow.paste(shadow, offset)
    return offset_shadow.filter(ImageFilter.GaussianBlur(blur))

def create_inner_bevel(mask, size=(1024, 1024)):
    w, h = size
    arr = np.array(mask, dtype=np.float32) / 255.0
    grad_y, grad_x = np.gradient(arr)
    edge = np.sqrt(grad_x**2 + grad_y**2)
    edge = np.clip(edge * 5.0, 0, 1.0)
    
    y, x = np.ogrid[:h, :w]
    cy = h / 2.0
    top_factor = np.clip((cy - y + 240) / 450.0, 0.12, 1.0)
    alpha = (edge * top_factor * 170).astype(np.uint8)
    
    rim = Image.new('RGBA', (w, h), (255, 255, 255, 0))
    rim.putalpha(Image.fromarray(alpha))
    return rim

def draw_laser_route(draw_layer, points, color_core=(255, 255, 255, 255), color_glow=(0, 210, 255, 160)):
    # 1. Broad outer diffuse glow
    broad = Image.new('RGBA', draw_layer.size, (0, 0, 0, 0))
    d_broad = ImageDraw.Draw(broad)
    d_broad.line(points, fill=color_glow, width=18, joint='curve')
    broad = broad.filter(ImageFilter.GaussianBlur(12))
    
    # 2. Focused mid glow
    mid = Image.new('RGBA', draw_layer.size, (0, 0, 0, 0))
    d_mid = ImageDraw.Draw(mid)
    d_mid.line(points, fill=(color_glow[0], color_glow[1], color_glow[2], 230), width=8, joint='curve')
    mid = mid.filter(ImageFilter.GaussianBlur(3))
    
    # 3. Crisp sharp laser core
    core = Image.new('RGBA', draw_layer.size, (0, 0, 0, 0))
    d_core = ImageDraw.Draw(core)
    d_core.line(points, fill=color_core, width=2, joint='curve')
    
    draw_layer.alpha_composite(broad)
    draw_layer.alpha_composite(mid)
    draw_layer.alpha_composite(core)

def draw_glowing_hold(layer, cx, cy, rx, ry, color_rgb):
    r, g, b = color_rgb
    
    # 1. Large ambient floor glow (illuminates surrounding wood)
    amb = Image.new('RGBA', layer.size, (0, 0, 0, 0))
    da = ImageDraw.Draw(amb)
    da.ellipse([cx - rx - 48, cy - ry - 48, cx + rx + 48, cy + ry + 48], fill=(r, g, b, 70))
    amb = amb.filter(ImageFilter.GaussianBlur(26))
    
    # 2. Mid volumetric ring glow
    mid = Image.new('RGBA', layer.size, (0, 0, 0, 0))
    dm = ImageDraw.Draw(mid)
    dm.ellipse([cx - rx - 16, cy - ry - 16, cx + rx + 16, cy + ry + 16], outline=(r, g, b, 200), width=12)
    dm.ellipse([cx - rx - 2, cy - ry - 2, cx + rx + 2, cy + ry + 2], fill=(r, g, b, 65))
    mid = mid.filter(ImageFilter.GaussianBlur(7))
    
    # 3. High intensity neon outline
    ring = Image.new('RGBA', layer.size, (0, 0, 0, 0))
    dr = ImageDraw.Draw(ring)
    dr.ellipse([cx - rx - 4, cy - ry - 4, cx + rx + 4, cy + ry + 4], outline=(r, g, b, 255), width=5)
    
    # 4. White-hot center / inner specular rim
    core = Image.new('RGBA', layer.size, (0, 0, 0, 0))
    dc = ImageDraw.Draw(core)
    dc.ellipse([cx - rx - 2, cy - ry - 2, cx + rx + 2, cy + ry + 2], outline=(255, 255, 255, 220), width=2)
    # Small laser waypoint dot
    dc.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], fill=(255, 255, 255, 240))
    core = core.filter(ImageFilter.GaussianBlur(1))
    
    layer.alpha_composite(amb)
    layer.alpha_composite(mid)
    layer.alpha_composite(ring)
    layer.alpha_composite(core)

def render_constellation_icon(
    crop_path,
    output_path,
    style='natural',
    size=(1024, 1024),
    icon_size=824
):
    raw_crop = Image.open(crop_path).convert('RGB')
    wall = raw_crop.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
    
    # Micro-contrast
    wall = ImageEnhance.Sharpness(wall).enhance(1.65)
    
    if style == 'natural':
        wall = ImageEnhance.Color(wall).enhance(1.35)
        wall = ImageEnhance.Contrast(wall).enhance(1.35)
        
        # Golden warm vignette
        vignette = Image.new('L', (icon_size, icon_size), 0)
        y, x = np.ogrid[:icon_size, :icon_size]
        cx, cy = icon_size / 2.0, icon_size / 2.0
        rad = np.sqrt((x - cx)**2 + (y - cy)**2) / (icon_size * 0.70)
        vig_alpha = np.clip((rad ** 2.2) * 220, 0, 215).astype(np.uint8)
        vig_img = Image.new('RGBA', (icon_size, icon_size), (10, 8, 5, 0))
        vig_img.putalpha(Image.fromarray(vig_alpha))
        wall_rgba = wall.convert('RGBA')
        wall_rgba.alpha_composite(vig_img)
        wall = wall_rgba
        
    elif style == 'dark':
        wall = ImageOps.autocontrast(wall, cutoff=1)
        wall = ImageEnhance.Brightness(wall).enhance(0.50)
        wall = ImageEnhance.Contrast(wall).enhance(1.65)
        
        # Deep charcoal espresso tint
        wash = Image.new('RGBA', (icon_size, icon_size), (8, 14, 24, 100))
        wall_rgba = wall.convert('RGBA')
        wall_rgba.alpha_composite(wash)
        
        # Strong vignette
        y, x = np.ogrid[:icon_size, :icon_size]
        cx, cy = icon_size / 2.0, icon_size / 2.0
        rad = np.sqrt((x - cx)**2 + (y - cy)**2) / (icon_size * 0.62)
        vig_alpha = np.clip((rad ** 2.0) * 240, 0, 240).astype(np.uint8)
        vig_img = Image.new('RGBA', (icon_size, icon_size), (2, 4, 8, 0))
        vig_img.putalpha(Image.fromarray(vig_alpha))
        wall_rgba.alpha_composite(vig_img)
        wall = wall_rgba
        
    elif style == 'vector':
        wall = ImageOps.autocontrast(wall, cutoff=1)
        wall = ImageEnhance.Brightness(wall).enhance(0.62)
        wall = ImageEnhance.Contrast(wall).enhance(1.45)
        wall_rgba = wall.convert('RGBA')
        
        # Blueprint grid overlay
        grid = Image.new('RGBA', (icon_size, icon_size), (0, 0, 0, 0))
        d_grid = ImageDraw.Draw(grid)
        step = icon_size // 8
        for i in range(step, icon_size, step):
            d_grid.line([(i, 0), (i, icon_size)], fill=(70, 160, 255, 38), width=1)
            d_grid.line([(0, i), (icon_size, i)], fill=(70, 160, 255, 38), width=1)
        wall_rgba.alpha_composite(grid)
        wall = wall_rgba

    canvas = Image.new('RGBA', size, (0, 0, 0, 0))
    squircle_mask = create_squircle_mask(size=size, icon_size=icon_size)
    drop_shadow = create_drop_shadow(squircle_mask)
    canvas.alpha_composite(drop_shadow)
    
    ox, oy = (size[0] - icon_size) // 2, (size[1] - icon_size) // 2
    icon_content = Image.new('RGBA', size, (0, 0, 0, 0))
    icon_content.paste(wall, (ox, oy))
    
    overlay = Image.new('RGBA', size, (0, 0, 0, 0))
    
    # Coordinated climbing problem:
    # 1. Start Left (Green)
    start_left = (ox + 370, oy + 705, 36, 20, (30, 255, 110))
    # 2. Start Right (Green)
    start_right = (ox + 580, oy + 800, 34, 20, (30, 255, 110))
    # 3. Foothold (Golden Yellow)
    foothold = (ox + 446, oy + 778, 22, 15, (255, 215, 35))
    
    # 4. Hand sequence (Electric Sapphire Cyan-Blue)
    seq_left_pinch = (ox + 275, oy + 540, 24, 42, (0, 210, 255))
    seq_mid_crimp = (ox + 422, oy + 465, 44, 20, (0, 210, 255))
    seq_high_crimp = (ox + 425, oy + 412, 44, 22, (0, 210, 255))
    seq_rail = (ox + 590, oy + 450, 30, 65, (0, 210, 255))
    
    # 5. Top Finish (Ruby Red)
    top_hold = (ox + 480, oy + 98, 54, 22, (255, 45, 75))
    
    # Clean natural climbing sequence without line crossings:
    # Left Start -> Left Pinch -> Mid Crimp -> High Crimp -> Right Organic Rail -> Top Finish
    laser_pts = [
        (start_left[0], start_left[1]),
        (seq_left_pinch[0], seq_left_pinch[1]),
        (seq_mid_crimp[0], seq_mid_crimp[1]),
        (seq_high_crimp[0], seq_high_crimp[1]),
        (seq_rail[0], seq_rail[1]),
        (top_hold[0], top_hold[1])
    ]
    
    foot_pts = [
        (start_right[0], start_right[1]),
        (foothold[0], foothold[1]),
        (start_left[0], start_left[1])
    ]
    
    # Draw laser paths
    draw_laser_route(overlay, foot_pts, color_core=(255, 245, 190, 180), color_glow=(255, 200, 30, 80))
    draw_laser_route(overlay, laser_pts, color_core=(240, 255, 255, 255), color_glow=(0, 200, 255, 175))
    
    # Draw all holds
    all_holds = [
        top_hold,
        seq_high_crimp,
        seq_rail,
        seq_mid_crimp,
        seq_left_pinch,
        start_left,
        start_right,
        foothold
    ]
    
    for h_x, h_y, h_rx, h_ry, h_color in all_holds:
        draw_glowing_hold(overlay, h_x, h_y, h_rx, h_ry, h_color)
        
    icon_content.alpha_composite(overlay)
    
    masked_icon = Image.new('RGBA', size, (0, 0, 0, 0))
    masked_icon.paste(icon_content, (0, 0), mask=squircle_mask)
    
    bevel = create_inner_bevel(squircle_mask, size=size)
    masked_icon.alpha_composite(bevel)
    
    canvas.alpha_composite(masked_icon)
    canvas.save(output_path, 'PNG', optimize=True)
    print(f'Rendered: {output_path}')

if __name__ == '__main__':
    crop_input = '/Users/igorcerovsky/.gemini/antigravity/brain/7b84420a-a9b9-4994-8476-8808f2ca085c/crop_full.jpg'
    output_icon = 'docs/icons/constellation_realwall_natural.png'
    render_constellation_icon(crop_input, output_icon, style='natural')

