require 'xcodeproj'

project_path = 'ECHO-macOS-App.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'ECHO-macOS-App' }

services_group = project.main_group.find_subpath('ECHO-macOS-App/Services', false)

old_file = services_group.files.find { |f| f.path == 'LLMService.swift' }
if old_file
  old_file.remove_from_project
end

new_file = services_group.files.find { |f| f.path == 'NativeLLMService.swift' }
unless new_file
  new_file = services_group.new_file('NativeLLMService.swift')
end

unless target.source_build_phase.files_references.include?(new_file)
  target.source_build_phase.add_file_reference(new_file)
end

project.save
puts "Successfully updated Xcode project!"
