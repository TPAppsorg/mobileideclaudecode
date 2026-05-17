require 'xcodeproj'
project_path = 'claudecodeide.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

group = project.main_group.find_subpath(File.join('claudecodeide', 'Sources', 'Utilities'), true)
group.set_source_tree('<group>')

file_path = File.join('claudecodeide', 'Sources', 'Utilities', 'AgentReasoningParser.swift')
file_ref = group.new_reference(file_path)

target.add_file_references([file_ref])

project.save
