#!/usr/bin/env ruby
# Read .crew/config.yml, apply defaults, and print KEY=VALUE lines suitable for $GITHUB_ENV.
# Pass --json to print the resolved config as JSON instead (handy for local debugging).
require 'yaml'
require 'json'

path = ENV['CREW_CONFIG'] || '.crew/config.yml'
abort("crew: #{path} not found") unless File.exist?(path)
cfg = YAML.load_file(path) || {}

def dig(cfg, keys, default)
  v = keys.reduce(cfg) { |h, k| h.is_a?(Hash) ? h[k] : nil }
  v.nil? ? default : v
end

pm = dig(cfg, %w[commands package_manager], 'pnpm').to_s
default_install = { 'pnpm' => 'pnpm install --frozen-lockfile', 'npm' => 'npm ci', 'yarn' => 'yarn install --frozen-lockfile' }[pm] || "#{pm} install"

resolved = {
  'CREW_PROJECT'        => dig(cfg, %w[project name], ENV['GITHUB_REPOSITORY'].to_s),
  'CREW_OWNER'          => dig(cfg, %w[project owner], ENV['GITHUB_REPOSITORY_OWNER'].to_s),
  'CREW_MODEL'          => dig(cfg, %w[model], 'claude-sonnet-5'),
  'CREW_STANDARDS'      => dig(cfg, %w[standards_file], 'CLAUDE.md'),
  'CREW_GOALS'          => dig(cfg, %w[goals_file], '.crew/goals.md'),
  'CREW_SOURCES'        => dig(cfg, %w[sources_file], '.crew/sources.yml'),
  'CREW_NODE'           => dig(cfg, %w[node_version], '22'),
  'CREW_PM'             => pm,
  'CREW_PNPM_VERSION'   => dig(cfg, %w[commands pnpm_version], '10'),
  'CREW_INSTALL'        => dig(cfg, %w[commands install], default_install),
  'CREW_LINT'           => dig(cfg, %w[commands lint], "#{pm} run lint"),
  'CREW_TYPECHECK'      => dig(cfg, %w[commands typecheck], ''),
  'CREW_BUILD'          => dig(cfg, %w[commands build], "#{pm} run build"),
  'CREW_START'          => dig(cfg, %w[commands start], "#{pm} run start"),
  'CREW_PREVIEW_MODE'   => dig(cfg, %w[preview mode], 'local'),
  'CREW_PREVIEW_URL'    => dig(cfg, %w[preview url], 'http://localhost:3000'),
  'CREW_PROD_URL'       => dig(cfg, %w[production url], ''),
  'CREW_PAGES'          => JSON.generate(dig(cfg, %w[pages], ['/'])),
  'CREW_VIEWPORTS'      => JSON.generate(dig(cfg, %w[screenshots viewports], [
                             { 'name' => 'mobile', 'width' => 390, 'height' => 844 },
                             { 'name' => 'desktop', 'width' => 1440, 'height' => 900 }
                           ])),
  'CREW_SCHEMES'        => JSON.generate(dig(cfg, %w[screenshots color_schemes], %w[light dark])),
  'CREW_TZ'             => dig(cfg, %w[scout timezone], 'UTC'),
  'CREW_SCOUT_MAX'      => dig(cfg, %w[scout max_proposals], 5).to_s,
  'CREW_SCOUT_TRACKS'   => JSON.generate(dig(cfg, %w[scout tracks], { 'quality' => 2, 'feature' => 2, 'learn' => 2 })),
  'CREW_SCOUT_TURNS'    => dig(cfg, %w[limits scout_turns], 40).to_s,
  'CREW_APPROVER_TURNS' => dig(cfg, %w[limits approver_turns], 4).to_s,
  'CREW_CODER_TURNS'    => dig(cfg, %w[limits coder_turns], 60).to_s,
  'CREW_REVIEW_TURNS'   => dig(cfg, %w[limits reviewer_turns], 30).to_s,
  'CREW_MAX_SIZE'       => dig(cfg, %w[coder max_size], 'M'),
  'CREW_MAX_ROUNDS'     => dig(cfg, %w[coder max_fix_rounds], 3).to_s,
  'CREW_BRANCH_PREFIX'  => dig(cfg, %w[coder branch_prefix], 'crew/'),
  'CREW_ALLOW_DEPS'     => dig(cfg, %w[coder allow_new_dependencies], false).to_s,
  'CREW_COMMIT_AS_OWNER' => dig(cfg, %w[coder commit_as_owner], true).to_s,
  'CREW_PROTECTED'      => JSON.generate(dig(cfg, %w[coder protected_paths],
                             ['.github/**', '.crew/**', '.env*', '*.pem', '*.key']))
}

if ARGV.include?('--json')
  puts JSON.pretty_generate(resolved)
else
  resolved.each { |k, v| puts "#{k}=#{v.to_s.gsub(/\s*\n\s*/, ' ')}" }
end
