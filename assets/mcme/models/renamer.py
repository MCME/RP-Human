import os

def duplicate_and_replace(folder_path):
    for filename in os.listdir(folder_path):
        if filename.startswith('poplar'):
            spruce_file_path = os.path.join(folder_path, filename)
            maple_file_path = os.path.join(folder_path, filename.replace('poplar', 'whitebeam'))

            # Duplicate the file
            with open(spruce_file_path, 'r') as spruce_file:
                spruce_content = spruce_file.read()
            with open(maple_file_path, 'w') as maple_file:
                maple_file.write(spruce_content.replace('poplar', 'whitebeam'))

            print(f'Duplicated and replaced: {filename} -> {filename.replace("poplar", "whitebeam")}')

if __name__ == "__main__":
    script_directory = os.path.dirname(__file__)
    folder_name = "work"  # Replace with the name of your folder
    folder_path = os.path.join(script_directory, folder_name)
    duplicate_and_replace(folder_path)
