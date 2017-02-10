require_relative 'db_connection'
require 'active_support/inflector'
# NB: the attr_accessor we wrote in phase 0 is NOT used in the rest
# of this project. It was only a warm up.

class SQLObject
  attr_reader :table_name

  def self.columns
    if @column_names.nil?
      columns = DBConnection.execute2(<<-SQL)
        SELECT
          *
        FROM
          #{self.table_name}
        SQL

      @column_names = columns.first.map(&:to_sym)
    end

    @column_names
  end

  def self.finalize!
    columns.each do |col|
      define_method col do
        attributes[col]
      end

      define_method "#{col}=" do |val|
        attributes[col] = val
      end
    end
  end

  def self.table_name=(table_name)
    @table_name = table_name
  end

  def self.table_name
    @table_name ||= self.name.tableize
  end

  def self.all
    parse_all DBConnection.execute(<<-SQL)
      SELECT
        *
      FROM
        #{table_name}
    SQL
  end

  def self.parse_all(results)
    results.map { |args| self.new(args) }
  end

  def self.find(id)
    result = DBConnection.execute(<<-SQL, id)
      SELECT
        *
      FROM
        #{table_name}
      WHERE
        id = ?
    SQL

    return nil if result.length < 1

    parse_all(result).first
  end

  def initialize(params = {})
    params.each do |key, value|
      attr_name = key.to_sym

      unless self.class.columns.include?(attr_name)
        raise "unknown attribute '#{attr_name}'"
      end

      send("#{attr_name}=", value)
    end
  end

  def attributes
    @attributes ||= {}
  end

  def attribute_values
    self.class.columns.map { |attr_name| send(attr_name.to_sym) }
  end

  def insert
    col_names = self.class.columns.join(", ")
    question_marks = ( ["?"] * self.class.columns.length ).join(", ")
    DBConnection.execute(<<-SQL, *attribute_values)
      INSERT INTO
        #{self.class.table_name} (#{col_names})
      VALUES
        (#{question_marks})
    SQL

    self.id = DBConnection.last_insert_row_id
  end

  def update
    set_line = self.class.columns
                .map { |attr_name| "#{attr_name} = ?" }.join(", ")
    DBConnection.execute(<<-SQL, *attribute_values, self.id)
      UPDATE
        #{self.class.table_name}
      SET
        #{set_line}
      WHERE
        id = ?
    SQL
  end

  def save
    self.id.nil? ? self.insert : self.update
  end
end
