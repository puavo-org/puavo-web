# ExternalLoginError means some error occurred on our side
# ExternalLoginConfigError means external logins were badly configured
# ExternalLoginNotConfigured means external logins are not configured
#   in whatever particular case
# ExternalLoginUnavailable means an error at external service
# ExternalLoginUserMissing means user could not found at external service
# ExternalLoginWrongCredentials means user or password was invalid

class ExternalLoginError               < StandardError; end
class ExternalLoginConfigError         < ExternalLoginError; end
class ExternalLoginNotConfigured       < ExternalLoginError; end
class ExternalLoginPasswordChangeError < ExternalLoginError; end
class ExternalLoginUnavailable         < ExternalLoginError; end
class ExternalLoginPuavoUserMissing    < ExternalLoginError; end
class ExternalLoginUserMissing         < ExternalLoginError; end
class ExternalLoginWrongCredentials    < ExternalLoginError; end
