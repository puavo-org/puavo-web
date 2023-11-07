class ExternalServicesBase < ApplicationController
  # Make a list of all available external services. You have to filter the list
  # in the derived controller.
  before_action do
    @external_services = ExternalService.all.collect do |e|
      created = ExternalService.find(e.dn, :attributes => ['createTimestamp'])

      {
        org_level: false,     # filled in where needed
        name: e.cn,
        dn: e.dn.to_s,
        description: e.description,
        url: e.puavoServiceDescriptionURL,
        domains: Array(e.puavoServiceDomain),
        email: e.mail,
        prefix: e.puavoServicePathPrefix,
        created: created['createTimestamp'] ? Time.at(created['createTimestamp']).localtime.strftime('%Y-%m-%d %H:%M:%S') : nil,
        trusted: e.puavoServiceTrusted,
      }
    end
  end
end
