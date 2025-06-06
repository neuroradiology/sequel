require_relative "spec_helper"

Sequel.extension :migration

describe "pg_enum extension" do
  mod = Module.new do
    private
    def schema_parse_table(*)
      [[:a, {:oid=>1, :type=>:enum}], [:b, {:oid=>1234}]]
    end
    def _metadata_dataset
      super.with_fetch([[{:v=>1, :enumlabel=>'a'}, {:v=>1, :enumlabel=>'b'}, {:v=>1, :enumlabel=>'c'}], [{:typname=>'enum1', :v=>212389, :sv=>212388}]])
    end
  end
  before do
    @db = Sequel.connect('mock://postgres')
    @db.extend_datasets{def quote_identifiers?; false end}
    @db.extend(mod)
    @db.extension(:pg_array, :pg_enum)
    @db.sqls
  end

  it "should parse enum labels respecting the sort order" do
    @db.send(:parse_enum_labels)
    @db.sqls.must_equal ["SELECT CAST(enumtypid AS integer) AS v, enumlabel FROM pg_enum ORDER BY enumtypid, enumsortorder",
      "SELECT typname, CAST(typarray AS integer) AS v, CAST(oid AS integer) AS sv FROM pg_type WHERE ((1 = 0) AND (typarray != 0))"]
  end

  it "should parse enum labels without the sort order on PostgreSQL < 9.1" do
    def @db.server_version(_=nil); 90000; end
    @db.send(:parse_enum_labels)
    @db.sqls.must_equal ["SELECT CAST(enumtypid AS integer) AS v, enumlabel FROM pg_enum ORDER BY enumtypid",
    "SELECT typname, CAST(typarray AS integer) AS v, CAST(oid AS integer) AS sv FROM pg_type WHERE ((1 = 0) AND (typarray != 0))"]
  end

  it "should add enum values to parsed schema columns" do
    @db.schema(:foo).must_equal [[:a, {:oid=>1, :ruby_default=>nil, :type=>:enum, :enum_values=>["a", "b", "c"]}], [:b, {:oid=>1234, :ruby_default=>nil}]]
  end

  it "should typecast objects to string" do
    @db.typecast_value(:enum, :a).must_equal 'a'
  end

  it "should add array parsers for enum values" do
    @db.conversion_procs[212389].call('{a,b,c}').must_equal %w'a b c'
  end

  it "should not add array parser if there is already a conversion proc" do
    @db = Sequel.connect('mock://postgres')
    @db.extend_datasets{def quote_identifiers?; false end}
    @db.extend(mod)
    pr = proc{}
    @db.conversion_procs[212389] = pr
    @db.extension(:pg_array, :pg_enum)
    @db.conversion_procs[212389].must_equal pr
    @db.sqls.must_equal ["SELECT CAST(enumtypid AS integer) AS v, enumlabel FROM pg_enum ORDER BY enumtypid, enumsortorder",
      "SELECT typname, CAST(typarray AS integer) AS v, CAST(oid AS integer) AS sv FROM pg_type WHERE ((oid IN (1)) AND (typarray != 0))"]
  end

  it "should not make individual queries for each array type" do
    @db = Sequel.connect('mock://postgres')
    @db.extend_datasets{def quote_identifiers?; false end}
    @db.extend(mod)
    @db.extension(:pg_array, :pg_enum)
    @db.sqls.must_equal ["SELECT CAST(enumtypid AS integer) AS v, enumlabel FROM pg_enum ORDER BY enumtypid, enumsortorder",
      "SELECT typname, CAST(typarray AS integer) AS v, CAST(oid AS integer) AS sv FROM pg_type WHERE ((oid IN (1)) AND (typarray != 0))"]
  end

  it "should not add array parsers for enum values if pg_array extension is not used" do
    @db = Sequel.connect('mock://postgres')
    @db.extend_datasets{def quote_identifiers?; false end}
    @db.extend(mod)
    @db.extension(:pg_enum)
    @db.conversion_procs[212389].must_be_nil
    @db.sqls.must_equal ["SELECT CAST(enumtypid AS integer) AS v, enumlabel FROM pg_enum ORDER BY enumtypid, enumsortorder"]
  end

  it "should support #create_enum method for adding a new enum" do
    @db.create_enum(:foo, [:a, :b, :c])
    @db.sqls.first.must_equal "CREATE TYPE foo AS ENUM ('a', 'b', 'c')"
    @db.create_enum(Sequel[:sch][:foo], %w'a b c')
    @db.sqls.first.must_equal "CREATE TYPE sch.foo AS ENUM ('a', 'b', 'c')"
  end

  with_symbol_splitting "should support #create_enum method for adding a new enum with qualified symbol" do
    @db.create_enum(:sch__foo, %w'a b c')
    @db.sqls.first.must_equal "CREATE TYPE sch.foo AS ENUM ('a', 'b', 'c')"
  end

  it "should support #rename_enum method for renameing an enum" do
    @db.rename_enum(:foo, :bar)
    @db.sqls.first.must_equal "ALTER TYPE foo RENAME TO bar"
    @db.rename_enum(Sequel[:sch][:foo], Sequel[:sch][:bar])
    @db.sqls.first.must_equal "ALTER TYPE sch.foo RENAME TO sch.bar"
  end

  it "should support #rename_enum_value method for renameing an enum value" do
    @db.rename_enum_value(:foo, :b, :x)
    @db.sqls.first.must_equal "ALTER TYPE foo RENAME VALUE 'b' TO 'x'"
  end

  it "should support #drop_enum method for dropping an enum" do
    @db.drop_enum(:foo)
    @db.sqls.first.must_equal "DROP TYPE foo"
    @db.drop_enum(Sequel[:sch][:foo], :if_exists=>true)
    @db.sqls.first.must_equal "DROP TYPE IF EXISTS sch.foo"
    @db.drop_enum('foo', :cascade=>true)
    @db.sqls.first.must_equal "DROP TYPE foo CASCADE"
  end

  with_symbol_splitting "should support #drop_enum method for dropping an enum with a splittable symbol" do
    @db.drop_enum(:sch__foo, :if_exists=>true)
    @db.sqls.first.must_equal "DROP TYPE IF EXISTS sch.foo"
  end

  it "should support #add_enum_value method for adding value to an existing enum" do
    @db.add_enum_value(:foo, :a)
    @db.sqls.first.must_equal "ALTER TYPE foo ADD VALUE 'a'"
  end

  it "should support :before option for #add_enum_value method for adding value before an existing enum value" do
    @db.add_enum_value('foo', :a, :before=>:b)
    @db.sqls.first.must_equal "ALTER TYPE foo ADD VALUE 'a' BEFORE 'b'"
  end

  it "should support :after option for #add_enum_value method for adding value after an existing enum value" do
    @db.add_enum_value(Sequel[:sch][:foo], :a, :after=>:b)
    @db.sqls.first.must_equal "ALTER TYPE sch.foo ADD VALUE 'a' AFTER 'b'"
  end

  with_symbol_splitting "should support :after option for #add_enum_value method for adding value after an existing enum value with splittable symbol" do
    @db.add_enum_value(:sch__foo, :a, :after=>:b)
    @db.sqls.first.must_equal "ALTER TYPE sch.foo ADD VALUE 'a' AFTER 'b'"
  end

  it "should support :if_not_exists option for #add_enum_value method for not adding the value if it exists" do
    @db.add_enum_value(:foo, :a, :if_not_exists=>true)
    @db.sqls.first.must_equal "ALTER TYPE foo ADD VALUE IF NOT EXISTS 'a'"
  end

  it "should reverse a create_enum directive in a migration" do
    m = Sequel.migration{change{create_enum(:type_name, %w'value1 value2 value3')}}
    m.apply(@db, :up)
    @db.sqls.must_equal ["CREATE TYPE type_name AS ENUM ('value1', 'value2', 'value3')",
      "SELECT CAST(enumtypid AS integer) AS v, enumlabel FROM pg_enum ORDER BY enumtypid, enumsortorder",
      "SELECT typname, CAST(typarray AS integer) AS v, CAST(oid AS integer) AS sv FROM pg_type WHERE ((1 = 0) AND (typarray != 0))"]
    m.apply(@db, :down)
    @db.sqls.must_equal ["DROP TYPE type_name", "SELECT CAST(enumtypid AS integer) AS v, enumlabel FROM pg_enum ORDER BY enumtypid, enumsortorder",
      "SELECT typname, CAST(typarray AS integer) AS v, CAST(oid AS integer) AS sv FROM pg_type WHERE ((1 = 0) AND (typarray != 0))"]
  end

  it "should reverse a rename_enum directive in a migration" do
    m = Sequel.migration{change{rename_enum(:old_type_name, :new_type_name)}}
    m.apply(@db, :up)
    @db.sqls.must_equal ["ALTER TYPE old_type_name RENAME TO new_type_name",
      "SELECT CAST(enumtypid AS integer) AS v, enumlabel FROM pg_enum ORDER BY enumtypid, enumsortorder",
      "SELECT typname, CAST(typarray AS integer) AS v, CAST(oid AS integer) AS sv FROM pg_type WHERE ((1 = 0) AND (typarray != 0))"]
    m.apply(@db, :down)
    @db.sqls.must_equal ["ALTER TYPE new_type_name RENAME TO old_type_name",
      "SELECT CAST(enumtypid AS integer) AS v, enumlabel FROM pg_enum ORDER BY enumtypid, enumsortorder",
      "SELECT typname, CAST(typarray AS integer) AS v, CAST(oid AS integer) AS sv FROM pg_type WHERE ((1 = 0) AND (typarray != 0))"]
  end
end
