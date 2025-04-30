#! ruby

# deprecations.rb
#
# Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE

spec = `git -C sass status |head -1`.chomp

spec_deps = File.readlines('sass/spec/deprecations.yaml')
  .filter { it =~ /^[a-z]/ }
  .map { it.chomp ":\n" }
  .sort
  .map { [it, it.gsub(/-./) { it[1].upcase }] }


puts "        // Generated from sass version: #{spec}"
puts "        //"
spec_deps.each do |sass, swift|
  if swift == 'import'
    swift = '`import`'
  end
  anchor = sass.gsub('-','_')
  puts <<HERE
        /// [#{sass}](https://sass-lang.com/documentation/js-api/interfaces/deprecations/##{anchor})
        case #{swift} = "#{sass}"
HERE
end
