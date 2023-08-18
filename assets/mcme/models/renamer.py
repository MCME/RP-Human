import os

def duplicate_and_replace(folder_path):
    for filename in os.listdir(folder_path):
        if filename.startswith('beech_leaves'):
            pine_file_path = os.path.join(folder_path, filename)
            maple_file_path = os.path.join(folder_path, filename.replace('beech_leaves', 'ash_leaves_yellowish'))

            # Duplicate the file
            with open(pine_file_path, 'r') as pine_file:
                pine_content = pine_file.read()
            with open(maple_file_path, 'w') as maple_file:
                maple_file.write(pine_content.replace('beech_leaves', 'ash_leaves_yellowish'))

            print(f'Duplicated and replaced: {filename} -> {filename.replace("beech_leaves", "ash_leaves_yellowish")}')

if __name__ == "__main__":
    script_directory = os.path.dirname(__file__)
    folder_name = "work"  # Replace with the name of your folder
    folder_path = os.path.join(script_directory, folder_name)
    duplicate_and_replace(folder_path)
