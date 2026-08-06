import os
from PIL import Image, ImageDraw, ImageFont

def create_timetable_image():
    # Dimensions
    width, height = 1800, 560
    img = Image.new('RGBA', (width, height), (255, 255, 255, 255))
    draw = ImageDraw.Draw(img)

    # Load system font
    font_paths = [
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf"
    ]
    
    font_bold = None
    font_regular = None
    font_header = None
    
    for path in font_paths:
        if os.path.exists(path):
            try:
                font_bold = ImageFont.truetype(path, 28)
                font_regular = ImageFont.truetype(path, 24)
                font_header = ImageFont.truetype(path, 32)
                break
            except Exception:
                pass
                
    if not font_bold:
        font_bold = ImageFont.load_default()
        font_regular = ImageFont.load_default()
        font_header = ImageFont.load_default()

    # Table layout definitions
    # Columns: Day (0), 8-9 (1), 9-10 (2), Short Break (3), 10.30-11.30 (4), 11.30-12.30 (5), Lunch Break (6), 1.15-2.15 (7), 2.15-3.15 (8)
    col_widths = [200, 200, 200, 110, 200, 200, 110, 200, 180]
    row_height = 70
    start_x = 20
    start_y = 20

    # Calculate column X positions
    col_x = [start_x]
    for w in col_widths:
        col_x.append(col_x[-1] + w)

    # Header labels
    headers = [
        "Day", "8.00-9.00", "9.00-10.00", "Short\nBreak",
        "10.30-11.30", "11.30-12.30", "Lunch\nBreak",
        "1.15-2.15", "2.15-3.15"
    ]

    # Draw Header Row
    draw.rectangle([col_x[0], start_y, col_x[-1], start_y + row_height], fill=(245, 247, 250, 255), outline=(0, 0, 0, 255), width=3)
    
    for i, h_text in enumerate(headers):
        x1, x2 = col_x[i], col_x[i+1]
        # vertical lines
        draw.line([x1, start_y, x1, start_y + row_height * 6], fill=(0, 0, 0, 255), width=3)
        # text
        bbox = draw.multiline_textbbox((0, 0), h_text, font=font_bold, align="center")
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        tx = x1 + (x2 - x1 - tw) / 2
        ty = start_y + (row_height - th) / 2
        draw.multiline_text((tx, ty), h_text, fill=(0, 0, 0, 255), font=font_bold, align="center")
    
    draw.line([col_x[-1], start_y, col_x[-1], start_y + row_height * 6], fill=(0, 0, 0, 255), width=3)

    # Data Rows
    schedule = [
        # Monday
        ("Monday", [
            (1, 1, "DBMS"), (2, 2, "SE"),
            (4, 5, "Elective 2"), # Spans 10.30-12.30
            (7, 8, "DBMS LAB")   # Spans 1.15-3.15
        ]),
        # Tuesday
        ("Tuesday", [
            (1, 2, "Elective 1"), # Spans 8-10
            (4, 4, "ML"), (5, 5, "DBMS")
        ]),
        # Wednesday
        ("Wednesday", [
            (1, 1, "ML"), (2, 2, "DBMS"),
            (4, 4, "SE"), (5, 5, "ML")
        ]),
        # Thursday
        ("Thursday", [
            (1, 2, "Elective 2"), # Spans 8-10
            (4, 4, "DBMS"), (5, 5, "SE"),
            (7, 8, "ML LAB")     # Spans 1.15-3.15
        ]),
        # Friday
        ("Friday", [
            (1, 1, "SE"), (2, 2, "ML"),
            (4, 5, "Elective 1")  # Spans 10.30-12.30
        ])
    ]

    for row_idx, (day_name, cells) in enumerate(schedule):
        y1 = start_y + (row_idx + 1) * row_height
        y2 = y1 + row_height
        
        # Horizontal row line
        draw.line([start_x, y1, col_x[-1], y1], fill=(0, 0, 0, 255), width=3)
        draw.line([start_x, y2, col_x[-1], y2], fill=(0, 0, 0, 255), width=3)

        # Day label (col 0)
        draw.rectangle([col_x[0], y1, col_x[1], y2], fill=(250, 250, 252, 255))
        bbox = draw.textbbox((0, 0), day_name, font=font_bold)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        draw.text((col_x[0] + (col_widths[0] - tw)/2, y1 + (row_height - th)/2), day_name, fill=(0, 0, 0, 255), font=font_bold)

        # Draw breaks (Short Break col 3, Lunch Break col 6)
        if row_idx == 0:
            # Draw Short Break vertical span
            sb_x1, sb_x2 = col_x[3], col_x[4]
            sb_y1, sb_y2 = start_y + row_height, start_y + 6 * row_height
            draw.rectangle([sb_x1, sb_y1, sb_x2, sb_y2], fill=(240, 240, 245, 255))
            
            # Draw rotated or centered text for Short Break
            sb_text = "Short Break"
            bbox = draw.textbbox((0, 0), sb_text, font=font_regular)
            tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
            
            # Create a vertical text image
            txt_img = Image.new('RGBA', (tw + 10, th + 10), (0, 0, 0, 0))
            txt_draw = ImageDraw.Draw(txt_img)
            txt_draw.text((5, 5), sb_text, fill=(0, 0, 0, 255), font=font_regular)
            rotated = txt_img.rotate(90, expand=True)
            rw, rh = rotated.size
            img.paste(rotated, (int(sb_x1 + (sb_x2 - sb_x1 - rw)/2), int(sb_y1 + (sb_y2 - sb_y1 - rh)/2)), rotated)

            # Draw Lunch Break vertical span
            lb_x1, lb_x2 = col_x[6], col_x[7]
            lb_y1, lb_y2 = start_y + row_height, start_y + 6 * row_height
            draw.rectangle([lb_x1, lb_y1, lb_x2, lb_y2], fill=(240, 240, 245, 255))
            
            lb_text = "Lunch Break"
            bbox = draw.textbbox((0, 0), lb_text, font=font_regular)
            tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
            txt_img2 = Image.new('RGBA', (tw + 10, th + 10), (0, 0, 0, 0))
            txt_draw2 = ImageDraw.Draw(txt_img2)
            txt_draw2.text((5, 5), lb_text, fill=(0, 0, 0, 255), font=font_regular)
            rotated2 = txt_img2.rotate(90, expand=True)
            rw2, rh2 = rotated2.size
            img.paste(rotated2, (int(lb_x1 + (lb_x2 - lb_x1 - rw2)/2), int(lb_y1 + (lb_y2 - lb_y1 - rh2)/2)), rotated2)

        # Draw Cells
        for start_c, end_c, text in cells:
            cx1 = col_x[start_c]
            cx2 = col_x[end_c + 1]
            
            # Subtle cell color for lab/elective/core
            bg_color = (255, 255, 255, 255)
            if "LAB" in text:
                bg_color = (235, 245, 255, 255)
            elif "Elective" in text:
                bg_color = (255, 245, 235, 255)
            elif text in ["DBMS", "SE", "ML"]:
                bg_color = (245, 255, 245, 255)

            draw.rectangle([cx1 + 2, y1 + 2, cx2 - 2, y2 - 2], fill=bg_color)
            
            bbox = draw.textbbox((0, 0), text, font=font_bold)
            tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
            draw.text((cx1 + (cx2 - cx1 - tw)/2, y1 + (row_height - th)/2), text, fill=(0, 0, 0, 255), font=font_bold)

    # Save output paths
    out_dir1 = os.path.expanduser("~/Pictures/CustomERTimetable")
    out_dir2 = os.path.expanduser("~/Pictures/CustomERPhotos")
    os.makedirs(out_dir1, exist_ok=True)
    os.makedirs(out_dir2, exist_ok=True)

    path1 = os.path.join(out_dir1, "timetable.png")
    path2 = os.path.join(out_dir2, "timetable.png")

    img.save(path1, "PNG")
    img.save(path2, "PNG")
    print(f"Saved HD Timetable Image to:\n- {path1}\n- {path2}")

if __name__ == "__main__":
    create_timetable_image()
