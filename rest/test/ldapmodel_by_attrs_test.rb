
require_relative "./helper"

describe "LdapModel#by_attrs(hash)" do

  before(:each) do
    Puavo::Test.clean_up_ldap

    PuavoRest::Organisation.refresh
    LdapModel.setup(
      :credentials => {
        :dn => "uid=admin,o=puavo",
        :password => "password"
      },
      :organisation => PuavoRest::Organisation.default_organisation_domain!
    )

    @school_a = PuavoRest::School.new(
      :name => "School A",
      :abbreviation => "school_a"
    )
    @school_a.save!

    @school_b = PuavoRest::School.new(
      :name => "School B",
      :abbreviation => "school_b"
    )
    @school_b.save!

    @duplicate_group_a = PuavoRest::Group.new(
      :name => "Group",
      :abbreviation => "group",
      :school_dn => @school_a.dn
    )
    @duplicate_group_a.save!

    @duplicate_group_b = PuavoRest::Group.new(
      :name => "Group",
      :abbreviation => "group",
      :school_dn => @school_b.dn
    )
    @duplicate_group_b.save!


  end

  it "can find models by multi attribute filtering" do
    groups = PuavoRest::Group.by_attrs({
      :name => "Group",
      :school_dn => @school_a.dn
    }, :multiple => true)
    assert_equal 1, groups.size
  end

  it "with bang(!) raises NotFound if not found" do
    assert_raises LdapModel::NotFound do
      PuavoRest::Group.by_attrs!({
        :name => "Unknown",
        :school_dn => @school_a.dn
      })
    end
  end

end
