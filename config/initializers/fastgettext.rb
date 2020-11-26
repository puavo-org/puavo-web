FastGettext.available_locales = ['en', 'fi', 'sv', 'de']    # 'en' must be first, otherwise tests can fail
FastGettext.text_domain = 'puavoweb'
FastGettext.add_text_domain('puavoweb', path: 'config/locales', type: :yaml)
