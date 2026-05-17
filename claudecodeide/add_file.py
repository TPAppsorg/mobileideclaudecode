import sys
from pbxproj import XcodeProject

project_path = 'claudecodeide.xcodeproj/project.pbxproj'
project = XcodeProject.load(project_path)

file_path = 'claudecodeide/Sources/Utilities/AgentReasoningParser.swift'

# Find the target
target = project.get_target_by_name('claudecodeide')
if not target:
    print("Target not found")
    sys.exit(1)

# Add the file to the project and target
project.add_file(file_path, force=False, target_name='claudecodeide')

project.save()
print("Added file successfully")
