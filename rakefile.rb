def format
  "dfmt -i --brace_style otbs --align_switch_statements=false"
end
task :default do
  sh "#{format} source/app.d"
  sh "#{format} source/srt.d"
end
