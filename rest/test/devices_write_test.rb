require_relative "./helper"

describe PuavoRest::Devices do

  before(:each) do
    Puavo::Test.clean_up_ldap
    setup_ldap_admin_connection()

    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoDeviceImage => "schoolprefimage",
      :puavoPersonalDevice => true,
      :puavoSchoolHomePageURL => "schoolhomepagefordevice.example",
      :puavoAllowGuest => true,
      :puavoAutomaticImageUpdates => true,
      :puavoImageSeriesSourceURL => "https://foobar.puavo.net/schoolpref.json",
      :puavoLocale => "fi_FI.UTF-8",
      :puavoTag => ["schooltag"],
      :puavoMountpoint => [ '{"fs":"nfs3","path":"10.0.0.3/share","mountpoint":"/home/school/share","options":"-o r"}',
                            '{"fs":"nfs4","path":"10.5.5.3/share","mountpoint":"/home/school/public","options":"-o r"}' ]
    )

    @group = PuavoRest::Group.new(
      :abbreviation => 'group1',
      :name         => 'Group 1',
      :school_dn    => @school.dn.to_s,
      :type         => 'teaching group')
    @group.save!

    maintenance_group = Group.find(:first,
                                   :attribute => 'cn',
                                   :value     => 'maintenance')
    @user = PuavoRest::User.new(
      :email          => 'bob@example.com',
      :first_name     => 'Bob',
      :last_name      => 'Brown',
      :locale         => 'en_US.UTF-8',
      :password       => 'secret',
      :roles          => [ 'student' ],
      :school_dns     => [ @school.dn.to_s ],
      :ssh_public_key => 'asdfsdfdfsdfwersSSH_PUBLIC_KEYfdsasdfasdfadf',
      :username       => 'bob',
    )
    @user.save!

    # XXX weird that these must be here
    @user.administrative_groups = [ maintenance_group.id ]
    @user.teaching_group = @group

    @laptop = create_device(
      :puavoHostname => "laptop1",
      :puavoDeviceType =>  "laptop",
      :macAddress => "00:60:2f:28:DC:51",
      :puavoSchool => @school.dn
    )
    @laptop.save!

  end

  describe "POST /v3/devices/:hostname" do
    it "can update graphics_driver"  do
      # XXX Use device dn and pw
      basic_authorize "cucumber", "cucumber"
      post "/v3/devices/laptop1", { "graphics_driver" => "foo" }
      assert_200

      get "/v3/devices/laptop1"
      assert_200
      data = JSON.parse last_response.body
      assert_equal "foo", data["graphics_driver"]
    end

    describe "can modify primary_user attribute" do
      before(:each) do
        # XXX Use device dn and pw
        basic_authorize "cucumber", "cucumber"
        post "/v3/devices/laptop1", { "primary_user" => "bob" }
        assert_200

      end

      it "and it was updated" do
        get "/v3/devices/laptop1"
        assert_200
        data = JSON.parse last_response.body
        assert_equal "bob", data["primary_user"]
      end

      it "by setting it to nil" do
        basic_authorize "cucumber", "cucumber"
        post "/v3/devices/laptop1", { "primary_user" => nil }
        assert_200

        get "/v3/devices/laptop1"
        assert_200
        data = JSON.parse last_response.body
        assert_nil data["primary_user"]
      end

    end
  end
end
