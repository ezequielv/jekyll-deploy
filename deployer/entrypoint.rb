#!/usr/bin/env ruby
# frozen_string_literal: true

require 'English'
require 'fileutils'

def system_or_fail(*cmd)
  puts "executing #{cmd.inspect}"
  if system(*cmd)
    puts "executed #{cmd.inspect} successfully"
  else
    puts "execution failed with '#{$CHILD_STATUS}'"
    exit $CHILD_STATUS.exitstatus
  end
end

basedir = Dir.pwd

# TODO: implement with ideas from the following example (irb):
#  2.2.10 :175 >   [ 'dir2/20-file_20', 'dir1/30-file_30', 'dir1/10-file_10', 'startwm.sh', './bin/ev_grepf', '.bash_history', '.shrc.d/05-debug-start.sh' ].sort { | a, b | (File.basename a) <=> (FFileTest.exists?(v) && FileTest.executable?(v) ; }
#   => ["./bin/ev_grepf", "startwm.sh"]
#
#  2.2.10 :249 > [ 'dir2/20-file_20', 'dir1/30-file_30', 'dir1/10-file_10', 'startwm.sh', './bin/ev_grepf', '.bash_history', '.shrc.d/05-debug-start.sh' ].sort_by! { | a | File.basename a }.keep_if { | v | FileTest.exists?(v) && FileTest.executable?(v) ; }
#   => ["./bin/ev_grepf", "startwm.sh"]
#
# IDEA: call the hooks with a certain environment that is more independent from the one used here.
#  ENV['INPUT_SOURCE-DIR'] -> 'env JEKYLLDEPLOY_HOOKS_SOURCEDIR=... another_variable=... {hook program}'

INPUT_KEYVAL_SEPARATOR = ':='.freeze
INPUT_KEYVAL_END = ';'.freeze
INPUT_LIST_SEPARATOR = ','.freeze

HOOKS_SUBDIRS_DEFAULT = [
  '.jekyll-deploy/hooks',
  '.jekyll-deploy-hooks',
].freeze

HOOKS_MAPPINGS_DEFAULT = {
  :init_done => [
    'init.d',
  ],
  :bundle_config_post => [
    'bundle-config-post.d',
    'bundle-config-post',
  ],
  :build_post => [
    'build-post.d',
    'build-post',
  ],
}.freeze

# TODO: def input_to_map(src_str) -> (map)

# TODO: def merge_def_overrides(current, overrides) -> (returns updated 'current' object -- maybe it will need to support different types)
#  2.2.10 :220 > nil.is_a?({}.class)
#   => false
#  2.2.10 :221 > {:key1=>1}.is_a?({}.class)
#   => true
#
#  2.2.10 :231 > ENV['inexisting']
#   => nil
#  2.2.10 :232 > ENV['inexisting'].empty?
#  NoMethodError: undefined method `empty?' for nil:NilClass
#          from (irb):232
#          from /home/eze/.rvm/rubies/ruby-2.2.10/bin/irb:11:in `<main>'
#  2.2.10 :233 > ENV['inexisting'] || ''
#   => ""
#  2.2.10 :234 > (ENV['inexisting'] || '').empty?
#   => true

# initialisations possibly not needed (but 'rubocop' is not complaining).
$hooks_dirs = nil
$hooks_ids_dirs = nil

# default: uses '.to_s'
ENV_SETTING_MAP = {
    # TODO: implement lambda-style?: :envtype_bool => { | v |  ... }
}.freeze

def envval_normalised(v, typeid)
  if ENV_SETTING_MAP.has_key? typeid
    # TODO: evaluate ENV_SETTING_MAP[typeid]
    raise "envval_normalised(): FIXME: implement for typeid=#{typeid}"
  end
  return v.to_s
end

# (by default?) aborts the program on error
def run_hooks(hook_id)
  # TODO: transform input to make lists out of each "dictionary" element
  #  IDEA: format: 'key1' INPUT_KEYVAL_SEPARATOR 'val1_1' INPUT_LIST_SEPARATOR 'val1_2' INPUT_KEYVAL_END 'key2' INPUT_KEYVAL_SEPARATOR 'val2_1' (optional at the end: INPUT_KEYVAL_END)
  #   example with values above: 'key1:=val1_1,val1_2;key2:=val2_1'
  # ref: FileUtils.cp(File.join(basedir, '/.git/config'), '.git/config')
  if $hooks_dirs.nil? then
    # TODO: merge from configuration
    dirs = HOOKS_SUBDIRS_DEFAULT.clone
    # TODO: consider *both* basedir and sourcedir, and de-duplicate (as
    # 'sourcedir' can ultimately be the same as 'basedir') (and do it after
    # expansion, as symlinks can result in duplicated paths -- TODO: find out
    # how to do that)
    #  2.2.10 :432 > Pathname.new('.gitignore').realpath
    #   => #<Pathname:/home/eze/data/apps/git/config/configs/std_01/gitignore>
    #  2.2.10 :433 > Pathname.new('.gitignore').realpath.to_s
    #   => "/home/eze/data/apps/git/config/configs/std_01/gitignore"
    #  IDEA: put that functionality into a function deduplicate_paths_list!(l) -> l
    dirs = dirs.map { | p | File.absolute_path(p, basedir) }.keep_if { | p | FileTest.directory? p }
    # commit to global variable
    $hooks_dirs = dirs
  end

  if $hooks_ids_dirs.nil? then
    # TODO: merge from configuration
    $hooks_ids_dirs = HOOKS_MAPPINGS_DEFAULT.clone
  end

  # get list of existing directories for the allowed "leaf" directory names
  # TODO: de-duplicate (see comments above)
  hook_dirs = $hooks_dirs.map { | d |
    ($hooks_ids_dirs[hook_id] || []).map { | sub | File.absolute_path(sub, d) }
  }.flatten.keep_if { | p | FileTest.directory? p }
  puts "hook: #{hook_id}; dirs: #{hook_dirs}"

  # get hook files, sorted by basename
  hooks = hook_dirs.map { | d | Dir.glob(File.join(d, '*')) }.flatten.keep_if { | p |
    FileTest.file?(p) && FileTest.executable?(p)
  }.sort_by! { | p | File.basename p }
  puts " hook files to execute (in order):#{ hooks.empty? ? '(nothing)' : ''}"

  return false if hooks.empty?

  hooks.each { | p |
    puts "  #{p}"
  }

  # set environment variables
  env_hash = {
    'JEKYLLDEPLOY_HOOKS_HOOK_ID' => [ hook_id.to_s, :envtype_string ],
    'JEKYLLDEPLOY_HOOKS_ADJUST_LAST_MODIFIED' => [ ENV['INPUT_ADJUST-LAST-MODIFIED'], :envtype_bool ],
    'JEKYLLDEPLOY_HOOKS_BUILD_ONLY' => [ ENV['INPUT_BUILD-ONLY'], :envtype_bool ],
    'JEKYLLDEPLOY_HOOKS_TARGET_BRANCH' => [ ENV['INPUT_TARGET-BRANCH'], :envtype_string ],
    'JEKYLLDEPLOY_HOOKS_BASE_DIR' => [ basedir, :envtype_string ],
    #? 'JEKYLLDEPLOY_HOOKS_SOURCE_DIR' => [ ENV['INPUT_SOURCE-DIR'], :envtype_string ],
    'JEKYLLDEPLOY_HOOKS_SOURCE_DIR' => [ sourcedir, :envtype_string ],
  }
  puts " setting environment variable values:"
  #? prev: v1: env_hash.each_pair { | k, e |
  #? prev: v1:   v = envval_normalised(e[0], e[1]) # TODO: implement
  #? prev: v1: ... }
  #? prev: v2: env_hash.keys.sort!.each { | k |
  #? prev: v2:   e = env_hash[k]
  # done: use ideas from this:
  #  2.2.10 :398 > Array({:key1 => 'val1', :key0 => 'zzz', :key2 => {:key1 => 'val2_1', :key2 => 'val2_2'}}.merge({:key2 => {:key2 => 'val2_2-b', :key3 => 'val2_3-b'}}).each_pair).sort_by! { |p| p[0] }.each { |e| puts "#{e}" }
  #  [:key0, "zzz"]
  #  [:key1, "val1"]
  #  [:key2, {:key2=>"val2_2-b", :key3=>"val2_3-b"}]
  #   => [[:key0, "zzz"], [:key1, "val1"], [:key2, {:key2=>"val2_2-b", :key3=>"val2_3-b"}]]
  # NOTE: sorted by variable name so it's "friendlier" (and more consistent)
  Array(env_hash.each_pair).sort_by! { | p | p[0] }.each { | p |
    k, e = [ p[0], p[1] ]
    v = envval_normalised(e[0], e[1]) # TODO: implement
    ENV[k] = v
    puts "  #{k}=#{v}"
  }

  puts " about to run hooks:"
  hooks.each { | p | system_or_fail(p, hook_id.to_s) }
  return true
end

if ENV['INPUT_ADJUST-LAST-MODIFIED'] == "true"
  # help jekyll with stable last modified times to avoid churning timestamps
  puts "Adjusting mtime/last modified times"
  system_or_fail('git', 'restore-mtime', '--merge', ENV['INPUT_SOURCE-DIR'])
else
  puts "Adjusting mtime/last modified times disabled in config"
end

Dir.chdir(ENV['INPUT_SOURCE-DIR'])
sourcedir = Dir.pwd

run_hooks(:init_done)

run_hooks(:bundle_config_pre)

system_or_fail('bundle', 'config', 'set', 'path', 'vendor/gems')
system_or_fail('bundle', 'config', 'set', 'deployment', 'true')

run_hooks(:bundle_config_post)

# TODO: add support for arbitrary options (pre-command, post-command)
#  IDEA: system_or_fail((['bundle', ] + pre_cmd + ['install', '--jobs=4', '--retry=3'] + post_cmd).keep_if { |v| ! v.empty? })
#   MAYBE: split (env var input) elements using the INPUT_LIST_SEPARATOR constant
#   IDEA: or just filter args through another function: system_or_fail_filtered(*l)
system_or_fail('bundle', 'install', '--jobs=4', '--retry=3')

run_hooks(:bundle_packages_installed)

run_hooks(:packages_installed)

run_hooks(:build_pre)

# NOTE: see comments below on how to slightly refactor this
if ENV['INPUT_BUILD-ONLY'] == "true"
  system_or_fail('bundle', 'exec', 'jekyll', 'build', '--future', '--verbose', '--trace')
  run_hooks(:build_post)
  exit
else
  system_or_fail('bundle', 'exec', 'jekyll', 'build', '--verbose', '--trace')
  run_hooks(:build_post)
end

# TODO: put '_site' in a variable
#  TODO: write the '.nojekyll' file first (using the dir variable set above) (unconditionally -> minor refactoring, so we can test every step before the actual git operations)
Dir.chdir('_site')
File.open('.nojekyll', 'w') { |f| f.puts 'Skip Jekyll' }

system_or_fail('git', 'init', '.')
FileUtils.cp(File.join(basedir, '/.git/config'), '.git/config')
system_or_fail('git', 'config', 'user.name', ENV['GITHUB_ACTOR'])
system_or_fail('git', 'config', 'user.email', "#{ENV['GITHUB_ACTOR']}@users.noreply.github.com")
system_or_fail('git', 'fetch', '--no-tags', '--no-recurse-submodules', 'origin', "+#{ENV['GITHUB_SHA']}:refs/remotes/origin/source")
if %x(git ls-remote --heads origin) =~ %r{\trefs/heads/#{ENV['INPUT_TARGET-BRANCH']}\n}
  puts "Found target branch '#{ENV['INPUT_TARGET-BRANCH']}', using that as base"
  system_or_fail('git', 'fetch', '--no-tags', '--no-recurse-submodules', 'origin', "+#{ENV['INPUT_TARGET-BRANCH']}:refs/remotes/origin/#{ENV['INPUT_TARGET-BRANCH']}")
  system_or_fail('git', 'reset', '--soft', "origin/#{ENV['INPUT_TARGET-BRANCH']}")
else
  puts "Didn't find target branch '#{ENV['INPUT_TARGET-BRANCH']}', using the source as a base"
  system_or_fail('git', 'reset', '--soft', "origin/source")
end

if File.exist?(File.join(sourcedir, 'CNAME')) && !File.exist?('CNAME')
  puts "Rendering github's CNAME file"
  FileUtils.cp(File.join(sourcedir, 'CNAME'), 'CNAME')
end

system_or_fail('git', 'add', '-A', '.')
system_or_fail('git', 'commit', '-m', 'Update github pages')
system_or_fail('git', 'merge', '-s', 'ours', 'origin/source')
system_or_fail('git', 'push', 'origin', "HEAD:#{ENV['INPUT_TARGET-BRANCH']}")

puts "triggering a github pages deploy"

require 'net/http'
result = Net::HTTP.post(
  URI("https://api.github.com/repos/#{ENV['GITHUB_REPOSITORY']}/pages/builds"),
  "",
  "Content-Type" => "application/json",
  "Authorization" => "token #{ENV['GH_PAGES_TOKEN']}",
)

puts result.body
