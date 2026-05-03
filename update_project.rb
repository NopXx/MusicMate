require 'yaml'
data = YAML.load_file('project.yml')
data['packages']['MediaRemoteAdapter']['version'] = '0.1.0'
File.write('project.yml', YAML.dump(data))
