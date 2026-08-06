import os

files = [
    "CustomERApp_Minimal.swift",
    "CustomERApp_Childish.swift",
    "CustomERApp_Glass.swift"
]

base_dir = os.path.expanduser("~/Desktop/CustomER")

for f in files:
    path = os.path.join(base_dir, f)
    if not os.path.exists(path): continue
    with open(path, "r") as fp:
        content = fp.read()

    content = content.replace("p.font(", "dynamicFont(")

    with open(path, "w") as fp:
        fp.write(content)

print("Replacement done!")
