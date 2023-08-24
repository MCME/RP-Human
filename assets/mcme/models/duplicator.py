import os

def duplicate_and_replace(folder_path):
    for filename in os.listdir(folder_path):
        if filename.startswith('birch_twig_branch'):
            pine_file_path = os.path.join(folder_path, filename)
            maple_file_path = os.path.join(folder_path, filename.replace('birch_twig_branch', 'birch_twig_branch_down'))

            # Duplicate the file
            with open(pine_file_path, 'r') as pine_file:
                pine_content = pine_file.read()
            with open(maple_file_path, 'w') as maple_file:
                maple_file.write(pine_content.replace('birch_twig_branch', 'birch_twig_branch_down'))

            print(f'Duplicated and replaced: {filename} -> {filename.replace("birch_twig_branch", "birch_twig_branch_down")}')

if __name__ == "__main__":
    script_directory = os.path.dirname(__file__)
    folder_name = "work"  # Replace with the name of your folder
    folder_path = os.path.join(script_directory, folder_name)
    duplicate_and_replace(folder_path)
