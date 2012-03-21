class Course < LdapBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Courses",
                :classes => ['puavoCourse'] )

  before_validation :set_puavoId

  after_create :webhook_create

  def set_puavoId
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
  end

  def id
    self.puavoId.to_s unless puavoId.nil?
  end

  def to_json(*args)
    { "name" => self.puavoCourseName,
      "course_id" => self.puavoCourseId,
      "description" => self.puavoCourseDescription,
      "puavo_id" => self.puavoId.to_s }.to_json
  end

  private

  def webhook_create
    webhook("create")
  end
  def webhook_update
    webhook("update")
  end
  def webhook_destroy
    webhook("destroy")
  end

  def webhook(action)
    organisation = LdapOrganisation.first.cn.to_s
    config = Puavo::Organisation.find( organisation )
    if webhook_config = config.value_by_key("webhooks")
      if webhook_config.has_key?("course")
        if webhook_config["course"]["actions"].to_a.include?(action)
          payload = ({ :course => self,
                       :action => action,
                       :organisation => organisation }).to_json
          hexdigest = HMAC::SHA1.hexdigest( webhook_config["private_api_key"],
                                            payload )
          RestClient.post( webhook_config["course"]["url"],
                           { :payload => payload,
                             :hmac => hexdigest },
                           :content_type => :json,
                           :accept => :json) 
        end
      end
    end
  end
end
