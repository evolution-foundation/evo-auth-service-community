# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20250819224900_init_schema.rb')

# Regression guard for the `add_fk_if_missing` / `column_type_incompatible?`
# helpers in the consolidated init migration. Those helpers exist to keep
# legacy installs (where `users.id` is still `integer` instead of `bigint`)
# from blowing up the migration with a PG type-mismatch when the FK is
# added. The bug they prevent only surfaces on real legacy DBs, so without
# this isolated spec a refactor that drops the type check would pass CI and
# only break weeks later when an operator upgrades. EVO-1404 covered the
# real-DB path via AC4; this spec covers the code path itself.
RSpec.describe InitSchema do
  let(:migration) { described_class.new }
  # `foreign_key_exists?` and `add_foreign_key` are delegated through
  # ActiveRecord::Migration#method_missing to the underlying connection
  # adapter, so we stub them on the connection double rather than on the
  # migration instance (verify_partial_doubles rejects stubs for methods
  # not directly defined on the receiver).
  let(:connection) { double('connection') }

  before do
    allow(migration).to receive(:connection).and_return(connection)
    allow(migration).to receive(:say)
  end

  def column_double(name, type)
    instance_double(ActiveRecord::ConnectionAdapters::Column, name: name, type: type)
  end

  describe '#add_fk_if_missing' do
    # Note: ActiveRecord::Migration#method_missing routes DDL inquiries through
    # `proper_table_name`, which stringifies the leading table-name argument(s)
    # before delegating to the connection. The expectations below mirror that
    # — `:posts`/`:users` become `"posts"`/`"users"` by the time they reach
    # the connection double.
    context 'when the FK already exists' do
      it 'returns early without inspecting column types or calling add_foreign_key' do
        allow(connection).to receive(:foreign_key_exists?)
          .with('posts', :users, column: :user_id).and_return(true)

        expect(connection).not_to receive(:columns)
        expect(connection).not_to receive(:add_foreign_key)

        migration.send(:add_fk_if_missing, :posts, :users, :user_id)
      end
    end

    context 'when the FK is missing and column types match' do
      it 'calls add_foreign_key' do
        allow(connection).to receive(:foreign_key_exists?).and_return(false)
        allow(connection).to receive(:columns).with(:posts)
          .and_return([column_double('user_id', :bigint)])
        allow(connection).to receive(:columns).with(:users)
          .and_return([column_double('id', :bigint)])

        expect(connection).to receive(:add_foreign_key)
          .with('posts', :users, column: :user_id, if_not_exists: true)

        migration.send(:add_fk_if_missing, :posts, :users, :user_id)
      end
    end

    context 'when the FK is missing and column types are incompatible (legacy integer ↔ bigint)' do
      it 'emits the exact skip message and does NOT call add_foreign_key' do
        allow(connection).to receive(:foreign_key_exists?).and_return(false)
        allow(connection).to receive(:columns).with(:posts)
          .and_return([column_double('user_id', :integer)])
        allow(connection).to receive(:columns).with(:users)
          .and_return([column_double('id', :bigint)])

        expected_message = 'Skipping FK posts.user_id → users.id: ' \
                           'type mismatch, integrity must be enforced at application level'
        expect(migration).to receive(:say).with(expected_message)
        expect(connection).not_to receive(:add_foreign_key)

        migration.send(:add_fk_if_missing, :posts, :users, :user_id)
      end
    end
  end

  describe '#column_type_incompatible?' do
    it 'returns false when from-column type matches target PK type' do
      allow(connection).to receive(:columns).with(:posts)
        .and_return([column_double('user_id', :bigint)])
      allow(connection).to receive(:columns).with(:users)
        .and_return([column_double('id', :bigint)])

      expect(migration.send(:column_type_incompatible?, :posts, :user_id, :users)).to be false
    end

    it 'returns true when from-column type differs from target PK type' do
      allow(connection).to receive(:columns).with(:posts)
        .and_return([column_double('user_id', :integer)])
      allow(connection).to receive(:columns).with(:users)
        .and_return([column_double('id', :bigint)])

      expect(migration.send(:column_type_incompatible?, :posts, :user_id, :users)).to be true
    end

    it 'returns false when the from-column is not present (fail-open: let add_foreign_key surface the error)' do
      allow(connection).to receive(:columns).with(:posts).and_return([])
      allow(connection).to receive(:columns).with(:users)
        .and_return([column_double('id', :bigint)])

      expect(migration.send(:column_type_incompatible?, :posts, :user_id, :users)).to be false
    end

    it 'returns false when the target PK column is not present' do
      allow(connection).to receive(:columns).with(:posts)
        .and_return([column_double('user_id', :integer)])
      allow(connection).to receive(:columns).with(:users).and_return([])

      expect(migration.send(:column_type_incompatible?, :posts, :user_id, :users)).to be false
    end
  end
end
