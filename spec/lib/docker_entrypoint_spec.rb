# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'

# CRM-216 — the entrypoint must not CREATE a database that already exists: the
# box connects as `evo_app`, NOCREATEDB by design, and the refused create aborted
# the boot of the whole stack. Runs the real script with `bundle` stubbed, so
# each Postgres behaviour is reproducible without a database.
RSpec.describe 'docker-entrypoint.sh' do
  # No Rails: this spec only shells out to bash, so it needs neither the app
  # environment nor a test database.
  def entrypoint
    File.expand_path('../../docker-entrypoint.sh', __dir__)
  end

  # Writes a fake `bundle` that logs every invocation and exits with the code
  # configured for the rails task being asked for.
  #
  # exit_codes: { 'db:version' => 1, 'db:create' => 1, ... } (default 0)
  def run_entrypoint(exit_codes: {}, env: {})
    Dir.mktmpdir do |dir|
      log = File.join(dir, 'calls.log')

      cases = exit_codes.map do |task, code|
        "    *#{task}*) exit #{code} ;;"
      end.join("\n")

      File.write(File.join(dir, 'bundle'), <<~SH)
        #!/usr/bin/env bash
        echo "$*" >> "#{log}"
        case "$*" in
        #{cases}
        esac
        exit 0
      SH
      FileUtils.chmod(0o755, File.join(dir, 'bundle'))

      # `sleep` is stubbed too: the retry loop waits 2s per attempt and the
      # failure paths burn all 30 of them.
      File.write(File.join(dir, 'sleep'), "#!/usr/bin/env bash\nexit 0\n")
      FileUtils.chmod(0o755, File.join(dir, 'sleep'))

      # RUN_MIGRATIONS is set in the container this suite runs in; without
      # clearing it the script would skip everything and every example would
      # pass vacuously.
      full_env = { 'PATH' => "#{dir}:#{ENV.fetch('PATH')}", 'RUN_MIGRATIONS' => nil }.merge(env)
      stdout, stderr, status = Open3.capture3(full_env, 'bash', entrypoint, 'true')

      calls = File.exist?(log) ? File.read(log).lines.map(&:strip) : []
      { calls: calls, stdout: stdout, stderr: stderr, status: status }
    end
  end

  def called?(result, task)
    result[:calls].any? { |c| c.include?(task) }
  end

  describe 'when the database already exists (the self-hosted box)' do
    it 'never attempts to create it' do
      # db:version succeeds => the database is reachable.
      result = run_entrypoint

      expect(called?(result, 'db:migrate')).to be(true)
      expect(called?(result, 'db:create')).to be(false),
                                             "db:create was attempted: #{result[:calls].inspect}"
      expect(result[:status]).to be_success
    end

    it 'boots even when the role cannot create databases at all' do
      # Reproduces evo_app: NOCREATEDB, so ANY db:create fails. The boot must
      # still succeed, because nothing needs creating.
      result = run_entrypoint(exit_codes: { 'db:create' => 1 })

      expect(result[:status]).to be_success
      expect(called?(result, 'db:create')).to be(false)
    end
  end

  describe 'when the database does not exist yet (fresh install)' do
    it 'creates it and then migrates' do
      # db:version fails once (no database), then the stub lets create/migrate pass.
      Dir.mktmpdir do |dir|
        log = File.join(dir, 'calls.log')
        state = File.join(dir, 'created')

        File.write(File.join(dir, 'bundle'), <<~SH)
          #!/usr/bin/env bash
          echo "$*" >> "#{log}"
          case "$*" in
            *db:version*) [ -f "#{state}" ] && exit 0 || exit 1 ;;
            *db:create*)  touch "#{state}"; exit 0 ;;
          esac
          exit 0
        SH
        FileUtils.chmod(0o755, File.join(dir, 'bundle'))
        File.write(File.join(dir, 'sleep'), "#!/usr/bin/env bash\nexit 0\n")
        FileUtils.chmod(0o755, File.join(dir, 'sleep'))

        _out, _err, status = Open3.capture3(
          { 'PATH' => "#{dir}:#{ENV.fetch('PATH')}", 'RUN_MIGRATIONS' => nil },
          'bash', entrypoint, 'true'
        )
        calls = File.read(log).lines.map(&:strip)

        expect(status).to be_success
        expect(calls.any? { |c| c.include?('db:create') }).to be(true)
        expect(calls.any? { |c| c.include?('db:migrate') }).to be(true)
      end
    end
  end

  describe 'when the database can neither be reached nor created' do
    it 'aborts instead of booting against an unknown schema' do
      result = run_entrypoint(exit_codes: { 'db:version' => 1, 'db:create' => 1 })

      expect(result[:status]).not_to be_success
      expect(result[:stderr]).to include('aborting boot')
    end

    it 'tells the operator that a NOCREATEDB role cannot be worked around' do
      # The original failure looked exactly like "Postgres is slow to start".
      # An operator who cannot tell those apart loses the install.
      result = run_entrypoint(exit_codes: { 'db:version' => 1, 'db:create' => 1 })

      expect(result[:stderr]).to include('NOCREATEDB')
      expect(result[:stderr]).to include('CREATEDB role')
      expect(result[:stderr]).to match(/owner does not grant it/i)
    end
  end

  describe 'the migration fail-safe (EVO-1999) still holds' do
    it 'aborts when migrations fail even though the database is reachable' do
      result = run_entrypoint(exit_codes: { 'db:migrate' => 1 })

      expect(result[:status]).not_to be_success
      expect(result[:stderr]).to include('aborting boot')
    end

    it 'skips everything when RUN_MIGRATIONS=false' do
      result = run_entrypoint(env: { 'RUN_MIGRATIONS' => 'false' })

      expect(result[:calls]).to be_empty
      expect(result[:status]).to be_success
    end

    it 'still migrates when RUN_MIGRATIONS is a malformed value' do
      # The gate compares against "false" precisely so a typo cannot silently
      # disable the fail-safe.
      result = run_entrypoint(env: { 'RUN_MIGRATIONS' => 'TRUE' })

      expect(called?(result, 'db:migrate')).to be(true)
    end
  end

  describe 'super_admin grant reconciliation' do
    it 'runs after the schema is up to date' do
      result = run_entrypoint

      migrate_at = result[:calls].index { |c| c.include?('db:migrate') }
      reconcile_at = result[:calls].index { |c| c.include?('rbac:reconcile_super_admin') }

      expect(reconcile_at).not_to be_nil
      expect(reconcile_at).to be > migrate_at
    end

    it 'does not abort the boot when it fails (degraded, not unsafe)' do
      result = run_entrypoint(exit_codes: { 'rbac:reconcile_super_admin' => 1 })

      expect(result[:status]).to be_success
      expect(result[:stderr]).to include('reconciliation FAILED')
    end
  end
end
