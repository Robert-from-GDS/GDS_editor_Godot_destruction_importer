# GDS Editor → Godot Destruction Animation Importer

Import **fragment‑based destruction / explode animations** created in **GDS Editor** directly into **Godot 4**.

This plugin converts the exported JSON + fragment atlas into a fully playable Godot animation.

---

## 📦 Installation

1. Open your Godot project folder.
2. If you already have an `addons` folder, place the entire  
   **`gds_destruction_animation_importer`** folder inside it.
3. If you *don’t* have an `addons` folder, create one:


---

## ⚙️ Enable the Plugin

1. In Godot, go to:  
   **Project → Project Settings → Plugins**
2. Locate **GDS Destruction Animation Importer**.
3. Enable it.
4. If it doesn’t appear, save and reload your project.

---

## 🧩 Exporting From GDS Editor

1. Create your destruction animation in **GDS Editor**.
2. When exporting, choose **“Godot Export”** from the dropdown.
3. GDS will generate a ZIP containing:
   - a fragment atlas PNG  
   - an animation JSON file  
   - (optional) a parent sprite PNG  

---

## 📥 Importing Into Godot

1. Unzip the exported file from GDS Editor.
2. Drop the unzipped folder into your Godot `res://` directory.
3. Godot will automatically import:
   - the JSON animation file  
   - the fragment atlas  
   - the optional parent sprite  

4. Select the **animation JSON file** in the FileSystem panel.
5. With the JSON selected, go to:  
   **Project → Tools → Import GDS Destruction Animation**

This will generate a complete Godot animation timeline.

---

## 🧹 Cleanup (Optional)

After the importer generates the animation timeline, you may delete the original JSON file from your project.  
Godot no longer needs it — the animation data is now stored internally.

---




