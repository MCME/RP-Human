import os
import shutil

def replace_text_in_file(file_path, old_text, new_text):
    with open(file_path, 'r', encoding='utf-8') as file:
        content = file.read()
    
    content = content.replace(old_text, new_text)
    
    with open(file_path, 'w', encoding='utf-8') as file:
        file.write(content)

def duplicate_and_replace(old_text, new_text_list):
    for file_name in os.listdir('.'):
        if file_name.endswith(('.json', '.mtl', '.objmeta')):
            for new_text in new_text_list:
                new_file_name = file_name.replace(old_text, new_text)

                # Skip if the new file name is the same as the original
                if new_file_name == file_name:
                    continue
                
                new_file_path = os.path.join('.', new_file_name)

                # Copy file with new name
                shutil.copy2(file_name, new_file_path)

                # Replace content inside the new file with its corresponding new_text
                replace_text_in_file(new_file_path, old_text, new_text)
                
                print(f"Duplicated and modified: {new_file_name}")

if __name__ == "__main__":
    old_text = "oak"
    new_text_list = ["pine", "ash", "chestnut", "elm", "whitebeam", "birch", "maple", "beech", "poplar", "larch", "spruce"]  # Set your replacement words here
    
    duplicate_and_replace(old_text, new_text_list)
