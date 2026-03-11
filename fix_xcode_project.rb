require 'xcodeproj'

project_path = 'Whisper.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

models_group = project.main_group.find_subpath(File.join('Whisper', 'Models'), true)
views_group = project.main_group.find_subpath(File.join('Whisper', 'Views'), true)

# Remove ShortcutModifier.swift
models_group.files.each do |file|
  if file.path == 'ShortcutModifier.swift'
    file.remove_from_project
  end
end

# Add AppShortcut.swift
file_app_shortcut = models_group.new_file('AppShortcut.swift')

# Add ShortcutRecordingView.swift
file_recording_view = views_group.new_file('ShortcutRecordingView.swift')

# Add files to the target
target.add_file_references([file_app_shortcut, file_recording_view])

project.save
puts "Xcode project successfully updated."
