module Puavo
  module Locale

    private

    def set_preferred_language
      language = nil
      if self.puavoLocale && !self.puavoLocale.empty?
        language = self.puavoLocale.match(/^[a-z]{2}/)[0]
      end
      self.preferredLanguage = language
    end
  end
end
