require 'xcodeproj'
project_path = 'Whisper.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

models_group = project.main_group.find_subpath(File.join('Whisper', 'Models'), true)

file1 = models_group.new_reference('RecordingMode.swift')
file2 = models_group.new_reference('ShortcutModifier.swift')

target.add_file_references([file1, file2])

project.save
