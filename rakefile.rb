task :default do
  sh "dfmt -i --brace_style otbs source/app.d"
  sh "dfmt -i --brace_style otbs source/srt.d"
end