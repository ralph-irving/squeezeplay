# USAGE: fontforge -script overlay.py base.ttf overlay.ttf output.ttf
# you must use fontforge's built-in python via -script argument
import os
import sys
import fontforge

# Adjust this variable to change the scale size of the Japanese characters
SCALE_FACTOR = 1.7

raw_cmd_args = os.sys.argv if hasattr(os.sys, 'argv') else sys.argv

clean_paths = []
for item in raw_cmd_args:
    if isinstance(item, str):
        p_clean = item.strip().strip("'\"")
        if p_clean and not p_clean.endswith(".py") and not p_clean.startswith("-") and "fontforge" not in p_clean:
            clean_paths.append(p_clean)

if len(clean_paths) < 2:
    print(f"Usage: fontforge -script {sys.argv[0]} <base_font_ttf> <jp_font_ttf> [output_file]")
    sys.exit(1)

# Pull individual strings explicitly via array index channels
base_font_path = clean_paths[0]
jp_font_path = clean_paths[1]
output_font_path = clean_paths[2] if len(clean_paths) > 2 else "DejaVuSans-Bold-JP.ttf"

print(f"Base Destination Font: {base_font_path}")
print(f"Japanese Native TTF:   {jp_font_path}")
print(f"Target Output Path:     {output_font_path}")
print(f"Scale Factor:    {SCALE_FACTOR}\n")

# open Japanese Source Font directly in memory
print("Opening Japanese Source...")
noto = fontforge.open(jp_font_path)
noto_layer = noto.activeLayer

# flatten if the font natively contains a CID layout structure
if noto.cidversion is not None and noto.cidversion > 0:
    print("Flattening CID structures natively inside memory buffer...")
    noto.cidFlatten()

# global scale pass
print("Performing global scale transformation on Japanese TrueType vectors...")
noto.selection.all()
noto.selection.select(("less", "unicode"), 0x0100) # Keep Latin block native size
noto.transform([SCALE_FACTOR, 0, 0, SCALE_FACTOR, 0, 0])

# open destination base font
print("Opening Base Font...")
dejavu = fontforge.open(base_font_path)
dejavu_layer = dejavu.activeLayer

# Japanese unicode block ranges
japanese_unicode_ranges = [
    (0xFF00, 0xFFEF), (0x3000, 0x303F), (0x3040, 0x309F), 
    (0x30A0, 0x30FF), (0x3190, 0x319F), (0x31F0, 0x31FF), 
    (0x3200, 0x32FF), (0x3400, 0x4DBF), (0x4E00, 0x9FFF), 
    (0x2E80, 0x2EFF), (0x2F00, 0x2FDF), (0xF900, 0xFAFF)
]

# cell-by-cell re-mapping
print("Injecting scaled Japanese ranges character-by-character straight through memory...")
for start_uni, end_uni in japanese_unicode_ranges:
    for uni_code in range(start_uni, end_uni + 1):
        if uni_code in noto:
            glyph_layer_copy = noto[uni_code].layers[noto_layer]
            dejavu.createMappedChar(uni_code)
            dejavu[uni_code].layers[dejavu_layer] = glyph_layer_copy
            dejavu[uni_code].width = noto[uni_code].width

noto.close()

# align metadata flags for Squeezeplay
dejavu.os2_version = 4
if "bold" in base_font_path.lower():
    dejavu.macstyle = 1 
else:
    dejavu.macstyle = 0 

# generate final compiled TrueType font package
print(f"Saving merged font to {output_font_path}...")
dejavu.generate(output_font_path, flags=("opentype", "round"))
print("Finished successfully!")
