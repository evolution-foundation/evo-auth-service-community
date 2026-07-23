# frozen_string_literal: true

# Applies the search term + advanced-filter payload sent by the Users list
# screen (`GET /users?q=...&filters[i][attribute_key|filter_operator|values|query_operator]`)
# to a User relation. Attribute keys are whitelisted (mapped to known columns or
# the roles association) and every value goes through bind parameters, so user
# input never reaches the SQL string — only the operator/column shape does.
#
# Mirrors the Contacts::FilterService contract from evo-ai-crm-community, scoped
# down to the six attributes the Users screen exposes; `q` is a free-text search
# across name/email and is AND-combined with the filters.
module Users
  class FilterService
    TEXT_ATTRIBUTES = %w[name email].freeze
    VALUE_OPERATORS = %w[equal_to not_equal_to contains does_not_contain].freeze

    def initialize(filters, search = nil)
      @filters = normalize(filters)
      @search = search.to_s.strip
    end

    def resolve
      relation = base_relation
      relation = apply_search(relation) if @search.present?
      return relation if @filters.empty?

      conditions = []
      binds = []

      @filters.each_with_index do |filter, index|
        fragment, fragment_binds = build_fragment(filter)
        next if fragment.nil?

        glue = index.zero? || conditions.empty? ? '' : "#{query_operator(filter)} "
        conditions << "#{glue}(#{fragment})"
        binds.concat(fragment_binds)
      end

      return relation if conditions.empty?

      relation.where(conditions.join(' '), *binds)
    end

    private

    def base_relation
      User.order_by_full_name.includes(:user_roles)
    end

    def apply_search(relation)
      relation.where('users.name ILIKE :term OR users.email ILIKE :term', term: "%#{like_escape(@search)}%")
    end

    # `%` and `_` are wildcards in ILIKE. A user searching for "50%" or "a_b"
    # means the literal characters, not "anything" — escape them so the search
    # box cannot silently degrade into a full-table match.
    def like_escape(value)
      ActiveRecord::Base.sanitize_sql_like(value.to_s)
    end

    def normalize(filters)
      list =
        if filters.respond_to?(:to_unsafe_h)
          filters.to_unsafe_h.sort_by { |key, _| key.to_i }.map(&:last)
        elsif filters.is_a?(Hash)
          filters.sort_by { |key, _| key.to_i }.map(&:last)
        else
          Array(filters)
        end

      list.filter_map { |entry| entry.respond_to?(:to_h) ? entry.to_h.stringify_keys : nil }
    end

    def query_operator(filter)
      filter['query_operator'].to_s.casecmp?('or') ? 'OR' : 'AND'
    end

    def values_for(filter)
      filter['values'].to_s.split(',').map(&:strip).reject(&:blank?)
    end

    def build_fragment(filter)
      operator = filter['filter_operator'].to_s
      values = values_for(filter)
      return nil if VALUE_OPERATORS.include?(operator) && values.empty?

      case filter['attribute_key'].to_s
      when *TEXT_ATTRIBUTES then text_fragment("users.#{filter['attribute_key']}", operator, values)
      when 'role' then role_fragment(operator, values)
      when 'availability_status' then availability_fragment(operator, values)
      when 'confirmed' then confirmed_fragment(operator, values)
      when 'created_at' then created_at_fragment(operator, values)
      end
    end

    def text_fragment(column, operator, values)
      case operator
      when 'equal_to' then ["LOWER(#{column}) = LOWER(?)", [values.first]]
      when 'not_equal_to' then ["#{column} IS NULL OR LOWER(#{column}) <> LOWER(?)", [values.first]]
      when 'contains' then ["#{column} ILIKE ?", ["%#{like_escape(values.first)}%"]]
      when 'does_not_contain' then ["#{column} IS NULL OR #{column} NOT ILIKE ?", ["%#{like_escape(values.first)}%"]]
      when 'is_present' then ["#{column} IS NOT NULL", []]
      when 'is_not_present' then ["#{column} IS NULL", []]
      end
    end

    def role_fragment(operator, values)
      exists = 'EXISTS (SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id ' \
               'WHERE ur.user_id = users.id AND r.key IN (?))'
      operator == 'not_equal_to' ? ["NOT (#{exists})", [values]] : [exists, [values]]
    end

    def availability_fragment(operator, values)
      ints = values.filter_map { |value| User.availabilities[value] }
      return nil if ints.empty?

      # `availability` is nullable (integer, default 0, no NOT NULL). A bare
      # `NOT IN` evaluates to NULL for those rows, so they would fall out of
      # BOTH "= online" and "<> online" — the negation must claim them, the way
      # the text fragments already do with `IS NULL OR ...`.
      if operator == 'not_equal_to'
        ['users.availability IS NULL OR users.availability NOT IN (?)', [ints]]
      else
        ['users.availability IN (?)', [ints]]
      end
    end

    def confirmed_fragment(operator, values)
      confirmed = values.first.to_s == 'true'
      confirmed = !confirmed if operator == 'not_equal_to'
      confirmed ? ['users.confirmed_at IS NOT NULL', []] : ['users.confirmed_at IS NULL', []]
    end

    def created_at_fragment(operator, values)
      case operator
      when 'is_present' then ['users.created_at IS NOT NULL', []]
      when 'is_not_present' then ['users.created_at IS NULL', []]
      when 'equal_to', 'not_equal_to' then created_at_day_fragment(operator, values.first)
      when 'contains' then ['users.created_at::text ILIKE ?', ["%#{like_escape(values.first)}%"]]
      when 'does_not_contain' then ['users.created_at::text NOT ILIKE ?', ["%#{like_escape(values.first)}%"]]
      end
    end

    # Matches a whole day as a half-open range instead of `DATE(created_at) = ?`.
    # Two reasons: an unparseable value ("abc") reached Postgres as a date cast
    # and blew the request up with a 500, and wrapping the column in DATE()
    # makes any index on created_at unusable. The range is built in the app's
    # Time.zone, so configuring a zone shifts the day boundaries with it.
    def created_at_day_fragment(operator, value)
      day = parse_day(value)
      return nil if day.nil?

      range = [day.beginning_of_day, day.next_day.beginning_of_day]
      if operator == 'not_equal_to'
        ['users.created_at IS NULL OR users.created_at < ? OR users.created_at >= ?', range]
      else
        ['users.created_at >= ? AND users.created_at < ?', range]
      end
    end

    def parse_day(value)
      Time.zone.parse(value.to_s)&.to_date
    rescue ArgumentError
      nil
    end
  end
end
