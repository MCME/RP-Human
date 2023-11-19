import os

def rename_files_in_work_folder():
    script_directory = os.path.dirname(os.path.abspath(__file__))
    work_folder = os.path.join(script_directory, "work")

    if not os.path.exists(work_folder) or not os.path.isdir(work_folder):
        print("The 'work' folder does not exist.")
        return

    replace_this = "brain_coral_fan"  # Specify the text to be replaced
    replace_with = "locked_powered_repeater_delay1_s"  # Specify the replacement text

    for filename in os.listdir(work_folder):
        old_path = os.path.join(work_folder, filename)
        new_filename = filename.replace(replace_this, replace_with)
        new_path = os.path.join(work_folder, new_filename)
        
        os.rename(old_path, new_path)
        print(f"Renamed: {filename} -> {new_filename}")

if __name__ == "__main__":
    rename_files_in_work_folder()
