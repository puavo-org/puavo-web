module Locale

  def set_preferred_language
    if self.puavoLocale && !self.puavoLocale.empty?
      self.preferredLanguage = self.puavoLocale.match(/^[a-z]{2}/)[0]
    end
  end
end
