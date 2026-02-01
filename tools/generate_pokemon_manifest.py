#!/usr/bin/env python3
"""
Generates the Pokemon asset pack manifest from the legacy pokemon.json format.
Run this once to migrate to the new pack-based system.
"""

import json
import os

def main():
    # Paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    pokemon_json_path = os.path.join(project_root, "data", "pokemon.json")
    manifest_path = os.path.join(project_root, "user_assets", "pokemon", "manifest.json")
    
    # Read legacy pokemon.json
    with open(pokemon_json_path, "r", encoding="utf-8") as f:
        pokemon_data = json.load(f)
    
    # Build manifest
    manifest = {
        "pack_id": "pokemon",
        "display_name": "Pokemon",
        "version": "1.0",
        "assets": {}
    }
    
    for number, data in pokemon_data.items():
        name = data["name"]
        has_shiny = data.get("has_shiny", False)
        
        # Asset ID uses the pokemon number for uniqueness
        asset_id = number
        
        # Build variants
        variants = {
            "default": {
                "model": f"{number}_{name}.glb",
                "icon": f"{number}_{name}.png"
            }
        }
        
        if has_shiny:
            variants["shiny"] = {
                "model": f"{number}_{name}_shiny.glb",
                "icon": f"{number}_{name}_shiny.png"
            }
        
        manifest["assets"][asset_id] = {
            "display_name": name.replace("-", " ").title(),
            "variants": variants
        }
    
    # Write manifest
    os.makedirs(os.path.dirname(manifest_path), exist_ok=True)
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    
    print(f"Generated manifest with {len(manifest['assets'])} assets")
    print(f"Manifest written to: {manifest_path}")

if __name__ == "__main__":
    main()
