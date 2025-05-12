module FormUtility
  # Applies per-organisation customisations to the content, if any
  def customise_form(content, org_name)
    begin
      # Any per-organisation login screen customisations?
      customisations = ORGANISATIONS[org_name]['login_screen']
      customisations = {} unless customisations.class == Hash
    rescue StandardError => e
      customisations = {}
    end

    unless customisations.empty?
      rlog.info("Organisation \"#{org_name}\" has login screen customisations enabled")
    end

    # Apply per-customer customisations
    if customisations.include?('css')
      content['css'] = customisations['css']
    end

    if customisations.include?('upper_logos')
      content['upper_logos'] = customisations['upper_logos']
    end

    if customisations.include?('header_text')
      content['header_text'] = customisations['header_text']
    end

    if customisations.include?('service_title_override')
      content['service_title_override'] = customisations['service_title_override']
    end

    if customisations.include?('lower_logos')
      content['lower_logos'] = customisations['lower_logos']
    end
  end
end
