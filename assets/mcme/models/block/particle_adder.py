import os
import json

def inject_texture_path(json_file, texture_path):
    """
    Injects the texture path into the JSON file on line 3, if not already present.

    Args:
        json_file (str): Path to the JSON file.
        texture_path (str): Texture path to inject.
    """
    try:
        with open(json_file, 'r+', encoding='utf-8') as f:
            lines = f.readlines()
            
            # Check if the "particle" key already exists in the file
            if any('particle' in line for line in lines):
                print(f"Skipping {json_file} - 'particle' key already exists.")
                return

            # Insert on line 3 with 2 spaces indentation
            lines.insert(2, f'  "particle": "{texture_path}",\n')
            f.seek(0)
            f.writelines(lines)
        print(f"Successfully injected texture path into {json_file}")
    except Exception as e:
        print(f"Error injecting texture into {json_file}: {e}")

def extract_texture_from_mtl(mtl_file):
    """
    Extracts the texture path from an MTL file.

    Args:
        mtl_file (str): Path to the MTL file.

    Returns:
        str: The texture path (e.g., "mcme:block/texture_name"), or None if not found.
    """
    try:
        with open(mtl_file, 'r', encoding='utf-8') as f:
            for line in f:
                if line.startswith("map_Kd"):
                    texture_path = line.split()[1]
                    # Convert path to use "mcme:block/" format
                    texture_path = texture_path.replace('\\', '/')
                    texture_path_parts = texture_path.split('/')
                    if len(texture_path_parts) > 1:
                        # Ensure the correct prefix format
                        return f"mcme:block/{'/'.join(texture_path_parts[1:])}"
    except Exception as e:
        print(f"Error reading MTL file {mtl_file}: {e}")
    return None

def process_json_files(directory):
    """
    Processes JSON files in a directory to inject texture paths from associated OBJ and MTL files.

    Args:
        directory (str): Path to the directory containing JSON, OBJ, and MTL files.
    """
    print(f"Scanning directory: {directory}")
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.json'):
                json_file_path = os.path.join(root, file)
                print(f"Processing JSON file: {json_file_path}")

                try:
                    with open(json_file_path, 'r', encoding='utf-8') as f:
                        json_data = f.read()

                    # Find the OBJ file name in the "model" field
                    obj_path_start = json_data.find("\"model\": ")
                    if obj_path_start != -1:
                        obj_name = json_data[obj_path_start:].split('"')[3].split('/')[-1]  # Extract OBJ file name
                        obj_file_path = os.path.join(directory, obj_name)  # Look for the OBJ in the same directory

                        if os.path.exists(obj_file_path):
                            print(f"Found OBJ file: {obj_file_path}")
                            # Find the associated MTL file
                            with open(obj_file_path, 'r', encoding='utf-8') as obj_file:
                                for line in obj_file:
                                    if line.startswith("mtllib"):
                                        mtl_file = line.split()[1]
                                        mtl_file_path = os.path.join(directory, mtl_file)  # Look for MTL in same directory

                                        if os.path.exists(mtl_file_path):
                                            print(f"Found MTL file: {mtl_file_path}")
                                            # Extract texture path from MTL
                                            texture_path = extract_texture_from_mtl(mtl_file_path)
                                            if texture_path:
                                                inject_texture_path(json_file_path, texture_path)
                                        else:
                                            print(f"MTL file not found: {mtl_file_path}")
                        else:
                            print(f"OBJ file not found: {obj_file_path}")
                    else:
                        print(f"No OBJ file reference found in {json_file_path}")
                except Exception as e:
                    print(f"Error processing JSON file {json_file_path}: {e}")

if __name__ == "__main__":
    # Use the current working directory as the resource pack path
    resource_pack_path = os.getcwd()

    print("Processing JSON files to inject texture paths...")
    process_json_files(resource_pack_path)
