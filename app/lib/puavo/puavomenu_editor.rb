# Puavomenu Editor helpers

# I wanted to put this in its own controller, and that's what I did. Except it didn't work
# very well with the tabs at the top of the page. Multi-controller setups are... hairy.

module Puavo
  module PuavomenuEditor
    # The editor is an experimental feature that will be enabled in
    # selected test organisations first
    def puavomenu_editing_enabled?
      begin
        Puavo::Organisation.find(LdapOrganisation.current.cn).value_by_key('enable_puavomenu_editor') || false
      rescue StandardError => e
        # Fail safe. One place that can cause exceptions here is the login screen, when there is
        # no "current" organisation yet.
        false
      end
    end

    def make_puavomenu_preview(data)
      if data
        data = JSON.parse(data)

        @puavomenu_data = {
          categories: data.fetch('categories', {}).keys,
          menus: data.fetch('menus', {}).keys,
          programs: data.fetch('programs', {}).keys
        }

        @puavomenu_data.delete_if { |k, v| v.nil? || v.empty? }
      end
    end

    def load_menudata(source)
      return {} if source.nil?

      begin
        JSON.parse(source)
      rescue StandardError => e
        logger.error("load_menudata: can't parse menudata JSON: #{e}")
        logger.error(source.inspect)
        {}
      end
    end

    # AJAX call
    def save_menudata(&block)
      response = {
        success: true,
        message: nil,
        redirect: nil,
      }

      begin
        menudata = JSON.parse(request.body.read)

        if block.call(menudata, response)
          # This message will be seen after the redirect
          flash[:notice] = t('flash.puavomenu_editor.saved')
        end
      rescue StandardError => e
        logger.error("save_menudata(): save failed: #{e}")

        response[:success] = false
        response[:message] = e.to_s
      end

      render json: response
    end

    def get_conditions
      begin
        JSON.parse(File.read(File.join(Rails.root, 'config', 'puavomenu_editor_conditions.json'))).keys
      rescue
        []
      end
    end
  end
end
