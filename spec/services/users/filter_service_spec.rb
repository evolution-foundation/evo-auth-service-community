# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::FilterService do
  # The service resolves over the whole table, so every assertion is scoped to
  # the users the example itself created — otherwise a leftover row breaks them.
  let(:created_ids) { [] }

  def make_user(name:, availability: :online, confirmed: true, created_at: Time.current)
    User.create!(
      name: name,
      email: "#{name.parameterize}-#{SecureRandom.hex(3)}@example.com",
      password: 'Valid1!Pass',
      password_confirmation: 'Valid1!Pass',
      availability: availability,
      confirmed_at: confirmed ? Time.current : nil,
      created_at: created_at
    ).tap { |user| created_ids << user.id }
  end

  def assign_role(user, key)
    role = Role.find_by(key: key) || Role.create!(key: key, name: key.titleize, type: 'account', system: false)
    UserRole.assign_role_to_user(user, role)
  end

  def filter(attribute_key, operator, values, query_operator = 'and')
    {
      'attribute_key' => attribute_key,
      'filter_operator' => operator,
      'values' => values,
      'query_operator' => query_operator
    }
  end

  def resolve(*filters)
    mine(described_class.new(filters).resolve)
  end

  # Narrows a resolved relation to this example's own fixtures.
  def mine(relation)
    relation.where(id: created_ids).to_a
  end

  describe 'no filters' do
    it 'returns every user unfiltered' do
      alice = make_user(name: 'Alice')
      bob = make_user(name: 'Bob')

      expect(mine(described_class.new(nil).resolve)).to contain_exactly(alice, bob)
      expect(mine(described_class.new([]).resolve)).to contain_exactly(alice, bob)
    end
  end

  describe 'search (q)' do
    let!(:alice) { make_user(name: 'Alice Silva') }
    let!(:bob) { make_user(name: 'Bob Souza') }

    it 'matches name or email (case-insensitive)' do
      expect(mine(described_class.new(nil, 'SILVA').resolve)).to contain_exactly(alice)
    end

    it 'composes the search with filters (AND)' do
      assign_role(alice, 'agent')
      assign_role(bob, 'agent')

      result = mine(described_class.new([filter('role', 'equal_to', 'agent')], 'silva').resolve)
      expect(result).to contain_exactly(alice)
    end
  end

  describe 'text attributes (name)' do
    let!(:alice) { make_user(name: 'Alice Silva') }
    let!(:bob) { make_user(name: 'Bob Souza') }

    it 'filters by contains (case-insensitive)' do
      expect(resolve(filter('name', 'contains', 'SILVA'))).to contain_exactly(alice)
    end

    it 'filters by equal_to (case-insensitive)' do
      expect(resolve(filter('name', 'equal_to', 'alice silva'))).to contain_exactly(alice)
    end

    it 'filters by does_not_contain' do
      expect(resolve(filter('name', 'does_not_contain', 'silva'))).to contain_exactly(bob)
    end

    it 'filters by not_equal_to' do
      expect(resolve(filter('name', 'not_equal_to', 'Alice Silva'))).to contain_exactly(bob)
    end
  end

  describe 'role (via user_roles join)' do
    let!(:admin) { make_user(name: 'Admin') }
    let!(:agent) { make_user(name: 'Agent') }

    before do
      assign_role(admin, 'administrator')
      assign_role(agent, 'agent')
    end

    it 'matches equal_to a role key' do
      expect(resolve(filter('role', 'equal_to', 'administrator'))).to contain_exactly(admin)
    end

    it 'excludes with not_equal_to' do
      expect(resolve(filter('role', 'not_equal_to', 'administrator'))).to contain_exactly(agent)
    end
  end

  describe 'availability_status (enum)' do
    let!(:online) { make_user(name: 'On', availability: :online) }
    let!(:busy) { make_user(name: 'Busy', availability: :busy) }

    it 'matches the mapped enum integer' do
      expect(resolve(filter('availability_status', 'equal_to', 'busy'))).to contain_exactly(busy)
    end
  end

  describe 'confirmed (confirmed_at presence)' do
    let!(:confirmed) { make_user(name: 'Conf', confirmed: true) }
    let!(:pending) { make_user(name: 'Pend', confirmed: false) }

    it 'true matches confirmed users' do
      expect(resolve(filter('confirmed', 'equal_to', 'true'))).to contain_exactly(confirmed)
    end

    it 'false matches pending users' do
      expect(resolve(filter('confirmed', 'equal_to', 'false'))).to contain_exactly(pending)
    end
  end

  describe 'created_at' do
    let!(:old) { make_user(name: 'Old', created_at: Time.utc(2020, 1, 1, 12)) }
    let!(:recent) { make_user(name: 'Recent', created_at: Time.current) }

    it 'matches equal_to a date' do
      expect(resolve(filter('created_at', 'equal_to', '2020-01-01'))).to contain_exactly(old)
    end
  end

  describe 'query_operator across filters' do
    let!(:alice_admin) { make_user(name: 'Alice') }
    let!(:bob_agent) { make_user(name: 'Bob') }

    before do
      assign_role(alice_admin, 'administrator')
      assign_role(bob_agent, 'agent')
    end

    it 'AND narrows the result' do
      result = resolve(
        filter('name', 'contains', 'ali'),
        filter('role', 'equal_to', 'administrator', 'and')
      )
      expect(result).to contain_exactly(alice_admin)
    end

    it 'OR widens the result' do
      result = resolve(
        filter('name', 'equal_to', 'Alice'),
        filter('name', 'equal_to', 'Bob', 'or')
      )
      expect(result).to contain_exactly(alice_admin, bob_agent)
    end
  end

  describe 'robustness' do
    it 'ignores an unknown attribute_key (no leak, no crash)' do
      user = make_user(name: 'X')
      expect(mine(described_class.new([filter('password', 'contains', 'x')]).resolve)).to contain_exactly(user)
    end

    it 'ignores a value-requiring filter with blank values' do
      user = make_user(name: 'X')
      expect(mine(described_class.new([filter('name', 'contains', '')]).resolve)).to contain_exactly(user)
    end

    it 'ignores an unparseable created_at instead of blowing up the query' do
      user = make_user(name: 'X')

      expect { described_class.new([filter('created_at', 'equal_to', 'abc')]).resolve.load }
        .not_to raise_error
      expect(mine(described_class.new([filter('created_at', 'equal_to', 'abc')]).resolve)).to contain_exactly(user)
    end

    it 'treats ILIKE wildcards in the search term as literal characters' do
      literal = make_user(name: 'Discount 50% Off')
      make_user(name: 'Nothing To Do With It')

      expect(mine(described_class.new(nil, '50%').resolve)).to contain_exactly(literal)
    end

    it 'treats ILIKE wildcards in a contains filter as literal characters' do
      literal = make_user(name: 'a_b')
      make_user(name: 'axb')

      expect(resolve(filter('name', 'contains', 'a_b'))).to contain_exactly(literal)
    end
  end

  describe 'created_at day matching' do
    let!(:on_day) { make_user(name: 'OnDay', created_at: Time.utc(2026, 3, 10, 14, 30)) }
    let!(:next_day) { make_user(name: 'NextDay', created_at: Time.utc(2026, 3, 11, 0, 15)) }

    it 'equal_to matches the whole day, not just midnight' do
      expect(resolve(filter('created_at', 'equal_to', '2026-03-10'))).to contain_exactly(on_day)
    end

    it 'not_equal_to excludes exactly that day' do
      expect(resolve(filter('created_at', 'not_equal_to', '2026-03-10'))).to contain_exactly(next_day)
    end
  end

  describe 'availability negation with NULL rows' do
    let!(:online) { make_user(name: 'On', availability: :online) }
    let!(:unset) { make_user(name: 'Unset').tap { |user| user.update_column(:availability, nil) } }

    it 'equal_to leaves the NULL row out' do
      expect(resolve(filter('availability_status', 'equal_to', 'online'))).to contain_exactly(online)
    end

    it 'not_equal_to claims the NULL row' do
      expect(resolve(filter('availability_status', 'not_equal_to', 'online'))).to contain_exactly(unset)
    end
  end

  describe 'sort (order by)' do
    let!(:carol) { make_user(name: 'Carol', created_at: Time.utc(2020, 1, 1)) }
    let!(:alice) { make_user(name: 'Alice', created_at: Time.utc(2022, 1, 1)) }
    let!(:bob)   { make_user(name: 'Bob',   created_at: Time.utc(2021, 1, 1)) }

    def sorted(sort, order)
      mine(described_class.new(nil, nil, sort, order).resolve).map(&:name)
    end

    it 'defaults to name ascending when no sort is given (order_by_full_name parity)' do
      expect(sorted(nil, nil)).to eq(%w[Alice Bob Carol])
    end

    it 'sorts by name descending' do
      expect(sorted('name', 'desc')).to eq(%w[Carol Bob Alice])
    end

    it 'sorts by created_at descending (newest first)' do
      expect(sorted('created_at', 'desc')).to eq(%w[Alice Bob Carol])
    end

    it 'sorts by role name through the join, first-role-by-name per user' do
      assign_role(carol, 'admin')   # -> "Admin"
      assign_role(bob, 'manager')   # -> "Manager"
      assign_role(alice, 'zeta')    # -> "Zeta"

      expect(sorted('role', 'asc')).to eq(%w[Carol Bob Alice])
    end

    it 'falls back to name ascending for an unknown sort key' do
      expect(sorted('encrypted_password', 'asc')).to eq(%w[Alice Bob Carol])
    end

    it 'falls back to ascending for an unknown direction' do
      expect(sorted('name', 'sideways')).to eq(%w[Alice Bob Carol])
    end
  end

  describe 'preloading' do
    def queries_while
      queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        queries << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name])
      end
      yield
      queries
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    # role_data reads the role key to skip derived roles, so the role has to come
    # down with the list — otherwise every user costs an extra query per role.
    it 'resolves role_data without querying again' do
      3.times do |i|
        user = make_user(name: "Preload #{i}")
        assign_role(user, 'agent')
        assign_role(user, "evo_derived_#{user.id}_global")
      end

      users = mine(described_class.new([]).resolve)

      expect(queries_while { users.each(&:role_data) }).to be_empty
    end
  end
end
